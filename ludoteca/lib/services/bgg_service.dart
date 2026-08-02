import 'dart:async';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'game_catalog.dart';

/// Cliente da XML API2 do BoardGameGeek.
///
/// Fonte **opcional**: desde o fim de outubro de 2025 a API exige cadastro de
/// aplicativo aprovado pelo BGG e um token. Sem token, todo endpoint responde
/// 401 — enquanto a home do site continua abrindo, o que faz o sintoma parecer
/// problema de rede quando não é. A fonte padrão do app é o Comparajogos, que
/// funciona sem credencial.
///
/// Três manias da API tratadas aqui, que derrubam implementações ingênuas:
///
/// 1. **202 Accepted** com corpo vazio quando o pedido entra na fila. Não é
///    erro — é "pergunte de novo em instantes".
/// 2. **429** se você acelerar. Os dois são reconsultados com espera
///    progressiva.
/// 3. **401 e 403 falham na hora**, sem repetir: falta de credencial não
///    melhora tentando de novo.
class BggService implements GameCatalog {
  BggService({http.Client? client, this.maxAttempts = 5, String? token})
      : _client = client ?? http.Client(),
        _token = token;

  final http.Client _client;
  final int maxAttempts;

  /// Token de aplicativo do BGG. Sem ele a API responde 401 em tudo.
  String? _token;

  set token(String? v) => _token = (v == null || v.trim().isEmpty) ? null : v.trim();
  bool get hasToken => _token != null;

  @override
  CatalogSource get source => CatalogSource.bgg;

  static const _base = 'https://boardgamegeek.com/xmlapi2';

  Map<String, String> get _headers => {
        'Accept': 'application/xml',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Espera entre tentativas: 1s, 2s, 3s, 4s... Suficiente para a fila do BGG
  /// sem deixar o usuário olhando um spinner eterno.
  Duration _backoff(int attempt) => Duration(milliseconds: 900 * attempt);

  Future<XmlDocument> _get(Uri uri) async {
    Object? ultimoErro;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) await Future<void>.delayed(_backoff(attempt - 1));

      try {
        final res = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 20));

        switch (res.statusCode) {
          case 200:
            if (res.bodyBytes.isEmpty) {
              ultimoErro = CatalogException('O BGG respondeu vazio.');
              continue;
            }
            return XmlDocument.parse(res.body);

          // Pedido enfileirado, ou limite de taxa: as duas pedem reconsulta.
          case 202:
          case 429:
          case 503:
            ultimoErro = CatalogException(
              'O BGG está processando o pedido (${res.statusCode}).',
            );
            continue;

          // Falta de credencial NÃO melhora tentando de novo. Insistir aqui só
          // deixaria o usuário olhando um spinner por 15 segundos antes de um
          // erro genérico.
          case 401:
          case 403:
            throw CatalogAuthException(
              _token == null
                  ? 'O BoardGameGeek passou a exigir cadastro para usar a API '
                      'dele. Configure o token em Ajustes para a busca '
                      'funcionar.'
                  : 'O BGG recusou o token configurado (${res.statusCode}). '
                      'Confira se ele foi copiado inteiro e se ainda está '
                      'válido.',
              temToken: _token != null,
            );

          case 404:
            throw CatalogException('Jogo não encontrado no BGG.');

          default:
            ultimoErro =
                CatalogException('O BGG respondeu ${res.statusCode}.');
            continue;
        }
      } on TimeoutException {
        ultimoErro = CatalogException('O BGG demorou demais para responder.');
      } on XmlParserException {
        ultimoErro = CatalogException('Resposta do BGG veio malformada.');
      } on CatalogException {
        rethrow;
      } catch (e) {
        ultimoErro = e;
      }
    }

    throw CatalogException(
      'Não consegui falar com o BGG. Verifique a conexão e tente de novo.\n'
      '($ultimoErro)',
    );
  }

  /// Busca por nome. Retorna jogos e expansões, com os títulos mais próximos
  /// da consulta primeiro.
  @override
  Future<List<CatalogSearchResult>> search(String query,
      {bool comCapas = true}) async {
    final termo = query.trim();
    if (termo.length < 2) return const [];

    final uri = Uri.parse('$_base/search').replace(queryParameters: {
      'query': termo,
      'type': 'boardgame,boardgameexpansion',
    });

    final doc = await _get(uri);
    final resultados = <CatalogSearchResult>[];
    final vistos = <int>{};

    for (final item in doc.findAllElements('item')) {
      final id = int.tryParse(item.getAttribute('id') ?? '');
      if (id == null || !vistos.add(id)) continue;

      final nome = item
          .findElements('name')
          .map((e) => e.getAttribute('value'))
          .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
      if (nome == null) continue;

      resultados.add(CatalogSearchResult(
        source: CatalogSource.bgg,
        id: id,
        name: nome,
        year: int.tryParse(
          item.findElements('yearpublished').firstOrNull?.getAttribute('value') ??
              '',
        ),
        isExpansion: item.getAttribute('type') == 'boardgameexpansion',
      ));
    }

    _ordenaPorRelevancia(resultados, termo);

    final recortado = resultados.take(25).toList();
    if (!comCapas || recortado.isEmpty) return recortado;

    // Uma única chamada extra traz as capas de todos os resultados.
    try {
      final capas = await _thumbnails(recortado.map((r) => r.id).toList());
      return recortado.map((r) => r.withThumb(capas[r.id])).toList();
    } on CatalogException {
      // Sem capa a lista ainda serve — não vale derrubar a busca por isso.
      return recortado;
    }
  }

  /// A busca do BGG devolve numa ordem pouco útil: um "Catan" digitado traz
  /// dezenas de derivados antes do jogo-base. Aqui o casamento exato sobe,
  /// depois o prefixo, e o resto vai por ano de publicação.
  void _ordenaPorRelevancia(List<CatalogSearchResult> lista, String termo) {
    final alvo = termo.toLowerCase();

    int nota(CatalogSearchResult r) {
      final n = r.name.toLowerCase();
      if (n == alvo) return 0;
      if (n.startsWith(alvo)) return 1;
      if (n.contains(alvo)) return 2;
      return 3;
    }

    lista.sort((a, b) {
      final byNota = nota(a).compareTo(nota(b));
      if (byNota != 0) return byNota;

      // Jogo-base antes de expansão quando o resto empata.
      if (a.isExpansion != b.isExpansion) return a.isExpansion ? 1 : -1;

      final ay = a.year ?? 9999;
      final by = b.year ?? 9999;
      return ay.compareTo(by);
    });
  }

  Future<Map<int, String?>> _thumbnails(List<int> ids) async {
    final docs = await _fetchThings(ids);
    final out = <int, String?>{};
    for (final item in docs) {
      final id = int.tryParse(item.getAttribute('id') ?? '');
      if (id == null) continue;
      out[id] = _texto(item, 'thumbnail');
    }
    return out;
  }

  /// Ficha completa de um jogo.
  @override
  Future<CatalogGameDetails> details(int bggId) async {
    final items = await _fetchThings([bggId]);
    if (items.isEmpty) {
      throw CatalogException('O BGG não retornou dados para o id $bggId.');
    }
    return _parseDetails(items.first);
  }

  Future<List<XmlElement>> _fetchThings(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final uri = Uri.parse('$_base/thing').replace(queryParameters: {
      'id': ids.join(','),
      'stats': '1',
    });
    final doc = await _get(uri);
    return doc.findAllElements('item').toList();
  }

  CatalogGameDetails _parseDetails(XmlElement item) {
    final id = int.tryParse(item.getAttribute('id') ?? '') ?? 0;

    // O BGG lista vários nomes; o `type="primary"` é o oficial.
    final nome = item
            .findElements('name')
            .where((e) => e.getAttribute('type') == 'primary')
            .firstOrNull
            ?.getAttribute('value') ??
        item.findElements('name').firstOrNull?.getAttribute('value') ??
        'Sem nome';

    final minP = _numero(item, 'minplayers');
    final maxP = _numero(item, 'maxplayers');

    final duracaoUnica = _numero(item, 'playingtime');
    final minT = _numero(item, 'minplaytime') ?? duracaoUnica;
    final maxT = _numero(item, 'maxplaytime') ?? duracaoUnica;

    return CatalogGameDetails(
      source: CatalogSource.bgg,
      // No BGG o id da fonte e o id do BGG são o mesmo número.
      id: id,
      bggId: id,
      name: nome,
      year: _numero(item, 'yearpublished'),
      minPlayers: minP,
      maxPlayers: maxP,
      bestPlayers: _melhorNumeroDeJogadores(item),
      minPlaytime: minT,
      maxPlaytime: maxT,
      weight: _peso(item),
      imageUrl: _texto(item, 'image'),
      thumbUrl: _texto(item, 'thumbnail'),
      isExpansion: item.getAttribute('type') == 'boardgameexpansion',
      description: _limpaDescricao(_texto(item, 'description')),
      expansions: _expansoes(item),
      tags: [
        ..._tags(item, 'boardgamecategory', TagKind.tema),
        ..._tags(item, 'boardgamemechanic', TagKind.mecanica),
      ],
    );
  }

  /// No BGG tudo é `<link>`: categoria, mecânica, designer, expansão. O que
  /// separa é o atributo `type`.
  List<CatalogTag> _tags(XmlElement item, String tipoLink, TagKind tipo) {
    final nomes = <String>{};
    for (final link in item.findElements('link')) {
      if (link.getAttribute('type') != tipoLink) continue;
      final v = link.getAttribute('value')?.trim();
      if (v != null && v.isNotEmpty) nomes.add(v);
    }
    final lista = nomes.map((n) => CatalogTag(name: n, kind: tipo)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return lista;
  }

  /// Lê os `<link type="boardgameexpansion">` do jogo.
  ///
  /// O atributo `inbound="true"` inverte o sentido do vínculo: numa expansão,
  /// o link com inbound aponta para o jogo-base. Filtrar por isso evita que a
  /// ficha de uma expansão liste o jogo-base como se fosse expansão dela.
  List<CatalogExpansionRef> _expansoes(XmlElement item) {
    final out = <CatalogExpansionRef>[];
    final vistos = <int>{};

    for (final link in item.findElements('link')) {
      if (link.getAttribute('type') != 'boardgameexpansion') continue;
      if (link.getAttribute('inbound') == 'true') continue;

      final id = int.tryParse(link.getAttribute('id') ?? '');
      final nome = link.getAttribute('value');
      if (id == null || nome == null || nome.isEmpty) continue;
      if (!vistos.add(id)) continue;

      out.add(CatalogExpansionRef(id: id, name: nome));
    }

    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Fichas de vários jogos numa chamada só. Usado para trazer os dados das
  /// expansões que o usuário marcou sem fazer uma requisição por expansão.
  @override
  Future<List<CatalogGameDetails>> detailsBatch(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final items = await _fetchThings(ids);
    return items.map(_parseDetails).toList();
  }

  /// Lê a enquete `suggested_numplayers` e devolve o nº de jogadores com mais
  /// votos "Best".
  int? _melhorNumeroDeJogadores(XmlElement item) {
    final poll = item
        .findElements('poll')
        .where((e) => e.getAttribute('name') == 'suggested_numplayers')
        .firstOrNull;
    if (poll == null) return null;

    int? melhor;
    var maisVotos = 0;

    for (final results in poll.findElements('results')) {
      // Pode vir como "4" ou "4+".
      final bruto = results.getAttribute('numplayers') ?? '';
      final n = int.tryParse(bruto.replaceAll(RegExp(r'[^0-9]'), ''));
      if (n == null || n == 0) continue;

      final votosBest = results
          .findElements('result')
          .where((r) => r.getAttribute('value') == 'Best')
          .map((r) => int.tryParse(r.getAttribute('numvotes') ?? '') ?? 0)
          .fold(0, (a, b) => a + b);

      if (votosBest > maisVotos) {
        maisVotos = votosBest;
        melhor = n;
      }
    }

    return maisVotos > 0 ? melhor : null;
  }

  double? _peso(XmlElement item) {
    final v = item
        .findAllElements('averageweight')
        .firstOrNull
        ?.getAttribute('value');
    final d = double.tryParse(v ?? '');
    return (d == null || d == 0) ? null : d;
  }

  int? _numero(XmlElement item, String tag) {
    final v = item.findElements(tag).firstOrNull?.getAttribute('value');
    final n = int.tryParse(v ?? '');
    return (n == null || n == 0) ? null : n;
  }

  String? _texto(XmlElement item, String tag) {
    final e = item.findElements(tag).firstOrNull;
    final t = e?.innerText.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// A descrição vem com entidades HTML e `<br/>` literais.
  String? _limpaDescricao(String? bruto) {
    if (bruto == null) return null;
    final texto = bruto
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return texto.isEmpty ? null : texto;
  }

  @override
  void dispose() => _client.close();
}
