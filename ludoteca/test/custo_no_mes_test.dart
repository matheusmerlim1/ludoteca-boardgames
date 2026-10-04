import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludoteca/data/database.dart';
import 'package:ludoteca/data/game_repository.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/screens/costs_screen.dart';
import 'package:ludoteca/state/collection_store.dart';
import 'package:ludoteca/stats/cost_stats.dart';
import 'package:ludoteca/theme.dart';
import 'package:ludoteca/utils/format.dart';
import 'package:ludoteca/widgets/month_spend_sheet.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// "Custo no mês": o que saiu do bolso **neste** mês, ao lado do "custo por
/// mês" (custo de posse), que é outra grandeza.
///
/// Regressão: o cartão de custo do mês mostrava o custo de posse da coleção
/// inteira — com compras recentes, praticamente o total investido — e não
/// mudava com o mês. O gasto do mês só aparecia depois de abrir a folha.

final _agora = DateTime.now();
final _esteMes = DateTime(_agora.year, _agora.month);
// Dia 1 do mês atual: nunca cai no futuro, seja qual for o dia de hoje.
final _diaDoMes = DateTime(_agora.year, _agora.month, 1);
final _mesPassado = DateTime(_agora.year, _agora.month - 1, 10);
final _anoPassado = DateTime(_agora.year - 1, _agora.month, 10);

GameEntry _entrada(Game g) => GameEntry(
      game: g,
      loggedPlays: 0,
      lastLoggedPlay: null,
      expansionCount: 0,
      expansionCost: 0,
      loggedPlaysWithDuration: 0,
      loggedMinutes: 0,
    );

void main() {
  group('CostStats — custo no mês atual', () {
    test('soma só as compras deste mês, com sleeves e acessórios', () {
      final s = CostStats.compute(entries: [
        _entrada(Game(id: 1, name: 'Deste mês', price: 300, sleeveCost: 40, purchaseDate: _diaDoMes)),
        _entrada(Game(id: 2, name: 'Também', price: 60, accessoryCost: 10, purchaseDate: _diaDoMes)),
        _entrada(Game(id: 3, name: 'Mês passado', price: 500, purchaseDate: _mesPassado)),
        _entrada(Game(id: 4, name: 'Ano passado', price: 900, purchaseDate: _anoPassado)),
        _entrada(const Game(id: 5, name: 'Sem data', price: 999)),
      ]);

      expect(s.currentMonthSpend.month, _esteMes);
      expect(s.currentMonthSpend.total, 410, reason: '300 + 40 + 60 + 10');
      expect(s.currentMonthSpend.itemCount, 2);
    });

    test('é diferente do custo por mês (custo de posse) — os dois existem', () {
      final s = CostStats.compute(entries: [
        _entrada(Game(id: 1, name: 'Deste mês', price: 300, purchaseDate: _diaDoMes)),
        _entrada(Game(id: 2, name: 'Ano passado', price: 1200, purchaseDate: _anoPassado)),
      ]);

      expect(s.currentMonthSpend.total, 300);
      // O de posse dilui cada jogo pelos meses de posse: o do ano passado
      // entra com ~1/12, o deste mês com o valor cheio.
      expect(s.monthlyOwnershipCost, greaterThan(300));
      expect(s.monthlyOwnershipCost, lessThan(1500));
    });

    test('mês sem compra: zero, com o mês certo', () {
      final s = CostStats.compute(entries: [
        _entrada(Game(id: 1, name: 'Mês passado', price: 500, purchaseDate: _mesPassado)),
      ]);

      expect(s.currentMonthSpend.month, _esteMes);
      expect(s.currentMonthSpend.total, 0);
      expect(s.currentMonthSpend.itemCount, 0);
    });

    test('jogo de outra pessoa e jogo desejado não entram', () {
      final s = CostStats.compute(entries: [
        _entrada(Game(id: 1, name: 'Do amigo', price: 500, purchaseDate: _diaDoMes, ownership: Ownership.jogada)),
        _entrada(Game(id: 2, name: 'Quero', price: 400, purchaseDate: _diaDoMes, ownership: Ownership.desejada)),
        _entrada(Game(id: 3, name: 'Meu', price: 100, purchaseDate: _diaDoMes)),
      ]);

      expect(s.currentMonthSpend.total, 100);
      expect(s.currentMonthSpend.itemCount, 1);
    });

    test('coleção sem nenhuma data: zero, sem quebrar', () {
      final s = CostStats.compute(entries: [_entrada(const Game(id: 1, name: 'Sem data', price: 100))]);
      expect(s.currentMonthSpend.total, 0);
      expect(s.currentMonthSpend.month, _esteMes);
    });
  });

  group('Tela de custos — cartão "custo no mês"', () {
    late Directory temp;
    late AppDatabase db;
    late CollectionStore store;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    Future<void> abreCustos(WidgetTester tester) async {
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('ludoteca_custo_mes');
        db = AppDatabase.paraArquivo('${temp.path}/t.db');
        final repo = GameRepository(database: db);
        await repo.insertGame(Game(name: 'Comprado agora', price: 250, sleeveCost: 30, purchaseDate: _diaDoMes));
        await repo.insertGame(Game(name: 'Comprado antes', price: 2000, purchaseDate: _anoPassado));
        store = CollectionStore(repository: repo);
        await store.load();
      });
      addTearDown(() => tester.runAsync(() async {
            await db.close();
            if (await temp.exists()) await temp.delete(recursive: true);
          }));

      tester.view.physicalSize = const Size(900, 1600);
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

    testWidgets('mostra os dois cartões: custo por mês e custo no mês', (tester) async {
      await abreCustos(tester);

      expect(find.text('CUSTO POR MÊS'), findsOneWidget);
      expect(find.text('CUSTO NO MÊS'), findsOneWidget);
      // O custo no mês é só o que foi comprado neste mês: 250 + 30.
      expect(find.text(dinheiro(280, casas: 0)), findsOneWidget);
      expect(find.textContaining(mesAnoLongo(_esteMes)), findsWidgets);
    });

    testWidgets('tocar no custo no mês abre as compras deste mês', (tester) async {
      await abreCustos(tester);

      await tester.tap(find.text('CUSTO NO MÊS'));
      await tester.pumpAndSettle();

      expect(find.byType(MonthSpendSheet), findsOneWidget);
      final folha = find.byType(MonthSpendSheet);
      expect(find.descendant(of: folha, matching: find.text(mesAnoLongo(_esteMes))), findsOneWidget);
      expect(find.descendant(of: folha, matching: find.text('Comprado agora')), findsOneWidget);
      expect(find.descendant(of: folha, matching: find.text('Comprado antes')), findsNothing);
    });
  });
}
