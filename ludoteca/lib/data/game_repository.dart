import 'package:sqflite/sqflite.dart';

import '../models/extra.dart';
import '../models/game.dart';
import '../models/play.dart';
import '../models/play_score.dart';
import '../models/suggestion.dart';
import '../models/trade.dart';
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

  /// Substitui o placar de uma partida, e guarda quem jogou.
  ///
  /// As duas coisas na mesma transação: um nome que entrou no placar mas não no
  /// cadastro não apareceria na sugestão da partida seguinte, que é justamente
  /// para o que ele serve.
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
      await registrarJogadores(
        scores.map((s) => s.playerName),
        txn: txn,
      );
    });
  }

  /// Com quem você joga, de quem mais joga para quem menos joga.
  ///
  /// Alimenta a sugestão ao anotar o placar: você joga quase sempre com as
  /// mesmas pessoas, e redigitar os nomes toda vez é atrito puro.
  ///
  /// Vem da tabela `players`, e não de um `GROUP BY` sobre as partidas, para o
  /// nome não sumir quando você apaga a partida em que ele apareceu.
  Future<List<String>> playerNames() async {
    final db = await _db;
    // A contagem sai de `play_scores` na hora, em vez de um contador guardado
    // em `players`: contador mantido à mão erra na primeira edição de partida
    // (regravar o placar somaria de novo) e o erro passa despercebido, porque
    // ele só mexe na ordem das sugestões.
    final rows = await db.rawQuery('''
      SELECT p.name AS name,
             (SELECT COUNT(*) FROM play_scores s
               WHERE s.player_name = p.name COLLATE NOCASE) AS total
      FROM players p
      -- Empate na frequência desempata por quem jogou mais recentemente: quem
      -- entrou no grupo esta semana é mais provável que quem jogou duas vezes
      -- há dois anos.
      ORDER BY total DESC, p.last_used_at DESC, p.name COLLATE NOCASE
      LIMIT 30
    ''');
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Guarda as pessoas que entraram numa partida.
  ///
  /// Idempotente por nome, sem diferenciar maiúsculas: digitar "ana" hoje e
  /// "Ana" amanhã não cria duas pessoas. Fica valendo a grafia da primeira vez.
  Future<void> registrarJogadores(
    Iterable<String> nomes, {
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await _db;
    final agora = isoData(DateTime.now());

    for (final bruto in nomes) {
      final nome = bruto.trim();
      if (nome.isEmpty) continue;

      await db.rawInsert(
        'INSERT OR IGNORE INTO players (name, last_used_at) VALUES (?, ?)',
        [nome, agora],
      );
      await db.rawUpdate(
        'UPDATE players SET last_used_at = ? WHERE name = ? COLLATE NOCASE',
        [agora, nome],
      );
    }
  }

  // -------------------------------------------------------------- saída

  /// Marca a saída do jogo da coleção.
  ///
  /// Venda e doação saem por aqui. A **troca** é encaminhada para
  /// [registrarTroca], que sabe dividir o valor entre vários jogos — este
  /// atalho de um-por-um continua existindo porque é o caso mais comum e
  /// porque a ficha do jogo já chamava assim.
  Future<void> registrarSaida({
    required Game jogo,
    required Disposal tipo,
    double? valorRecebido,
    DateTime? quando,
    int? trocadoPorId,
  }) async {
    if (tipo == Disposal.trocado) {
      await registrarTroca(
        saindo: [jogo],
        entrando: trocadoPorId == null
            ? const []
            : [TrocaEntrada(gameId: trocadoPorId)],
        quando: quando,
      );
      return;
    }

    final db = await _db;
    await db.update(
      'games',
      {
        'disposal_kind': tipo.dbValue,
        'traded_for_id': null,
        'sold': 1,
        'sold_price': tipo == Disposal.vendido ? valorRecebido : null,
        'sold_date': isoData(quando ?? DateTime.now()),
      },
      where: 'id = ?',
      whereArgs: [jogo.id],
    );
  }

  /// Registra uma troca de N jogos por M jogos.
  ///
  /// O investimento somado dos que saíram é **dividido** entre os que entraram,
  /// na proporção do que cada um vale (ver [rateio]): 500 trocados por um jogo
  /// de 300 e um de 100 deixam 375 no primeiro e 125 no segundo. O valor de
  /// referência é peso, não dinheiro pago — quem pagou a conta foi o jogo que
  /// saiu, e por isso o preço do que entrou é **substituído**, não somado.
  ///
  /// Quem entra deixa de ser desejado e ganha a data da troca como data de
  /// compra: ele está na estante desde hoje, e sem data não existe custo por
  /// mês. O estado anterior de cada ponta fica gravado em `trade_games`, que é
  /// o que [desfazerTroca] devolve.
  ///
  /// [entrando] vazio é um caso legítimo: "troquei, mas ainda não cadastrei o
  /// que recebi". Os jogos saem da estante e o valor fica esperando; apontar
  /// depois é refazer a troca.
  Future<int> registrarTroca({
    required List<Game> saindo,
    List<TrocaEntrada> entrando = const [],
    DateTime? quando,
  }) async {
    assert(saindo.isNotEmpty, 'uma troca precisa de pelo menos um jogo saindo');
    final db = await _db;
    final dia = isoData(quando ?? DateTime.now());

    return db.transaction((txn) async {
      final tradeId = await txn.insert('trades', {'traded_at': dia});

      var total = 0.0;
      for (final jogo in saindo) {
        total += jogo.totalInvested;
        await txn.update(
          'games',
          {
            'disposal_kind': Disposal.trocado.dbValue,
            // Uma ponta só, para um backup restaurado numa versão anterior
            // ainda dizer o essencial. Quem manda é `trade_games`.
            'traded_for_id': entrando.isEmpty ? null : entrando.first.gameId,
            'sold': 1,
            // Troca não devolve dinheiro; um número aqui viraria "recuperado".
            'sold_price': null,
            'sold_date': dia,
          },
          where: 'id = ?',
          whereArgs: [jogo.id],
        );
        await txn.insert('trade_games', {
          'trade_id': tradeId,
          'game_id': jogo.id,
          'side': 'saiu',
          'price_before': jogo.price,
          'ownership_before': jogo.ownership.dbValue,
          'purchase_before':
              jogo.purchaseDate == null ? null : isoData(jogo.purchaseDate!),
        });
      }

      if (entrando.isEmpty) return tradeId;

      final destinos = <Game>[];
      for (final e in entrando) {
        final linhas = await txn.query(
          'games',
          where: 'id = ?',
          whereArgs: [e.gameId],
          limit: 1,
        );
        // Jogo apagado entre escolher e confirmar: a troca continua válida
        // para os outros, em vez de falhar inteira.
        if (linhas.isNotEmpty) destinos.add(Game.fromMap(linhas.first));
      }
      if (destinos.isEmpty) return tradeId;

      final pesos = [
        for (final d in destinos)
          entrando
                  .firstWhere((e) => e.gameId == d.id)
                  .valorReferencia ??
              d.price,
      ];
      final partes = rateio(total, pesos);

      for (var i = 0; i < destinos.length; i++) {
        final d = destinos[i];
        await txn.update(
          'games',
          {
            'price': partes[i],
            'ownership': null,
            'purchase_date': d.purchaseDate == null
                ? dia
                : isoData(d.purchaseDate!),
          },
          where: 'id = ?',
          whereArgs: [d.id],
        );
        await txn.insert('trade_games', {
          'trade_id': tradeId,
          'game_id': d.id,
          'side': 'entrou',
          'price_before': d.price,
          'ownership_before': d.ownership.dbValue,
          'purchase_before':
              d.purchaseDate == null ? null : isoData(d.purchaseDate!),
          'ref_value': pesos[i],
          'share': partes[i],
        });
      }

      return tradeId;
    });
  }

  /// Desfaz a saída e devolve o jogo para a estante.
  ///
  /// Se o jogo entrou numa troca registrada, desfaz a **troca inteira**: as
  /// duas pontas voltam ao que eram. Desfazer só um lado deixaria o valor
  /// investido contado duas vezes, na estante e no jogo que entrou.
  Future<void> desfazerSaida(Game jogo) async {
    // Só a troca em que ele **saiu**: um jogo que chegou numa troca antiga e
    // foi vendido depois não pode ter a troca antiga desmanchada no lugar da
    // venda.
    final tradeId = await _trocaDoJogo(jogo.id!, lado: 'saiu');
    if (tradeId != null) {
      await desfazerTroca(tradeId);
      return;
    }

    final db = await _db;
    await db.transaction((txn) async {
      // Troca vinda de um backup restaurado: sem registro em `trade_games`, o
      // único jeito de devolver o valor é subtrair de onde ele foi somado.
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

      await _limpaSaida(txn, jogo.id!);
    });
  }

  /// Desmancha a troca: cada jogo volta ao preço, ao tipo e à data que tinha.
  Future<void> desfazerTroca(int tradeId) async {
    final db = await _db;

    await db.transaction((txn) async {
      final pontas = await txn.query(
        'trade_games',
        where: 'trade_id = ?',
        whereArgs: [tradeId],
      );

      for (final p in pontas) {
        final gameId = p['game_id'] as int;
        if (p['side'] == 'saiu') {
          await _limpaSaida(txn, gameId);
          continue;
        }
        await txn.update(
          'games',
          {
            'price': (p['price_before'] as num?)?.toDouble() ?? 0,
            'ownership': p['ownership_before'],
            'purchase_date': p['purchase_before'],
          },
          where: 'id = ?',
          whereArgs: [gameId],
        );
      }

      // As pontas somem por cascata.
      await txn.delete('trades', where: 'id = ?', whereArgs: [tradeId]);
    });
  }

  Future<void> _limpaSaida(DatabaseExecutor txn, int gameId) => txn.update(
        'games',
        {
          'disposal_kind': null,
          'traded_for_id': null,
          'sold': 0,
          'sold_price': null,
          'sold_date': null,
        },
        where: 'id = ?',
        whereArgs: [gameId],
      );

  /// A troca mais recente de que este jogo participou. [lado] restringe a
  /// 'saiu' ou 'entrou'; nulo aceita qualquer um.
  Future<int?> _trocaDoJogo(int gameId, {String? lado}) async {
    final db = await _db;
    final linhas = await db.query(
      'trade_games',
      columns: ['trade_id'],
      where: lado == null ? 'game_id = ?' : 'game_id = ? AND side = ?',
      whereArgs: lado == null ? [gameId] : [gameId, lado],
      orderBy: 'trade_id DESC',
      limit: 1,
    );
    return linhas.isEmpty ? null : linhas.first['trade_id'] as int;
  }

  /// A troca de que este jogo participou, com nome das duas pontas.
  ///
  /// Alimenta a ficha: "virou Dune Imperium e Ark Nova" diz mais que "valor
  /// transferido", e do outro lado "veio da troca de Scythe" explica um preço
  /// que o usuário nunca digitou.
  Future<Trade?> tradeDeJogo(int gameId) async {
    final tradeId = await _trocaDoJogo(gameId);
    if (tradeId == null) return null;

    final db = await _db;
    final cabecalho = await db.query(
      'trades',
      where: 'id = ?',
      whereArgs: [tradeId],
      limit: 1,
    );
    if (cabecalho.isEmpty) return null;

    final linhas = await db.rawQuery('''
      SELECT tg.*, g.name, g.name_pt
      FROM trade_games tg
      JOIN games g ON g.id = tg.game_id
      WHERE tg.trade_id = ?
    ''', [tradeId]);

    TradeParte parte(Map<String, Object?> r) {
      final pt = (r['name_pt'] as String?)?.trim();
      return TradeParte(
        gameId: r['game_id'] as int,
        nome: (pt == null || pt.isEmpty) ? r['name'] as String : pt,
        precoAntes: (r['price_before'] as num?)?.toDouble() ?? 0,
        valorReferencia: (r['ref_value'] as num?)?.toDouble(),
        parte: (r['share'] as num?)?.toDouble(),
      );
    }

    return Trade(
      id: tradeId,
      quando: parseIsoData(cabecalho.first['traded_at'] as String?) ??
          DateTime.now(),
      saiu: [
        for (final r in linhas)
          if (r['side'] == 'saiu') parte(r),
      ],
      entrou: [
        for (final r in linhas)
          if (r['side'] == 'entrou') parte(r),
      ],
    );
  }

  // ------------------------------------------------------------- sugestões

  /// Ideias de melhoria do app, das mais novas para as mais velhas, com as
  /// já feitas no fim — o que ainda falta é o que interessa ao abrir a lista.
  Future<List<Suggestion>> suggestions() async {
    final db = await _db;
    final linhas = await db.query(
      'suggestions',
      orderBy: 'done ASC, id DESC',
    );
    return linhas.map(Suggestion.fromMap).toList();
  }

  Future<int> addSuggestion(String texto) async {
    final db = await _db;
    return db.insert('suggestions', {
      'text': texto.trim(),
      'created_at': isoData(DateTime.now()),
      'done': 0,
    });
  }

  Future<void> setSuggestionDone(int id, bool feito) async {
    final db = await _db;
    await db.update(
      'suggestions',
      {'done': feito ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteSuggestion(int id) async {
    final db = await _db;
    await db.delete('suggestions', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------- extras

  /// Compras avulsas (kits, playmats), das mais recentes para as mais velhas.
  Future<List<Extra>> extras() async {
    final db = await _db;
    final linhas = await db.query(
      'extras',
      orderBy: 'purchase_date IS NULL, purchase_date DESC, id DESC',
    );
    return linhas.map(Extra.fromMap).toList();
  }

  Future<int> insertExtra(Extra extra) async {
    final db = await _db;
    return db.insert('extras', extra.toMap()..remove('id'));
  }

  Future<void> updateExtra(Extra extra) async {
    final db = await _db;
    await db.update('extras', extra.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [extra.id]);
  }

  Future<void> deleteExtra(int id) async {
    final db = await _db;
    await db.delete('extras', where: 'id = ?', whereArgs: [id]);
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

  /// Jogos sem capa **ou** sem etiqueta.
  ///
  /// Os dois buracos vêm da mesma origem — jogo digitado à mão ou importado da
  /// planilha nasce sem imagem e sem tema — e a mesma consulta ao catálogo
  /// preenche os dois. Varrer a coleção duas vezes seria o dobro de espera e o
  /// dobro de requisição para o mesmo resultado.
  Future<List<Game>> gamesSemCapaOuTema() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT g.* FROM games g
      WHERE NOT EXISTS (SELECT 1 FROM game_tags gt WHERE gt.game_id = g.id)
         OR ((g.image_url IS NULL OR g.image_url = '')
             AND (g.thumb_url IS NULL OR g.thumb_url = ''))
      ORDER BY g.name COLLATE NOCASE
    ''');
    return rows.map(Game.fromMap).toList();
  }

  /// Quantos jogos estão sem capa nenhuma. Alimenta o texto do cartão em
  /// Ajustes — "45 jogos sem capa" é o que faz a pessoa entender por que a
  /// lista virou uma coluna de iniciais.
  Future<int> countGamesSemCapa() async {
    final db = await _db;
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS total FROM games
      WHERE (image_url IS NULL OR image_url = '')
        AND (thumb_url IS NULL OR thumb_url = '')
    ''');
    return (r.first['total'] as int?) ?? 0;
  }

  // --------------------------------------------------------------- settings

  /// Chaves usadas na tabela `settings`.
  static const keyBggToken = 'bgg_token';

  /// Nome de usuário no Comparajogos, para ler as listas públicas dele.
  static const keyComparajogosUser = 'comparajogos_user';

  /// As réguas dos rankings de "vale a pena?". Ausente = comparar sem régua.
  static const keyMetaPorPartida = 'meta_por_partida';
  static const keyMetaPorMes = 'meta_por_mes';
  static const keyMetaPorHora = 'meta_por_hora';

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
    final extras = await db.query('extras');
    return {
      'schema': 1,
      'exportado_em': DateTime.now().toIso8601String(),
      'jogos': games,
      'partidas': plays,
      // Backup antigo não tem esta chave; a restauração trata como "nenhum".
      'extras': extras,
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
    final extras = (data['extras'] as List?) ?? const [];

    final db = await _db;
    var nJogos = 0;
    var nPartidas = 0;

    await db.transaction((txn) async {
      await txn.delete('plays');
      await txn.delete('games');
      // As pontas caem por cascata com os jogos; a troca em si ficaria órfã.
      await txn.delete('trades');
      await txn.delete('extras');

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

      for (final raw in extras) {
        await txn.insert('extras', Map<String, Object?>.from(raw as Map));
      }
    });

    return (jogos: nJogos, partidas: nPartidas);
  }
}
