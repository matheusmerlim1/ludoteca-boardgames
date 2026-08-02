import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ludoteca/services/comparajogos_service.dart';
import 'package:ludoteca/services/game_catalog.dart';

/// Testes do cliente do Comparajogos.
///
/// As respostas falsas abaixo têm o formato exato que a API devolveu quando
/// foi verificada — inclusive as pegadinhas: `best_players` vem como lista de
/// **strings**, e as expansões vêm embrulhadas num objeto `expansion`.

http.Response _ok(Map<String, Object?> data) =>
    http.Response(jsonEncode({'data': data}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

const _marvel = {
  'id': 27956,
  'name': 'Marvel Champions: The Card Game',
  'year': 2019,
  'image_url': 'https://uploads.comparajogos.com.br/img/grande.jpg',
  'thumbnail_url': 'https://uploads.comparajogos.com.br/img/thumb.jpg',
  'min_players': 1,
  'max_players': 4,
  'best_players': ['2', '1'],
  'min_playtime': 45,
  'max_playtime': 90,
  'playing_time': 90,
  'bgg_id': 285774,
  'bgg_weight': 2.949,
  'type': 'game',
  'product_price': {
    'min_price': 899.90,
    'min_price_new': 969.99,
    'available': true,
    'stores_count': 3,
  },
  'expansions': [
    {
      'expansion': {
        'id': 30073,
        'name': 'Captain America Hero Pack',
        'year': 2019,
        'thumbnail_url': 'https://uploads.comparajogos.com.br/img/cap.png',
      }
    },
    {
      'expansion': {
        'id': 30072,
        'name': 'Black Widow Hero Pack',
        'year': 2020,
        'thumbnail_url': null,
      }
    },
  ],
};

void main() {
  group('busca', () {
    test('termo curto não chega a bater na rede', () async {
      var chamou = false;
      final cliente = MockClient((_) async {
        chamou = true;
        return _ok({'product': const []});
      });

      final r = await ComparajogosService(client: cliente).search('a');

      expect(r, isEmpty);
      expect(chamou, isFalse);
    });

    /// Extrai os `_ilike` que a busca montou, na ordem.
    List<String> curingas(Map<String, dynamic> corpo) {
      final and = (corpo['variables'] as Map)['where']['_and'] as List;
      return and
          .map((c) => (c as Map)['name_unaccented']['_ilike'] as String)
          .toList();
    }

    test('envia GraphQL por POST', () async {
      Map<String, dynamic>? corpo;
      final cliente = MockClient((req) async {
        corpo = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.method, 'POST');
        return _ok({'product': const []});
      });

      await ComparajogosService(client: cliente).search('catan');

      expect(corpo!['query'], contains('product'));
      expect(curingas(corpo!), ['%catan%']);
    });

    test('busca na coluna sem acento, tirando o acento do que foi digitado',
        () async {
      // "Caçadores da Galáxia" está gravado lá como "Cacadores da Galaxia".
      // Digitando com acento ou sem, a busca tem de achar do mesmo jeito.
      Map<String, dynamic>? corpo;
      final cliente = MockClient((req) async {
        corpo = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok({'product': const []});
      });

      await ComparajogosService(client: cliente).search('Caçadores da Galáxia');

      expect(curingas(corpo!), ['%cacadores%', '%da%', '%galaxia%']);
    });

    test('uma condição por palavra: a ordem digitada não importa', () async {
      // Procurar a frase inteira exigiria aquela ordem exata, com aquelas
      // palavras no meio. Separado, "catan colonizadores" também acha
      // "Os Colonizadores de Catan".
      Map<String, dynamic>? corpo;
      final cliente = MockClient((req) async {
        corpo = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok({'product': const []});
      });

      await ComparajogosService(client: cliente).search('catan colonizadores');

      expect(curingas(corpo!), ['%catan%', '%colonizadores%']);
    });

    test('pontuação não vira condição de busca', () async {
      Map<String, dynamic>? corpo;
      final cliente = MockClient((req) async {
        corpo = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok({'product': const []});
      });

      await ComparajogosService(client: cliente)
          .search('Unmatched: Robin Hood vs. Pé-Grande');

      expect(
        curingas(corpo!),
        ['%unmatched%', '%robin%', '%hood%', '%vs%', '%pe%', '%grande%'],
      );
    });

    test('palavra de uma letra é descartada', () async {
      // "%e%" casaria com quase todo o catálogo e afogaria o resultado.
      // Em "É Top", o que importa é "top".
      Map<String, dynamic>? corpo;
      final cliente = MockClient((req) async {
        corpo = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok({'product': const []});
      });

      await ComparajogosService(client: cliente).search('É Top');

      expect(curingas(corpo!), ['%top%']);
    });

    test('termo só de uma letra ainda busca, em vez de virar nada', () async {
      Map<String, dynamic>? corpo;
      final cliente = MockClient((req) async {
        corpo = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok({'product': const []});
      });

      // Dois caracteres passam pelo mínimo da busca, mas viram uma palavra
      // de uma letra depois de tirar a pontuação.
      await ComparajogosService(client: cliente).search('7!');

      expect(curingas(corpo!), ['%7%']);
    });

    test('lê os resultados e marca expansão pelo campo type', () async {
      final cliente = MockClient((_) async => _ok({
            'product': [
              {
                'id': 1,
                'name': 'Catan',
                'year': 1995,
                'thumbnail_url': 't.jpg',
                'type': 'game',
              },
              {
                'id': 2,
                'name': 'Catan: Navegadores',
                'year': 1997,
                'thumbnail_url': null,
                'type': 'expansion',
              },
            ]
          }));

      final r = await ComparajogosService(client: cliente).search('catan');

      expect(r.length, 2);
      expect(r.first.name, 'Catan');
      expect(r.first.id, 1);
      expect(r.first.source, CatalogSource.comparajogos);
      expect(r.first.isExpansion, isFalse);
      expect(r[1].isExpansion, isTrue);
    });

    test('casamento exato sobe, mesmo vindo depois na resposta', () async {
      final cliente = MockClient((_) async => _ok({
            'product': [
              {'id': 9, 'name': 'Catan Junior', 'type': 'game'},
              {'id': 1, 'name': 'Catan', 'type': 'game'},
            ]
          }));

      final r = await ComparajogosService(client: cliente).search('catan');

      expect(r.first.name, 'Catan');
    });

    test('jogo-base vem antes de expansão quando o resto empata', () async {
      final cliente = MockClient((_) async => _ok({
            'product': [
              {'id': 2, 'name': 'Zumbi Expansão', 'type': 'expansion'},
              {'id': 1, 'name': 'Zumbi Jogo', 'type': 'game'},
            ]
          }));

      final r = await ComparajogosService(client: cliente).search('zumbi');

      expect(r.first.isExpansion, isFalse);
    });
  });

  group('ficha do jogo', () {
    test('lê os campos principais', () async {
      final cliente =
          MockClient((_) async => _ok({'product_by_pk': _marvel}));

      final d = await ComparajogosService(client: cliente).details(27956);

      expect(d.source, CatalogSource.comparajogos);
      expect(d.id, 27956);
      expect(d.name, 'Marvel Champions: The Card Game');
      expect(d.year, 2019);
      expect(d.minPlayers, 1);
      expect(d.maxPlayers, 4);
      expect(d.minPlaytime, 45);
      expect(d.maxPlaytime, 90);
      expect(d.weight, closeTo(2.949, 0.001));
      expect(d.imageUrl, contains('grande.jpg'));
      expect(d.thumbUrl, contains('thumb.jpg'));
      expect(d.isExpansion, isFalse);
    });

    test('traz o bgg_id, para o jogo nascer cruzável com o BGG', () async {
      final cliente =
          MockClient((_) async => _ok({'product_by_pk': _marvel}));

      final d = await ComparajogosService(client: cliente).details(27956);

      expect(d.bggId, 285774);
    });

    test('best_players vem como lista de strings; fica o menor', () async {
      // A API devolve ["2","1"]. O app guarda um número só, e o menor é o mais
      // útil como sugestão ao registrar partida.
      final cliente =
          MockClient((_) async => _ok({'product_by_pk': _marvel}));

      final d = await ComparajogosService(client: cliente).details(27956);

      expect(d.bestPlayers, 1);
    });

    test('sem min/max de duração, cai para playing_time', () async {
      final cliente = MockClient((_) async => _ok({
            'product_by_pk': {
              'id': 5,
              'name': 'X',
              'playing_time': 60,
              'type': 'game',
            }
          }));

      final d = await ComparajogosService(client: cliente).details(5);

      expect(d.minPlaytime, 60);
      expect(d.maxPlaytime, 60);
    });

    test('ficha inexistente vira erro claro', () async {
      final cliente = MockClient((_) async => _ok({'product_by_pk': null}));

      await expectLater(
        ComparajogosService(client: cliente).details(999),
        throwsA(isA<CatalogException>()),
      );
    });
  });

  group('expansões', () {
    test('desembrulha o objeto expansion e ordena por nome', () async {
      final cliente =
          MockClient((_) async => _ok({'product_by_pk': _marvel}));

      final d = await ComparajogosService(client: cliente).details(27956);

      expect(d.expansions.length, 2);
      // Black Widow vem depois no JSON mas antes no alfabeto.
      expect(d.expansions.first.name, 'Black Widow Hero Pack');
      expect(d.expansions.first.id, 30072);
      expect(d.expansions[1].name, 'Captain America Hero Pack');
      expect(d.expansions[1].thumbUrl, contains('cap.png'));
    });

    test('jogo sem expansões devolve lista vazia, não nulo', () async {
      final cliente = MockClient((_) async => _ok({
            'product_by_pk': {'id': 5, 'name': 'X', 'type': 'game'}
          }));

      final d = await ComparajogosService(client: cliente).details(5);

      expect(d.expansions, isEmpty);
    });

    test('detailsBatch pega várias fichas numa requisição só', () async {
      var chamadas = 0;
      Map<String, dynamic>? corpo;
      final cliente = MockClient((req) async {
        chamadas++;
        corpo = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok({
          'product': [
            {'id': 1, 'name': 'A', 'type': 'expansion'},
            {'id': 2, 'name': 'B', 'type': 'expansion'},
          ]
        });
      });

      final r =
          await ComparajogosService(client: cliente).detailsBatch([1, 2]);

      expect(chamadas, 1);
      expect((corpo!['variables'] as Map)['ids'], [1, 2]);
      expect(r.length, 2);
      expect(r.first.isExpansion, isTrue);
    });

    test('detailsBatch com lista vazia não bate na rede', () async {
      var chamou = false;
      final cliente = MockClient((_) async {
        chamou = true;
        return _ok({'product': const []});
      });

      final r = await ComparajogosService(client: cliente).detailsBatch([]);

      expect(r, isEmpty);
      expect(chamou, isFalse);
    });
  });

  group('preço de referência', () {
    test('prefere o preço de item novo', () async {
      final cliente =
          MockClient((_) async => _ok({'product_by_pk': _marvel}));

      final d = await ComparajogosService(client: cliente).details(27956);

      // min_price é 899,90 e min_price_new é 969,99: vale o de novo, porque
      // "usado" varia demais para servir de sugestão.
      expect(d.referencePrice, 969.99);
      expect(d.priceNote, contains('3 lojas'));
    });

    test('sem preço de novo, cai para o menor preço geral', () async {
      final cliente = MockClient((_) async => _ok({
            'product_by_pk': {
              'id': 5,
              'name': 'X',
              'type': 'game',
              'product_price': {
                'min_price': 120.0,
                'min_price_new': null,
                'available': true,
                'stores_count': 1,
              },
            }
          }));

      final d = await ComparajogosService(client: cliente).details(5);

      expect(d.referencePrice, 120.0);
      expect(d.priceNote, contains('1 loja'));
    });

    test('fora de estoque, a nota avisa que o preço é antigo', () async {
      final cliente = MockClient((_) async => _ok({
            'product_by_pk': {
              'id': 5,
              'name': 'X',
              'type': 'game',
              'product_price': {
                'min_price_new': 300.0,
                'available': false,
                'stores_count': 0,
              },
            }
          }));

      final d = await ComparajogosService(client: cliente).details(5);

      expect(d.referencePrice, 300.0);
      expect(d.priceNote, contains('fora de estoque'));
    });

    test('sem bloco de preço, não inventa número nem nota', () async {
      final cliente = MockClient((_) async => _ok({
            'product_by_pk': {'id': 5, 'name': 'X', 'type': 'game'}
          }));

      final d = await ComparajogosService(client: cliente).details(5);

      expect(d.referencePrice, isNull);
      expect(d.priceNote, isNull);
    });

    test('preço zero conta como ausente', () async {
      final cliente = MockClient((_) async => _ok({
            'product_by_pk': {
              'id': 5,
              'name': 'X',
              'type': 'game',
              'product_price': {'min_price_new': 0, 'available': true},
            }
          }));

      final d = await ComparajogosService(client: cliente).details(5);

      expect(d.referencePrice, isNull);
    });
  });

  group('listas públicas', () {
    /// A API corta em 15 linhas por consulta e **ignora o `limit`**. Uma lista
    /// de 40 jogos viria pela metade, sem erro nenhum — o pior tipo de falha.
    test('pagina até trazer a lista inteira', () async {
      var chamadas = 0;
      final offsetsPedidos = <int>[];

      final cliente = MockClient((req) async {
        final corpo = jsonDecode(req.body) as Map<String, dynamic>;
        final query = corpo['query'] as String;
        chamadas++;

        if (query.contains('lists(')) {
          return _ok({
            'lists': [
              {
                'id': 'abc',
                'name': 'Desejos',
                'type': 'WISH',
                'items_aggregate': {
                  'aggregate': {'count': 40}
                },
              }
            ]
          });
        }

        final vars = corpo['variables'] as Map<String, dynamic>;
        final offset = vars['offset'] as int;
        offsetsPedidos.add(offset);

        // 40 itens ao todo: 15, 15 e 10.
        final nesta = (40 - offset).clamp(0, 15);
        return _ok({
          'list_item': [
            for (var i = 0; i < nesta; i++)
              {
                'product': {
                  'id': offset + i,
                  'name': 'Jogo ${offset + i}',
                  'type': 'game',
                }
              }
          ]
        });
      });

      final listas =
          await ComparajogosService(client: cliente).publicLists('alguem');

      expect(listas.single.games.length, 40, reason: 'trouxe a lista inteira');
      expect(offsetsPedidos, [0, 15, 30]);
      expect(chamadas, 4, reason: '1 de metadados + 3 páginas');
    });

    test('lista vazia não dispara consulta de itens', () async {
      var paginas = 0;
      final cliente = MockClient((req) async {
        final corpo = jsonDecode(req.body) as Map<String, dynamic>;
        if ((corpo['query'] as String).contains('list_item')) paginas++;
        return _ok({
          'lists': [
            {
              'id': 'abc',
              'name': 'Vazia',
              'type': 'WISH',
              'items_aggregate': {
                'aggregate': {'count': 0}
              },
            }
          ]
        });
      });

      final listas =
          await ComparajogosService(client: cliente).publicLists('alguem');

      expect(listas.single.games, isEmpty);
      expect(paginas, 0);
    });

    test('para de paginar se a página vier vazia antes da conta', () async {
      // Guarda contra laço infinito caso o total declarado não bata com o que
      // a API entrega de fato.
      var paginas = 0;
      final cliente = MockClient((req) async {
        final corpo = jsonDecode(req.body) as Map<String, dynamic>;
        if ((corpo['query'] as String).contains('lists(')) {
          return _ok({
            'lists': [
              {
                'id': 'abc',
                'name': 'Desejos',
                'type': 'WISH',
                'items_aggregate': {
                  'aggregate': {'count': 900}
                },
              }
            ]
          });
        }
        paginas++;
        return _ok({'list_item': const []});
      });

      final listas =
          await ComparajogosService(client: cliente).publicLists('alguem');

      expect(listas.single.games, isEmpty);
      expect(paginas, 1, reason: 'parou na primeira página vazia');
    });

    test('username vazio não vai à rede', () async {
      var chamou = false;
      final cliente = MockClient((_) async {
        chamou = true;
        return _ok({'lists': const []});
      });

      final r = await ComparajogosService(client: cliente).publicLists('  ');

      expect(r, isEmpty);
      expect(chamou, isFalse);
    });

    test('classifica os tipos de lista do catálogo', () {
      expect(CatalogListKind.fromApi('WISH'), CatalogListKind.desejos);
      expect(CatalogListKind.fromApi('OWN'), CatalogListKind.colecao);
      expect(CatalogListKind.fromApi('PRICE_ALERT'),
          CatalogListKind.alertaDePreco);
      expect(CatalogListKind.fromApi(null), CatalogListKind.outra);

      // As duas que alimentam a lista de desejos do app.
      expect(CatalogListKind.desejos.eDesejo, isTrue);
      expect(CatalogListKind.alertaDePreco.eDesejo, isTrue);
      expect(CatalogListKind.colecao.eDesejo, isFalse);
      expect(CatalogListKind.troca.eDesejo, isFalse);
    });
  });

  group('erros', () {
    test('GraphQL responde 200 com erro no corpo — vira exceção', () async {
      // Esta é a pegadinha do GraphQL: falha não vem como status HTTP.
      final cliente = MockClient((_) async => http.Response(
            jsonEncode({
              'errors': [
                {'message': "field 'xpto' not found"}
              ]
            }),
            200,
          ));

      await expectLater(
        ComparajogosService(client: cliente).search('catan'),
        throwsA(isA<CatalogException>()),
      );
    });

    test('status HTTP de erro vira exceção', () async {
      final cliente =
          MockClient((_) async => http.Response('nope', 503));

      await expectLater(
        ComparajogosService(client: cliente).search('catan'),
        throwsA(isA<CatalogException>()),
      );
    });

    test('corpo que não é JSON vira exceção clara', () async {
      final cliente =
          MockClient((_) async => http.Response('<html>erro</html>', 200));

      await expectLater(
        ComparajogosService(client: cliente).search('catan'),
        throwsA(isA<CatalogException>()),
      );
    });

    test('acentuação sobrevive à decodificação', () async {
      // O corpo vem em UTF-8; decodificar como latin-1 quebraria "Expansão".
      final cliente = MockClient((_) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'data': {
                'product': [
                  {'id': 1, 'name': 'Coleção de Expansões', 'type': 'game'}
                ]
              }
            })),
            200,
          ));

      final r = await ComparajogosService(client: cliente).search('colecao');

      expect(r.first.name, 'Coleção de Expansões');
    });
  });
}
