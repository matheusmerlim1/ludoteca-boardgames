import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludoteca/data/database.dart';
import 'package:ludoteca/data/game_repository.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/services/game_catalog.dart';
import 'package:ludoteca/services/tag_backfill_service.dart';
import 'package:ludoteca/state/collection_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Testes do filtro por tema e do preenchimento em lote.

CatalogTag _tema(String n) => CatalogTag(name: n, kind: TagKind.tema);
CatalogTag _mec(String n) => CatalogTag(name: n, kind: TagKind.mecanica);

/// Catálogo falso: devolve o que o teste mandar, sem rede.
class _CatalogoFake implements GameCatalog {
  _CatalogoFake(this.porNome);

  /// nome buscado -> (nome encontrado, tags). Ausente = não achou.
  final Map<String, ({String nome, List<CatalogTag> tags})> porNome;

  int buscas = 0;
  int fichas = 0;

  @override
  CatalogSource get source => CatalogSource.comparajogos;

  @override
  Future<List<CatalogSearchResult>> search(String query,
      {bool comCapas = true}) async {
    buscas++;
    final achado = porNome[query];
    if (achado == null) return const [];
    return [
      CatalogSearchResult(
        source: CatalogSource.comparajogos,
        id: query.hashCode.abs(),
        name: achado.nome,
      ),
    ];
  }

  @override
  Future<CatalogGameDetails> details(int id) async {
    fichas++;
    // O id que `search` devolveu é o hash do termo buscado; desfaz o caminho
    // para achar de qual entrada do mapa esta ficha veio.
    final entrada =
        porNome.entries.firstWhere((e) => e.key.hashCode.abs() == id);
    return CatalogGameDetails(
      source: CatalogSource.comparajogos,
      id: id,
      name: entrada.value.nome,
      tags: entrada.value.tags,
    );
  }

  @override
  Future<List<CatalogGameDetails>> detailsBatch(List<int> ids) async =>
      [for (final id in ids) await details(id)];

  @override
  void dispose() {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory temp;
  late AppDatabase db;
  late GameRepository repo;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ludoteca_tags');
    db = AppDatabase.paraArquivo('${temp.path}/t.db');
    repo = GameRepository(database: db);
  });

  tearDown(() async {
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('gravar e ler etiquetas', () {
    test('grava tema e mecânica e lê de volta', () async {
      final id = await repo.insertGame(const Game(name: 'Marvel Champions'));
      await repo.setGameTags(id, [_tema('Luta'), _mec('Cooperativo')]);

      final tags = await repo.tagsFor(id);

      expect(tags.length, 2);
      expect(tags.any((t) => t.name == 'Luta' && t.kind == TagKind.tema), isTrue);
      expect(
        tags.any((t) => t.name == 'Cooperativo' && t.kind == TagKind.mecanica),
        isTrue,
      );
    });

    test('o mesmo tema em dois jogos não vira duas etiquetas', () async {
      final a = await repo.insertGame(const Game(name: 'A'));
      final b = await repo.insertGame(const Game(name: 'B'));

      await repo.setGameTags(a, [_tema('Aventura')]);
      await repo.setGameTags(b, [_tema('Aventura')]);

      final tags = await repo.loadTags();
      final aventura = tags.where((t) => t.name == 'Aventura').toList();

      expect(aventura.length, 1);
      expect(aventura.first.gameCount, 2);
    });

    test('mesmo nome como tema e como mecânica são etiquetas distintas',
        () async {
      // "Dados" existe nos dois eixos e significa coisas diferentes.
      final id = await repo.insertGame(const Game(name: 'A'));
      await repo.setGameTags(id, [_tema('Dados'), _mec('Dados')]);

      final tags = await repo.loadTags();
      expect(tags.where((t) => t.name == 'Dados').length, 2);
    });

    test('regravar substitui, não acumula', () async {
      final id = await repo.insertGame(const Game(name: 'A'));

      await repo.setGameTags(id, [_tema('Guerra'), _tema('Antiguidade')]);
      await repo.setGameTags(id, [_tema('Guerra')]);

      final tags = await repo.tagsFor(id);
      expect(tags.length, 1);
      expect(tags.first.name, 'Guerra');
    });

    test('a lista sai ordenada por uso, não por alfabeto', () async {
      // Numa lista de dezenas de temas, os seus temas frequentes têm de estar
      // no topo — em ordem alfabética ficariam perdidos no meio.
      for (var i = 0; i < 3; i++) {
        final id = await repo.insertGame(Game(name: 'Jogo $i'));
        await repo.setGameTags(id, [_tema('Zumbis')]);
      }
      final so = await repo.insertGame(const Game(name: 'Sozinho'));
      await repo.setGameTags(so, [_tema('Agricultura')]);

      final tags = await repo.loadTags();

      expect(tags.first.name, 'Zumbis');
      expect(tags.first.gameCount, 3);
    });

    test('jogo vendido não conta na contagem do tema', () async {
      // O filtro serve para escolher o que jogar hoje; um jogo que saiu da
      // coleção inflaria o número e prometeria o que não existe.
      final ativo = await repo.insertGame(const Game(name: 'Ativo'));
      final vendido = await repo.insertGame(
        Game(name: 'Vendido', sold: true, soldPrice: 100, soldDate: DateTime(2025)),
      );
      await repo.setGameTags(ativo, [_tema('Fantasia')]);
      await repo.setGameTags(vendido, [_tema('Fantasia')]);

      final tags = await repo.loadTags();
      expect(tags.single.gameCount, 1);
    });

    test('remover o jogo leva o vínculo junto', () async {
      final id = await repo.insertGame(const Game(name: 'A'));
      await repo.setGameTags(id, [_tema('Corrida')]);

      await repo.deleteGame(id);

      final vinculos = await repo.loadGameTagIds();
      expect(vinculos[id], isNull);
      // A etiqueta some da lista por não ter mais jogo nenhum.
      expect(await repo.loadTags(), isEmpty);
    });

    test('gamesWithoutTags traz só quem não tem etiqueta', () async {
      final com = await repo.insertGame(const Game(name: 'Com'));
      await repo.insertGame(const Game(name: 'Sem'));
      await repo.setGameTags(com, [_tema('Dedução')]);

      final pendentes = await repo.gamesWithoutTags();

      expect(pendentes.length, 1);
      expect(pendentes.single.name, 'Sem');
    });
  });

  group('filtro por tema', () {
    late CollectionStore store;
    late int idCoop;
    late int idSolo;

    setUp(() async {
      idCoop = await repo.insertGame(const Game(name: 'Pandemic'));
      idSolo = await repo.insertGame(const Game(name: 'Wingspan'));

      await repo.setGameTags(idCoop, [_tema('Médico'), _mec('Cooperativo')]);
      await repo.setGameTags(idSolo, [_tema('Animais')]);

      store = CollectionStore(repository: repo);
      await store.load();
    });

    int idDaTag(String nome) =>
        store.tags.firstWhere((t) => t.name == nome).id;

    test('sem filtro, mostra tudo', () {
      expect(store.filteredEntries.length, 2);
    });

    test('filtrar por um tema recorta a lista', () {
      store.setTagFilter({idDaTag('Animais')});

      final nomes = store.filteredEntries.map((e) => e.game.name).toList();
      expect(nomes, ['Wingspan']);
    });

    test('duas etiquetas exigem as duas, não qualquer uma', () {
      // Marcar mais filtros tem de estreitar o resultado. Se fosse "qualquer
      // uma", marcar mais aumentaria a lista e o filtro andaria para trás.
      store.setTagFilter({idDaTag('Médico'), idDaTag('Cooperativo')});
      expect(store.filteredEntries.length, 1);

      store.setTagFilter({idDaTag('Médico'), idDaTag('Animais')});
      expect(store.filteredEntries, isEmpty);
    });

    test('o filtro de tema conta como filtro ativo', () {
      expect(store.hasActiveFilters, isFalse);
      store.setTagFilter({idDaTag('Animais')});
      expect(store.hasActiveFilters, isTrue);
    });

    test('limpar filtros zera o tema também', () {
      store.setTagFilter({idDaTag('Animais')});
      store.clearFilters();

      expect(store.tagFilter, isEmpty);
      expect(store.filteredEntries.length, 2);
    });

    test('alternar liga e desliga a mesma etiqueta', () {
      final id = idDaTag('Animais');
      store.toggleTag(id);
      expect(store.tagFilter, {id});
      store.toggleTag(id);
      expect(store.tagFilter, isEmpty);
    });

    test('etiqueta que deixou de existir sai do filtro sozinha', () async {
      // Sem isso, o filtro apontaria para um id morto e a coleção sumiria
      // inteira, sem explicação na tela.
      final id = idDaTag('Animais');
      store.setTagFilter({id});

      await repo.deleteGame(idSolo);
      await store.load();

      expect(store.tagFilter, isEmpty);
      expect(store.filteredEntries.length, 1);
    });

    test('tagsOf devolve as etiquetas do jogo', () {
      final nomes = store.tagsOf(idCoop).map((t) => t.name).toSet();
      expect(nomes, {'Médico', 'Cooperativo'});
    });
  });

  group('estilo', () {
    test('estilo, tema e mecânica convivem como tipos distintos', () async {
      final id = await repo.insertGame(const Game(name: 'Unmatched'));
      await repo.setGameTags(id, [
        const CatalogTag(name: 'Estratégico', kind: TagKind.estilo),
        _tema('Luta'),
        _mec('Gestão de Mão'),
      ]);

      final tags = await repo.tagsFor(id);
      expect(tags.length, 3);
      expect(
        tags.map((t) => t.kind).toSet(),
        {TagKind.estilo, TagKind.tema, TagKind.mecanica},
      );
    });

    test('estilo sobrevive à ida e volta pelo banco', () async {
      final id = await repo.insertGame(const Game(name: 'A'));
      await repo.setGameTags(
        id,
        [const CatalogTag(name: 'Festivo', kind: TagKind.estilo)],
      );

      final lidas = await repo.loadTags();
      expect(lidas.single.kind, TagKind.estilo);
      expect(lidas.single.name, 'Festivo');
    });

    test('filtrar por estilo funciona como qualquer etiqueta', () async {
      final festa = await repo.insertGame(const Game(name: 'Codenames'));
      final euro = await repo.insertGame(const Game(name: 'Wingspan'));
      await repo.setGameTags(
        festa,
        [const CatalogTag(name: 'Festivo', kind: TagKind.estilo)],
      );
      await repo.setGameTags(
        euro,
        [const CatalogTag(name: 'Estratégico', kind: TagKind.estilo)],
      );

      final store = CollectionStore(repository: repo);
      await store.load();

      final idFestivo =
          store.tags.firstWhere((t) => t.name == 'Festivo').id;
      store.setTagFilter({idFestivo});

      expect(store.filteredEntries.single.game.name, 'Codenames');
    });
  });

  group('preenchimento em lote', () {
    test('preenche quem casou e relata quem não achou', () async {
      await repo.insertGame(const Game(name: 'Pandemic'));
      await repo.insertGame(const Game(name: 'Jogo Inventado'));

      final catalogo = _CatalogoFake({
        'Pandemic': (nome: 'Pandemic', tags: [_tema('Médico'), _mec('Cooperativo')]),
      });

      final r = await TagBackfillService(
        catalogo: catalogo,
        repository: repo,
        pausa: Duration.zero,
      ).run();

      expect(r.preenchidos, 1);
      expect(r.problemas.length, 1);
      expect(r.problemas.single.game.name, 'Jogo Inventado');
      expect(r.problemas.single.outcome, BackfillOutcome.naoEncontrado);
    });

    test('sinaliza casamento aproximado, para você conferir', () async {
      // É aqui que o erro se esconde: um "Catan" que virou "Catan Junior"
      // traria os temas errados sem ninguém perceber.
      await repo.insertGame(const Game(name: 'Catan'));

      final catalogo = _CatalogoFake({
        'Catan': (nome: 'Catan Junior', tags: [_tema('Náutico')]),
      });

      final r = await TagBackfillService(
        catalogo: catalogo,
        repository: repo,
        pausa: Duration.zero,
      ).run();

      expect(r.preenchidos, 1);
      expect(r.aproximados.length, 1);
      expect(r.aproximados.single.matchedName, 'Catan Junior');
    });

    test('nome igual não entra na lista de conferir', () async {
      await repo.insertGame(const Game(name: 'Pandemic'));

      final catalogo = _CatalogoFake({
        'Pandemic': (nome: 'Pandemic', tags: [_tema('Médico')]),
      });

      final r = await TagBackfillService(
        catalogo: catalogo,
        repository: repo,
        pausa: Duration.zero,
      ).run();

      expect(r.aproximados, isEmpty);
    });

    test('não mexe em quem já tem etiqueta', () async {
      final jaTem = await repo.insertGame(const Game(name: 'Pandemic'));
      await repo.setGameTags(jaTem, [_tema('Meu tema')]);

      final catalogo = _CatalogoFake({
        'Pandemic': (nome: 'Pandemic', tags: [_tema('Médico')]),
      });

      await TagBackfillService(
        catalogo: catalogo,
        repository: repo,
        pausa: Duration.zero,
      ).run();

      expect(catalogo.buscas, 0, reason: 'nem devia ter ido à rede');
      final tags = await repo.tagsFor(jaTem);
      expect(tags.single.name, 'Meu tema');
    });

    test('relata progresso a cada jogo', () async {
      await repo.insertGame(const Game(name: 'A'));
      await repo.insertGame(const Game(name: 'B'));

      final passos = <String>[];
      await TagBackfillService(
        catalogo: _CatalogoFake(const {}),
        repository: repo,
        pausa: Duration.zero,
      ).run(onProgress: (f, t) => passos.add('$f/$t'));

      expect(passos, ['1/2', '2/2']);
    });

    test('com todos: true, rebusca também quem já tem etiqueta', () async {
      // É assim que o estilo alcança quem foi preenchido antes de o app
      // aprender a ler esse campo.
      final jaTem = await repo.insertGame(const Game(name: 'Pandemic'));
      await repo.setGameTags(jaTem, [_tema('Antigo')]);

      final catalogo = _CatalogoFake({
        'Pandemic': (
          nome: 'Pandemic',
          tags: [const CatalogTag(name: 'Temático', kind: TagKind.estilo)],
        ),
      });

      final r = await TagBackfillService(
        catalogo: catalogo,
        repository: repo,
        pausa: Duration.zero,
      ).run(todos: true);

      expect(r.preenchidos, 1);
      final tags = await repo.tagsFor(jaTem);
      expect(tags.single.name, 'Temático');
      expect(tags.single.kind, TagKind.estilo);
    });

    test('cancelar interrompe e marca o relatório', () async {
      for (var i = 0; i < 5; i++) {
        await repo.insertGame(Game(name: 'Jogo $i'));
      }

      final servico = TagBackfillService(
        catalogo: _CatalogoFake(const {}),
        repository: repo,
        pausa: Duration.zero,
      );

      final r = await servico.run(
        onProgress: (f, _) {
          if (f == 2) servico.cancel();
        },
      );

      expect(r.cancelado, isTrue);
      expect(r.itens.length, lessThan(5));
    });
  });
}
