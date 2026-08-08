import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../data/game_repository.dart';
import '../models/game.dart';
import '../models/play.dart';
import '../models/play_score.dart';
import '../services/game_catalog.dart';
import '../utils/format.dart';

/// Seções do menu de ordenação.
///
/// Com treze opções, uma lista corrida vira parede de texto. Agrupar por
/// pergunta ("o que jogar hoje?", "quanto custou?") deixa a busca visual curta.
enum SortGroup {
  geral(''),
  tempo('Tempo'),
  partidas('Partidas'),
  custo('Custo');

  const SortGroup(this.label);
  final String label;
}

enum SortKey {
  nome('Nome', SortGroup.geral),
  maisPesados('Mais pesados', SortGroup.geral),

  /// Para a pergunta "temos 40 minutos, o que dá para jogar?".
  maisRapidos('Partida mais curta', SortGroup.tempo),
  maisLongos('Partida mais longa', SortGroup.tempo),

  /// Horas acumuladas: o cronometrado mais a média nas partidas sem cronômetro.
  maisHoras('Mais horas na mesa', SortGroup.tempo),
  menosHoras('Menos horas na mesa', SortGroup.tempo),

  maisJogados('Mais jogados', SortGroup.partidas),
  menosJogados('Menos jogados', SortGroup.partidas),
  jogadosRecentemente('Jogados por último', SortGroup.partidas),
  esquecidos('Há mais tempo sem jogar', SortGroup.partidas),

  maisCaros('Mais caros', SortGroup.custo),
  melhorCustoPorPartida('Melhor custo por partida', SortGroup.custo),
  piorCustoPorPartida('Pior custo por partida', SortGroup.custo);

  const SortKey(this.label, this.group);
  final String label;
  final SortGroup group;
}

/// Estado da coleção. Uma única fonte de verdade para todas as telas.
class CollectionStore extends ChangeNotifier {
  CollectionStore({GameRepository? repository})
      : _repo = repository ?? GameRepository();

  final GameRepository _repo;

  GameRepository get repository => _repo;

  List<GameEntry> _entries = const [];
  bool _loading = true;
  Object? _error;

  /// Token da API do BGG. Nulo = não configurado, e nesse caso a busca de
  /// jogos não funciona (o BGG passou a responder 401 sem credencial).
  String? _bggToken;
  String? get bggToken => _bggToken;
  bool get hasBggToken => _bggToken != null && _bggToken!.isNotEmpty;

  /// Etiquetas existentes, com contagem, e quais cada jogo tem.
  List<TagCount> _tags = const [];
  Map<int, Set<int>> _tagsPorJogo = const {};

  List<TagCount> get tags => _tags;

  /// Todas as partidas registradas, para o calendário de frequência.
  List<Play> _todasPartidas = const [];
  List<Play> get todasPartidas => _todasPartidas;

  /// Etiquetas escolhidas no filtro. Vazio = sem filtro de tema.
  Set<int> _tagFilter = const {};
  Set<int> get tagFilter => _tagFilter;

  /// Etiquetas de um jogo, para a ficha e para a lista.
  List<TagCount> tagsOf(int gameId) {
    final ids = _tagsPorJogo[gameId];
    if (ids == null || ids.isEmpty) return const [];
    return _tags.where((t) => ids.contains(t.id)).toList();
  }

  // Filtros
  String _query = '';
  int? _playerCount;
  bool _showExpansions = false;
  bool _showSold = false;

  /// Mostrar também os jogos que você jogou sem ter.
  bool _showPlayedNotOwned = false;

  bool _onlyNeverPlayed = false;
  SortKey _sort = SortKey.nome;

  bool get loading => _loading;
  Object? get error => _error;
  List<GameEntry> get allEntries => _entries;

  String get query => _query;
  int? get playerCount => _playerCount;
  bool get showExpansions => _showExpansions;
  bool get showSold => _showSold;
  bool get onlyNeverPlayed => _onlyNeverPlayed;
  SortKey get sort => _sort;

  bool get hasActiveFilters =>
      _query.isNotEmpty ||
      _playerCount != null ||
      _onlyNeverPlayed ||
      _showExpansions ||
      _showSold ||
      _tagFilter.isNotEmpty;

  /// O filtro em palavras, ou nulo se a lista é a coleção inteira.
  ///
  /// Serve ao texto compartilhado: uma lista filtrada que chega sem dizer o
  /// filtro passa por "esta é a coleção dele" — e o amigo conclui que você só
  /// tem cinco jogos.
  String? get filtroDescrito {
    final partes = <String>[
      if (_query.isNotEmpty) 'busca "$_query"',
      if (_playerCount != null) 'para $_playerCount jogadores',
      for (final t in _tags.where((t) => _tagFilter.contains(t.id))) t.name,
      if (_onlyNeverPlayed) 'nunca jogados',
      if (_showExpansions) 'com agrupados',
      if (_showSold) 'com vendidos',
      if (_showPlayedNotOwned) 'com jogados sem ter',
    ];
    return partes.isEmpty ? null : partes.join(' · ');
  }

  /// Índice do que já está na coleção, para a busca marcar o que você tem.
  ///
  /// Guarda nome normalizado **e** id do BGG, e é recalculado a cada `refresh`
  /// em vez de a cada resultado de busca — a lista de resultados chega inteira
  /// e reconstruir isso por linha seria trabalho repetido.
  Set<String> _nomesConhecidos = const {};
  Set<int> _bggIdsConhecidos = const {};

  void _reindexa() {
    _nomesConhecidos = {
      for (final e in _entries) ...[
        normalizaNome(e.game.name),
        if (e.game.namePt != null) normalizaNome(e.game.namePt!),
      ],
    }..removeWhere((n) => n.isEmpty);

    _bggIdsConhecidos = {
      for (final e in _entries)
        if (e.game.bggId != null) e.game.bggId!,
    };
  }

  /// Se um resultado de busca já está na sua coleção.
  ///
  /// O id da fonte não serve para isso: cada catálogo tem a sua numeração, e
  /// um jogo que você cadastrou à mão não tem id de fonte nenhuma. O nome
  /// normalizado atravessa esses três casos.
  bool alreadyOwned({String? name, int? bggId}) {
    if (bggId != null && _bggIdsConhecidos.contains(bggId)) return true;
    if (name == null) return false;
    final n = normalizaNome(name);
    return n.isNotEmpty && _nomesConhecidos.contains(n);
  }

  /// Só os jogos-base que são **seus** — a base honesta para "quantos jogos eu
  /// tenho". Jogo de outra pessoa e jogo desejado não estão na sua estante.
  List<GameEntry> get ownedBaseGames => _entries
      .where((e) => !e.game.isGrouped && !e.game.sold && e.game.isMine)
      .toList(growable: false);

  /// A lista de desejos, com os que já bateram o preço-alvo primeiro.
  List<GameEntry> get wishlist {
    final lista = _entries.where((e) => e.game.isWishlist).toList()
      ..sort((a, b) {
        // Quem chegou no alvo sobe: é o que exige ação.
        if (a.game.priceReached != b.game.priceReached) {
          return a.game.priceReached ? -1 : 1;
        }
        return a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            );
      });
    return lista;
  }

  /// Quantos jogos desejados chegaram no preço que você queria.
  int get wishlistAlerts =>
      _entries.where((e) => e.game.isWishlist && e.game.priceReached).length;

  /// Jogos que você jogou sem ter.
  List<GameEntry> get playedNotOwned => _entries
      .where((e) => e.game.ownership == Ownership.jogada)
      .toList(growable: false);

  /// Tudo que ainda está na estante, expansões incluídas. É a base dos custos:
  /// cada item conta uma vez só, sem o risco de somar a expansão duas vezes
  /// (nela mesma e dentro do jogo-base).
  List<GameEntry> get ownedEverything =>
      _entries.where((e) => !e.game.sold).toList(growable: false);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _entries = await _repo.loadEntries();
      _tags = await _repo.loadTags();
      _tagsPorJogo = await _repo.loadGameTagIds();
      _todasPartidas = await _repo.allPlays();
      // Uma etiqueta pode ter sumido (último jogo dela removido); manter o
      // filtro apontando para ela esconderia a coleção inteira.
      final vivos = {for (final t in _tags) t.id};
      _tagFilter = _tagFilter.intersection(vivos);
      _reindexa();
      _bggToken = await _repo.getSetting(GameRepository.keyBggToken);
      await _carregarMetas();
      _error = null;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setBggToken(String? token) async {
    await _repo.setSetting(GameRepository.keyBggToken, token);
    _bggToken = (token == null || token.trim().isEmpty) ? null : token.trim();
    notifyListeners();
  }

  // ------------------------------------------------- réguas do "vale a pena?"

  /// Quanto você aceita pagar por partida, por mês de posse e por hora de mesa.
  ///
  /// Nulo = sem régua; os rankings voltam a comparar os jogos só entre si.
  /// Ficam aqui, e não na tela de custos, porque ler o banco no `initState` de
  /// uma tela cria I/O fora do ciclo de carga do app — e, em teste, um future
  /// que nasce na zona de tempo falso nunca completa.
  final Map<String, double?> _metas = {};

  double? get metaPorPartida => _metas[GameRepository.keyMetaPorPartida];
  double? get metaPorMes => _metas[GameRepository.keyMetaPorMes];
  double? get metaPorHora => _metas[GameRepository.keyMetaPorHora];

  static const _chavesDeMeta = [
    GameRepository.keyMetaPorPartida,
    GameRepository.keyMetaPorMes,
    GameRepository.keyMetaPorHora,
  ];

  Future<void> _carregarMetas() async {
    for (final chave in _chavesDeMeta) {
      _metas[chave] = double.tryParse(await _repo.getSetting(chave) ?? '');
    }
  }

  Future<void> setMeta(String chave, double? valor) async {
    await _repo.setSetting(chave, valor?.toString());
    _metas[chave] = valor;
    notifyListeners();
  }

  /// Recarrega sem piscar a tela inteira — o render anterior fica no lugar
  /// até os dados novos chegarem.
  Future<void> refresh() async {
    try {
      _entries = await _repo.loadEntries();
      _tags = await _repo.loadTags();
      _tagsPorJogo = await _repo.loadGameTagIds();
      _todasPartidas = await _repo.allPlays();
      // Uma etiqueta pode ter sumido (último jogo dela removido); manter o
      // filtro apontando para ela esconderia a coleção inteira.
      final vivos = {for (final t in _tags) t.id};
      _tagFilter = _tagFilter.intersection(vivos);
      _reindexa();
      _error = null;
    } catch (e) {
      _error = e;
    }
    notifyListeners();
  }

  // ----------------------------------------------------------------- filtros

  void setQuery(String v) {
    if (v == _query) return;
    _query = v;
    notifyListeners();
  }

  void setPlayerCount(int? v) {
    if (v == _playerCount) return;
    _playerCount = v;
    notifyListeners();
  }

  void setShowExpansions(bool v) {
    if (v == _showExpansions) return;
    _showExpansions = v;
    notifyListeners();
  }

  void setShowSold(bool v) {
    if (v == _showSold) return;
    _showSold = v;
    notifyListeners();
  }

  bool get showPlayedNotOwned => _showPlayedNotOwned;

  void setShowPlayedNotOwned(bool v) {
    if (v == _showPlayedNotOwned) return;
    _showPlayedNotOwned = v;
    notifyListeners();
  }

  void setOnlyNeverPlayed(bool v) {
    if (v == _onlyNeverPlayed) return;
    _onlyNeverPlayed = v;
    notifyListeners();
  }

  void setSort(SortKey v) {
    if (v == _sort) return;
    _sort = v;
    notifyListeners();
  }

  void toggleTag(int tagId) {
    final novo = Set<int>.from(_tagFilter);
    if (!novo.remove(tagId)) novo.add(tagId);
    _tagFilter = novo;
    notifyListeners();
  }

  void setTagFilter(Set<int> ids) {
    _tagFilter = Set.unmodifiable(ids);
    notifyListeners();
  }

  void clearFilters() {
    _query = '';
    _playerCount = null;
    _showExpansions = false;
    _showSold = false;
    _onlyNeverPlayed = false;
    _tagFilter = const {};
    _sort = SortKey.nome;
    notifyListeners();
  }

  /// A lista que a tela de coleção desenha.
  List<GameEntry> get filteredEntries {
    // Busca branda, igual à do catálogo: sem acento, sem pontuação, e cada
    // palavra pode aparecer em qualquer ordem. Digitar "galaxia cacadores"
    // acha "Caçadores da Galáxia".
    final palavras = normalizaNome(_query)
        .split(' ')
        .where((p) => p.isNotEmpty)
        .toList();

    final lista = _entries.where((e) {
      // Desejados têm tela própria; misturá-los na estante faria você contar
      // como seu o que ainda quer comprar.
      if (e.game.isWishlist) return false;

      if (!_showPlayedNotOwned && e.game.ownership == Ownership.jogada) {
        return false;
      }
      if (!_showExpansions && e.game.isGrouped) return false;
      if (!_showSold && e.game.sold) return false;
      if (_onlyNeverPlayed && !e.neverPlayed) return false;

      if (_playerCount != null && !e.game.supportsPlayerCount(_playerCount!)) {
        return false;
      }

      // Várias etiquetas marcadas = **todas** têm de bater, não qualquer uma.
      // Marcar "Cooperativo" e "Fantasia" quer dizer "algo que seja os dois";
      // se fosse "qualquer uma", marcar mais só aumentaria a lista e o filtro
      // andaria para trás.
      if (_tagFilter.isNotEmpty) {
        final doJogo = _tagsPorJogo[e.id];
        if (doJogo == null || !_tagFilter.every(doJogo.contains)) return false;
      }

      if (palavras.isNotEmpty) {
        // Procura nos dois nomes: você pode ter digitado o português e o jogo
        // estar salvo com o nome original, ou o contrário.
        final alvo = normalizaNome('${e.game.displayName} ${e.game.name}');
        if (!palavras.every(alvo.contains)) return false;
      }

      return true;
    }).toList();

    _ordena(lista);
    return lista;
  }

  void _ordena(List<GameEntry> lista) {
    // Comparador de nome, usado como desempate em todas as ordens.
    int porNome(GameEntry a, GameEntry b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());

    /// Datas nulas ("nunca jogado") vão sempre para o fim, independente da
    /// direção — um jogo sem data não é "o mais recente" nem "o mais antigo".
    int porData(DateTime? a, DateTime? b, {required bool recentesPrimeiro}) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return recentesPrimeiro ? b.compareTo(a) : a.compareTo(b);
    }

    /// Números ausentes vão sempre para o fim, nas duas direções: um jogo sem
    /// o dado não é o menor nem o maior, é desconhecido.
    int porNumero(double? a, double? b, {required bool crescente}) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return crescente ? a.compareTo(b) : b.compareTo(a);
    }

    /// Idem para custo por partida: nunca jogado não entra no ranking.
    int porCusto(double? a, double? b, {required bool baratosPrimeiro}) =>
        porNumero(a, b, crescente: baratosPrimeiro);

    switch (_sort) {
      case SortKey.nome:
        lista.sort(porNome);
      case SortKey.maisJogados:
        lista.sort((a, b) {
          final c = b.playCount.compareTo(a.playCount);
          return c != 0 ? c : porNome(a, b);
        });
      case SortKey.menosJogados:
        lista.sort((a, b) {
          final c = a.playCount.compareTo(b.playCount);
          return c != 0 ? c : porNome(a, b);
        });
      case SortKey.jogadosRecentemente:
        lista.sort((a, b) {
          final c = porData(a.lastPlayed, b.lastPlayed, recentesPrimeiro: true);
          return c != 0 ? c : porNome(a, b);
        });
      case SortKey.esquecidos:
        lista.sort((a, b) {
          final c = porData(a.lastPlayed, b.lastPlayed, recentesPrimeiro: false);
          return c != 0 ? c : porNome(a, b);
        });
      case SortKey.maisCaros:
        lista.sort((a, b) {
          final c = b.totalInvested.compareTo(a.totalInvested);
          return c != 0 ? c : porNome(a, b);
        });
      case SortKey.melhorCustoPorPartida:
        lista.sort((a, b) {
          final c = porCusto(a.costPerPlay, b.costPerPlay, baratosPrimeiro: true);
          return c != 0 ? c : porNome(a, b);
        });
      case SortKey.piorCustoPorPartida:
        lista.sort((a, b) {
          final c =
              porCusto(a.costPerPlay, b.costPerPlay, baratosPrimeiro: false);
          return c != 0 ? c : porNome(a, b);
        });
      case SortKey.maisPesados:
        lista.sort((a, b) {
          final c = (b.game.weight ?? 0).compareTo(a.game.weight ?? 0);
          return c != 0 ? c : porNome(a, b);
        });

      // Duração de uma partida, pela média da faixa do catálogo. Jogo sem
      // duração cadastrada vai para o fim nas duas direções: não é "o mais
      // rápido" nem "o mais longo", é desconhecido.
      case SortKey.maisRapidos:
        lista.sort((a, b) {
          final c = porNumero(
            a.game.averagePlaytime?.toDouble(),
            b.game.averagePlaytime?.toDouble(),
            crescente: true,
          );
          return c != 0 ? c : porNome(a, b);
        });
      case SortKey.maisLongos:
        lista.sort((a, b) {
          final c = porNumero(
            a.game.averagePlaytime?.toDouble(),
            b.game.averagePlaytime?.toDouble(),
            crescente: false,
          );
          return c != 0 ? c : porNome(a, b);
        });

      // Horas acumuladas na mesa. Zero é valor legítimo aqui ("nunca jogado"),
      // mas **nulo** não é a mesma coisa: significa que o jogo não tem duração
      // cadastrada e não dá para estimar. Esses vão para o fim.
      case SortKey.maisHoras:
        lista.sort((a, b) {
          final c = porNumero(
            a.totalMinutes?.toDouble(),
            b.totalMinutes?.toDouble(),
            crescente: false,
          );
          return c != 0 ? c : porNome(a, b);
        });
      case SortKey.menosHoras:
        lista.sort((a, b) {
          final c = porNumero(
            a.totalMinutes?.toDouble(),
            b.totalMinutes?.toDouble(),
            crescente: true,
          );
          return c != 0 ? c : porNome(a, b);
        });
    }
  }

  // ---------------------------------------------------------------- mutações

  GameEntry? entryById(int id) =>
      _entries.where((e) => e.game.id == id).firstOrNull;

  /// Expansões cadastradas sob um jogo-base.
  List<GameEntry> expansionsOf(int gameId) =>
      _entries.where((e) => e.game.parentId == gameId).toList();

  /// Candidatos a "jogo-base" no formulário de expansão.
  List<GameEntry> get baseGameOptions =>
      _entries.where((e) => !e.game.isGrouped).toList();

  Future<int> addGame(Game game, {List<CatalogTag> tags = const []}) async {
    final id = await _repo.insertGame(game);
    if (tags.isNotEmpty) await _repo.setGameTags(id, tags);
    await refresh();
    return id;
  }

  Future<void> saveGame(Game game, {List<CatalogTag>? tags}) async {
    await _repo.updateGame(game);
    // Nulo significa "não mexa nas etiquetas"; lista vazia significa "apague".
    if (tags != null) await _repo.setGameTags(game.id!, tags);
    await refresh();
  }

  Future<void> deleteGame(int id) async {
    await _repo.deleteGame(id);
    await refresh();
  }

  Future<List<Play>> playsFor(int gameId) => _repo.playsFor(gameId);

  /// Nomes de jogadores já usados, para sugerir no placar.
  Future<List<String>> playerNames() => _repo.playerNames();

  Future<List<PlayScore>> scoresFor(int playId) => _repo.scoresFor(playId);

  Future<Map<int, List<PlayScore>>> scoresForPlays(List<int> ids) =>
      _repo.scoresForPlays(ids);

  Future<void> logPlay(Play play, {List<PlayScore> placar = const []}) async {
    final id = await _repo.insertPlay(play);
    if (placar.isNotEmpty) await _repo.setScores(id, placar);
    await refresh();
  }

  Future<void> updatePlay(Play play, {List<PlayScore>? placar}) async {
    await _repo.updatePlay(play);
    // Nulo = "não mexa no placar"; lista vazia = "apague o que havia".
    if (placar != null) await _repo.setScores(play.id!, placar);
    await refresh();
  }

  /// Registra a saída do jogo da coleção (venda, troca ou doação).
  Future<void> registrarSaida({
    required Game jogo,
    required Disposal tipo,
    double? valorRecebido,
    DateTime? quando,
    int? trocadoPorId,
  }) async {
    await _repo.registrarSaida(
      jogo: jogo,
      tipo: tipo,
      valorRecebido: valorRecebido,
      quando: quando,
      trocadoPorId: trocadoPorId,
    );
    await refresh();
  }

  Future<void> desfazerSaida(Game jogo) async {
    await _repo.desfazerSaida(jogo);
    await refresh();
  }

  Future<void> deletePlay(int playId) async {
    await _repo.deletePlay(playId);
    await refresh();
  }
}
