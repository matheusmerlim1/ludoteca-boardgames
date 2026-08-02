import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/play.dart';
import '../services/share_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'chart_card.dart';
import 'game_cover.dart';

/// Um jogo no mês, com quantas partidas.
class _Bolha {
  _Bolha({required this.entry, required this.partidas, required this.raio});

  final GameEntry entry;
  final int partidas;
  final double raio;

  Offset centro = Offset.zero;
}

/// Os jogos de um mês em círculos, com a capa dentro e o tamanho pela
/// quantidade de partidas.
///
/// O tamanho é proporcional à **área**, não ao diâmetro — o raio cresce com a
/// raiz do número de partidas. É o que o olho compara num círculo, e usar o
/// diâmetro faria quatro partidas parecerem dezesseis.
class PlayBubbles extends StatefulWidget {
  const PlayBubbles({
    super.key,
    required this.plays,
    required this.entryPorId,
    this.modoImagem = false,
  });

  final List<Play> plays;

  /// Para achar nome e capa a partir do id da partida.
  final GameEntry? Function(int gameId) entryPorId;

  /// Deixa o quadro no estado em que ele é capturado, para o teste conferir o
  /// que sai na imagem sem precisar abrir a folha de compartilhamento.
  @visibleForTesting
  final bool modoImagem;

  @override
  State<PlayBubbles> createState() => _PlayBubblesState();
}

class _PlayBubblesState extends State<PlayBubbles> {
  /// Mês mostrado. Começa no mês corrente.
  late DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);

  int? _selecionada;

  /// O pedaço que vira imagem ao compartilhar: mês, círculos e legenda.
  final _quadro = GlobalKey();

  /// Ligado por um instante durante a captura.
  ///
  /// A imagem leva só o mês, o ano e os círculos. Setas, anel de seleção,
  /// contagem de partidas e a legenda com os nomes ficam de fora: os dois
  /// primeiros são controles da tela, e os dois últimos transformariam a
  /// imagem no mesmo texto que ela veio substituir.
  late bool _capturando = widget.modoImagem;

  bool _compartilhando = false;

  /// Meses que têm partida, do mais antigo ao mais novo.
  List<DateTime> get _mesesComPartida {
    final chaves = <String, DateTime>{};
    for (final p in widget.plays) {
      final m = DateTime(p.playedAt.year, p.playedAt.month);
      chaves[chaveMes(m)] = m;
    }
    final lista = chaves.values.toList()..sort();
    return lista;
  }

  @override
  void initState() {
    super.initState();
    // Se o mês corrente não tem partida, abre no último mês que teve — uma
    // tela vazia por padrão não diz nada a ninguém.
    final comPartida = _mesesComPartida;
    if (comPartida.isNotEmpty &&
        !comPartida.any((m) => chaveMes(m) == chaveMes(_mes))) {
      _mes = comPartida.last;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    if (widget.plays.isEmpty) {
      return ChartCard(
        title: 'O mês em jogos',
        child: Text(
          'Registre partidas e elas aparecem aqui, cada jogo num círculo.',
          style: text.bodySmall,
        ),
      );
    }

    // Partidas do mês, agrupadas por jogo.
    final contagem = <int, int>{};
    for (final p in widget.plays) {
      if (p.playedAt.year != _mes.year || p.playedAt.month != _mes.month) {
        continue;
      }
      contagem[p.gameId] = (contagem[p.gameId] ?? 0) + 1;
    }

    final meses = _mesesComPartida;
    final i = meses.indexWhere((m) => chaveMes(m) == chaveMes(_mes));
    final temAnterior = i > 0;
    final temProximo = i >= 0 && i < meses.length - 1;

    return ChartCard(
      title: 'O mês em jogos',
      subtitle: 'Cada círculo é um jogo; o tamanho é quantas vezes foi à mesa.',
      trailing: IconButton(
        onPressed: contagem.isEmpty || _compartilhando ? null : _compartilhar,
        icon: _compartilhando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.ios_share),
        tooltip: 'Compartilhar a imagem do mês',
        visualDensity: VisualDensity.compact,
      ),
      // O que entra na imagem começa aqui. O fundo é pintado de propósito:
      // uma captura de área transparente vira um PNG que some no fundo escuro
      // do WhatsApp.
      child: RepaintBoundary(
        key: _quadro,
        child: Container(
          color: viz.surface,
          // Só embaixo, e só na imagem: sem a legenda, os círculos ficariam
          // colados na borda. Mexer na largura mudaria o empacotamento e a
          // imagem sairia com os círculos noutro arranjo do que você viu.
          padding: EdgeInsets.only(bottom: _capturando ? 18 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          _NavegadorDeMes(
            mes: _mes,
            partidas: contagem.values.fold(0, (a, b) => a + b),
            jogos: contagem.length,
            soMesEAno: _capturando,
            onAnterior: temAnterior
                ? () => setState(() {
                      _mes = meses[i - 1];
                      _selecionada = null;
                    })
                : null,
            onProximo: temProximo
                ? () => setState(() {
                      _mes = meses[i + 1];
                      _selecionada = null;
                    })
                : null,
          ),
          const SizedBox(height: 14),
          if (contagem.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'Nenhuma partida neste mês.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                // Teto de altura para o conjunto caber na tela sem rolar,
                // como na imagem que o Ludohall gera. Se não couber, os
                // círculos encolhem juntos — a proporção entre eles é o que
                // importa, não o tamanho absoluto.
                final bolhas = _monta(contagem, c.maxWidth, 460);
                final altura = _alturaNecessaria(bolhas);

                return SizedBox(
                  height: altura,
                  child: Stack(
                    children: [
                      for (final b in bolhas)
                        Positioned(
                          left: b.centro.dx - b.raio,
                          top: b.centro.dy - b.raio,
                          width: b.raio * 2,
                          height: b.raio * 2,
                          child: _Circulo(
                            bolha: b,
                            selecionada:
                                !_capturando && _selecionada == b.entry.id,
                            onTap: () => setState(
                              () => _selecionada =
                                  _selecionada == b.entry.id ? null : b.entry.id,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 10),
          // A legenda é a lista: na tela, capa e círculo não dizem o nome, e
          // depender de tocar em cada bolha para saber o que é seria esconder
          // o dado.
          //
          // Na imagem ela sai fora: o que se manda é o desenho do mês, e uma
          // lista de nomes com contagem embaixo transforma a imagem no mesmo
          // texto que ela veio substituir.
          if (!_capturando)
            for (final e in _ordenado(contagem))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: viz.serie(0),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.entryPorId(e.key)?.displayName ?? 'Removido',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: viz.inkPrimary),
                      ),
                    ),
                    Text(
                      contagemPartidas(e.value),
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Manda o mês como **imagem**, não como lista de nomes.
  ///
  /// A graça do disco é justamente ser visual: um círculo grande diz na hora o
  /// que "Ark Nova — 6×" só diz depois de você ler a linha inteira.
  ///
  /// Se a captura falhar por qualquer motivo, o texto vai no lugar — melhor um
  /// compartilhamento sem graça do que um botão que não faz nada.
  Future<void> _compartilhar() async {
    const servico = ShareService();
    final legenda = servico.textoDoMes(_mes, widget.plays, widget.entryPorId);

    setState(() {
      _compartilhando = true;
      _capturando = true;
    });

    Uint8List? png;
    try {
      // Espera o quadro em que as setas já sumiram; capturar antes disso
      // pegaria a tela do jeito que ela estava.
      await WidgetsBinding.instance.endOfFrame;
      png = await capturaPng(_quadro);
    } finally {
      if (mounted) setState(() => _capturando = false);
    }

    try {
      if (png == null) {
        await servico.compartilhar(
          legenda,
          assunto: 'Meus jogos em ${mesAnoLongo(_mes)}',
        );
      } else {
        await servico.compartilharImagem(
          png,
          nomeDoArquivo: 'ludoteca-${chaveMes(_mes)}.png',
          // O texto acompanha a imagem: no WhatsApp vira a legenda, e em quem
          // não mostra imagem (e-mail antigo) ainda sobra o conteúdo.
          texto: legenda,
          assunto: 'Meus jogos em ${mesAnoLongo(_mes)}',
        );
      }
    } finally {
      if (mounted) setState(() => _compartilhando = false);
    }
  }

  List<MapEntry<int, int>> _ordenado(Map<int, int> contagem) {
    final lista = contagem.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        final na = widget.entryPorId(a.key)?.displayName ?? '';
        final nb = widget.entryPorId(b.key)?.displayName ?? '';
        return na.toLowerCase().compareTo(nb.toLowerCase());
      });
    return lista;
  }

  /// Monta o conjunto e encolhe até caber em [alturaMax].
  ///
  /// Encolher todo mundo pelo mesmo fator mantém a proporção entre os
  /// círculos, que é a informação — o tamanho absoluto não significa nada
  /// sozinho.
  List<_Bolha> _monta(
    Map<int, int> contagem,
    double largura,
    double alturaMax,
  ) {
    var escala = 1.0;

    for (var tentativa = 0; tentativa < 6; tentativa++) {
      final bolhas = _comEscala(contagem, largura, escala);
      _empacota(bolhas, largura);

      final altura = _alturaNecessaria(bolhas);
      if (altura <= alturaMax) return bolhas;

      // Área cresce com o quadrado do raio: para cortar a altura por um
      // fator, o raio cai pela raiz dele. O 0,95 evita ficar oscilando na
      // borda do limite.
      escala *= math.sqrt(alturaMax / altura) * 0.95;
    }

    final bolhas = _comEscala(contagem, largura, escala);
    _empacota(bolhas, largura);
    return bolhas;
  }

  /// Calcula os raios para uma dada escala.
  List<_Bolha> _comEscala(
    Map<int, int> contagem,
    double largura,
    double escala,
  ) {
    final ordenado = _ordenado(contagem);
    final maxPartidas =
        ordenado.fold<int>(1, (m, e) => e.value > m ? e.value : m);

    // Área proporcional às partidas: o raio cresce com a **raiz** da
    // contagem. É o que o olho compara num círculo — dobrar o raio quadruplica
    // a área, então raio proporcional faria 4 partidas parecerem 16.
    //
    // A escala é absoluta, não normalizada pelo máximo: 4 partidas tem de ser
    // exatamente o dobro do raio de 1 partida, independente do maior do mês.
    // Normalizar pelo intervalo (o que eu fazia antes) fazia todo mundo virar
    // do mesmo tamanho quando todos tinham a mesma contagem, e ainda deixava
    // o menor sempre no mínimo, mentindo sobre a proporção.
    final rTeto = math.min(70.0, largura / 3.0) * escala;
    final rBase =
        (rTeto / math.sqrt(maxPartidas)).clamp(14.0 * escala, 34.0 * escala);

    return [
      for (final e in ordenado)
        if (widget.entryPorId(e.key) != null)
          _Bolha(
            entry: widget.entryPorId(e.key)!,
            partidas: e.value,
            raio: math.min(rBase * math.sqrt(e.value), rTeto),
          ),
    ];
  }

  /// Empacotamento simples: o maior no centro, e cada seguinte procura em
  /// espiral o primeiro lugar livre.
  ///
  /// Não é o empacotamento ótimo — esse é um problema difícil e o ganho visual
  /// não pagaria a complexidade. O que importa aqui é não sobrepor e ficar
  /// agrupado, e a espiral entrega os dois de forma determinística: a mesma
  /// coleção desenha igual toda vez, sem "pular" a cada rebuild.
  void _empacota(List<_Bolha> bolhas, double largura) {
    if (bolhas.isEmpty) return;

    const folga = 4.0;
    final centro = Offset(largura / 2, 0);
    bolhas.first.centro = centro;

    for (var i = 1; i < bolhas.length; i++) {
      final b = bolhas[i];
      var achou = false;

      // Anéis crescentes, do mais perto para o mais longe, para o conjunto
      // ficar apertado em vez de espalhado. Passo fino: um passo grosso pula
      // encaixes válidos e joga o círculo longe sem necessidade.
      for (var raio = 8.0; raio < largura * 2 && !achou; raio += 3) {
        final passos = math.max(24, (raio / 2).round() * 4);
        for (var k = 0; k < passos; k++) {
          final ang = 2 * math.pi * k / passos;
          final p = centro + Offset(math.cos(ang) * raio, math.sin(ang) * raio);

          // Não pode vazar pelas laterais.
          if (p.dx - b.raio < 0 || p.dx + b.raio > largura) continue;

          final colide = bolhas.take(i).any((o) =>
              (p - o.centro).distance < b.raio + o.raio + folga);
          if (colide) continue;

          b.centro = p;
          achou = true;
          break;
        }
      }

      // Sem lugar na espiral: desce abaixo de **tudo** que já foi colocado.
      //
      // Antes eu descia só abaixo do círculo anterior, e era esse o bug das
      // capas sobrepostas: o anterior podia estar bem acima de outro maior,
      // e o novo caía em cima dele.
      if (!achou) {
        final maisBaixo = bolhas
            .take(i)
            .map((o) => o.centro.dy + o.raio)
            .reduce(math.max);
        b.centro = Offset(largura / 2, maisBaixo + b.raio + folga);
      }
    }

    // Sobe tudo para o topo do quadro ficar em zero.
    final topo = bolhas.map((b) => b.centro.dy - b.raio).reduce(math.min);
    for (final b in bolhas) {
      b.centro = Offset(b.centro.dx, b.centro.dy - topo);
    }
  }

  double _alturaNecessaria(List<_Bolha> bolhas) {
    if (bolhas.isEmpty) return 0;
    return bolhas.map((b) => b.centro.dy + b.raio).reduce(math.max) + 4;
  }
}

class _Circulo extends StatelessWidget {
  const _Circulo({
    required this.bolha,
    required this.selecionada,
    required this.onTap,
  });

  final _Bolha bolha;
  final bool selecionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final game = bolha.entry.game;

    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: '${bolha.entry.displayName} · '
            '${contagemPartidas(bolha.partidas)}',
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Anel na cor da superfície separa bolhas encostadas, em vez de
            // uma borda desenhada em volta de cada uma.
            border: Border.all(
              color: selecionada ? viz.inkPrimary : viz.surface,
              width: selecionada ? 3 : 2,
            ),
          ),
          // Só a capa: o tamanho do círculo já é a quantidade de partidas, e
          // escrever o número em cima seria dizer duas vezes a mesma coisa —
          // além de tapar justamente a arte que identifica o jogo. O número
          // continua na lista abaixo e ao tocar.
          child: ClipOval(
            child: GameCover(
              url: game.thumbUrl ?? game.imageUrl,
              name: game.displayName,
              borderRadius: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavegadorDeMes extends StatelessWidget {
  const _NavegadorDeMes({
    required this.mes,
    required this.partidas,
    required this.jogos,
    required this.onAnterior,
    required this.onProximo,
    this.soMesEAno = false,
  });

  final DateTime mes;
  final int partidas;
  final int jogos;
  final VoidCallback? onAnterior;
  final VoidCallback? onProximo;

  /// Modo imagem: só o mês e o ano.
  ///
  /// As setas somem porque são controles da tela — e a seta apagada de "não
  /// tem mês anterior" chegaria no WhatsApp parecendo defeito. O espaço delas
  /// fica, senão o título salta de lugar entre o que você vê e o que sai.
  ///
  /// A contagem de partidas some porque o tamanho dos círculos já é ela.
  final bool soMesEAno;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    return Row(
      children: [
        Visibility(
          visible: !soMesEAno,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: IconButton(
            onPressed: onAnterior,
            icon: const Icon(Icons.chevron_left),
            visualDensity: VisualDensity.compact,
            tooltip: 'Mês anterior com partida',
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                mesAnoLongo(mes),
                textAlign: TextAlign.center,
                // Na imagem o mês é o único texto, então ele é o título.
                style: soMesEAno
                    ? text.titleLarge?.copyWith(fontSize: 22)
                    : text.titleMedium?.copyWith(fontSize: 16),
              ),
              if (!soMesEAno)
                Text(
                  partidas == 0
                      ? 'sem partidas'
                      : '$partidas ${partidas == 1 ? 'partida' : 'partidas'} · '
                          '$jogos ${jogos == 1 ? 'jogo' : 'jogos'}',
                  style: text.labelSmall?.copyWith(color: viz.inkMuted),
                ),
            ],
          ),
        ),
        Visibility(
          visible: !soMesEAno,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: IconButton(
            onPressed: onProximo,
            icon: const Icon(Icons.chevron_right),
            visualDensity: VisualDensity.compact,
            tooltip: 'Próximo mês com partida',
          ),
        ),
      ],
    );
  }
}
