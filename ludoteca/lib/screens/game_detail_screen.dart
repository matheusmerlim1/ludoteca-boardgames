import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game.dart';
import '../models/play.dart';
import '../models/play_score.dart';
import '../services/comparajogos_service.dart';
import '../services/game_catalog.dart';
import '../state/collection_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/disposal_sheet.dart';
import '../widgets/expansion_picker_sheet.dart';
import '../widgets/game_cover.dart';
import '../widgets/log_play_sheet.dart';
import 'game_form_screen.dart';

class GameDetailScreen extends StatefulWidget {
  const GameDetailScreen({super.key, required this.gameId});

  final int gameId;

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  List<Play> _plays = const [];

  /// Placar de cada partida, por id. Vem numa consulta só para o histórico não
  /// disparar uma ida ao banco por linha.
  Map<int, List<PlayScore>> _placares = const {};

  bool _loadingPlays = true;
  bool _buscandoItens = false;

  @override
  void initState() {
    super.initState();
    _carregarPartidas();
  }

  Future<void> _carregarPartidas() async {
    final store = context.read<CollectionStore>();
    final lista = await store.playsFor(widget.gameId);
    final placares = await store.scoresForPlays(
      lista.map((p) => p.id!).toList(),
    );
    if (!mounted) return;
    setState(() {
      _plays = lista;
      _placares = placares;
      _loadingPlays = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CollectionStore>();
    final entry = store.entryById(widget.gameId);

    // O jogo pode ter sido removido enquanto a tela estava aberta.
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Este jogo não está mais na coleção.')),
      );
    }

    final game = entry.game;
    final viz = context.viz;
    final expansoes = store.expansionsOf(widget.gameId);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: viz.page,
            flexibleSpace: FlexibleSpaceBar(
              background: _CoverHeader(game: game),
            ),
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editar(game),
              ),
              _MoreMenu(
                game: game,
                onSaida: () => _registrarSaida(game),
                onRemover: () => _remover(game),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _Titulo(game: game),
                const SizedBox(height: 18),
                _FichaTecnica(game: game),
                const SizedBox(height: 20),
                _BlocoPartidas(
                  entry: entry,
                  onRegistrar: () => _registrarPartida(game),
                ),
                const SizedBox(height: 20),
                _BlocoCustos(
                  entry: entry,
                  trocadoPor: game.tradedForId == null
                      ? null
                      : store.entryById(game.tradedForId!)?.displayName,
                ),
                const SizedBox(height: 20),
                _BlocoExpansoes(
                  expansoes: expansoes,
                  plays: _plays,
                  buscando: _buscandoItens,
                  onAdicionar: () => _adicionarItens(game),
                ),
                const SizedBox(height: 20),
                _Historico(
                  plays: _plays,
                  placares: _placares,
                  loading: _loadingPlays,
                  manualCount: game.manualPlayCount,
                  manualLast: game.manualLastPlayed,
                  onEditar: (p) => _editarPartida(game, p),
                  onRemover: _removerPartida,
                ),
                if (game.notes != null && game.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _Secao(
                    titulo: 'Anotações',
                    child: Text(
                      game.notes!.trim(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- ações

  Future<void> _registrarPartida(Game game) async {
    final sugestoes = await context.read<CollectionStore>().playerNames();
    if (!mounted) return;

    final r = await LogPlaySheet.show(
      context,
      game: game,
      itens: context
          .read<CollectionStore>()
          .expansionsOf(widget.gameId)
          .map((e) => e.game)
          .toList(),
      sugestoesDeNome: sugestoes,
    );
    if (r == null || !mounted) return;

    await context.read<CollectionStore>().logPlay(r.play, placar: r.placar);
    if (!mounted) return;

    // Volta para a coleção: registrar partida é o fim da tarefa, e ficar na
    // ficha faria você tocar em "voltar" toda vez. O aviso aparece já na lista,
    // que é para onde você estava indo de qualquer jeito.
    Navigator.of(context).pop();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Partida de ${data(r.play.playedAt)} registrada.')),
    );
  }

  Future<void> _editarPartida(Game game, Play play) async {
    final store = context.read<CollectionStore>();
    final sugestoes = await store.playerNames();
    if (!mounted) return;

    final r = await LogPlaySheet.show(
      context,
      game: game,
      existing: play,
      placarInicial: _placares[play.id] ?? const [],
      sugestoesDeNome: sugestoes,
      itens: store.expansionsOf(widget.gameId).map((e) => e.game).toList(),
    );
    if (r == null || !mounted) return;

    await store.updatePlay(r.play, placar: r.placar);
    await _carregarPartidas();
  }

  Future<void> _removerPartida(Play play) async {
    await context.read<CollectionStore>().deletePlay(play.id!);
    await _carregarPartidas();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Partida removida.')),
    );
  }

  /// Busca no catálogo os itens ligados a este jogo e deixa você escolher.
  ///
  /// Existe porque expansão quase nunca chega junto com o jogo — você compra a
  /// caixa base, joga uns meses, e só depois pega um pacote. Sem isto, a única
  /// forma de vincular seria editar o item novo e apontar o pai à mão.
  ///
  /// Serve também para agrupar séries como Unmatched, em que cada caixa é um
  /// jogo completo mas você quer uma linha só na estante.
  Future<void> _adicionarItens(Game game) async {
    setState(() => _buscandoItens = true);

    final store = context.read<CollectionStore>();
    final catalogo = ComparajogosService();

    try {
      // Pelo id do catálogo quando o jogo veio de lá; senão pelo nome.
      CatalogGameDetails? ficha;
      if (game.bggId != null) {
        final achados = await catalogo.search(game.name, comCapas: false);
        final igual = achados.where((r) => r.name == game.name).firstOrNull;
        if (igual != null) ficha = await catalogo.details(igual.id);
      }
      ficha ??= await _porNome(catalogo, game);

      if (!mounted) return;

      if (ficha == null) {
        _aviso('Não achei "${game.name}" no catálogo para listar as expansões.');
        return;
      }
      if (ficha.expansions.isEmpty) {
        _aviso('O catálogo não conhece expansões de ${game.displayName}.');
        return;
      }

      // Já cadastradas não aparecem de novo na lista.
      final jaTenho = store.allEntries
          .map((e) => normalizaNome(e.game.name))
          .toSet();
      final novos = ficha.expansions
          .where((e) => !jaTenho.contains(normalizaNome(e.name)))
          .toList();

      if (novos.isEmpty) {
        _aviso('Você já cadastrou todas as expansões que o catálogo conhece.');
        return;
      }

      if (!mounted) return;
      final escolha = await ExpansionPickerSheet.show(
        context,
        gameName: game.displayName,
        expansions: novos,
      );
      if (escolha == null || escolha.itens.isEmpty || !mounted) return;

      var inseridos = 0;
      for (var i = 0; i < escolha.itens.length; i += 20) {
        final lote = escolha.itens.skip(i).take(20).map((e) => e.id).toList();
        for (final f in await catalogo.detailsBatch(lote)) {
          final novoId = await store.repository.insertGame(Game(
            bggId: f.bggId,
            name: f.name,
            year: f.year,
            minPlayers: f.minPlayers,
            maxPlayers: f.maxPlayers,
            bestPlayers: f.bestPlayers,
            minPlaytime: f.minPlaytime,
            maxPlaytime: f.maxPlaytime,
            weight: f.weight,
            imageUrl: f.imageUrl,
            thumbUrl: f.thumbUrl,
            linkKind: escolha.tipo,
            parentId: widget.gameId,
          ));
          if (f.tags.isNotEmpty) {
            await store.repository.setGameTags(novoId, f.tags);
          }
          inseridos++;
        }
      }

      await store.refresh();
      if (!mounted) return;
      _aviso('$inseridos ${escolha.tipo.contar(inseridos)} '
          '${inseridos == 1 ? 'adicionada' : 'adicionadas'}.');
    } on CatalogException catch (e) {
      if (mounted) _aviso(e.message);
    } finally {
      catalogo.dispose();
      if (mounted) setState(() => _buscandoItens = false);
    }
  }

  Future<CatalogGameDetails?> _porNome(
    ComparajogosService catalogo,
    Game game,
  ) async {
    final achados = await catalogo.search(game.name, comCapas: false);
    if (achados.isEmpty) return null;
    return catalogo.details(achados.first.id);
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _editar(Game game) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GameFormScreen(existing: game)),
    );
  }

  /// Tirar o jogo da estante — ou trazer de volta.
  ///
  /// O jogo não é apagado: o histórico de partidas e o que você gastou nele
  /// continuam valendo para as estatísticas. O que muda é só a contagem do
  /// dinheiro, e cada saída mexe nela de um jeito (ver [DisposalSheet]).
  Future<void> _registrarSaida(Game game) async {
    final store = context.read<CollectionStore>();

    if (game.isGone) {
      await store.desfazerSaida(game);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jogo de volta para a estante.')),
      );
      return;
    }

    // Candidatos à troca: o que já está na estante, menos ele mesmo e menos
    // o que também já saiu.
    final candidatos = store.allEntries
        .where((e) =>
            e.game.id != game.id && !e.game.isGone && !e.game.isWishlist)
        .toList();

    final r = await DisposalSheet.show(
      context,
      game: game,
      candidatos: candidatos,
    );
    if (r == null || !mounted) return;

    await store.registrarSaida(
      jogo: game,
      tipo: r.tipo,
      valorRecebido: r.valor,
      quando: r.quando,
      trocadoPorId: r.trocadoPorId,
    );

    if (!mounted) return;

    final recebido = r.trocadoPorId == null
        ? null
        : store.entryById(r.trocadoPorId!)?.displayName;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (r.tipo) {
          Disposal.vendido =>
            'Vendido por ${dinheiro(r.valor ?? 0)} — abatido dos custos.',
          Disposal.trocado when recebido != null =>
            '${dinheiro(game.totalInvested)} passaram para $recebido.',
          Disposal.trocado => 'Marcado como trocado.',
          Disposal.doado => 'Marcado como doado.',
        }),
      ),
    );
  }

  Future<void> _remover(Game game) async {
    final temExpansoes =
        context.read<CollectionStore>().expansionsOf(widget.gameId).isNotEmpty;

    final escolha = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tirar ${game.displayName}?'),
        content: Text(
          [
            'Se o jogo saiu da coleção — vendido, trocado ou doado — o certo '
                'é marcar a saída: as partidas que você jogou e o que gastou '
                'nele continuam contando na sua história.',
            'Apagar joga tudo fora: o jogo e o histórico de partidas dele.',
            if (temExpansoes)
              'As expansões cadastradas continuam na coleção, mas ficam sem '
                  'jogo-base.',
            'Apagar não tem como desfazer — mas um backup em Ajustes resolve.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          if (!game.isGone)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('saida'),
              child: const Text('Saiu da coleção'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop('apagar'),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (escolha == null || !mounted) return;

    if (escolha == 'saida') {
      await _registrarSaida(game);
      return;
    }

    await context.read<CollectionStore>().deleteGame(widget.gameId);
    if (!mounted) return;

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${game.displayName} removido.')),
    );
  }
}

// ---------------------------------------------------------------- cabeçalho

class _CoverHeader extends StatelessWidget {
  const _CoverHeader({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: viz.gridline),
        GameCover(
          url: game.imageUrl ?? game.thumbUrl,
          name: game.displayName,
          borderRadius: 0,
          fit: BoxFit.cover,
        ),
        // Véu na base para os controles da barra continuarem legíveis sobre
        // qualquer capa.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.35),
                Colors.transparent,
                viz.page.withValues(alpha: 0.85),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          game.displayName,
          style: text.headlineSmall?.copyWith(fontSize: 24),
        ),
        if (game.subtitleName != null) ...[
          const SizedBox(height: 3),
          Text(game.subtitleName!, style: text.bodySmall),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (game.year != null)
              Text('${game.year}', style: text.labelSmall),
            if (game.linkLabel != null)
              Text(game.linkLabel!, style: text.labelSmall),
            if (game.bggId != null)
              Text('BGG #${game.bggId}',
                  style: text.labelSmall?.copyWith(color: viz.inkMuted)),
          ],
        ),
      ],
    );
  }
}

/// Jogadores, duração, peso, "melhor com".
class _FichaTecnica extends StatelessWidget {
  const _FichaTecnica({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            _Celula(
              icone: Icons.group_outlined,
              valor: faixaJogadores(game.minPlayers, game.maxPlayers)
                  .replaceAll(' jogadores', '')
                  .replaceAll(' jogador', ''),
              legenda: game.bestPlayers != null
                  ? 'melhor com ${game.bestPlayers}'
                  : 'jogadores',
            ),
            _Divisor(color: viz.gridline),
            _Celula(
              icone: Icons.schedule,
              valor: faixaDuracao(game.minPlaytime, game.maxPlaytime)
                  .replaceAll(' min', ''),
              legenda: 'minutos',
            ),
            _Divisor(color: viz.gridline),
            _Celula(
              icone: Icons.fitness_center,
              valor: peso(game.weight),
              legenda: 'peso (1–5)',
            ),
          ],
        ),
      ),
    );
  }
}

class _Celula extends StatelessWidget {
  const _Celula({
    required this.icone,
    required this.valor,
    required this.legenda,
  });

  final IconData icone;
  final String valor;
  final String legenda;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Expanded(
      child: Column(
        children: [
          Icon(icone, size: 17, color: viz.inkMuted),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valor,
              style: text.titleMedium?.copyWith(fontSize: 17),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            legenda,
            textAlign: TextAlign.center,
            style: text.labelSmall?.copyWith(color: viz.inkMuted, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _Divisor extends StatelessWidget {
  const _Divisor({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 42, color: color);
}

// ------------------------------------------------------------------ partidas

class _BlocoPartidas extends StatelessWidget {
  const _BlocoPartidas({required this.entry, required this.onRegistrar});

  final GameEntry entry;
  final VoidCallback onRegistrar;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${entry.playCount}',
                          style: text.headlineSmall?.copyWith(fontSize: 30)),
                      Text(
                        entry.playCount == 1 ? 'partida' : 'partidas',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        desdeQuando(entry.lastPlayed),
                        style: text.titleMedium?.copyWith(fontSize: 17),
                      ),
                      Text(
                        entry.lastPlayed == null
                            ? 'ainda não foi à mesa'
                            : 'última vez · ${data(entry.lastPlayed!)}',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRegistrar,
              icon: const Icon(Icons.add),
              label: const Text('Registrar partida'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Historico extends StatelessWidget {
  const _Historico({
    required this.plays,
    required this.placares,
    required this.loading,
    required this.manualCount,
    required this.manualLast,
    required this.onEditar,
    required this.onRemover,
  });

  final List<Play> plays;
  final Map<int, List<PlayScore>> placares;
  final bool loading;
  final int manualCount;
  final DateTime? manualLast;
  final void Function(Play) onEditar;
  final Future<void> Function(Play) onRemover;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    return _Secao(
      titulo: 'Histórico',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (plays.isEmpty && manualCount == 0)
            Text('Nenhuma partida registrada.', style: text.bodySmall)
          else ...[
            for (final p in plays)
              Dismissible(
                key: ValueKey('play-${p.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 18),
                  color: viz.critical.withValues(alpha: 0.14),
                  child: Icon(Icons.delete_outline, color: viz.critical),
                ),
                onDismissed: (_) => onRemover(p),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onTap: () => onEditar(p),
                  title: Text(data(p.playedAt)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_linha(p, placares[p.id] ?? const [])),
                      if ((placares[p.id] ?? const []).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _Placar(linhas: placares[p.id]!),
                        ),
                    ],
                  ),
                ),
              ),
            // O que veio da planilha aparece como uma linha só, sem fingir
            // que são partidas com data.
            if (manualCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.table_chart_outlined,
                        size: 15, color: viz.inkMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '+ $manualCount ${manualCount == 1 ? 'partida' : 'partidas'} '
                        'do histórico antigo'
                        '${manualLast == null ? '' : ' · última em ${data(manualLast!)}'}',
                        style: text.labelSmall?.copyWith(color: viz.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _linha(Play p, List<PlayScore> placar) {
    // Com placar na tela, a coroa já diz quem ganhou: repetir "ganhou: Ana"
    // na linha de cima seria a mesma informação duas vezes.
    final temPlacar = placar.isNotEmpty;

    final partes = <String>[
      // Com placar, o número de jogadores é o tamanho da lista — e essa é a
      // contagem certa, mesmo que o campo tenha ficado em branco.
      if (temPlacar)
        '${placar.length} jogadores'
      else if (p.players != null)
        '${p.players} jogadores',
      // Só aparece quando foi cronometrada — partida sem duração não ganha um
      // "(média)" poluindo cada linha do histórico.
      if (p.hasMeasuredDuration) duracao(p.durationMinutes!),
      if (!temPlacar && p.winner != null && p.winner!.isNotEmpty)
        'ganhou: ${p.winner}',
      if (p.notes != null && p.notes!.isNotEmpty) p.notes!,
    ];
    return partes.isEmpty ? 'sem detalhes' : partes.join(' · ');
  }
}

/// O placar de uma partida: quem jogou, quanto fez e quem levou.
///
/// Ordenado por pontos, com quem não anotou pontuação no fim — assim a linha
/// de cima é sempre a que interessa, e jogo sem contagem não vira lista solta.
class _Placar extends StatelessWidget {
  const _Placar({required this.linhas});

  final List<PlayScore> linhas;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    final ordenadas = [...linhas]..sort((a, b) {
        if (a.won != b.won) return a.won ? -1 : 1;
        if (a.score == null && b.score == null) return 0;
        if (a.score == null) return 1;
        if (b.score == null) return -1;
        return b.score!.compareTo(a.score!);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in ordenadas)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Icon(
                  s.won ? Icons.emoji_events : Icons.circle,
                  size: s.won ? 13 : 5,
                  color: s.won ? viz.serie(3) : viz.inkMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.playerName,
                    style: s.won
                        ? text.bodySmall?.copyWith(
                            color: viz.inkPrimary,
                            fontWeight: FontWeight.w600,
                          )
                        : text.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (s.score != null)
                  Text(
                    pontos(s.score!),
                    // Coluna de números: alinhados, para comparar de relance.
                    style: text.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: viz.inkPrimary,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// -------------------------------------------------------------------- custos

class _BlocoCustos extends StatelessWidget {
  const _BlocoCustos({required this.entry, this.trocadoPor});

  final GameEntry entry;

  /// Nome do jogo que entrou na troca, quando este saiu por troca.
  final String? trocadoPor;

  @override
  Widget build(BuildContext context) {
    final game = entry.game;
    final viz = context.viz;

    return _Secao(
      titulo: 'Custos',
      child: Column(
        children: [
          _LinhaValor(rotulo: 'Caixa do jogo', valor: dinheiro(game.price)),
          if (game.sleeveCost > 0)
            _LinhaValor(rotulo: 'Sleeves', valor: dinheiro(game.sleeveCost)),
          if (game.accessoryCost > 0)
            _LinhaValor(
              rotulo: 'Acessórios',
              valor: dinheiro(game.accessoryCost),
            ),
          if (entry.expansionCost > 0)
            _LinhaValor(
              rotulo: '${entry.expansionCount} '
                  '${entry.expansionCount == 1 ? 'expansão' : 'expansões'}',
              valor: dinheiro(entry.expansionCost),
            ),
          Divider(color: viz.gridline, height: 20),
          _LinhaValor(
            rotulo: 'Total investido',
            valor: dinheiro(entry.totalInvested),
            destaque: true,
          ),
          // Cada saída fecha a conta de um jeito diferente, e a linha final
          // precisa dizer qual foi — "saldo" sem contexto esconde se o
          // dinheiro voltou, virou outro jogo ou simplesmente foi embora.
          if (game.disposal == Disposal.vendido || game.sold) ...[
            _LinhaValor(
              rotulo: 'Vendido por',
              valor: '− ${dinheiro(game.soldPrice ?? 0)}',
            ),
            _LinhaValor(
              rotulo: 'Saldo final',
              valor: dinheiro(entry.totalInvested - (game.soldPrice ?? 0)),
              destaque: true,
            ),
          ] else if (game.disposal == Disposal.trocado)
            _LinhaValor(
              rotulo: 'Trocado',
              valor: trocadoPor == null
                  ? 'valor transferido'
                  : 'virou $trocadoPor',
            )
          else if (game.disposal == Disposal.doado)
            const _LinhaValor(rotulo: 'Doado', valor: 'sem retorno'),
          Divider(color: viz.gridline, height: 20),
          _LinhaValor(
            rotulo: 'Horas de mesa',
            valor: entry.totalHours == null
                ? '—'
                : talvez(
                    horas(entry.totalHours!),
                    estimado: entry.hoursAreEstimated,
                  ),
            nota: _notaHoras(entry),
          ),
          _LinhaValor(
            rotulo: 'Custo por hora',
            valor: entry.costPerHour == null
                ? '—'
                : talvez(
                    dinheiro(entry.costPerHour!),
                    estimado: entry.hoursAreEstimated,
                  ),
            nota: entry.costPerHour == null
                ? 'precisa de partidas e de duração cadastrada'
                : null,
          ),
          _LinhaValor(
            rotulo: 'Custo por partida',
            valor: entry.costPerPlay == null
                ? '—'
                : dinheiro(entry.costPerPlay!),
            nota: entry.costPerPlay == null
                ? 'precisa de pelo menos uma partida'
                : contagemPartidas(entry.playCount),
          ),
          _LinhaValor(
            rotulo: 'Custo de posse por mês',
            valor: entry.costPerMonth == null
                ? '—'
                : dinheiro(entry.costPerMonth!),
            nota: game.purchaseDate == null
                ? 'precisa da data de compra'
                : '${entry.monthsOwned} '
                    '${entry.monthsOwned == 1 ? 'mês' : 'meses'} de posse '
                    '· desde ${data(game.purchaseDate!)}',
          ),
        ],
      ),
    );
  }
}

/// De onde vêm as horas deste jogo: quanto foi cronometrado, quanto foi
/// estimado pela média. Sem isso o "≈" fica sem explicação.
String? _notaHoras(GameEntry entry) {
  final medio = entry.game.averagePlaytime;

  // Só acontece quando não há média nem partida cronometrada.
  if (entry.totalMinutes == null) {
    return 'cadastre a duração do jogo para contar horas';
  }

  if (entry.playCount == 0) return 'nenhuma partida ainda';

  final medidas = entry.loggedPlaysWithDuration;
  final estimadas = entry.estimatedPlays;

  if (medidas == 0) {
    return '$estimadas × ${duracao(medio!)}, a duração média do jogo';
  }

  if (estimadas == 0) {
    return 'tudo cronometrado · '
        '${duracao(entry.measuredAverageMinutes!.round())} por partida';
  }

  return '$medidas cronometrada${medidas == 1 ? '' : 's'} '
      '+ $estimadas pela média de ${duracao(medio!)}';
}

class _LinhaValor extends StatelessWidget {
  const _LinhaValor({
    required this.rotulo,
    required this.valor,
    this.nota,
    this.destaque = false,
  });

  final String rotulo;
  final String valor;
  final String? nota;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotulo,
                  style: text.bodyMedium?.copyWith(
                    color: viz.inkPrimary,
                    fontWeight: destaque ? FontWeight.w600 : null,
                  ),
                ),
                if (nota != null)
                  Text(nota!, style: text.labelSmall?.copyWith(color: viz.inkMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            valor,
            style: text.bodyMedium?.copyWith(
              color: viz.inkPrimary,
              fontWeight: destaque ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlocoExpansoes extends StatelessWidget {
  const _BlocoExpansoes({
    required this.expansoes,
    required this.plays,
    required this.buscando,
    required this.onAdicionar,
  });

  final List<GameEntry> expansoes;

  /// Partidas do grupo, para contar quantas foram de cada caixa.
  final List<Play> plays;

  final bool buscando;
  final VoidCallback onAdicionar;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    // Quantas partidas do grupo foram marcadas com cada caixa.
    final porItem = <int, int>{};
    for (final p in plays) {
      final id = p.itemGameId;
      if (id != null) porItem[id] = (porItem[id] ?? 0) + 1;
    }

    // Todas do mesmo tipo é o caso normal; misturado cai no genérico.
    final tipos = expansoes.map((e) => e.game.linkKind).toSet();
    final rotulo = tipos.length == 1 && tipos.first != null
        ? tipos.first!.contar(expansoes.length)
        : (expansoes.length == 1 ? 'item' : 'itens');

    return _Secao(
      titulo: expansoes.isEmpty
          ? 'Expansões e caixas'
          : '${expansoes.length} $rotulo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (expansoes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Nada vinculado ainda. Use o botão abaixo quando comprar uma '
                'expansão, ou para juntar as caixas de uma série como o '
                'Unmatched num jogo só.',
                style: text.bodySmall,
              ),
            ),
          for (final e in expansoes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: SizedBox(
                width: 34,
                height: 44,
                child: GameCover(
                  url: e.game.thumbUrl,
                  name: e.game.displayName,
                  borderRadius: 5,
                ),
              ),
              title: Text(e.game.displayName),
              subtitle: Text(
                [
                  dinheiro(e.game.totalInvested),
                  if ((porItem[e.id] ?? 0) > 0)
                    contagemPartidas(porItem[e.id]!),
                ].join(' · '),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GameDetailScreen(gameId: e.id),
                ),
              ),
            ),
          if (plays.any((p) => p.itemGameId != null))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'A contagem por caixa vem das partidas em que você marcou qual '
                'jogou. As demais contam para o grupo.',
                style: text.labelSmall?.copyWith(color: viz.inkMuted),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: buscando ? null : onAdicionar,
            icon: buscando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 18),
            label: Text(
              buscando ? 'Buscando no catálogo...' : 'Adicionar expansão ou caixa',
            ),
          ),
        ],
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo, style: text.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.game,
    required this.onSaida,
    required this.onRemover,
  });

  final Game game;
  final VoidCallback onSaida;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;

    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'saida') onSaida();
        if (v == 'remover') onRemover();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'saida',
          child: Text(
            game.isGone
                ? 'Voltou para a estante'
                : 'Saiu da coleção (vendi, troquei, doei)',
          ),
        ),
        PopupMenuItem(
          value: 'remover',
          child: Text('Apagar da coleção',
              style: TextStyle(color: viz.critical)),
        ),
      ],
    );
  }
}

