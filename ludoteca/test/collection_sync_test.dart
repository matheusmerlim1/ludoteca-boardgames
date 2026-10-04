import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ludoteca/data/database.dart';
import 'package:ludoteca/data/game_repository.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/services/collection_sync_service.dart';
import 'package:ludoteca/services/comparajogos_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Comparação entre a coleção do app e a coleção pública do Comparajogos.
///
/// O que se testa aqui é sobretudo **não oferecer o que já se tem**: uma caixa
/// que sugere adicionar de novo trinta jogos que já estão na estante é pior que
/// não ter a função, porque o estrago (duplicatas, custos dobrados) só aparece
/// depois.

http.Response _ok(Map<String, Object?> data) => http.Response(
      jsonEncode({'data': data}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _produto(
  int id,
  String nome, {
  int? bggId,
  double? preco,
}) =>
    {
      'id': id,
      'name': nome,
      'year': 2020,
      'image_url': null,
      'thumbnail_url': null,
      'min_players': 1,
      'max_players': 4,
      'best_players': const <String>[],
      'min_playtime': 30,
      'max_playtime': 60,
      'playing_time': 60,
      'bgg_id': bggId,
      'bgg_weight': null,
      'type': 'game',
      'domains': const [],
      'categories': const [],
      'mechanics': const [],
      if (preco != null)
        'product_price': {
          'min_price': preco,
          'min_price_new': preco,
          'available': true,
          'stores_count': 1,
        },
    };

/// Responde às duas consultas que a leitura de uma lista pública faz: os
/// metadados das listas, e depois os itens de cada uma.
MockClient _catalogoCom(List<Map<String, Object?>> produtos, {String tipo = 'OWN'}) {
  return MockClient((req) async {
    final corpo = jsonDecode(req.body) as Map<String, dynamic>;
    final query = corpo['query'] as String;

    if (query.contains('lists(')) {
      return _ok({
        'lists': [
          {
            'id': 'lista-1',
            'name': 'Minha coleção',
            'type': tipo,
            'items_aggregate': {
              'aggregate': {'count': produtos.length},
            },
          }
        ],
      });
    }

    return _ok({
      'list_item': [for (final p in produtos) {'product': p}],
    });
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory temp;
  late AppDatabase db;
  late GameRepository repo;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ludoteca_sync');
    db = AppDatabase.paraArquivo('${temp.path}/t.db');
    repo = GameRepository(database: db);
  });

  tearDown(() async {
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  CollectionSyncService servicoCom(List<Map<String, Object?>> produtos,
      {String tipo = 'OWN'}) {
    return CollectionSyncService(
      repository: repo,
      catalogo: ComparajogosService(client: _catalogoCom(produtos, tipo: tipo)),
    );
  }

  test('separa o que está lá e não está aqui', () async {
    await repo.insertGame(const Game(name: 'Ark Nova', price: 400));

    final diff = await servicoCom([
      _produto(1, 'Ark Nova'),
      _produto(2, 'Wingspan', preco: 300),
    ]).comparar('matheusmerlim');

    expect(diff.jaTinha, 1);
    expect(diff.faltando.single.name, 'Wingspan');
    expect(diff.nomesDasListas, ['Minha coleção']);
  });

  test('acento e pontuação diferentes não viram jogo novo', () async {
    // "Caçadores da Galáxia" aqui e "Cacadores da Galaxia" lá são o mesmo jogo.
    // Sem normalizar, a caixa ofereceria uma duplicata da coleção inteira.
    await repo.insertGame(const Game(name: 'Caçadores da Galáxia'));

    final diff = await servicoCom([
      _produto(1, 'Cacadores da Galaxia'),
    ]).comparar('matheusmerlim');

    expect(diff.faltando, isEmpty);
    expect(diff.jaTinha, 1);
  });

  test('o nome em português também conta como conhecido', () async {
    await repo.insertGame(
      const Game(name: 'Wingspan', namePt: 'Asas'),
    );

    final diff = await servicoCom([_produto(1, 'Asas')])
        .comparar('matheusmerlim');

    expect(diff.faltando, isEmpty);
  });

  test('id do BGG casa mesmo com o nome escrito diferente', () async {
    await repo.insertGame(const Game(name: 'Dune: Imperium', bggId: 316554));

    final diff = await servicoCom([
      _produto(1, 'Duna Imperium — Edição Deluxe', bggId: 316554),
    ]).comparar('matheusmerlim');

    expect(diff.faltando, isEmpty);
  });

  test('lista que não é de coleção não entra', () async {
    // A lista de desejos tem tela própria; trazer os desejos para a estante
    // contaria como seu o que você ainda quer comprar.
    final diff = await servicoCom(
      [_produto(1, 'Wingspan')],
      tipo: 'WISH',
    ).comparar('matheusmerlim');

    expect(diff.semListas, isTrue);
    expect(diff.faltando, isEmpty);
  });

  test('importa como jogo seu, com o preço do catálogo quando pedido',
      () async {
    final servico = servicoCom([_produto(2, 'Wingspan', preco: 300)]);
    final diff = await servico.comparar('matheusmerlim');

    await servico.importar(diff.faltando);

    final salvo = (await repo.allGames()).single;
    expect(salvo.name, 'Wingspan');
    expect(salvo.isMine, isTrue);
    expect(salvo.price, 300);
    // Sem data de compra: o app não sabe quando foi, e chutar "hoje" faria o
    // custo por mês da coleção inteira nascer errado.
    expect(salvo.purchaseDate, isNull);
  });

  test('sem o preço do catálogo, entra zerado para você preencher', () async {
    final servico = servicoCom([_produto(2, 'Wingspan', preco: 300)]);
    final diff = await servico.comparar('matheusmerlim');

    await servico.importar(diff.faltando, usarPrecoDeReferencia: false);

    final salvo = (await repo.allGames()).single;
    expect(salvo.price, 0);
    // O preço de referência fica guardado de qualquer jeito: serve de palpite
    // na hora de preencher.
    expect(salvo.lastPrice, 300);
  });
}
