import '../data/game_repository.dart';
import '../models/game.dart';
import '../utils/format.dart';
import 'comparajogos_service.dart';
import 'game_catalog.dart';

class WishlistSyncResult {
  const WishlistSyncResult({
    required this.adicionados,
    required this.atualizados,
    required this.listasLidas,
    required this.nomesDasListas,
  });

  final int adicionados;
  final int atualizados;
  final int listasLidas;
  final List<String> nomesDasListas;

  bool get vazio => listasLidas == 0;
}

class PriceRefreshResult {
  const PriceRefreshResult({
    required this.consultados,
    required this.baixaram,
    required this.novosAlertas,
  });

  final int consultados;
  final int baixaram;

  /// Jogos que **agora** chegaram no preço-alvo e antes não estavam.
  final List<Game> novosAlertas;
}

/// Traz a lista de desejos do Comparajogos e mantém os preços atualizados.
///
/// **Não existe login.** A API deles expõe só três mutations, nenhuma de
/// autenticação, e `list_item_mine` volta vazio sem credencial. O que dá é ler
/// listas marcadas como **públicas**, pelo nome de usuário — o que tem a
/// vantagem de o app nunca precisar guardar senha de ninguém.
///
/// A sincronia é de mão única: o que você marca lá aparece aqui, o que você faz
/// aqui não volta para lá.
class WishlistService {
  WishlistService({
    required this.repository,
    ComparajogosService? catalogo,
  }) : _catalogo = catalogo ?? ComparajogosService();

  final GameRepository repository;
  final ComparajogosService _catalogo;

  /// Puxa as listas públicas de [username] e reflete os desejos no app.
  ///
  /// Só adiciona e atualiza; **nunca apaga**. Se você tirar um jogo da lista
  /// lá, ele continua aqui — apagar automaticamente poderia levar junto um
  /// preço-alvo que você ajustou à mão, e o estrago seria silencioso.
  Future<WishlistSyncResult> sincronizar(String username) async {
    final listas = await _catalogo.publicLists(username);
    final desejos = listas.where((l) => l.kind.eDesejo).toList();

    if (listas.isEmpty) {
      return const WishlistSyncResult(
        adicionados: 0,
        atualizados: 0,
        listasLidas: 0,
        nomesDasListas: [],
      );
    }

    // O mesmo jogo pode estar em "Desejos" e em "Alerta de preço".
    final porId = <int, CatalogGameDetails>{};
    for (final l in desejos) {
      for (final g in l.games) {
        porId[g.id] = g;
      }
    }

    final existentes = await repository.allGames();
    final porNome = {
      for (final g in existentes) normalizaNome(g.name): g,
    };

    var adicionados = 0;
    var atualizados = 0;
    final agora = soData(DateTime.now());

    for (final ficha in porId.values) {
      final jaTem = porNome[normalizaNome(ficha.name)];

      if (jaTem == null) {
        final novoId = await repository.insertGame(Game(
          bggId: ficha.bggId,
          name: ficha.name,
          year: ficha.year,
          minPlayers: ficha.minPlayers,
          maxPlayers: ficha.maxPlayers,
          bestPlayers: ficha.bestPlayers,
          minPlaytime: ficha.minPlaytime,
          maxPlaytime: ficha.maxPlaytime,
          weight: ficha.weight,
          imageUrl: ficha.imageUrl,
          thumbUrl: ficha.thumbUrl,
          ownership: Ownership.desejada,
          lastPrice: ficha.referencePrice,
          lastPriceAt: ficha.referencePrice == null ? null : agora,
        ));
        if (ficha.tags.isNotEmpty) {
          await repository.setGameTags(novoId, ficha.tags);
        }
        adicionados++;
        continue;
      }

      // Já é seu: a lista de lá não manda no que está na sua estante.
      // Rebaixar um jogo que você comprou para "desejado" seria apagar
      // informação que só o app tem.
      if (jaTem.isMine) continue;

      await repository.updateGame(jaTem.copyWith(
        ownership: Ownership.desejada,
        lastPrice: ficha.referencePrice,
        lastPriceAt: ficha.referencePrice == null ? null : agora,
      ));
      atualizados++;
    }

    return WishlistSyncResult(
      adicionados: adicionados,
      atualizados: atualizados,
      listasLidas: desejos.length,
      nomesDasListas: desejos.map((l) => l.name).toList(),
    );
  }

  /// Reconsulta o preço de tudo que está na lista de desejos.
  ///
  /// Devolve quais **passaram** a estar no alvo agora — comparar com o estado
  /// anterior é o que evita avisar de novo, todo dia, sobre o mesmo jogo.
  Future<PriceRefreshResult> atualizarPrecos() async {
    final desejados =
        (await repository.allGames()).where((g) => g.isWishlist).toList();

    if (desejados.isEmpty) {
      return const PriceRefreshResult(
        consultados: 0,
        baixaram: 0,
        novosAlertas: [],
      );
    }

    // O id do catálogo não é guardado; o casamento é pelo nome, como no resto
    // do app.
    final novos = <Game>[];
    var baixaram = 0;
    var consultados = 0;

    for (final g in desejados) {
      final achados = await _catalogo.search(g.name, comCapas: false);
      if (achados.isEmpty) continue;

      final ficha = await _catalogo.details(achados.first.id);
      consultados++;

      final antes = g.priceReached;
      final atualizado = g.copyWith(
        lastPrice: ficha.referencePrice,
        lastPriceAt: soData(DateTime.now()),
      );
      await repository.updateGame(atualizado);

      if (ficha.referencePrice != null &&
          g.lastPrice != null &&
          ficha.referencePrice! < g.lastPrice!) {
        baixaram++;
      }

      // Só o que virou alerta agora. Sem essa comparação, o mesmo jogo
      // avisaria todo dia enquanto o preço continuasse bom.
      if (!antes && atualizado.priceReached) novos.add(atualizado);

      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    return PriceRefreshResult(
      consultados: consultados,
      baixaram: baixaram,
      novosAlertas: novos,
    );
  }

  void dispose() => _catalogo.dispose();
}
