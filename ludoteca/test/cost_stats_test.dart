import 'package:flutter_test/flutter_test.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/stats/cost_stats.dart';
import 'package:ludoteca/utils/format.dart';

/// Constrói um jogo com o mínimo necessário para o teste em questão.
Game _jogo({
  required int id,
  String name = 'Jogo',
  double price = 0,
  double sleeveCost = 0,
  double accessoryCost = 0,
  DateTime? purchaseDate,
  int manualPlayCount = 0,
  LinkKind? linkKind,
  int? parentId,
  bool sold = false,
  double? soldPrice,
}) {
  return Game(
    id: id,
    name: name,
    price: price,
    sleeveCost: sleeveCost,
    accessoryCost: accessoryCost,
    purchaseDate: purchaseDate,
    manualPlayCount: manualPlayCount,
    linkKind: linkKind,
    parentId: parentId,
    sold: sold,
    soldPrice: soldPrice,
  );
}

GameEntry _entrada(
  Game g, {
  int loggedPlays = 0,
  DateTime? lastLoggedPlay,
  int expansionCount = 0,
  double expansionCost = 0,
  int loggedPlaysWithDuration = 0,
  int loggedMinutes = 0,
}) {
  return GameEntry(
    game: g,
    loggedPlays: loggedPlays,
    lastLoggedPlay: lastLoggedPlay,
    expansionCount: expansionCount,
    expansionCost: expansionCost,
    loggedPlaysWithDuration: loggedPlaysWithDuration,
    loggedMinutes: loggedMinutes,
  );
}

void _grupoDatas() {
  group('custo por mês sem data de compra', () {
    test('coleção inteira sem data: desconhecido, não zero', () {
      // Era o que aparecia na tela: "R$ 0 por mês", que lido de boa-fé quer
      // dizer "minha coleção não me custa nada" — o oposto do que a tela toda
      // existe para responder.
      final s = CostStats.compute(entries: [
        _entrada(const Game(id: 1, name: 'Sem data', price: 500)),
        _entrada(const Game(id: 2, name: 'Tambem sem', price: 300)),
      ]);

      expect(s.monthlyCostIsUnknown, isTrue);
      expect(s.datedGameCount, 0);
      expect(s.undatedGameCount, 2);
      expect(s.totalInvested, 800);
    });

    test('só os que têm data entram na conta, e o resto é contado', () {
      final s = CostStats.compute(entries: [
        _entrada(_jogo(
          id: 1,
          name: 'Com data',
          price: 600,
          purchaseDate: DateTime.now().subtract(const Duration(days: 365)),
        )),
        _entrada(const Game(id: 2, name: 'Sem data', price: 300)),
      ]);

      expect(s.monthlyCostIsUnknown, isFalse);
      expect(s.datedGameCount, 1);
      expect(s.undatedGameCount, 1);
      // 600 em ~12 meses. Nada do jogo sem data entra aqui.
      expect(s.monthlyOwnershipCost, closeTo(50, 5));
    });
  });

  group('rankings vêm inteiros', () {
    test('não são cortados no top 8 — quem corta é a tela', () {
      final entries = [
        for (var i = 1; i <= 15; i++)
          _entrada(
            Game(id: i, name: 'Jogo $i', price: 100.0 * i),
            loggedPlays: 2,
          ),
      ];

      final s = CostStats.compute(entries: entries);

      expect(s.priciestPerPlay.length, 15);
      expect(s.cheapestPerPlay.length, 15);
      expect(s.mostPlayed.length, 15);
    });
  });
}

void main() {
  _grupoDatas();

  group('GameEntry', () {
    test('soma o histórico da planilha com as partidas registradas', () {
      final e = _entrada(
        _jogo(id: 1, manualPlayCount: 10),
        loggedPlays: 3,
      );
      expect(e.playCount, 13);
    });

    test('última partida é a mais recente entre manual e registrada', () {
      final antiga = DateTime(2024, 1, 10);
      final nova = DateTime(2025, 6, 1);

      final manualMaisNovo = _entrada(
        Game(id: 1, name: 'X', manualLastPlayed: nova),
        lastLoggedPlay: antiga,
      );
      expect(manualMaisNovo.lastPlayed, nova);

      final registradaMaisNova = _entrada(
        Game(id: 1, name: 'X', manualLastPlayed: antiga),
        lastLoggedPlay: nova,
      );
      expect(registradaMaisNova.lastPlayed, nova);
    });

    test('custo por partida é nulo, não infinito, sem partida jogada', () {
      final e = _entrada(_jogo(id: 1, price: 300));
      expect(e.playCount, 0);
      expect(e.costPerPlay, isNull);
    });

    test('custo por partida divide o investimento total', () {
      final e = _entrada(
        _jogo(id: 1, price: 300, sleeveCost: 40, accessoryCost: 60),
        loggedPlays: 4,
      );
      // (300 + 40 + 60) / 4
      expect(e.costPerPlay, 100);
    });

    test('custo por partida inclui o que foi gasto nas expansões', () {
      final e = _entrada(
        _jogo(id: 1, price: 200),
        loggedPlays: 2,
        expansionCost: 100,
      );
      expect(e.totalInvested, 300);
      expect(e.costPerPlay, 150);
    });

    test('mês de posse tem piso 1: compra de hoje não estoura a divisão', () {
      final e = _entrada(
        _jogo(id: 1, price: 500, purchaseDate: DateTime.now()),
      );
      expect(e.monthsOwned, 1);
      expect(e.costPerMonth, 500);
    });

    // A contagem de meses é testada direto na função, com as duas datas
    // explícitas: usar "hoje menos 2 anos" faria o teste falhar em 29 de
    // fevereiro, quando a data de dois anos antes não existe e normaliza
    // para 1º de março.
    test('conta meses completos de posse', () {
      expect(
        mesesDePosse(DateTime(2023, 7, 15), ate: DateTime(2025, 7, 15)),
        24,
      );
      // Zero mês completo, mas o piso de 1 evita divisão por zero no
      // custo/mês de uma compra recente.
      expect(
        mesesDePosse(DateTime(2025, 1, 20), ate: DateTime(2025, 2, 19)),
        1,
      );
      expect(
        mesesDePosse(DateTime(2025, 1, 20), ate: DateTime(2025, 2, 20)),
        1,
      );
      expect(
        mesesDePosse(DateTime(2025, 1, 20), ate: DateTime(2025, 4, 20)),
        3,
      );
    });

    test('custo de posse por mês cai conforme o tempo passa', () {
      // 24 meses atrás a partir de hoje, sem tocar em dia do mês.
      final hoje = soData(DateTime.now());
      final doisAnosAtras = DateTime(hoje.year - 2, hoje.month, hoje.day);
      final e = _entrada(_jogo(id: 1, price: 480, purchaseDate: doisAnosAtras));

      // O valor exato depende do calendário; o que importa é que o custo
      // mensal seja o investimento dividido pelos meses contados.
      expect(e.monthsOwned, greaterThanOrEqualTo(23));
      expect(e.costPerMonth, closeTo(480 / e.monthsOwned, 0.001));
      expect(e.costPerMonth, lessThan(480));
    });

    test('sem data de compra não há custo por mês', () {
      final e = _entrada(_jogo(id: 1, price: 480));
      expect(e.costPerMonth, isNull);
    });
  });

  group('duração média do jogo', () {
    test('é o meio da faixa que o BGG informa', () {
      const g = Game(id: 1, name: 'X', minPlaytime: 60, maxPlaytime: 120);
      expect(g.averagePlaytime, 90);
    });

    test('com um lado só, usa o lado que existe', () {
      const so = Game(id: 1, name: 'X', minPlaytime: 45);
      expect(so.averagePlaytime, 45);
      const soMax = Game(id: 1, name: 'X', maxPlaytime: 200);
      expect(soMax.averagePlaytime, 200);
    });

    test('sem duração cadastrada é nulo, não zero', () {
      const g = Game(id: 1, name: 'X');
      expect(g.averagePlaytime, isNull);
    });
  });

  group('horas jogadas', () {
    // O jogo padrão destes testes: 60–120 min, média 90.
    Game jogoDe90({double price = 0, int manualPlayCount = 0}) => Game(
          id: 1,
          name: 'X',
          minPlaytime: 60,
          maxPlaytime: 120,
          price: price,
          manualPlayCount: manualPlayCount,
        );

    test('sem cronometrar nada, estima tudo pela média', () {
      // 2 partidas da planilha + 1 registrada = 3 × 90 min.
      final e = _entrada(jogoDe90(manualPlayCount: 2), loggedPlays: 1);

      expect(e.playCount, 3);
      expect(e.estimatedPlays, 3);
      expect(e.totalMinutes, 270);
      expect(e.totalHours, 4.5);
      expect(e.hoursAreEstimated, isTrue);
      expect(e.hoursAreMeasured, isFalse);
    });

    test('mistura o cronometrado com a média das outras', () {
      // 2 partidas: uma cronometrada em 150 min, outra estimada em 90.
      final e = _entrada(
        jogoDe90(),
        loggedPlays: 2,
        loggedPlaysWithDuration: 1,
        loggedMinutes: 150,
      );

      expect(e.estimatedPlays, 1);
      expect(e.totalMinutes, 240);
      expect(e.hoursAreEstimated, isTrue);
    });

    test('tudo cronometrado ignora a média e não marca estimativa', () {
      final e = _entrada(
        jogoDe90(),
        loggedPlays: 2,
        loggedPlaysWithDuration: 2,
        loggedMinutes: 200,
      );

      expect(e.estimatedPlays, 0);
      expect(e.totalMinutes, 200);
      expect(e.hoursAreEstimated, isFalse);
      expect(e.hoursAreMeasured, isTrue);
      expect(e.measuredAverageMinutes, 100);
    });

    test('o histórico da planilha entra como estimativa', () {
      // Partidas antigas nunca tiveram duração registrada.
      final e = _entrada(jogoDe90(manualPlayCount: 4));

      expect(e.estimatedPlays, 4);
      expect(e.totalMinutes, 360);
      expect(e.hoursAreEstimated, isTrue);
    });

    test('sem duração cadastrada e sem cronômetro, não inventa horas', () {
      final e = _entrada(
        const Game(id: 1, name: 'X', price: 300),
        loggedPlays: 3,
      );

      expect(e.totalMinutes, isNull);
      expect(e.totalHours, isNull);
      expect(e.costPerHour, isNull);
    });

    test('sem duração cadastrada, o cronometrado ainda vale', () {
      final e = _entrada(
        const Game(id: 1, name: 'X'),
        loggedPlays: 1,
        loggedPlaysWithDuration: 1,
        loggedMinutes: 75,
      );

      expect(e.totalMinutes, 75);
    });

    test('nunca jogado dá zero hora e nenhum custo por hora', () {
      final e = _entrada(jogoDe90(price: 300));

      expect(e.playCount, 0);
      expect(e.totalMinutes, 0);
      // Zero hora não permite dividir — o custo por hora não existe.
      expect(e.costPerHour, isNull);
      expect(e.hoursAreEstimated, isFalse);
    });

    test('custo por hora divide o investimento pelas horas', () {
      // 300 reais, 4 partidas × 90 min = 6 h -> 50/h.
      final e = _entrada(jogoDe90(price: 300), loggedPlays: 4);

      expect(e.totalHours, 6);
      expect(e.costPerHour, 50);
    });

    test('custo por hora separa jogo curto de jogo longo', () {
      // Mesmo preço e mesmo número de partidas, durações diferentes: por
      // partida empatam, por hora não. É esse o ponto da métrica.
      final curto = _entrada(
        const Game(id: 1, name: 'Filler', price: 200, minPlaytime: 20, maxPlaytime: 20),
        loggedPlays: 10,
      );
      final longo = _entrada(
        const Game(id: 2, name: 'Campanha', price: 200, minPlaytime: 240, maxPlaytime: 240),
        loggedPlays: 10,
      );

      expect(curto.costPerPlay, longo.costPerPlay);
      expect(curto.costPerHour, 60); // 200 / (200min = 3,33h)
      expect(longo.costPerHour, 5); // 200 / 40h
    });

    test('duração média por partida mistura medido e estimado', () {
      final e = _entrada(
        jogoDe90(),
        loggedPlays: 2,
        loggedPlaysWithDuration: 1,
        loggedMinutes: 150,
      );
      // (150 + 90) / 2
      expect(e.averageMinutesPerPlay, 120);
    });
  });

  group('CostStats — horas', () {
    test('soma as horas da coleção e calcula o custo por hora', () {
      final entradas = [
        _entrada(
          const Game(
            id: 1,
            name: 'A',
            price: 300,
            minPlaytime: 60,
            maxPlaytime: 60,
          ),
          loggedPlays: 4,
        ),
        _entrada(
          const Game(
            id: 2,
            name: 'B',
            price: 100,
            minPlaytime: 120,
            maxPlaytime: 120,
          ),
          loggedPlays: 1,
        ),
      ];

      final s = CostStats.compute(entries: entradas);

      // 4×60 + 1×120 = 360 min = 6 h; investido 400.
      expect(s.totalMinutes, 360);
      expect(s.totalHours, 6);
      expect(s.costPerHour, closeTo(400 / 6, 0.001));
      expect(s.avgMinutesPerPlay, 72); // 360 / 5 partidas
      expect(s.hoursAreEstimated, isTrue);
      expect(s.measuredShare, 0);
    });

    test('proporção cronometrada reflete o que foi medido', () {
      final entradas = [
        _entrada(
          const Game(
            id: 1,
            name: 'A',
            price: 100,
            minPlaytime: 60,
            maxPlaytime: 60,
          ),
          loggedPlays: 2,
          loggedPlaysWithDuration: 1,
          loggedMinutes: 60,
        ),
      ];

      final s = CostStats.compute(entries: entradas);

      expect(s.totalMinutes, 120);
      expect(s.measuredMinutes, 60);
      expect(s.measuredShare, 0.5);
      expect(s.hoursAreEstimated, isTrue);
    });

    test('ranking por hora ignora quem não tem horas', () {
      final entradas = [
        _entrada(
          const Game(
            id: 1,
            name: 'Com duração',
            price: 200,
            minPlaytime: 90,
            maxPlaytime: 90,
          ),
          loggedPlays: 2,
        ),
        // Sem duração cadastrada: não entra no ranking de custo por hora.
        _entrada(const Game(id: 2, name: 'Sem duração', price: 500),
            loggedPlays: 5),
      ];

      final s = CostStats.compute(entries: entradas);

      expect(s.byCostPerHour.length, 1);
      expect(s.byCostPerHour.first.entry.id, 1);
      expect(s.mostHours.length, 1);
    });

    test('coleção vazia não quebra as horas', () {
      final s = CostStats.compute(entries: const []);
      expect(s.totalMinutes, 0);
      expect(s.totalHours, 0);
      expect(s.costPerHour, isNull);
      expect(s.avgMinutesPerPlay, isNull);
      expect(s.byCostPerHour, isEmpty);
      expect(s.mostHours, isEmpty);
    });
  });

  group('jogo que não é seu', () {
    test('conta partidas e horas, mas não entra no investimento', () {
      // Jogar o jogo de outra pessoa é hora de mesa sua. Somar o preço dele
      // inflaria o total com dinheiro que você nunca gastou.
      final meu = _entrada(
        const Game(id: 1, name: 'Meu', price: 300, minPlaytime: 60, maxPlaytime: 60),
        loggedPlays: 2,
      );
      final deOutro = _entrada(
        const Game(
          id: 2,
          name: 'Do amigo',
          price: 900,
          minPlaytime: 60,
          maxPlaytime: 60,
          ownership: Ownership.jogada,
        ),
        loggedPlays: 3,
      );

      final s = CostStats.compute(entries: [meu, deOutro]);

      expect(s.totalInvested, 300, reason: 'só o seu conta como dinheiro');
      expect(s.totalPlays, 5, reason: 'as partidas contam todas');
      expect(s.totalMinutes, 300, reason: '5 partidas de 60 min');
      expect(s.itemCount, 1, reason: 'a estante tem um jogo só');
    });

    test('aparece no ranking de mais jogados', () {
      final deOutro = _entrada(
        const Game(id: 1, name: 'Do amigo', ownership: Ownership.jogada),
        loggedPlays: 7,
      );

      final s = CostStats.compute(entries: [deOutro]);

      expect(s.mostPlayed.length, 1);
      expect(s.mostPlayed.single.entry.game.name, 'Do amigo');
    });

    test('não entra na linha do tempo de gastos', () {
      // Você não comprou; não saiu do seu bolso em mês nenhum.
      final deOutro = _entrada(Game(
        id: 1,
        name: 'Do amigo',
        price: 500,
        purchaseDate: DateTime(2025, 3, 1),
        ownership: Ownership.jogada,
      ));

      final s = CostStats.compute(entries: [deOutro]);

      expect(s.monthlySpend, isEmpty);
    });
  });

  group('lista de desejos', () {
    test('jogo desejado fica fora de tudo nos custos', () {
      final desejado = _entrada(Game(
        id: 1,
        name: 'Quero',
        price: 400,
        purchaseDate: DateTime(2025, 1, 1),
        ownership: Ownership.desejada,
      ));

      final s = CostStats.compute(entries: [desejado]);

      expect(s.isEmpty, isTrue);
      expect(s.totalInvested, 0);
      expect(s.monthlySpend, isEmpty);
    });

    test('o alerta exige alvo e preço consultado', () {
      const semNada = Game(id: 1, name: 'X', ownership: Ownership.desejada);
      expect(semNada.priceReached, isFalse);

      const soAlvo = Game(
        id: 1,
        name: 'X',
        ownership: Ownership.desejada,
        targetPrice: 200,
      );
      expect(soAlvo.priceReached, isFalse, reason: 'sem preço não há o que comparar');

      const soPreco = Game(
        id: 1,
        name: 'X',
        ownership: Ownership.desejada,
        lastPrice: 150,
      );
      expect(soPreco.priceReached, isFalse, reason: 'sem alvo não há alerta');
    });

    test('dispara quando o preço chega ou passa do alvo', () {
      Game com(double alvo, double atual) => Game(
            id: 1,
            name: 'X',
            ownership: Ownership.desejada,
            targetPrice: alvo,
            lastPrice: atual,
          );

      expect(com(200, 250).priceReached, isFalse);
      expect(com(200, 200).priceReached, isTrue, reason: 'exatamente no alvo conta');
      expect(com(200, 180).priceReached, isTrue);
    });

    test('alvo zero não vira alerta permanente', () {
      // Um alvo de R$ 0 nunca seria atingido de verdade; tratá-lo como alvo
      // válido deixaria o jogo num limbo.
      const g = Game(
        id: 1,
        name: 'X',
        ownership: Ownership.desejada,
        targetPrice: 0,
        lastPrice: 0,
      );
      expect(g.priceReached, isFalse);
    });

    test('ida e volta pelo banco preserva o tipo e os preços', () {
      final original = Game(
        id: 1,
        name: 'X',
        ownership: Ownership.desejada,
        targetPrice: 199.90,
        lastPrice: 249.90,
        lastPriceAt: DateTime(2026, 7, 30),
      );

      final voltou = Game.fromMap(original.toMap());

      expect(voltou.ownership, Ownership.desejada);
      expect(voltou.targetPrice, 199.90);
      expect(voltou.lastPrice, 249.90);
      expect(voltou.lastPriceAt, DateTime(2026, 7, 30));
    });

    test('banco antigo, sem a coluna, lê tudo como "minha"', () {
      // A migração não precisa de UPDATE: nulo já significa "é meu".
      final antigo = <String, Object?>{
        'id': 1,
        'name': 'Antigo',
        'price': 100.0,
        'sleeve_cost': 0.0,
        'accessory_cost': 0.0,
        'manual_play_count': 0,
        'is_expansion': 0,
        'sold': 0,
        'created_at': '2025-01-01',
      };

      final g = Game.fromMap(antigo);

      expect(g.ownership, Ownership.propria);
      expect(g.isMine, isTrue);
      expect(g.countsAsInvestment, isTrue);
    });
  });

  group('tipo de vínculo', () {
    test('expansão e caixa da série são ambas itens agrupados', () {
      final exp = _jogo(id: 1, linkKind: LinkKind.expansao);
      final serie = _jogo(id: 2, linkKind: LinkKind.serie);
      final solto = _jogo(id: 3);

      expect(exp.isGrouped, isTrue);
      expect(serie.isGrouped, isTrue);
      expect(solto.isGrouped, isFalse);
    });

    test('só a expansão é "expansão"; a caixa da série joga sozinha', () {
      expect(_jogo(id: 1, linkKind: LinkKind.expansao).isExpansion, isTrue);
      expect(_jogo(id: 2, linkKind: LinkKind.serie).isExpansion, isFalse);
    });

    test('cada tipo tem a sua palavra, no singular e no plural', () {
      expect(LinkKind.expansao.contar(1), 'expansão');
      expect(LinkKind.expansao.contar(3), 'expansões');
      expect(LinkKind.serie.contar(1), 'caixa da série');
      expect(LinkKind.serie.contar(6), 'caixas da série');
    });

    test('ida e volta pelo banco preserva o tipo', () {
      for (final k in [LinkKind.expansao, LinkKind.serie, null]) {
        final original = _jogo(id: 1, linkKind: k, parentId: 9);
        final voltou = Game.fromMap(original.toMap());
        expect(voltou.linkKind, k, reason: 'tipo $k não sobreviveu');
      }
    });

    test('backup antigo, sem link_kind, é lido como expansão', () {
      // Versões anteriores só tinham `is_expansion`. Um backup daquela época
      // precisa continuar abrindo, e o que existia lá era expansão.
      final antigo = <String, Object?>{
        'id': 1,
        'name': 'Hero Pack',
        'parent_id': 9,
        'is_expansion': 1,
        'price': 90.0,
        'sleeve_cost': 0.0,
        'accessory_cost': 0.0,
        'manual_play_count': 0,
        'sold': 0,
        'created_at': '2025-01-01',
      };

      final g = Game.fromMap(antigo);

      expect(g.linkKind, LinkKind.expansao);
      expect(g.isGrouped, isTrue);
    });

    test('is_expansion continua sendo gravado, derivado do tipo', () {
      // Para um backup feito hoje ainda abrir numa versão anterior do app.
      expect(_jogo(id: 1, linkKind: LinkKind.serie).toMap()['is_expansion'], 1);
      expect(
        _jogo(id: 1, linkKind: LinkKind.expansao).toMap()['is_expansion'],
        1,
      );
      expect(_jogo(id: 1).toMap()['is_expansion'], 0);
    });
  });

  group('faixa de jogadores', () {
    test('reconhece para quantos jogadores o jogo serve', () {
      const g = Game(id: 1, name: 'X', minPlayers: 2, maxPlayers: 4);
      expect(g.supportsPlayerCount(1), isFalse);
      expect(g.supportsPlayerCount(2), isTrue);
      expect(g.supportsPlayerCount(4), isTrue);
      expect(g.supportsPlayerCount(5), isFalse);
    });

    test('sem informação de jogadores não afirma que serve', () {
      const g = Game(id: 1, name: 'X');
      expect(g.supportsPlayerCount(3), isFalse);
    });
  });

  group('CostStats — investimento', () {
    test('não conta a expansão duas vezes', () {
      // A expansão aparece como item próprio E somada dentro do jogo-base.
      // O total da coleção precisa contá-la uma única vez.
      final base = _entrada(
        _jogo(id: 1, name: 'Base', price: 200),
        expansionCount: 1,
        expansionCost: 100,
      );
      final exp = _entrada(
        _jogo(id: 2, name: 'Exp', price: 100, linkKind: LinkKind.expansao, parentId: 1),
      );

      final s = CostStats.compute(entries: [base, exp]);

      expect(s.totalInvested, 300);
      // Uma fatia só: a expansão está dentro do jogo-base.
      expect(s.compositionByGame.length, 1);
      expect(s.compositionByGame.first.value, 300);
    });

    test('caixa da série também não conta duas vezes', () {
      // Unmatched: cada caixa é um jogo completo, mas agrupada sob uma linha
      // só. Se o cálculo tratasse "caixa da série" como jogo independente — o
      // que aconteceria checando `isExpansion` em vez de `isGrouped` — o
      // dinheiro dela entraria no total dela **e** dentro do grupo.
      final grupo = _entrada(
        _jogo(id: 1, name: 'Unmatched', price: 199),
        expansionCount: 2,
        expansionCost: 380,
      );
      final caixa1 = _entrada(_jogo(
        id: 2,
        name: 'Unmatched: Cobble & Fog',
        price: 189,
        linkKind: LinkKind.serie,
        parentId: 1,
      ));
      final caixa2 = _entrada(_jogo(
        id: 3,
        name: 'Unmatched: Robin Hood',
        price: 191,
        linkKind: LinkKind.serie,
        parentId: 1,
      ));

      final s = CostStats.compute(entries: [grupo, caixa1, caixa2]);

      expect(s.totalInvested, 579);
      // Uma linha só na composição, com o total do grupo.
      expect(s.compositionByGame.length, 1);
      expect(s.compositionByGame.first.label, 'Unmatched');
      expect(s.compositionByGame.first.value, 579);
      // As caixas contam como itens agrupados, não como jogos-base.
      expect(s.baseGameCount, 1);
      expect(s.expansionCount, 2);
    });

    test('caixa da série órfã entra sozinha, como qualquer item sem pai', () {
      final orfa = _entrada(_jogo(
        id: 5,
        name: 'Unmatched: Buffy',
        price: 210,
        linkKind: LinkKind.serie,
      ));

      final s = CostStats.compute(entries: [orfa]);

      expect(s.totalInvested, 210);
      expect(s.compositionByGame.length, 1);
    });

    test('expansão órfã entra por conta própria', () {
      // Sem jogo-base presente, ela não está somada em ninguém — se ficasse
      // de fora, o dinheiro dela desapareceria do total.
      final orfa = _entrada(
        _jogo(id: 2, name: 'Exp', price: 100, linkKind: LinkKind.expansao),
      );

      final s = CostStats.compute(entries: [orfa]);

      expect(s.totalInvested, 100);
      expect(s.compositionByGame.length, 1);
    });

    test('jogo vendido sai do investimento e entra em recuperado', () {
      final ativo = _entrada(_jogo(id: 1, price: 200));
      final vendido = _entrada(
        _jogo(id: 2, price: 300, sold: true, soldPrice: 180),
      );

      final s = CostStats.compute(entries: [ativo, vendido]);

      expect(s.totalInvested, 200);
      expect(s.totalRecovered, 180);
      expect(s.itemCount, 1);
    });

    test('separa caixa, sleeves e acessórios', () {
      final e = _entrada(
        _jogo(id: 1, price: 250, sleeveCost: 45, accessoryCost: 80),
      );

      final s = CostStats.compute(entries: [e]);

      expect(s.totalGames, 250);
      expect(s.totalSleeves, 45);
      expect(s.totalAccessories, 80);
      expect(s.totalInvested, 375);
      expect(s.compositionByType.length, 3);
    });

    test('composição por tipo omite o que é zero', () {
      final e = _entrada(_jogo(id: 1, price: 250));
      final s = CostStats.compute(entries: [e]);

      // Só a caixa: uma fatia. O widget cai para números soltos nesse caso,
      // em vez de desenhar uma rosca de uma fatia.
      expect(s.compositionByType.length, 1);
      expect(s.compositionByType.first.label, 'Caixa do jogo');
    });
  });

  group('CostStats — pizza', () {
    test('dobra a cauda em "Outros" e nunca passa de 6 fatias', () {
      final entradas = [
        for (var i = 1; i <= 12; i++)
          _entrada(_jogo(id: i, name: 'Jogo $i', price: 100.0 * (13 - i))),
      ];

      final s = CostStats.compute(entries: entradas);

      expect(s.compositionByGame.length, 6);
      expect(s.compositionByGame.last.isOther, isTrue);
      expect(s.compositionByGame.last.label, 'Outros 7');

      // A soma das fatias tem de fechar com o total: nada some no "Outros".
      final somaFatias =
          s.compositionByGame.fold<double>(0, (a, f) => a + f.value);
      expect(somaFatias, closeTo(s.totalInvested, 0.001));
    });

    test('a pizza do custo mensal fecha com o custo mensal total', () {
      final hoje = soData(DateTime.now());
      final entradas = [
        for (var i = 1; i <= 9; i++)
          _entrada(_jogo(
            id: i,
            name: 'Jogo $i',
            price: 100.0 * i,
            purchaseDate: DateTime(hoje.year - 1, hoje.month, hoje.day),
          )),
      ];

      final s = CostStats.compute(entries: entradas);

      expect(s.compositionByMonthlyCost.length, 6);
      expect(s.compositionByMonthlyCost.last.isOther, isTrue);

      final soma = s.compositionByMonthlyCost
          .fold<double>(0, (a, f) => a + f.value);
      expect(soma, closeTo(s.monthlyOwnershipCost, 0.001));
    });

    test('jogo sem data de compra fica fora da pizza do custo mensal', () {
      final entradas = [
        _entrada(_jogo(id: 1, price: 300, purchaseDate: DateTime.now())),
        _entrada(_jogo(id: 2, price: 500)), // sem data
      ];

      final s = CostStats.compute(entries: entradas);

      expect(s.compositionByMonthlyCost.length, 1);
      expect(s.compositionByMonthlyCost.first.value, 300);
    });

    test('cada fatia tem slot fixo, para a cor seguir a entidade', () {
      final entradas = [
        for (var i = 1; i <= 4; i++)
          _entrada(_jogo(id: i, name: 'Jogo $i', price: 100.0 * (5 - i))),
      ];

      final s = CostStats.compute(entries: entradas);

      expect(s.compositionByGame.map((f) => f.slot).toList(), [0, 1, 2, 3]);
    });
  });

  group('CostStats — gasto por mês', () {
    test('preenche os meses sem compra com zero', () {
      // Compras em janeiro e abril de 2025: fevereiro e março têm de existir
      // na série, senão a linha do tempo mente sobre o intervalo.
      final entradas = [
        _entrada(_jogo(id: 1, price: 100, purchaseDate: DateTime(2025, 1, 15))),
        _entrada(_jogo(id: 2, price: 200, purchaseDate: DateTime(2025, 4, 3))),
      ];

      final s = CostStats.compute(entries: entradas);
      final meses = s.monthlySpend;

      expect(meses.first.month, DateTime(2025, 1));
      expect(meses[0].total, 100);
      expect(meses[1].total, 0);
      expect(meses[1].month, DateTime(2025, 2));
      expect(meses[2].total, 0);
      expect(meses[3].total, 200);

      // A série se estende até o mês corrente.
      final agora = DateTime.now();
      expect(meses.last.month, DateTime(agora.year, agora.month));
    });

    test('soma várias compras no mesmo mês', () {
      final entradas = [
        _entrada(_jogo(id: 1, price: 100, purchaseDate: DateTime(2025, 3, 2))),
        _entrada(
          _jogo(
            id: 2,
            price: 200,
            sleeveCost: 50,
            purchaseDate: DateTime(2025, 3, 20),
          ),
        ),
      ];

      final s = CostStats.compute(entries: entradas);
      final marco = s.monthlySpend.first;

      expect(marco.month, DateTime(2025, 3));
      expect(marco.itemCount, 2);
      expect(marco.games, 300);
      expect(marco.sleeves, 50);
      expect(marco.total, 350);
    });

    test('inclui jogo vendido: o dinheiro saiu do bolso na época', () {
      final entradas = [
        _entrada(
          _jogo(
            id: 1,
            price: 400,
            purchaseDate: DateTime(2025, 2, 10),
            sold: true,
            soldPrice: 250,
          ),
        ),
      ];

      final s = CostStats.compute(entries: entradas);

      // Fora do investimento atual...
      expect(s.totalInvested, 0);
      // ...mas presente na linha do tempo de gastos.
      expect(s.monthlySpend.first.total, 400);
    });

    test('sem data de compra em nenhum jogo, a série fica vazia', () {
      final s = CostStats.compute(entries: [_entrada(_jogo(id: 1, price: 100))]);
      expect(s.monthlySpend, isEmpty);
    });
  });

  group('CostStats — rankings e valor parado', () {
    test('ranking de custo por partida ignora quem nunca foi jogado', () {
      final jogado = _entrada(_jogo(id: 1, price: 100), loggedPlays: 5);
      final nunca = _entrada(_jogo(id: 2, price: 900));

      final s = CostStats.compute(entries: [jogado, nunca]);

      expect(s.priciestPerPlay.length, 1);
      expect(s.priciestPerPlay.first.entry.id, 1);
    });

    test('conta e soma o valor do que nunca foi à mesa', () {
      final entradas = [
        _entrada(_jogo(id: 1, price: 100), loggedPlays: 2),
        _entrada(_jogo(id: 2, price: 250)),
        _entrada(_jogo(id: 3, price: 150)),
      ];

      final s = CostStats.compute(entries: entradas);

      expect(s.neverPlayedCount, 2);
      expect(s.idleValue, 400);
    });

    test('custo médio por partida da coleção inteira', () {
      final entradas = [
        _entrada(_jogo(id: 1, price: 200), loggedPlays: 4),
        _entrada(_jogo(id: 2, price: 100), loggedPlays: 1),
      ];

      final s = CostStats.compute(entries: entradas);

      expect(s.totalPlays, 5);
      expect(s.avgCostPerPlay, 60); // 300 / 5
    });

    test('coleção vazia não quebra nem divide por zero', () {
      final s = CostStats.compute(entries: const []);

      expect(s.isEmpty, isTrue);
      expect(s.totalInvested, 0);
      expect(s.avgCostPerPlay, isNull);
      expect(s.compositionByGame, isEmpty);
      expect(s.monthlySpend, isEmpty);
    });
  });

  group('parseMoeda', () {
    test('aceita a convenção brasileira', () {
      expect(parseMoeda('1.234,56'), 1234.56);
      expect(parseMoeda('349,90'), 349.90);
      expect(parseMoeda('1.500'), 1500);
    });

    // O ponto sem vírgula é ambíguo: o número de dígitos depois dele é o que
    // desempata milhar de decimal.
    test('desambigua o ponto pela quantidade de dígitos', () {
      expect(parseMoeda('1.500'), 1500); // 3 digitos -> milhar
      expect(parseMoeda('12.345'), 12345); // 3 digitos -> milhar
      expect(parseMoeda('349.90'), 349.90); // 2 digitos -> decimal
      expect(parseMoeda('1.5'), 1.5); // 1 digito  -> decimal
      expect(parseMoeda('1.234.567'), 1234567); // varios pontos -> milhar
    });

    test('aceita ponto como decimal, que é o que o teclado às vezes dá', () {
      expect(parseMoeda('1234.56'), 1234.56);
      expect(parseMoeda('349.90'), 349.90);
    });

    test('as duas convenções dão o mesmo número', () {
      expect(parseMoeda('1.234,56'), parseMoeda('1234.56'));
    });

    test('trata milhar múltiplo sem decimal', () {
      expect(parseMoeda('1.234.567'), 1234567);
    });

    test('ignora símbolo e espaço', () {
      expect(parseMoeda('R\$ 249,90'), 249.90);
      expect(parseMoeda('  120  '), 120);
    });

    test('vazio e lixo viram nulo', () {
      expect(parseMoeda(''), isNull);
      expect(parseMoeda('   '), isNull);
      expect(parseMoeda(null), isNull);
      expect(parseMoeda('abc'), isNull);
    });

    test('campo vazio soma como zero', () {
      expect(parseMoedaOuZero(''), 0);
      expect(parseMoedaOuZero('50'), 50);
    });
  });

  group('formatação', () {
    test('dinheiro em pt-BR', () {
      expect(dinheiro(1234.56), r'R$ 1.234,56');
      expect(dinheiro(0), r'R$ 0,00');
      expect(dinheiro(1234.56, casas: 0), r'R$ 1.235');
      expect(dinheiro(1234567.89), r'R$ 1.234.567,89');
      expect(dinheiro(-50), r'-R$ 50,00');
    });

    test('ida e volta do campo de dinheiro preserva o valor', () {
      for (final v in [0.0, 49.9, 349.90, 1234.56, 1500.0]) {
        final texto = moedaParaCampo(v);
        expect(parseMoedaOuZero(texto), closeTo(v, 0.001),
            reason: 'valor $v virou "$texto"');
      }
    });

    test('faixa de jogadores em texto', () {
      expect(faixaJogadores(2, 4), '2–4 jogadores');
      expect(faixaJogadores(1, 1), '1 jogador');
      expect(faixaJogadores(4, 4), '4 jogadores');
      expect(faixaJogadores(null, null), '—');
    });

    test('desdeQuando fala em português', () {
      final hoje = DateTime.now();
      expect(desdeQuando(null), 'nunca');
      expect(desdeQuando(hoje), 'hoje');
      expect(
        desdeQuando(hoje.subtract(const Duration(days: 1))),
        'ontem',
      );
      expect(
        desdeQuando(hoje.subtract(const Duration(days: 5))),
        'há 5 dias',
      );
    });

    test('contagem de partidas concorda em número', () {
      expect(contagemPartidas(0), 'nunca jogado');
      expect(contagemPartidas(1), '1 partida');
      expect(contagemPartidas(7), '7 partidas');
    });

    test('duração em minutos e horas', () {
      expect(duracao(45), '45min');
      expect(duracao(60), '1h');
      expect(duracao(100), '1h40');
      expect(duracao(120), '2h');
      expect(duracao(125), '2h05');
    });

    test('horas acumuladas', () {
      expect(horas(4.5), '4,5 h');
      expect(horas(6), '6 h');
      expect(horas(137.4), '137 h');
    });

    test('marca de estimativa só aparece quando é estimativa', () {
      expect(talvez('6 h', estimado: true), '≈ 6 h');
      expect(talvez('6 h', estimado: false), '6 h');
    });
  });
}
