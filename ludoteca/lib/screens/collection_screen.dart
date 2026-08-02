import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game.dart';
import '../services/share_service.dart';
import '../state/collection_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/game_card.dart';
import '../widgets/log_play_sheet.dart';
import '../widgets/pick_game_sheet.dart';
import '../widgets/tag_filter_sheet.dart';
import 'add_game_screen.dart';
import 'game_detail_screen.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _searchController = TextEditingController();

  /// Começa fechado: o painel inteiro ocupava metade da tela, e a lista de
  /// jogos é o que se quer ver ao abrir o app. O botão marca quantos filtros
  /// estão ligados, então nada fica escondido sem aviso.
  bool _filtrosAbertos = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CollectionStore>();
    final viz = context.viz;

    final entries = store.filteredEntries;
    final total = store.ownedBaseGames.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ludoteca'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0),
          child: Container(height: 1, color: viz.gridline),
        ),
        actions: [
          IconButton(
            onPressed: () => _compartilharColecao(context, store),
            icon: const Icon(Icons.ios_share),
            tooltip: 'Compartilhar a coleção',
          ),
          _SortButton(
            current: store.sort,
            onSelected: store.setSort,
          ),
        ],
      ),
      // Dois botões em vez de um genérico: "adicionar" sozinho não dizia o
      // quê, e registrar partida — que é o que mais se faz no dia a dia —
      // exigia achar o jogo na lista e abrir a ficha antes.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'fab-jogo',
            onPressed: () => _abrirAdicionar(context),
            icon: const Icon(Icons.add),
            label: const Text('Jogo'),
            backgroundColor: viz.surface,
            foregroundColor: viz.inkPrimary,
            elevation: 1,
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'fab-partida',
            onPressed: () => _registrarPartida(context, store),
            icon: const Icon(Icons.casino),
            label: const Text('Partida'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: Column(
          children: [
            // Uma faixa de filtros só, acima de tudo que ela afeta.
            _FilterBar(
              controller: _searchController,
              store: store,
              resultCount: entries.length,
              totalCount: total,
              aberto: _filtrosAbertos,
              onAlternar: () =>
                  setState(() => _filtrosAbertos = !_filtrosAbertos),
            ),
            Container(height: 1, color: viz.gridline),
            Expanded(
              child: _Body(
                store: store,
                entries: entries,
                onOpen: (id) => _abrirDetalhe(context, id),
                onAdd: () => _abrirAdicionar(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirAdicionar(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddGameScreen()),
    );
  }

  Future<void> _compartilharColecao(
    BuildContext context,
    CollectionStore store,
  ) async {
    const servico = ShareService();

    // O que está na tela é o que vai. Se você filtrou por 2 jogadores para
    // mostrar o que dá para jogar hoje, mandar a coleção inteira seria
    // desfazer o filtro justamente na hora de usá-lo.
    final texto = servico.textoDaColecao(
      store.filteredEntries,
      filtro: store.filtroDescrito,
    );

    // A folha do Android é quem oferece WhatsApp, Instagram e o resto —
    // integrar com cada rede uma a uma daria o mesmo resultado com muito mais
    // código para manter.
    await servico.compartilhar(texto, assunto: 'Minha coleção de jogos');
  }

  /// Escolher o jogo e registrar a partida, sem passar pela ficha.
  Future<void> _registrarPartida(
    BuildContext context,
    CollectionStore store,
  ) async {
    // Só o que dá para jogar: desejados e vendidos não vão à mesa.
    final jogaveis = store.allEntries
        .where((e) => !e.game.isWishlist && !e.game.sold)
        .toList();

    if (jogaveis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cadastre um jogo primeiro, no botão "Jogo".'),
        ),
      );
      return;
    }

    final escolha = await PickGameSheet.show(context, entries: jogaveis);
    if (escolha == null || !context.mounted) return;

    GameEntry? alvo = escolha.entry;

    // Jogou o jogo de outra pessoa: busca no catálogo, cadastra já como
    // "Só joguei" e segue direto para o registro da partida.
    if (escolha.buscarNoCatalogo) {
      final novoId = await Navigator.of(context).push<int>(
        MaterialPageRoute<int>(
          builder: (_) =>
              const AddGameScreen(ownershipInicial: Ownership.jogada),
        ),
      );
      if (novoId == null || !context.mounted) return;

      await store.refresh();
      if (!context.mounted) return;
      alvo = store.entryById(novoId);
    }

    if (alvo == null || !context.mounted) return;

    final sugestoes = await store.playerNames();
    if (!context.mounted) return;

    final r = await LogPlaySheet.show(
      context,
      game: alvo.game,
      itens: store.expansionsOf(alvo.id).map((e) => e.game).toList(),
      sugestoesDeNome: sugestoes,
    );
    if (r == null || !context.mounted) return;

    await store.logPlay(r.play, placar: r.placar);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Partida de ${alvo.displayName} '
          'em ${data(r.play.playedAt)} registrada.',
        ),
      ),
    );
  }

  Future<void> _abrirDetalhe(BuildContext context, int gameId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameDetailScreen(gameId: gameId),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.store,
    required this.entries,
    required this.onOpen,
    required this.onAdd,
  });

  final CollectionStore store;
  final List<GameEntry> entries;
  final void Function(int) onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;

    if (store.loading && store.allEntries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (store.error != null && store.allEntries.isEmpty) {
      return _Empty(
        icon: Icons.error_outline,
        title: 'Não consegui abrir a coleção',
        message: '${store.error}',
        actionLabel: 'Tentar de novo',
        onAction: store.load,
      );
    }

    // Coleção realmente vazia x filtro que não achou nada: são situações
    // diferentes e merecem saídas diferentes.
    if (store.allEntries.isEmpty) {
      return _Empty(
        icon: Icons.casino_outlined,
        title: 'Sua estante está vazia',
        message: 'Busque um jogo pelo nome e ele já vem com capa, número de '
            'jogadores, duração e preço preenchidos.\n\n'
            'Se você tem um backup da sua planilha, restaure primeiro em '
            'Ajustes — restaurar substitui a coleção inteira.',
        actionLabel: 'Adicionar o primeiro jogo',
        onAction: onAdd,
      );
    }

    if (entries.isEmpty) {
      return _Empty(
        icon: Icons.filter_alt_off_outlined,
        title: 'Nenhum jogo com esses filtros',
        message: store.playerCount != null
            ? 'Nenhum jogo da coleção serve para '
                '${store.playerCount} ${store.playerCount == 1 ? 'jogador' : 'jogadores'} '
                'com os outros filtros ativos.'
            : 'Tente afrouxar a busca.',
        actionLabel: 'Limpar filtros',
        onAction: store.clearFilters,
      );
    }

    return ListView.separated(
      // Folga para os dois botões empilhados; com 96 o último jogo ficava
      // atrás deles.
      padding: const EdgeInsets.only(bottom: 168),
      itemCount: entries.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 1,
        color: viz.gridline,
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, i) {
        final e = entries[i];
        return GameCard(
          entry: e,
          highlightPlayerCount: store.playerCount,
          onTap: () => onOpen(e.id),
        );
      },
    );
  }
}

/// Botão que abre e fecha o painel de filtros.
///
/// Com o painel fechado ele mostra quantos filtros estão ligados — sem isso,
/// uma lista curta por causa de um filtro esquecido pareceria bug.
class _BotaoFiltros extends StatelessWidget {
  const _BotaoFiltros({
    required this.aberto,
    required this.ativos,
    required this.onTap,
  });

  final bool aberto;
  final int ativos;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final ligado = ativos > 0;

    return Tooltip(
      message: aberto ? 'Esconder filtros' : 'Mostrar filtros',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: ligado
                ? viz.serie(0).withValues(alpha: 0.12)
                : viz.surface,
            border: Border.all(color: ligado ? viz.serie(0) : viz.gridline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                aberto ? Icons.filter_list_off : Icons.filter_list,
                size: 20,
                color: ligado ? viz.serie(0) : viz.inkSecondary,
              ),
              if (ligado) ...[
                const SizedBox(width: 5),
                Text(
                  '$ativos',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: viz.serie(0),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Os filtros ativos em uma linha, com o painel fechado. Tocar num remove.
class _ResumoFiltros extends StatelessWidget {
  const _ResumoFiltros({required this.store});

  final CollectionStore store;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;

    final itens = <({String rotulo, VoidCallback remover})>[
      if (store.sort != SortKey.nome)
        (
          rotulo: 'por ${store.sort.label.toLowerCase()}',
          remover: () => store.setSort(SortKey.nome),
        ),
      if (store.playerCount != null)
        (
          rotulo: '${store.playerCount} jogadores',
          remover: () => store.setPlayerCount(null),
        ),
      if (store.onlyNeverPlayed)
        (
          rotulo: 'nunca jogados',
          remover: () => store.setOnlyNeverPlayed(false),
        ),
      if (store.showExpansions)
        (
          rotulo: 'com agrupados',
          remover: () => store.setShowExpansions(false),
        ),
      if (store.showSold)
        (rotulo: 'com vendidos', remover: () => store.setShowSold(false)),
      for (final t in store.tags.where((t) => store.tagFilter.contains(t.id)))
        (rotulo: t.name, remover: () => store.toggleTag(t.id)),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final i in itens)
          InputChip(
            label: Text(i.rotulo),
            onDeleted: i.remover,
            deleteIcon: const Icon(Icons.close, size: 14),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelStyle: TextStyle(fontSize: 12, color: viz.inkPrimary),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.controller,
    required this.store,
    required this.resultCount,
    required this.totalCount,
    required this.aberto,
    required this.onAlternar,
  });

  final TextEditingController controller;
  final CollectionStore store;
  final int resultCount;
  final int totalCount;

  /// Painel de filtros expandido. Começa fechado: a lista de jogos é o que
  /// interessa ver, e o painel inteiro comia metade da tela.
  final bool aberto;
  final VoidCallback onAlternar;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    // Quantos ajustes estão ligados, para o botão avisar mesmo fechado.
    //
    // A ordenação entra na conta apesar de não esconder jogo nenhum: com o
    // painel fechado, uma lista fora de ordem alfabética e sem explicação
    // parece defeito.
    final ativos = (store.playerCount != null ? 1 : 0) +
        (store.onlyNeverPlayed ? 1 : 0) +
        (store.showExpansions ? 1 : 0) +
        (store.showSold ? 1 : 0) +
        (store.showPlayedNotOwned ? 1 : 0) +
        (store.sort != SortKey.nome ? 1 : 0) +
        store.tagFilter.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: store.setQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Buscar na coleção',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    suffixIcon: store.query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              controller.clear();
                              store.setQuery('');
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _BotaoFiltros(
                aberto: aberto,
                ativos: ativos,
                onTap: onAlternar,
              ),
            ],
          ),

          // Fechado: uma linha só dizendo o que está filtrando, para a lista
          // curta nunca parecer bug. Aberto: o painel inteiro.
          if (!aberto) ...[
            if (ativos > 0) ...[
              const SizedBox(height: 8),
              _ResumoFiltros(store: store),
            ],
          ] else ...[
          const SizedBox(height: 10),
          Text(
            'Serve para quantos jogadores?',
            style: text.labelSmall?.copyWith(color: viz.inkSecondary),
          ),
          const SizedBox(height: 6),
          // Wrap, não rolagem horizontal. Numa tela de celular comum (~390 de
          // largura) estes chips não cabem numa linha só, e com rolagem os
          // últimos — "8" jogadores e "Vendidos" — ficavam invisíveis: um
          // filtro que existe mas que ninguém descobre. Quebrar em duas linhas
          // custa altura e devolve a descoberta.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip(
                label: 'Todos',
                selected: store.playerCount == null,
                onTap: () => store.setPlayerCount(null),
              ),
              for (var n = 1; n <= 8; n++)
                _Chip(
                  label: '$n',
                  selected: store.playerCount == n,
                  onTap: () => store.setPlayerCount(
                    store.playerCount == n ? null : n,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Tempo sem jogar',
            style: text.labelSmall?.copyWith(color: viz.inkSecondary),
          ),
          const SizedBox(height: 6),
          // Estas duas ordenam em vez de esconder jogos — a pergunta
          // ("qual está parado há mais tempo?") é sobre a ordem da lista, não
          // sobre um recorte dela. Ficam aqui, e não só no menu de ordenação,
          // porque é neste painel que se procura por elas.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip(
                label: 'Mais tempo parados',
                selected: store.sort == SortKey.esquecidos,
                onTap: () => store.setSort(
                  store.sort == SortKey.esquecidos
                      ? SortKey.nome
                      : SortKey.esquecidos,
                ),
              ),
              _Chip(
                label: 'Jogados por último',
                selected: store.sort == SortKey.jogadosRecentemente,
                onTap: () => store.setSort(
                  store.sort == SortKey.jogadosRecentemente
                      ? SortKey.nome
                      : SortKey.jogadosRecentemente,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
                _Chip(
                  label: 'Nunca jogados',
                  selected: store.onlyNeverPlayed,
                  onTap: () => store.setOnlyNeverPlayed(!store.onlyNeverPlayed),
                ),
                _Chip(
                  label: 'Itens agrupados',
                  selected: store.showExpansions,
                  onTap: () => store.setShowExpansions(!store.showExpansions),
                ),
                _Chip(
                  label: 'Vendidos',
                  selected: store.showSold,
                  onTap: () => store.setShowSold(!store.showSold),
                ),
                // Sem este chip os jogos marcados como "Só joguei" ficavam
                // invisíveis e sem caminho de volta.
                _Chip(
                  label: 'Jogados sem ter',
                  selected: store.showPlayedNotOwned,
                  onTap: () =>
                      store.setShowPlayedNotOwned(!store.showPlayedNotOwned),
                ),
                // Tema fica atrás de uma folha, não de chips: uma coleção de
                // sessenta jogos gera dezenas de temas, e todos aqui
                // empurrariam a lista de jogos para fora da tela.
                _Chip(
                  label: store.tagFilter.isEmpty
                      ? 'Tema'
                      : 'Tema · ${store.tagFilter.length}',
                  selected: store.tagFilter.isNotEmpty,
                  onTap: () => _abrirTemas(context, store),
                ),
                // Também aparece com só uma ordenação escolhida: `clearFilters`
                // devolve a ordem para nome, e sem o botão não haveria como
                // desfazer isso a não ser tocando no mesmo chip.
                if (store.hasActiveFilters || store.sort != SortKey.nome)
                  TextButton.icon(
                    onPressed: store.clearFilters,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Limpar'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
          ),
          ],
          const SizedBox(height: 10),
          Text(
            store.hasActiveFilters
                ? '$resultCount de $totalCount ${totalCount == 1 ? 'jogo' : 'jogos'}'
                : '$totalCount ${totalCount == 1 ? 'jogo' : 'jogos'} na estante',
            style: text.labelSmall?.copyWith(color: viz.inkMuted),
          ),
        ],
      ),
    );
  }
}

Future<void> _abrirTemas(BuildContext context, CollectionStore store) async {
  final escolhidas = await TagFilterSheet.show(
    context,
    tags: store.tags,
    selecionadas: store.tagFilter,
  );
  if (escolhidas != null) store.setTagFilter(escolhidas);
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Sem Padding próprio: o espaçamento vem do `spacing`/`runSpacing` do Wrap
    // que contém os chips. Ter os dois daria folga dobrada entre eles.
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.current, required this.onSelected});

  final SortKey current;
  final ValueChanged<SortKey> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortKey>(
      icon: const Icon(Icons.sort),
      tooltip: 'Ordenar',
      onSelected: onSelected,
      itemBuilder: (context) => [
        // Agrupado por pergunta ("o que jogar hoje?", "quanto custou?"): com
        // treze opções, uma lista corrida vira parede de texto.
        for (final grupo in SortGroup.values) ...[
          if (grupo.label.isNotEmpty)
            PopupMenuItem<SortKey>(
              enabled: false,
              height: 30,
              child: Text(
                grupo.label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.viz.inkMuted,
                      letterSpacing: 0.6,
                    ),
              ),
            ),
          for (final k in SortKey.values.where((k) => k.group == grupo))
            PopupMenuItem(
              value: k,
              child: Row(
                children: [
                  Icon(
                    k == current ? Icons.check : null,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(k.label),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      children: [
        Icon(icon, size: 44, color: viz.inkMuted),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: text.titleMedium),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: text.bodySmall),
        const SizedBox(height: 22),
        Center(
          child: FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ),
      ],
    );
  }
}
