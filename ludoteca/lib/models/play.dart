import '../utils/format.dart';

/// Uma partida registrada.
class Play {
  const Play({
    this.id,
    required this.gameId,
    required this.playedAt,
    this.players,
    this.winner,
    this.notes,
    this.durationMinutes,
    this.itemGameId,
  });

  final int? id;
  final int gameId;
  final DateTime playedAt;

  /// Quantas pessoas jogaram.
  final int? players;
  final String? winner;
  final String? notes;

  /// Quanto a partida durou, em minutos.
  ///
  /// **Nulo é o caso normal**, não uma falha de preenchimento: significa "não
  /// cronometrei". Quem for calcular horas jogadas usa a duração média do jogo
  /// no lugar. Preencher é opcional e existe para quando você quiser o número
  /// exato — cronometrar toda partida seria trabalho demais para o retorno.
  final int? durationMinutes;

  /// Qual caixa do grupo foi jogada, quando o jogo agrupa vários itens.
  ///
  /// Nulo significa "o jogo em si" ou "não quis detalhar" — nunca é erro
  /// deixar em branco. Serve para, num Unmatched com seis caixas, saber qual
  /// delas realmente vai à mesa.
  final int? itemGameId;

  /// Se esta partida tem duração medida em vez de estimada.
  bool get hasMeasuredDuration =>
      durationMinutes != null && durationMinutes! > 0;

  Play copyWith({
    int? id,
    int? gameId,
    DateTime? playedAt,
    int? players,
    String? winner,
    String? notes,
    int? durationMinutes,
    bool clearDuration = false,
    int? itemGameId,
    bool clearItemGame = false,
  }) {
    return Play(
      id: id ?? this.id,
      gameId: gameId ?? this.gameId,
      playedAt: playedAt ?? this.playedAt,
      players: players ?? this.players,
      winner: winner ?? this.winner,
      notes: notes ?? this.notes,
      durationMinutes:
          clearDuration ? null : (durationMinutes ?? this.durationMinutes),
      itemGameId: clearItemGame ? null : (itemGameId ?? this.itemGameId),
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'game_id': gameId,
        'played_at': isoData(playedAt),
        'players': players,
        'winner': winner,
        'notes': notes,
        'duration_minutes': durationMinutes,
        'item_game_id': itemGameId,
      };

  factory Play.fromMap(Map<String, Object?> m) => Play(
        id: m['id'] as int?,
        gameId: m['game_id'] as int,
        playedAt: parseIsoData(m['played_at'] as String?) ?? DateTime.now(),
        players: m['players'] as int?,
        winner: m['winner'] as String?,
        notes: m['notes'] as String?,
        durationMinutes: m['duration_minutes'] as int?,
        itemGameId: m['item_game_id'] as int?,
      );

  Map<String, Object?> toJson() => toMap();

  factory Play.fromJson(Map<String, Object?> j) => Play.fromMap(j);
}
