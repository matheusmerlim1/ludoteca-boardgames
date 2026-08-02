import 'package:sqflite/sqflite.dart';

import '../models/game.dart';
import '../models/play.dart';
import '../models/play_score.dart';
import '../utils/format.dart';
import '../services/game_catalog.dart';
import 'database.dart';

/// Uma etiqueta com quantos jogos a usam.
class TagCount {
  const TagCount({
    required this.id,
    required this.name,
    required this.kind,
    required this.gameCount,
  });

  final int id;
  final String name;
  final TagKind kind;
  final int gameCount;
}

/// Todo acesso ao banco passa por aqui. As telas nunca falam SQL.
class GameRepository {
  GameRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db => _database.db;

  // ---------------------------------------------------------------- leitura

  /// Carrega a coleção inteira já com os números derivados.
  ///
  /// São três consultas agregadas em vez de um `COUNT` por jogo, para a lista
  /// não degradar conforme o histórico de partidas cresce.
  Future<List<GameEntry>> loadEntries() async {
    final db = await _db;

    final gameRows = await db.query('games', orderBy: 'name COLLATE NOCASE');

    // COUNT(duration_minutes) conta só as linhas com valor não nulo — é
    // exatamente "quantas partidas eu cronometrei".
    final playRows = await db.rawQuery('''
      SELECT game_id,
             COUNT(*)                          AS total,
             MAX(played_at)                    AS ultima,
             COUNT(duration_minutes)           AS com_duracao,
             COALESCE(SUM(duration_minutes),0) AS minutos
      FROM plays
      GROUP BY game_id
    ''');

    // `sold = 0`: o custo somado ao jogo-base é o que ainda está na estante.
    // Expansão vendida não deve inflar o investimento atual dele.
    final expansionRows = await db.rawQuery('''
      SELECT parent_id,
             COUNT(*) AS total,
             SUM(price + sleeve_cost + accessory_cost) AS custo
      FROM games
      WHERE parent_id IS NOT NULL AND sold = 0
      GROUP BY parent_id
    ''');

    final plays =
        <int, ({int total, DateTime? ultima, int comDuracao, int minutos})>{};
    for (final r in playRows) {
      plays[r['game_id'] as int] = (
        total: (r['total'] as int?) ?? 0,
        ultima: DateTime.tryParse((r['ultima'] as String?) ?? ''),
        comDuracao: (r['com_duracao'] as int?) ?? 0,
        minutos: ((r['minutos'] as num?) ?? 0).toInt(),
      );
    }

    final expansions = <int, ({int total, double custo})>{};
    for (final r in expansionRows) {
      expansions[r['parent_id'] as int] = (
        total: (r['total'] as int?) ?? 0,
        custo: (r['custo'] as num?)?.toDouble() ?? 0,
      );
    }

    return gameRows.map((row) {
      final game = Game.fromMap(row);
      final pl = plays[game.id];
      final ex = expansions[game.id];
      return GameEntry(
        game: game,
        loggedPlays: pl?.total ?? 0,
        lastLoggedPlay: pl?.ultima,
        loggedPlaysWithDuration: pl?.comDuracao ?? 0,
        loggedMinutes: pl?.minutos ?? 0,
        expansionCount: ex?.total ?? 0,
        expansionCost: ex?.custo ?? 0,
      );
    }).toList();
  }

  Future<Game?> gameById(int id) async {
    final db = await _db;
    final rows = await db.query('games', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Game.fromMap(rows.first);
  }

  /// Usado para avisar antes de cadastrar o mesmo jogo do BGG duas vezes.
  Future<Game?> findByBggId(int bggId) async {
    final db = await _db;
    final rows = await db.query(
      'games',
      where: 'bgg_id = ?',
      whereArgs: [bggId],
      limit: 1,
    );
    return rows.isEmpty ? null : Game.fromMap(rows.first);
  }

  Future<List<Play>> playsFor(int gameId) async {
    final db = await _db;
    final rows = await db.query(
      'plays',
      where: 'game_id = ?',
      whereArgs: [gameId],
      orderBy: 'played_at DESC, id DESC',
    );
    return rows.map(Play.fromMap).toList();
  }

  /// Todas as partidas, mais recentes primeiro. Alimenta a linha do tempo.
  Future<List<Play>> allPlays() async {
    final db = await _db;
    final rows = await db.query('plays', orderBy: 'played_at DESC, id DESC');
    return rows.map(Play.fromMap).toList();
  }

  // ---------------------------------------------------------------- escrita

  Future<int> insertGame(Game game) async {
    final db = await _db;
    final map = game.toMap()..remove('id');
    return db.insert('games', map);
  }

  Future<void> updateGame(Game game) async {
    assert(game.id != null, 'updateGame precisa de um jogo já salvo');
    final db = await _db;
    await db.update(
      'games',
      game.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [game.id],
    );
  }

  /// Remove o jogo. As partidas vão junto (ON DELETE CASCADE) e as expansões
  /// ficam órfãs em vez de desaparecerem (ON DELETE SET NULL).
  Future<void> deleteGame(int id) async {
    final db = await _db;
    await db.delete('games', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertPlay(Play play) async {
    final db = await _db;
    final map = play.toMap()..remove('id');
    return db.insert('plays', map);
  }

  Future<void> updatePlay(Play play) async {
    assert(play.id != null, 'updatePlay precisa de uma partida já salva');
    final db = await _db;
    await db.update(
      'plays',
      play.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [play.id],
    );
  }

  Future<void> deletePlay(int id) async {
    final db = await _db;
    await db.delete('plays', where: 'id = ?', whereArgs: [id]);
  }

  /// Insere vários jogos de uma vez (importação da planilha). Numa transação,
  /// para não deixar meia coleção gravada se algo falhar no meio.
  Future<void> insertGamesBatch(List<Game> games) async {
    final db = await _db;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final g in games) {
        batch.insert('games', g.toMap()..remove('id'));
      }
      await batch.commit(noResult: true);
    });
  }

  // --------------------------------------------------------------- placares

  Future<List<PlayScore>> scoresFor(int playId) async {
    final db = await _db;
    final rows = await db.query(
      'play_scores',
      where: 'play_id = ?',
      whereArgs: [playId],
      orderBy: 'won DESC, score DESC, player_name COLLATE NOCASE',
    );
    return rows.map(PlayScore.fromMap).toList();
  }

  /// Placares de várias partidas de uma vez, para a ficha não fazer uma
  /// consulta por linha do histórico.
  Future<Map<int, List<PlayScore>>> scoresForPlays(List<int> playIds) async {
    if (playIds.isEmpty) return const {};
    final db = await _db;

    final marcadores = List.filled(playIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM play_scores WHERE play_id IN ($marcadores) '
      'ORDER BY won DESC, score DESC, player_name COLLATE NOCASE',
      playIds,
    );

    final out = <int, List<PlayScore>>{};
    for (final r in rows) {
      final s = PlayScore.fromMap(r);
      (out[s.playId!] ??= <PlayScore>[]).add(s);
    }
    return out;
  }

  /// Substitui o placar de uma partida.
  Future<void> setScores(int playId, List<PlayScore> scores) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('play_scores', where: 'play_id = ?', whereArgs: [playId]);
      for (final s in scores) {
        if (s.playerName.trim().isEmpty) continue;
        await txn.insert('play_scores', {
          'play_id': playId,
          'player_name': s.playerName.trim(),
          'score': s.score,
          'won': s.won ? 1 : 0,
        });
      }
    });
  }

  /// Nomes já usados, dos mais frequentes para os menos.
  ///
  /// Alimenta a sugestão ao anotar o placar: você joga quase sempre com as
  /// mesmas pessoas, e redigitar os nomes toda vez é atrito puro.
  Future<List<String>> playerNames() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT player_name, COUNT(*) AS total
      FROM play_scores
      GROUP BY player_name COLLATE NOCASE
      ORDER BY total DESC, player_name COLLATE NOCASE
      LIMIT 30
    ''');
    return rows.map((r) => r['player_name'] as String).toList();
  }

  // -------------------------------------------------------------- saída

  /// Marca a saída do jogo da coleção.
  ///
  /// Numa **troca**, o valor investido migra para o jogo que entrou: ele foi
  /// pago com o que você já tinha, e sem transferir isso o novo jogo nasceria
  /// com custo zero e um custo por partida irreal.
  Future<void> registrarSaida({
    required Game jogo,
    required Disposal tipo,
    double? valorRecebido,
    DateTime? quando,
    int? trocadoPorId,
  }) async {
    final db = await _db;

    await db.transaction((txn) async {
      await txn.update(
        'games',
        {
          'disposal_kind': tipo.dbValue,
          'traded_for_id': tipo == Disposal.trocado ? trocadoPorId : null,
          'sold': 1,
          'sold_price': tipo == Disposal.vendido ? valorRecebido : null,
          'sold_date': isoData(quando ?? DateTime.now()),
        },
        where: 'id = ?',
        whereArgs: [jogo.id],
      );

      if (tipo != Disposal.trocado || trocadoPorId == null) return;

      final destino = await txn.query(
        'games',
        where: 'id = ?',
        whereArgs: [trocadoPorId],
        limit: 1,
      );
      if (destino.isEmpty) return;

      final novo = Game.fromMap(destino.first);
      await txn.update(
        'games',
        {'price': novo.price + jogo.totalInvested},
        where: 'id = ?',
        whereArgs: [trocadoPorId],
      );
    });
  }

  /// Desfaz a saída e devolve o jogo para a estante.
  ///
  /// Numa troca desfeita, o valor volta do jogo que tinha entrado — senão o
  /// dinheiro apareceria contado duas vezes.
  Future<void> desfazerSaida(Game jogo) async {
    final db = await _db;

    await db.transaction((txn) async {
      if (jogo.disposal == Disposal.trocado && jogo.tradedForId != null) {
        final destino = await txn.query(
          'games',
          where: 'id = ?',
          whereArgs: [jogo.tradedForId],
          limit: 1,
        );
        if (destino.isNotEmpty) {
          final novo = Game.fromMap(destino.first);
          final devolvido = novo.price - jogo.totalInvested;
          await txn.update(
            'games',
            {'price': devolvido < 0 ? 0.0 : devolvido},
            where: 'id = ?',
            whereArgs: [jogo.tradedForId],
          );
        }
      }

      await txn.update(
        'games',
        {
          'disposal_kind': null,
          'traded_for_id': null,
          'sold': 0,
          'sold_price': null,
          'sold_date': null,
        },
        where: 'id = ?',
        whereArgs: [jogo.id],
      );
    });
  }

  // ------------------------------------------------------------------- tags

  /// Todas as etiquetas usadas, com quantos jogos cada uma tem.
  ///
  /// Sai já ordenado por uso: numa lista de dezenas de temas, os seus três
  /// temas frequentes têm de estar no topo, não em ordem alfabética no meio.
  Future<List<TagCount>> loadTags() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT t.id, t.name, t.kind, COUNT(gt.game_id) AS total
      FROM tags t
      JOIN game_tags gt ON gt.tag_id = t.id
      JOIN games g      ON g.id = gt.game_id AND g.sold = 0
      GROUP BY t.id
      ORDER BY total DESC, t.name COLLATE NOCASE
    ''');

    return rows
        .map((r) => TagCount(
              id: r['id'] as int,
              name: r['name'] as String,
              kind: TagKind.fromDb(r['kind'] as String?),
              gameCount: (r['total'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Quais etiquetas cada jogo tem, para a lista filtrar sem ir ao banco.
  Future<Map<int, Set<int>>> loadGameTagIds() async {
    final db = await _db;
    final rows = await db.query('game_tags');
    final out = <int, Set<int>>{};
    for (final r in rows) {
      final g = r['game_id'] as int;
      (out[g] ??= <int>{}).add(r['tag_id'] as int);
    }
    return out;
  }

  /// Substitui as etiquetas de um jogo.
  ///
  /// Cria as que ainda não existem. `INSERT OR IGNORE` no lugar de consultar
  /// antes: a corrida entre "existe?" e "insere" não vale o código a mais, e a
  /// restrição de unicidade já resolve.
  Future<void> setGameTags(int gameId, List<CatalogTag> tags) async {
    final db = await _db;

    await db.transaction((txn) async {
      await txn.delete('game_tags', where: 'game_id = ?', whereArgs: [gameId]);

      for (final t in tags) {
        final nome = t.name.trim();
        if (nome.isEmpty) continue;

        await txn.insert(
          'tags',
          {'name': nome, 'kind': t.kind.dbValue},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        final achou = await txn.query(
          'tags',
          columns: ['id'],
          where: 'name = ? AND kind = ?',
          whereArgs: [nome, t.kind.dbValue],
          limit: 1,
        );
        if (achou.isEmpty) continue;

        await txn.insert(
          'game_tags',
          {'game_id': gameId, 'tag_id': achou.first['id']},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<List<CatalogTag>> tagsFor(int gameId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT t.name, t.kind
      FROM tags t
      JOIN game_tags gt ON gt.tag_id = t.id
      WHERE gt.game_id = ?
      ORDER BY t.kind, t.name COLLATE NOCASE
    ''', [gameId]);

    return rows
        .map((r) => CatalogTag(
              name: r['name'] as String,
              kind: TagKind.fromDb(r['kind'] as String?),
            ))
        .toList();
  }

  Future<List<Game>> allGames() async {
    final db = await _db;
    final rows = await db.query('games', orderBy: 'name COLLATE NOCASE');
    return rows.map(Game.fromMap).toList();
  }

  /// Jogos que ainda não têm etiqueta nenhuma — o alvo do preenchimento em
  /// lote.
  Future<List<Game>> gamesWithoutTags() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT g.* FROM games g
      WHERE NOT EXISTS (SELECT 1 FROM game_tags gt WHERE gt.game_id = g.id)
      ORDER BY g.name COLLATE NOCASE
    ''');
    return rows.map(Game.fromMap).toList();
  }

  // --------------------------------------------------------------- settings

  /// Chaves usadas na tabela `settings`.
  static const keyBggToken = 'bgg_token';

  /// Nome de usuário no Comparajogos, para ler as listas públicas dele.
  static const keyComparajogosUser = 'comparajogos_user';

  Future<String?> getSetting(String key) async {
    final db = await _db;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final v = rows.first['value'] as String?;
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Grava a chave. Passar nulo ou vazio remove a linha, para "não
  /// configurado" e "configurado com string vazia" não serem estados
  /// diferentes.
  Future<void> setSetting(String key, String? value) async {
    final db = await _db;
    if (value == null || value.trim().isEmpty) {
      await db.delete('settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await db.insert(
      'settings',
      {'key': key, 'value': value.trim()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------- backup

  /// Snapshot da coleção, pronto para virar JSON.
  ///
  /// **A tabela `settings` fica fora de propósito.** Ela guarda o token da API
  /// do BGG, e o arquivo de backup é feito para sair do aparelho — vai para o
  /// Drive, para o e-mail, para o WhatsApp. Credencial não viaja nisso. Pelo
  /// mesmo motivo a restauração não apaga `settings`: o token sobrevive.
  Future<Map<String, Object?>> exportAll() async {
    final db = await _db;
    final games = await db.query('games');
    final plays = await db.query('plays');
    return {
      'schema': 1,
      'exportado_em': DateTime.now().toIso8601String(),
      'jogos': games,
      'partidas': plays,
    };
  }

  /// Substitui a coleção inteira pelo conteúdo do backup.
  ///
  /// Preserva os ids originais para os vínculos de expansão (`parent_id`) e de
  /// partida (`game_id`) continuarem apontando para o lugar certo.
  Future<({int jogos, int partidas})> importAll(
    Map<String, Object?> data,
  ) async {
    final jogos = (data['jogos'] as List?) ?? const [];
    final partidas = (data['partidas'] as List?) ?? const [];

    final db = await _db;
    var nJogos = 0;
    var nPartidas = 0;

    await db.transaction((txn) async {
      await txn.delete('plays');
      await txn.delete('games');

      // Duas passadas: primeiro todos os jogos sem vínculo, depois os
      // `parent_id`. Religar durante a inserção estouraria a chave
      // estrangeira quando a expansão aparece antes do jogo-base no arquivo.
      final vinculos = <int, Object>{};

      for (final raw in jogos) {
        final m = Map<String, Object?>.from(raw as Map);
        final parent = m.remove('parent_id');
        await txn.insert('games', m);
        if (parent != null && m['id'] != null) {
          vinculos[m['id'] as int] = parent;
        }
        nJogos++;
      }

      for (final entry in vinculos.entries) {
        await txn.update(
          'games',
          {'parent_id': entry.value},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }

      for (final raw in partidas) {
        await txn.insert('plays', Map<String, Object?>.from(raw as Map));
        nPartidas++;
      }
    });

    return (jogos: nJogos, partidas: nPartidas);
  }
}
