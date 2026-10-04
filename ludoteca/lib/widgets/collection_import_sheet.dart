import 'package:flutter/material.dart';

import '../services/collection_sync_service.dart';
import '../services/game_catalog.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'game_cover.dart';

/// O que você decidiu importar da sua coleção do Comparajogos.
class CollectionImportChoice {
  const CollectionImportChoice({
    required this.itens,
    required this.usarPreco,
  });

  final List<CatalogGameDetails> itens;

  /// Se o preço de referência do catálogo entra como preço pago.
  final bool usarPreco;
}

/// A caixa que pergunta o que fazer com o que está lá e não está aqui.
///
/// Vem tudo marcado: quem pediu para comparar as duas coleções quer, na
/// esmagadora maioria das vezes, trazer o que falta. Mas nada entra sem passar
/// por aqui — o casamento é por nome, e nome erra: "Catan" e "Catan Junior" são
/// jogos diferentes, e um deles chegaria como novidade sem você poder olhar.
///
/// O preço é uma pergunta à parte porque a resposta muda os custos da coleção
/// inteira: o catálogo tem o preço de **hoje**, e um jogo comprado há três anos
/// não custou isso.
class CollectionImportSheet extends StatefulWidget {
  const CollectionImportSheet({super.key, required this.diff});

  final CollectionDiff diff;

  static Future<CollectionImportChoice?> show(
    BuildContext context, {
    required CollectionDiff diff,
  }) {
    return showModalBottomSheet<CollectionImportChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CollectionImportSheet(diff: diff),
    );
  }

  @override
  State<CollectionImportSheet> createState() => _CollectionImportSheetState();
}

class _CollectionImportSheetState extends State<CollectionImportSheet> {
  late final Set<int> _marcados = {
    for (final g in widget.diff.faltando) g.id,
  };

  bool _usarPreco = true;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final faltando = widget.diff.faltando;
    final todos = _marcados.length == faltando.length;

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
                  Text(
                    '${faltando.length} '
                    '${faltando.length == 1 ? 'jogo está' : 'jogos estão'} '
                    'no Comparajogos e não ${faltando.length == 1 ? 'está' : 'estão'} aqui',
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Li ${widget.diff.nomesDasListas.join(', ')}: '
                    '${widget.diff.total} '
                    '${widget.diff.total == 1 ? 'jogo' : 'jogos'}, dos quais '
                    '${widget.diff.jaTinha} já ${widget.diff.jaTinha == 1 ? 'estava' : 'estavam'} '
                    'no app. Desmarque o que não quiser trazer.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        if (todos) {
                          _marcados.clear();
                        } else {
                          _marcados.addAll(faltando.map((g) => g.id));
                        }
                      }),
                      icon: Icon(
                        todos ? Icons.remove_done : Icons.done_all,
                        size: 18,
                      ),
                      label: Text(todos ? 'Desmarcar todos' : 'Marcar todos'),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: viz.gridline),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: faltando.length,
                itemBuilder: (context, i) {
                  final g = faltando[i];
                  return CheckboxListTile(
                    value: _marcados.contains(g.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _marcados.add(g.id);
                      } else {
                        _marcados.remove(g.id);
                      }
                    }),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    secondary: SizedBox(
                      width: 34,
                      height: 44,
                      child: GameCover(
                        url: g.thumbUrl ?? g.imageUrl,
                        name: g.name,
                        borderRadius: 5,
                      ),
                    ),
                    title: Text(
                      g.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                    subtitle: Text(
                      [
                        if (g.year != null) '${g.year}',
                        if (g.referencePrice != null)
                          'hoje ${dinheiro(g.referencePrice!)}',
                      ].join(' · '),
                      style: text.labelSmall?.copyWith(color: viz.inkMuted),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: viz.gridline),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    value: _usarPreco,
                    onChanged: (v) => setState(() => _usarPreco = v ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      'Usar o preço de hoje como o que paguei',
                      style: text.bodySmall,
                    ),
                    subtitle: Text(
                      _usarPreco
                          ? 'Vai inflar os custos de quem você comprou barato '
                              'ou faz tempo — dá para corrigir jogo a jogo.'
                          : 'Entram com preço zero, para você preencher o que '
                              'pagou de verdade.',
                      style: text.labelSmall?.copyWith(color: viz.inkMuted),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FilledButton(
                    onPressed: _marcados.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(
                              CollectionImportChoice(
                                itens: faltando
                                    .where((g) => _marcados.contains(g.id))
                                    .toList(),
                                usarPreco: _usarPreco,
                              ),
                            ),
                    child: Text(
                      _marcados.isEmpty
                          ? 'Nenhum marcado'
                          : 'Adicionar ${_marcados.length} '
                              '${_marcados.length == 1 ? 'jogo' : 'jogos'}',
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
