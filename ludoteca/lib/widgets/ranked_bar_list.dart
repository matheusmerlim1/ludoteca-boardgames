import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../stats/cost_stats.dart';
import '../theme.dart';
import 'chart_card.dart';

/// Ranking de jogos em barras horizontais.
///
/// Uma série, uma cor (slot 1). O valor vem rotulado em toda linha de
/// propósito: aqui a "barra" é essencialmente uma tabela com régua, então o
/// número precisa estar legível sem tocar em nada.
class RankedBarList extends StatelessWidget {
  const RankedBarList({
    super.key,
    required this.title,
    this.subtitle,
    required this.items,
    required this.format,
    this.emptyMessage = 'Nada para mostrar ainda.',
    this.onTapGame,
    this.colorSlot = 0,
  });

  final String title;
  final String? subtitle;
  final List<RankedGame> items;

  /// Como escrever o valor (dinheiro, contagem...).
  final String Function(double) format;

  final String emptyMessage;
  final void Function(int gameId)? onTapGame;
  final int colorSlot;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    if (items.isEmpty) {
      return ChartCard(
        title: title,
        subtitle: subtitle,
        child: Text(emptyMessage, style: text.bodySmall),
      );
    }

    final maxValor = items.fold<double>(0, (m, i) => math.max(m, i.value));

    return ChartCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        children: [
          for (final item in items)
            _Row(
              item: item,
              max: maxValor,
              color: viz.serie(colorSlot),
              label: format(item.value),
              onTap: onTapGame == null
                  ? null
                  : () => onTapGame!(item.entry.id),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.max,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final RankedGame item;
  final double max;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    final fracao = max <= 0 ? 0.0 : (item.value / max).clamp(0.02, 1.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: viz.inkPrimary),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: text.bodyMedium?.copyWith(
                    color: viz.inkPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Trilha + barra. A ponta arredondada fica só na extremidade do
            // dado; a origem continua reta, ancorada na linha de base.
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  Container(height: 6, color: viz.gridline),
                  FractionallySizedBox(
                    widthFactor: fracao,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(item.detail, style: text.labelSmall?.copyWith(color: viz.inkMuted)),
          ],
        ),
      ),
    );
  }
}
