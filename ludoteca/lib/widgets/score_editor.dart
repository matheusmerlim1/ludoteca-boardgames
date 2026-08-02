import 'package:flutter/material.dart';

import '../models/play_score.dart';
import '../theme.dart';
import '../utils/format.dart';

/// Uma linha em edição: os controladores vivem aqui para o texto não sumir a
/// cada rebuild.
class _Linha {
  _Linha({String nome = '', String pontos = '', this.venceu = false})
      : nome = TextEditingController(text: nome),
        pontos = TextEditingController(text: pontos);

  final TextEditingController nome;
  final TextEditingController pontos;
  bool venceu;

  void dispose() {
    nome.dispose();
    pontos.dispose();
  }

  PlayScore paraModelo() => PlayScore(
        playerName: nome.text.trim(),
        score: parseMoeda(pontos.text),
        won: venceu,
      );
}

/// Quem jogou, quantos pontos fez e quem venceu.
///
/// Tudo opcional de propósito. Muito jogo não tem placar, e cooperativo não
/// tem vencedor individual — exigir os campos travaria o lançamento rápido,
/// que é o caso mais comum.
class ScoreEditor extends StatefulWidget {
  const ScoreEditor({
    super.key,
    required this.inicial,
    required this.sugestoes,
    required this.onChanged,
  });

  final List<PlayScore> inicial;

  /// Nomes já usados antes, para não redigitar sempre os mesmos.
  final List<String> sugestoes;

  final ValueChanged<List<PlayScore>> onChanged;

  @override
  State<ScoreEditor> createState() => _ScoreEditorState();
}

class _ScoreEditorState extends State<ScoreEditor> {
  late List<_Linha> _linhas;

  @override
  void initState() {
    super.initState();
    _linhas = widget.inicial
        .map((s) => _Linha(
              nome: s.playerName,
              pontos: s.score == null ? '' : dinheiro(s.score!, simbolo: false),
              venceu: s.won,
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final l in _linhas) {
      l.dispose();
    }
    super.dispose();
  }

  void _avisa() => widget.onChanged(
        _linhas
            .map((l) => l.paraModelo())
            .where((s) => s.playerName.isNotEmpty)
            .toList(),
      );

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Placar (opcional)', style: text.labelSmall),
            const Spacer(),
            if (_linhas.any((l) => l.pontos.text.trim().isNotEmpty))
              TextButton(
                onPressed: _marcarMaiorPontuacao,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Quem fez mais pontos venceu'),
              ),
          ],
        ),
        const SizedBox(height: 4),

        for (var i = 0; i < _linhas.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // A coroa é o marcador de vencedor. Em cooperativo, marcar
                // todo mundo é uma leitura legítima — por isso não é exclusivo.
                IconButton(
                  onPressed: () => setState(() {
                    _linhas[i].venceu = !_linhas[i].venceu;
                    _avisa();
                  }),
                  icon: Icon(
                    _linhas[i].venceu
                        ? Icons.emoji_events
                        : Icons.emoji_events_outlined,
                    size: 20,
                    color: _linhas[i].venceu ? viz.serie(3) : viz.inkMuted,
                  ),
                  tooltip: 'Venceu',
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _linhas[i].nome,
                    onChanged: (_) => _avisa(),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Nome',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _linhas[i].pontos,
                    onChanged: (_) => setState(_avisa),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      hintText: 'Pontos',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _linhas.removeAt(i).dispose();
                    _avisa();
                  }),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Tirar',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _linhas.add(_Linha())),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Adicionar jogador'),
          ),
        ),

        // Você joga quase sempre com as mesmas pessoas; um toque evita
        // redigitar o nome inteiro no teclado do celular.
        if (widget.sugestoes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final nome in widget.sugestoes)
                if (!_linhas.any((l) =>
                    normalizaNome(l.nome.text) == normalizaNome(nome)))
                  ActionChip(
                    label: Text(nome),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: () => setState(() {
                      _linhas.add(_Linha(nome: nome));
                      _avisa();
                    }),
                  ),
            ],
          ),
        ],
      ],
    );
  }

  /// Marca como vencedor quem fez mais pontos.
  ///
  /// É um botão e não algo automático: em cooperativo, ou em jogo de menor
  /// pontuação, "mais pontos" não é vitória. Quem sabe disso é você.
  void _marcarMaiorPontuacao() {
    final atual = _linhas.map((l) => l.paraModelo()).toList();
    final maior = atual.maiorPontuacao;
    if (maior == null) return;

    setState(() {
      for (var i = 0; i < _linhas.length; i++) {
        final p = parseMoeda(_linhas[i].pontos.text);
        _linhas[i].venceu = p != null && p == maior;
      }
      _avisa();
    });
  }
}
