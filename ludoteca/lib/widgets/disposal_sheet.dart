import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game.dart';
import '../models/trade.dart';
import '../screens/add_game_screen.dart';
import '../state/collection_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'game_cover.dart';
import 'pick_game_sheet.dart';

/// O que foi decidido sobre a saída do jogo.
class DisposalResult {
  const DisposalResult({
    required this.tipo,
    this.valor,
    required this.quando,
    this.saindo = const [],
    this.entrando = const [],
  });

  final Disposal tipo;

  /// Só na venda. Em troca e doação não entra dinheiro.
  final double? valor;

  final DateTime quando;

  /// Só na troca: todos os jogos que saíram, incluindo o da ficha.
  final List<Game> saindo;

  /// Só na troca: os jogos que entraram, com o valor de cada um.
  final List<TrocaEntrada> entrando;
}

/// Como o jogo saiu da coleção.
///
/// As três saídas mexem no dinheiro de formas diferentes, e é por isso que a
/// pergunta existe em vez de um "remover" seco:
///
/// - **vendido** devolve dinheiro, que abate o investimento;
/// - **trocado** distribui o valor investido entre os jogos que entraram — eles
///   foram pagos com o que você já tinha;
/// - **doado** não devolve nada; o que você gastou continua gasto.
///
/// A troca é N por M porque é assim que ela acontece: um jogo grande vira dois
/// menores, ou três juntos viram um. E o jogo que chega quase nunca está
/// cadastrado — a folha deixa cadastrar na hora, sem perder o que já foi
/// preenchido aqui.
class DisposalSheet extends StatefulWidget {
  const DisposalSheet({super.key, required this.game});

  final Game game;

  static Future<DisposalResult?> show(
    BuildContext context, {
    required Game game,
  }) {
    return showModalBottomSheet<DisposalResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DisposalSheet(game: game),
    );
  }

  @override
  State<DisposalSheet> createState() => _DisposalSheetState();
}

/// Um jogo que entrou, com o campo do valor que serve de peso no rateio.
class _Entrada {
  _Entrada({required this.game, required double valor})
      : controller = TextEditingController(text: moedaParaCampo(valor));

  final Game game;
  final TextEditingController controller;

  double get valor => parseMoedaOuZero(controller.text);
}

class _DisposalSheetState extends State<DisposalSheet> {
  Disposal _tipo = Disposal.vendido;
  DateTime _quando = soData(DateTime.now());

  late final List<Game> _saindo = [widget.game];
  final List<_Entrada> _entrando = [];

  late final TextEditingController _valor = TextEditingController(
    text: moedaParaCampo(widget.game.totalInvested),
  );

  @override
  void dispose() {
    _valor.dispose();
    for (final e in _entrando) {
      e.controller.dispose();
    }
    super.dispose();
  }

  /// O investimento somado de tudo que está saindo. É este valor que se divide.
  double get _totalSaindo =>
      _saindo.fold(0.0, (s, g) => s + g.totalInvested);

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

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
            Text('Saiu da coleção', style: text.titleMedium),
            const SizedBox(height: 2),
            Text(
              '${widget.game.displayName} · investido '
              '${dinheiro(widget.game.totalInvested)}',
              style: text.bodySmall,
            ),
            const SizedBox(height: 18),

            SegmentedButton<Disposal>(
              segments: const [
                ButtonSegment(value: Disposal.vendido, label: Text('Vendi')),
                ButtonSegment(value: Disposal.trocado, label: Text('Troquei')),
                ButtonSegment(value: Disposal.doado, label: Text('Doei')),
              ],
              selected: {_tipo},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _tipo = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              switch (_tipo) {
                Disposal.vendido =>
                  'O valor recebido abate o total investido na coleção.',
                Disposal.trocado =>
                  'O investido nos jogos que saíram se divide entre os que '
                      'entraram, na proporção do que cada um vale.',
                Disposal.doado =>
                  'Nada volta. O que você gastou continua contado como gasto.',
              },
              style: text.labelSmall?.copyWith(color: viz.inkMuted),
            ),
            const SizedBox(height: 18),

            if (_tipo == Disposal.vendido)
              TextField(
                controller: _valor,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Vendido por',
                  prefixText: 'R\$ ',
                  isDense: true,
                ),
              ),

            if (_tipo == Disposal.trocado) _troca(text, viz),

            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _escolherData,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text('Quando: ${data(_quando)}'),
            ),

            const SizedBox(height: 20),
            FilledButton(
              onPressed: _confirmar,
              child: Text(
                _tipo == Disposal.trocado
                    ? 'Registrar a troca'
                    : 'Marcar como ${_tipo.label.toLowerCase()}',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- troca

  Widget _troca(TextTheme text, VizColors viz) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Rotulo(texto: 'SAÍRAM', nota: dinheiro(_totalSaindo)),
        const SizedBox(height: 8),
        for (final g in _saindo)
          _LinhaJogo(
            game: g,
            detalhe: 'investido ${dinheiro(g.totalInvested)}',
            // O jogo da ficha é o motivo de a folha estar aberta; tirá-lo daqui
            // deixaria uma troca sem dono, e a ficha marcaria a saída de um
            // jogo que não saiu.
            onRemover: g.id == widget.game.id
                ? null
                : () => setState(() => _saindo.remove(g)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _adicionarSaindo,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Outro jogo meu foi junto'),
          ),
        ),

        const SizedBox(height: 10),
        _Rotulo(
          texto: 'ENTRARAM',
          nota: _entrando.isEmpty ? null : '${_entrando.length}',
        ),
        const SizedBox(height: 8),

        if (_entrando.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Se o jogo que você recebeu ainda não está cadastrado, use '
              '"Cadastrar o jogo que recebi" — ele já entra aqui.',
              style: text.labelSmall?.copyWith(color: viz.inkMuted),
            ),
          )
        else
          for (final e in _entrando)
            _LinhaEntrada(
              entrada: e,
              onMudou: () => setState(() {}),
              onRemover: () => setState(() {
                _entrando.remove(e);
                e.controller.dispose();
              }),
            ),

        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: _escolherEntrando,
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('Da coleção'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: _cadastrarEntrando,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Cadastrar'),
              ),
            ),
          ],
        ),

        if (_entrando.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Rateio(total: _totalSaindo, entradas: _entrando),
        ],
      ],
    );
  }

  /// Os jogos que podem entrar ou sair: o que está na estante, menos quem já
  /// está nesta troca e menos o que já tinha saído.
  List<GameEntry> _candidatos({required bool paraEntrar}) {
    final store = context.read<CollectionStore>();
    final jaEscolhidos = {
      ..._saindo.map((g) => g.id),
      ..._entrando.map((e) => e.game.id),
    };

    return store.allEntries.where((e) {
      if (jaEscolhidos.contains(e.game.id)) return false;
      if (e.game.isGrouped) return false;
      // Quem entra pode estar na lista de desejos — receber numa troca é
      // justamente como um desejado deixa de ser desejo. Quem sai tem de ser
      // seu e estar na estante.
      if (paraEntrar) return !e.game.isGone;
      return e.game.isMine && !e.game.isGone;
    }).toList();
  }

  Future<void> _adicionarSaindo() async {
    final escolha = await PickGameSheet.show(
      context,
      entries: _candidatos(paraEntrar: false),
      titulo: 'Qual outro jogo saiu na troca?',
      mostrarEscape: false,
      porNome: true,
    );
    final entry = escolha?.entry;
    if (entry == null || !mounted) return;
    setState(() => _saindo.add(entry.game));
  }

  Future<void> _escolherEntrando() async {
    final escolha = await PickGameSheet.show(
      context,
      entries: _candidatos(paraEntrar: true),
      titulo: 'Qual jogo entrou na troca?',
      escapeTitulo: 'Cadastrar o jogo que recebi',
      escapeSubtitulo: 'Busca no catálogo e volta para cá',
      escapeIcone: Icons.add_circle_outline,
      porNome: true,
    );
    if (escolha == null || !mounted) return;

    if (escolha.buscarNoCatalogo) {
      await _cadastrarEntrando();
      return;
    }
    _incluiEntrada(escolha.entry!.game);
  }

  /// Cadastra na hora o jogo que chegou.
  ///
  /// Este é o caminho normal, não a exceção: o jogo que você recebeu numa troca
  /// nunca esteve na sua coleção. Antes a folha só listava o que você já tinha,
  /// e a troca acabava não sendo registrada.
  Future<void> _cadastrarEntrando() async {
    final novoId = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        // O aviso do fim da troca é que conta o que aconteceu; um "entrou na
        // coleção" no meio do caminho falaria do passo, não do resultado.
        builder: (_) => const AddGameScreen(anunciarSalvo: false),
      ),
    );
    if (novoId == null || !mounted) return;

    final store = context.read<CollectionStore>();
    await store.refresh();
    if (!mounted) return;

    final entry = store.entryById(novoId);
    if (entry != null) _incluiEntrada(entry.game);
  }

  void _incluiEntrada(Game g) {
    setState(() {
      _entrando.add(_Entrada(game: g, valor: g.price));
    });
  }

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _quando,
      firstDate: DateTime(1990),
      lastDate: soData(DateTime.now()),
    );
    if (d != null) setState(() => _quando = soData(d));
  }

  void _confirmar() {
    Navigator.of(context).pop(
      DisposalResult(
        tipo: _tipo,
        // Valor só na venda: gravar um número em troca ou doação faria o app
        // contar como recuperado um dinheiro que nunca entrou.
        valor: _tipo == Disposal.vendido ? parseMoeda(_valor.text) : null,
        quando: _quando,
        saindo: _tipo == Disposal.trocado ? List.of(_saindo) : const [],
        entrando: _tipo == Disposal.trocado
            ? [
                for (final e in _entrando)
                  TrocaEntrada(gameId: e.game.id!, valorReferencia: e.valor),
              ]
            : const [],
      ),
    );
  }
}

/// Como o valor vai ficar dividido, com o número já feito.
///
/// Mostrar o resultado antes de confirmar é o que torna a regra checável: você
/// vê "375 e 125" e reconhece (ou corrige) a proporção, em vez de descobrir
/// dias depois que o custo por partida de um dos jogos ficou estranho.
class _Rateio extends StatelessWidget {
  const _Rateio({required this.total, required this.entradas});

  final double total;
  final List<_Entrada> entradas;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    final partes = rateio(total, [for (final e in entradas) e.valor]);
    final semValor = entradas.every((e) => e.valor <= 0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: viz.page,
        border: Border.all(color: viz.gridline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${dinheiro(total)} vão se dividir assim:',
            style: text.labelSmall?.copyWith(color: viz.inkSecondary),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < entradas.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entradas[i].game.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ),
                  Text(
                    total <= 0
                        ? dinheiro(0)
                        : '${dinheiro(partes[i])}  ·  '
                            '${porcento(partes[i] / total)}',
                    style: text.bodySmall?.copyWith(
                      color: viz.inkPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (semValor && entradas.length > 1) ...[
            const SizedBox(height: 6),
            Text(
              'Nenhum dos jogos que entraram tem valor, então a divisão é em '
              'partes iguais. Preencha o quanto cada um vale para dividir na '
              'proporção certa.',
              style: text.labelSmall?.copyWith(color: viz.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Rotulo extends StatelessWidget {
  const _Rotulo({required this.texto, this.nota});

  final String texto;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Text(
          texto,
          style: text.labelSmall?.copyWith(
            color: viz.inkSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: viz.gridline)),
        if (nota != null) ...[
          const SizedBox(width: 8),
          Text(nota!, style: text.labelSmall?.copyWith(color: viz.inkMuted)),
        ],
      ],
    );
  }
}

class _LinhaJogo extends StatelessWidget {
  const _LinhaJogo({
    required this.game,
    required this.detalhe,
    this.onRemover,
  });

  final Game game;
  final String detalhe;
  final VoidCallback? onRemover;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 34,
            child: GameCover(
              url: game.thumbUrl ?? game.imageUrl,
              name: game.displayName,
              borderRadius: 4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
                Text(
                  detalhe,
                  style: text.labelSmall?.copyWith(color: viz.inkMuted),
                ),
              ],
            ),
          ),
          if (onRemover != null)
            IconButton(
              onPressed: onRemover,
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
              tooltip: 'Tirar da troca',
            ),
        ],
      ),
    );
  }
}

class _LinhaEntrada extends StatelessWidget {
  const _LinhaEntrada({
    required this.entrada,
    required this.onMudou,
    required this.onRemover,
  });

  final _Entrada entrada;
  final VoidCallback onMudou;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 34,
            child: GameCover(
              url: entrada.game.thumbUrl ?? entrada.game.imageUrl,
              name: entrada.game.displayName,
              borderRadius: 4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entrada.game.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: TextField(
              controller: entrada.controller,
              onChanged: (_) => onMudou(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'vale',
                prefixText: 'R\$ ',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            onPressed: onRemover,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Tirar da troca',
          ),
        ],
      ),
    );
  }
}
