import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../stats/cost_stats.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'chart_card.dart';

/// Barras do gasto mês a mês.
///
/// Uma série só, então uma cor só (slot 1) e nenhuma legenda — o título já diz
/// o que é. Colorir cada barra por altura seria gastar o canal de cor com
/// informação que a barra já mostra.
///
/// Rola na horizontal dentro do próprio cartão, com **todos** os meses
/// presentes: nada de cortar a série em "últimos 12" e esconder história.
class MonthBarChart extends StatefulWidget {
  const MonthBarChart({
    super.key,
    required this.data,
    required this.title,
    this.subtitle,
    this.plotHeight = 150,
  });

  final List<MonthSpend> data;
  final String title;
  final String? subtitle;
  final double plotHeight;

  @override
  State<MonthBarChart> createState() => _MonthBarChartState();
}

class _MonthBarChartState extends State<MonthBarChart> {
  static const _slotWidth = 44.0;
  static const _barWidth = 24.0;
  static const _axisBand = 38.0;
  static const _yLabelWidth = 62.0;

  final _scroll = ScrollController();
  int? _selected;
  bool _showTable = false;

  @override
  void initState() {
    super.initState();
    // Abre mostrando os meses mais recentes — é o que interessa primeiro.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final data = widget.data;

    if (data.isEmpty) {
      return ChartCard(
        title: widget.title,
        subtitle: widget.subtitle,
        child: Text(
          'Preencha a data de compra dos jogos para ver a linha do tempo.',
          style: text.bodySmall,
        ),
      );
    }

    final maxReal = data.fold<double>(0, (m, d) => math.max(m, d.total));
    final maxEscala = _niceMax(maxReal);

    // Sempre há um valor legível na tela: por padrão o mês mais recente,
    // trocando para o mês tocado. O número nunca fica preso num tooltip.
    final destaque = _selected != null && _selected! < data.length
        ? data[_selected!]
        : data.last;

    return ChartCard(
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: IconButton(
        onPressed: () => setState(() => _showTable = !_showTable),
        icon: Icon(_showTable ? Icons.bar_chart : Icons.table_rows_outlined),
        tooltip: _showTable ? 'Ver gráfico' : 'Ver valores em tabela',
        visualDensity: VisualDensity.compact,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Readout(spend: destaque),
          const SizedBox(height: 14),
          if (_showTable)
            _Table(data: data)
          else
            SizedBox(
              // A altura inclui a faixa dos rótulos do eixo x, senão o cartão
              // ganha uma barrinha de scroll vertical minúscula.
              height: widget.plotHeight + _axisBand,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _YAxis(
                    max: maxEscala,
                    plotHeight: widget.plotHeight,
                    width: _yLabelWidth,
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        // Grade em hairline sólido, um tom acima da superfície.
                        // Nunca tracejada: tracejado lê como "projeção".
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: widget.plotHeight,
                          child: _Gridlines(
                            color: viz.gridline,
                            baseline: viz.baseline,
                          ),
                        ),
                        SingleChildScrollView(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var i = 0; i < data.length; i++)
                                _Bar(
                                  spend: data[i],
                                  max: maxEscala,
                                  plotHeight: widget.plotHeight,
                                  slotWidth: _slotWidth,
                                  barWidth: _barWidth,
                                  axisBand: _axisBand,
                                  color: viz.serie(0),
                                  selected: _selected == i,
                                  showYear: i == 0 ||
                                      data[i].month.year !=
                                          data[i - 1].month.year,
                                  onTap: () => setState(
                                    () => _selected = _selected == i ? null : i,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Linha de leitura acima do gráfico: mês, total e a quebra do gasto.
class _Readout extends StatelessWidget {
  const _Readout({required this.spend});

  final MonthSpend spend;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    final partes = <String>[
      if (spend.games > 0) 'caixa ${dinheiro(spend.games, casas: 0)}',
      if (spend.sleeves > 0) 'sleeves ${dinheiro(spend.sleeves, casas: 0)}',
      if (spend.accessories > 0)
        'acessórios ${dinheiro(spend.accessories, casas: 0)}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              dinheiro(spend.total, casas: 0),
              style: text.headlineSmall?.copyWith(fontSize: 24),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'em ${mesAnoLongo(spend.month)}',
                style: text.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          spend.itemCount == 0
              ? 'nenhuma compra neste mês'
              : '${spend.itemCount} ${spend.itemCount == 1 ? 'item' : 'itens'}'
                  '${partes.isEmpty ? '' : ' · ${partes.join(' · ')}'}',
          style: text.labelSmall?.copyWith(color: viz.inkMuted),
          maxLines: 2,
        ),
      ],
    );
  }
}

class _YAxis extends StatelessWidget {
  const _YAxis({
    required this.max,
    required this.plotHeight,
    required this.width,
  });

  final double max;
  final double plotHeight;
  final double width;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return SizedBox(
      width: width,
      height: plotHeight,
      child: Stack(
        children: [
          for (var i = 0; i <= 4; i++)
            Positioned(
              right: 8,
              // -6 alinha a linha de base do texto com a gridline.
              top: plotHeight - (plotHeight * i / 4) - 6,
              child: Text(
                dinheiroCurto(max * i / 4),
                style: TextStyle(
                  fontSize: 10,
                  color: viz.inkMuted,
                  // Eixo é coluna de números alinhados: aqui tabular cabe.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Gridlines extends StatelessWidget {
  const _Gridlines({required this.color, required this.baseline});

  final Color color;
  final Color baseline;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 5; i++)
          Container(height: 1, color: i == 4 ? baseline : color),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.spend,
    required this.max,
    required this.plotHeight,
    required this.slotWidth,
    required this.barWidth,
    required this.axisBand,
    required this.color,
    required this.selected,
    required this.showYear,
    required this.onTap,
  });

  final MonthSpend spend;
  final double max;
  final double plotHeight;
  final double slotWidth;
  final double barWidth;
  final double axisBand;
  final Color color;
  final bool selected;
  final bool showYear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;

    final fracao = max <= 0 ? 0.0 : (spend.total / max).clamp(0.0, 1.0);
    // Mês sem compra vira um toco de 2px em vez de nada: assim ele lê como
    // "mês existiu, não gastei", não como um mês ausente da série.
    final altura = spend.total <= 0 ? 2.0 : math.max(fracao * plotHeight, 3.0);

    return SizedBox(
      width: slotWidth,
      height: plotHeight + axisBand,
      child: InkWell(
        onTap: onTap,
        // O alvo de toque é o slot inteiro, muito maior que a barra de 24px.
        borderRadius: BorderRadius.circular(6),
        child: Column(
          children: [
            SizedBox(
              height: plotHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: barWidth,
                  height: altura,
                  decoration: BoxDecoration(
                    color: spend.total <= 0 ? viz.baseline : color,
                    // Pontas arredondadas só no topo: a barra fica ancorada
                    // na linha de base, e a base não deve parecer flutuando.
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                    border: selected
                        ? Border.all(color: viz.inkPrimary, width: 2)
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              mesCurto(spend.month),
              style: TextStyle(
                fontSize: 10,
                color: selected ? viz.inkPrimary : viz.inkMuted,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
            if (showYear)
              Text(
                '${spend.month.year}',
                style: TextStyle(fontSize: 9, color: viz.inkMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Visão em tabela — o gêmeo legível de qualquer gráfico.
class _Table extends StatelessWidget {
  const _Table({required this.data});

  final List<MonthSpend> data;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final comGasto = data.where((d) => d.total > 0).toList().reversed.toList();

    if (comGasto.isEmpty) {
      return Text('Nenhuma compra registrada.', style: text.bodySmall);
    }

    final tabular = text.bodyMedium?.copyWith(
      color: viz.inkPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      children: [
        for (final d in comGasto)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(child: Text(mesAno(d.month), style: text.bodyMedium)),
                Text(
                  '${d.itemCount} ${d.itemCount == 1 ? 'item' : 'itens'}',
                  style: text.bodySmall,
                ),
                const SizedBox(width: 16),
                Text(dinheiro(d.total, casas: 0), style: tabular),
              ],
            ),
          ),
      ],
    );
  }
}

/// Arredonda o topo da escala para um número redondo (1, 2, 2,5, 5 ou 10 vezes
/// uma potência de dez), para os rótulos do eixo não virarem "R$ 1.847".
double _niceMax(double v) {
  if (v <= 0) return 1;
  final expoente = (math.log(v) / math.ln10).floor();
  final potencia = math.pow(10, expoente).toDouble();
  final n = v / potencia;
  final passo = n <= 1
      ? 1.0
      : n <= 2
          ? 2.0
          : n <= 2.5
              ? 2.5
              : n <= 5
                  ? 5.0
                  : 10.0;
  return passo * potencia;
}
