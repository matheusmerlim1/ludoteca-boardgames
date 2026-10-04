import 'package:flutter/material.dart';

import '../models/extra.dart';
import '../models/game.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'game_cover.dart';

/// O que você comprou num mês, item a item.
///
/// O total do mês, sozinho, não responde a pergunta que vem depois dele — "no
/// que foi?". Esta folha existe para fechar esse ciclo: você vê R$ 1.200 em
/// março e descobre na hora que foi uma caixa cara e dois pacotes de sleeves.
///
/// Navega entre os meses que **têm compra**. Pular os meses vazios é
/// deliberado: com uma coleção de anos, passar por dezenas de meses em branco
/// até achar o próximo gasto é o tipo de navegação que ninguém usa duas vezes.
class MonthSpendSheet extends StatefulWidget {
  const MonthSpendSheet({
    super.key,
    required this.entries,
    required this.mesInicial,
    this.onAbrirJogo,
    this.extras = const [],
    this.onAbrirExtra,
  });

  /// Compras avulsas (kits, playmats): entram no mês da data de compra.
  final List<Extra> extras;

  final void Function(Extra extra)? onAbrirExtra;

  /// A coleção inteira. A folha filtra por mês de compra por conta própria.
  final List<GameEntry> entries;

  final DateTime mesInicial;

  final void Function(int gameId)? onAbrirJogo;

  static Future<void> show(
    BuildContext context, {
    required List<GameEntry> entries,
    required DateTime mesInicial,
    void Function(int gameId)? onAbrirJogo,
    List<Extra> extras = const [],
    void Function(Extra extra)? onAbrirExtra,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MonthSpendSheet(
        entries: entries,
        mesInicial: mesInicial,
        onAbrirJogo: onAbrirJogo,
        extras: extras,
        onAbrirExtra: onAbrirExtra,
      ),
    );
  }

  @override
  State<MonthSpendSheet> createState() => _MonthSpendSheetState();
}

class _MonthSpendSheetState extends State<MonthSpendSheet> {
  late DateTime _mes = _primeiroMes();

  /// Só o que saiu do **seu** bolso. Jogo de outra pessoa e jogo desejado
  /// nunca foram comprados; jogo já vendido foi, e o dinheiro saiu na época.
  late final List<GameEntry> _compras = widget.entries
      .where((e) => e.game.isMine && e.game.purchaseDate != null)
      .toList();

  late final List<Extra> _extrasComData =
      widget.extras.where((x) => x.purchaseDate != null).toList();

  List<Extra> get _extrasDoMes => _extrasComData.where((x) {
        final d = x.purchaseDate!;
        return d.year == _mes.year && d.month == _mes.month;
      }).toList();

  /// Meses com compra, do mais antigo para o mais novo.
  late final List<DateTime> _meses = () {
    final chaves = <String, DateTime>{};
    for (final e in _compras) {
      final d = e.game.purchaseDate!;
      final m = DateTime(d.year, d.month);
      chaves[chaveMes(m)] = m;
    }
    for (final x in _extrasComData) {
      final d = x.purchaseDate!;
      final m = DateTime(d.year, d.month);
      chaves[chaveMes(m)] = m;
    }
    return chaves.values.toList()..sort();
  }();

  /// Abre no mês pedido; se ele não tiver compra, no mês com compra mais
  /// próximo dele — abrir numa tela vazia não conta nada a ninguém.
  DateTime _primeiroMes() {
    final pedido = DateTime(widget.mesInicial.year, widget.mesInicial.month);
    return pedido;
  }

  @override
  void initState() {
    super.initState();
    if (_meses.isEmpty) return;
    if (!_meses.any((m) => chaveMes(m) == chaveMes(_mes))) {
      _mes = _maisProximo(_mes);
    }
  }

  DateTime _maisProximo(DateTime alvo) {
    var melhor = _meses.first;
    var menorDistancia = _distanciaEmMeses(melhor, alvo);
    for (final m in _meses) {
      final d = _distanciaEmMeses(m, alvo);
      if (d < menorDistancia) {
        melhor = m;
        menorDistancia = d;
      }
    }
    return melhor;
  }

  static int _distanciaEmMeses(DateTime a, DateTime b) =>
      ((a.year - b.year) * 12 + (a.month - b.month)).abs();

  List<GameEntry> get _doMes {
    final lista = _compras.where((e) {
      final d = e.game.purchaseDate!;
      return d.year == _mes.year && d.month == _mes.month;
    }).toList()
      // Mais caro primeiro: é o que explica o tamanho da barra daquele mês.
      ..sort((a, b) => b.game.totalInvested.compareTo(a.game.totalInvested));
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    final itens = _doMes;
    final extras = _extrasDoMes;
    final extrasSleeves = extras
        .where((x) => x.isSleeve)
        .fold<double>(0, (s, x) => s + x.price);
    final extrasOutros = extras
        .where((x) => !x.isSleeve)
        .fold<double>(0, (s, x) => s + x.price);
    final total = itens.fold<double>(0, (s, e) => s + e.game.totalInvested) +
        extrasSleeves +
        extrasOutros;
    final caixas = itens.fold<double>(0, (s, e) => s + e.game.price);
    final sleeves =
        itens.fold<double>(0, (s, e) => s + e.game.sleeveCost) + extrasSleeves;
    final acessorios =
        itens.fold<double>(0, (s, e) => s + e.game.accessoryCost) + extrasOutros;
    final quantos = itens.length + extras.length;

    // Jogos e extras numa lista só, do mais caro para o mais barato: é o que
    // explica o tamanho da barra daquele mês, seja caixa ou playmat.
    final linhas = <({double valor, Widget linha})>[
      for (final e in itens)
        (
          valor: e.game.totalInvested,
          linha: _LinhaDeCompra(
            entry: e,
            onTap: widget.onAbrirJogo == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onAbrirJogo!(e.id);
                  },
          ),
        ),
      for (final x in extras)
        (
          valor: x.price,
          linha: _LinhaDeExtra(
            extra: x,
            onTap: widget.onAbrirExtra == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onAbrirExtra!(x);
                  },
          ),
        ),
    ]..sort((a, b) => b.valor.compareTo(a.valor));

    final i = _meses.indexWhere((m) => chaveMes(m) == chaveMes(_mes));
    final temAnterior = i > 0;
    final temProximo = i >= 0 && i < _meses.length - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: viz.baseline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              IconButton(
                onPressed: temAnterior
                    ? () => setState(() => _mes = _meses[i - 1])
                    : null,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Mês anterior com compra',
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      mesAnoLongo(_mes),
                      textAlign: TextAlign.center,
                      style: text.titleMedium?.copyWith(fontSize: 16),
                    ),
                    Text(
                      quantos == 0
                          ? 'nenhuma compra'
                          : '$quantos '
                              '${quantos == 1 ? 'item' : 'itens'} · '
                              '${dinheiro(total)}',
                      style: text.labelSmall?.copyWith(color: viz.inkMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: temProximo
                    ? () => setState(() => _mes = _meses[i + 1])
                    : null,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Próximo mês com compra',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),

          if (_meses.isEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Nenhum jogo ou extra tem data de compra ainda. Preencha a data '
              'na ficha e as compras aparecem aqui, mês a mês.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const SizedBox(height: 24),
          ] else ...[
            const SizedBox(height: 8),
            // A quebra por tipo só aparece quando há mais de um tipo: numa
            // compra só de caixa, repetir o mesmo número em duas linhas não
            // acrescenta nada.
            if (sleeves > 0 || acessorios > 0) ...[
              _Quebra(
                caixas: caixas,
                sleeves: sleeves,
                acessorios: acessorios,
              ),
              const SizedBox(height: 8),
            ],
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: linhas.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: viz.gridline),
                itemBuilder: (_, k) => linhas[k].linha,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Quebra extends StatelessWidget {
  const _Quebra({
    required this.caixas,
    required this.sleeves,
    required this.acessorios,
  });

  final double caixas;
  final double sleeves;
  final double acessorios;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    final partes = <String>[
      if (caixas > 0) 'caixa ${dinheiro(caixas, casas: 0)}',
      if (sleeves > 0) 'sleeves ${dinheiro(sleeves, casas: 0)}',
      if (acessorios > 0) 'acessórios ${dinheiro(acessorios, casas: 0)}',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: viz.serie(0).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        partes.join(' · '),
        style: text.labelSmall?.copyWith(color: viz.inkPrimary),
      ),
    );
  }
}

class _LinhaDeCompra extends StatelessWidget {
  const _LinhaDeCompra({required this.entry, required this.onTap});

  final GameEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final g = entry.game;

    final extras = <String>[
      if (g.sleeveCost > 0) 'sleeves ${dinheiro(g.sleeveCost, casas: 0)}',
      if (g.accessoryCost > 0)
        'acessórios ${dinheiro(g.accessoryCost, casas: 0)}',
      // Vendido depois continua contando aqui: o dinheiro saiu naquele mês,
      // independente do que aconteceu com o jogo mais tarde.
      if (g.isGone) g.disposal?.label.toLowerCase() ?? 'saiu da coleção',
    ];

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: GameCover(
                  url: g.thumbUrl ?? g.imageUrl,
                  name: entry.displayName,
                  borderRadius: 0,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: viz.inkPrimary),
                  ),
                  if (extras.isNotEmpty)
                    Text(
                      extras.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(color: viz.inkMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              dinheiro(g.totalInvested),
              style: text.bodyMedium?.copyWith(
                color: viz.inkPrimary,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compra avulsa no meio das compras do mês, com o tipo no lugar da capa.
class _LinhaDeExtra extends StatelessWidget {
  const _LinhaDeExtra({required this.extra, required this.onTap});

  final Extra extra;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: viz.serie(1).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(extra.kind.icon, size: 18, color: viz.inkPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    extra.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: viz.inkPrimary),
                  ),
                  Text(
                    '${extra.kind.label.toLowerCase()} · avulso',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(color: viz.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              dinheiro(extra.price),
              style: text.bodyMedium?.copyWith(
                color: viz.inkPrimary,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
