import 'package:flutter/material.dart';

import '../data/game_repository.dart';
import '../services/game_catalog.dart';
import '../theme.dart';
import '../utils/format.dart';

/// Escolha de temas e mecânicas para filtrar a coleção.
///
/// Numa folha e não em chips na tela: uma coleção de sessenta jogos gera
/// facilmente cinquenta etiquetas, e cinquenta chips empurrariam a lista de
/// jogos para fora da tela.
///
/// Cada etiqueta mostra **quantos jogos** tem. Sem esse número, marcar um tema
/// com um jogo só parece um filtro quebrado; com ele, você sabe de antemão o
/// que vai encontrar.
class TagFilterSheet extends StatefulWidget {
  const TagFilterSheet({
    super.key,
    required this.tags,
    required this.selecionadas,
  });

  final List<TagCount> tags;
  final Set<int> selecionadas;

  static Future<Set<int>?> show(
    BuildContext context, {
    required List<TagCount> tags,
    required Set<int> selecionadas,
  }) {
    return showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TagFilterSheet(tags: tags, selecionadas: selecionadas),
    );
  }

  @override
  State<TagFilterSheet> createState() => _TagFilterSheetState();
}

class _TagFilterSheetState extends State<TagFilterSheet> {
  late final Set<int> _marcadas = {...widget.selecionadas};
  final _busca = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  List<TagCount> _doTipo(TagKind tipo) {
    final palavras = normalizaNome(_filtro).split(' ').where((p) => p.isNotEmpty);
    return widget.tags.where((t) {
      if (t.kind != tipo) return false;
      if (palavras.isEmpty) return true;
      final alvo = normalizaNome(t.name);
      return palavras.every(alvo.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    final temas = _doTipo(TagKind.tema);
    final mecanicas = _doTipo(TagKind.mecanica);
    final vazio = temas.isEmpty && mecanicas.isEmpty;

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
                  Text('Tema e mecânica', style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    _marcadas.isEmpty
                        ? 'Marque para filtrar a coleção. O número é quantos '
                            'jogos seus têm aquele tema.'
                        : 'Marcando mais de uma, o jogo precisa ter todas.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (widget.tags.length > 10)
                    TextField(
                      controller: _busca,
                      onChanged: (v) => setState(() => _filtro = v),
                      decoration: InputDecoration(
                        hintText: 'Filtrar temas',
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
            const SizedBox(height: 10),
            Divider(height: 1, color: viz.gridline),
            Expanded(
              child: vazio
                  ? _Vazio(temFiltro: _filtro.isNotEmpty, termo: _filtro)
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      children: [
                        // Estilo primeiro: é o corte mais grosso, e quem sabe
                        // que quer "algo festivo" já resolve aqui sem descer.
                        for (final tipo in TagKind.values)
                          if (_doTipo(tipo).isNotEmpty) ...[
                            _Secao(
                              titulo: tipo.label,
                              tags: _doTipo(tipo),
                              marcadas: _marcadas,
                              onToggle: _alterna,
                            ),
                            const SizedBox(height: 18),
                          ],
                      ],
                    ),
            ),
            Divider(height: 1, color: viz.gridline),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  if (_marcadas.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_marcadas.clear),
                      child: const Text('Limpar'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_marcadas),
                    child: Text(
                      _marcadas.isEmpty
                          ? 'Ver todos'
                          : 'Aplicar ${_marcadas.length}',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _alterna(int id) => setState(() {
        if (!_marcadas.remove(id)) _marcadas.add(id);
      });
}

class _Secao extends StatelessWidget {
  const _Secao({
    required this.titulo,
    required this.tags,
    required this.marcadas,
    required this.onToggle,
  });

  final String titulo;
  final List<TagCount> tags;
  final Set<int> marcadas;
  final void Function(int) onToggle;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo.toUpperCase(),
          style: text.labelSmall?.copyWith(
            color: viz.inkMuted,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in tags)
              FilterChip(
                label: Text('${t.name} · ${t.gameCount}'),
                selected: marcadas.contains(t.id),
                onSelected: (_) => onToggle(t.id),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio({required this.temFiltro, required this.termo});

  final bool temFiltro;
  final String termo;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_off_outlined, size: 36, color: viz.inkMuted),
            const SizedBox(height: 14),
            Text(
              temFiltro
                  ? 'Nenhum tema com "$termo".'
                  : 'Seus jogos ainda não têm tema.',
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
            if (!temFiltro) ...[
              const SizedBox(height: 8),
              Text(
                'Em Ajustes existe um botão que busca os temas de todos os '
                'jogos que você já cadastrou.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
