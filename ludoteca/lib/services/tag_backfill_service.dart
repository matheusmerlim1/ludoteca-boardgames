import '../data/game_repository.dart';
import '../models/game.dart';
import 'game_catalog.dart';

/// Como um jogo se saiu no preenchimento.
enum BackfillOutcome { preenchido, semTags, naoEncontrado, falhou }

class BackfillItem {
  const BackfillItem({
    required this.game,
    required this.outcome,
    this.matchedName,
    this.tagCount = 0,
  });

  final Game game;
  final BackfillOutcome outcome;

  /// Nome do jogo no catálogo. Só é diferente quando o casamento foi por
  /// aproximação — e é aí que o usuário precisa conferir.
  final String? matchedName;

  final int tagCount;
}

class BackfillReport {
  const BackfillReport({required this.itens, required this.cancelado});

  final List<BackfillItem> itens;
  final bool cancelado;

  int get preenchidos =>
      itens.where((i) => i.outcome == BackfillOutcome.preenchido).length;

  List<BackfillItem> get problemas => itens
      .where((i) => i.outcome != BackfillOutcome.preenchido)
      .toList(growable: false);

  /// Casamentos em que o nome do catálogo difere do seu — os que valem
  /// conferir, porque é onde um "Catan" pode ter virado "Catan Junior".
  List<BackfillItem> get aproximados => itens
      .where((i) =>
          i.outcome == BackfillOutcome.preenchido &&
          i.matchedName != null &&
          _normaliza(i.matchedName!) != _normaliza(i.game.displayName))
      .toList(growable: false);

  static String _normaliza(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

/// Busca temas e mecânicas para os jogos que ainda não têm.
///
/// Existe porque um filtro por tema nasce inútil numa coleção já cadastrada:
/// sessenta e cinco jogos digitados à mão não têm etiqueta nenhuma, e
/// preencher um a um não é trabalho que se peça a alguém.
///
/// O casamento é **por nome**, então pode errar. Por isso o relatório separa os
/// casos em que o nome encontrado difere do seu — são exatamente esses que
/// merecem conferência, e escondê-los seria pior que não preencher.
class TagBackfillService {
  TagBackfillService({
    required this.catalogo,
    required this.repository,
    this.pausa = const Duration(milliseconds: 350),
  });

  final GameCatalog catalogo;
  final GameRepository repository;

  /// Espera entre jogos. A API é de terceiro e não documentada: varrer a
  /// coleção inteira o mais rápido possível seria falta de educação, e o custo
  /// aqui é alguns segundos numa operação que se faz uma vez.
  final Duration pausa;

  bool _cancelado = false;
  void cancel() => _cancelado = true;

  /// [onProgress] recebe (feitos, total) para a tela mostrar andamento.
  ///
  /// Com [todos], rebusca também quem já tem etiqueta. Serve para quando o app
  /// passa a ler um campo novo do catálogo — o estilo, por exemplo — e os jogos
  /// preenchidos numa versão anterior ficariam sem ele para sempre.
  Future<BackfillReport> run({
    void Function(int feitos, int total)? onProgress,
    bool todos = false,
  }) async {
    _cancelado = false;

    final pendentes = todos
        ? await repository.allGames()
        : await repository.gamesWithoutTags();
    final itens = <BackfillItem>[];

    for (var i = 0; i < pendentes.length; i++) {
      if (_cancelado) break;

      final jogo = pendentes[i];
      itens.add(await _umJogo(jogo));
      onProgress?.call(i + 1, pendentes.length);

      if (i < pendentes.length - 1 && !_cancelado) {
        await Future<void>.delayed(pausa);
      }
    }

    return BackfillReport(itens: itens, cancelado: _cancelado);
  }

  Future<BackfillItem> _umJogo(Game jogo) async {
    try {
      // Busca pelo nome original: é o que o catálogo indexa. O nome em
      // português é o seu apelido e pode não existir lá.
      final resultados = await catalogo.search(jogo.name, comCapas: false);
      if (resultados.isEmpty) {
        return BackfillItem(
          game: jogo,
          outcome: BackfillOutcome.naoEncontrado,
        );
      }

      final escolhido = resultados.first;
      final ficha = await catalogo.details(escolhido.id);

      if (ficha.tags.isEmpty) {
        return BackfillItem(
          game: jogo,
          outcome: BackfillOutcome.semTags,
          matchedName: ficha.name,
        );
      }

      await repository.setGameTags(jogo.id!, ficha.tags);

      return BackfillItem(
        game: jogo,
        outcome: BackfillOutcome.preenchido,
        matchedName: ficha.name,
        tagCount: ficha.tags.length,
      );
    } on CatalogException {
      return BackfillItem(game: jogo, outcome: BackfillOutcome.falhou);
    } catch (_) {
      return BackfillItem(game: jogo, outcome: BackfillOutcome.falhou);
    }
  }
}
