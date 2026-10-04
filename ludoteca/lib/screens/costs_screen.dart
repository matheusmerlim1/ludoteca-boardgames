import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/game_repository.dart';
import '../models/extra.dart';
import '../stats/cost_stats.dart';
import '../state/collection_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/chart_card.dart';
import '../widgets/donut_chart.dart';
import '../widgets/meta_sheet.dart';
import '../widgets/extra_sheet.dart';
import '../widgets/month_bar_chart.dart';
import '../widgets/month_spend_sheet.dart';
import '../widgets/play_bubbles.dart';
import '../widgets/play_calendar.dart';
import '../widgets/ranked_bar_list.dart';
import '../widgets/stat_tile.dart';
import 'collection_screen.dart';
import 'game_detail_screen.dart';

/// Tela de custos: as quatro métricas.
///
/// Cada cartão diz no subtítulo qual é a base do número. Os totais e a
/// composição olham só o que está na estante hoje; a linha do tempo de gastos
/// inclui jogos já vendidos, porque o dinheiro saiu do bolso de qualquer forma.
/// Sem isso escrito, dois cartões parecem se contradizer.
/// As abas da tela. Cada uma responde uma pergunta, e o rótulo é a pergunta
/// encurtada — "Dinheiro" e não "Gráficos de composição".
enum _Aba {
  resumo('Resumo'),
  mes('Mês'),
  dinheiro('Dinheiro'),
  valeAPena('Vale a pena?'),
  tempo('Tempo');

  const _Aba(this.titulo);
  final String titulo;
}

class CostsScreen extends StatefulWidget {
  const CostsScreen({super.key, this.onVerColecao});

  /// Leva para a aba da coleção. A tela de custos mostra contagens ("6 nunca
  /// jogados") e a pergunta seguinte é sempre "quais?" — sem este caminho, a
  /// resposta exige trocar de aba e remontar o filtro à mão.
  final void Function()? onVerColecao;

  @override
  State<CostsScreen> createState() => _CostsScreenState();
}

class _CostsScreenState extends State<CostsScreen> {
  bool _piores = true;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CollectionStore>();
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    if (store.loading && store.allEntries.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Custos')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final stats = CostStats.compute(
      entries: store.allEntries,
      extras: store.extras,
    );

    if (stats.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Custos')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
          children: [
            Icon(Icons.pie_chart_outline, size: 44, color: viz.inkMuted),
            const SizedBox(height: 18),
            Text(
              'Nada para somar ainda',
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Cadastre jogos com preço e data de compra e os gráficos '
              'aparecem aqui.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
        ),
      );
    }

    // Uma pergunta por aba, em vez de uma página só que se rola inteira para
    // achar um cartão. As abas são as perguntas que a tela responde, não
    // categorias de gráfico.
    return DefaultTabController(
      length: _Aba.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Custos e partidas'),
          actions: [
            IconButton(
              onPressed: () => _editarExtra(null),
              icon: const Icon(Icons.add_shopping_cart),
              tooltip: 'Adicionar kit ou extra',
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final a in _Aba.values) Tab(text: a.titulo),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final a in _Aba.values)
              RefreshIndicator(
                onRefresh: store.refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  children: _conteudo(a, stats, store),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _conteudo(_Aba aba, CostStats stats, CollectionStore store) {
    switch (aba) {
      case _Aba.resumo:
        return [
          _Numeros(
            stats: stats,
            onVerNuncaJogados:
                stats.neverPlayedCount == 0 ? null : _verNuncaJogados,
            onVerGastoDoMes: () => _verGastoDoMes(store),
          ),
          const SizedBox(height: 16),
          PlayCalendar(plays: store.todasPartidas),
        ];

      case _Aba.mes:
        return [
          PlayBubbles(
            plays: store.todasPartidas,
            entryPorId: store.entryById,
          ),
        ];

      case _Aba.dinheiro:
        return _abaDinheiro(stats, store);

      case _Aba.valeAPena:
        return _abaValeAPena(stats, store);

      case _Aba.tempo:
        return _abaTempo(stats);
    }
  }

  List<Widget> _abaDinheiro(CostStats stats, CollectionStore store) {
    return [
            // Pizza 1 — onde o dinheiro está. Máximo 6 fatias: a cauda já vem
            // dobrada em "Outros" do cálculo.
            DonutChart(
              title: 'Onde está o seu dinheiro',
              subtitle: 'Investimento por jogo, do maior para o menor. '
                  'Expansões somam no jogo-base.',
              slices: stats.compositionByGame,
            ),
            const SizedBox(height: 16),

            // Pizza 2 — o custo mensal fatiado por jogo. As fatias somam
            // exatamente o "custo por mês" do cartão lá em cima.
            DonutChart(
              title: 'Quem puxa o custo por mês',
              subtitle: 'Cada jogo como fatia dos '
                  '${dinheiro(stats.monthlyOwnershipCost, casas: 0)} que a '
                  'coleção custa por mês de posse.',
              slices: stats.compositionByMonthlyCost,
            ),
            const SizedBox(height: 16),

            // Pizza 3 — três fatias. Se sobrar menos de três (sem sleeves nem
            // acessórios), o próprio widget troca a rosca por números soltos.
            DonutChart(
              title: 'Em que você gastou',
              subtitle: 'Caixa do jogo, sleeves e acessórios.',
              slices: stats.compositionByType,
            ),
            const SizedBox(height: 16),

            MonthBarChart(
              title: 'Quanto você gastou por mês',
              subtitle: 'Pela data de compra. Inclui jogos já vendidos — '
                  'o dinheiro saiu do bolso na época. Toque duas vezes numa '
                  'barra para ver o que foi comprado.',
              data: stats.monthlySpend,
              onAbrirMes: (mes) => MonthSpendSheet.show(
                context,
                entries: store.allEntries,
                mesInicial: mes,
                onAbrirJogo: _abrir,
                extras: store.extras,
                onAbrirExtra: _editarExtra,
              ),
            ),
            const SizedBox(height: 16),
            _ExtrasCard(
              extras: store.extras,
              onAdicionar: () => _editarExtra(null),
              onEditar: _editarExtra,
            ),
    ];
  }

  List<Widget> _abaValeAPena(CostStats stats, CollectionStore store) {
    return [
            RankedBarList(
              title: _piores
                  ? 'Os que ainda não se pagaram'
                  : 'Os que mais valeram o dinheiro',
              subtitle: 'Custo por partida: tudo que o jogo custou dividido '
                  'pelas partidas jogadas.',
              items:
                  _piores ? stats.priciestPerPlay : stats.cheapestPerPlay,
              format: (v) => dinheiro(v),
              emptyMessage: 'Registre partidas para este ranking existir.',
              onTapGame: _abrir,
              meta: store.metaPorPartida,
              metaLabel: store.metaPorPartida == null
                  ? null
                  : 'Vale a pena até ${dinheiro(store.metaPorPartida!)} por partida',
              onAjustarMeta: () => _ajustarMeta(
                        chave: GameRepository.keyMetaPorPartida,
                        atual: store.metaPorPartida,
                        titulo: 'Quanto por partida vale a pena?',
                        descricao: 'Acima disso o jogo aparece marcado como '
                            'ainda não pago. Quem joga toda semana e quem joga '
                            'uma vez por mês não usam o mesmo número.',
                        sufixo: 'por partida',
                        sugestoes: const [5, 10, 20, 30],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Piores')),
                  ButtonSegment(value: false, label: Text('Melhores')),
                ],
                selected: {_piores},
                onSelectionChanged: (s) => setState(() => _piores = s.first),
              ),
            ),
            const SizedBox(height: 16),

            RankedBarList(
              title: 'Custo de posse por mês',
              subtitle: 'Total investido dividido pelos meses desde a compra. '
                  'Jogo antigo custa pouco por mês; recém-comprado custa caro.',
              items: stats.byCostPerMonth,
              format: (v) => '${dinheiro(v)}/mês',
              emptyMessage: 'Preencha a data de compra dos jogos.',
              onTapGame: _abrir,
              meta: store.metaPorMes,
              metaLabel: store.metaPorMes == null
                  ? null
                  : 'Meu teto: ${dinheiro(store.metaPorMes!)} por mês',
              onAjustarMeta: () => _ajustarMeta(
                        chave: GameRepository.keyMetaPorMes,
                        atual: store.metaPorMes,
                        titulo: 'Quanto um jogo pode custar por mês?',
                        descricao: 'Custo de posse: o investimento diluído no '
                            'tempo em que o jogo está com você.',
                        sufixo: '/mês',
                        sugestoes: const [10, 20, 50, 100],
              ),
            ),
            const SizedBox(height: 16),

            RankedBarList(
              title: 'Custo por hora de jogo',
              subtitle: 'Investimento dividido pelas horas de mesa. Compara '
                  'melhor que o custo por partida quando as durações são bem '
                  'diferentes — um filler de 20 min e uma campanha de 4 h não '
                  'valem uma "partida" cada.',
              items: stats.byCostPerHour,
              format: (v) => '${dinheiro(v)}/h',
              emptyMessage: 'Precisa de partidas registradas e de duração '
                  'cadastrada no jogo.',
              onTapGame: _abrir,
              meta: store.metaPorHora,
              metaLabel: store.metaPorHora == null
                  ? null
                  : 'Vale a pena até ${dinheiro(store.metaPorHora!)} por hora',
              onAjustarMeta: () => _ajustarMeta(
                        chave: GameRepository.keyMetaPorHora,
                        atual: store.metaPorHora,
                        titulo: 'Quanto por hora de mesa vale a pena?',
                        descricao: 'Um bom parâmetro é o que você pagaria por '
                            'uma hora de qualquer outro lazer.',
                        sufixo: '/h',
                        sugestoes: const [5, 10, 15, 25],
              ),
            ),
    ];
  }

  Future<void> _ajustarMeta({
    required String chave,
    required double? atual,
    required String titulo,
    required String descricao,
    required String sufixo,
    required List<double> sugestoes,
  }) async {
    final store = context.read<CollectionStore>();
    final r = await MetaSheet.show(
      context,
      titulo: titulo,
      descricao: descricao,
      sufixo: sufixo,
      inicial: atual,
      sugestoes: sugestoes,
    );
    // Fechar a folha arrastando não é "tirar a régua": só o botão é.
    if (r == null) return;

    await store.setMeta(chave, r.valor);
  }

  List<Widget> _abaTempo(CostStats stats) {
    return [
            RankedBarList(
              title: 'Mais horas de mesa',
              subtitle: stats.hoursAreEstimated
                  ? 'Partidas cronometradas contam o tempo real; o resto conta '
                      'pela duração média do jogo. Por isso o "≈".'
                  : 'Tempo cronometrado em todas as partidas.',
              items: stats.mostHours,
              format: (v) => talvez(
                horas(v),
                estimado: stats.hoursAreEstimated,
              ),
              emptyMessage: 'Nenhuma hora contabilizada ainda.',
              onTapGame: _abrir,
              // Violeta: azul é dinheiro, água é contagem, violeta é tempo.
              // Amarelo e magenta ficariam abaixo de 3:1 numa barra de 6px
              // sobre a superfície clara.
              colorSlot: 6,
            ),
            const SizedBox(height: 16),

            RankedBarList(
              title: 'Os mais jogados',
              subtitle: 'Partidas registradas, mais o histórico que veio da '
                  'planilha.',
              items: stats.mostPlayed,
              format: (v) => '${v.toInt()}',
              emptyMessage: 'Nenhuma partida registrada ainda.',
              onTapGame: _abrir,
              // Slot 3 (água) em vez do azul: esta é outra grandeza,
              // contagem e não dinheiro, e a cor sinaliza isso.
              colorSlot: 2,
            ),
    ];
  }

  /// Do número para a lista: monta o filtro e leva para a coleção.
  ///
  /// Ler "6 nunca jogados" e não ter como ver quais são é a parte frustrante
  /// de um painel de números — a pergunta seguinte é sempre "quais?".
  void _verNuncaJogados() {
    final store = context.read<CollectionStore>();
    store.clearFilters();
    store.setOnlyNeverPlayed(true);

    final ir = widget.onVerColecao;
    if (ir != null) {
      ir();
      return;
    }

    // Sem a casca do app por perto (num teste, ou aberta como tela solta), a
    // coleção entra empilhada — o filtro já vai aplicado do mesmo jeito.
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CollectionScreen()),
    );
  }

  /// Do total do mês para as compras que o formaram.
  ///
  /// Vale reparar que são grandezas diferentes: o cartão mostra **custo de
  /// posse** (o investimento diluído nos meses em que o jogo é seu), e a folha
  /// mostra **gasto** (o que saiu do bolso naquele mês). A pergunta que leva de
  /// um ao outro — "de onde vem esse número?" — é a mesma, então o caminho
  /// existe; a folha diz no cabeçalho o que está somando.
  Future<void> _verGastoDoMes(CollectionStore store) {
    return MonthSpendSheet.show(
      context,
      entries: store.allEntries,
      mesInicial: DateTime.now(),
      onAbrirJogo: _abrir,
      extras: store.extras,
      onAbrirExtra: _editarExtra,
    );
  }

  /// Cadastra (nulo) ou edita um kit/extra avulso.
  Future<void> _editarExtra(Extra? extra) async {
    final store = context.read<CollectionStore>();
    final r = await ExtraSheet.show(context, inicial: extra);
    if (r == null) return;
    if (r.apagar && extra?.id != null) {
      await store.deleteExtra(extra!.id!);
    } else if (r.salvo != null) {
      if (r.salvo!.id == null) {
        await store.addExtra(r.salvo!);
      } else {
        await store.updateExtra(r.salvo!);
      }
    }
  }

  void _abrir(int gameId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameDetailScreen(gameId: gameId),
      ),
    );
  }
}

/// Os números de cabeceira. Quando a história é um número, um número é o
/// gráfico certo — não uma pizza de duas fatias.
class _Numeros extends StatelessWidget {
  const _Numeros({
    required this.stats,
    this.onVerNuncaJogados,
    this.onVerGastoDoMes,
  });

  final CostStats stats;
  final VoidCallback? onVerNuncaJogados;
  final VoidCallback? onVerGastoDoMes;

  @override
  Widget build(BuildContext context) {
    return StatTileGrid(
      tiles: [
        StatTile(
          label: 'TOTAL INVESTIDO',
          // Com extras, o total é o do hobby: jogos mais kits e playmats.
          value: dinheiro(stats.totalSpent, casas: 0),
          hint: '${stats.baseGameCount} '
              '${stats.baseGameCount == 1 ? 'jogo' : 'jogos'}'
              '${stats.expansionCount > 0 ? ' + ${stats.expansionCount} exp.' : ''}'
              '${stats.extrasCount > 0 ? ' + ${stats.extrasCount} ${stats.extrasCount == 1 ? 'extra' : 'extras'}' : ''}',
        ),
        StatTile(
          label: 'CUSTO POR MÊS',
          // Sem nenhuma data de compra a conta não dá zero, ela não existe.
          // Mostrar "R$ 0" aqui dizia que a coleção não custa nada — o oposto
          // do que a tela inteira serve para responder.
          value: stats.monthlyCostIsUnknown
              ? '—'
              : dinheiro(stats.monthlyOwnershipCost, casas: 0),
          hint: switch (stats) {
            _ when stats.monthlyCostIsUnknown =>
              'falta a data de compra · toque para ver as compras',
            _ when stats.undatedGameCount > 0 =>
              'de ${stats.datedGameCount} jogos; '
                  '${stats.undatedGameCount} sem data · toque para ver o mês',
            _ => 'custo de posse · toque para ver o que comprou no mês',
          },
          onTap: onVerGastoDoMes,
        ),
        // O que saiu do bolso neste mês. Fica ao lado do custo por mês (de
        // posse) porque são perguntas diferentes: "quanto a coleção me custa
        // por mês" e "quanto eu gastei este mês".
        StatTile(
          label: 'CUSTO NO MÊS',
          value: dinheiro(stats.currentMonthSpend.total, casas: 0),
          hint: switch (stats.currentMonthSpend.itemCount) {
            0 => 'nada comprado em ${mesAnoLongo(stats.currentMonthSpend.month)}'
                ' · toque para ver os meses',
            final n => '$n ${n == 1 ? 'item' : 'itens'} em '
                '${mesAnoLongo(stats.currentMonthSpend.month)} · toque para ver',
          },
          onTap: onVerGastoDoMes,
        ),
        StatTile(
          label: 'CUSTO MÉDIO POR PARTIDA',
          value: stats.avgCostPerPlay == null
              ? '—'
              : dinheiro(stats.avgCostPerPlay!),
          hint: '${stats.totalPlays} '
              '${stats.totalPlays == 1 ? 'partida' : 'partidas'} no total',
        ),
        StatTile(
          label: 'HORAS DE MESA',
          value: stats.totalMinutes == 0
              ? '—'
              : talvez(
                  horas(stats.totalHours),
                  estimado: stats.hoursAreEstimated,
                ),
          hint: stats.playsWithMeasuredDuration == 0
              ? 'estimado pela duração média dos jogos'
              : '${porcento(stats.measuredShare)} cronometrado',
        ),
        StatTile(
          label: 'CUSTO POR HORA',
          value: stats.costPerHour == null
              ? '—'
              : talvez(
                  dinheiro(stats.costPerHour!),
                  estimado: stats.hoursAreEstimated,
                ),
          hint: stats.avgMinutesPerPlay == null
              ? null
              : '${duracao(stats.avgMinutesPerPlay!.round())} por partida, '
                  'em média',
        ),
        StatTile(
          label: 'NUNCA JOGADOS',
          value: '${stats.neverPlayedCount}',
          hint: stats.neverPlayedCount == 0
              ? 'tudo já foi à mesa'
              : '${dinheiro(stats.idleValue, casas: 0)} parados '
                  '· toque para ver quais',
          onTap: onVerNuncaJogados,
        ),
        if (stats.totalSleeves > 0)
          StatTile(
            label: 'GASTO COM SLEEVES',
            value: dinheiro(stats.totalSleeves, casas: 0),
            hint: '${porcento(stats.totalSleeves / stats.totalInvested)} '
                'do total',
          ),
        if (stats.totalRecovered > 0)
          StatTile(
            label: 'RECUPERADO EM VENDAS',
            value: dinheiro(stats.totalRecovered, casas: 0),
            hint: 'jogos que saíram da coleção',
          ),
      ],
    );
  }
}

/// Kits e extras avulsos: o que não é de um jogo só.
class _ExtrasCard extends StatelessWidget {
  const _ExtrasCard({
    required this.extras,
    required this.onAdicionar,
    required this.onEditar,
  });

  final List<Extra> extras;
  final VoidCallback onAdicionar;
  final void Function(Extra) onEditar;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final total = extras.fold<double>(0, (s, x) => s + x.price);

    return ChartCard(
      title: 'Kits e extras',
      subtitle: extras.isEmpty
          ? 'Sleeves, playmat, organizador que não são de um jogo só. '
              'Entram no custo do mês da compra.'
          : '${extras.length} ${extras.length == 1 ? 'item' : 'itens'} · '
              '${dinheiro(total)}. Entram no custo do mês da compra.',
      trailing: IconButton(
        onPressed: onAdicionar,
        icon: const Icon(Icons.add),
        tooltip: 'Adicionar kit ou extra',
        visualDensity: VisualDensity.compact,
      ),
      child: extras.isEmpty
          ? Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAdicionar,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Adicionar o primeiro'),
              ),
            )
          : Column(
              children: [
                for (final x in extras)
                  InkWell(
                    onTap: () => onEditar(x),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(x.kind.icon, size: 20, color: viz.inkMuted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  x.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium
                                      ?.copyWith(color: viz.inkPrimary),
                                ),
                                Text(
                                  '${x.kind.label.toLowerCase()} · '
                                  '${x.purchaseDate == null ? 'sem data' : data(x.purchaseDate!)}',
                                  style: text.labelSmall
                                      ?.copyWith(color: viz.inkMuted),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            dinheiro(x.price),
                            style: text.bodyMedium?.copyWith(
                              color: viz.inkPrimary,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
