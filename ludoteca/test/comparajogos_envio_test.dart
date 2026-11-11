import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ludoteca/data/database.dart';
import 'package:ludoteca/data/game_repository.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/models/play.dart';
import 'package:ludoteca/models/play_score.dart';
import 'package:ludoteca/services/comparajogos_partidas.dart';
import 'package:ludoteca/services/sincronizador_partidas.dart';
import 'package:ludoteca/state/collection_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// JWT com a carga dada (assinatura de mentira: o app não confere).
String jwt(Map<String, Object?> carga) {
  String b(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b({'alg': 'RS256'})}.${b(carga)}.assinatura';
}

final tokenBom = jwt({'sub': '42', 'username': 'matheus', 'name': 'Matheus Merlim'});

class FonteFixa implements FonteDeToken {
  FonteFixa(this.tokens);

  /// Um token por chamada; o último se repete.
  final List<String?> tokens;
  int chamadas = 0;
  final renovacoes = <bool>[];

  @override
  Future<String?> token({bool renovar = false}) async {
    renovacoes.add(renovar);
    final t = tokens[chamadas < tokens.length ? chamadas : tokens.length - 1];
    chamadas++;
    return t;
  }
}

/// Um Comparajogos de mentira: guarda partidas e participantes em memória e
/// responde às mesmas operações que o app manda.
class ComparajogosFalso {
  final produtosPorBgg = <int, int>{174430: 900};
  final produtosPorNome = <String, int>{'azul': 901, 'azul: pavilhão de verão': 902};
  final participantes = <Map<String, Object?>>[];
  final partidas = <int, Map<String, Object?>>{};
  final apagadas = <int>[];
  final tokensRecusados = <String>{};
  final headers = <Map<String, String>>[];
  var semRede = false;
  var proximoId = 1000;

  MockClient get client => MockClient((req) async {
        if (semRede) throw const SocketException('sem rede');
        headers.add(req.headers);
        final corpo = jsonDecode(req.body) as Map<String, dynamic>;
        final q = corpo['query'] as String;
        final v = (corpo['variables'] as Map).cast<String, dynamic>();
        final token = (req.headers['Authorization'] ?? '').replaceFirst('Bearer ', '');
        if (tokensRecusados.contains(token)) {
          return _json({
            'errors': [
              {'message': 'Could not verify JWT: JWTExpired'}
            ]
          });
        }
        return _json({'data': _responde(q, v)});
      });

  http.Response _json(Object o) => http.Response.bytes(
        utf8.encode(jsonEncode(o)),
        200,
        headers: {'content-type': 'application/json'},
      );

  String _semEscape(String s) =>
      s.replaceAll(r'\%', '%').replaceAll(r'\_', '_').replaceAll(r'\\', r'\');

  Map<String, Object?> _responde(String q, Map<String, dynamic> v) {
    if (q.contains('ProdutoPorBgg')) {
      final id = produtosPorBgg[v['bgg']];
      return {'product': [if (id != null) {'id': id}]};
    }
    if (q.contains('ProdutoPorNome')) {
      final id = produtosPorNome[_semEscape(v['nome'] as String).toLowerCase()];
      return {'product': [if (id != null) {'id': id}]};
    }
    if (q.contains('query Dono')) {
      final achado = participantes.where((p) =>
          p['user_id'] == v['me'] && p['participant_user_id'] == v['me']);
      return {'play_participant': [for (final p in achado) {'id': p['id']}]};
    }
    if (q.contains('query Jogador')) {
      final nome = _semEscape(v['nome'] as String).toLowerCase();
      final achado = participantes.where((p) =>
          p['user_id'] == v['me'] && '${p['name']}'.toLowerCase() == nome);
      return {'play_participant': [for (final p in achado.take(1)) {'id': p['id']}]};
    }
    if (q.contains('insert_play_participant_one')) {
      final o = (v['object'] as Map).cast<String, Object?>();
      final p = {...o, 'id': proximoId++, 'user_id': 42};
      participantes.add(p);
      return {'insert_play_participant_one': {'id': p['id']}};
    }
    if (q.contains('insert_play_one')) {
      final id = proximoId++;
      partidas[id] = (v['object'] as Map).cast<String, Object?>();
      return {'insert_play_one': {'id': id}};
    }
    if (q.contains('deletePlayAndAssociations')) {
      final id = v['playId'] as int;
      apagadas.add(id);
      final existia = partidas.remove(id) != null;
      return {'delete_play_by_pk': existia ? {'id': id} : null};
    }
    throw StateError('operação inesperada: $q');
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('conta lida do token', () {
    test('o id é o sub, como no site', () {
      final c = ContaComparajogos.doToken(tokenBom)!;
      expect(c.id, 42);
      expect(c.username, 'matheus');
      expect(c.exibicao, 'Matheus Merlim');
    });

    test('texto que não é JWT vira nulo', () {
      expect(ContaComparajogos.doToken(null), isNull);
      expect(ContaComparajogos.doToken('abc'), isNull);
      expect(ContaComparajogos.doToken(jwt({'sub': 'x'})), isNull);
    });

    test('o dono é reconhecido no placar pelo usuário, nome ou primeiro nome', () {
      final c = ContaComparajogos.doToken(tokenBom)!;
      expect(EnvioDePartidas.ehODono('Matheus', c), isTrue);
      expect(EnvioDePartidas.ehODono('matheus merlim', c), isTrue);
      expect(EnvioDePartidas.ehODono(' MATHEUS ', c), isTrue);
      expect(EnvioDePartidas.ehODono('Ana', c), isFalse);
      expect(EnvioDePartidas.ehODono('', c), isFalse);
    });
  });

  group('envio de uma partida', () {
    late ComparajogosFalso cj;
    late EnvioDePartidas envio;

    setUp(() {
      cj = ComparajogosFalso();
      envio = EnvioDePartidas(fonte: FonteFixa([tokenBom]), client: cj.client);
    });

    test('monta a partida como o site: segundos, MANUAL, placar e token', () async {
      final id = await envio.criar(PartidaParaEnviar(
        nomesJogo: const ['Wingspan'],
        bggId: 174430,
        data: DateTime(2026, 11, 9),
        duracaoMinutos: 95,
        notas: 'revanche',
        jogadores: const [
          JogadorParaEnviar(nome: 'Matheus', pontos: 87, venceu: true),
          JogadorParaEnviar(nome: 'Ana', pontos: 80),
        ],
      ));

      final p = cj.partidas[id]!;
      expect(p['product_id'], 900);
      expect(p['date'], '2026-11-09');
      expect(p['duration'], 95 * 60);
      expect(p['notes'], 'revanche');
      expect(p['win_condition'], 'MANUAL');
      expect(p['draft'], false);

      final jogadores = ((p['participants'] as Map)['data'] as List).cast<Map>();
      expect(jogadores, hasLength(2));
      expect(jogadores[0]['turn_order'], 1);
      expect(jogadores[0]['total_points'], 87);
      expect(jogadores[0]['is_winner'], true);
      expect(jogadores[1]['is_winner'], false);

      // "Matheus" virou o participante ligado à conta; "Ana" foi criada.
      final dono = cj.participantes.firstWhere((x) => x['participant_user_id'] == 42);
      expect(jogadores[0]['participant_id'], dono['id']);
      expect(cj.participantes.where((x) => x['name'] == 'Ana'), hasLength(1));

      expect(cj.headers.every((h) => h['Authorization'] == 'Bearer $tokenBom'), isTrue);
    });

    test('reaproveita os participantes que já existem', () async {
      final base = PartidaParaEnviar(
        nomesJogo: const ['Azul'],
        data: DateTime(2026, 11, 9),
        jogadores: const [
          JogadorParaEnviar(nome: 'Matheus'),
          JogadorParaEnviar(nome: 'Ana'),
        ],
      );
      await envio.criar(base);
      await envio.criar(base);
      expect(cj.participantes, hasLength(2));
    });

    test('sem placar vai só o dono, e sem duração vai zero', () async {
      final id = await envio.criar(PartidaParaEnviar(
        nomesJogo: const ['Azul'],
        data: DateTime(2026, 1, 2),
      ));
      final p = cj.partidas[id]!;
      expect(p['product_id'], 901);
      expect(p['duration'], 0);
      final jogadores = ((p['participants'] as Map)['data'] as List).cast<Map>();
      expect(jogadores, hasLength(1));
      expect(cj.participantes.single['participant_user_id'], 42);
    });

    test('pelo nome, tenta o português e depois o principal; expansão vira addon',
        () async {
      final id = await envio.criar(PartidaParaEnviar(
        nomesJogo: const ['Nome que não existe', 'Azul'],
        data: DateTime(2026, 1, 2),
        expansoes: const [
          (nomes: ['Azul: Pavilhão de Verão'], bggId: null),
          (nomes: ['Expansão desconhecida'], bggId: null),
        ],
      ));
      final p = cj.partidas[id]!;
      expect(p['product_id'], 901);
      expect((p['addons'] as Map)['data'], [
        {'product_id': 902}
      ]);
    });

    test('jogo que não existe lá é erro definitivo', () async {
      expect(
        () => envio.criar(PartidaParaEnviar(
          nomesJogo: const ['Jogo Inventado'],
          data: DateTime(2026, 1, 2),
        )),
        throwsA(isA<EnvioException>().having((e) => e.definitivo, 'definitivo', isTrue)),
      );
    });

    test('token vencido: pede outro uma vez e manda de novo', () async {
      final velho = jwt({'sub': '42', 'username': 'matheus', 'v': 1});
      cj.tokensRecusados.add(velho);
      final fonte = FonteFixa([velho, tokenBom]);
      envio = EnvioDePartidas(fonte: fonte, client: cj.client);

      await envio.criar(PartidaParaEnviar(nomesJogo: const ['Azul'], data: DateTime(2026)));
      expect(cj.partidas, hasLength(1));
      expect(fonte.renovacoes, [false, true]);
    });

    test('sem sessão é SemLoginException', () async {
      envio = EnvioDePartidas(fonte: FonteFixa([null]), client: cj.client);
      expect(
        () => envio.criar(PartidaParaEnviar(nomesJogo: const ['Azul'], data: DateTime(2026))),
        throwsA(isA<SemLoginException>()),
      );
    });
  });

  group('fila no aparelho', () {
    late Directory temp;
    late AppDatabase db;
    late GameRepository repo;
    late CollectionStore store;
    late ComparajogosFalso cj;
    late int azul;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('ludoteca_cj');
      db = AppDatabase.paraArquivo('${temp.path}/t.db');
      repo = GameRepository(database: db);
      azul = await repo.insertGame(const Game(name: 'Azul'));
      cj = ComparajogosFalso();
      store = CollectionStore(repository: repo)
        ..criarSincronizador = (r) => SincronizadorDePartidas(
              repo: r,
              envio: EnvioDePartidas(fonte: FonteFixa([tokenBom]), client: cj.client),
            );
      await store.load();
    });

    tearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });

    Future<void> entrar() =>
        store.entrarNoComparajogos(ContaComparajogos.doToken(tokenBom)!);

    Future<int?> cjIdDe(int playId) async {
      final d = await db.db;
      final r = await d.query('plays', where: 'id = ?', whereArgs: [playId]);
      return r.first['cj_play_id'] as int?;
    }

    test('sem login nada vai e nada entra na fila', () async {
      await store.logPlay(Play(gameId: azul, playedAt: DateTime(2026, 11, 1)));
      expect(await store.enviarPendentes(), isNull);
      expect(cj.partidas, isEmpty);
      expect((await repo.situacaoDoEnvio()).pendentes, 0);
    });

    test('partida antiga não vai ao entrar; a nova vai, com placar', () async {
      await store.logPlay(Play(gameId: azul, playedAt: DateTime(2026, 10, 1)));
      await entrar();
      await store.enviarPendentes();
      expect(cj.partidas, isEmpty);

      final id = await store.logPlay(
        Play(gameId: azul, playedAt: DateTime(2026, 11, 1), durationMinutes: 40),
        placar: const [PlayScore(playerName: 'Ana', score: 10, won: true)],
      );
      await store.enviarPendentes();

      expect(cj.partidas, hasLength(1));
      expect(await cjIdDe(id), cj.partidas.keys.single);
      expect(store.situacaoEnvio.pendentes, 0);
      final p = cj.partidas.values.single;
      expect(p['duration'], 2400);
    });

    test('sem cronometrar vai a média do jogo, como o app conta', () async {
      final castle = await repo.insertGame(
          const Game(name: 'Azul', minPlaytime: 20, maxPlaytime: 30));
      await store.refresh();
      await entrar();
      await store.logPlay(Play(gameId: castle, playedAt: DateTime(2026, 11, 11)));
      await store.enviarPendentes();
      expect(cj.partidas.values.single['duration'], 25 * 60);
    });

    test('jogo sem duração cadastrada e sem cronômetro vai zero', () async {
      await entrar();
      await store.logPlay(Play(gameId: azul, playedAt: DateTime(2026, 11, 11)));
      await store.enviarPendentes();
      expect(cj.partidas.values.single['duration'], 0);
    });

    test('sem rede fica na fila e vai na rodada seguinte', () async {
      await entrar();
      cj.semRede = true;
      final id = await store.logPlay(Play(gameId: azul, playedAt: DateTime(2026, 11, 1)));
      final r = await store.enviarPendentes();
      expect(r!.erro, isNotNull);
      expect(store.situacaoEnvio.pendentes, 1);
      expect(await cjIdDe(id), isNull);

      cj.semRede = false;
      await store.enviarPendentes();
      expect(cj.partidas, hasLength(1));
      expect(store.situacaoEnvio.pendentes, 0);
    });

    test('apagar aqui apaga lá, mesmo se a conexão só voltar depois', () async {
      await entrar();
      final id = await store.logPlay(Play(gameId: azul, playedAt: DateTime(2026, 11, 1)));
      await store.enviarPendentes();
      final cjId = cj.partidas.keys.single;

      cj.semRede = true;
      await store.deletePlay(id);
      await store.enviarPendentes();
      expect(cj.partidas, hasLength(1));
      expect(store.situacaoEnvio.pendentes, 1);

      cj.semRede = false;
      await store.enviarPendentes();
      expect(cj.partidas, isEmpty);
      expect(cj.apagadas, [cjId]);
      expect(store.situacaoEnvio.pendentes, 0);
    });

    test('editar troca a cópia de lá pela nova', () async {
      await entrar();
      final id = await store.logPlay(Play(gameId: azul, playedAt: DateTime(2026, 11, 1)));
      await store.enviarPendentes();
      final antigo = cj.partidas.keys.single;

      final play = (await repo.playById(id))!;
      await store.updatePlay(play.copyWith(durationMinutes: 75));
      await store.enviarPendentes();

      expect(cj.apagadas, [antigo]);
      expect(cj.partidas, hasLength(1));
      expect(cj.partidas.values.single['duration'], 75 * 60);
      expect(await cjIdDe(id), cj.partidas.keys.single);
    });

    test('editar partida de antes do login não manda (evita cópia)', () async {
      final id = await store.logPlay(Play(gameId: azul, playedAt: DateTime(2026, 10, 1)));
      await entrar();
      final play = (await repo.playById(id))!;
      await store.updatePlay(play.copyWith(durationMinutes: 30));
      await store.enviarPendentes();
      expect(cj.partidas, isEmpty);
    });

    test('jogo que não existe lá sai da fila com o motivo, e dá para tentar de novo',
        () async {
      final inventado = await repo.insertGame(const Game(name: 'Jogo Inventado'));
      await store.refresh();
      await entrar();
      await store.logPlay(Play(gameId: inventado, playedAt: DateTime(2026, 11, 1)));
      await store.enviarPendentes();

      expect(store.situacaoEnvio, (pendentes: 0, comErro: 1));
      final erros = await repo.errosDeEnvio();
      expect(erros.single.motivo, contains('Jogo Inventado'));

      cj.produtosPorNome['jogo inventado'] = 905;
      await store.tentarDeNovoOsEnviosComErro();
      expect(store.situacaoEnvio, (pendentes: 0, comErro: 0));
      expect(cj.partidas.values.single['product_id'], 905);
    });

    test('caixa de série vai como o jogo; expansão vai como addon', () async {
      final base = await repo.insertGame(const Game(name: 'Azul'));
      final exp = await repo.insertGame(Game(
          name: 'Azul: Pavilhão de Verão', parentId: base, linkKind: LinkKind.expansao));
      await store.refresh();
      await entrar();
      await store.logPlay(Play(gameId: base, playedAt: DateTime(2026, 11, 1), itemGameId: exp));
      await store.enviarPendentes();
      final p = cj.partidas.values.single;
      expect(p['product_id'], 901);
      expect((p['addons'] as Map)['data'], [
        {'product_id': 902}
      ]);
    });

    test('sessão expirada para a rodada e avisa', () async {
      store.criarSincronizador = (r) => SincronizadorDePartidas(
            repo: r,
            envio: EnvioDePartidas(fonte: FonteFixa([null]), client: cj.client),
          );
      await entrar();
      await store.logPlay(Play(gameId: azul, playedAt: DateTime(2026, 11, 1)));
      final r = await store.enviarPendentes();
      expect(r!.semLogin, isTrue);
      expect(store.ultimaRodadaDeEnvio!.semLogin, isTrue);
      expect(store.situacaoEnvio.pendentes, 1);
    });

    test('sair para de enviar, mas guarda a fila', () async {
      await entrar();
      cj.semRede = true;
      await store.logPlay(Play(gameId: azul, playedAt: DateTime(2026, 11, 1)));
      await store.enviarPendentes();
      await store.sairDoComparajogos();
      cj.semRede = false;
      expect(await store.enviarPendentes(), isNull);
      expect(cj.partidas, isEmpty);
      expect((await repo.situacaoDoEnvio()).pendentes, 1);
    });
  });

  test('migração 11 → 12 repõe na fila as partidas que foram com duração zero',
      () async {
    final temp = await Directory.systemTemp.createTemp('ludoteca_cj_mig');
    final caminho = '${temp.path}/v11.db';
    final antigo = await databaseFactory.openDatabase(
      caminho,
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: (db, v) => db.execute('''
          CREATE TABLE plays (
            id INTEGER PRIMARY KEY, duration_minutes INTEGER,
            cj_play_id INTEGER, cj_pendente INTEGER NOT NULL DEFAULT 0,
            cj_erro TEXT)
        '''),
      ),
    );
    await antigo.insert('plays', {'id': 1, 'cj_play_id': 65454});             // média: volta
    await antigo.insert('plays', {'id': 2, 'cj_play_id': 7, 'duration_minutes': 40}); // fica
    await antigo.insert('plays', {'id': 3});                                    // nunca foi: fica
    await antigo.close();

    final db = AppDatabase.paraArquivo(caminho);
    final d = await db.db;
    expect(await d.getVersion(), AppDatabase.versaoAtual);
    final linhas = {
      for (final m in await d.query('plays')) m['id']: m['cj_pendente'],
    };
    expect(linhas, {1: 1, 2: 0, 3: 0});
    await db.close();
    await temp.delete(recursive: true);
  });
}
