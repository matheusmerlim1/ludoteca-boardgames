import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Banco SQLite local. Nenhum dado sai do celular.
class AppDatabase {
  AppDatabase._({String? caminho}) : _caminhoFixo = caminho;

  static final AppDatabase instance = AppDatabase._();

  /// Instância isolada apontando para um arquivo específico.
  ///
  /// Existe para o teste conseguir criar um banco na versão antiga e reabrir
  /// por aqui, exercitando o `onUpgrade` **de verdade**. Uma cópia da migração
  /// dentro do teste não provaria nada: o que quebra o app de quem já tem dados
  /// no aparelho é justamente este código, não uma reprodução dele.
  @visibleForTesting
  factory AppDatabase.paraArquivo(String caminho) =>
      AppDatabase._(caminho: caminho);

  /// Nulo em produção: o caminho sai de `getDatabasesPath()`.
  final String? _caminhoFixo;

  static const _fileName = 'ludoteca.db';

  /// Exposta para o teste poder abrir um banco "uma versão atrás" sem repetir
  /// o número mágico.
  @visibleForTesting
  static int get versaoAtual => _version;

  /// Guardado numa constante porque é usado nos dois caminhos: na criação de
  /// um banco novo e na migração de quem já tem dados no aparelho.
  static const _settingsDdl = '''
    CREATE TABLE settings (
      key   TEXT PRIMARY KEY,
      value TEXT
    )
  ''';

  /// Quem jogou cada partida, com quantos pontos fez e se venceu.
  ///
  /// Tabela própria em vez de um texto solto na partida: assim dá para
  /// perguntar quem mais ganha e qual foi a maior pontuação, em vez de só
  /// reler uma anotação.
  static const _scoresDdl = '''
    CREATE TABLE play_scores (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      play_id     INTEGER NOT NULL REFERENCES plays(id) ON DELETE CASCADE,
      player_name TEXT    NOT NULL,
      score       REAL,
      won         INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static const _scoresIndexDdl =
      'CREATE INDEX idx_play_scores_play ON play_scores(play_id)';

  /// As pessoas com quem você joga.
  ///
  /// Tabela própria em vez de deduzir os nomes das partidas: assim o nome
  /// sobrevive a apagar a partida em que ele apareceu pela primeira vez, e as
  /// sugestões podem ordenar por quem joga mais e mais recentemente sem varrer
  /// o histórico inteiro a cada vez que a folha de partida abre.
  ///
  /// `COLLATE NOCASE` no índice: "Ana" e "ana" são a mesma pessoa, e duas
  /// linhas para ela dariam dois chips iguais na sugestão.
  ///
  /// Não há coluna de contagem aqui de propósito: quantas partidas cada pessoa
  /// jogou é uma pergunta que `play_scores` responde sempre certo. Um contador
  /// mantido à mão erraria na primeira edição de partida — regravar o placar
  /// somaria de novo — e passaria despercebido, porque ele só mexe na ordem
  /// das sugestões.
  static const _playersDdl = '''
    CREATE TABLE players (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      name         TEXT NOT NULL,
      last_used_at TEXT
    )
  ''';

  static const _playersIndexDdl =
      'CREATE UNIQUE INDEX idx_players_name ON players(name COLLATE NOCASE)';

  /// A troca em si, e as pontas dela.
  ///
  /// Tabela própria porque troca é N por M: um jogo grande vira dois menores,
  /// ou três juntos viram um. O `games.traded_for_id` só apontava um jogo, o
  /// que obrigava a escolher qual das pontas mentir.
  ///
  /// `price_before`, `ownership_before` e `purchase_before` guardam o estado de
  /// cada jogo **antes** da troca. É o que o desfazer devolve: recalcular por
  /// subtração já erra quando o mesmo jogo entra em duas trocas seguidas, e
  /// erra em silêncio.
  static const _tradesDdl = [
    '''
    CREATE TABLE trades (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      traded_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE trade_games (
      trade_id        INTEGER NOT NULL REFERENCES trades(id) ON DELETE CASCADE,
      game_id         INTEGER NOT NULL REFERENCES games(id)  ON DELETE CASCADE,
      -- 'saiu' | 'entrou'
      side            TEXT    NOT NULL,
      price_before    REAL    NOT NULL DEFAULT 0,
      ownership_before TEXT,
      purchase_before TEXT,
      -- Só de quem entrou: o peso usado no rateio e a parte que coube a ele.
      ref_value       REAL,
      share           REAL,
      PRIMARY KEY (trade_id, game_id)
    )
    ''',
    'CREATE INDEX idx_trade_games_game ON trade_games(game_id)',
  ];

  /// Ideias de melhoria do próprio app, anotadas na hora em que incomodam.
  ///
  /// Fica no banco, e não num bloco de notas fora, porque a ideia aparece no
  /// meio do uso — e uma ideia que exige sair do app para ser anotada não é
  /// anotada.
  static const _suggestionsDdl = '''
    CREATE TABLE suggestions (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      text       TEXT    NOT NULL,
      created_at TEXT    NOT NULL,
      done       INTEGER NOT NULL DEFAULT 0
    )
  ''';

  /// Compras avulsas do hobby que não pertencem a um jogo: kit de sleeves,
  /// playmat, organizador. Tabela própria para não entrarem na estante, no
  /// custo por partida nem no "nunca jogado" — só nos gastos.
  static const _extrasDdl = '''
    CREATE TABLE extras (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      name          TEXT    NOT NULL,
      -- 'sleeves' | 'playmat' | 'organizador' | 'acessorio' | 'outro'
      kind          TEXT    NOT NULL DEFAULT 'outro',
      price         REAL    NOT NULL DEFAULT 0,
      purchase_date TEXT,
      notes         TEXT
    )
  ''';

  /// Temas e mecânicas, e o vínculo deles com os jogos.
  static const _tagsDdl = [
    '''
    CREATE TABLE tags (
      id   INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      -- 'tema' | 'mecanica'
      kind TEXT NOT NULL,
      UNIQUE(name, kind)
    )
    ''',
    '''
    CREATE TABLE game_tags (
      game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
      tag_id  INTEGER NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
      PRIMARY KEY (game_id, tag_id)
    )
    ''',
    'CREATE INDEX idx_game_tags_tag ON game_tags(tag_id)',
  ];

  /// v1 → v2: `plays.duration_minutes`, para registrar quanto a partida durou
  ///          de verdade quando você quiser. Nulo significa "use a duração
  ///          média do jogo".
  /// v2 → v3: tabela `settings`, que hoje guarda o token da API do BGG. Fica
  ///          no banco em vez de num plugin de preferências para não somar
  ///          mais uma dependência nativa ao build.
  /// v3 → v4: `games.link_kind` e `plays.item_game_id`.
  ///
  ///          `link_kind` separa duas coisas que antes eram a mesma: uma
  ///          **expansão** (não joga sozinha) e uma **caixa da mesma série**
  ///          (joga sozinha, mas você trata como um jogo só). Unmatched é o
  ///          caso: cada caixa é um jogo completo, e ainda assim ninguém quer
  ///          seis linhas de "Unmatched" na estante com o custo por partida
  ///          picado entre elas.
  ///
  ///          `item_game_id` guarda qual caixa foi jogada numa partida
  ///          lançada no grupo.
  /// v4 → v5: `tags` e `game_tags`, para filtrar por tema e por mecânica.
  ///
  ///          Tabelas próprias em vez de uma coluna de texto no jogo: assim dá
  ///          para listar os temas existentes com a contagem de cada um, e
  ///          renomear um tema não exige varrer todos os jogos.
  /// v5 → v6: `games.ownership` e o acompanhamento de preço.
  ///
  ///          Até aqui, estar na tabela significava "é meu". Isso não dava
  ///          conta de duas coisas reais: jogar o jogo de outra pessoa (conta
  ///          para as horas, mas não é investimento seu) e querer comprar um
  ///          jogo (não é seu nem foi jogado). Um campo com três estados
  ///          resolve as duas sem criar tabelas paralelas que precisariam ser
  ///          mantidas em sincronia.
  /// v6 → v7: como o jogo saiu da coleção, e a pontuação de cada partida.
  ///
  ///          Até aqui só existia "vendido". Trocar e doar são saídas
  ///          diferentes: doar não devolve dinheiro nenhum, e trocar transfere
  ///          o valor investido para o jogo que entrou — tratar as três como
  ///          venda mentiria no custo.
  /// v7 → v8: tabela `players`, com quem você joga.
  ///
  ///          Os nomes já vinham sendo sugeridos, mas deduzidos das partidas
  ///          gravadas: apagar a única partida de alguém apagava a pessoa junto.
  ///          A migração semeia a tabela com o que já existe — inclusive os
  ///          nomes digitados no campo antigo "quem ganhou", que nunca tinham
  ///          entrado na sugestão.
  /// v8 → v9: `trades` e `trade_games`, e `suggestions`.
  ///
  ///          Até aqui a troca era um jogo por **um** jogo, gravada num
  ///          `traded_for_id` só. A troca real é N por M — um jogo grande vira
  ///          dois menores, três juntos viram um — e o valor investido precisa
  ///          se dividir entre os que entraram, na proporção do que cada um
  ///          vale. As trocas antigas viram linhas nas tabelas novas, com o
  ///          preço anterior reconstruído, para o desfazer continuar exato.
  /// v9 → v10: tabela `extras`, para compras avulsas (kit de sleeves,
  ///          playmat, organizador) que entram no custo do mês sem ser um
  ///          jogo. Só cria a tabela: nada do que já existe muda.
  static const _version = 10;

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final caminho = _caminhoFixo ?? p.join(await getDatabasesPath(), _fileName);
    return openDatabase(
      caminho,
      version: _version,
      onConfigure: (db) async {
        // Sem isto o ON DELETE CASCADE das partidas não vale.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _create(db);
      },
      onUpgrade: (db, from, to) async {
        // Cada versão futura entra como um `if (from < N)` aqui, sempre
        // aditivo — quem já tem dados no aparelho passa por este caminho.
        if (from < 2) {
          await db.execute(
            'ALTER TABLE plays ADD COLUMN duration_minutes INTEGER',
          );
        }
        if (from < 3) {
          await db.execute(_settingsDdl);
        }
        if (from < 4) {
          await db.execute('ALTER TABLE games ADD COLUMN link_kind TEXT');
          // Tudo que era expansão continua expansão. Quem quiser reclassificar
          // como caixa de série faz isso item a item, na tela de edição.
          await db.execute(
            "UPDATE games SET link_kind = 'expansao' WHERE is_expansion = 1",
          );
          await db.execute('ALTER TABLE plays ADD COLUMN item_game_id INTEGER');
        }
        if (from < 5) {
          for (final ddl in _tagsDdl) {
            await db.execute(ddl);
          }
        }
        if (from < 6) {
          // Nulo = "minha". Todo mundo que já estava cadastrado é seu, então
          // não precisa de UPDATE nenhum aqui.
          await db.execute('ALTER TABLE games ADD COLUMN ownership TEXT');
          await db.execute('ALTER TABLE games ADD COLUMN target_price REAL');
          await db.execute('ALTER TABLE games ADD COLUMN last_price REAL');
          await db.execute('ALTER TABLE games ADD COLUMN last_price_at TEXT');
        }
        if (from < 7) {
          await db.execute('ALTER TABLE games ADD COLUMN disposal_kind TEXT');
          await db.execute('ALTER TABLE games ADD COLUMN traded_for_id INTEGER');
          // Tudo que estava marcado como vendido continua vendido.
          await db.execute(
            "UPDATE games SET disposal_kind = 'vendido' WHERE sold = 1",
          );
          await db.execute(_scoresDdl);
          await db.execute(_scoresIndexDdl);
        }
        if (from < 8) {
          await db.execute(_playersDdl);
          await db.execute(_playersIndexDdl);
          await _semeiaJogadores(db);
        }
        if (from < 9) {
          for (final ddl in _tradesDdl) {
            await db.execute(ddl);
          }
          await db.execute(_suggestionsDdl);
          await _semeiaTrocas(db);
        }
        if (from < 10) {
          await db.execute(_extrasDdl);
        }
      },
    );
  }

  Future<void> _create(Database db) async {
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
        -- NULL | 'jogada' | 'desejada'. NULL significa "é minha" — o caso
        -- comum fica sem valor gravado, e bancos antigos leem certo.
        ownership          TEXT,
        -- Como o jogo saiu da coleção: NULL | 'vendido' | 'trocado' | 'doado'.
        disposal_kind      TEXT,
        -- Numa troca, o jogo que entrou no lugar. O valor investido migra
        -- para ele, então o custo por partida do novo jogo já nasce certo.
        traded_for_id      INTEGER,
        -- Acompanhamento de preço, para a lista de desejos.
        target_price       REAL,
        last_price         REAL,
        last_price_at      TEXT,
        -- 'expansao' | 'serie' | NULL (item independente).
        -- Não-nulo significa que o item está agrupado sob `parent_id`.
        link_kind          TEXT,
        -- Mantida derivada de `link_kind` só para backups antigos, que ainda
        -- trazem esta coluna, continuarem legíveis nos dois sentidos.
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
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id          INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
        played_at        TEXT    NOT NULL,
        players          INTEGER,
        winner           TEXT,
        notes            TEXT,
        -- Nulo de propósito: significa "não cronometrei, use a média do
        -- jogo". Zero significaria uma partida de zero minuto.
        duration_minutes INTEGER,
        -- Qual caixa do grupo foi jogada. Nulo = partida do jogo em si, ou
        -- você não quis detalhar. ON DELETE SET NULL: remover uma caixa não
        -- pode apagar o histórico de partidas do grupo.
        item_game_id     INTEGER REFERENCES games(id) ON DELETE SET NULL
      )
    ''');

    await db.execute(_settingsDdl);
    await db.execute(_scoresDdl);
    await db.execute(_scoresIndexDdl);
    await db.execute(_playersDdl);
    await db.execute(_playersIndexDdl);
    await db.execute(_suggestionsDdl);
    await db.execute(_extrasDdl);
    for (final ddl in [..._tagsDdl, ..._tradesDdl]) {
      await db.execute(ddl);
    }

    await db.execute('CREATE INDEX idx_plays_game ON plays(game_id)');
    await db.execute('CREATE INDEX idx_plays_date ON plays(played_at)');
    await db.execute('CREATE INDEX idx_games_parent ON games(parent_id)');
    await db.execute('CREATE INDEX idx_games_bgg ON games(bgg_id)');
  }

  /// Semeia `players` com quem já aparece no histórico.
  ///
  /// Duas fontes, e a segunda é a que importa para quem já usava o app: o campo
  /// livre "quem ganhou" da partida. Ele existe desde a primeira versão e nunca
  /// alimentou sugestão nenhuma — sem trazê-lo, atualizar o app deixaria a lista
  /// de pessoas vazia para quem sempre anotou o vencedor ali.
  ///
  /// O `INSERT OR IGNORE` cuida dos repetidos: o índice em `name COLLATE NOCASE`
  /// é quem decide que "Ana" e "ana" são a mesma pessoa.
  static Future<void> _semeiaJogadores(Database db) async {
    final agora = DateTime.now().toIso8601String();

    await db.execute('''
      INSERT OR IGNORE INTO players (name, last_used_at)
      SELECT TRIM(player_name), ?
      FROM play_scores
      WHERE TRIM(player_name) <> ''
      GROUP BY TRIM(player_name) COLLATE NOCASE
    ''', [agora]);

    await db.execute('''
      INSERT OR IGNORE INTO players (name, last_used_at)
      SELECT TRIM(winner), ?
      FROM plays
      WHERE winner IS NOT NULL AND TRIM(winner) <> ''
      GROUP BY TRIM(winner) COLLATE NOCASE
    ''', [agora]);
  }

  /// Transforma as trocas antigas (um `traded_for_id` no jogo) em linhas das
  /// tabelas novas.
  ///
  /// Não mexe em preço nenhum: o dinheiro já está onde a versão antiga o
  /// colocou. O que a migração faz é **reconstruir o preço anterior** de quem
  /// recebeu o valor, que é a única informação que faltava para desfazer a
  /// troca sem inventar número.
  ///
  /// A reconstrução é de trás para frente porque duas trocas podem ter
  /// desembocado no mesmo jogo: desfazer a última tem de devolver o estado
  /// imediatamente anterior a ela, não o do começo de tudo.
  static Future<void> _semeiaTrocas(Database db) async {
    final trocas = await db.query(
      'games',
      columns: [
        'id',
        'traded_for_id',
        'price',
        'sleeve_cost',
        'accessory_cost',
        'sold_date',
      ],
      where: "disposal_kind = 'trocado' AND traded_for_id IS NOT NULL",
      orderBy: 'sold_date DESC, id DESC',
    );
    if (trocas.isEmpty) return;

    double num2(Object? v) => (v as num?)?.toDouble() ?? 0;

    // Preço corrente de cada destino enquanto desfazemos mentalmente as
    // trocas, uma a uma.
    final correntes = <int, double>{};

    for (final linha in trocas) {
      final saiuId = linha['id'] as int;
      final entrouId = linha['traded_for_id'] as int;

      final destino = await db.query(
        'games',
        columns: ['price', 'ownership', 'purchase_date'],
        where: 'id = ?',
        whereArgs: [entrouId],
        limit: 1,
      );
      // O jogo que entrou pode ter sido apagado desde então. A ponta que
      // sobrou ainda vale: sem ela, desfazer a saída não devolveria o jogo.
      final existe = destino.isNotEmpty;

      final transferido = num2(linha['price']) +
          num2(linha['sleeve_cost']) +
          num2(linha['accessory_cost']);

      final atual = correntes[entrouId] ??
          (existe ? num2(destino.first['price']) : 0);
      final antes = atual - transferido;
      correntes[entrouId] = antes < 0 ? 0 : antes;

      final tradeId = await db.insert('trades', {
        'traded_at': (linha['sold_date'] as String?) ??
            DateTime.now().toIso8601String().substring(0, 10),
      });

      await db.insert('trade_games', {
        'trade_id': tradeId,
        'game_id': saiuId,
        'side': 'saiu',
        'price_before': num2(linha['price']),
      });

      if (!existe) continue;

      await db.insert('trade_games', {
        'trade_id': tradeId,
        'game_id': entrouId,
        'side': 'entrou',
        'price_before': correntes[entrouId],
        'ownership_before': destino.first['ownership'],
        'purchase_before': destino.first['purchase_date'],
        'ref_value': correntes[entrouId],
        'share': transferido,
      });
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Apaga tudo. Usado pela restauração de backup.
  Future<void> wipe() async {
    final d = await db;
    await d.delete('plays');
    await d.delete('games');
    // As pontas somem por cascata junto com os jogos; a troca em si ficaria
    // como linha órfã, e o desfazer de uma troca sem pontas não faz nada.
    await d.delete('trades');
    await d.delete('extras');
  }
}
