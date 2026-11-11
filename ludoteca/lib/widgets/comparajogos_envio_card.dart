import 'package:flutter/material.dart';

import '../screens/comparajogos_login_screen.dart';
import '../services/comparajogos_login.dart';
import '../services/comparajogos_partidas.dart';
import '../services/sincronizador_partidas.dart';
import '../state/collection_store.dart';
import '../theme.dart';

/// Cartão de Ajustes: entrar no Comparajogos para as partidas irem para lá.
class ComparajogosEnvioCard extends StatefulWidget {
  const ComparajogosEnvioCard({super.key, required this.store});

  final CollectionStore store;

  @override
  State<ComparajogosEnvioCard> createState() => _ComparajogosEnvioCardState();
}

class _ComparajogosEnvioCardState extends State<ComparajogosEnvioCard> {
  bool _enviando = false;

  Future<void> _entrar() async {
    final conta = await Navigator.of(context).push<ContaComparajogos>(
      MaterialPageRoute(builder: (_) => const ComparajogosLoginScreen()),
    );
    if (conta == null || !mounted) return;
    await widget.store.entrarNoComparajogos(conta);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Pronto: as próximas partidas vão para '
        '@${widget.store.contaEnvioComparajogos}.',
      ),
    ));
  }

  Future<void> _sair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair do Comparajogos?'),
        content: const Text(
          'As partidas param de ir para lá. O que já foi continua lá, e o '
          'que estava na fila fica guardado para quando você entrar de novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ComparajogosWeb.sair();
    } catch (_) {}
    await widget.store.sairDoComparajogos();
  }

  Future<void> _enviar(Future<void> Function() acao) async {
    setState(() => _enviando = true);
    try {
      await acao();
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _verErros() async {
    final erros = await widget.store.repository.errosDeEnvio();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Não foram para o Comparajogos'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in erros)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${e.jogo} · ${e.data}'),
                  subtitle: Text(e.motivo),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final store = widget.store;
    final conta = store.contaEnvioComparajogos;
    final sit = store.situacaoEnvio;
    final RodadaDeEnvio? rodada = store.ultimaRodadaDeEnvio;
    final expirou = conta != null && rodada?.semLogin == true;

    final String estado;
    final Color corEstado;
    final IconData icone;
    if (conta == null) {
      estado = 'desligado';
      corEstado = viz.inkSecondary;
      icone = Icons.cloud_off_outlined;
    } else if (expirou) {
      estado = 'entre de novo';
      corEstado = viz.warning;
      icone = Icons.error_outline;
    } else {
      estado = '@$conta';
      corEstado = viz.good;
      icone = Icons.check_circle;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Partidas no Comparajogos',
                      style: text.titleMedium),
                ),
                Icon(icone, size: 18, color: corEstado),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    estado,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(color: corEstado),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              conta == null
                  ? 'Entre na sua conta e cada partida registrada aqui também '
                      'fica registrada no Comparajogos, com placar, vencedor, '
                      'duração e expansão. As partidas antigas não vão, só as '
                      'de agora em diante.\n\n'
                      'O login é feito na página do próprio Comparajogos, e o '
                      'app não vê a sua senha. Sem rede, a partida fica salva '
                      'aqui e vai depois, sozinha.'
                  : 'Cada partida registrada, editada ou apagada aqui vai para '
                      'a sua conta lá. O que não foi por falta de rede vai na '
                      'próxima vez que o app abrir.',
              style: text.bodySmall,
            ),
            if (conta != null) ...[
              const SizedBox(height: 12),
              if (expirou)
                _Aviso(
                  icone: Icons.error_outline,
                  cor: viz.warning,
                  texto: 'A sessão do Comparajogos expirou. Entre de novo '
                      'para mandar o que está na fila.',
                )
              else if (rodada?.erro != null && sit.pendentes > 0)
                _Aviso(
                  icone: Icons.wifi_off,
                  cor: viz.warning,
                  texto: 'Ainda não foi: ${rodada!.erro}',
                ),
              _Contagem(rotulo: 'Na fila para enviar', valor: sit.pendentes),
              if (sit.comErro > 0)
                _Contagem(rotulo: 'Não foram', valor: sit.comErro),
            ],
            const SizedBox(height: 14),
            if (conta == null || expirou)
              FilledButton.icon(
                onPressed: _entrar,
                icon: const Icon(Icons.login),
                label: const Text('Entrar no Comparajogos'),
              ),
            if (conta != null) ...[
              if (sit.pendentes > 0 && !expirou)
                FilledButton.icon(
                  onPressed: _enviando
                      ? null
                      : () => _enviar(() async {
                            await store.enviarPendentes();
                          }),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(_enviando ? 'Enviando…' : 'Enviar agora'),
                ),
              if (sit.comErro > 0) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _verErros,
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Ver o que não foi'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _enviando
                      ? null
                      : () => _enviar(store.tentarDeNovoOsEnviosComErro),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar de novo'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: _sair,
                child: const Text('Sair da conta'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.cor, required this.texto});

  final IconData icone;
  final Color cor;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 15, color: cor),
          const SizedBox(width: 7),
          Expanded(
            child: Text(texto, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _Contagem extends StatelessWidget {
  const _Contagem({required this.rotulo, required this.valor});

  final String rotulo;
  final int valor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(rotulo, style: text.bodyMedium)),
          Text(
            '$valor',
            style: text.bodyMedium?.copyWith(
              color: context.viz.inkPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
