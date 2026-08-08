import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludoteca/data/database.dart';
import 'package:ludoteca/data/game_repository.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/models/play.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Testes da migração do banco.
///
/// Isto existe por um motivo concreto: quem já tem o app instalado tem dados no
/// aparelho, e uma versão nova abre o banco **antigo** dele. Se o `onUpgrade`
/// falhar, o app quebra ao abrir e a coleção fica inacessível — o pior tipo de
/// bug possível aqui, porque atinge exatamente quem já usava.
///
/// Os testes criam um banco na versão antiga com dados dentro e reabrem pelo
/// `AppDatabase`, exercitando o `onUpgrade` de verdade.

/// Schema como ele era na v1: sem `plays.duration_minutes`, sem `settings`.
Future<void> _criaBancoV1(String caminho) async {
  final db = await databaseFactory.openDatabase(
    caminho,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE games (
            id                 INTEGER PRIMARY KEY AUTOINCREMENT,
            bgg_id             INTEGER,
            name               TEXT    NOT NULL,
            name_pt            TEXT,
            year               INTEGER,
            min_players        INTEGER,
            max_players        INTEGER,
            best_players       INTEGER,
            min_playtime       INTEGER,
            max_playtime       INTEGER,
            weight             REAL,
            image_url          TEXT,
            thumb_url          TEXT,
            parent_id          INTEGER REFERENCES games(id) ON DELETE SET NULL,
            is_expansion       INTEGER NOT NULL DEFAULT 0,
            price              REAL    NOT NULL DEFAULT 0,
            sleeve_cost        REAL    NOT NULL DEFAULT 0,
            accessory_cost     REAL    NOT NULL DEFAULT 0,
            purchase_date      TEXT,
            manual_play_count  INTEGER NOT NULL DEFAULT 0,
            manual_last_played TEXT,
            sold               INTEGER NOT NULL DEFAULT 0,
            sold_price         REAL,
            sold_date          TEXT,
            notes              TEXT,
            created_at         TEXT    NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE plays (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            game_id   INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
            played_at TEXT    NOT NULL,
            players   INTEGER,
            winner    TEXT,
            notes     TEXT
          )
        ''');
      },
    ),
  );
  await db.close();
}

/// v2 = v1 + `plays.duration_minutes`.
Future<void> _criaBancoV2(String caminho) async {
  await _criaBancoV1(caminho);
  final db = await databaseFactory.openDatabase(
    caminho,
    options: OpenDatabaseOptions(version: 1),
  );
  await db.execute('ALTER TABLE plays ADD COLUMN duration_minutes INTEGER');
  await db.setVersion(2);
  await db.close();
}

/// Popula com um jogo e uma partida, para provar que a migração não perde dado.
Future<void> _povoa(String caminho) async {
  final db = await databaseFactory.openDatabase(caminho);
  await db.insert('games', {
    'name': 'Gloomhaven',
    'price': 899.90,
    'sleeve_cost': 120.0,
    'accessory_cost': 0.0,
    'manual_play_count': 7,
    'is_expansion': 0,
    'sold': 0,
    'created_at': '2024-01-15',
  });
  await db.insert('plays', {
    'game_id': 1,
    'played_at': '2025-06-01',
    'players': 3,
  });
  await db.close();
}

Future<bool> _tabelaExiste(dynamic db, String nome) async {
  final r = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    [nome],
  );
  return (r as List).isNotEmpty;
}

Future<Set<String>> _colunas(dynamic db, String tabela) async {
  final r = await db.rawQuery('PRAGMA table_info($tabela)');
  return {for (final linha in r as List) linha['name'] as String};
}

void main() {
  setUpAll(() {
    // SQLite nativo não existe no desktop de teste; o ffi entra no lugar.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory temp;
  late String caminho;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ludoteca_test');
    caminho = '${temp.path}/ludoteca.db';
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('banco novo', () {
    test('cria as três tabelas já na versão atual', () async {
      final app = AppDatabase.paraArquivo(caminho);
      final db = await app.db;

      expect(await _tabelaExiste(db, 'games'), isTrue);
      expect(await _tabelaExiste(db, 'plays'), isTrue);
      expect(await _tabelaExiste(db, 'settings'), isTrue);
      expect(await db.getVersion(), AppDatabase.versaoAtual);

      await app.close();
    });

    test('plays já nasce com duration_minutes', () async {
      final app = AppDatabase.paraArquivo(caminho);
      final db = await app.db;

      expect(await _colunas(db, 'plays'), contains('duration_minutes'));

      await app.close();
    });
  });

  group('migração v2 → v3', () {
    test('cria settings sem perder os dados que já estavam lá', () async {
      // É este o caso do celular que já tinha o app instalado.
      await _criaBancoV2(caminho);
      await _povoa(caminho);

      final app = AppDatabase.paraArquivo(caminho);
      final db = await app.db;

      expect(await db.getVersion(), AppDatabase.versaoAtual);
      expect(await _tabelaExiste(db, 'settings'), isTrue);

      final jogos = await db.query('games');
      expect(jogos.length, 1);
      expect(jogos.first['name'], 'Gloomhaven');
      expect(jogos.first['price'], 899.90);
      expect(jogos.first['manual_play_count'], 7);

      final partidas = await db.query('plays');
      expect(partidas.length, 1);
      expect(partidas.first['players'], 3);

      await app.close();
    });

    test('o token grava e lê depois de migrar', () async {
      await _criaBancoV2(caminho);

      final app = AppDatabase.paraArquivo(caminho);
      final repo = GameRepository(database: app);

      expect(await repo.getSetting(GameRepository.keyBggToken), isNull);

      await repo.setSetting(GameRepository.keyBggToken, 'tok_123');
      expect(await repo.getSetting(GameRepository.keyBggToken), 'tok_123');

      await app.close();
    });
  });

  group('migração v1 → atual (pulando versões)', () {
    test('roda todos os passos acumulados', () async {
      // Alguém que instalou a primeira versão e só atualizou agora pula todas as
      // intermediárias. A cadeia de `if (from < N)` precisa aplicar cada passo.
      await _criaBancoV1(caminho);
      await _povoa(caminho);

      final app = AppDatabase.paraArquivo(caminho);
      final db = await app.db;

      expect(await db.getVersion(), AppDatabase.versaoAtual);
      expect(await _colunas(db, 'plays'), contains('duration_minutes'));
      expect(await _tabelaExiste(db, 'settings'), isTrue);
      expect((await db.query('games')).length, 1);

      await app.close();
    });

    test('partida antiga fica com duração nula, não zero', () async {
      // Zero significaria "partida de zero minuto". Nulo significa "não
      // cronometrei, use a média do jogo" — que é o certo para o histórico
      // gravado antes da coluna existir.
      await _criaBancoV1(caminho);
      await _povoa(caminho);

      final app = AppDatabase.paraArquivo(caminho);
      final db = await app.db;

      final partidas = await db.query('plays');
      expect(partidas.first['duration_minutes'], isNull);

      await app.close();
    });
  });

  group('migração → v7 (saída da coleção e placar)', () {
    test('o que já estava marcado como vendido vira saída "vendido"', () async {
      // Antes da v7 só existia `sold`. Quem vendeu um jogo na versão velha não
      // pode aparecer com a saída em branco depois de atualizar — a ficha diria
      // "saiu da coleção" sem dizer como, e o valor recebido ficaria solto.
      await _criaBancoV1(caminho);
      final antigo = await databaseFactory.openDatabase(caminho);
      await antigo.insert('games', {
        'name': 'Scythe',
        'price': 400.0,
        'sleeve_cost': 0.0,
        'accessory_cost': 0.0,
        'manual_play_count': 0,
        'is_expansion': 0,
        'sold': 1,
        'sold_price': 300.0,
        'created_at': '2024-01-15',
      });
      await antigo.insert('games', {
        'name': 'Ark Nova',
        'price': 500.0,
        'sleeve_cost': 0.0,
        'accessory_cost': 0.0,
        'manual_play_count': 0,
        'is_expansion': 0,
        'sold': 0,
        'created_at': '2024-01-15',
      });
      await antigo.close();

      final app = AppDatabase.paraArquivo(caminho);
      final db = await app.db;

      final jogos = await db.query('games', orderBy: 'name');
      expect(jogos.first['name'], 'Ark Nova');
      // O que continua na estante não pode ganhar uma saída do nada.
      expect(jogos.first['disposal_kind'], isNull);

      expect(jogos.last['name'], 'Scythe');
      expect(jogos.last['disposal_kind'], 'vendido');
      expect(jogos.last['sold_price'], 300.0);

      await app.close();
    });

    test('quem estava no campo "quem ganhou" vira uma pessoa cadastrada',
        () async {
      // Esse campo existe desde a v1 e nunca alimentou sugestão nenhuma. Sem
      // trazê-lo na migração, quem sempre anotou o vencedor ali atualizaria o
      // app e encontraria a lista de pessoas vazia.
      await _criaBancoV1(caminho);
      final antigo = await databaseFactory.openDatabase(caminho);
      await antigo.insert('games', {
        'name': 'Ark Nova',
        'price': 0.0,
        'sleeve_cost': 0.0,
        'accessory_cost': 0.0,
        'manual_play_count': 0,
        'is_expansion': 0,
        'sold': 0,
        'created_at': '2024-01-15',
      });
      await antigo.insert('plays', {
        'game_id': 1,
        'played_at': '2025-06-01',
        'winner': 'Matheus',
      });
      await antigo.insert('plays', {
        'game_id': 1,
        'played_at': '2025-07-01',
        'winner': 'matheus',
      });
      await antigo.insert('plays', {
        'game_id': 1,
        'played_at': '2025-08-01',
        'winner': '  ',
      });
      await antigo.close();

      final app = AppDatabase.paraArquivo(caminho);
      final db = await app.db;

      final pessoas = await db.query('players');
      // Uma pessoa só: a grafia diferente não cria outra, e o campo em branco
      // não vira uma pessoa sem nome.
      expect(pessoas.length, 1);
      expect(pessoas.first['name'], 'Matheus');

      await app.close();
    });

    test('play_scores nasce com a partida apagando o placar junto', () async {
      await _criaBancoV1(caminho);
      await _povoa(caminho);

      final app = AppDatabase.paraArquivo(caminho);
      final db = await app.db;

      expect(await _tabelaExiste(db, 'play_scores'), isTrue);

      // A chave estrangeira só age com o pragma ligado; se o `AppDatabase` não
      // ligar, o placar sobrevive à partida e reaparece grudado noutra.
      await db.insert('play_scores', {
        'play_id': 1,
        'player_name': 'Ana',
        'score': 42.0,
        'won': 1,
      });
      await db.delete('plays', where: 'id = ?', whereArgs: [1]);

      expect(await db.query('play_scores'), isEmpty);

      await app.close();
    });
  });

  group('migração v3 → v4', () {
    /// Monta um banco **realmente** na v3: v2 mais a tabela `settings`.
    ///
    /// Não dá para abrir pelo `AppDatabase` e só rebaixar o número da versão —
    /// isso criaria o schema atual, e a migração então tentaria adicionar uma
    /// coluna que já existe. O teste tem de partir do schema antigo de verdade.
    Future<void> criaV3ComDados() async {
      await _criaBancoV2(caminho);

      final db = await databaseFactory.openDatabase(
        caminho,
        options: OpenDatabaseOptions(version: 2),
      );
      await db.execute(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)',
      );
      await db.setVersion(3);

      await db.insert('games', {
        'name': 'Unmatched',
        'price': 199.0,
        'sleeve_cost': 0.0,
        'accessory_cost': 0.0,
        'manual_play_count': 0,
        'is_expansion': 0,
        'sold': 0,
        'created_at': '2025-01-01',
      });
      await db.insert('games', {
        'name': 'Hero Pack',
        'parent_id': 1,
        'is_expansion': 1,
        'price': 90.0,
        'sleeve_cost': 0.0,
        'accessory_cost': 0.0,
        'manual_play_count': 0,
        'sold': 0,
        'created_at': '2025-01-01',
      });
      await db.insert('plays', {'game_id': 1, 'played_at': '2025-06-01'});
      await db.close();
    }

    test('o que era expansão continua expansão depois de migrar', () async {
      await criaV3ComDados();

      final app = AppDatabase.paraArquivo(caminho);
      final db = await app.db;

      expect(await db.getVersion(), AppDatabase.versaoAtual);
      expect(await _colunas(db, 'games'), contains('link_kind'));
      expect(await _colunas(db, 'plays'), contains('item_game_id'));

      final linhas = await db.query('games', orderBy: 'id');
      expect(linhas[0]['link_kind'], isNull, reason: 'o jogo-base não é item');
      expect(linhas[1]['link_kind'], 'expansao');

      await app.close();
    });

    test('partida antiga fica sem caixa marcada, não com caixa errada',
        () async {
      await criaV3ComDados();

      final app = AppDatabase.paraArquivo(caminho);
      final db = await app.db;

      final partidas = await db.query('plays');
      expect(partidas.first['item_game_id'], isNull);

      await app.close();
    });

    test('remover uma caixa não apaga as partidas do grupo', () async {
      // ON DELETE SET NULL, não CASCADE: a partida aconteceu, e perder o
      // histórico do grupo porque uma caixa saiu da coleção seria pior que
      // perder só a informação de qual caixa era.
      final app = AppDatabase.paraArquivo(caminho);
      final repo = GameRepository(database: app);

      final pai = await repo.insertGame(const Game(id: null, name: 'Unmatched'));
      final caixa = await repo.insertGame(Game(
        name: 'Unmatched: Buffy',
        parentId: pai,
        linkKind: LinkKind.serie,
      ));
      await repo.insertPlay(Play(
        gameId: pai,
        playedAt: DateTime(2025, 6, 1),
        itemGameId: caixa,
      ));

      await repo.deleteGame(caixa);

      final partidas = await repo.playsFor(pai);
      expect(partidas.length, 1, reason: 'a partida do grupo tem de sobreviver');
      expect(partidas.first.itemGameId, isNull);

      await app.close();
    });

    test('a caixa jogada sobrevive à ida e volta pelo banco', () async {
      final app = AppDatabase.paraArquivo(caminho);
      final repo = GameRepository(database: app);

      final pai = await repo.insertGame(const Game(name: 'Unmatched'));
      final caixa = await repo.insertGame(Game(
        name: 'Unmatched: Cobble & Fog',
        parentId: pai,
        linkKind: LinkKind.serie,
      ));
      await repo.insertPlay(Play(
        gameId: pai,
        playedAt: DateTime(2025, 7, 2),
        itemGameId: caixa,
      ));

      final partidas = await repo.playsFor(pai);
      expect(partidas.first.itemGameId, caixa);

      final salva = await repo.gameById(caixa);
      expect(salva!.linkKind, LinkKind.serie);
      expect(salva.parentId, pai);

      await app.close();
    });
  });

  group('settings', () {
    test('gravar a mesma chave duas vezes substitui, não duplica', () async {
      final app = AppDatabase.paraArquivo(caminho);
      final repo = GameRepository(database: app);

      await repo.setSetting(GameRepository.keyBggToken, 'primeiro');
      await repo.setSetting(GameRepository.keyBggToken, 'segundo');

      expect(await repo.getSetting(GameRepository.keyBggToken), 'segundo');

      final db = await app.db;
      expect((await db.query('settings')).length, 1);

      await app.close();
    });

    test('valor vazio ou só espaço apaga a chave', () async {
      // "não configurado" e "configurado com string vazia" não podem ser
      // estados diferentes — senão o app acha que tem token e manda um
      // Authorization vazio.
      final app = AppDatabase.paraArquivo(caminho);
      final repo = GameRepository(database: app);

      await repo.setSetting(GameRepository.keyBggToken, 'tok');
      await repo.setSetting(GameRepository.keyBggToken, '   ');

      expect(await repo.getSetting(GameRepository.keyBggToken), isNull);

      await app.close();
    });

    test('o token sobrevive a uma restauração de backup', () async {
      // A restauração apaga jogos e partidas, mas não pode levar a credencial
      // junto: o usuário teria de cadastrar o token de novo a cada restauração.
      final app = AppDatabase.paraArquivo(caminho);
      final repo = GameRepository(database: app);

      await repo.setSetting(GameRepository.keyBggToken, 'tok_abc');
      await repo.importAll({
        'schema': 1,
        'jogos': [
          {
            'id': 1,
            'name': 'Wingspan',
            'price': 300.0,
            'sleeve_cost': 0.0,
            'accessory_cost': 0.0,
            'manual_play_count': 0,
            'is_expansion': 0,
            'sold': 0,
            'created_at': '2025-01-01',
          }
        ],
        'partidas': const [],
      });

      expect(await repo.getSetting(GameRepository.keyBggToken), 'tok_abc');
      expect((await repo.loadEntries()).length, 1);

      await app.close();
    });

    test('o backup exportado não carrega o token', () async {
      // O arquivo sai do aparelho — vai para o Drive, e-mail, WhatsApp.
      // Credencial não viaja nisso.
      final app = AppDatabase.paraArquivo(caminho);
      final repo = GameRepository(database: app);

      await repo.setSetting(GameRepository.keyBggToken, 'tok_secreto');
      final dump = await repo.exportAll();

      expect(dump.keys, isNot(contains('settings')));
      expect(dump.toString(), isNot(contains('tok_secreto')));

      await app.close();
    });
  });
}
