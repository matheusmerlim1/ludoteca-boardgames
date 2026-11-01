import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/collection_store.dart';
import '../utils/format.dart';
import 'log_play_sheet.dart';

/// Tempo decorrido no formato do relógio: "0:07:42", "1:40:05".
String relogio(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, seg = s % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${seg.toString().padLeft(2, '0')}';
}

/// Minutos a gravar de um cronômetro: arredonda, e no mínimo 1 — uma partida
/// encerrada aos 30 segundos ainda é uma partida.
int minutosDoCronometro(DateTime inicio, DateTime fim) {
  final m = (fim.difference(inicio).inSeconds / 60).round();
  return m < 1 ? 1 : m;
}

/// Texto do tempo decorrido desde [inicio], atualizado a cada segundo.
class TempoDecorrido extends StatefulWidget {
  const TempoDecorrido({super.key, required this.inicio, this.style});

  final DateTime inicio;
  final TextStyle? style;

  @override
  State<TempoDecorrido> createState() => _TempoDecorridoState();
}

class _TempoDecorridoState extends State<TempoDecorrido> {
  late final Timer _tique;

  @override
  void initState() {
    super.initState();
    _tique = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tique.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      relogio(DateTime.now().difference(widget.inicio)),
      style: widget.style
          ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

/// Liga o cronômetro para o jogo. Se outro jogo já estiver sendo
/// cronometrado, pergunta antes de trocar.
Future<void> iniciarCronometro(BuildContext context, int gameId) async {
  final store = context.read<CollectionStore>();
  final atual = store.partidaEmAndamento;
  if (atual != null && atual.gameId != gameId) {
    final nome = store.entryById(atual.gameId)?.displayName ?? 'outro jogo';
    final trocar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Já há uma partida cronometrada'),
        content: Text('O cronômetro de $nome está ligado. Descartar o tempo '
            'dele e começar este?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Manter'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trocar'),
          ),
        ],
      ),
    );
    if (trocar != true) return;
  }
  await store.iniciarCronometro(gameId);
}

/// Para o cronômetro e abre a folha de registro com a data do início e os
/// minutos medidos. Cancelar a folha deixa o cronômetro correndo.
///
/// Devolve `true` quando a partida foi registrada.
Future<bool> finalizarCronometro(BuildContext context) async {
  final store = context.read<CollectionStore>();
  final atual = store.partidaEmAndamento;
  if (atual == null) return false;
  final entry = store.entryById(atual.gameId);
  if (entry == null) {
    // O jogo foi removido com o cronômetro ligado: não há onde registrar.
    await store.encerrarCronometro();
    return false;
  }

  final minutos = minutosDoCronometro(atual.inicio, DateTime.now());
  final sugestoes = await store.playerNames();
  if (!context.mounted) return false;

  final r = await LogPlaySheet.show(
    context,
    game: entry.game,
    itens: store.expansionsOf(entry.id).map((e) => e.game).toList(),
    sugestoesDeNome: sugestoes,
    duracaoInicial: minutos,
    dataInicial: atual.inicio,
  );
  if (r == null || !context.mounted) return false;

  final playId = await store.logPlay(r.play, placar: r.placar);
  await store.encerrarCronometro();
  if (!context.mounted) return true;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Partida de ${entry.displayName} registrada'
          '${r.play.durationMinutes == null ? '' : ' (${duracao(r.play.durationMinutes!)})'}.'),
      duration: const Duration(seconds: 2),
      persist: false,
      action: SnackBarAction(
        label: 'Desfazer',
        onPressed: () => store.deletePlay(playId),
      ),
    ),
  );
  return true;
}

/// Faixa que aparece acima da navegação enquanto há partida cronometrada:
/// o jogo, o tempo correndo e os botões de finalizar e descartar.
class PartidaEmAndamentoBar extends StatelessWidget {
  const PartidaEmAndamentoBar({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CollectionStore>();
    final atual = store.partidaEmAndamento;
    if (atual == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final nome = store.entryById(atual.gameId)?.displayName ?? 'Partida';

    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, color: scheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium
                          ?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                    TempoDecorrido(
                      inicio: atual.inicio,
                      style: text.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Descartar cronômetro',
                icon: const Icon(Icons.close),
                color: scheme.onPrimaryContainer,
                onPressed: () => _descartar(context, nome),
              ),
              FilledButton(
                onPressed: () => finalizarCronometro(context),
                child: const Text('Finalizar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _descartar(BuildContext context, String nome) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar o cronômetro?'),
        content: Text('O tempo da partida de $nome não será registrado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar contando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<CollectionStore>().encerrarCronometro();
    }
  }
}
