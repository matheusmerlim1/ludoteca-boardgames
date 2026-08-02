import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludoteca/data/database.dart';
import 'package:ludoteca/data/game_repository.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/models/play.dart';
import 'package:ludoteca/models/play_score.dart';
import 'package:ludoteca/stats/cost_stats.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Saída da coleção (venda, troca, doação) e placar das partidas.
///
/// Os dois assuntos moram no mesmo arquivo porque são a mesma pergunta em
/// tempos diferentes: o que aconteceu com o jogo, e o que aconteceu na mesa.
/// O que se testa aqui é sobretudo **dinheiro**, que é onde um erro passa
/// despercebido por meses até a conta do ano não fechar.

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory temp;
  late AppDatabase db;
  late GameRepository repo;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ludoteca_saida');
    db = AppDatabase.paraArquivo('${temp.path}/t.db');
    repo = GameRepository(database: db);
  });

  tearDown(() async {
    await db.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<Game> recarrega(int id) async {
    final todos = await repo.loadEntries();
    return todos.firstWhere((e) => e.game.id == id).game;
  }

  Future<CostStats> contas() async =>
      CostStats.compute(entries: await repo.loadEntries());

  group('venda', () {
    test('grava o valor recebido e tira o jogo da estante', () async {
      final id = await repo.insertGame(
        const Game(name: 'Scythe', price: 400, sleeveCost: 50),
      );
      final jogo = await recarrega(id);

      await repo.registrarSaida(
        jogo: jogo,
        tipo: Disposal.vendido,
        valorRecebido: 320,
        quando: DateTime(2026, 3, 10),
      );

      final depois = await recarrega(id);
      expect(depois.disposal, Disposal.vendido);
      expect(depois.soldPrice, 320);
      expect(depois.isGone, isTrue);
      expect(depois.countsAsInvestment, isFalse);
    });

    test('o valor recebido abate o investimento total', () async {
      final ficou = await repo.insertGame(const Game(name: 'Ark Nova', price: 500));
      final saiu = await repo.insertGame(const Game(name: 'Scythe', price: 400));

      expect((await contas()).totalInvested, 900);

      await repo.registrarSaida(
        jogo: await recarrega(saiu),
        tipo: Disposal.vendido,
        valorRecebido: 300,
      );

      // O que saiu deixa de contar como investimento, e os 300 aparecem como
      // recuperados — não some tudo como se o jogo nunca tivesse existido.
      final depois = await contas();
      expect(depois.totalInvested, 500);
      expect(depois.totalRecovered, 300);
      expect(ficou, isNotNull);
    });
  });

  group('troca', () {
    test('transfere o investido para o jogo que entrou', () async {
      final saiu = await repo.insertGame(
        const Game(name: 'Scythe', price: 400, sleeveCost: 50, accessoryCost: 30),
      );
      // O jogo que chegou não custou dinheiro novo: entrou pela troca.
      final entrou = await repo.insertGame(const Game(name: 'Dune Imperium'));

      await repo.registrarSaida(
        jogo: await recarrega(saiu),
        tipo: Disposal.trocado,
        trocadoPorId: entrou,
      );

      final novo = await recarrega(entrou);
      expect(novo.price, 480);

      final velho = await recarrega(saiu);
      expect(velho.disposal, Disposal.trocado);
      expect(velho.tradedForId, entrou);
      // Numa troca ninguém recebeu dinheiro; gravar valor aqui inventaria uma
      // recuperação que nunca existiu.
      expect(velho.soldPrice, isNull);
    });

    test('o total investido na coleção não muda com a troca', () async {
      final saiu = await repo.insertGame(const Game(name: 'Scythe', price: 400));
      final entrou = await repo.insertGame(const Game(name: 'Dune Imperium'));

      final antes = (await contas()).totalInvested;

      await repo.registrarSaida(
        jogo: await recarrega(saiu),
        tipo: Disposal.trocado,
        trocadoPorId: entrou,
      );

      // O dinheiro mudou de caixa, não sumiu nem apareceu.
      final depois = await contas();
      expect(depois.totalInvested, antes);
      expect(depois.totalRecovered, 0);
    });

    test('desfazer a troca devolve o valor de onde veio', () async {
      final saiu = await repo.insertGame(const Game(name: 'Scythe', price: 400));
      final entrou = await repo.insertGame(
        const Game(name: 'Dune Imperium', price: 100),
      );

      await repo.registrarSaida(
        jogo: await recarrega(saiu),
        tipo: Disposal.trocado,
        trocadoPorId: entrou,
      );
      expect((await recarrega(entrou)).price, 500);

      await repo.desfazerSaida(await recarrega(saiu));

      expect((await recarrega(entrou)).price, 100);
      final velho = await recarrega(saiu);
      expect(velho.disposal, isNull);
      expect(velho.isGone, isFalse);
    });

    test('troca sem apontar o jogo novo não transfere nada', () async {
      final saiu = await repo.insertGame(const Game(name: 'Scythe', price: 400));
      final outro = await repo.insertGame(const Game(name: 'Ark Nova', price: 500));

      await repo.registrarSaida(
        jogo: await recarrega(saiu),
        tipo: Disposal.trocado,
      );

      expect((await recarrega(outro)).price, 500);
      expect((await recarrega(saiu)).tradedForId, isNull);
    });
  });

  group('doação', () {
    test('não devolve dinheiro nenhum', () async {
      final id = await repo.insertGame(const Game(name: 'Coup', price: 60));

      await repo.registrarSaida(jogo: await recarrega(id), tipo: Disposal.doado);

      final depois = await recarrega(id);
      expect(depois.disposal, Disposal.doado);
      expect(depois.soldPrice, isNull);

      // Doar não devolve nada: o que saiu do bolso continua fora.
      expect((await contas()).totalRecovered, 0);
    });
  });

  group('histórico continua valendo', () {
    test('as partidas do jogo que saiu não somem', () async {
      final id = await repo.insertGame(const Game(name: 'Scythe', price: 400));
      await repo.insertPlay(Play(gameId: id, playedAt: DateTime(2026, 1, 5)));
      await repo.insertPlay(Play(gameId: id, playedAt: DateTime(2026, 2, 5)));

      await repo.registrarSaida(
        jogo: await recarrega(id),
        tipo: Disposal.vendido,
        valorRecebido: 300,
      );

      final entry = (await repo.loadEntries()).firstWhere((e) => e.id == id);
      expect(entry.playCount, 2);
      expect((await repo.playsFor(id)).length, 2);
    });
  });

  group('placar', () {
    test('grava jogadores, pontos e vencedor e lê de volta', () async {
      final id = await repo.insertGame(const Game(name: 'Ark Nova'));
      final playId = await repo.insertPlay(
        Play(gameId: id, playedAt: DateTime(2026, 4, 1)),
      );

      await repo.setScores(playId, const [
        PlayScore(playerName: 'Matheus', score: 112, won: true),
        PlayScore(playerName: 'Ana', score: 98),
      ]);

      final placar = await repo.scoresFor(playId);
      expect(placar.length, 2);
      expect(placar.map((s) => s.playerName), containsAll(['Matheus', 'Ana']));
      expect(placar.vencedores.single.playerName, 'Matheus');
      expect(placar.maiorPontuacao, 112);
    });

    test('regravar substitui, não duplica', () async {
      final id = await repo.insertGame(const Game(name: 'Ark Nova'));
      final playId = await repo.insertPlay(
        Play(gameId: id, playedAt: DateTime(2026, 4, 1)),
      );

      await repo.setScores(playId, const [PlayScore(playerName: 'Ana', score: 10)]);
      await repo.setScores(playId, const [
        PlayScore(playerName: 'Ana', score: 42, won: true),
        PlayScore(playerName: 'Bia', score: 30),
      ]);

      final placar = await repo.scoresFor(playId);
      expect(placar.length, 2);
      expect(placar.firstWhere((s) => s.playerName == 'Ana').score, 42);
    });

    test('apagar a partida leva o placar junto', () async {
      final id = await repo.insertGame(const Game(name: 'Ark Nova'));
      final playId = await repo.insertPlay(
        Play(gameId: id, playedAt: DateTime(2026, 4, 1)),
      );
      await repo.setScores(playId, const [PlayScore(playerName: 'Ana', score: 10)]);

      await repo.deletePlay(playId);

      // Sem o ON DELETE CASCADE, o placar viraria lixo órfão que reapareceria
      // colado numa partida futura com o mesmo id.
      expect(await repo.scoresFor(playId), isEmpty);
    });

    test('scoresForPlays traz tudo numa consulta só', () async {
      final id = await repo.insertGame(const Game(name: 'Ark Nova'));
      final p1 = await repo.insertPlay(
        Play(gameId: id, playedAt: DateTime(2026, 4, 1)),
      );
      final p2 = await repo.insertPlay(
        Play(gameId: id, playedAt: DateTime(2026, 4, 8)),
      );
      final p3 = await repo.insertPlay(
        Play(gameId: id, playedAt: DateTime(2026, 4, 15)),
      );

      await repo.setScores(p1, const [PlayScore(playerName: 'Ana', score: 10)]);
      await repo.setScores(p2, const [
        PlayScore(playerName: 'Ana', score: 20, won: true),
        PlayScore(playerName: 'Bia', score: 15),
      ]);

      final mapa = await repo.scoresForPlays([p1, p2, p3]);
      expect(mapa[p1]!.length, 1);
      expect(mapa[p2]!.length, 2);
      // Partida sem placar não vem com lista vazia inventada.
      expect(mapa[p3], anyOf(isNull, isEmpty));
    });

    test('sugere os nomes já usados, sem repetir', () async {
      final id = await repo.insertGame(const Game(name: 'Ark Nova'));
      final p1 = await repo.insertPlay(
        Play(gameId: id, playedAt: DateTime(2026, 4, 1)),
      );
      final p2 = await repo.insertPlay(
        Play(gameId: id, playedAt: DateTime(2026, 4, 8)),
      );

      await repo.setScores(p1, const [
        PlayScore(playerName: 'Ana'),
        PlayScore(playerName: 'Bia'),
      ]);
      await repo.setScores(p2, const [PlayScore(playerName: 'Ana')]);

      final nomes = await repo.playerNames();
      expect(nomes, containsAll(['Ana', 'Bia']));
      expect(nomes.where((n) => n == 'Ana').length, 1);
    });

    test('cooperativo: todo mundo pode ter vencido', () async {
      final id = await repo.insertGame(const Game(name: 'Pandemic'));
      final playId = await repo.insertPlay(
        Play(gameId: id, playedAt: DateTime(2026, 4, 1)),
      );

      await repo.setScores(playId, const [
        PlayScore(playerName: 'Ana', won: true),
        PlayScore(playerName: 'Bia', won: true),
      ]);

      final placar = await repo.scoresFor(playId);
      expect(placar.vencedores.length, 2);
      // Sem pontuação nenhuma, não há "maior pontuação" para inventar.
      expect(placar.maiorPontuacao, isNull);
    });

    test('comVencedorPorPontuacao marca o empate inteiro', () {
      const placar = [
        PlayScore(playerName: 'Ana', score: 42),
        PlayScore(playerName: 'Bia', score: 42),
        PlayScore(playerName: 'Cau', score: 30),
      ];

      final marcado = placar.comVencedorPorPontuacao();
      expect(marcado.where((s) => s.won).map((s) => s.playerName),
          containsAll(['Ana', 'Bia']));
      expect(marcado.firstWhere((s) => s.playerName == 'Cau').won, isFalse);
    });
  });
}
