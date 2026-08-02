import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/services/share_service.dart';
import 'package:ludoteca/stats/cost_stats.dart';
import 'package:ludoteca/theme.dart';
import 'package:ludoteca/utils/format.dart';
import 'package:ludoteca/widgets/donut_chart.dart';
import 'package:ludoteca/models/play.dart';
import 'package:ludoteca/widgets/month_bar_chart.dart';
import 'package:ludoteca/widgets/play_bubbles.dart';
import 'package:ludoteca/widgets/play_calendar.dart';
import 'package:ludoteca/widgets/ranked_bar_list.dart';
import 'package:ludoteca/widgets/stat_tile.dart';

/// Teste de fumaça dos gráficos.
///
/// Não testa aparência — testa que eles *renderizam*. Pega três classes de
/// erro que só apareceriam no celular: exceção dentro do CustomPainter, a
/// extensão VizColors ausente no tema (o `context.viz` usa `!`, então falta
/// dela é crash), e overflow de layout (o framework de teste trata overflow
/// como falha).
///
/// Roda nos dois temas porque claro e escuro têm valores de cor próprios, e um
/// deles poderia estar faltando.
Future<void> _renderiza(
  WidgetTester tester,
  Widget filho, {
  Brightness brilho = Brightness.light,
  Size tamanho = const Size(400, 900),
}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brilho),
      home: Scaffold(
        body: SingleChildScrollView(child: filho),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

GameEntry _entry(String nome, {double preco = 100, int partidas = 3}) {
  return GameEntry(
    game: Game(
      id: nome.hashCode.abs(),
      name: nome,
      price: preco,
      minPlaytime: 60,
      maxPlaytime: 90,
      purchaseDate: DateTime(2024, 1, 15),
    ),
    loggedPlays: partidas,
    lastLoggedPlay: DateTime(2025, 6, 1),
  );
}

/// Partidas espalhadas no tempo, para o calendário ter o que desenhar.
List<Play> _partidas() {
  final hoje = DateTime.now();
  return [
    for (final atras in [0, 1, 3, 40, 41, 120, 300])
      for (var n = 0; n < (atras == 1 ? 3 : 1); n++)
        Play(
          gameId: 1,
          playedAt: hoje.subtract(Duration(days: atras)),
        ),
  ];
}

void main() {
  group('bolhas do mês', () {
    /// Partidas de [quantidades] jogos diferentes, todas no mês corrente.
    List<Play> partidasDe(List<int> quantidades) {
      final hoje = DateTime.now();
      final dia = DateTime(hoje.year, hoje.month, 5);
      return [
        for (var g = 0; g < quantidades.length; g++)
          for (var n = 0; n < quantidades[g]; n++)
            Play(gameId: g + 1, playedAt: dia),
      ];
    }

    GameEntry? porId(int id) => GameEntry(
          game: Game(id: id, name: 'Jogo $id'),
          loggedPlays: 1,
        );

    /// Os círculos desenhados, como (centro, raio) na tela.
    List<({Offset centro, double raio})> circulos(WidgetTester tester) {
      return tester
          .widgetList<ClipOval>(find.byType(ClipOval))
          .map((w) => tester.getRect(find.byWidget(w)))
          .map((r) => (centro: r.center, raio: r.width / 2))
          .toList();
    }

    testWidgets('nenhum círculo se sobrepõe a outro', (tester) async {
      // Foi um bug real: quando a espiral não achava lugar, o círculo descia
      // só abaixo do anterior e caía em cima de um terceiro.
      await _renderiza(
        tester,
        PlayBubbles(
          plays: partidasDe([9, 6, 5, 4, 3, 3, 2, 2, 1, 1, 1, 1]),
          entryPorId: porId,
        ),
        tamanho: const Size(393, 1400),
      );

      final cs = circulos(tester);
      expect(cs.length, 12);

      for (var i = 0; i < cs.length; i++) {
        for (var j = i + 1; j < cs.length; j++) {
          final d = (cs[i].centro - cs[j].centro).distance;
          expect(
            d,
            greaterThanOrEqualTo(cs[i].raio + cs[j].raio - 1),
            reason: 'círculos $i e $j se sobrepõem',
          );
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a área é proporcional às partidas', (tester) async {
      // 4 partidas tem de ter o dobro do raio de 1 — quádruplo da área.
      // Raio proporcional à contagem faria 4 parecer 16.
      await _renderiza(
        tester,
        PlayBubbles(plays: partidasDe([4, 1]), entryPorId: porId),
        tamanho: const Size(393, 900),
      );

      final cs = circulos(tester)..sort((a, b) => b.raio.compareTo(a.raio));
      expect(cs.length, 2);
      expect(cs.first.raio / cs[1].raio, closeTo(2.0, 0.15));
    });

    testWidgets('nenhum círculo vaza pelas laterais', (tester) async {
      const largura = 360.0;
      await _renderiza(
        tester,
        PlayBubbles(plays: partidasDe([5, 3, 2, 1, 1]), entryPorId: porId),
        tamanho: const Size(largura, 1000),
      );

      for (final c in circulos(tester)) {
        expect(c.centro.dx - c.raio, greaterThanOrEqualTo(-1));
        expect(c.centro.dx + c.raio, lessThanOrEqualTo(largura + 1));
      }
    });

    testWidgets('com muitos jogos, encolhe para caber', (tester) async {
      // O conjunto tem de caber na tela; com mais jogos os círculos diminuem
      // juntos, preservando a proporção entre eles.
      await _renderiza(
        tester,
        PlayBubbles(
          plays: partidasDe(List.filled(30, 1)),
          entryPorId: porId,
        ),
        tamanho: const Size(393, 1400),
      );

      final cs = circulos(tester);
      expect(cs.length, 30);

      final alturaUsada = cs
          .map((c) => c.centro.dy + c.raio)
          .reduce(math.max);
      // O teto do widget é 460; com folga para a moldura do cartão.
      expect(alturaUsada, lessThan(700));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sem partidas no mês, diz isso em vez de ficar em branco',
        (tester) async {
      await _renderiza(
        tester,
        PlayBubbles(plays: const [], entryPorId: porId),
      );
      expect(find.textContaining('Registre partidas'), findsOneWidget);
    });

    for (final brilho in [Brightness.light, Brightness.dark]) {
      testWidgets('renderiza no tema ${brilho.name}', (tester) async {
        await _renderiza(
          tester,
          PlayBubbles(plays: partidasDe([3, 2, 1]), entryPorId: porId),
          brilho: brilho,
        );
        expect(find.text('O mês em jogos'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('na imagem sai só o mês, o ano e os círculos', (tester) async {
      await _renderiza(
        tester,
        PlayBubbles(
          plays: partidasDe([4, 2]),
          entryPorId: porId,
          modoImagem: true,
        ),
        tamanho: const Size(393, 1200),
      );

      final mes = mesAnoLongo(DateTime.now());
      expect(find.text(mes), findsOneWidget);
      expect(find.byType(ClipOval), findsNWidgets(2));

      // Nome do jogo e contagem de partidas ficam de fora: o círculo já é o
      // jogo, e o tamanho dele já é quantas vezes foi à mesa.
      expect(find.text('Jogo 1'), findsNothing);
      expect(find.text('Jogo 2'), findsNothing);
      expect(find.textContaining('×'), findsNothing);
      expect(find.textContaining('partidas'), findsNothing);
      // Setas de navegação são controle de tela, não de imagem. Elas seguem
      // na árvore para guardar o espaço (senão o título salta de lugar), mas
      // não são pintadas — e o que não é pintado não entra na captura.
      final setas = tester.widgetList<Visibility>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_left),
          matching: find.byType(Visibility),
        ),
      );
      expect(setas, isNotEmpty);
      expect(setas.every((v) => !v.visible), isTrue);
    });

    testWidgets('na tela, nome e contagem continuam aparecendo',
        (tester) async {
      // A legenda sai da imagem, não da tela: sem ela, saber que círculo é
      // qual jogo exigiria tocar em cada um.
      await _renderiza(
        tester,
        PlayBubbles(plays: partidasDe([4, 2]), entryPorId: porId),
        tamanho: const Size(393, 1200),
      );

      expect(find.text('Jogo 1'), findsOneWidget);
      expect(find.textContaining('partidas'), findsWidgets);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    });

    testWidgets('o disco vira uma imagem de verdade', (tester) async {
      // O botão compartilhar manda a imagem, não a lista de nomes. Se a
      // captura falhasse, o app cairia calado no texto e ninguém notaria.
      await _renderiza(
        tester,
        PlayBubbles(plays: partidasDe([4, 2, 1]), entryPorId: porId),
        tamanho: const Size(393, 1200),
      );

      // O boundary do compartilhamento é o único com GlobalKey; o framework
      // insere vários outros por conta própria.
      final quadro = find.descendant(
        of: find.byType(PlayBubbles),
        matching: find.byWidgetPredicate(
          (w) => w is RepaintBoundary && w.key is GlobalKey,
        ),
      );
      expect(quadro, findsOneWidget);
      final chave = tester.widget<RepaintBoundary>(quadro).key! as GlobalKey;

      Uint8List? png;
      // `toImage` precisa do rasterizador de verdade, fora do tempo falso.
      await tester.runAsync(() async {
        png = await capturaPng(chave, escala: 2);
      });

      expect(png, isNotNull);
      // Assinatura do PNG: se vier outra coisa, não é imagem.
      expect(png!.take(4), [0x89, 0x50, 0x4E, 0x47]);
      expect(png!.length, greaterThan(1000));
    });
  });

  group('calendário de partidas', () {
    for (final brilho in [Brightness.light, Brightness.dark]) {
      final modo = brilho == Brightness.light ? 'claro' : 'escuro';

      testWidgets('renderiza no tema $modo', (tester) async {
        await _renderiza(
          tester,
          PlayCalendar(plays: _partidas()),
          brilho: brilho,
        );
        expect(find.text('Quando você jogou'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('sem partidas, explica em vez de desenhar grade vazia',
        (tester) async {
      await _renderiza(tester, const PlayCalendar(plays: []));
      expect(find.textContaining('Registre partidas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cabe numa tela estreita', (tester) async {
      await _renderiza(
        tester,
        PlayCalendar(plays: _partidas()),
        tamanho: const Size(320, 900),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a rampa sequencial tem os quatro passos nos dois temas',
        (tester) async {
      // Uma rampa curta demais faria "muitas partidas" e "poucas" caírem no
      // mesmo tom, e o calendário perderia justamente o que ele mostra.
      for (final brilho in [Brightness.light, Brightness.dark]) {
        final viz = brilho == Brightness.light
            ? VizColors.light
            : VizColors.dark;
        expect(viz.sequential.length, 4, reason: 'tema $brilho');
        expect(viz.sequential.toSet().length, 4,
            reason: 'tons repetidos no tema $brilho');
      }
    });
  });

  for (final brilho in [Brightness.light, Brightness.dark]) {
    final modo = brilho == Brightness.light ? 'claro' : 'escuro';

    group('tema $modo', () {
      testWidgets('o tema traz a extensão VizColors', (tester) async {
        await _renderiza(
          tester,
          Builder(
            builder: (context) {
              // Se a extensão faltar, `context.viz` estoura aqui.
              final viz = context.viz;
              expect(viz.series.length, 8);
              return Text('ok', style: TextStyle(color: viz.inkPrimary));
            },
          ),
          brilho: brilho,
        );
        expect(find.text('ok'), findsOneWidget);
      });

      testWidgets('rosca com 6 fatias renderiza e responde ao toque',
          (tester) async {
        await _renderiza(
          tester,
          const DonutChart(
            title: 'Onde está o dinheiro',
            subtitle: 'teste',
            slices: [
              Slice(label: 'Gloomhaven', value: 700, slot: 0),
              Slice(label: 'Spirit Island', value: 450, slot: 1),
              Slice(label: 'Brass', value: 300, slot: 2),
              Slice(label: 'Wingspan', value: 250, slot: 3),
              Slice(label: 'Azul', value: 180, slot: 4),
              Slice(label: 'Outros 12', value: 900, slot: 5, isOther: true),
            ],
          ),
          brilho: brilho,
        );

        expect(find.text('Gloomhaven'), findsOneWidget);
        expect(find.text('Outros 12'), findsOneWidget);

        // Tocar na legenda seleciona a fatia sem quebrar nada.
        await tester.tap(find.text('Spirit Island'));
        await tester.pumpAndSettle();
      });

      testWidgets('rosca com menos de 3 fatias cai para números soltos',
          (tester) async {
        await _renderiza(
          tester,
          const DonutChart(
            title: 'Em que você gastou',
            slices: [
              Slice(label: 'Caixa do jogo', value: 500, slot: 0),
              Slice(label: 'Sleeves', value: 60, slot: 1),
            ],
          ),
          brilho: brilho,
        );

        expect(find.text('Caixa do jogo'), findsOneWidget);
        expect(find.text('Sleeves'), findsOneWidget);
        // Sem rosca desenhada. O discriminador é o rótulo "total" do centro
        // da rosca, que só existe no caminho do gráfico — procurar por
        // CustomPaint não serve, porque widgets do próprio Flutter
        // (Scrollbar, ripple do InkWell) usam CustomPaint internamente.
        expect(find.text('total'), findsNothing);
      });

      testWidgets('rosca sem valor nenhum mostra aviso, não divide por zero',
          (tester) async {
        await _renderiza(
          tester,
          const DonutChart(title: 'Vazio', slices: []),
          brilho: brilho,
        );
        expect(find.textContaining('Sem valores'), findsOneWidget);
      });

      testWidgets('barras mensais renderizam com meses vazios no meio',
          (tester) async {
        final meses = [
          for (var m = 1; m <= 14; m++)
            MonthSpend(
              month: DateTime(2025, m),
              games: m % 3 == 0 ? 0 : 120.0 * m,
              sleeves: m % 4 == 0 ? 30 : 0,
              accessories: 0,
              itemCount: m % 3 == 0 ? 0 : 1,
            ),
        ];

        await _renderiza(
          tester,
          MonthBarChart(
            title: 'Gasto por mês',
            subtitle: 'teste',
            data: meses,
          ),
          brilho: brilho,
        );

        // O readout abre no mês mais recente da série. São 14 meses a partir
        // de janeiro/2025, e DateTime(2025, 14) normaliza para fevereiro/2026 —
        // é esse que deve aparecer.
        expect(find.textContaining('em fevereiro de 2026'), findsOneWidget);

        // Alternar para a tabela e voltar.
        await tester.tap(find.byTooltip('Ver valores em tabela'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Ver gráfico'));
        await tester.pumpAndSettle();
      });

      testWidgets('barras mensais sem dados avisam em vez de quebrar',
          (tester) async {
        await _renderiza(
          tester,
          const MonthBarChart(title: 'Gasto por mês', data: []),
          brilho: brilho,
        );
        expect(find.textContaining('data de compra'), findsOneWidget);
      });

      testWidgets('ranking horizontal renderiza com rótulo em toda linha',
          (tester) async {
        final itens = [
          RankedGame(entry: _entry('Gloomhaven'), value: 12.5, detail: 'a'),
          RankedGame(entry: _entry('Azul'), value: 3.2, detail: 'b'),
          RankedGame(entry: _entry('Root'), value: 0.8, detail: 'c'),
        ];

        await _renderiza(
          tester,
          RankedBarList(
            title: 'Custo por hora',
            items: itens,
            format: (v) => '${dinheiro(v)}/h',
          ),
          brilho: brilho,
        );

        expect(find.text('Gloomhaven'), findsOneWidget);
        expect(find.text(r'R$ 12,50/h'), findsOneWidget);
        expect(find.text(r'R$ 0,80/h'), findsOneWidget);
      });

      testWidgets('ranking vazio mostra a mensagem de vazio', (tester) async {
        await _renderiza(
          tester,
          RankedBarList(
            title: 'Custo por hora',
            items: const [],
            format: (v) => '$v',
            emptyMessage: 'Nada aqui ainda.',
          ),
          brilho: brilho,
        );
        expect(find.text('Nada aqui ainda.'), findsOneWidget);
      });

      testWidgets('grade de stat tiles se ajusta a tela estreita',
          (tester) async {
        await _renderiza(
          tester,
          const StatTileGrid(
            tiles: [
              StatTile(label: 'TOTAL INVESTIDO', value: r'R$ 12.480', hint: '56 jogos'),
              StatTile(label: 'CUSTO POR HORA', value: r'≈ R$ 8,40', hint: '1h15 por partida'),
              StatTile(label: 'HORAS DE MESA', value: '≈ 214 h', hint: '0% cronometrado'),
              StatTile(label: 'NUNCA JOGADOS', value: '7', hint: r'R$ 1.900 parados'),
            ],
          ),
          brilho: brilho,
          // Tela estreita de propósito: é onde stat tile costuma estourar.
          tamanho: const Size(320, 900),
        );

        expect(find.text('TOTAL INVESTIDO'), findsOneWidget);
        expect(find.text('≈ 214 h'), findsOneWidget);
      });
    });
  }

  testWidgets('a pizza pinta as fatias na ordem fixa dos slots',
      (tester) async {
    // A cor precisa seguir o slot gravado na fatia, não a posição na lista:
    // filtrar não deve repintar quem sobrou.
    late VizColors viz;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              viz = context.viz;
              return const SingleChildScrollView(
                child: DonutChart(
                  title: 'x',
                  slices: [
                    // Slots fora de ordem de propósito.
                    Slice(label: 'A', value: 10, slot: 3),
                    Slice(label: 'B', value: 20, slot: 0),
                    Slice(label: 'C', value: 30, slot: 5),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // As três legendas usam a cor do slot declarado.
    final marcas = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration)
        .map((c) => (c.decoration as BoxDecoration).color)
        .whereType<Color>()
        .toList();

    expect(marcas, contains(viz.serie(3)));
    expect(marcas, contains(viz.serie(0)));
    expect(marcas, contains(viz.serie(5)));
  });
}
