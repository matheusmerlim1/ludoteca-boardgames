import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/game_repository.dart';
import '../stats/cost_stats.dart';
import '../state/collection_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/donut_chart.dart';
import '../widgets/meta_sheet.dart';
import '../widgets/month_bar_chart.dart';
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

    final stats = CostStats.compute(entries: store.allEntries);

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
        return _abaDinheiro(stats);

      case _Aba.valeAPena:
        return _abaValeAPena(stats, store);

      case _Aba.tempo:
        return _abaTempo(stats);
    }
  }

  List<Widget> _abaDinheiro(CostStats stats) {
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
                  'o dinheiro saiu do bolso na época.',
              data: stats.monthlySpend,
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
  const _Numeros({required this.stats, this.onVerNuncaJogados});

  final CostStats stats;
  final VoidCallback? onVerNuncaJogados;

  @override
  Widget build(BuildContext context) {
    return StatTileGrid(
      tiles: [
        StatTile(
          label: 'TOTAL INVESTIDO',
          value: dinheiro(stats.totalInvested, casas: 0),
          hint: '${stats.baseGameCount} '
              '${stats.baseGameCount == 1 ? 'jogo' : 'jogos'}'
              '${stats.expansionCount > 0 ? ' + ${stats.expansionCount} exp.' : ''}',
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
              'falta a data de compra dos jogos',
            _ when stats.undatedGameCount > 0 =>
              'de ${stats.datedGameCount} jogos; '
                  '${stats.undatedGameCount} sem data de compra',
            _ => 'o que a coleção custa por mês de posse',
          },
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
