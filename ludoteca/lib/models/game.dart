import '../utils/format.dart';

/// Que relação você tem com este jogo.
///
/// Antes, estar cadastrado significava "é meu". Isso não dava conta de dois
/// casos reais:
///
/// - **[jogada]** — jogou o jogo de outra pessoa. Conta para as partidas e as
///   horas de mesa, mas não é investimento seu: entrar nos custos inflaria o
///   total com dinheiro que você nunca gastou.
/// - **[desejada]** — quer comprar. Não é sua nem foi jogada; serve para
///   acompanhar preço.
enum Ownership {
  propria('Minha', 'na estante'),
  jogada('Jogada sem ter', 'jogou sem ser dono'),
  desejada('Quero comprar', 'lista de desejos');

  const Ownership(this.label, this.descricao);

  final String label;
  final String descricao;

  /// Nulo no banco significa "minha" — o caso comum não gasta valor gravado,
  /// e um banco anterior à coluna lê certo sem migração de dados.
  static Ownership fromDb(String? v) => switch (v) {
        'jogada' => Ownership.jogada,
        'desejada' => Ownership.desejada,
        _ => Ownership.propria,
      };

  String? get dbValue => this == Ownership.propria ? null : name;
}

/// Como o jogo saiu da coleção.
///
/// As três saídas têm efeitos diferentes no dinheiro, e tratá-las como uma só
/// mentiria no custo:
///
/// - [vendido] devolve dinheiro, que abate o investimento.
/// - [trocado] não devolve dinheiro, mas **transfere** o valor investido para
///   o jogo que entrou no lugar.
/// - [doado] não devolve nada. O que você gastou continua gasto.
enum Disposal {
  vendido('Vendido', 'entrou dinheiro'),
  trocado('Trocado', 'veio outro jogo no lugar'),
  doado('Doado', 'saiu sem retorno');

  const Disposal(this.label, this.efeito);

  final String label;
  final String efeito;

  static Disposal? fromDb(String? v) => switch (v) {
        'vendido' => Disposal.vendido,
        'trocado' => Disposal.trocado,
        'doado' => Disposal.doado,
        _ => null,
      };

  String get dbValue => name;
}

/// Como um item se vincula ao jogo-pai.
///
/// A diferença importa porque muda a leitura, não só a palavra:
///
/// - [expansao] não joga sozinha. Um "Hero Pack" de Marvel Champions precisa
///   da caixa base.
/// - [serie] joga sozinha, mas você trata como um jogo só. Unmatched é o caso
///   exemplar: cada caixa é um jogo completo, e ainda assim ninguém quer seis
///   linhas de "Unmatched" na estante, com as partidas e o custo por partida
///   picados entre elas.
///
/// Nos dois casos o custo soma no pai e o item some da lista principal — o que
/// muda é o rótulo e o texto que o app usa para falar da coisa.
enum LinkKind {
  expansao('expansão', 'expansões'),
  serie('caixa da série', 'caixas da série');

  const LinkKind(this.singular, this.plural);

  final String singular;
  final String plural;

  String contar(int n) => n == 1 ? singular : plural;

  static LinkKind? fromDb(String? v) => switch (v) {
        'expansao' => LinkKind.expansao,
        'serie' => LinkKind.serie,
        _ => null,
      };

  String get dbValue => this == LinkKind.expansao ? 'expansao' : 'serie';
}

/// Um jogo (ou expansão) da coleção.
///
/// Os campos vindos do BGG (jogadores, duração, peso, imagem) são gravados
/// junto do registro para o app funcionar offline depois do primeiro
/// cadastro — nada é buscado de novo só para exibir a lista.
class Game {
  const Game({
    this.id,
    this.bggId,
    required this.name,
    this.namePt,
    this.year,
    this.minPlayers,
    this.maxPlayers,
    this.bestPlayers,
    this.minPlaytime,
    this.maxPlaytime,
    this.weight,
    this.imageUrl,
    this.thumbUrl,
    this.parentId,
    this.linkKind,
    this.ownership = Ownership.propria,
    this.targetPrice,
    this.lastPrice,
    this.lastPriceAt,
    this.price = 0,
    this.sleeveCost = 0,
    this.accessoryCost = 0,
    this.purchaseDate,
    this.manualPlayCount = 0,
    this.manualLastPlayed,
    this.disposal,
    this.tradedForId,
    this.sold = false,
    this.soldPrice,
    this.soldDate,
    this.notes,
    this.createdAt,
  });

  final int? id;

  /// Id no BoardGameGeek, quando o jogo veio da busca.
  final int? bggId;

  /// Nome principal (normalmente em inglês, como vem do BGG).
  final String name;

  /// Nome em português, editável. Tem prioridade na exibição.
  final String? namePt;

  final int? year;
  final int? minPlayers;
  final int? maxPlayers;

  /// Nº de jogadores mais votado na enquete do BGG.
  final int? bestPlayers;

  final int? minPlaytime;
  final int? maxPlaytime;

  /// Peso/complexidade do BGG, de 1 a 5.
  final double? weight;

  final String? imageUrl;
  final String? thumbUrl;

  /// Se preenchido, este item está agrupado sob o jogo com esse id.
  final int? parentId;

  /// Como o item se vincula ao pai. Nulo = item independente.
  final LinkKind? linkKind;

  /// Verdadeiro para qualquer item agrupado (expansão ou caixa de série).
  ///
  /// Derivado, nunca guardado à parte: dois campos independentes dizendo a
  /// mesma coisa acabam se contradizendo.
  bool get isGrouped => linkKind != null;

  /// Mantido para não quebrar quem já chamava assim. Hoje significa
  /// especificamente "não joga sozinho".
  bool get isExpansion => linkKind == LinkKind.expansao;

  /// Palavra certa para este item no singular: "expansão" ou "caixa da série".
  String? get linkLabel => linkKind?.singular;

  final Ownership ownership;

  bool get isMine => ownership == Ownership.propria;
  bool get isWishlist => ownership == Ownership.desejada;

  /// Só o que é seu entra nos custos. Jogo de outra pessoa e jogo desejado
  /// não são dinheiro que saiu do seu bolso.
  bool get countsAsInvestment => isMine && !isGone;

  /// Preço que você quer pagar, para o alerta disparar.
  final double? targetPrice;

  /// Menor preço visto na última consulta ao catálogo, e quando foi.
  final double? lastPrice;
  final DateTime? lastPriceAt;

  /// O preço acompanhado chegou no alvo.
  ///
  /// Exige os dois números: sem alvo não há o que comparar, e sem preço
  /// consultado não há o que dizer.
  bool get priceReached {
    final alvo = targetPrice;
    final atual = lastPrice;
    if (alvo == null || atual == null || alvo <= 0) return false;
    return atual <= alvo;
  }

  final double price;
  final double sleeveCost;
  final double accessoryCost;
  final DateTime? purchaseDate;

  /// Partidas jogadas *antes* de começar a registrar no app — o número que
  /// você já tinha na planilha. Soma com as partidas lançadas.
  final int manualPlayCount;
  final DateTime? manualLastPlayed;

  /// Como o jogo saiu da coleção. Nulo = ainda está com você.
  final Disposal? disposal;

  /// Numa troca, o jogo que entrou no lugar deste.
  final int? tradedForId;

  /// Legado da época em que "vendido" era a única saída.
  ///
  /// Continua gravado para um backup feito aqui abrir numa versão anterior do
  /// app, mas quem manda é [disposal] — ver [isGone].
  final bool sold;

  /// Quanto voltou na venda. Nulo em troca e doação: nessas não entra dinheiro.
  final double? soldPrice;
  final DateTime? soldDate;

  /// Saiu da coleção de qualquer forma.
  bool get isGone => disposal != null || sold;

  /// Rótulo da saída, para a UI não repetir o switch.
  String? get disposalLabel => disposal?.label ?? (sold ? 'vendido' : null);

  final String? notes;
  final DateTime? createdAt;

  /// Nome como deve aparecer na tela.
  String get displayName =>
      (namePt != null && namePt!.trim().isNotEmpty) ? namePt!.trim() : name;

  /// Nome secundário, mostrado só quando difere do principal.
  String? get subtitleName =>
      displayName.toLowerCase() == name.toLowerCase() ? null : name;

  /// Duração média em minutos, o meio da faixa que o BGG informa.
  ///
  /// É a base para estimar horas jogadas sem você ter de cronometrar nada.
  /// Nulo quando o jogo não tem duração cadastrada — e nesse caso as horas
  /// ficam indisponíveis em vez de virarem zero, porque "não sei" e "não
  /// jogou" são coisas diferentes.
  int? get averagePlaytime {
    final a = minPlaytime;
    final b = maxPlaytime;
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    return ((a + b) / 2).round();
  }

  /// Tudo que esse jogo custou: caixa + sleeves + acessórios.
  double get totalInvested => price + sleeveCost + accessoryCost;

  /// Quanto ainda está "no bolso do jogo" depois de uma venda.
  double get netInvested => sold ? totalInvested - (soldPrice ?? 0) : totalInvested;

  bool supportsPlayerCount(int n) {
    final min = minPlayers;
    final max = maxPlayers;
    if (min == null && max == null) return false;
    return n >= (min ?? n) && n <= (max ?? n);
  }

  Game copyWith({
    int? id,
    int? bggId,
    String? name,
    String? namePt,
    int? year,
    int? minPlayers,
    int? maxPlayers,
    int? bestPlayers,
    int? minPlaytime,
    int? maxPlaytime,
    double? weight,
    String? imageUrl,
    String? thumbUrl,
    int? parentId,
    LinkKind? linkKind,
    bool clearLinkKind = false,
    Ownership? ownership,
    double? targetPrice,
    bool clearTargetPrice = false,
    double? lastPrice,
    DateTime? lastPriceAt,
    double? price,
    double? sleeveCost,
    double? accessoryCost,
    DateTime? purchaseDate,
    int? manualPlayCount,
    DateTime? manualLastPlayed,
    Disposal? disposal,
    int? tradedForId,
    bool? sold,
    double? soldPrice,
    DateTime? soldDate,
    String? notes,
    DateTime? createdAt,
    bool clearParent = false,
    bool clearPurchaseDate = false,
    bool clearSoldFields = false,
  }) {
    return Game(
      id: id ?? this.id,
      bggId: bggId ?? this.bggId,
      name: name ?? this.name,
      namePt: namePt ?? this.namePt,
      year: year ?? this.year,
      minPlayers: minPlayers ?? this.minPlayers,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      bestPlayers: bestPlayers ?? this.bestPlayers,
      minPlaytime: minPlaytime ?? this.minPlaytime,
      maxPlaytime: maxPlaytime ?? this.maxPlaytime,
      weight: weight ?? this.weight,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbUrl: thumbUrl ?? this.thumbUrl,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      linkKind: clearLinkKind ? null : (linkKind ?? this.linkKind),
      ownership: ownership ?? this.ownership,
      targetPrice:
          clearTargetPrice ? null : (targetPrice ?? this.targetPrice),
      lastPrice: lastPrice ?? this.lastPrice,
      lastPriceAt: lastPriceAt ?? this.lastPriceAt,
      price: price ?? this.price,
      sleeveCost: sleeveCost ?? this.sleeveCost,
      accessoryCost: accessoryCost ?? this.accessoryCost,
      purchaseDate:
          clearPurchaseDate ? null : (purchaseDate ?? this.purchaseDate),
      manualPlayCount: manualPlayCount ?? this.manualPlayCount,
      manualLastPlayed: manualLastPlayed ?? this.manualLastPlayed,
      disposal: clearSoldFields ? null : (disposal ?? this.disposal),
      tradedForId: clearSoldFields ? null : (tradedForId ?? this.tradedForId),
      sold: clearSoldFields ? false : (sold ?? this.sold),
      soldPrice: clearSoldFields ? null : (soldPrice ?? this.soldPrice),
      soldDate: clearSoldFields ? null : (soldDate ?? this.soldDate),
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'bgg_id': bggId,
        'name': name,
        'name_pt': namePt,
        'year': year,
        'min_players': minPlayers,
        'max_players': maxPlayers,
        'best_players': bestPlayers,
        'min_playtime': minPlaytime,
        'max_playtime': maxPlaytime,
        'weight': weight,
        'image_url': imageUrl,
        'thumb_url': thumbUrl,
        'parent_id': parentId,
        'link_kind': linkKind?.dbValue,
        'ownership': ownership.dbValue,
        'target_price': targetPrice,
        'last_price': lastPrice,
        'last_price_at':
            lastPriceAt == null ? null : isoData(lastPriceAt!),
        // Derivada de link_kind. Continua sendo gravada para um backup feito
        // aqui ainda abrir numa versão anterior do app.
        'is_expansion': isGrouped ? 1 : 0,
        'price': price,
        'sleeve_cost': sleeveCost,
        'accessory_cost': accessoryCost,
        'purchase_date': purchaseDate == null ? null : isoData(purchaseDate!),
        'manual_play_count': manualPlayCount,
        'manual_last_played':
            manualLastPlayed == null ? null : isoData(manualLastPlayed!),
        'disposal_kind': disposal?.dbValue,
        'traded_for_id': tradedForId,
        // Derivado de disposal: um backup feito aqui ainda abre numa versao
        // anterior do app, que so conhecia sold.
        'sold': isGone ? 1 : 0,
        'sold_price': soldPrice,
        'sold_date': soldDate == null ? null : isoData(soldDate!),
        'notes': notes,
        'created_at': isoData(createdAt ?? DateTime.now()),
      };

  factory Game.fromMap(Map<String, Object?> m) => Game(
        id: m['id'] as int?,
        bggId: m['bgg_id'] as int?,
        name: (m['name'] as String?) ?? 'Sem nome',
        namePt: m['name_pt'] as String?,
        year: m['year'] as int?,
        minPlayers: m['min_players'] as int?,
        maxPlayers: m['max_players'] as int?,
        bestPlayers: m['best_players'] as int?,
        minPlaytime: m['min_playtime'] as int?,
        maxPlaytime: m['max_playtime'] as int?,
        weight: (m['weight'] as num?)?.toDouble(),
        imageUrl: m['image_url'] as String?,
        thumbUrl: m['thumb_url'] as String?,
        parentId: m['parent_id'] as int?,
        ownership: Ownership.fromDb(m['ownership'] as String?),
        targetPrice: (m['target_price'] as num?)?.toDouble(),
        lastPrice: (m['last_price'] as num?)?.toDouble(),
        lastPriceAt: parseIsoData(m['last_price_at'] as String?),
        // Backup antigo não tem `link_kind`: nesse caso o que existia era
        // expansão, então é assim que ele é lido.
        linkKind: LinkKind.fromDb(m['link_kind'] as String?) ??
            ((m['is_expansion'] as int? ?? 0) == 1 ? LinkKind.expansao : null),
        price: (m['price'] as num?)?.toDouble() ?? 0,
        sleeveCost: (m['sleeve_cost'] as num?)?.toDouble() ?? 0,
        accessoryCost: (m['accessory_cost'] as num?)?.toDouble() ?? 0,
        purchaseDate: parseIsoData(m['purchase_date'] as String?),
        manualPlayCount: m['manual_play_count'] as int? ?? 0,
        manualLastPlayed: parseIsoData(m['manual_last_played'] as String?),
        disposal: Disposal.fromDb(m['disposal_kind'] as String?),
        tradedForId: m['traded_for_id'] as int?,
        sold: (m['sold'] as int? ?? 0) == 1,
        soldPrice: (m['sold_price'] as num?)?.toDouble(),
        soldDate: parseIsoData(m['sold_date'] as String?),
        notes: m['notes'] as String?,
        createdAt: parseIsoData(m['created_at'] as String?),
      );

  Map<String, Object?> toJson() => toMap();

  factory Game.fromJson(Map<String, Object?> j) => Game.fromMap(j);
}

/// Jogo + os números derivados das partidas. É o que as telas consomem;
/// nada de recalcular contagem espalhado pela UI.
class GameEntry {
  const GameEntry({
    required this.game,
    required this.loggedPlays,
    this.lastLoggedPlay,
    this.expansionCount = 0,
    this.expansionCost = 0,
    this.loggedPlaysWithDuration = 0,
    this.loggedMinutes = 0,
  });

  final Game game;

  /// Partidas registradas no app (sem o contador manual).
  final int loggedPlays;
  final DateTime? lastLoggedPlay;

  /// Quantas dessas partidas têm duração cronometrada.
  final int loggedPlaysWithDuration;

  /// Soma dos minutos das partidas cronometradas.
  final int loggedMinutes;

  final int expansionCount;

  /// Soma investida nas expansões deste jogo.
  final double expansionCost;

  int get id => game.id!;
  String get displayName => game.displayName;

  /// Total de partidas: o que veio da planilha + o que foi registrado.
  int get playCount => game.manualPlayCount + loggedPlays;

  /// A mais recente entre a data manual e a última partida registrada.
  DateTime? get lastPlayed {
    final a = game.manualLastPlayed;
    final b = lastLoggedPlay;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  bool get neverPlayed => playCount == 0;

  /// Investimento do jogo somado ao das expansões.
  double get totalInvested => game.totalInvested + expansionCost;

  /// Custo por partida. `null` quando nunca foi jogado — nesse caso o número
  /// não existe, e a UI mostra "—" em vez de um infinito disfarçado.
  double? get costPerPlay =>
      playCount == 0 ? null : totalInvested / playCount;

  /// Custo de posse por mês: total investido ÷ meses desde a compra.
  double? get costPerMonth {
    final meses = mesesDePosse(game.purchaseDate);
    if (meses == 0) return null;
    return totalInvested / meses;
  }

  int get monthsOwned => mesesDePosse(game.purchaseDate);

  // ------------------------------------------------------------------- horas

  /// Partidas cujo tempo é estimado pela média, não cronometrado.
  ///
  /// Inclui o histórico que veio da planilha: aquelas partidas nunca tiveram
  /// duração registrada.
  int get estimatedPlays => playCount - loggedPlaysWithDuration;

  /// Minutos totais jogados: o que foi cronometrado, mais a duração média do
  /// jogo para cada partida que você não cronometrou.
  ///
  /// Nulo quando não há como saber — nenhuma partida cronometrada e o jogo sem
  /// duração cadastrada.
  int? get totalMinutes {
    final medio = game.averagePlaytime;

    if (medio == null) {
      // Sem média, só o medido conta. Nada medido, nada a informar.
      return loggedPlaysWithDuration == 0 ? null : loggedMinutes;
    }

    return loggedMinutes + estimatedPlays * medio;
  }

  double? get totalHours {
    final m = totalMinutes;
    return m == null ? null : m / 60;
  }

  /// Se alguma parte das horas é estimativa. A UI marca o número com "≈"
  /// quando isto é verdade — número estimado apresentado como medido é o
  /// tipo de detalhe que corrói a confiança no resto.
  bool get hoursAreEstimated => estimatedPlays > 0;

  /// Se **tudo** foi cronometrado.
  bool get hoursAreMeasured => playCount > 0 && estimatedPlays == 0;

  /// Custo por hora de jogo. A métrica mais justa entre jogos de duração
  /// muito diferente: um filler de 20 minutos e um campanha de 4 horas não se
  /// comparam bem por partida.
  double? get costPerHour {
    final h = totalHours;
    if (h == null || h <= 0) return null;
    return totalInvested / h;
  }

  /// Duração média das partidas *deste* jogo, misturando medido e estimado.
  double? get averageMinutesPerPlay {
    final m = totalMinutes;
    if (m == null || playCount == 0) return null;
    return m / playCount;
  }

  /// Média só das partidas cronometradas — o número sem estimativa dentro.
  /// Útil para descobrir que um jogo "de 60 min" na verdade leva 100 na sua
  /// mesa.
  double? get measuredAverageMinutes => loggedPlaysWithDuration == 0
      ? null
      : loggedMinutes / loggedPlaysWithDuration;
}
