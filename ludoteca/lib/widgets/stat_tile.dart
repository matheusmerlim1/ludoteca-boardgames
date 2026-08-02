import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Um número que se explica sozinho.
///
/// Quando a história é *um número*, um número é o gráfico certo — não uma
/// pizza de duas fatias nem uma barra solitária.
///
/// O valor usa figuras proporcionais (o padrão da fonte). `tabular-nums` em
/// número grande deixa dígitos estreitos com folga sobrando e faz "121"
/// parecer frouxo; alinhamento tabular é para colunas de tabela.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.accentSlot,
    this.onTap,
  });

  final String label;
  final String value;
  final String? hint;

  /// Marca colorida opcional. É identidade visual, não semântica de estado.
  final int? accentSlot;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (accentSlot != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: viz.serie(accentSlot!),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(color: viz.inkSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: text.headlineSmall?.copyWith(fontSize: 23),
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 3),
                Text(
                  hint!,
                  maxLines: 2,
                  style: text.labelSmall?.copyWith(color: viz.inkMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Grade de stat tiles que se adapta à largura, sem altura fixa por linha.
class StatTileGrid extends StatelessWidget {
  const StatTileGrid({super.key, required this.tiles, this.minTileWidth = 158});

  final List<Widget> tiles;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final colunas =
            math.max(1, ((constraints.maxWidth + gap) / (minTileWidth + gap)).floor());
        final largura =
            (constraints.maxWidth - gap * (colunas - 1)) / colunas;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: largura, child: t),
          ],
        );
      },
    );
  }
}
