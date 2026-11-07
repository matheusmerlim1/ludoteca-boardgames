import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludoteca/data/database.dart';
import 'package:ludoteca/data/game_repository.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/screens/game_detail_screen.dart';
import 'package:ludoteca/state/collection_store.dart';
import 'package:ludoteca/theme.dart';
import 'package:ludoteca/utils/format.dart';
import 'package:ludoteca/widgets/log_play_sheet.dart';
import 'package:ludoteca/widgets/play_timer.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('duração digitada', () {
    test('minutos puros, com ou sem "min"', () {
      expect(parseDuracao('95'), 95);
      expect(parseDuracao('40min'), 40);
      expect(parseDuracao(' 40 min '), 40);
    });

    test('horas e minutos: 1:40, 1h40, 1h 40min, 2h', () {
      expect(parseDuracao('1:40'), 100);
      expect(parseDuracao('1:05'), 65);
      expect(parseDuracao('1h40'), 100);
      expect(parseDuracao('1h 40min'), 100);
      expect(parseDuracao('2h'), 120);
      expect(parseDuracao('0:45'), 45);
    });

    test('teclado numérico: "1 00" é 1h, e ".", "," e "-" também separam', () {
      expect(parseDuracao('1 00'), 60);
      expect(parseDuracao('1 40'), 100);
      expect(parseDuracao(' 2  15 '), 135);
      expect(parseDuracao('1.30'), 90);
      expect(parseDuracao('1,30'), 90);
      expect(parseDuracao('1-05'), 65);
      expect(parseDuracao('100'), 100); // sem separador continua minutos
      expect(parseDuracao('1 75'), isNull);
    });

    test('o que não dá para entender vira nulo', () {
      expect(parseDuracao(''), isNull);
      expect(parseDuracao('1:75'), isNull);
      expect(parseDuracao('abc'), isNull);
      expect(parseDuracao('1:2:3'), isNull);
    });

    test('volta para o campo no mesmo formato', () {
      expect(duracaoDigitavel(40), '40');
      expect(duracaoDigitavel(100), '1:40');
      expect(duracaoDigitavel(120), '2:00');
      expect(parseDuracao(duracaoDigitavel(185)), 185);
    });
  });

  testWidgets('a folha de registro também liga o cronômetro', (tester) async {
    late Directory temp;
    late AppDatabase db;
    late CollectionStore store;
    late Game jogo;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('ludoteca_crono_f');
      db = AppDatabase.paraArquivo('${temp.path}/t.db');
      final repo = GameRepository(database: db);
      final id = await repo.insertGame(const Game(name: 'Azul'));
      store = CollectionStore(repository: repo);
      await store.load();
      jogo = store.entryById(id)!.game;
    });
    addTearDown(() => tester.runAsync(() async {
          await db.close();
          await temp.delete(recursive: true);
        }));
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChangeNotifierProvider<CollectionStore>.value(
      value: store,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => LogPlaySheet.show(ctx, game: jogo),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    final iniciar = find.text('Iniciar cronômetro');
    expect(iniciar, findsOneWidget);
    await tester.ensureVisible(iniciar);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(iniciar);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(store.partidaEmAndamento?.gameId, jogo.id);
    expect(find.text('Salvar partida'), findsNothing);
  });

  testWidgets('tocar no balão de duração soma ao que já está no campo',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const jogo = Game(id: 1, name: 'Brass', minPlaytime: 90, maxPlaytime: 120);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => LogPlaySheet.show(ctx, game: jogo),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    final minutos = find.text('Minutos');
    await tester.ensureVisible(minutos);
    await tester.tap(minutos);
    await tester.pumpAndSettle();

    String campo() => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Quanto durou'))
        .controller!
        .text;

    // Campo vazio: o balão só preenche.
    await tester.ensureVisible(find.text('1h30'));
    await tester.tap(find.text('1h30'));
    await tester.pumpAndSettle();
    expect(campo(), '1:30');

    // Com tempo no campo: o rótulo ganha "+" e o toque soma.
    expect(find.text('+1h45'), findsOneWidget);
    await tester.tap(find.text('+1h45'));
    await tester.pumpAndSettle();
    expect(campo(), '3:15');
  });

  group('cronômetro', () {
    test('relógio em h:mm:ss', () {
      expect(relogio(const Duration(minutes: 7, seconds: 42)), '0:07:42');
      expect(relogio(const Duration(hours: 1, minutes: 40, seconds: 5)),
          '1:40:05');
    });

    test('minutos arredondados, nunca zero', () {
      final i = DateTime(2026, 11, 1, 20);
      expect(minutosDoCronometro(i, i.add(const Duration(seconds: 20))), 1);
      expect(
          minutosDoCronometro(
              i, i.add(const Duration(minutes: 99, seconds: 40))),
          100);
    });

    test('continua ligado depois de reabrir o app', () async {
      final temp = await Directory.systemTemp.createTemp('ludoteca_crono');
      final db = AppDatabase.paraArquivo('${temp.path}/t.db');
      try {
        final repo = GameRepository(database: db);
        final id = await repo.insertGame(const Game(name: 'Azul'));
        final inicio = DateTime(2026, 11, 1, 21, 15);

        final a = CollectionStore(repository: repo);
        await a.load();
        await a.iniciarCronometro(id, agora: inicio);

        final b = CollectionStore(repository: repo);
        await b.load();
        expect(b.partidaEmAndamento?.gameId, id);
        expect(b.partidaEmAndamento?.inicio, inicio);

        await b.encerrarCronometro();
        final c = CollectionStore(repository: repo);
        await c.load();
        expect(c.partidaEmAndamento, isNull);
      } finally {
        await db.close();
        await temp.delete(recursive: true);
      }
    });

    testWidgets('finalizar abre o registro com os minutos medidos',
        (tester) async {
      late Directory temp;
      late AppDatabase db;
      late CollectionStore store;
      late int id;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('ludoteca_crono_w');
        db = AppDatabase.paraArquivo('${temp.path}/t.db');
        final repo = GameRepository(database: db);
        id = await repo.insertGame(const Game(
          name: 'Azul',
          minPlayers: 2,
          maxPlayers: 4,
          minPlaytime: 30,
          maxPlaytime: 45,
        ));
        store = CollectionStore(repository: repo);
        await store.load();
        await store.iniciarCronometro(id,
            agora: DateTime.now().subtract(const Duration(minutes: 100)));
      });
      addTearDown(() => tester.runAsync(() async {
            await db.close();
            await temp.delete(recursive: true);
          }));

      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await tester.pumpWidget(ChangeNotifierProvider<CollectionStore>.value(
          value: store,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: GameDetailScreen(gameId: id),
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      // O relógio tiquetaqueia a cada segundo: pumpAndSettle nunca assentaria.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Iniciar cronômetro'), findsNothing);
      expect(find.textContaining('1:40:'), findsOneWidget);

      final finalizar = find.widgetWithText(FilledButton, 'Finalizar');
      await tester.ensureVisible(finalizar);
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(finalizar);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final campo = find.widgetWithText(TextField, 'Quanto durou');
      expect(campo, findsOneWidget);
      expect(tester.widget<TextField>(campo).controller!.text, '1:40');
      expect(find.text('= 1h40'), findsOneWidget);

      final salvar = find.text('Salvar partida');
      await tester.ensureVisible(salvar);
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(salvar);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final partidas = await tester
          .runAsync(() => GameRepository(database: db).playsFor(id));
      expect(partidas, hasLength(1));
      expect(partidas!.first.durationMinutes, 100);
      expect(store.partidaEmAndamento, isNull);
      expect(find.text('Iniciar cronômetro'), findsOneWidget);
    });
  });
}
