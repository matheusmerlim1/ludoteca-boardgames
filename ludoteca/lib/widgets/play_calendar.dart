import 'package:flutter/material.dart';

import '../models/play.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'chart_card.dart';

/// Calendário de intensidade das partidas.
///
/// Cada quadrado é um dia; quanto mais escuro, mais partidas naquele dia. As
/// colunas são semanas e as linhas são os dias da semana, então a passagem do
/// tempo corre da esquerda para a direita e os buracos aparecem sozinhos — dá
/// para ver o mês que você não jogou nada sem precisar contar nada.
///
/// A cor é **um hue só**, do claro ao escuro, porque a grandeza é contínua:
/// hue diferente sugeriria categoria diferente, e aqui é a mesma coisa em
/// quantidades diferentes. Dia sem partida não recebe cor da rampa — fica na
/// cor da grade, para "nenhuma" não parecer "pouquinha".
class PlayCalendar extends StatefulWidget {
  const PlayCalendar({
    super.key,
    required this.plays,
    this.weeks = 53,
  });

  final List<Play> plays;

  /// Quantas semanas mostrar para trás.
  final int weeks;

  @override
  State<PlayCalendar> createState() => _PlayCalendarState();
}

class _PlayCalendarState extends State<PlayCalendar> {
  static const _cell = 14.0;
  static const _gap = 3.0;

  final _scroll = ScrollController();
  DateTime? _selecionado;

  @override
  void initState() {
    super.initState();
    // Abre no fim: o que interessa primeiro é o mês corrente.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    if (widget.plays.isEmpty) {
      return ChartCard(
        title: 'Quando você jogou',
        subtitle: 'Cada quadrado é um dia.',
        child: Text(
          'Registre partidas e o calendário aparece aqui.',
          style: text.bodySmall,
        ),
      );
    }

    final porDia = <DateTime, int>{};
    for (final p in widget.plays) {
      final d = soData(p.playedAt);
      porDia[d] = (porDia[d] ?? 0) + 1;
    }

    final hoje = soData(DateTime.now());
    // A grade começa no domingo, para as linhas serem dias da semana.
    final fimDaSemana = hoje.add(Duration(days: 6 - hoje.weekday % 7));
    final inicio = fimDaSemana.subtract(Duration(days: widget.weeks * 7 - 1));

    final noPeriodo = porDia.entries
        .where((e) => !e.key.isBefore(inicio) && !e.key.isAfter(hoje))
        .toList();
    final diasComJogo = noPeriodo.length;
    final partidas = noPeriodo.fold<int>(0, (s, e) => s + e.value);
    final maximo = noPeriodo.fold<int>(0, (m, e) => e.value > m ? e.value : m);

    final destaque = _selecionado;

    return ChartCard(
      title: 'Quando você jogou',
      subtitle: 'Cada quadrado é um dia. Mais escuro, mais partidas.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Um valor sempre legível, sem depender de tocar em nada.
          _Leitura(
            dia: destaque,
            partidasNoDia: destaque == null ? 0 : (porDia[destaque] ?? 0),
            partidas: partidas,
            diasComJogo: diasComJogo,
            semanas: widget.weeks,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 7 * (_cell + _gap) + 20,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Meses(
                    inicio: inicio,
                    semanas: widget.weeks,
                    largura: _cell + _gap,
                  ),
                  Row(
                    children: [
                      for (var s = 0; s < widget.weeks; s++)
                        Padding(
                          padding: const EdgeInsets.only(right: _gap),
                          child: Column(
                            children: [
                              for (var d = 0; d < 7; d++)
                                _Quadrado(
                                  dia: inicio.add(Duration(days: s * 7 + d)),
                                  hoje: hoje,
                                  contagem: porDia[
                                          inicio.add(Duration(days: s * 7 + d))] ??
                                      0,
                                  maximo: maximo,
                                  tamanho: _cell,
                                  gap: _gap,
                                  selecionado: destaque,
                                  onTap: (dia) => setState(
                                    () => _selecionado =
                                        _selecionado == dia ? null : dia,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Legenda(maximo: maximo),
          const SizedBox(height: 4),
          Text(
            'Toque num quadrado para ver o dia.',
            style: text.labelSmall?.copyWith(color: viz.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// Passo da rampa para uma contagem. Zero devolve `null` — dia sem partida não
/// entra na rampa, senão "nenhuma" pareceria "pouquinha".
int? _nivel(int contagem, int maximo) {
  if (contagem <= 0) return null;
  if (maximo <= 1) return 3;
  // Quatro faixas sobre o máximo observado, com piso 0 para uma partida.
  final f = (contagem - 1) / (maximo - 1);
  return (f * 3).round().clamp(0, 3);
}

class _Quadrado extends StatelessWidget {
  const _Quadrado({
    required this.dia,
    required this.hoje,
    required this.contagem,
    required this.maximo,
    required this.tamanho,
    required this.gap,
    required this.selecionado,
    required this.onTap,
  });

  final DateTime dia;
  final DateTime hoje;
  final int contagem;
  final int maximo;
  final double tamanho;
  final double gap;
  final DateTime? selecionado;
  final void Function(DateTime) onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final futuro = dia.isAfter(hoje);
    final nivel = _nivel(contagem, maximo);
    final marcado = selecionado == dia;

    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: GestureDetector(
        onTap: futuro ? null : () => onTap(dia),
        child: Container(
          width: tamanho,
          height: tamanho,
          decoration: BoxDecoration(
            // Dia futuro nem existe ainda: sem cor e sem toque.
            color: futuro
                ? Colors.transparent
                : nivel == null
                    ? viz.gridline
                    : viz.sequential[nivel],
            borderRadius: BorderRadius.circular(3),
            border: marcado
                ? Border.all(color: viz.inkPrimary, width: 2)
                : dia == hoje
                    ? Border.all(color: viz.inkMuted, width: 1)
                    : null,
          ),
        ),
      ),
    );
  }
}

/// Rótulos de mês acima das colunas.
class _Meses extends StatelessWidget {
  const _Meses({
    required this.inicio,
    required this.semanas,
    required this.largura,
  });

  final DateTime inicio;
  final int semanas;
  final double largura;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;

    return SizedBox(
      height: 18,
      child: Row(
        children: [
          for (var s = 0; s < semanas; s++)
            SizedBox(
              width: largura,
              child: _mostraRotulo(s)
                  ? Text(
                      mesCurto(inicio.add(Duration(days: s * 7))),
                      style: TextStyle(fontSize: 9.5, color: viz.inkMuted),
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  /// Rotula a primeira semana de cada mês, e nunca duas seguidas — com colunas
  /// de 17px, meses vizinhos escreveriam por cima um do outro.
  bool _mostraRotulo(int semana) {
    if (semana == 0) return false;
    final atual = inicio.add(Duration(days: semana * 7));
    final anterior = inicio.add(Duration(days: (semana - 1) * 7));
    return atual.month != anterior.month;
  }
}

class _Leitura extends StatelessWidget {
  const _Leitura({
    required this.dia,
    required this.partidasNoDia,
    required this.partidas,
    required this.diasComJogo,
    required this.semanas,
  });

  final DateTime? dia;
  final int partidasNoDia;
  final int partidas;
  final int diasComJogo;
  final int semanas;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    if (dia != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            partidasNoDia == 0
                ? 'Nada neste dia'
                : contagemPartidas(partidasNoDia),
            style: text.headlineSmall?.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 2),
          Text('em ${data(dia!)}', style: text.bodySmall),
        ],
      );
    }

    // Média por semana só faz sentido com histórico; abaixo disso o número
    // seria mais ruído que informação.
    final porSemana = partidas / semanas;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$partidas',
              style: text.headlineSmall?.copyWith(fontSize: 24),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                partidas == 1 ? 'partida no último ano' : 'partidas no último ano',
                style: text.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'em $diasComJogo ${diasComJogo == 1 ? 'dia' : 'dias'} diferentes · '
          '${porSemana.toStringAsFixed(1).replaceAll('.', ',')} por semana',
          style: text.labelSmall?.copyWith(color: viz.inkMuted),
        ),
      ],
    );
  }
}

class _Amostra extends StatelessWidget {
  const _Amostra({required this.cor});

  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: cor,
          borderRadius: BorderRadius.circular(3),
        ),
      );
}

class _Legenda extends StatelessWidget {
  const _Legenda({required this.maximo});

  final int maximo;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    // Wrap e não Row: numa tela de 320 a escala e o texto do pico não cabem
    // lado a lado, e um Spacer entre eles só empurraria o excedente para fora.
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('menos', style: text.labelSmall?.copyWith(color: viz.inkMuted)),
            const SizedBox(width: 6),
            _Amostra(cor: viz.gridline),
            for (final c in viz.sequential) ...[
              const SizedBox(width: 3),
              _Amostra(cor: c),
            ],
            const SizedBox(width: 6),
            Text('mais', style: text.labelSmall?.copyWith(color: viz.inkMuted)),
          ],
        ),
        if (maximo > 0)
          Text(
            'pico: ${contagemPartidas(maximo)} num dia',
            style: text.labelSmall?.copyWith(color: viz.inkMuted),
          ),
      ],
    );
  }
}
