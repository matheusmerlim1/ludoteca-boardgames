/// Catálogo de jogos: a interface que as telas enxergam.
///
/// Existem duas fontes com características bem diferentes, e a UI não deveria
/// precisar saber de qual delas o dado veio:
///
/// - **Comparajogos** — funciona sem cadastro, nomes em português e preços em
///   reais. É a fonte padrão.
/// - **BoardGameGeek** — exige token aprovado por eles, nomes em inglês, base
///   maior. Fica disponível quando o usuário configura o token.
///
/// Os tipos aqui são de propósito neutros: nada de `BggIsso`, `CjAquilo` na
/// assinatura, senão trocar de fonte vira reescrita de tela.
library;

enum CatalogSource {
  comparajogos('Comparajogos'),
  bgg('BoardGameGeek');

  const CatalogSource(this.label);
  final String label;
}

/// Tipo de etiqueta. As duas respondem "o que a gente joga hoje?", por ângulos
/// diferentes — uma pelo assunto, a outra pelo jeito de jogar.
enum TagKind {
  /// Festivo, Estratégico, Temático, Familiar... a família do jogo.
  /// É o "party / euro / ameritrash" do jargão, na taxonomia do catálogo.
  estilo('Estilo', 'estilo'),

  /// Do que o jogo trata: Aventura, Econômico, Animais, Dedução.
  tema('Tema', 'tema'),

  /// Como se joga: Cooperativo, Construção de Baralho, Gestão de Mão.
  mecanica('Mecânica', 'mecanica');

  const TagKind(this.label, this.dbValue);

  final String label;
  final String dbValue;

  static TagKind fromDb(String? v) => switch (v) {
        'estilo' => TagKind.estilo,
        'mecanica' => TagKind.mecanica,
        _ => TagKind.tema,
      };
}

/// Um tema ("Aventura") ou uma mecânica ("Cooperativo").
class CatalogTag {
  const CatalogTag({required this.name, required this.kind});

  final String name;
  final TagKind kind;

  @override
  bool operator ==(Object other) =>
      other is CatalogTag && other.name == name && other.kind == kind;

  @override
  int get hashCode => Object.hash(name, kind);
}

/// Resultado enxuto da busca: o suficiente para montar a lista.
class CatalogSearchResult {
  const CatalogSearchResult({
    required this.source,
    required this.id,
    required this.name,
    this.year,
    this.isExpansion = false,
    this.thumbUrl,
  });

  final CatalogSource source;

  /// Id **dentro da fonte**. Não é comparável entre fontes.
  final int id;

  final String name;
  final int? year;
  final bool isExpansion;
  final String? thumbUrl;

  CatalogSearchResult withThumb(String? url) => CatalogSearchResult(
        source: source,
        id: id,
        name: name,
        year: year,
        isExpansion: isExpansion,
        thumbUrl: url,
      );
}

/// Uma expansão associada a um jogo. Só id e nome — o resto vem depois, e só
/// das que o usuário marcar.
class CatalogExpansionRef {
  const CatalogExpansionRef({
    required this.id,
    required this.name,
    this.thumbUrl,
    this.year,
  });

  final int id;
  final String name;
  final String? thumbUrl;
  final int? year;
}

/// Ficha completa de um jogo.
class CatalogGameDetails {
  const CatalogGameDetails({
    required this.source,
    required this.id,
    this.bggId,
    required this.name,
    this.year,
    this.minPlayers,
    this.maxPlayers,
    this.bestPlayers,
    this.minPlaytime,
    this.maxPlaytime,
    this.weight,
    this.imageUrl,
    this.thumbUrl,
    this.isExpansion = false,
    this.description,
    this.expansions = const [],
    this.referencePrice,
    this.priceNote,
    this.tags = const [],
  });

  final CatalogSource source;
  final int id;

  /// Id no BGG quando conhecido. O Comparajogos devolve isto, então um jogo
  /// cadastrado por ele já nasce cruzável com o BGG.
  final int? bggId;

  final String name;
  final int? year;
  final int? minPlayers;
  final int? maxPlayers;
  final int? bestPlayers;
  final int? minPlaytime;
  final int? maxPlaytime;
  final double? weight;
  final String? imageUrl;
  final String? thumbUrl;
  final bool isExpansion;
  final String? description;

  /// O que a fonte conhece de expansões. É a lista do que **existe**, não do
  /// que o usuário tem.
  final List<CatalogExpansionRef> expansions;

  /// Menor preço encontrado hoje, em reais, quando a fonte tem essa informação.
  ///
  /// Serve como **ponto de partida** para o campo de preço, nunca como
  /// verdade: o que interessa no app é quanto *você pagou*, e um jogo comprado
  /// há três anos não custou o preço de hoje. Por isso o campo continua
  /// editável e a UI diz de onde o número veio.
  final double? referencePrice;

  /// Explica a procedência do preço, para a UI mostrar junto.
  final String? priceNote;

  /// Temas e mecânicas do jogo.
  final List<CatalogTag> tags;
}

/// Os tipos de lista que o Comparajogos tem.
enum CatalogListKind {
  colecao('Coleção', 'OWN'),
  desejos('Desejos', 'WISH'),
  alertaDePreco('Alerta de preço', 'PRICE_ALERT'),
  troca('Troca', 'TRADE'),
  outra('Outra', null);

  const CatalogListKind(this.label, this.apiValue);

  final String label;
  final String? apiValue;

  /// As duas que alimentam a lista de desejos do app.
  bool get eDesejo =>
      this == CatalogListKind.desejos || this == CatalogListKind.alertaDePreco;

  static CatalogListKind fromApi(String? v) => switch (v) {
        'OWN' => CatalogListKind.colecao,
        'WISH' => CatalogListKind.desejos,
        'PRICE_ALERT' => CatalogListKind.alertaDePreco,
        'TRADE' => CatalogListKind.troca,
        _ => CatalogListKind.outra,
      };
}

/// Uma lista pública de um usuário do catálogo.
class CatalogList {
  const CatalogList({
    required this.id,
    required this.name,
    required this.kind,
    required this.games,
  });

  final String id;
  final String name;
  final CatalogListKind kind;
  final List<CatalogGameDetails> games;
}

class CatalogException implements Exception {
  CatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A fonte recusou por falta de credencial.
///
/// Tipo próprio porque a UI trata diferente: não adianta oferecer "tentar de
/// novo", o caminho é configurar o token.
class CatalogAuthException extends CatalogException {
  CatalogAuthException(super.message, {required this.temToken});

  /// Se havia token configurado. Separa "falta cadastrar" de "o token está
  /// errado ou expirou".
  final bool temToken;
}

/// Uma fonte de dados de jogos.
abstract class GameCatalog {
  CatalogSource get source;

  /// Busca por nome. Devolve vazio para termos curtos demais, sem ir à rede.
  Future<List<CatalogSearchResult>> search(String query, {bool comCapas = true});

  /// Ficha completa de um item.
  Future<CatalogGameDetails> details(int id);

  /// Várias fichas numa requisição só. Usado ao adicionar expansões marcadas.
  Future<List<CatalogGameDetails>> detailsBatch(List<int> ids);

  void dispose();
}
