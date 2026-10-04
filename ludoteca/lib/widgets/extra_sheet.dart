import 'package:flutter/material.dart';

import '../models/extra.dart';
import '../theme.dart';
import '../utils/format.dart';

/// Desfecho da folha: o extra gravado, ou o pedido de apagá-lo.
typedef ExtraResultado = ({Extra? salvo, bool apagar});

/// Cadastro de uma compra avulsa — kit de sleeves, playmat, organizador.
///
/// Não pede jogo nenhum de propósito: é exatamente o que separa um extra do
/// campo "sleeves" da ficha do jogo. A data já vem como hoje, porque quase
/// sempre o extra é cadastrado no dia da compra, e é a data que decide em que
/// mês ele entra.
class ExtraSheet extends StatefulWidget {
  const ExtraSheet({super.key, this.inicial});

  /// Nulo = extra novo.
  final Extra? inicial;

  static Future<ExtraResultado?> show(BuildContext context, {Extra? inicial}) {
    return showModalBottomSheet<ExtraResultado>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ExtraSheet(inicial: inicial),
    );
  }

  @override
  State<ExtraSheet> createState() => _ExtraSheetState();
}

class _ExtraSheetState extends State<ExtraSheet> {
  final _form = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.inicial?.name ?? '');
  late final _preco = TextEditingController(
    text: widget.inicial == null || widget.inicial!.price == 0
        ? ''
        : dinheiro(widget.inicial!.price, simbolo: false),
  );
  late final _notas = TextEditingController(text: widget.inicial?.notes ?? '');
  late ExtraKind _tipo = widget.inicial?.kind ?? ExtraKind.sleeves;
  late DateTime? _data =
      widget.inicial == null ? soData(DateTime.now()) : widget.inicial!.purchaseDate;

  bool get _editando => widget.inicial?.id != null;

  @override
  void dispose() {
    _nome.dispose();
    _preco.dispose();
    _notas.dispose();
    super.dispose();
  }

  void _salvar() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final nome = _nome.text.trim().isEmpty ? _tipo.label : _nome.text.trim();
    final extra = Extra(
      id: widget.inicial?.id,
      name: nome,
      kind: _tipo,
      price: parseMoedaOuZero(_preco.text),
      purchaseDate: _data,
      notes: _notas.text.trim().isEmpty ? null : _notas.text.trim(),
    );
    Navigator.of(context).pop<ExtraResultado>((salvo: extra, apagar: false));
  }

  Future<void> _apagar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar este extra?'),
        content: Text('“${widget.inicial!.name}” sai dos gastos e do custo do mês.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop<ExtraResultado>((salvo: null, apagar: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
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
            Text(
              _editando ? 'Editar extra' : 'Novo extra',
              style: text.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Compra que não é de um jogo só — um kit de sleeves, um playmat, '
              'uma caixa organizadora. Entra no custo do mês da data de compra.',
              style: text.bodySmall?.copyWith(color: viz.inkMuted),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final k in ExtraKind.values)
                  ChoiceChip(
                    avatar: Icon(k.icon, size: 18),
                    label: Text(k.label),
                    selected: _tipo == k,
                    onSelected: (_) => setState(() => _tipo = k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nome,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nome',
                hintText: 'Ex.: ${_tipo == ExtraKind.playmat ? 'Playmat neoprene 60×35' : 'Kit 100 sleeves 63,5×88'}',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _preco,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Preço', prefixText: 'R\$ '),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Informe quanto custou';
                return parseMoeda(v) == null ? 'Valor inválido' : null;
              },
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Data da compra',
                helperText: 'Decide em que mês o gasto entra.',
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _data == null ? 'não informada' : data(_data!),
                      style: text.bodyMedium?.copyWith(
                        color: _data == null ? viz.inkMuted : viz.inkPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    tooltip: 'Escolher data',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _data ?? soData(DateTime.now()),
                        firstDate: DateTime(1980),
                        lastDate: soData(DateTime.now()),
                        helpText: 'Data da compra',
                      );
                      if (d != null) setState(() => _data = soData(d));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notas,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Anotação (opcional)'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_editando)
                  TextButton.icon(
                    onPressed: _apagar,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Apagar'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _salvar,
                  child: Text(_editando ? 'Salvar' : 'Adicionar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
