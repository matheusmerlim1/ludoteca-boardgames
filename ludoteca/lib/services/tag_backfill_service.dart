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
    this.capaPreenchida = false,
  });

  final Game game;
  final BackfillOutcome outcome;

  /// Nome do jogo no catálogo. Só é diferente quando o casamento foi por
  /// aproximação — e é aí que o usuário precisa conferir.
  final String? matchedName;

  final int tagCount;

  /// A capa deste jogo veio nesta passada.
  final bool capaPreenchida;
}

class BackfillReport {
  const BackfillReport({required this.itens, required this.cancelado});

  final List<BackfillItem> itens;
  final bool cancelado;

  int get preenchidos =>
      itens.where((i) => i.outcome == BackfillOutcome.preenchido).length;

  int get capas => itens.where((i) => i.capaPreenchida).length;

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

/// Busca **capa**, tema e mecânica para os jogos que ainda não têm.
///
/// Existe porque um filtro por tema nasce inútil numa coleção já cadastrada:
/// sessenta e cinco jogos digitados à mão não têm etiqueta nenhuma, e
/// preencher um a um não é trabalho que se peça a alguém. A capa entra na mesma
/// varredura porque vem na **mesma consulta** que já era feita: um jogo
/// digitado à mão (ou vindo da planilha) chega sem imagem, e a lista inteira
/// vira uma coluna de iniciais — que é o sintoma mais visível de todos.
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
  /// Com [todos], rebusca também quem já está completo. Serve para quando o app
  /// passa a ler um campo novo do catálogo — o estilo, por exemplo — e os jogos
  /// preenchidos numa versão anterior ficariam sem ele para sempre.
  Future<BackfillReport> run({
    void Function(int feitos, int total)? onProgress,
    bool todos = false,
  }) async {
    _cancelado = false;

    final pendentes = todos
        ? await repository.allGames()
        : await repository.gamesSemCapaOuTema();
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

      // A capa é gravada mesmo quando o catálogo não tem tema nenhum para o
      // jogo: são dois dados independentes, e sair daqui sem a imagem só
      // porque faltou etiqueta deixaria a lista com as iniciais à toa.
      final capa = await _gravaCapaSeFaltar(jogo, ficha);

      if (ficha.tags.isEmpty) {
        return BackfillItem(
          game: jogo,
          // Com a capa preenchida, a passada valeu — chamar isso de problema
          // mandaria o usuário conferir um jogo que não tem o que conferir.
          outcome:
              capa ? BackfillOutcome.preenchido : BackfillOutcome.semTags,
          matchedName: ficha.name,
          capaPreenchida: capa,
        );
      }

      await repository.setGameTags(jogo.id!, ficha.tags);

      return BackfillItem(
        game: jogo,
        outcome: BackfillOutcome.preenchido,
        matchedName: ficha.name,
        tagCount: ficha.tags.length,
        capaPreenchida: capa,
      );
    } on CatalogException {
      return BackfillItem(game: jogo, outcome: BackfillOutcome.falhou);
    } catch (_) {
      return BackfillItem(game: jogo, outcome: BackfillOutcome.falhou);
    }
  }

  /// Grava a capa só quando o jogo não tem nenhuma.
  ///
  /// Nunca sobrescreve: se você trocou a imagem à mão, foi de propósito, e uma
  /// varredura em lote não pode desfazer isso sem avisar.
  Future<bool> _gravaCapaSeFaltar(Game jogo, CatalogGameDetails ficha) async {
    final temCapa = (jogo.imageUrl?.isNotEmpty ?? false) ||
        (jogo.thumbUrl?.isNotEmpty ?? false);
    final achou = (ficha.imageUrl?.isNotEmpty ?? false) ||
        (ficha.thumbUrl?.isNotEmpty ?? false);
    if (temCapa || !achou) return false;

    await repository.updateGame(jogo.copyWith(
      imageUrl: ficha.imageUrl,
      thumbUrl: ficha.thumbUrl,
      // O id do BGG vem de graça na mesma ficha e é o que permite cruzar este
      // jogo com o catálogo depois sem depender do nome.
      bggId: jogo.bggId ?? ficha.bggId,
    ));
    return true;
  }
}
