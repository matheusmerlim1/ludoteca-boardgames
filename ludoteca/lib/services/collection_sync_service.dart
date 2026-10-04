import '../data/game_repository.dart';
import '../models/game.dart';
import '../utils/format.dart';
import 'comparajogos_service.dart';
import 'game_catalog.dart';

/// O resultado da comparação entre a sua coleção lá e a daqui.
class CollectionDiff {
  const CollectionDiff({
    required this.faltando,
    required this.jaTinha,
    required this.nomesDasListas,
  });

  /// Jogos que estão no Comparajogos e não estão no app.
  final List<CatalogGameDetails> faltando;

  /// Quantos da lista de lá o app já conhecia. Serve para o usuário entender
  /// um "0 para adicionar" — sem esse número, a caixa vazia parece falha.
  final int jaTinha;

  final List<String> nomesDasListas;

  bool get semListas => nomesDasListas.isEmpty;
  int get total => faltando.length + jaTinha;
}

/// Compara a coleção do app com a coleção pública do Comparajogos.
///
/// A direção é uma só: de lá para cá, e **só somando**. O app sabe coisas que o
/// catálogo não sabe — quanto você pagou, as partidas, os sleeves — e uma
/// sincronia que apagasse ou sobrescrevesse levaria isso junto sem aviso. Por
/// isso a comparação nunca remove nada, e o que ela encontra é oferecido numa
/// caixa em vez de entrar sozinho.
class CollectionSyncService {
  CollectionSyncService({
    required this.repository,
    ComparajogosService? catalogo,
  }) : _catalogo = catalogo ?? ComparajogosService();

  final GameRepository repository;
  final ComparajogosService _catalogo;

  /// Lê as listas públicas de [username] e separa o que falta aqui.
  Future<CollectionDiff> comparar(String username) async {
    final listas = await _catalogo.publicLists(username);
    final colecoes =
        listas.where((l) => l.kind == CatalogListKind.colecao).toList();

    if (colecoes.isEmpty) {
      return const CollectionDiff(
        faltando: [],
        jaTinha: 0,
        nomesDasListas: [],
      );
    }

    // O mesmo jogo pode aparecer em mais de uma lista de coleção.
    final porId = <int, CatalogGameDetails>{};
    for (final l in colecoes) {
      for (final g in l.games) {
        porId[g.id] = g;
      }
    }

    // O casamento é por **nome normalizado**, não por id: o id é da fonte, e
    // um jogo que você digitou à mão aqui não tem id de fonte nenhuma. Sem
    // isso, a caixa ofereceria de volta jogos que você já tem.
    final existentes = await repository.allGames();
    final conhecidos = <String>{
      for (final g in existentes) ...[
        normalizaNome(g.name),
        if (g.namePt != null) normalizaNome(g.namePt!),
      ],
    }..removeWhere((n) => n.isEmpty);
    final bggConhecidos = {
      for (final g in existentes)
        if (g.bggId != null) g.bggId!,
    };

    final faltando = <CatalogGameDetails>[];
    var jaTinha = 0;

    for (final ficha in porId.values) {
      final tem = conhecidos.contains(normalizaNome(ficha.name)) ||
          (ficha.bggId != null && bggConhecidos.contains(ficha.bggId));
      if (tem) {
        jaTinha++;
      } else {
        faltando.add(ficha);
      }
    }

    faltando.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return CollectionDiff(
      faltando: faltando,
      jaTinha: jaTinha,
      nomesDasListas: colecoes.map((l) => l.name).toList(),
    );
  }

  /// Cadastra os escolhidos como jogos seus.
  ///
  /// [usarPrecoDeReferencia] decide o que vai no campo de preço. O preço do
  /// catálogo é o de **hoje**, não o que você pagou — num jogo comprado há três
  /// anos ele infla o investimento. Por isso a escolha é sua, e o preço de
  /// referência fica gravado em `lastPrice` de qualquer jeito: você consegue
  /// conferir e corrigir jogo a jogo depois.
  Future<int> importar(
    List<CatalogGameDetails> escolhidos, {
    bool usarPrecoDeReferencia = true,
  }) async {
    final hoje = soData(DateTime.now());
    var inseridos = 0;

    for (final f in escolhidos) {
      final id = await repository.insertGame(Game(
        // `f.bggId`, não `f.id`: o id do Comparajogos é dele, e gravá-lo no
        // campo do BGG faria o app achar que conhece um jogo do BGG que não
        // existe.
        bggId: f.bggId,
        name: f.name,
        year: f.year,
        minPlayers: f.minPlayers,
        maxPlayers: f.maxPlayers,
        bestPlayers: f.bestPlayers,
        minPlaytime: f.minPlaytime,
        maxPlaytime: f.maxPlaytime,
        weight: f.weight,
        imageUrl: f.imageUrl,
        thumbUrl: f.thumbUrl,
        price: usarPrecoDeReferencia ? (f.referencePrice ?? 0) : 0,
        lastPrice: f.referencePrice,
        lastPriceAt: f.referencePrice == null ? null : hoje,
        // Sem data de compra: o app não sabe quando você comprou, e chutar
        // "hoje" faria o custo por mês de uma coleção inteira nascer errado.
      ));
      if (f.tags.isNotEmpty) await repository.setGameTags(id, f.tags);
      inseridos++;
    }

    return inseridos;
  }

  void dispose() => _catalogo.dispose();
}
