import 'package:flutter/material.dart';

import '../services/collection_sync_service.dart';
import '../services/comparajogos_service.dart';
import '../services/game_catalog.dart';
import '../services/tag_backfill_service.dart';
import '../services/wishlist_service.dart';
import '../state/collection_store.dart';
import '../theme.dart';

/// Em que pé está cada tarefa da atualização.
enum _Estado { espera, rodando, feito, pulado, erro }

class _Passo {
  _Passo(this.titulo, this.descricao);

  final String titulo;
  final String descricao;

  _Estado estado = _Estado.espera;

  /// O que aconteceu, em uma linha. É o que fica na tela no fim.
  String? resumo;

  /// Andamento, quando a tarefa sabe contar.
  int feitos = 0;
  int total = 0;
}

/// Uma passada só em tudo que o app busca de fora.
///
/// As três tarefas existiam, cada uma escondida na sua tela: capa e tema em
/// Ajustes, preço na aba Quero, coleção do Comparajogos na barra da Coleção.
/// Quem quer "deixar o app em dia" não quer decorar onde cada uma mora — quer
/// um botão. Aqui elas correm em sequência, cada uma dizendo o que fez.
///
/// Em sequência, e não em paralelo, de propósito: são três varreduras na mesma
/// API de terceiro, e disparar tudo junto seria falta de educação com quem
/// hospeda o catálogo de graça.
class AtualizarTudoSheet extends StatefulWidget {
  const AtualizarTudoSheet({
    super.key,
    required this.store,
    required this.usuarioSalvo,
    required this.onPedirUsuario,
    required this.onImportar,
  });

  final CollectionStore store;

  /// Nome de usuário no Comparajogos, se já configurado.
  final String? usuarioSalvo;

  /// Pergunta o nome de usuário. Só é chamado quando a hora chega e não há um
  /// salvo — perguntar antes travaria quem só quer as capas.
  final Future<String?> Function() onPedirUsuario;

  /// Abre a caixa que oferece os jogos que faltam aqui.
  final Future<int?> Function(CollectionDiff diff) onImportar;

  static Future<void> show(
    BuildContext context, {
    required CollectionStore store,
    required String? usuarioSalvo,
    required Future<String?> Function() onPedirUsuario,
    required Future<int?> Function(CollectionDiff diff) onImportar,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Fechar no meio deixaria varreduras rodando sem ninguém para contar o
      // resultado. O botão "Fechar" aparece quando dá.
      isDismissible: false,
      enableDrag: false,
      builder: (_) => AtualizarTudoSheet(
        store: store,
        usuarioSalvo: usuarioSalvo,
        onPedirUsuario: onPedirUsuario,
        onImportar: onImportar,
      ),
    );
  }

  @override
  State<AtualizarTudoSheet> createState() => _AtualizarTudoSheetState();
}

class _AtualizarTudoSheetState extends State<AtualizarTudoSheet> {
  late final _capas = _Passo(
    'Capas e temas que faltam',
    'Busca no catálogo, pelo nome, a imagem e o tema de quem está sem.',
  );
  late final _precos = _Passo(
    'Preços da lista de desejos',
    'Reconsulta quanto está custando hoje o que você quer comprar.',
  );
  late final _colecao = _Passo(
    'Sua coleção no Comparajogos',
    'Compara com a de lá e oferece o que ainda não está aqui.',
  );

  late final List<_Passo> _passos = [_capas, _precos, _colecao];

  bool _rodando = false;
  bool _terminou = false;

  /// O que a comparação achou, para o botão do fim abrir a caixa.
  CollectionDiff? _diff;

  TagBackfillService? _backfill;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: viz.baseline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Atualizar tudo', style: text.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Uma passada em tudo que o app busca de fora. Nada é apagado nem '
              'sobrescrito: só entra o que está faltando.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 18),

            for (final p in _passos) ...[
              _LinhaPasso(passo: p),
              const SizedBox(height: 12),
            ],

            if (_diff != null && _diff!.faltando.isNotEmpty) ...[
              const SizedBox(height: 2),
              OutlinedButton.icon(
                onPressed: _abrirImportacao,
                icon: const Icon(Icons.playlist_add, size: 18),
                label: Text(
                  'Ver ${_diff!.faltando.length} '
                  '${_diff!.faltando.length == 1 ? 'jogo que falta' : 'jogos que faltam'}',
                ),
              ),
              const SizedBox(height: 8),
            ],

            const SizedBox(height: 6),
            if (!_terminou)
              FilledButton.icon(
                onPressed: _rodando ? _parar : _rodar,
                icon: Icon(_rodando ? Icons.stop : Icons.refresh),
                label: Text(_rodando ? 'Parar' : 'Atualizar tudo'),
              ),
            TextButton(
              onPressed: _rodando ? null : () => Navigator.of(context).pop(),
              child: Text(_terminou ? 'Fechar' : 'Agora não'),
            ),
          ],
        ),
      ),
    );
  }

  void _parar() {
    _backfill?.cancel();
  }

  Future<void> _rodar() async {
    setState(() {
      _rodando = true;
      _terminou = false;
      _diff = null;
      for (final p in _passos) {
        p.estado = _Estado.espera;
        p.resumo = null;
        p.feitos = 0;
        p.total = 0;
      }
    });

    await _rodarCapas();
    await _rodarPrecos();
    await _rodarColecao();

    await widget.store.refresh();
    if (!mounted) return;
    setState(() {
      _rodando = false;
      _terminou = true;
    });
  }

  Future<void> _rodarCapas() async {
    final catalogo = ComparajogosService();
    final servico = TagBackfillService(
      catalogo: catalogo,
      repository: widget.store.repository,
    );
    _backfill = servico;

    setState(() => _capas.estado = _Estado.rodando);

    try {
      final r = await servico.run(
        onProgress: (feitos, total) {
          if (!mounted) return;
          setState(() {
            _capas.feitos = feitos;
            _capas.total = total;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _capas.estado = _Estado.feito;
        _capas.resumo = r.itens.isEmpty
            ? 'Nada faltando.'
            : '${r.capas} ${r.capas == 1 ? 'capa' : 'capas'} e '
                '${r.preenchidos} ${r.preenchidos == 1 ? 'jogo preenchido' : 'jogos preenchidos'}'
                '${r.cancelado ? ' (interrompido)' : ''}.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _capas.estado = _Estado.erro;
          _capas.resumo = '$e';
        });
      }
    } finally {
      _backfill = null;
      catalogo.dispose();
    }
  }

  Future<void> _rodarPrecos() async {
    if (widget.store.wishlist.isEmpty) {
      setState(() {
        _precos.estado = _Estado.pulado;
        _precos.resumo = 'A lista de desejos está vazia.';
      });
      return;
    }

    final servico = WishlistService(repository: widget.store.repository);
    setState(() => _precos.estado = _Estado.rodando);

    try {
      final r = await servico.atualizarPrecos();
      if (!mounted) return;
      setState(() {
        _precos.estado = _Estado.feito;
        _precos.resumo = r.novosAlertas.isEmpty
            ? '${r.consultados} consultados, ${r.baixaram} baixaram de preço.'
            : '${r.novosAlertas.length} chegaram no preço-alvo: '
                '${r.novosAlertas.map((g) => g.displayName).join(', ')}.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _precos.estado = _Estado.erro;
          _precos.resumo = '$e';
        });
      }
    } finally {
      servico.dispose();
    }
  }

  Future<void> _rodarColecao() async {
    var usuario = widget.usuarioSalvo;
    if (usuario == null || usuario.isEmpty) {
      usuario = await widget.onPedirUsuario();
    }
    if (!mounted) return;

    if (usuario == null || usuario.isEmpty) {
      setState(() {
        _colecao.estado = _Estado.pulado;
        _colecao.resumo = 'Sem o seu usuário do Comparajogos, não dá para ler '
            'as listas de lá.';
      });
      return;
    }

    final servico = CollectionSyncService(repository: widget.store.repository);
    setState(() => _colecao.estado = _Estado.rodando);

    try {
      final diff = await servico.comparar(usuario);
      if (!mounted) return;
      setState(() {
        _diff = diff;
        _colecao.estado = diff.semListas ? _Estado.pulado : _Estado.feito;
        _colecao.resumo = diff.semListas
            ? 'Não achei lista de coleção pública de "$usuario".'
            : diff.faltando.isEmpty
                ? 'Em dia: os ${diff.jaTinha} jogos de lá já estão aqui.'
                : '${diff.faltando.length} '
                    '${diff.faltando.length == 1 ? 'jogo está lá e não está aqui' : 'jogos estão lá e não estão aqui'}.';
      });
    } on CatalogException catch (e) {
      if (mounted) {
        setState(() {
          _colecao.estado = _Estado.erro;
          _colecao.resumo = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _colecao.estado = _Estado.erro;
          _colecao.resumo = '$e';
        });
      }
    } finally {
      servico.dispose();
    }
  }

  Future<void> _abrirImportacao() async {
    final diff = _diff;
    if (diff == null) return;

    final quantos = await widget.onImportar(diff);
    if (!mounted || quantos == null) return;

    setState(() {
      _diff = null;
      _colecao.resumo = '$quantos '
          '${quantos == 1 ? 'jogo adicionado' : 'jogos adicionados'}.';
    });
  }
}

class _LinhaPasso extends StatelessWidget {
  const _LinhaPasso({required this.passo});

  final _Passo passo;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: switch (passo.estado) {
            _Estado.rodando => const CircularProgressIndicator(strokeWidth: 2),
            _Estado.feito => Icon(Icons.check_circle, size: 20, color: viz.good),
            _Estado.pulado =>
              Icon(Icons.remove_circle_outline, size: 20, color: viz.inkMuted),
            _Estado.erro =>
              Icon(Icons.error_outline, size: 20, color: viz.critical),
            _Estado.espera =>
              Icon(Icons.circle_outlined, size: 20, color: viz.inkMuted),
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(passo.titulo, style: text.bodyMedium),
              const SizedBox(height: 2),
              Text(
                passo.resumo ?? passo.descricao,
                style: text.labelSmall?.copyWith(
                  color: passo.estado == _Estado.erro
                      ? viz.critical
                      : passo.resumo != null
                          ? viz.inkSecondary
                          : viz.inkMuted,
                ),
              ),
              if (passo.estado == _Estado.rodando && passo.total > 0) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: passo.feitos / passo.total,
                  minHeight: 3,
                ),
                const SizedBox(height: 3),
                Text(
                  '${passo.feitos} de ${passo.total}',
                  style: text.labelSmall?.copyWith(color: viz.inkMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
