import 'package:flutter/material.dart';

import '../models/game.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'game_cover.dart';

/// Uma linha da coleção.
///
/// Em linha e não em grade de propósito: o que a planilha respondia — para
/// quantos jogadores serve, quantas vezes jogou, quando foi a última — é
/// texto, e numa grade de capas isso não cabe.
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.highlightPlayerCount,
  });

  final GameEntry entry;
  final VoidCallback onTap;

  /// Quando o filtro "serve para N" está ativo, N aparece marcado.
  final int? highlightPlayerCount;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final game = entry.game;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 54,
              height: 68,
              child: GameCover(
                url: game.thumbUrl ?? game.imageUrl,
                name: game.displayName,
                borderRadius: 8,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          game.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: game.sold ? viz.inkMuted : viz.inkPrimary,
                            decoration:
                                game.sold ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (game.linkLabel != null) _Tag(texto: game.linkLabel!),
                      if (game.sold) const _Tag(texto: 'vendido'),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Com o filtro "serve para N" ativo, um tique confirma
                      // por que este jogo apareceu na lista.
                      if (highlightPlayerCount != null &&
                          game.supportsPlayerCount(highlightPlayerCount!)) ...[
                        Icon(Icons.check, size: 13, color: viz.good),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          [
                            faixaJogadores(game.minPlayers, game.maxPlayers),
                            if (game.minPlaytime != null ||
                                game.maxPlaytime != null)
                              faixaDuracao(game.minPlaytime, game.maxPlaytime),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _PlayLine(entry: entry),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 20, color: viz.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// Contagem de partidas + quando foi a última.
class _PlayLine extends StatelessWidget {
  const _PlayLine({required this.entry});

  final GameEntry entry;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;

    if (entry.neverPlayed) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 13, color: viz.inkMuted),
          const SizedBox(width: 4),
          Text(
            'nunca jogado',
            style: TextStyle(fontSize: 12.5, color: viz.inkMuted),
          ),
        ],
      );
    }

    return Text(
      '${contagemPartidas(entry.playCount)} · '
      'última ${desdeQuando(entry.lastPlayed)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12.5, color: viz.inkSecondary),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: viz.gridline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 10, color: viz.inkMuted),
      ),
    );
  }
}
