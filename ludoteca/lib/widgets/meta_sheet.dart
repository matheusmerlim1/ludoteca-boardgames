import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/format.dart';

/// Ajuste da régua de um ranking.
///
/// Sem uma régua, a barra mais longa é sempre "a pior" — mesmo numa coleção em
/// que todo jogo já se pagou. O número que separa bom de ruim é seu: quem joga
/// toda semana acha caro R$ 10 por partida, quem joga uma vez por mês acha
/// barato. Por isso ele é ajustável em vez de fixo no código.
class MetaSheet extends StatefulWidget {
  const MetaSheet({
    super.key,
    required this.titulo,
    required this.descricao,
    required this.sufixo,
    required this.inicial,
    required this.sugestoes,
  });

  final String titulo;
  final String descricao;

  /// O que vem depois do número: "por partida", "/mês", "/h".
  final String sufixo;

  /// Nulo = sem régua, as barras se comparam só entre si.
  final double? inicial;

  /// Atalhos para os valores mais prováveis, para não digitar no celular.
  final List<double> sugestoes;

  /// Devolve nulo se você fechou sem escolher, e `(valor: null)` se pediu para
  /// comparar sem régua. São desfechos diferentes — um `double?` sozinho
  /// confundiria "deixa como estava" com "tira a régua".
  static Future<({double? valor})?> show(
    BuildContext context, {
    required String titulo,
    required String descricao,
    required String sufixo,
    required double? inicial,
    required List<double> sugestoes,
  }) {
    return showModalBottomSheet<({double? valor})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MetaSheet(
        titulo: titulo,
        descricao: descricao,
        sufixo: sufixo,
        inicial: inicial,
        sugestoes: sugestoes,
      ),
    );
  }

  @override
  State<MetaSheet> createState() => _MetaSheetState();
}

class _MetaSheetState extends State<MetaSheet> {
  late final TextEditingController _campo = TextEditingController(
    text: widget.inicial == null ? '' : moedaParaCampo(widget.inicial!),
  );

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

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
            Text(widget.titulo, style: text.titleMedium),
            const SizedBox(height: 4),
            Text(widget.descricao, style: text.bodySmall),
            const SizedBox(height: 18),

            TextField(
              controller: _campo,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Minha régua',
                prefixText: 'R\$ ',
                suffixText: widget.sufixo,
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in widget.sugestoes)
                  ActionChip(
                    label: Text('${dinheiro(v, casas: 0)} ${widget.sufixo}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: () => setState(
                      () => _campo.text = moedaParaCampo(v),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                (valor: parseMoeda(_campo.text)),
              ),
              child: const Text('Usar esta régua'),
            ),
            // Tirar a régua é uma escolha legítima: sem ela as barras voltam a
            // se comparar só entre si, que é o comportamento de antes.
            TextButton(
              onPressed: () => Navigator.of(context).pop((valor: null)),
              child: const Text('Comparar sem régua'),
            ),
          ],
        ),
      ),
    );
  }
}
