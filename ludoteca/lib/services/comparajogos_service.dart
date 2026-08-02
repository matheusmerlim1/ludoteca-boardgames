import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'game_catalog.dart';

/// Cliente do Comparajogos (GraphQL).
///
/// Fonte padrão do app, por três motivos práticos: funciona sem cadastro nem
/// token, os nomes vêm em português, e ela devolve o `bgg_id` de cada jogo —
/// então um jogo cadastrado por aqui já nasce cruzável com o BoardGameGeek.
///
/// Também traz o menor preço em reais, que o app usa como sugestão inicial no
/// campo de preço.
///
/// ⚠️ É uma API pública mas **não documentada** por eles. Pode mudar sem aviso.
/// Por isso o app grava tudo no banco local no momento do cadastro: se a API
/// sumir amanhã, a coleção continua inteira, e só o cadastro de jogo novo
/// deixa de autopreencher.
class ComparajogosService implements GameCatalog {
  ComparajogosService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _endpoint = 'https://api.comparajogos.com.br/v1/graphql';

  @override
  CatalogSource get source => CatalogSource.comparajogos;

  /// Campos da ficha, num fragmento só para busca e detalhe não divergirem.
  static const _camposJogo = '''
    id
    name
    year
    image_url
    thumbnail_url
    min_players
    max_players
    best_players
    min_playtime
    max_playtime
    playing_time
    bgg_id
    bgg_weight
    type
    domains { domain { name } }
    categories { category { name } }
    mechanics { mechanic { name } }
  ''';

  Future<Map<String, dynamic>> _query(
    String query, [
    Map<String, dynamic> variables = const {},
  ]) async {
    late http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(_endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'query': query, 'variables': variables}),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw CatalogException(
        'O Comparajogos demorou demais para responder.',
      );
    } catch (e) {
      throw CatalogException(
        'Não consegui falar com o Comparajogos. Verifique a conexão.',
      );
    }

    if (res.statusCode != 200) {
      throw CatalogException(
        'O Comparajogos respondeu ${res.statusCode}.',
      );
    }

    final Object? corpo;
    try {
      corpo = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw CatalogException('Resposta do Comparajogos veio malformada.');
    }

    if (corpo is! Map<String, dynamic>) {
      throw CatalogException('Resposta do Comparajogos veio inesperada.');
    }

    // GraphQL responde 200 mesmo com erro; o erro vem no corpo.
    final erros = corpo['errors'];
    if (erros is List && erros.isNotEmpty) {
      final msg = (erros.first as Map?)?['message'];
      throw CatalogException('O Comparajogos recusou a consulta: $msg');
    }

    final dados = corpo['data'];
    if (dados is! Map<String, dynamic>) {
      throw CatalogException('O Comparajogos não devolveu dados.');
    }
    return dados;
  }

  @override
  Future<List<CatalogSearchResult>> search(
    String query, {
    bool comCapas = true,
  }) async {
    final termo = query.trim();
    if (termo.length < 2) return const [];

    const gql = r'''
      query Busca($where: product_bool_exp!) {
        product(
          where: $where,
          limit: 25,
          order_by: [{bgg_ranking: asc_nulls_last}, {year: desc_nulls_last}]
        ) {
          id
          name
          year
          thumbnail_url
          type
        }
      }
    ''';

    final dados = await _query(gql, {'where': _condicoes(termo)});
    final lista = (dados['product'] as List?) ?? const [];

    final resultados = lista
        .whereType<Map<String, dynamic>>()
        .map((m) => CatalogSearchResult(
              source: CatalogSource.comparajogos,
              id: m['id'] as int,
              name: (m['name'] as String?) ?? 'Sem nome',
              year: m['year'] as int?,
              isExpansion: m['type'] == 'expansion',
              thumbUrl: m['thumbnail_url'] as String?,
            ))
        .toList();

    _ordenaPorRelevancia(resultados, termo);
    return resultados;
  }

  /// Monta a condição de busca: cada palavra tem de aparecer, em qualquer
  /// ordem, ignorando acento e pontuação.
  ///
  /// Três decisões, cada uma resolvendo um jeito real de a busca falhar:
  ///
  /// - Usa `name_unaccented`, coluna em que o próprio catálogo já guarda o
  ///   nome sem acento nem pontuação ("Caçadores da Galáxia: Colonizadores"
  ///   vira "Cacadores da Galaxia Colonizadores"). Assim "cacadores galaxia"
  ///   acha o jogo.
  /// - Uma condição **por palavra**, não a frase inteira: procurar
  ///   "%colonizadores de catan%" exige aquela ordem exata com aquelas
  ///   palavras no meio. Separado, "catan colonizadores" também acha.
  /// - Descarta palavras de uma letra. "%e%" casa com quase todo o catálogo e
  ///   afogaria o resultado — o que importa em "É Top" é "top".
  Map<String, Object?> _condicoes(String termo) {
    final normalizado = _semAcento(termo);

    final palavras =
        normalizado.split(' ').where((p) => p.length > 1).toList();

    // Só sobrou coisa de uma letra ("É", "7"): usa o termo como veio, senão a
    // busca não teria o que procurar.
    final alvos = palavras.isEmpty ? [normalizado] : palavras;

    return {
      '_and': [
        for (final p in alvos)
          {
            'name_unaccented': {'_ilike': '%$p%'}
          },
      ],
    };
  }

  /// Mesma normalização que a coluna `name_unaccented` do catálogo aplica.
  static String _semAcento(String bruto) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';

    var s = bruto.toLowerCase().trim();
    final buf = StringBuffer();
    for (final c in s.split('')) {
      final i = de.indexOf(c);
      buf.write(i >= 0 ? para[i] : c);
    }
    s = buf.toString();

    return s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  /// Um `_ilike` com curinga nos dois lados casa "Catan" dentro de dezenas de
  /// derivados. Sobe o casamento exato, depois o prefixo; o resto mantém a
  /// ordem que veio (ranking do BGG).
  void _ordenaPorRelevancia(List<CatalogSearchResult> lista, String termo) {
    final alvo = termo.toLowerCase();

    int nota(CatalogSearchResult r) {
      final n = r.name.toLowerCase();
      if (n == alvo) return 0;
      if (n.startsWith(alvo)) return 1;
      return 2;
    }

    // Ordenação estável: empates preservam a ordem original.
    final indice = {for (var i = 0; i < lista.length; i++) lista[i]: i};
    lista.sort((a, b) {
      final porNota = nota(a).compareTo(nota(b));
      if (porNota != 0) return porNota;
      if (a.isExpansion != b.isExpansion) return a.isExpansion ? 1 : -1;
      return indice[a]!.compareTo(indice[b]!);
    });
  }

  @override
  Future<CatalogGameDetails> details(int id) async {
    const gql = '''
      query Ficha(\$id: Int!) {
        product_by_pk(id: \$id) {
          $_camposJogo
          product_price { min_price min_price_new available stores_count }
          expansions { expansion { id name year thumbnail_url } }
        }
      }
    ''';

    final dados = await _query(gql, {'id': id});
    final m = dados['product_by_pk'];
    if (m is! Map<String, dynamic>) {
      throw CatalogException('O Comparajogos não achou o jogo $id.');
    }
    return _parse(m);
  }

  @override
  Future<List<CatalogGameDetails>> detailsBatch(List<int> ids) async {
    if (ids.isEmpty) return const [];

    const gql = '''
      query Fichas(\$ids: [Int!]!) {
        product(where: {id: {_in: \$ids}}) {
          $_camposJogo
          product_price { min_price min_price_new available stores_count }
        }
      }
    ''';

    final dados = await _query(gql, {'ids': ids});
    final lista = (dados['product'] as List?) ?? const [];
    return lista.whereType<Map<String, dynamic>>().map(_parse).toList();
  }

  CatalogGameDetails _parse(Map<String, dynamic> m) {
    final preco = m['product_price'];
    final expansoes = (m['expansions'] as List?) ?? const [];

    return CatalogGameDetails(
      source: CatalogSource.comparajogos,
      id: m['id'] as int,
      bggId: m['bgg_id'] as int?,
      name: (m['name'] as String?) ?? 'Sem nome',
      year: m['year'] as int?,
      minPlayers: m['min_players'] as int?,
      maxPlayers: m['max_players'] as int?,
      bestPlayers: _melhorNumeroDeJogadores(m['best_players']),
      minPlaytime: (m['min_playtime'] as int?) ?? (m['playing_time'] as int?),
      maxPlaytime: (m['max_playtime'] as int?) ?? (m['playing_time'] as int?),
      weight: _double(m['bgg_weight']),
      imageUrl: m['image_url'] as String?,
      thumbUrl: m['thumbnail_url'] as String?,
      isExpansion: m['type'] == 'expansion',
      expansions: expansoes
          .whereType<Map<String, dynamic>>()
          .map((e) => e['expansion'])
          .whereType<Map<String, dynamic>>()
          .map((e) => CatalogExpansionRef(
                id: e['id'] as int,
                name: (e['name'] as String?) ?? 'Sem nome',
                year: e['year'] as int?,
                thumbUrl: e['thumbnail_url'] as String?,
              ))
          .toList()
        ..sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      referencePrice: _precoDeReferencia(preco),
      priceNote: _notaDePreco(preco),
      tags: [
        ..._tags(m['domains'], 'domain', TagKind.estilo),
        ..._tags(m['categories'], 'category', TagKind.tema),
        ..._tags(m['mechanics'], 'mechanic', TagKind.mecanica),
      ],
    );
  }

  /// Desembrulha `[{category: {name: "Aventura"}}, ...]`.
  List<CatalogTag> _tags(Object? bruto, String chave, TagKind tipo) {
    if (bruto is! List) return const [];
    return bruto
        .whereType<Map<String, dynamic>>()
        .map((e) => e[chave])
        .whereType<Map<String, dynamic>>()
        .map((e) => (e['name'] as String?)?.trim())
        .where((n) => n != null && n.isNotEmpty)
        .map((n) => CatalogTag(name: n!, kind: tipo))
        .toSet() // o catálogo às vezes repete
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// `best_players` vem como lista de strings: `["1","2"]`. O app guarda um
  /// número só, então fica o menor — que é o mais restritivo e o mais útil
  /// como sugestão ao registrar partida.
  int? _melhorNumeroDeJogadores(Object? bruto) {
    if (bruto is! List || bruto.isEmpty) return null;
    final numeros = bruto
        .map((e) => int.tryParse(e.toString().replaceAll(RegExp(r'[^0-9]'), '')))
        .whereType<int>()
        .where((n) => n > 0)
        .toList();
    if (numeros.isEmpty) return null;
    numeros.sort();
    return numeros.first;
  }

  double? _precoDeReferencia(Object? preco) {
    if (preco is! Map) return null;
    // Só preço de item novo: usado varia demais para servir de sugestão.
    final v = _double(preco['min_price_new']) ?? _double(preco['min_price']);
    return (v == null || v <= 0) ? null : v;
  }

  String? _notaDePreco(Object? preco) {
    if (preco is! Map) return null;
    if (_precoDeReferencia(preco) == null) return null;

    final lojas = preco['stores_count'];
    final disponivel = preco['available'] == true;

    if (!disponivel) return 'último preço visto — fora de estoque hoje';
    if (lojas is int && lojas > 0) {
      return 'menor preço hoje em $lojas ${lojas == 1 ? 'loja' : 'lojas'}';
    }
    return 'menor preço encontrado hoje';
  }

  double? _double(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// Uma lista pública de um usuário do Comparajogos.
  ///
  /// **Não há login.** A API expõe só três mutations, nenhuma de autenticação,
  /// e `list_item_mine` volta vazio sem credencial. O que dá para fazer é ler
  /// as listas marcadas como públicas, pelo nome de usuário — o que também
  /// evita o app ter de guardar senha de alguém.
  Future<List<CatalogList>> publicLists(String username) async {
    final nome = username.trim();
    if (nome.isEmpty) return const [];

    // Só os metadados aqui. Os itens vêm depois, paginados — ver `_itensDaLista`.
    const gql = r'''
      query Listas($username: String!) {
        lists(
          where: {
            user: {username: {_eq: $username}},
            visibility: {_eq: "PUBLIC"}
          }
        ) {
          id
          name
          type
          items_aggregate { aggregate { count } }
        }
      }
    ''';

    final dados = await _query(gql, {'username': nome});
    final listas = (dados['lists'] as List?) ?? const [];

    final out = <CatalogList>[];
    for (final l in listas.whereType<Map<String, dynamic>>()) {
      final id = '${l['id']}';
      final total = ((l['items_aggregate'] as Map?)?['aggregate']
              as Map?)?['count'] as int? ??
          0;

      out.add(CatalogList(
        id: id,
        name: (l['name'] as String?) ?? 'Lista',
        kind: CatalogListKind.fromApi(l['type'] as String?),
        games: await _itensDaLista(id, total),
      ));
    }
    return out;
  }

  /// Quantas linhas a API entrega por consulta, **independente do `limit`**.
  ///
  /// O papel anônimo do Hasura deles tem teto fixo em 15: pedir 100 devolve
  /// 15 e não avisa. Uma lista de 40 jogos viria pela metade, em silêncio.
  static const _tetoPorPagina = 15;

  /// Todos os itens de uma lista, percorrendo as páginas.
  ///
  /// [total] vem do `items_aggregate` e serve de guarda: sem ele, o laço
  /// dependeria só de "a página veio menor que o teto", que é frágil.
  Future<List<CatalogGameDetails>> _itensDaLista(String listId, int total) async {
    const gql = r'''
      query Itens($id: String!, $limit: Int!, $offset: Int!) {
        list_item(
          where: {list_id: {_eq: $id}},
          order_by: {position: asc},
          limit: $limit,
          offset: $offset
        ) {
          product {
            id
            name
            year
            image_url
            thumbnail_url
            min_players
            max_players
            best_players
            min_playtime
            max_playtime
            playing_time
            bgg_id
            bgg_weight
            type
            domains { domain { name } }
            categories { category { name } }
            mechanics { mechanic { name } }
            product_price { min_price min_price_new available stores_count }
          }
        }
      }
    ''';

    final jogos = <CatalogGameDetails>[];

    for (var offset = 0; offset < total; offset += _tetoPorPagina) {
      final dados = await _query(gql, {
        'id': listId,
        'limit': _tetoPorPagina,
        'offset': offset,
      });

      final pagina = (dados['list_item'] as List?) ?? const [];
      if (pagina.isEmpty) break;

      jogos.addAll(
        pagina
            .whereType<Map<String, dynamic>>()
            .map((i) => i['product'])
            .whereType<Map<String, dynamic>>()
            .map(_parse),
      );
    }

    return jogos;
  }

  /// Só os preços, para atualizar a lista de desejos sem baixar tudo de novo.
  Future<Map<int, double?>> precos(List<int> ids) async {
    if (ids.isEmpty) return const {};

    const gql = r'''
      query Precos($ids: [Int!]!) {
        product(where: {id: {_in: $ids}}) {
          id
          product_price { min_price min_price_new }
        }
      }
    ''';

    final dados = await _query(gql, {'ids': ids});
    final lista = (dados['product'] as List?) ?? const [];

    return {
      for (final m in lista.whereType<Map<String, dynamic>>())
        m['id'] as int: _precoDeReferencia(m['product_price']),
    };
  }

  @override
  void dispose() => _client.close();
}
