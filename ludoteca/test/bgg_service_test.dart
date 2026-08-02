import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ludoteca/services/bgg_service.dart';
import 'package:ludoteca/services/game_catalog.dart';

/// Testes do cliente do BGG com um `http.Client` falso.
///
/// A API real exige token desde o fim de outubro de 2025, então não há como
/// testar contra ela aqui. O que importa verificar é o comportamento do nosso
/// lado: que o token vai no cabeçalho certo, que 401 falha na hora em vez de
/// insistir, e que o XML é lido como esperado.

/// XML de `/search` com dois resultados.
const _xmlBusca = '''
<?xml version="1.0" encoding="utf-8"?>
<items total="2">
  <item type="boardgame" id="13">
    <name type="primary" value="CATAN"/>
    <yearpublished value="1995"/>
  </item>
  <item type="boardgameexpansion" id="926">
    <name type="primary" value="CATAN: Seafarers"/>
    <yearpublished value="1997"/>
  </item>
</items>
''';

/// XML de `/thing` com enquete de jogadores e links de expansão.
const _xmlThing = '''
<?xml version="1.0" encoding="utf-8"?>
<items>
  <item type="boardgame" id="285774">
    <thumbnail>https://cf.geekdo-images.com/thumb.jpg</thumbnail>
    <image>https://cf.geekdo-images.com/original.jpg</image>
    <name type="alternate" value="Nome alternativo"/>
    <name type="primary" value="Marvel Champions: The Card Game"/>
    <description>Um jogo &amp;quot;cooperativo&amp;quot;.&lt;br/&gt;Segunda linha.</description>
    <yearpublished value="2019"/>
    <minplayers value="1"/>
    <maxplayers value="4"/>
    <playingtime value="90"/>
    <minplaytime value="45"/>
    <maxplaytime value="90"/>
    <link type="boardgameexpansion" id="300001" value="The Rise of Red Skull"/>
    <link type="boardgameexpansion" id="300002" value="Galaxy's Most Wanted"/>
    <link type="boardgameexpansion" id="300002" value="Galaxy's Most Wanted"/>
    <link type="boardgamecategory" id="1002" value="Card Game"/>
    <poll name="suggested_numplayers" totalvotes="500">
      <results numplayers="1">
        <result value="Best" numvotes="120"/>
        <result value="Recommended" numvotes="200"/>
      </results>
      <results numplayers="2">
        <result value="Best" numvotes="300"/>
        <result value="Recommended" numvotes="150"/>
      </results>
      <results numplayers="4+">
        <result value="Best" numvotes="10"/>
      </results>
    </poll>
    <statistics>
      <ratings>
        <averageweight value="2.7143"/>
      </ratings>
    </statistics>
  </item>
</items>
''';

/// XML de uma expansão: o link de volta ao jogo-base vem com inbound="true".
const _xmlExpansao = '''
<?xml version="1.0" encoding="utf-8"?>
<items>
  <item type="boardgameexpansion" id="300001">
    <name type="primary" value="The Rise of Red Skull"/>
    <minplayers value="1"/>
    <maxplayers value="4"/>
    <link type="boardgameexpansion" id="285774" inbound="true"
          value="Marvel Champions: The Card Game"/>
  </item>
</items>
''';

void main() {
  group('autenticação', () {
    test('manda o token como Bearer no cabeçalho Authorization', () async {
      String? autorizacao;
      final cliente = MockClient((req) async {
        autorizacao = req.headers['Authorization'];
        return http.Response(_xmlBusca, 200);
      });

      final bgg = BggService(client: cliente, token: 'tok_abc123');
      await bgg.search('catan', comCapas: false);

      expect(autorizacao, 'Bearer tok_abc123');
    });

    test('sem token, não manda cabeçalho de autorização', () async {
      var tinhaHeader = true;
      final cliente = MockClient((req) async {
        tinhaHeader = req.headers.containsKey('Authorization');
        return http.Response(_xmlBusca, 200);
      });

      final bgg = BggService(client: cliente);
      await bgg.search('catan', comCapas: false);

      expect(tinhaHeader, isFalse);
    });

    test('token só com espaço em branco conta como ausente', () {
      final bgg = BggService(client: MockClient((_) async => http.Response('', 200)));
      bgg.token = '   ';
      expect(bgg.hasToken, isFalse);
      bgg.token = ' tok ';
      expect(bgg.hasToken, isTrue);
    });

    test('401 falha na primeira tentativa, sem insistir', () async {
      // Esse é o ponto do teste: 401 é permanente. Repetir só faz o usuário
      // olhar um spinner por 15 segundos antes de um erro genérico.
      var chamadas = 0;
      final cliente = MockClient((req) async {
        chamadas++;
        return http.Response('Unauthorized', 401);
      });

      final bgg = BggService(client: cliente, maxAttempts: 5);

      await expectLater(
        bgg.search('catan'),
        throwsA(isA<CatalogAuthException>()),
      );
      expect(chamadas, 1);
    });

    test('401 sem token orienta a cadastrar; com token, a conferir', () async {
      final cliente =
          MockClient((req) async => http.Response('Unauthorized', 401));

      try {
        await BggService(client: cliente).search('catan');
        fail('deveria ter lançado');
      } on CatalogAuthException catch (e) {
        expect(e.temToken, isFalse);
        expect(e.message, contains('cadastro'));
      }

      try {
        await BggService(client: cliente, token: 'ruim').search('catan');
        fail('deveria ter lançado');
      } on CatalogAuthException catch (e) {
        expect(e.temToken, isTrue);
        expect(e.message.toLowerCase(), contains('recusou'));
      }
    });

    test('403 também é tratado como falta de autorização', () async {
      final cliente = MockClient((_) async => http.Response('Forbidden', 403));
      await expectLater(
        BggService(client: cliente).search('catan'),
        throwsA(isA<CatalogAuthException>()),
      );
    });
  });

  group('202 e limite de taxa', () {
    test('202 é reconsultado até virar 200', () async {
      // O BGG responde 202 com corpo vazio quando enfileira o pedido. Não é
      // erro: é "pergunte de novo".
      var chamadas = 0;
      final cliente = MockClient((req) async {
        chamadas++;
        if (chamadas < 3) return http.Response('', 202);
        return http.Response(_xmlBusca, 200);
      });

      final bgg = BggService(client: cliente, maxAttempts: 5);
      final r = await bgg.search('catan', comCapas: false);

      expect(chamadas, 3);
      expect(r, isNotEmpty);
    });

    test('429 também é reconsultado', () async {
      var chamadas = 0;
      final cliente = MockClient((req) async {
        chamadas++;
        if (chamadas < 2) return http.Response('slow down', 429);
        return http.Response(_xmlBusca, 200);
      });

      final r = await BggService(client: cliente, maxAttempts: 4)
          .search('catan', comCapas: false);

      expect(chamadas, 2);
      expect(r, isNotEmpty);
    });

    test('esgotar as tentativas vira CatalogException, não CatalogAuthException',
        () async {
      final cliente = MockClient((_) async => http.Response('', 202));
      final bgg = BggService(client: cliente, maxAttempts: 2);

      await expectLater(
        bgg.search('catan'),
        throwsA(
          allOf(isA<CatalogException>(), isNot(isA<CatalogAuthException>())),
        ),
      );
    });
  });

  group('busca', () {
    test('termo curto não chega a bater na rede', () async {
      var chamou = false;
      final cliente = MockClient((_) async {
        chamou = true;
        return http.Response(_xmlBusca, 200);
      });

      final r = await BggService(client: cliente).search('a');

      expect(r, isEmpty);
      expect(chamou, isFalse);
    });

    test('casamento exato sobe no resultado', () async {
      // Digitando "catan", o jogo-base tem de vir antes da expansão
      // "CATAN: Seafarers", que também contém o termo.
      final cliente =
          MockClient((_) async => http.Response(_xmlBusca, 200));

      final r =
          await BggService(client: cliente).search('catan', comCapas: false);

      expect(r.first.name, 'CATAN');
      expect(r.first.id, 13);
      expect(r[1].isExpansion, isTrue);
    });
  });

  group('ficha do jogo', () {
    test('lê os campos principais', () async {
      final cliente = MockClient((_) async => http.Response(_xmlThing, 200));
      final d = await BggService(client: cliente).details(285774);

      // Pega o name type="primary", não o alternate que vem antes no XML.
      expect(d.name, 'Marvel Champions: The Card Game');
      expect(d.bggId, 285774);
      expect(d.year, 2019);
      expect(d.minPlayers, 1);
      expect(d.maxPlayers, 4);
      expect(d.minPlaytime, 45);
      expect(d.maxPlaytime, 90);
      expect(d.weight, closeTo(2.7143, 0.0001));
      expect(d.imageUrl, contains('original.jpg'));
      expect(d.thumbUrl, contains('thumb.jpg'));
      expect(d.isExpansion, isFalse);
    });

    test('melhor nº de jogadores é o mais votado como "Best"', () async {
      final cliente = MockClient((_) async => http.Response(_xmlThing, 200));
      final d = await BggService(client: cliente).details(285774);
      // 2 jogadores tem 300 votos "Best" contra 120 de 1 jogador.
      expect(d.bestPlayers, 2);
    });

    test('limpa entidades HTML e <br/> da descrição', () async {
      final cliente = MockClient((_) async => http.Response(_xmlThing, 200));
      final d = await BggService(client: cliente).details(285774);

      expect(d.description, contains('"cooperativo"'));
      expect(d.description, isNot(contains('&quot;')));
      expect(d.description, isNot(contains('<br')));
      expect(d.description, contains('\nSegunda linha.'));
    });
  });

  group('expansões', () {
    test('lista as expansões do jogo, sem duplicar e em ordem', () async {
      final cliente = MockClient((_) async => http.Response(_xmlThing, 200));
      final d = await BggService(client: cliente).details(285774);

      // O XML repete "Galaxy's Most Wanted" de propósito.
      expect(d.expansions.length, 2);
      expect(d.expansions.map((e) => e.name).toList(),
          ["Galaxy's Most Wanted", 'The Rise of Red Skull']);
      expect(d.expansions.first.id, 300002);
    });

    test('ignora links que não são de expansão', () async {
      final cliente = MockClient((_) async => http.Response(_xmlThing, 200));
      final d = await BggService(client: cliente).details(285774);
      // O link de categoria "Card Game" não pode entrar.
      expect(d.expansions.any((e) => e.name == 'Card Game'), isFalse);
    });

    test('na ficha de uma expansão, o jogo-base não aparece como expansão',
        () async {
      // O link para o jogo-base vem com inbound="true". Sem filtrar isso, abrir
      // uma expansão ofereceria o jogo-base como "expansão dela".
      final cliente = MockClient((_) async => http.Response(_xmlExpansao, 200));
      final d = await BggService(client: cliente).details(300001);

      expect(d.isExpansion, isTrue);
      expect(d.expansions, isEmpty);
    });

    test('detailsBatch traz várias fichas numa requisição só', () async {
      var chamadas = 0;
      Uri? uriUsada;
      final cliente = MockClient((req) async {
        chamadas++;
        uriUsada = req.url;
        return http.Response(_xmlThing, 200);
      });

      final fichas =
          await BggService(client: cliente).detailsBatch([285774, 300001]);

      expect(chamadas, 1);
      expect(uriUsada!.queryParameters['id'], '285774,300001');
      expect(fichas.length, 1); // o XML de teste só tem um item
    });

    test('detailsBatch com lista vazia não bate na rede', () async {
      var chamou = false;
      final cliente = MockClient((_) async {
        chamou = true;
        return http.Response(_xmlThing, 200);
      });

      final r = await BggService(client: cliente).detailsBatch([]);

      expect(r, isEmpty);
      expect(chamou, isFalse);
    });
  });
}
