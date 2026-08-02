import 'package:flutter/material.dart';

import '../models/game.dart';
import '../theme.dart';
import '../utils/format.dart';

/// O que foi decidido sobre a saída do jogo.
class DisposalResult {
  const DisposalResult({
    required this.tipo,
    this.valor,
    required this.quando,
    this.trocadoPorId,
  });

  final Disposal tipo;

  /// Só na venda. Em troca e doação não entra dinheiro.
  final double? valor;

  final DateTime quando;

  /// Só na troca: o jogo que entrou no lugar.
  final int? trocadoPorId;
}

/// Como o jogo saiu da coleção.
///
/// As três saídas mexem no dinheiro de formas diferentes, e é por isso que a
/// pergunta existe em vez de um "remover" seco:
///
/// - **vendido** devolve dinheiro, que abate o investimento;
/// - **trocado** transfere o valor investido para o jogo que entrou — ele foi
///   pago com o que você já tinha;
/// - **doado** não devolve nada; o que você gastou continua gasto.
class DisposalSheet extends StatefulWidget {
  const DisposalSheet({
    super.key,
    required this.game,
    required this.candidatos,
  });

  final Game game;

  /// Jogos que podem ter entrado na troca.
  final List<GameEntry> candidatos;

  static Future<DisposalResult?> show(
    BuildContext context, {
    required Game game,
    required List<GameEntry> candidatos,
  }) {
    return showModalBottomSheet<DisposalResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DisposalSheet(game: game, candidatos: candidatos),
    );
  }

  @override
  State<DisposalSheet> createState() => _DisposalSheetState();
}

class _DisposalSheetState extends State<DisposalSheet> {
  Disposal _tipo = Disposal.vendido;
  DateTime _quando = soData(DateTime.now());
  int? _trocadoPor;

  late final TextEditingController _valor = TextEditingController(
    text: moedaParaCampo(widget.game.totalInvested),
  );

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final investido = widget.game.totalInvested;

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
              '${widget.game.displayName} · investido ${dinheiro(investido)}',
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
                  'Os ${dinheiro(investido)} deste jogo passam para o jogo '
                      'que entrou — ele foi pago com o que você já tinha.',
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

            if (_tipo == Disposal.trocado) ...[
              if (widget.candidatos.isEmpty)
                Text(
                  'Cadastre primeiro o jogo que você recebeu; depois volte '
                  'aqui para apontar a troca.',
                  style: text.bodySmall,
                )
              else
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Recebi qual jogo?',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _trocadoPor,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Não vou apontar agora'),
                        ),
                        for (final e in widget.candidatos)
                          DropdownMenuItem<int?>(
                            value: e.game.id,
                            child: Text(
                              e.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _trocadoPor = v),
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _escolherData,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text('Quando: ${data(_quando)}'),
            ),

            const SizedBox(height: 20),
            FilledButton(
              onPressed: _confirmar,
              child: Text('Marcar como ${_tipo.label.toLowerCase()}'),
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
        trocadoPorId: _tipo == Disposal.trocado ? _trocadoPor : null,
      ),
    );
  }
}
