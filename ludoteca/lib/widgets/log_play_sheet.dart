import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game.dart';
import '../models/play.dart';
import '../models/play_score.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'score_editor.dart';

/// Como a duração da partida foi informada.
enum _ModoDuracao {
  /// Não informou: vale a duração média do jogo. É o padrão, de propósito.
  media,

  /// Digitou os minutos direto.
  minutos,

  /// Marcou a hora de início e de fim, e o app calcula.
  inicioFim,
}

/// Folha de registro de partida.
///
/// Feita para o caso real: você acabou de jogar e quer lançar em dois toques.
/// A data já vem hoje, o número de jogadores já vem no valor mais provável e a
/// duração já vem como "a média do jogo" — então "Salvar" direto costuma ser o
/// suficiente. Cronometrar é opcional e fica atrás de uma escolha explícita.
class LogPlaySheet extends StatefulWidget {
  const LogPlaySheet({
    super.key,
    required this.game,
    this.existing,
    this.itens = const [],
    this.placarInicial = const [],
    this.sugestoesDeNome = const [],
  });

  final Game game;

  /// Quando presente, a folha edita a partida em vez de criar uma nova.
  final Play? existing;

  /// Caixas agrupadas sob este jogo, quando houver.
  ///
  /// Num Unmatched com seis caixas, a partida é lançada no grupo e você marca
  /// qual caixa foi à mesa. Marcar é opcional — o que importa para a contagem
  /// é a partida, e obrigar a escolher travaria o lançamento rápido.
  final List<Game> itens;

  /// Placar já gravado, ao editar uma partida.
  final List<PlayScore> placarInicial;

  /// Nomes usados antes, para sugerir sem redigitar.
  final List<String> sugestoesDeNome;

  static Future<({Play play, List<PlayScore> placar})?> show(
    BuildContext context, {
    required Game game,
    Play? existing,
    List<Game> itens = const [],
    List<PlayScore> placarInicial = const [],
    List<String> sugestoesDeNome = const [],
  }) {
    return showModalBottomSheet<({Play play, List<PlayScore> placar})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LogPlaySheet(
        game: game,
        existing: existing,
        itens: itens,
        placarInicial: placarInicial,
        sugestoesDeNome: sugestoesDeNome,
      ),
    );
  }

  @override
  State<LogPlaySheet> createState() => _LogPlaySheetState();
}

class _LogPlaySheetState extends State<LogPlaySheet> {
  late DateTime _date;
  late int? _players;
  late TextEditingController _winner;
  late TextEditingController _notes;
  late TextEditingController _minutos;

  late _ModoDuracao _modo;
  TimeOfDay? _inicio;
  TimeOfDay? _fim;

  /// Caixa do grupo que foi jogada. Nulo = não detalhou.
  int? _itemId;

  late List<PlayScore> _placar = widget.placarInicial;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    _date = e?.playedAt ?? soData(DateTime.now());
    _players = e?.players ?? widget.game.bestPlayers ?? widget.game.minPlayers;
    _winner = TextEditingController(text: e?.winner ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');

    // Editando uma partida cronometrada, a folha abre em "digitar minutos".
    // O app guarda a duração, não o par início/fim — aquele é só um jeito de
    // chegar no número.
    _minutos = TextEditingController(
      text: e?.durationMinutes == null ? '' : '${e!.durationMinutes}',
    );
    _modo = e?.durationMinutes == null
        ? _ModoDuracao.media
        : _ModoDuracao.minutos;

    _itemId = e?.itemGameId;
  }

  @override
  void dispose() {
    _winner.dispose();
    _notes.dispose();
    _minutos.dispose();
    super.dispose();
  }

  /// Os minutos que serão gravados. Nulo = "usa a média do jogo".
  int? get _duracaoFinal {
    switch (_modo) {
      case _ModoDuracao.media:
        return null;
      case _ModoDuracao.minutos:
        final n = parseInteiro(_minutos.text);
        return (n == null || n <= 0) ? null : n;
      case _ModoDuracao.inicioFim:
        return _duracaoDeInicioFim();
    }
  }

  int? _duracaoDeInicioFim() {
    final i = _inicio;
    final f = _fim;
    if (i == null || f == null) return null;

    var mins = (f.hour * 60 + f.minute) - (i.hour * 60 + i.minute);
    // "Começamos 22h, terminamos 1h" — a partida atravessou a meia-noite.
    if (mins <= 0) mins += 24 * 60;
    return mins;
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final game = widget.game;

    final min = game.minPlayers ?? 1;
    final max = (game.maxPlayers ?? 8).clamp(min, 12);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
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
            const SizedBox(height: 16),
            Text(
              widget.existing == null ? 'Registrar partida' : 'Editar partida',
              style: text.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(game.displayName, style: text.bodySmall),
            const SizedBox(height: 20),

            Text('Quando', style: text.labelSmall),
            const SizedBox(height: 6),
            Row(
              children: [
                _Chip(
                  label: 'Hoje',
                  selected: _mesmoDia(_date, DateTime.now()),
                  onTap: () => setState(() => _date = soData(DateTime.now())),
                ),
                _Chip(
                  label: 'Ontem',
                  selected: _mesmoDia(
                    _date,
                    DateTime.now().subtract(const Duration(days: 1)),
                  ),
                  onTap: () => setState(
                    () => _date = soData(
                      DateTime.now().subtract(const Duration(days: 1)),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _escolherData,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(data(_date)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Só aparece quando o jogo agrupa caixas. Um jogo comum não ganha
            // um campo a mais por causa do Unmatched.
            if (widget.itens.isNotEmpty) ...[
              Text('Qual caixa você jogou', style: text.labelSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Não especificar'),
                    selected: _itemId == null,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _itemId = null),
                  ),
                  for (final item in widget.itens)
                    ChoiceChip(
                      label: Text(_nomeCurto(item)),
                      selected: _itemId == item.id,
                      showCheckmark: false,
                      onSelected: (_) => setState(
                        () => _itemId = _itemId == item.id ? null : item.id,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
            ],

            Text('Quantos jogaram', style: text.labelSmall),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var n = min; n <= max; n++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('$n'),
                        selected: _players == n,
                        showCheckmark: false,
                        onSelected: (_) => setState(
                          () => _players = _players == n ? null : n,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            _SecaoDuracao(
              game: game,
              modo: _modo,
              minutosController: _minutos,
              inicio: _inicio,
              fim: _fim,
              duracaoCalculada: _duracaoFinal,
              onModo: (m) => setState(() => _modo = m),
              onMinutosMudou: () => setState(() {}),
              onInicio: (t) => setState(() => _inicio = t),
              onFim: (t) => setState(() => _fim = t),
            ),
            const SizedBox(height: 18),

            ScoreEditor(
              inicial: widget.placarInicial,
              sugestoes: widget.sugestoesDeNome,
              onChanged: (p) => _placar = p,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _winner,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Quem ganhou, em uma linha (opcional)',
                helperText: 'Use se não quiser preencher o placar acima.',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Anotações (opcional)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 22),

            FilledButton(
              onPressed: _salvar,
              child: Text(widget.existing == null ? 'Salvar partida' : 'Salvar'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Tira o prefixo do jogo-pai do nome da caixa.
  ///
  /// "Unmatched: Robin Hood vs Pé-Grande" dentro de "Unmatched" vira só
  /// "Robin Hood vs Pé-Grande" — repetir o nome do grupo em todo chip gasta a
  /// largura da tela sem informar nada.
  String _nomeCurto(Game item) {
    final pai = widget.game.displayName;
    var nome = item.displayName;

    if (nome.toLowerCase().startsWith(pai.toLowerCase())) {
      nome = nome.substring(pai.length).trim();
      // Sobra a pontuação que separava: ": ", " – ", " - ".
      nome = nome.replaceFirst(RegExp(r'^[:\-–—]\s*'), '').trim();
    }

    return nome.isEmpty ? item.displayName : nome;
  }

  bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1990),
      // Partida no futuro não existe.
      lastDate: soData(DateTime.now()),
      helpText: 'Data da partida',
    );
    if (escolhida != null) setState(() => _date = soData(escolhida));
  }

  void _salvar() {
    final winner = _winner.text.trim();
    final notes = _notes.text.trim();

    // O campo de texto "quem ganhou" e o placar convivem: quem preencheu o
    // placar não precisa repetir o nome ali, e quem só quer anotar rápido não
    // precisa montar um placar inteiro.
    final vencedoresDoPlacar =
        _placar.where((s) => s.won).map((s) => s.playerName).toList();

    Navigator.of(context).pop((
      placar: _placar,
      play: Play(
        id: widget.existing?.id,
        gameId: widget.game.id!,
        playedAt: _date,
        players: _players,
        // Se você marcou o vencedor no placar, o campo de texto é preenchido
        // sozinho — a ficha e o histórico leem daqui.
        winner: winner.isNotEmpty
            ? winner
            : (vencedoresDoPlacar.isEmpty
                ? null
                : vencedoresDoPlacar.join(', ')),
        notes: notes.isEmpty ? null : notes,
        durationMinutes: _duracaoFinal,
        itemGameId: _itemId,
      ),
    ));
  }
}

/// A parte da duração.
///
/// O modo "média" é o primeiro e vem selecionado: cronometrar toda partida é
/// trabalho que a maioria não quer, e a duração média do BGG já dá um número
/// bom o suficiente para custo por hora.
class _SecaoDuracao extends StatelessWidget {
  const _SecaoDuracao({
    required this.game,
    required this.modo,
    required this.minutosController,
    required this.inicio,
    required this.fim,
    required this.duracaoCalculada,
    required this.onModo,
    required this.onMinutosMudou,
    required this.onInicio,
    required this.onFim,
  });

  final Game game;
  final _ModoDuracao modo;
  final TextEditingController minutosController;
  final TimeOfDay? inicio;
  final TimeOfDay? fim;
  final int? duracaoCalculada;
  final ValueChanged<_ModoDuracao> onModo;
  final VoidCallback onMinutosMudou;
  final ValueChanged<TimeOfDay?> onInicio;
  final ValueChanged<TimeOfDay?> onFim;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final medio = game.averagePlaytime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Duração', style: text.labelSmall),
            const SizedBox(width: 6),
            Text(
              '(opcional)',
              style: text.labelSmall?.copyWith(color: viz.inkMuted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<_ModoDuracao>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: _ModoDuracao.media,
              label: Text(medio == null ? 'Média' : 'Média (${duracao(medio)})'),
            ),
            const ButtonSegment(
              value: _ModoDuracao.minutos,
              label: Text('Minutos'),
            ),
            const ButtonSegment(
              value: _ModoDuracao.inicioFim,
              label: Text('Início e fim'),
            ),
          ],
          selected: {modo},
          onSelectionChanged: (s) => onModo(s.first),
        ),
        const SizedBox(height: 10),
        switch (modo) {
          _ModoDuracao.media => _AvisoMedia(medio: medio),
          _ModoDuracao.minutos => _CampoMinutos(
              controller: minutosController,
              game: game,
              onMudou: onMinutosMudou,
            ),
          _ModoDuracao.inicioFim => _CamposInicioFim(
              inicio: inicio,
              fim: fim,
              minutos: duracaoCalculada,
              onInicio: onInicio,
              onFim: onFim,
            ),
        },
      ],
    );
  }
}

class _AvisoMedia extends StatelessWidget {
  const _AvisoMedia({required this.medio});

  final int? medio;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(Icons.info_outline, size: 14, color: viz.inkMuted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            medio == null
                ? 'Este jogo não tem duração cadastrada, então esta partida '
                    'não vai contar horas. Preencha a duração no cadastro do '
                    'jogo, ou informe os minutos aqui.'
                : 'Vai contar como ${duracao(medio!)}, a média deste jogo. '
                    'Não precisa cronometrar nada.',
            style: text.labelSmall?.copyWith(color: viz.inkMuted),
          ),
        ),
      ],
    );
  }
}

class _CampoMinutos extends StatelessWidget {
  const _CampoMinutos({
    required this.controller,
    required this.game,
    required this.onMudou,
  });

  final TextEditingController controller;
  final Game game;
  final VoidCallback onMudou;

  @override
  Widget build(BuildContext context) {
    // Atalhos com a faixa do próprio jogo: quase sempre a partida cai perto
    // de um desses, e o teclado não precisa aparecer.
    final atalhos = <int>{
      if (game.minPlaytime != null) game.minPlaytime!,
      if (game.averagePlaytime != null) game.averagePlaytime!,
      if (game.maxPlaytime != null) game.maxPlaytime!,
    }.toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => onMudou(),
          decoration: const InputDecoration(
            labelText: 'Quanto durou',
            suffixText: 'min',
            isDense: true,
          ),
        ),
        if (atalhos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final m in atalhos)
                ActionChip(
                  label: Text(duracao(m)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    controller.text = '$m';
                    onMudou();
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CamposInicioFim extends StatelessWidget {
  const _CamposInicioFim({
    required this.inicio,
    required this.fim,
    required this.minutos,
    required this.onInicio,
    required this.onFim,
  });

  final TimeOfDay? inicio;
  final TimeOfDay? fim;

  /// Minutos já calculados a partir das duas horas. Nome não é `duracao` para
  /// não sombrear a função de formatação com o mesmo nome.
  final int? minutos;

  final ValueChanged<TimeOfDay?> onInicio;
  final ValueChanged<TimeOfDay?> onFim;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _BotaoHora(
                rotulo: 'Começou',
                valor: inicio,
                onEscolher: onInicio,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BotaoHora(
                rotulo: 'Terminou',
                valor: fim,
                onEscolher: onFim,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              minutos == null ? Icons.info_outline : Icons.timer_outlined,
              size: 14,
              color: minutos == null ? viz.inkMuted : viz.serie(0),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                minutos == null
                    ? 'Marque as duas horas para o app calcular.'
                    : 'Deu ${duracao(minutos!)}.'
                        // Passou de 12h provavelmente é hora invertida, não
                        // uma maratona — vale conferir antes de salvar.
                        '${minutos! > 12 * 60 ? ' Confira se as horas estão certas.' : ''}',
                style: text.labelSmall?.copyWith(
                  color: minutos == null ? viz.inkMuted : viz.inkSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BotaoHora extends StatelessWidget {
  const _BotaoHora({
    required this.rotulo,
    required this.valor,
    required this.onEscolher,
  });

  final String rotulo;
  final TimeOfDay? valor;
  final ValueChanged<TimeOfDay?> onEscolher;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: valor ?? TimeOfDay.now(),
          helpText: rotulo,
        );
        if (t != null) onEscolher(t);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rotulo, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            valor == null
                ? '--:--'
                : '${valor!.hour.toString().padLeft(2, '0')}:'
                    '${valor!.minute.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
