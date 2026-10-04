import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludoteca/data/database.dart';
import 'package:ludoteca/data/game_repository.dart';
import 'package:ludoteca/models/extra.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/screens/costs_screen.dart';
import 'package:ludoteca/state/collection_store.dart';
import 'package:ludoteca/stats/cost_stats.dart';
import 'package:ludoteca/theme.dart';
import 'package:ludoteca/utils/format.dart';
import 'package:ludoteca/widgets/extra_sheet.dart';
import 'package:ludoteca/widgets/month_spend_sheet.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Kits e extras avulsos: sleeves, playmat, organizador que não são de um
/// jogo só. Entram no custo do mês e nos gastos, mas não no custo por
/// partida — um playmat não é de jogo nenhum.

final _agora = DateTime.now();
final _esteMes = DateTime(_agora.year, _agora.month);
final _diaDoMes = DateTime(_agora.year, _agora.month, 1);
final _anoPassado = DateTime(_agora.year - 1, _agora.month, 10);

GameEntry _entrada(Game g, {int loggedPlays = 0}) => GameEntry(
      game: g,
      loggedPlays: loggedPlays,
      lastLoggedPlay: null,
      expansionCount: 0,
      expansionCost: 0,
      loggedPlaysWithDuration: 0,
      loggedMinutes: 0,
    );

void main() {
  group('Extra (modelo)', () {
    test('ida e volta pelo banco preserva tudo', () {
      final x = Extra(
        id: 7,
        name: 'Playmat neoprene',
        kind: ExtraKind.playmat,
        price: 129.9,
        purchaseDate: DateTime(2026, 5, 3),
        notes: 'para Wingspan e Cascadia',
      );
      final y = Extra.fromMap(x.toMap());
      expect(y.id, 7);
      expect(y.name, 'Playmat neoprene');
      expect(y.kind, ExtraKind.playmat);
      expect(y.price, 129.9);
      expect(y.purchaseDate, DateTime(2026, 5, 3));
      expect(y.notes, 'para Wingspan e Cascadia');
    });

    test('tipo desconhecido no banco vira "outro", sem quebrar', () {
      expect(ExtraKind.fromDb('inventado'), ExtraKind.outro);
      expect(ExtraKind.fromDb(null), ExtraKind.outro);
    });

    test('só o tipo sleeves conta como sleeve', () {
      expect(const Extra(name: 'a', kind: ExtraKind.sleeves).isSleeve, isTrue);
      for (final k in ExtraKind.values.where((k) => k != ExtraKind.sleeves)) {
        expect(Extra(name: 'a', kind: k).isSleeve, isFalse);
      }
    });
  });

  group('CostStats com extras', () {
    final jogo = _entrada(
      Game(id: 1, name: 'Jogo', price: 200, purchaseDate: _diaDoMes),
      loggedPlays: 4,
    );
    final kitSleeves = Extra(id: 1, name: 'Kit sleeves', kind: ExtraKind.sleeves, price: 60, purchaseDate: _diaDoMes);
    final playmat = Extra(id: 2, name: 'Playmat', kind: ExtraKind.playmat, price: 140, purchaseDate: _diaDoMes);
    final antigo = Extra(id: 3, name: 'Organizador', kind: ExtraKind.organizador, price: 80, purchaseDate: _anoPassado);

    test('entram no custo no mês da compra', () {
      final s = CostStats.compute(entries: [jogo], extras: [kitSleeves, playmat, antigo]);
      expect(s.currentMonthSpend.total, 400, reason: '200 do jogo + 60 + 140');
      expect(s.currentMonthSpend.itemCount, 3);
      expect(s.currentMonthSpend.sleeves, 60);
      expect(s.currentMonthSpend.accessories, 140);
    });

    test('entram no mês certo da linha do tempo', () {
      final s = CostStats.compute(entries: [jogo], extras: [antigo]);
      final mes = s.monthlySpend.firstWhere(
          (m) => m.month == DateTime(_anoPassado.year, _anoPassado.month));
      expect(mes.total, 80);
      expect(mes.itemCount, 1);
    });

    test('não mexem no custo por partida nem no investimento nos jogos', () {
      final sem = CostStats.compute(entries: [jogo]);
      final com = CostStats.compute(entries: [jogo], extras: [kitSleeves, playmat]);
      expect(com.totalInvested, sem.totalInvested);
      expect(com.avgCostPerPlay, sem.avgCostPerPlay);
      expect(com.monthlyOwnershipCost, sem.monthlyOwnershipCost);
      expect(com.extrasTotal, 200);
      expect(com.totalSpent, 400);
      expect(com.extrasCount, 2);
    });

    test('aparecem em "em que você gastou"', () {
      final s = CostStats.compute(entries: [jogo], extras: [kitSleeves, playmat]);
      final porTipo = {for (final f in s.compositionByType) f.label: f.value};
      expect(porTipo['Caixa do jogo'], 200);
      expect(porTipo['Sleeves'], 60);
      expect(porTipo['Acessórios'], 140);
    });

    test('só extras, sem jogo: a tela não fica vazia', () {
      final s = CostStats.compute(entries: const [], extras: [playmat]);
      expect(s.isEmpty, isFalse);
      expect(s.currentMonthSpend.total, 140);
    });

    test('extra sem data entra no total, mas em mês nenhum', () {
      const semData = Extra(name: 'Sem data', price: 50);
      final s = CostStats.compute(entries: [jogo], extras: [semData]);
      expect(s.extrasTotal, 50);
      expect(s.currentMonthSpend.total, 200);
    });
  });

  group('Extras no banco', () {
    late Directory temp;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(() async => temp = await Directory.systemTemp.createTemp('ludoteca_extras'));
    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('cadastrar, listar, editar e apagar', () async {
      final db = AppDatabase.paraArquivo('${temp.path}/t.db');
      final repo = GameRepository(database: db);

      final id = await repo.insertExtra(
          Extra(name: 'Kit sleeves', kind: ExtraKind.sleeves, price: 45, purchaseDate: DateTime(2026, 9, 2)));
      var lista = await repo.extras();
      expect(lista.single.name, 'Kit sleeves');
      expect(lista.single.id, id);

      await repo.updateExtra(lista.single.copyWith(price: 50, name: 'Kit 100 sleeves'));
      lista = await repo.extras();
      expect(lista.single.price, 50);
      expect(lista.single.name, 'Kit 100 sleeves');

      await repo.deleteExtra(id);
      expect(await repo.extras(), isEmpty);
      await db.close();
    });

    test('migração 9 → 10 cria a tabela sem tocar no resto', () async {
      final caminho = '${temp.path}/antigo.db';
      // Banco "da versão anterior": só o número da versão importa aqui, porque
      // o passo 9 → 10 apenas cria a tabela nova.
      final antigo = await databaseFactory.openDatabase(
        caminho,
        options: OpenDatabaseOptions(
          version: 9,
          onCreate: (db, v) => db.execute('CREATE TABLE marcador (x INTEGER)'),
        ),
      );
      await antigo.insert('marcador', {'x': 42});
      await antigo.close();

      final db = AppDatabase.paraArquivo(caminho);
      final repo = GameRepository(database: db);
      expect(await repo.extras(), isEmpty);
      await repo.insertExtra(const Extra(name: 'Playmat', kind: ExtraKind.playmat, price: 100));
      expect((await repo.extras()).single.kind, ExtraKind.playmat);

      final d = await db.db;
      expect(await d.getVersion(), AppDatabase.versaoAtual);
      expect((await d.query('marcador')).single['x'], 42, reason: 'o que já existia fica intacto');
      await db.close();
    });

    test('backup leva os extras e a restauração os traz de volta', () async {
      final db = AppDatabase.paraArquivo('${temp.path}/t.db');
      final repo = GameRepository(database: db);
      await repo.insertExtra(
          Extra(name: 'Organizador', kind: ExtraKind.organizador, price: 89, purchaseDate: DateTime(2026, 8, 1)));

      final backup = await repo.exportAll();
      expect((backup['extras'] as List).length, 1);

      await repo.deleteExtra((await repo.extras()).single.id!);
      expect(await repo.extras(), isEmpty);

      await repo.importAll(backup);
      final volta = await repo.extras();
      expect(volta.single.name, 'Organizador');
      expect(volta.single.price, 89);
      await db.close();
    });

    test('backup antigo, sem a chave "extras", restaura sem erro', () async {
      final db = AppDatabase.paraArquivo('${temp.path}/t.db');
      final repo = GameRepository(database: db);
      await repo.insertExtra(const Extra(name: 'Vai sumir', price: 10));

      final r = await repo.importAll({'schema': 1, 'jogos': const [], 'partidas': const []});
      expect(r.jogos, 0);
      expect(await repo.extras(), isEmpty, reason: 'restaurar substitui a coleção inteira');
      await db.close();
    });
  });

  group('Telas', () {
    late Directory temp;
    late AppDatabase db;
    late CollectionStore store;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    Future<void> abreCustos(WidgetTester tester, {List<Extra> extras = const []}) async {
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('ludoteca_extras_tela');
        db = AppDatabase.paraArquivo('${temp.path}/t.db');
        final repo = GameRepository(database: db);
        await repo.insertGame(Game(name: 'Jogo do mês', price: 200, purchaseDate: _diaDoMes));
        for (final x in extras) {
          await repo.insertExtra(x);
        }
        store = CollectionStore(repository: repo);
        await store.load();
      });
      addTearDown(() => tester.runAsync(() async {
            await db.close();
            if (await temp.exists()) await temp.delete(recursive: true);
          }));

      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<CollectionStore>.value(
          value: store,
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const CostsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('extra do mês soma no cartão "custo no mês" e no total', (tester) async {
      await abreCustos(tester, extras: [
        Extra(name: 'Playmat grande', kind: ExtraKind.playmat, price: 150, purchaseDate: _diaDoMes),
      ]);

      expect(find.text(dinheiro(350, casas: 0)), findsNWidgets(2),
          reason: 'custo no mês e total investido: 200 + 150');
      expect(find.textContaining('+ 1 extra'), findsOneWidget);
    });

    testWidgets('a aba Dinheiro lista os kits e extras', (tester) async {
      await abreCustos(tester, extras: [
        Extra(name: 'Kit sleeves 63,5', kind: ExtraKind.sleeves, price: 40, purchaseDate: _diaDoMes),
      ]);
      await tester.tap(find.widgetWithText(Tab, 'Dinheiro'));
      await tester.pumpAndSettle();
      // Cada aba tem a própria lista; rola a vertical que está na tela.
      await tester.scrollUntilVisible(
        find.text('Kits e extras'),
        300,
        scrollable: find
            .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .hitTestable()
            .first,
      );

      expect(find.text('Kits e extras'), findsOneWidget);
      expect(find.text('Kit sleeves 63,5'), findsOneWidget);
    });

    testWidgets('a folha do mês mostra o extra junto dos jogos', (tester) async {
      await abreCustos(tester, extras: [
        Extra(name: 'Organizador de cartas', kind: ExtraKind.organizador, price: 300, purchaseDate: _diaDoMes),
      ]);
      await tester.tap(find.text('CUSTO NO MÊS'));
      await tester.pumpAndSettle();

      final folha = find.byType(MonthSpendSheet);
      expect(find.descendant(of: folha, matching: find.text(mesAnoLongo(_esteMes))), findsOneWidget);
      expect(find.descendant(of: folha, matching: find.text('Organizador de cartas')), findsOneWidget);
      expect(find.descendant(of: folha, matching: find.text('Jogo do mês')), findsOneWidget);
      expect(find.descendant(of: folha, matching: find.textContaining('2 itens')), findsOneWidget);
    });

    testWidgets('o botão do topo abre o cadastro de extra', (tester) async {
      await abreCustos(tester);
      await tester.tap(find.byTooltip('Adicionar kit ou extra').first);
      await tester.pumpAndSettle();
      expect(find.byType(ExtraSheet), findsOneWidget);
      expect(find.text('Novo extra'), findsOneWidget);
    });

    /// Tela do tamanho de um celular: a folha inteira cabe sem rolar.
    void telaDeCelular(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
    }

    testWidgets('a folha de cadastro devolve o extra preenchido, com data de hoje', (tester) async {
      telaDeCelular(tester);
      ExtraResultado? resultado;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => resultado = await ExtraSheet.show(ctx),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Playmat'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Playmat neoprene');
      await tester.enterText(find.widgetWithText(TextFormField, 'Preço'), '129,90');
      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();

      expect(resultado, isNotNull);
      expect(resultado!.apagar, isFalse);
      expect(resultado!.salvo!.name, 'Playmat neoprene');
      expect(resultado!.salvo!.kind, ExtraKind.playmat);
      expect(resultado!.salvo!.price, closeTo(129.90, 0.001));
      expect(resultado!.salvo!.purchaseDate, soData(DateTime.now()));
    });

    testWidgets('sem preço, o cadastro não fecha', (tester) async {
      telaDeCelular(tester);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(onPressed: () => ExtraSheet.show(ctx), child: const Text('abrir')),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();

      expect(find.byType(ExtraSheet), findsOneWidget);
      expect(find.text('Informe quanto custou'), findsOneWidget);
    });
  });
}
