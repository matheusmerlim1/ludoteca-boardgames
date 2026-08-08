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
///
/// Mostra [visiveis] linhas e guarda o resto atrás de um "ver todos". O corte
/// é da tela, não do cálculo: a lista chega inteira, então expandir não
/// recalcula nada — e a pergunta "onde o meu está nessa lista" tem resposta.
class RankedBarList extends StatefulWidget {
  const RankedBarList({
    super.key,
    required this.title,
    this.subtitle,
    required this.items,
    required this.format,
    this.emptyMessage = 'Nada para mostrar ainda.',
    this.onTapGame,
    this.colorSlot = 0,
    this.visiveis = 8,
    this.meta,
    this.metaLabel,
    this.metaAcimaEhRuim = true,
    this.onAjustarMeta,
  });

  final String title;
  final String? subtitle;
  final List<RankedGame> items;

  /// Como escrever o valor (dinheiro, contagem...).
  final String Function(double) format;

  final String emptyMessage;
  final void Function(int gameId)? onTapGame;
  final int colorSlot;

  /// Quantas linhas antes do "ver todos".
  final int visiveis;

  /// Valor de referência da comparação — a régua que você escolheu.
  ///
  /// Com ela as barras deixam de ser medidas só entre si: o maior da lista
  /// não vira automaticamente "o ruim", e um jogo pode estar dentro da meta
  /// mesmo sendo o pior colocado.
  final double? meta;
  final String? metaLabel;

  /// Se passar da meta é problema (custo) ou conquista (horas jogadas).
  final bool metaAcimaEhRuim;

  final VoidCallback? onAjustarMeta;

  @override
  State<RankedBarList> createState() => _RankedBarListState();
}

class _RankedBarListState extends State<RankedBarList> {
  bool _tudo = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    if (widget.items.isEmpty) {
      return ChartCard(
        title: widget.title,
        subtitle: widget.subtitle,
        child: Text(widget.emptyMessage, style: text.bodySmall),
      );
    }

    final maiorValor =
        widget.items.fold<double>(0, (m, i) => math.max(m, i.value));

    // A régua vai até o maior entre o pior colocado e a meta: se a meta ficar
    // fora da escala, a linha dela sairia do gráfico e não compararia nada.
    final escala = widget.meta == null
        ? maiorValor
        : math.max(maiorValor, widget.meta!);

    final mostrados =
        _tudo ? widget.items : widget.items.take(widget.visiveis).toList();
    final escondidos = widget.items.length - mostrados.length;

    final dentro = widget.meta == null
        ? 0
        : widget.items
            .where((i) => widget.metaAcimaEhRuim
                ? i.value <= widget.meta!
                : i.value >= widget.meta!)
            .length;

    return ChartCard(
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: widget.onAjustarMeta == null
          ? null
          : IconButton(
              onPressed: widget.onAjustarMeta,
              icon: const Icon(Icons.tune, size: 20),
              tooltip: 'Ajustar a comparação',
              visualDensity: VisualDensity.compact,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.meta != null) ...[
            _FaixaDaMeta(
              label: widget.metaLabel ?? 'Meta: ${widget.format(widget.meta!)}',
              dentro: dentro,
              total: widget.items.length,
              acimaEhRuim: widget.metaAcimaEhRuim,
            ),
            const SizedBox(height: 6),
          ],
          for (final item in mostrados)
            _Row(
              item: item,
              max: escala,
              meta: widget.meta,
              // Fora da meta ganha a cor de alerta: é o que você pediu para
              // olhar, e distinguir por cor evita ter que ler linha por linha.
              color: _foraDaMeta(item) ? viz.critical : viz.serie(widget.colorSlot),
              label: widget.format(item.value),
              onTap: widget.onTapGame == null
                  ? null
                  : () => widget.onTapGame!(item.entry.id),
            ),
          if (escondidos > 0 || _tudo) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _tudo = !_tudo),
                icon: Icon(
                  _tudo ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(
                  _tudo
                      ? 'Mostrar menos'
                      : 'Ver todos os ${widget.items.length}',
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _foraDaMeta(RankedGame item) {
    final meta = widget.meta;
    if (meta == null) return false;
    return widget.metaAcimaEhRuim ? item.value > meta : item.value < meta;
  }
}

/// Uma linha dizendo quantos jogos passaram na régua que você escolheu.
class _FaixaDaMeta extends StatelessWidget {
  const _FaixaDaMeta({
    required this.label,
    required this.dentro,
    required this.total,
    required this.acimaEhRuim,
  });

  final String label;
  final int dentro;
  final int total;
  final bool acimaEhRuim;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final tudoDentro = dentro == total;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: viz.serie(0).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.straighten, size: 15, color: viz.inkSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: text.labelSmall?.copyWith(color: viz.inkPrimary),
            ),
          ),
          Text(
            tudoDentro ? 'todos passam' : '$dentro de $total',
            style: text.labelSmall?.copyWith(
              color: tudoDentro ? viz.inkSecondary : viz.critical,
              fontWeight: FontWeight.w600,
            ),
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
    required this.meta,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final RankedGame item;
  final double max;
  final double? meta;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    final fracao = max <= 0 ? 0.0 : (item.value / max).clamp(0.02, 1.0);
    final fracaoMeta =
        (meta == null || max <= 0) ? null : (meta! / max).clamp(0.0, 1.0);

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
                  // A régua atravessa todas as barras na mesma posição, que é
                  // o que deixa "passou ou não passou" visível de relance.
                  if (fracaoMeta != null)
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: fracaoMeta,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(width: 2, color: viz.inkPrimary),
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
