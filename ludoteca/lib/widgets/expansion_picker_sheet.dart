import 'package:flutter/material.dart';

import '../models/game.dart';
import '../services/game_catalog.dart';
import '../theme.dart';

/// Escolha de quais itens relacionados entram na coleção, e como.
///
/// A lista é o que **existe** no catálogo, não o que você tem. Marvel Champions
/// tem dezenas de pacotes; adicionar tudo automaticamente encheria a estante de
/// coisa que você não possui e, pior, sujaria os custos — cada item soma no
/// investimento do jogo-base. Então nada entra sem marcação explícita.
///
/// O **tipo** do vínculo também é escolhido aqui, porque o catálogo não
/// distingue os dois casos e quem tem o jogo na estante distingue:
///
/// - *expansão* não joga sozinha (um Hero Pack precisa da caixa base);
/// - *caixa da mesma série* joga sozinha, mas você quer tratar como um jogo só
///   — Unmatched é o caso clássico, com cada caixa completa e ninguém querendo
///   seis linhas de "Unmatched" na estante.
class ExpansionPickerSheet extends StatefulWidget {
  const ExpansionPickerSheet({
    super.key,
    required this.gameName,
    required this.expansions,
  });

  final String gameName;
  final List<CatalogExpansionRef> expansions;

  /// Devolve os itens marcados e **como** eles se vinculam ao jogo, ou nulo se
  /// o usuário fechou sem escolher.
  ///
  /// O tipo é escolhido aqui porque é aqui que a informação existe: o catálogo
  /// lista tudo como "expansão", mas quem sabe se aquela caixa joga sozinha é
  /// quem tem o jogo na estante.
  static Future<({List<CatalogExpansionRef> itens, LinkKind tipo})?> show(
    BuildContext context, {
    required String gameName,
    required List<CatalogExpansionRef> expansions,
  }) {
    return showModalBottomSheet<({List<CatalogExpansionRef> itens, LinkKind tipo})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ExpansionPickerSheet(
        gameName: gameName,
        expansions: expansions,
      ),
    );
  }

  @override
  State<ExpansionPickerSheet> createState() => _ExpansionPickerSheetState();
}

class _ExpansionPickerSheetState extends State<ExpansionPickerSheet> {
  final _marcadas = <int>{};
  final _busca = TextEditingController();
  String _filtro = '';

  /// Expansão é o caso comum, então é o padrão.
  LinkKind _tipo = LinkKind.expansao;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  List<CatalogExpansionRef> get _visiveis {
    if (_filtro.isEmpty) return widget.expansions;
    final t = _filtro.toLowerCase();
    return widget.expansions
        .where((e) => e.name.toLowerCase().contains(t))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final total = widget.expansions.length;
    final visiveis = _visiveis;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  const SizedBox(height: 14),
                  Text('Itens de ${widget.gameName}',
                      style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    'O catálogo conhece $total ${total == 1 ? 'item' : 'itens'} '
                    'ligados a este jogo. Marque só os que você tem.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Text('Estes itens são', style: text.labelSmall),
                  const SizedBox(height: 6),
                  SegmentedButton<LinkKind>(
                    segments: const [
                      ButtonSegment(
                        value: LinkKind.expansao,
                        label: Text('Expansões'),
                      ),
                      ButtonSegment(
                        value: LinkKind.serie,
                        label: Text('Caixas da série'),
                      ),
                    ],
                    selected: {_tipo},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    onSelectionChanged: (s) => setState(() => _tipo = s.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _tipo == LinkKind.expansao
                        ? 'Precisam do jogo-base para jogar.'
                        : 'Cada caixa joga sozinha, mas todas contam como um '
                            'jogo só na estante — o caso do Unmatched.',
                    style: text.labelSmall?.copyWith(color: viz.inkMuted),
                  ),
                  const SizedBox(height: 12),
                  if (total > 8)
                    TextField(
                      controller: _busca,
                      onChanged: (v) => setState(() => _filtro = v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Filtrar',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        suffixIcon: _filtro.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _busca.clear();
                                  setState(() => _filtro = '');
                                },
                              ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: viz.gridline),
            Expanded(
              child: visiveis.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Nenhum item com "$_filtro".',
                          style: text.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: visiveis.length,
                      itemBuilder: (context, i) {
                        final e = visiveis[i];
                        final marcada = _marcadas.contains(e.id);
                        return CheckboxListTile(
                          value: marcada,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _marcadas.add(e.id);
                            } else {
                              _marcadas.remove(e.id);
                            }
                          }),
                          title: Text(e.name, style: text.bodyMedium),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: viz.gridline),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _marcadas.isEmpty
                        ? 'Você pode cadastrar estes itens depois, a qualquer '
                            'momento.'
                        : 'Eles entram com preço zero — depois você abre cada '
                            'um e coloca quanto pagou.',
                    style: text.labelSmall?.copyWith(color: viz.inkMuted),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _marcadas.isEmpty
                        ? null
                        : () => Navigator.of(context).pop((
                              itens: widget.expansions
                                  .where((e) => _marcadas.contains(e.id))
                                  .toList(),
                              tipo: _tipo,
                            )),
                    child: Text(
                      _marcadas.isEmpty
                          ? 'Nenhum marcado'
                          : 'Adicionar ${_marcadas.length} '
                              '${_tipo.contar(_marcadas.length)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Agora não'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
