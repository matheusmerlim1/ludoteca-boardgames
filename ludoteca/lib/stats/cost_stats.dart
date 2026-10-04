import '../models/extra.dart';
import '../models/game.dart';
import '../utils/format.dart';

/// Uma fatia de gráfico de pizza.
class Slice {
  const Slice({
    required this.label,
    required this.value,
    this.slot,
    this.isOther = false,
  });

  final String label;
  final double value;

  /// Slot fixo na paleta categórica. Fica gravado na fatia para a cor seguir a
  /// *entidade* e não a posição — filtrar não deve repintar quem sobrou.
  final int? slot;

  final bool isOther;
}

/// Gasto de um mês da linha do tempo.
class MonthSpend {
  const MonthSpend({
    required this.month,
    required this.games,
    required this.sleeves,
    required this.accessories,
    required this.itemCount,
  });

  final DateTime month;
  final double games;
  final double sleeves;
  final double accessories;
  final int itemCount;

  double get total => games + sleeves + accessories;
}

/// Uma linha de ranking por jogo (custo/partida ou custo/mês).
class RankedGame {
  const RankedGame({
    required this.entry,
    required this.value,
    required this.detail,
  });

  final GameEntry entry;
  final double value;

  /// Texto secundário que explica de onde saiu o número.
  final String detail;
}

/// Todos os números da tela de custos, calculados de uma vez.
///
/// Cuidado central aqui é **não contar expansão duas vezes**: o custo dela
/// aparece somado dentro do jogo-base (`GameEntry.totalInvested`), então as
/// expansões vinculadas ficam fora da iteração de topo.
class CostStats {
  CostStats._({
    required this.totalInvested,
    required this.totalGames,
    required this.totalSleeves,
    required this.totalAccessories,
    required this.totalRecovered,
    required this.itemCount,
    required this.baseGameCount,
    required this.expansionCount,
    required this.totalPlays,
    required this.playedGameCount,
    required this.neverPlayedCount,
    required this.totalMinutes,
    required this.measuredMinutes,
    required this.playsWithMeasuredDuration,
    required this.monthlyOwnershipCost,
    required this.datedGameCount,
    required this.undatedGameCount,
    required this.idleValue,
    required this.compositionByGame,
    required this.compositionByType,
    required this.compositionByMonthlyCost,
    required this.monthlySpend,
    required this.cheapestPerPlay,
    required this.priciestPerPlay,
    required this.byCostPerMonth,
    required this.mostPlayed,
    required this.byCostPerHour,
    required this.mostHours,
    required this.extrasTotal,
    required this.extrasCount,
  });

  /// Compras avulsas (kit de sleeves, playmat...) — fora de [totalInvested],
  /// que é o investimento **nos jogos** e alimenta custo por partida e por
  /// hora. Um playmat não é de jogo nenhum; dividi-lo pelas partidas de um
  /// jogo inventaria um número.
  final double extrasTotal;
  final int extrasCount;

  /// Tudo que você gastou no hobby e ainda tem: jogos mais extras.
  double get totalSpent => totalInvested + extrasTotal;

  /// Investimento atual: tudo que está na estante.
  final double totalInvested;
  final double totalGames;
  final double totalSleeves;
  final double totalAccessories;

  /// Quanto voltou de vendas.
  final double totalRecovered;

  final int itemCount;
  final int baseGameCount;
  final int expansionCount;

  final int totalPlays;
  final int playedGameCount;
  final int neverPlayedCount;

  /// Minutos jogados na coleção: o cronometrado mais a duração média do jogo
  /// para cada partida não cronometrada.
  final int totalMinutes;

  /// Só a parte cronometrada, para dar a proporção de quanto do total é
  /// medido de verdade.
  final int measuredMinutes;
  final int playsWithMeasuredDuration;

  /// Soma do custo de posse mensal de cada jogo — "minha coleção me custa
  /// tanto por mês". Só entram os jogos com data de compra.
  final double monthlyOwnershipCost;

  /// Quantos jogos entraram nessa conta, e quantos ficaram de fora por não
  /// terem data de compra.
  ///
  /// Sem estes dois números a tela não tem como distinguir uma coleção que
  /// custa pouco por mês de uma coleção sem datas preenchidas — as duas somam
  /// zero, e uma delas está mentindo.
  final int datedGameCount;
  final int undatedGameCount;

  /// Verdadeiro quando nenhum jogo tem data de compra: aí o custo por mês não
  /// é zero, é desconhecido.
  bool get monthlyCostIsUnknown => datedGameCount == 0;

  /// Pizza 1: onde o dinheiro está, por jogo. No máximo 6 fatias.
  final List<Slice> compositionByGame;

  /// Pizza 2: caixa x sleeves x acessórios.
  final List<Slice> compositionByType;

  /// Pizza 3: quem puxa o custo mensal da coleção. As fatias somam
  /// [monthlyOwnershipCost]. No máximo 6.
  final List<Slice> compositionByMonthlyCost;

  /// Barras: gasto mês a mês, sem buracos.
  final List<MonthSpend> monthlySpend;

  final List<RankedGame> cheapestPerPlay;
  final List<RankedGame> priciestPerPlay;
  final List<RankedGame> byCostPerMonth;
  final List<RankedGame> mostPlayed;

  /// Custo por hora de jogo — a comparação mais justa entre um filler de 20
  /// minutos e um jogo de campanha de 4 horas, que por partida não se comparam.
  final List<RankedGame> byCostPerHour;

  final List<RankedGame> mostHours;

  bool get isEmpty => itemCount == 0 && extrasCount == 0;

  /// O que saiu do bolso **neste** mês — a mesma conta da barra do mês atual
  /// no gráfico de gasto. Não confundir com [monthlyOwnershipCost], o custo de
  /// posse: ele dilui a coleção inteira no tempo e não muda de mês para mês.
  /// Mês sem compra (ou coleção sem nenhuma data) dá zero, com o mês certo.
  MonthSpend get currentMonthSpend {
    final agora = DateTime.now();
    final mes = DateTime(agora.year, agora.month);
    for (final m in monthlySpend) {
      if (m.month.year == mes.year && m.month.month == mes.month) return m;
    }
    return MonthSpend(
      month: mes,
      games: 0,
      sleeves: 0,
      accessories: 0,
      itemCount: 0,
    );
  }

  /// Custo médio por partida da coleção como um todo.
  double? get avgCostPerPlay =>
      totalPlays == 0 ? null : totalInvested / totalPlays;

  double get totalHours => totalMinutes / 60;

  /// Custo por hora de jogo da coleção inteira.
  double? get costPerHour =>
      totalMinutes == 0 ? null : totalInvested / (totalMinutes / 60);

  /// Duração média de uma partida qualquer da sua coleção.
  double? get avgMinutesPerPlay =>
      totalPlays == 0 || totalMinutes == 0 ? null : totalMinutes / totalPlays;

  /// Se alguma parte das horas é estimada pela média em vez de cronometrada.
  bool get hoursAreEstimated => playsWithMeasuredDuration < totalPlays;

  /// Fração do tempo total que veio de cronômetro, de 0 a 1.
  double get measuredShare =>
      totalMinutes == 0 ? 0 : measuredMinutes / totalMinutes;

  /// Quanto do acervo nunca foi à mesa, em dinheiro.
  final double idleValue;

  /// Os rankings vêm **inteiros**, não cortados no top 8.
  ///
  /// Quem corta é a tela, que sabe quantas linhas cabem e oferece o "ver
  /// todos". Cortar aqui obrigaria a recalcular tudo para expandir uma lista —
  /// e um ranking com metade dos jogos não responde "onde o meu está".
  static CostStats compute({
    required List<GameEntry> entries,
    List<Extra> extras = const [],
    int topSlices = 5,
  }) {
    // Jogo desejado nunca entra em nada: não é seu e não foi jogado.
    final considerados =
        entries.where((e) => !e.game.isWishlist).toList(growable: false);

    // "Ativos" para custo é o que é **seu** e não vendido. Um jogo de outra
    // pessoa entra nas partidas e nas horas, mas somar o preço dele inflaria
    // o investimento com dinheiro que você nunca gastou.
    final ativos =
        considerados.where((e) => e.game.countsAsInvestment).toList();
    final vendidos = considerados.where((e) => e.game.sold).toList();

    /// Tudo que foi à mesa, seja seu ou de outra pessoa.
    final jogaveis = considerados.where((e) => !e.game.sold).toList();

    final idsAtivos = {for (final e in ativos) e.game.id};

    /// Entradas de topo: jogos-base + expansões órfãs (cujo pai foi removido
    /// ou nunca foi vinculado). Expansão vinculada a um pai presente já está
    /// contabilizada dentro dele.
    final topo = ativos.where((e) {
      final pai = e.game.parentId;
      if (!e.game.isGrouped) return true;
      return pai == null || !idsAtivos.contains(pai);
    }).toList();

    // --- totais -------------------------------------------------------------
    var totalGames = 0.0;
    var totalSleeves = 0.0;
    var totalAccessories = 0.0;
    for (final e in ativos) {
      totalGames += e.game.price;
      totalSleeves += e.game.sleeveCost;
      totalAccessories += e.game.accessoryCost;
    }
    final totalInvested = totalGames + totalSleeves + totalAccessories;

    final totalRecovered =
        vendidos.fold<double>(0, (s, e) => s + (e.game.soldPrice ?? 0));

    final totalPlays = jogaveis.fold<int>(0, (s, e) => s + e.playCount);
    final jogados = jogaveis.where((e) => e.playCount > 0).length;
    final nuncaJogados = topo.where((e) => e.neverPlayed).length;

    final idleValue = topo
        .where((e) => e.neverPlayed)
        .fold<double>(0, (s, e) => s + e.totalInvested);

    // Só dá para dividir por meses de posse quem tem data de compra. Contar
    // quantos ficaram de fora é o que separa "a coleção custa zero por mês"
    // (falso, e foi o que o app dizia) de "faltam datas para calcular".
    final comData = topo.where((e) => e.costPerMonth != null).toList();
    final semData = topo.length - comData.length;

    final monthlyOwnership =
        comData.fold<double>(0, (s, e) => s + e.costPerMonth!);

    // --- pizzas por jogo ----------------------------------------------------
    final compositionByGame =
        _fatias(topo, (e) => e.totalInvested, topSlices);

    final compositionByMonthlyCost =
        _fatias(topo, (e) => e.costPerMonth ?? 0, topSlices);

    // --- extras avulsos -----------------------------------------------------
    final extrasSleeves = extras
        .where((x) => x.isSleeve)
        .fold<double>(0, (s, x) => s + x.price);
    final extrasOutros = extras
        .where((x) => !x.isSleeve)
        .fold<double>(0, (s, x) => s + x.price);

    // --- pizza por tipo de gasto -------------------------------------------
    // Os extras entram aqui: a pergunta é "em que você gastou", e um kit de
    // sleeves avulso é gasto com sleeves do mesmo jeito.
    final sleevesTudo = totalSleeves + extrasSleeves;
    final acessoriosTudo = totalAccessories + extrasOutros;
    final compositionByType = <Slice>[
      if (totalGames > 0) Slice(label: 'Caixa do jogo', value: totalGames, slot: 0),
      if (sleevesTudo > 0) Slice(label: 'Sleeves', value: sleevesTudo, slot: 1),
      if (acessoriosTudo > 0)
        Slice(label: 'Acessórios', value: acessoriosTudo, slot: 2),
    ];

    // --- gasto por mês ------------------------------------------------------
    // Inclui vendidos: a pergunta é "quanto saiu do bolso naquele mês", e um
    // jogo comprado e depois vendido saiu do bolso do mesmo jeito.
    // Só o que você comprou. Jogo de outra pessoa e jogo desejado nunca
    // saíram do seu bolso, então não têm o que fazer numa linha do tempo de
    // gastos.
    final monthlySpend = _gastoPorMes(
      entries.where((e) => e.game.isMine).toList(),
      extras,
    );

    // --- rankings -----------------------------------------------------------
    final comCustoPorPartida =
        topo.where((e) => e.costPerPlay != null && e.totalInvested > 0).toList();

    final baratos = [...comCustoPorPartida]
      ..sort((a, b) => a.costPerPlay!.compareTo(b.costPerPlay!));
    final caros = [...comCustoPorPartida]
      ..sort((a, b) => b.costPerPlay!.compareTo(a.costPerPlay!));

    final porMes = topo.where((e) => e.costPerMonth != null).toList()
      ..sort((a, b) => b.costPerMonth!.compareTo(a.costPerMonth!));

    final maisJogados = jogaveis.where((e) => e.playCount > 0).toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));

    // --- horas --------------------------------------------------------------
    // Tempo usa `jogaveis` e não `topo`: expansão pode ter partida própria,
    // jogo de outra pessoa também conta hora de mesa, e horas não correm o
    // risco de dupla contagem que o custo corre.
    final totalMinutos =
        jogaveis.fold<int>(0, (s, e) => s + (e.totalMinutes ?? 0));
    final minutosMedidos =
        jogaveis.fold<int>(0, (s, e) => s + e.loggedMinutes);
    final partidasMedidas =
        jogaveis.fold<int>(0, (s, e) => s + e.loggedPlaysWithDuration);

    final porHora = ativos
        .where((e) => e.costPerHour != null && e.totalInvested > 0)
        .toList()
      ..sort((a, b) => b.costPerHour!.compareTo(a.costPerHour!));

    final maisHoras = jogaveis.where((e) => (e.totalMinutes ?? 0) > 0).toList()
      ..sort((a, b) => b.totalMinutes!.compareTo(a.totalMinutes!));

    RankedGame porPartida(GameEntry e) => RankedGame(
          entry: e,
          value: e.costPerPlay!,
          detail:
              '${dinheiro(e.totalInvested)} · ${contagemPartidas(e.playCount)}',
        );

    return CostStats._(
      totalInvested: totalInvested,
      totalGames: totalGames,
      totalSleeves: totalSleeves,
      totalAccessories: totalAccessories,
      totalRecovered: totalRecovered,
      itemCount: ativos.length,
      baseGameCount: ativos.where((e) => !e.game.isGrouped).length,
      expansionCount: ativos.where((e) => e.game.isGrouped).length,
      totalPlays: totalPlays,
      playedGameCount: jogados,
      neverPlayedCount: nuncaJogados,
      totalMinutes: totalMinutos,
      measuredMinutes: minutosMedidos,
      playsWithMeasuredDuration: partidasMedidas,
      monthlyOwnershipCost: monthlyOwnership,
      datedGameCount: comData.length,
      undatedGameCount: semData,
      idleValue: idleValue,
      compositionByGame: compositionByGame,
      compositionByType: compositionByType,
      compositionByMonthlyCost: compositionByMonthlyCost,
      monthlySpend: monthlySpend,
      extrasTotal: extrasSleeves + extrasOutros,
      extrasCount: extras.length,
      cheapestPerPlay: baratos.map(porPartida).toList(),
      priciestPerPlay: caros.map(porPartida).toList(),
      byCostPerMonth: porMes
          .map((e) => RankedGame(
                entry: e,
                value: e.costPerMonth!,
                detail: '${dinheiro(e.totalInvested)} · '
                    '${e.monthsOwned} ${e.monthsOwned == 1 ? 'mês' : 'meses'} de posse',
              ))
          .toList(),
      mostPlayed: maisJogados
          .map((e) => RankedGame(
                entry: e,
                value: e.playCount.toDouble(),
                detail: 'última vez ${desdeQuando(e.lastPlayed)}',
              ))
          .toList(),
      byCostPerHour: porHora
          .map((e) => RankedGame(
                entry: e,
                value: e.costPerHour!,
                detail: '${dinheiro(e.totalInvested)} · '
                    '${talvez(horas(e.totalHours!), estimado: e.hoursAreEstimated)} '
                    'de mesa',
              ))
          .toList(),
      mostHours: maisHoras
          .map((e) => RankedGame(
                entry: e,
                // O valor da barra é em horas; o rótulo formata.
                value: e.totalHours!,
                detail: '${contagemPartidas(e.playCount)} · '
                    '${duracao(e.averageMinutesPerPlay!.round())} por partida'
                    '${e.hoursAreEstimated ? ' (estimado)' : ''}',
              ))
          .toList(),
    );
  }

  /// As [limite] maiores entradas por [valor], com a cauda dobrada em "Outros".
  ///
  /// Pizza com mais de 6 fatias vira papa — as fatias vizinhas deixam de se
  /// distinguir, e sob daltonismo bem antes disso. Dobrar a cauda resolve sem
  /// esconder dinheiro: a soma das fatias continua fechando com o total.
  static List<Slice> _fatias(
    List<GameEntry> entradas,
    double Function(GameEntry) valor,
    int limite,
  ) {
    final ordenadas = entradas.where((e) => valor(e) > 0).toList()
      ..sort((a, b) => valor(b).compareTo(valor(a)));

    final out = <Slice>[];

    for (var i = 0; i < ordenadas.length && i < limite; i++) {
      out.add(Slice(
        // O slot fixo faz a cor seguir a entidade, não a posição no ranking.
        label: ordenadas[i].displayName,
        value: valor(ordenadas[i]),
        slot: i,
      ));
    }

    if (ordenadas.length > limite) {
      final resto =
          ordenadas.skip(limite).fold<double>(0, (s, e) => s + valor(e));
      if (resto > 0) {
        out.add(Slice(
          label: 'Outros ${ordenadas.length - limite}',
          value: resto,
          slot: limite,
          isOther: true,
        ));
      }
    }

    return out;
  }

  /// Agrupa compras por mês e **preenche os meses vazios com zero**.
  ///
  /// Sem esse preenchimento a linha do tempo mente: três compras em jan, mar e
  /// jun viram três barras lado a lado e parecem meses consecutivos.
  static List<MonthSpend> _gastoPorMes(
    List<GameEntry> entries, [
    List<Extra> extras = const [],
  ]) {
    final comData =
        entries.where((e) => e.game.purchaseDate != null).toList();
    final extrasComData = extras.where((x) => x.purchaseDate != null).toList();
    if (comData.isEmpty && extrasComData.isEmpty) return const [];

    final acc = <String, ({double j, double s, double a, int n})>{};
    DateTime? menor;
    DateTime? maior;

    for (final e in comData) {
      final d = e.game.purchaseDate!;
      final mes = DateTime(d.year, d.month);
      if (menor == null || mes.isBefore(menor)) menor = mes;
      if (maior == null || mes.isAfter(maior)) maior = mes;

      final k = chaveMes(mes);
      final atual = acc[k] ?? (j: 0.0, s: 0.0, a: 0.0, n: 0);
      acc[k] = (
        j: atual.j + e.game.price,
        s: atual.s + e.game.sleeveCost,
        a: atual.a + e.game.accessoryCost,
        n: atual.n + 1,
      );
    }

    // Extra avulso soma no mês em que foi comprado: sleeves com sleeves, o
    // resto com acessórios — a barra do mês mostra a quebra do mesmo jeito.
    for (final x in extrasComData) {
      final d = x.purchaseDate!;
      final mes = DateTime(d.year, d.month);
      if (menor == null || mes.isBefore(menor)) menor = mes;
      if (maior == null || mes.isAfter(maior)) maior = mes;

      final k = chaveMes(mes);
      final atual = acc[k] ?? (j: 0.0, s: 0.0, a: 0.0, n: 0);
      acc[k] = (
        j: atual.j,
        s: atual.s + (x.isSleeve ? x.price : 0),
        a: atual.a + (x.isSleeve ? 0 : x.price),
        n: atual.n + 1,
      );
    }

    // Estende até o mês atual, para "não comprei nada desde março" aparecer.
    final agora = DateTime.now();
    final fim = DateTime(agora.year, agora.month);
    if (maior!.isBefore(fim)) maior = fim;

    final out = <MonthSpend>[];
    var cursor = menor!;
    while (!cursor.isAfter(maior)) {
      final v = acc[chaveMes(cursor)];
      out.add(MonthSpend(
        month: cursor,
        games: v?.j ?? 0,
        sleeves: v?.s ?? 0,
        accessories: v?.a ?? 0,
        itemCount: v?.n ?? 0,
      ));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }

    return out;
  }
}
