/// A pontuação de um jogador numa partida.
///
/// Tabela própria em vez de um texto solto na partida: assim dá para perguntar
/// quem mais ganha e qual foi a maior pontuação, em vez de só reler uma
/// anotação.
class PlayScore {
  const PlayScore({
    this.id,
    this.playId,
    required this.playerName,
    this.score,
    this.won = false,
  });

  final int? id;

  /// Nulo enquanto a partida ainda não foi salva.
  final int? playId;

  final String playerName;

  /// Pontos. Nulo é legítimo: muito jogo não tem placar, e zero seria mentira
  /// diferente de "não anotei".
  final double? score;

  final bool won;

  PlayScore copyWith({
    int? id,
    int? playId,
    String? playerName,
    double? score,
    bool? won,
    bool clearScore = false,
  }) {
    return PlayScore(
      id: id ?? this.id,
      playId: playId ?? this.playId,
      playerName: playerName ?? this.playerName,
      score: clearScore ? null : (score ?? this.score),
      won: won ?? this.won,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'play_id': playId,
        'player_name': playerName,
        'score': score,
        'won': won ? 1 : 0,
      };

  factory PlayScore.fromMap(Map<String, Object?> m) => PlayScore(
        id: m['id'] as int?,
        playId: m['play_id'] as int?,
        playerName: (m['player_name'] as String?) ?? '',
        score: (m['score'] as num?)?.toDouble(),
        won: (m['won'] as int? ?? 0) == 1,
      );

  Map<String, Object?> toJson() => toMap();
  factory PlayScore.fromJson(Map<String, Object?> j) => PlayScore.fromMap(j);
}

/// Ajuda a ler um placar já preenchido.
extension PlacarDaPartida on List<PlayScore> {
  /// Quem venceu. Pode ser mais de um — empate acontece.
  List<PlayScore> get vencedores => where((s) => s.won).toList();

  /// Maior pontuação anotada, quando alguém anotou.
  double? get maiorPontuacao {
    final comPontos = where((s) => s.score != null).map((s) => s.score!);
    if (comPontos.isEmpty) return null;
    return comPontos.reduce((a, b) => a > b ? a : b);
  }

  /// Marca como vencedor quem fez mais pontos.
  ///
  /// Só serve quando ganhar é fazer mais pontos — em jogo cooperativo, ou de
  /// menor pontuação, quem decide é o usuário. Por isso é uma ação explícita
  /// na tela, não algo que acontece sozinho ao digitar.
  List<PlayScore> comVencedorPorPontuacao() {
    final maior = maiorPontuacao;
    if (maior == null) return this;
    return map((s) => s.copyWith(won: s.score != null && s.score == maior))
        .toList();
  }
}
