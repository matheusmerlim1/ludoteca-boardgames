import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/game_repository.dart';
import '../models/game.dart';
import '../services/wishlist_service.dart';
import '../state/collection_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/game_cover.dart';
import 'game_detail_screen.dart';

/// Lista de desejos, com o preço de hoje e o alvo que você definiu.
class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  bool _ocupado = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CollectionStore>();
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    final desejos = store.wishlist;
    final alertas = store.wishlistAlerts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quero comprar'),
        actions: [
          IconButton(
            onPressed: _ocupado ? null : _atualizarPrecos,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar preços',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          if (_ocupado) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          if (_status != null) ...[
            Text(_status!, style: text.bodySmall),
            const SizedBox(height: 12),
          ],

          if (alertas > 0) ...[
            Card(
              color: viz.serie(0).withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active, color: viz.serie(0)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        alertas == 1
                            ? '1 jogo chegou no preço que você queria.'
                            : '$alertas jogos chegaram no preço que você queria.',
                        style: text.bodyMedium?.copyWith(
                          color: viz.inkPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (desejos.isEmpty)
            _Vazio(onSincronizar: _sincronizar)
          else
            for (final e in desejos) ...[
              _Linha(
                entry: e,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GameDetailScreen(gameId: e.id),
                  ),
                ),
                onAlvo: () => _definirAlvo(e.game),
              ),
              Divider(height: 1, color: viz.gridline),
            ],

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _ocupado ? null : _sincronizar,
            icon: const Icon(Icons.sync),
            label: const Text('Sincronizar com o Comparajogos'),
          ),
        ],
      ),
    );
  }

  Future<void> _sincronizar() async {
    final store = context.read<CollectionStore>();
    final usuario =
        await store.repository.getSetting(GameRepository.keyComparajogosUser);

    if (!mounted) return;

    if (usuario == null || usuario.isEmpty) {
      final digitado = await _pedeUsuario();
      if (digitado == null || !mounted) return;
      await store.repository
          .setSetting(GameRepository.keyComparajogosUser, digitado);
      return _sincronizarCom(digitado);
    }

    return _sincronizarCom(usuario);
  }

  Future<void> _sincronizarCom(String usuario) async {
    setState(() {
      _ocupado = true;
      _status = 'Lendo as listas públicas de $usuario...';
    });

    final store = context.read<CollectionStore>();
    final servico = WishlistService(repository: store.repository);

    try {
      final r = await servico.sincronizar(usuario);
      await store.refresh();
      if (!mounted) return;

      setState(() {
        _status = r.vazio
            ? 'Não achei lista pública de "$usuario". Confira o nome de '
                'usuário e se a lista está marcada como pública lá.'
            : '${r.adicionados} adicionados, ${r.atualizados} atualizados '
                'de ${r.nomesDasListas.join(', ')}.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Falhou: $e');
    } finally {
      servico.dispose();
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _atualizarPrecos() async {
    final store = context.read<CollectionStore>();
    if (store.wishlist.isEmpty) {
      setState(() => _status = 'Nada na lista para consultar.');
      return;
    }

    setState(() {
      _ocupado = true;
      _status = 'Consultando preços...';
    });

    final servico = WishlistService(repository: store.repository);
    try {
      final r = await servico.atualizarPrecos();
      await store.refresh();
      if (!mounted) return;

      setState(() {
        _status = r.novosAlertas.isEmpty
            ? '${r.consultados} consultados, ${r.baixaram} baixaram de preço.'
            : '${r.novosAlertas.length} chegaram no alvo: '
                '${r.novosAlertas.map((g) => g.displayName).join(', ')}.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Falhou: $e');
    } finally {
      servico.dispose();
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<String?> _pedeUsuario() {
    // Pré-preenchido: o usuário já disse qual é, e digitar de novo num teclado
    // de celular é atrito à toa.
    final controller = TextEditingController(text: 'matheusmerlim');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seu usuário no Comparajogos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'O app lê apenas as suas listas marcadas como públicas lá. '
              'Não existe login na API deles, então nenhuma senha é pedida '
              'nem guardada.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Nome de usuário',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );
  }

  Future<void> _definirAlvo(Game game) async {
    final controller = TextEditingController(
      text: moedaParaCampo(game.targetPrice ?? 0),
    );

    final valor = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Preço-alvo de ${game.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (game.lastPrice != null)
              Text(
                'Hoje está ${dinheiro(game.lastPrice!)}.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Me avise quando chegar em',
                prefixText: 'R\$ ',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          if (game.targetPrice != null)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(0),
              child: const Text('Tirar o alvo'),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(parseMoeda(controller.text) ?? 0),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (valor == null || !mounted) return;

    final store = context.read<CollectionStore>();
    // Zero significa "sem alvo": um alvo de R$ 0 nunca seria atingido e
    // deixaria o jogo num limbo de alerta que nunca dispara.
    await store.saveGame(
      valor <= 0
          ? game.copyWith(clearTargetPrice: true)
          : game.copyWith(targetPrice: valor),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({
    required this.entry,
    required this.onTap,
    required this.onAlvo,
  });

  final GameEntry entry;
  final VoidCallback onTap;
  final VoidCallback onAlvo;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final game = entry.game;
    final noAlvo = game.priceReached;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              height: 60,
              child: GameCover(
                url: game.thumbUrl ?? game.imageUrl,
                name: game.displayName,
                borderRadius: 8,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (noAlvo) ...[
                        Icon(Icons.notifications_active,
                            size: 15, color: viz.serie(0)),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          game.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: viz.inkPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    game.lastPrice == null
                        ? 'sem preço no catálogo'
                        : 'hoje ${dinheiro(game.lastPrice!)}'
                            '${game.lastPriceAt == null ? '' : ' · visto ${desdeQuando(game.lastPriceAt)}'}',
                    style: text.bodySmall?.copyWith(
                      color: noAlvo ? viz.good : viz.inkSecondary,
                      fontWeight: noAlvo ? FontWeight.w600 : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: onAlvo,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        game.targetPrice == null
                            ? 'definir preço-alvo'
                            : 'alvo ${dinheiro(game.targetPrice!)}',
                        style: text.labelSmall?.copyWith(
                          color: viz.serie(0),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio({required this.onSincronizar});

  final VoidCallback onSincronizar;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.favorite_border, size: 44, color: viz.inkMuted),
          const SizedBox(height: 16),
          Text('Nada na lista ainda', style: text.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Você pode marcar um jogo como "quero comprar" ao cadastrá-lo, '
            'ou puxar a sua lista pública do Comparajogos.',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
