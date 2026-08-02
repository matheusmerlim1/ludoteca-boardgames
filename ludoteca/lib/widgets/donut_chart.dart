import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../stats/cost_stats.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'chart_card.dart';

/// Gráfico de pizza (em rosca) para parte-sobre-total.
///
/// Regras que valem a pena não perder de vista:
/// - **No máximo 6 fatias.** Passando disso as fatias adjacentes viram uma
///   papa; a cauda deve ir para "Outros" antes de chegar aqui.
/// - **Menos de 3 fatias não é pizza.** Uma rosca de duas fatias é um número
///   com enfeite, então o widget cai para números soltos nesse caso.
/// - A legenda mostra **valor e percentual de cada fatia**, então nenhuma
///   informação depende só da cor (três tons da paleta clara ficam abaixo de
///   3:1 de contraste, e o rótulo visível é justamente a compensação disso).
class DonutChart extends StatefulWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.title,
    this.subtitle,
    this.diameter = 176,
    this.thickness = 26,
  });

  final List<Slice> slices;
  final String title;
  final String? subtitle;
  final double diameter;
  final double thickness;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    final slices = widget.slices.where((s) => s.value > 0).toList();
    final total = slices.fold<double>(0, (s, x) => s + x.value);

    if (slices.isEmpty || total <= 0) {
      return ChartCard(
        title: widget.title,
        subtitle: widget.subtitle,
        child: Text(
          'Sem valores lançados ainda.',
          style: text.bodySmall,
        ),
      );
    }

    // Duas fatias (ou uma) não justificam uma rosca — a comparação é direta,
    // e os números soltos leem melhor que dois arcos.
    if (slices.length < 3) {
      return ChartCard(
        title: widget.title,
        subtitle: widget.subtitle,
        child: Column(
          children: [
            for (final s in slices)
              _LegendRow(
                slice: s,
                total: total,
                color: viz.serie(s.slot ?? slices.indexOf(s)),
                selected: false,
                onTap: null,
              ),
          ],
        ),
      );
    }

    final selecionada = _selected != null && _selected! < slices.length
        ? slices[_selected!]
        : null;

    return ChartCard(
      title: widget.title,
      subtitle: widget.subtitle,
      child: Column(
        children: [
          Center(
            child: GestureDetector(
              onTapDown: (d) => _handleTap(d.localPosition, slices, total),
              child: SizedBox(
                width: widget.diameter,
                height: widget.diameter,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.square(widget.diameter),
                      painter: _DonutPainter(
                        slices: slices,
                        total: total,
                        colors: [
                          for (var i = 0; i < slices.length; i++)
                            viz.serie(slices[i].slot ?? i),
                        ],
                        selected: _selected,
                        surface: viz.surface,
                        thickness: widget.thickness,
                      ),
                    ),
                    // Centro: o total, ou a fatia tocada.
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.thickness + 10,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dinheiro(selecionada?.value ?? total, casas: 0),
                            textAlign: TextAlign.center,
                            style: text.titleMedium?.copyWith(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selecionada == null
                                ? 'total'
                                : porcento(selecionada.value / total),
                            textAlign: TextAlign.center,
                            style: text.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // A legenda é também a "visão em tabela": todo valor está legível
          // aqui, sem depender de tocar a rosca.
          for (var i = 0; i < slices.length; i++)
            _LegendRow(
              slice: slices[i],
              total: total,
              color: viz.serie(slices[i].slot ?? i),
              selected: _selected == i,
              onTap: () => setState(() => _selected = _selected == i ? null : i),
            ),
        ],
      ),
    );
  }

  /// Descobre a fatia pelo ângulo do toque, ignorando toques no miolo.
  void _handleTap(Offset pos, List<Slice> slices, double total) {
    final c = Offset(widget.diameter / 2, widget.diameter / 2);
    final v = pos - c;
    final dist = v.distance;

    final raioExterno = widget.diameter / 2;
    final raioInterno = raioExterno - widget.thickness - 6;
    if (dist < raioInterno || dist > raioExterno + 4) {
      setState(() => _selected = null);
      return;
    }

    // atan2 dá 0 no leste; a rosca começa no norte.
    var ang = math.atan2(v.dy, v.dx) + math.pi / 2;
    if (ang < 0) ang += 2 * math.pi;

    var acc = 0.0;
    for (var i = 0; i < slices.length; i++) {
      final sweep = (slices[i].value / total) * 2 * math.pi;
      if (ang >= acc && ang < acc + sweep) {
        setState(() => _selected = _selected == i ? null : i);
        return;
      }
      acc += sweep;
    }
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.total,
    required this.colors,
    required this.selected,
    required this.surface,
    required this.thickness,
  });

  final List<Slice> slices;
  final double total;
  final List<Color> colors;
  final int? selected;
  final Color surface;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - thickness / 2 - 2;
    if (radius <= 0) return;

    // A folga de 2px entre fatias é o separador — nunca uma borda desenhada
    // em volta da fatia. Convertida de pixels para ângulo no raio médio.
    final gap = 2.0 / radius;

    var start = -math.pi / 2;

    for (var i = 0; i < slices.length; i++) {
      final sweep = (slices[i].value / total) * 2 * math.pi;
      final isSel = selected == i;

      // Fatia estreita não sobreviveria ao recorte da folga: desenha inteira.
      final podeFolga = sweep > gap * 2;
      final s = podeFolga ? start + gap / 2 : start;
      final sw = podeFolga ? sweep - gap : sweep;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? thickness + 6 : thickness
        ..strokeCap = StrokeCap.butt
        ..color = colors[i];

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        s,
        sw,
        false,
        paint,
      );

      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.selected != selected ||
      old.total != total ||
      old.slices.length != slices.length ||
      !listEquals(old.colors, colors);
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.total,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Slice slice;
  final double total;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        // Alvo de toque confortável, bem maior que a marca colorida.
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                slice.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // O texto usa tinta de texto, nunca a cor da série — a marca
                // colorida ao lado é que carrega a identidade.
                style: text.bodyMedium?.copyWith(
                  color: viz.inkPrimary,
                  fontStyle: slice.isOther ? FontStyle.italic : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              porcento(slice.value / total),
              style: text.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              dinheiro(slice.value, casas: 0),
              style: text.bodyMedium?.copyWith(
                color: viz.inkPrimary,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
