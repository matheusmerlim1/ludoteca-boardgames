import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludoteca/data/database.dart';
import 'package:ludoteca/data/game_repository.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/models/play.dart';
import 'package:ludoteca/models/play_score.dart';
import 'package:ludoteca/screens/collection_screen.dart';
import 'package:ludoteca/screens/costs_screen.dart';
import 'package:ludoteca/screens/game_detail_screen.dart';
import 'package:ludoteca/screens/settings_screen.dart';
import 'package:ludoteca/services/share_service.dart';
import 'package:ludoteca/state/collection_store.dart';
import 'package:ludoteca/widgets/game_card.dart';
import 'package:ludoteca/widgets/pick_game_sheet.dart';
import 'package:ludoteca/theme.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Testes de renderização das telas, contra um banco de verdade.
///
/// O que eles pegam é o que só apareceria no celular: overflow de layout (o
/// framework de teste trata como falha), exceção dentro de um CustomPainter, e
/// `context.viz` estourando por falta da extensão de tema.
///
/// Rodam nos dois temas e com a coleção vazia e cheia, porque estado vazio é
/// onde mais aparece layout quebrado — e é o primeiro estado que o usuário vê.
///
/// Os jogos de teste vão **sem URL de imagem** de propósito: em teste não há
/// rede, e o objetivo aqui é o layout, não o carregamento de capa.
///
/// ⚠️ Todo I/O real (criar diretório, abrir o banco) roda dentro de
/// `tester.runAsync`. `testWidgets` executa numa zona de tempo falso onde
/// futures de `dart:io` **nunca completam** — sem o `runAsync` o teste trava
/// para sempre, sem erro e sem timeout. Só o `pump` fica fora dele.

late Directory _temp;
late AppDatabase _db;
late CollectionStore _store;

Future<void> _montaStore(
  WidgetTester tester, {
  bool comDados = false,
  String? token,
  bool comAcento = false,
}) async {
  await tester.runAsync(
    () => _montaStoreReal(
      comDados: comDados,
      token: token,
      comAcento: comAcento,
    ),
  );
  // Emparelhado com o setup, para a limpeza acontecer mesmo se o teste falhar.
  addTearDown(() => _limpa(tester));
}

Future<void> _montaStoreReal({
  bool comDados = false,
  String? token,
  bool comAcento = false,
}) async {
  _temp = await Directory.systemTemp.createTemp('ludoteca_screens');
  _db = AppDatabase.paraArquivo('${_temp.path}/t.db');
  final repo = GameRepository(database: _db);

  if (comDados) {
    final base = await repo.insertGame(Game(
      name: 'Gloomhaven',
      namePt: 'Gloomhaven',
      minPlayers: 1,
      maxPlayers: 4,
      bestPlayers: 3,
      minPlaytime: 60,
      maxPlaytime: 120,
      weight: 3.9,
      price: 899.90,
      sleeveCost: 120,
      accessoryCost: 80,
      purchaseDate: DateTime(2023, 5, 10),
      manualPlayCount: 4,
      manualLastPlayed: DateTime(2025, 2, 1),
    ));

    await repo.insertGame(Game(
      name: 'Gloomhaven: Forgotten Circles',
      linkKind: LinkKind.expansao,
      parentId: base,
      price: 180,
      purchaseDate: DateTime(2024, 1, 20),
    ));

    await repo.insertGame(Game(
      name: 'Wingspan',
      minPlayers: 1,
      maxPlayers: 5,
      minPlaytime: 40,
      maxPlaytime: 70,
      price: 320,
      purchaseDate: DateTime(2024, 8, 3),
    ));

    // Vendido: entra no gasto histórico, sai do investimento atual.
    await repo.insertGame(Game(
      name: 'Scythe',
      minPlayers: 1,
      maxPlayers: 5,
      price: 450,
      purchaseDate: DateTime(2022, 11, 2),
      sold: true,
      soldPrice: 300,
      soldDate: DateTime(2025, 3, 1),
    ));

    await repo.insertPlay(Play(
      gameId: base,
      playedAt: DateTime(2025, 6, 12),
      players: 3,
      durationMinutes: 145,
    ));
    await repo.insertPlay(Play(
      gameId: base,
      playedAt: DateTime(2025, 7, 2),
      players: 2,
    ));
  }

  if (comAcento) {
    // Nome com acento e pontuação, para exercitar a busca branda.
    await repo.insertGame(const Game(
      name: 'Caçadores da Galáxia',
      minPlayers: 2,
      maxPlayers: 4,
      price: 250,
    ));
  }

  if (token != null) {
    await repo.setSetting(GameRepository.keyBggToken, token);
  }

  _store = CollectionStore(repository: repo);
  await _store.load();
}

/// Fecha o banco e apaga o temporário. Também precisa de `runAsync`.
Future<void> _limpa(WidgetTester tester) async {
  await tester.runAsync(() async {
    await _db.close();
    if (await _temp.exists()) await _temp.delete(recursive: true);
  });
}

/// Abre o painel de filtros, que agora começa fechado.
Future<void> _abreFiltros(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.filter_list));
  await tester.pumpAndSettle();
}

/// Troca para a aba de Custos com o rótulo dado.
Future<void> _vaiParaAba(WidgetTester tester, String rotulo) async {
  await tester.tap(find.widgetWithText(Tab, rotulo));
  await tester.pumpAndSettle();
}

Future<void> _renderiza(
  WidgetTester tester,
  Widget tela, {
  required Brightness brilho,
  Size tamanho = const Size(400, 900),
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<CollectionStore>.value(
      value: _store,
      child: MaterialApp(theme: buildTheme(brilho), home: tela),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  for (final brilho in [Brightness.light, Brightness.dark]) {
    final modo = brilho == Brightness.light ? 'claro' : 'escuro';

    group('tema $modo', () {
      testWidgets('Ajustes renderiza sem token configurado', (tester) async {
        await _montaStore(tester);
        await _renderiza(tester, const SettingsScreen(), brilho: brilho);

        expect(find.text('Token do BGG'), findsOneWidget);
        expect(find.text('não configurado'), findsOneWidget);
        expect(find.text('Backup'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Ajustes renderiza com token configurado', (tester) async {
        await _montaStore(tester, token: 'tok_de_teste');
        await _renderiza(tester, const SettingsScreen(), brilho: brilho);

        expect(find.text('configurado'), findsOneWidget);
        // Com token, aparece também o botão de remover.
        expect(find.text('Remover'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Coleção vazia mostra o estado inicial', (tester) async {
        await _montaStore(tester);
        await _renderiza(tester, const CollectionScreen(), brilho: brilho);

        expect(find.text('Sua estante está vazia'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Coleção com jogos lista os jogos-base', (tester) async {
        await _montaStore(tester, comDados: true);
        await _renderiza(tester, const CollectionScreen(), brilho: brilho);

        expect(find.text('Gloomhaven'), findsOneWidget);
        expect(find.text('Wingspan'), findsOneWidget);
        // Expansão e vendido ficam fora da lista por padrão.
        expect(find.text('Gloomhaven: Forgotten Circles'), findsNothing);
        expect(find.text('Scythe'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Custos sem dados não quebra', (tester) async {
        await _montaStore(tester);
        await _renderiza(tester, const CostsScreen(), brilho: brilho);

        expect(find.text('Nada para somar ainda'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Custos com dados desenha todos os gráficos', (tester) async {
        await _montaStore(tester, comDados: true);

        // Viewport alta: cada aba é uma ListView que constrói sob demanda, e
        // o objetivo é forçar todos os cartões dela a renderizar. Rolar até
        // cada um seria frágil — há scroll horizontal aninhado (barras
        // mensais, calendário), e o `scrollable:` acaba pegando o errado.
        await _renderiza(
          tester,
          const CostsScreen(),
          brilho: brilho,
          tamanho: const Size(400, 2400),
        );

        // Cada aba responde uma pergunta; o teste passa por todas para nenhum
        // cartão ficar sem nunca ter renderizado.
        expect(find.text('Quando você jogou'), findsOneWidget);

        await _vaiParaAba(tester, 'Mês');
        expect(find.text('O mês em jogos'), findsOneWidget);

        await _vaiParaAba(tester, 'Dinheiro');
        expect(find.text('Onde está o seu dinheiro'), findsOneWidget);
        expect(find.text('Quem puxa o custo por mês'), findsOneWidget);
        expect(find.text('Em que você gastou'), findsOneWidget);
        expect(find.text('Quanto você gastou por mês'), findsOneWidget);

        await _vaiParaAba(tester, 'Vale a pena?');
        expect(find.text('Custo de posse por mês'), findsOneWidget);
        expect(find.text('Custo por hora de jogo'), findsOneWidget);

        await _vaiParaAba(tester, 'Tempo');
        expect(find.text('Os mais jogados'), findsOneWidget);
        expect(find.text('Mais horas de mesa'), findsOneWidget);

        expect(tester.takeException(), isNull);
      });
    });
  }

  group('interação', () {
    /// Abre o painel (que começa fechado) e toca no chip.
    Future<void> tocaChip(WidgetTester tester, String rotulo) async {
      if (find.byIcon(Icons.filter_list).evaluate().isNotEmpty) {
        await _abreFiltros(tester);
      }
      final chip = find.widgetWithText(FilterChip, rotulo);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    testWidgets('filtrar por nº de jogadores recorta a lista', (tester) async {
      await _montaStore(tester, comDados: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      // Wingspan vai até 5; Gloomhaven até 4. Filtrando por 5, só um sobra.
      await tocaChip(tester, '5');

      expect(find.text('Wingspan'), findsOneWidget);
      expect(find.text('Gloomhaven'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mostrar vendidos traz o jogo vendido de volta', (tester) async {
      await _montaStore(tester, comDados: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      expect(find.text('Scythe'), findsNothing);

      await tocaChip(tester, 'Vendidos');

      expect(find.text('Scythe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('filtro sem resultado explica o porquê', (tester) async {
      await _montaStore(tester, comDados: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      // Nenhum jogo da amostra serve para 8 jogadores.
      await tocaChip(tester, '8');

      expect(find.text('Nenhum jogo com esses filtros'), findsOneWidget);
      expect(find.text('Limpar filtros'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('os dois botões', () {
    testWidgets('a coleção mostra "Jogo" e "Partida"', (tester) async {
      await _montaStore(tester, comDados: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      expect(find.widgetWithText(FloatingActionButton, 'Jogo'), findsOneWidget);
      expect(
        find.widgetWithText(FloatingActionButton, 'Partida'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Partida" abre a escolha de jogo, sem passar pela ficha',
        (tester) async {
      await _montaStore(tester, comDados: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Partida'));
      await tester.pumpAndSettle();

      expect(find.text('Qual jogo você jogou?'), findsOneWidget);

      // Restrito à folha: a lista da coleção continua montada atrás dela, e
      // sem o escopo os mesmos nomes apareceriam duas vezes.
      Finder naFolha(String texto) => find.descendant(
            of: find.byType(PickGameSheet),
            matching: find.text(texto),
          );

      // Vendido e desejado não vão à mesa, então ficam fora da escolha.
      expect(naFolha('Scythe'), findsNothing);
      expect(naFolha('Gloomhaven'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a escolha oferece o jogo que não é seu', (tester) async {
      // Jogo de outra pessoa quase nunca está cadastrado; sem esta saída o
      // fluxo obrigaria a sair, cadastrar e voltar.
      await _montaStore(tester, comDados: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Partida'));
      await tester.pumpAndSettle();

      expect(find.text('Joguei um jogo que não é meu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a escolha ordena por jogado recentemente', (tester) async {
      // Quem acabou de jogar algo tende a jogar de novo; o alfabeto não
      // ajudaria nesse momento.
      await _montaStore(tester, comDados: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Partida'));
      await tester.pumpAndSettle();

      Finder naFolha(String texto) => find.descendant(
            of: find.byType(PickGameSheet),
            matching: find.text(texto),
          );

      // Gloomhaven tem partidas; Wingspan nunca foi jogado.
      final gloom = tester.getTopLeft(naFolha('Gloomhaven')).dy;
      final wing = tester.getTopLeft(naFolha('Wingspan')).dy;
      expect(gloom, lessThan(wing));
    });
  });

  group('painel de filtros recolhido', () {
    testWidgets('começa fechado, dando a tela para a lista de jogos',
        (tester) async {
      await _montaStore(tester, comDados: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      // Os chips não existem antes de abrir.
      expect(find.widgetWithText(FilterChip, 'Vendidos'), findsNothing);
      // Mas a lista de jogos, sim.
      expect(find.text('Gloomhaven'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('o botão abre e fecha', (tester) async {
      await _montaStore(tester, comDados: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      await _abreFiltros(tester);
      expect(find.widgetWithText(FilterChip, 'Vendidos'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.filter_list_off));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'Vendidos'), findsNothing);
    });

    testWidgets('fechado, o filtro ativo continua visível e removível',
        (tester) async {
      // Sem isso, uma lista curta por causa de um filtro esquecido pareceria
      // bug — o usuário não teria como saber o que está filtrando.
      await _montaStore(tester, comDados: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      await _abreFiltros(tester);
      await tester.tap(find.widgetWithText(FilterChip, '5'));
      await tester.pumpAndSettle();

      // Fecha o painel: o resumo assume.
      await tester.tap(find.byIcon(Icons.filter_list_off));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, '5 jogadores'), findsOneWidget);
      expect(find.text('Wingspan'), findsOneWidget);
      expect(find.text('Gloomhaven'), findsNothing);

      // O X do chip desfaz o filtro sem precisar reabrir o painel.
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();

      expect(find.text('Gloomhaven'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('descoberta dos filtros', () {
    // Regressão de um bug real: os chips ficavam numa faixa de rolagem
    // horizontal, e num celular comum "8 jogadores" e "Vendidos" caíam fora da
    // tela. O filtro existia e ninguém achava. Aqui eles são tocados **sem**
    // ensureVisible: se voltarem a sair da tela, o teste falha.
    for (final largura in [360.0, 393.0, 411.0]) {
      testWidgets('todos os chips ficam na tela em ${largura.toInt()}dp',
          (tester) async {
        await _montaStore(tester, comDados: true);
        await _renderiza(
          tester,
          const CollectionScreen(),
          brilho: Brightness.light,
          tamanho: Size(largura, 900),
        );
        await _abreFiltros(tester);

        for (final rotulo in [
          'Todos', '1', '4', '8',
          'Mais tempo parados', 'Jogados por último',
          'Nunca jogados', 'Itens agrupados', 'Vendidos',
        ]) {
          final chip = find.widgetWithText(FilterChip, rotulo);
          expect(chip, findsOneWidget, reason: 'chip "$rotulo" sumiu');

          final caixa = tester.getRect(chip);
          expect(caixa.right, lessThanOrEqualTo(largura),
              reason: 'chip "$rotulo" passa da borda direita');
          expect(caixa.left, greaterThanOrEqualTo(0.0),
              reason: 'chip "$rotulo" começa fora da tela');
        }

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('dá para tocar em "Vendidos" sem rolar nada', (tester) async {
      await _montaStore(tester, comDados: true);
      await _renderiza(
        tester,
        const CollectionScreen(),
        brilho: Brightness.light,
        tamanho: const Size(393, 900),
      );
      await _abreFiltros(tester);

      // Sem ensureVisible de propósito: é isso que falhava antes.
      await tester.tap(find.widgetWithText(FilterChip, 'Vendidos'));
      await tester.pumpAndSettle();

      expect(find.text('Scythe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('busca branda na coleção', () {
    Future<void> digita(WidgetTester tester, String termo) async {
      await tester.enterText(find.byType(TextField).first, termo);
      await tester.pumpAndSettle();
    }

    testWidgets('acha sem acento o que está gravado com acento',
        (tester) async {
      await _montaStore(tester, comDados: true, comAcento: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      await digita(tester, 'cacadores');

      expect(find.text('Caçadores da Galáxia'), findsOneWidget);
      expect(find.text('Wingspan'), findsNothing);
    });

    testWidgets('acha com acento o que está gravado com acento',
        (tester) async {
      await _montaStore(tester, comDados: true, comAcento: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      await digita(tester, 'galáxia');

      expect(find.text('Caçadores da Galáxia'), findsOneWidget);
    });

    testWidgets('ordem das palavras não importa', (tester) async {
      await _montaStore(tester, comDados: true, comAcento: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      await digita(tester, 'galaxia cacadores');

      expect(find.text('Caçadores da Galáxia'), findsOneWidget);
    });

    testWidgets('pontuação digitada não atrapalha', (tester) async {
      await _montaStore(tester, comDados: true, comAcento: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      await digita(tester, 'caçadores:  da   galáxia!');

      expect(find.text('Caçadores da Galáxia'), findsOneWidget);
    });

    testWidgets('termo que não existe some com tudo', (tester) async {
      await _montaStore(tester, comDados: true, comAcento: true);
      await _renderiza(tester, const CollectionScreen(),
          brilho: Brightness.light);

      await digita(tester, 'xadrez');

      expect(find.text('Nenhum jogo com esses filtros'), findsOneWidget);
    });
  });

  group('tela estreita', () {
    // Um aparelho pequeno é onde o layout estoura primeiro.
    testWidgets('Custos cabe em 320 de largura', (tester) async {
      await _montaStore(tester, comDados: true);
      await _renderiza(
        tester,
        const CostsScreen(),
        brilho: Brightness.light,
        tamanho: const Size(320, 900),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ajustes cabe em 320 de largura', (tester) async {
      await _montaStore(tester, token: 'tok');
      await _renderiza(
        tester,
        const SettingsScreen(),
        brilho: Brightness.light,
        tamanho: const Size(320, 900),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('rankings de custo', () {
    /// Doze jogos com preço e partidas, para o ranking passar das 8 linhas.
    Future<void> abreValeAPena(WidgetTester tester) async {
      await tester.runAsync(() async {
        _temp = await Directory.systemTemp.createTemp('ludoteca_ranking');
        _db = AppDatabase.paraArquivo('${_temp.path}/t.db');
        final repo = GameRepository(database: _db);

        for (var i = 1; i <= 12; i++) {
          final id = await repo.insertGame(
            Game(name: 'Jogo $i', price: 100.0 * i),
          );
          await repo.insertPlay(
            Play(gameId: id, playedAt: DateTime(2026, 4, 10)),
          );
        }

        _store = CollectionStore(repository: repo);
        await _store.load();
      });
      addTearDown(() => _limpa(tester));

      await _renderiza(
        tester,
        const CostsScreen(),
        brilho: Brightness.light,
        // Largo o bastante para a faixa de abas caber inteira: aqui o alvo é o
        // ranking, e o teste de tela estreita já existe à parte.
        tamanho: const Size(900, 2200),
      );
      await _vaiParaAba(tester, 'Vale a pena?');
    }

    testWidgets('mostra 8 linhas e oferece ver todas', (tester) async {
      await abreValeAPena(tester);

      // O topo do ranking aparece; o fim fica atrás do botão.
      expect(find.text('Jogo 12'), findsOneWidget);
      expect(find.text('Jogo 1'), findsNothing);
      expect(find.text('Ver todos os 12'), findsWidgets);
    });

    testWidgets('"ver todos" traz o resto da lista', (tester) async {
      await abreValeAPena(tester);

      await tester.tap(find.text('Ver todos os 12').first);
      await tester.pumpAndSettle();

      expect(find.text('Jogo 1'), findsOneWidget);
      expect(find.text('Mostrar menos'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"mostrar menos" recolhe de volta', (tester) async {
      await abreValeAPena(tester);

      await tester.tap(find.text('Ver todos os 12').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mostrar menos').first);
      await tester.pumpAndSettle();

      expect(find.text('Jogo 1'), findsNothing);
    });

    testWidgets('sem régua, nenhum jogo é marcado como fora', (tester) async {
      await abreValeAPena(tester);
      // A faixa da régua só existe quando você escolheu uma.
      expect(find.textContaining('de 12'), findsNothing);
    });

    testWidgets('com régua, a faixa diz quantos passam', (tester) async {
      await abreValeAPena(tester);

      // 12 jogos de R$ 100 a R$ 1200, uma partida cada: com a régua em
      // R$ 500 por partida, só os cinco primeiros passam.
      await tester.runAsync(
        () => _store.setMeta(GameRepository.keyMetaPorPartida, 500),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('R\$ 500,00 por partida'), findsOneWidget);
      expect(find.text('5 de 12'), findsOneWidget);
    });
  });

  group('do número para a lista', () {
    testWidgets('"Nunca jogados" leva à coleção já filtrada', (tester) async {
      await _montaStore(tester, comDados: true);

      var foiParaColecao = false;
      await _renderiza(
        tester,
        CostsScreen(onVerColecao: () => foiParaColecao = true),
        brilho: Brightness.light,
        tamanho: const Size(400, 1400),
      );

      await tester.tap(find.text('NUNCA JOGADOS'));
      await tester.pumpAndSettle();

      expect(foiParaColecao, isTrue);
      // Ler "quantos" e não conseguir ver "quais" era o beco sem saída.
      expect(_store.onlyNeverPlayed, isTrue);
    });
  });

  group('tempo sem jogar', () {
    /// Três jogos com datas diferentes de última partida.
    ///
    /// O conjunto padrão não serve: nele só um jogo tem partida, e as duas
    /// ordens dariam o mesmo resultado — o teste passaria sem provar nada.
    Future<void> abreOPainel(WidgetTester tester) async {
      await tester.runAsync(() async {
        _temp = await Directory.systemTemp.createTemp('ludoteca_parados');
        _db = AppDatabase.paraArquivo('${_temp.path}/t.db');
        final repo = GameRepository(database: _db);

        final antigo = await repo.insertGame(const Game(name: 'Antigo'));
        final recente = await repo.insertGame(const Game(name: 'Recente'));
        await repo.insertGame(const Game(name: 'Nunca'));

        await repo.insertPlay(
          Play(gameId: antigo, playedAt: DateTime(2024, 1, 10)),
        );
        await repo.insertPlay(
          Play(gameId: recente, playedAt: DateTime(2026, 6, 20)),
        );

        _store = CollectionStore(repository: repo);
        await _store.load();
      });
      addTearDown(() => _limpa(tester));

      await _renderiza(
        tester,
        const CollectionScreen(),
        brilho: Brightness.light,
      );
      await _abreFiltros(tester);
    }

    /// Os nomes dos jogos na ordem em que aparecem na lista.
    List<String> nomesNaTela(WidgetTester tester) => tester
        .widgetList<GameCard>(find.byType(GameCard))
        .map((c) => c.entry.displayName)
        .toList();

    testWidgets('"Mais tempo parados" traz o esquecido primeiro',
        (tester) async {
      await abreOPainel(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Mais tempo parados'));
      await tester.pumpAndSettle();

      final nomes = nomesNaTela(tester);
      expect(nomes.indexOf('Antigo'), lessThan(nomes.indexOf('Recente')));

      // Nunca jogado vai para o fim nas **duas** direções: sem data, ele não é
      // o mais recente nem o mais antigo — é desconhecido. Quem quer esses tem
      // o filtro "Nunca jogados".
      expect(nomes.last, 'Nunca');
    });

    testWidgets('"Jogados por último" inverte', (tester) async {
      await abreOPainel(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Jogados por último'));
      await tester.pumpAndSettle();

      final nomes = nomesNaTela(tester);
      expect(nomes.indexOf('Recente'), lessThan(nomes.indexOf('Antigo')));
      expect(nomes.last, 'Nunca');
    });

    testWidgets('as duas se excluem — tocar numa desliga a outra',
        (tester) async {
      await abreOPainel(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Mais tempo parados'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Jogados por último'));
      await tester.pumpAndSettle();

      final store = _store;
      expect(store.sort, SortKey.jogadosRecentemente);
    });

    testWidgets('tocar de novo volta para a ordem alfabética', (tester) async {
      await abreOPainel(tester);
      final chip = find.widgetWithText(FilterChip, 'Mais tempo parados');

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(_store.sort, SortKey.esquecidos);

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(_store.sort, SortKey.nome);
    });

    testWidgets('com o painel fechado, a ordem escolhida continua visível',
        (tester) async {
      // Lista fora de ordem alfabética e sem explicação parece defeito.
      await abreOPainel(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Mais tempo parados'));
      await tester.pumpAndSettle();

      // O ícone troca quando o painel está aberto.
      await tester.tap(find.byIcon(Icons.filter_list_off));
      await tester.pumpAndSettle();

      expect(find.textContaining('há mais tempo sem jogar'), findsOneWidget);
    });
  });

  group('compartilhar o que está filtrado', () {
    const servico = ShareService();

    testWidgets('sem filtro, vai a coleção inteira e sem rótulo',
        (tester) async {
      await _montaStore(tester, comDados: true);

      final texto = servico.textoDaColecao(
        _store.filteredEntries,
        filtro: _store.filtroDescrito,
      );

      expect(_store.filtroDescrito, isNull);
      expect(texto, contains('Gloomhaven'));
      expect(texto, contains('Wingspan'));
      // O padrão da tela já esconde vendidos e agrupados; o texto acompanha.
      expect(texto, isNot(contains('Scythe')));
      expect(texto, isNot(contains('Forgotten Circles')));
    });

    testWidgets('filtrando por jogadores, vai só o que sobrou', (tester) async {
      await _montaStore(tester, comDados: true);

      // Wingspan é 1–5; Gloomhaven é 1–4.
      _store.setPlayerCount(5);

      final texto = servico.textoDaColecao(
        _store.filteredEntries,
        filtro: _store.filtroDescrito,
      );

      expect(texto, contains('Wingspan'));
      expect(texto, isNot(contains('Gloomhaven')));
      expect(texto, contains('para 5 jogadores'));
      expect(texto, contains('1 jogo'));
    });

    testWidgets('a busca digitada também vai no rótulo', (tester) async {
      await _montaStore(tester, comDados: true);
      _store.setQuery('wing');

      expect(_store.filtroDescrito, contains('wing'));
      expect(
        servico.textoDaColecao(
          _store.filteredEntries,
          filtro: _store.filtroDescrito,
        ),
        contains('Wingspan'),
      );
    });

    testWidgets('com "Vendidos" ligado, o vendido vai — e o rótulo avisa',
        (tester) async {
      await _montaStore(tester, comDados: true);
      _store.setShowSold(true);

      final texto = servico.textoDaColecao(
        _store.filteredEntries,
        filtro: _store.filtroDescrito,
      );

      // Você pediu para ver os vendidos; mandar sem eles seria desobedecer o
      // filtro. O rótulo é o que impede a lista de enganar quem recebe.
      expect(texto, contains('Scythe'));
      expect(texto, contains('com vendidos'));
    });
  });

  group('placar na ficha do jogo', () {
    /// Cadastra um jogo com uma partida pontuada e devolve o id do jogo.
    Future<int> comPlacar(WidgetTester tester) async {
      late int gameId;
      await tester.runAsync(() async {
        _temp = await Directory.systemTemp.createTemp('ludoteca_placar');
        _db = AppDatabase.paraArquivo('${_temp.path}/t.db');
        final repo = GameRepository(database: _db);

        gameId = await repo.insertGame(const Game(name: 'Ark Nova', price: 500));
        final playId = await repo.insertPlay(
          Play(gameId: gameId, playedAt: DateTime(2026, 4, 12)),
        );
        await repo.setScores(playId, const [
          PlayScore(playerName: 'Ana', score: 98),
          PlayScore(playerName: 'Matheus', score: 112, won: true),
        ]);

        _store = CollectionStore(repository: repo);
        await _store.load();
      });
      addTearDown(() => _limpa(tester));
      return gameId;
    }

    /// Abre a ficha e espera o histórico chegar do banco.
    ///
    /// O `pumpWidget` precisa acontecer **dentro** do `runAsync`: a ficha
    /// dispara a consulta no `initState`, e um future de banco criado na zona
    /// de tempo falso nunca completa — a tela ficaria carregando para sempre.
    ///
    /// A altura é generosa de propósito: a lista é preguiçosa e o Histórico
    /// fica lá no fim da rolagem.
    Future<void> abre(WidgetTester tester, int id) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          ChangeNotifierProvider<CollectionStore>.value(
            value: _store,
            child: MaterialApp(
              theme: buildTheme(Brightness.light),
              home: GameDetailScreen(gameId: id),
            ),
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('mostra quem jogou, os pontos e quem ganhou', (tester) async {
      await abre(tester, await comPlacar(tester));

      expect(find.text('Matheus'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      // Pontuação inteira não vira "112,0".
      expect(find.text('112'), findsOneWidget);
      expect(find.text('98'), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a contagem de jogadores vem do placar', (tester) async {
      await abre(tester, await comPlacar(tester));

      // A partida foi gravada sem o campo "players"; quem sabe quantos jogaram
      // é o placar.
      expect(find.textContaining('2 jogadores'), findsOneWidget);
    });
  });
}
