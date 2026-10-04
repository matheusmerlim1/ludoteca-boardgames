import 'package:flutter/material.dart';

import '../models/game.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'game_cover.dart';

/// Escolha de um jogo da coleção, com busca.
///
/// Serve ao caminho "acabei de jogar": em vez de achar o jogo na lista, abrir
/// a ficha e só então registrar, você escolhe aqui e cai direto na folha de
/// partida.
///
/// Ordena por **jogado recentemente**, não por nome: quem acabou de jogar
/// alguma coisa provavelmente vai jogar de novo, e o alfabeto não ajuda em
/// nada nesse momento.
///
/// A mesma folha serve à troca ("qual jogo entrou?"), com outro título e outra
/// saída de escape — as duas telas fazem a mesma pergunta com palavras
/// diferentes, e duplicar a busca com capa e ordenação daria duas listas para
/// manter.
/// O que saiu da escolha: um jogo da coleção, ou o pedido de buscar fora.
class PickGameResult {
  const PickGameResult.jogo(this.entry) : buscarNoCatalogo = false;
  const PickGameResult.buscar()
      : entry = null,
        buscarNoCatalogo = true;

  final GameEntry? entry;
  final bool buscarNoCatalogo;
}

class PickGameSheet extends StatefulWidget {
  const PickGameSheet({
    super.key,
    required this.entries,
    this.titulo = 'Qual jogo você jogou?',
    this.escapeTitulo = 'Joguei um jogo que não é meu',
    this.escapeSubtitulo = 'Busca no catálogo e já registra a partida',
    this.escapeIcone = Icons.travel_explore,
    this.mostrarEscape = true,
    this.porNome = false,
  });

  final List<GameEntry> entries;

  /// O que a folha pergunta. Muda com o caminho que abriu a folha.
  final String titulo;

  /// A saída para quando o jogo não está na lista: cadastrar um novo.
  final String escapeTitulo;
  final String escapeSubtitulo;
  final IconData escapeIcone;
  final bool mostrarEscape;

  /// Ordena por nome em vez de "jogado por último". Numa troca, a última vez
  /// que o jogo foi à mesa não diz nada sobre ele estar na negociação.
  final bool porNome;

  /// Devolve o jogo escolhido, ou [PickGameResult.buscar] quando o jogo não
  /// está cadastrado e você quer cadastrá-lo agora.
  static Future<PickGameResult?> show(
    BuildContext context, {
    required List<GameEntry> entries,
    String titulo = 'Qual jogo você jogou?',
    String escapeTitulo = 'Joguei um jogo que não é meu',
    String escapeSubtitulo = 'Busca no catálogo e já registra a partida',
    IconData escapeIcone = Icons.travel_explore,
    bool mostrarEscape = true,
    bool porNome = false,
  }) {
    return showModalBottomSheet<PickGameResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PickGameSheet(
        entries: entries,
        titulo: titulo,
        escapeTitulo: escapeTitulo,
        escapeSubtitulo: escapeSubtitulo,
        escapeIcone: escapeIcone,
        mostrarEscape: mostrarEscape,
        porNome: porNome,
      ),
    );
  }

  @override
  State<PickGameSheet> createState() => _PickGameSheetState();
}

class _PickGameSheetState extends State<PickGameSheet> {
  final _busca = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  List<GameEntry> get _visiveis {
    final lista = widget.entries.where((e) {
      if (_filtro.isEmpty) return true;
      final palavras =
          normalizaNome(_filtro).split(' ').where((p) => p.isNotEmpty);
      final alvo = normalizaNome('${e.game.displayName} ${e.game.name}');
      return palavras.every(alvo.contains);
    }).toList();

    if (widget.porNome) {
      lista.sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      return lista;
    }

    lista.sort((a, b) {
      final da = a.lastPlayed;
      final db = b.lastPlayed;
      // Nunca jogados vão para o fim: aqui a lista serve para registrar de
      // novo, e o que você acabou de jogar é o candidato mais provável.
      if (da == null && db == null) {
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      }
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final visiveis = _visiveis;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
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
                  Text(widget.titulo, style: text.titleMedium),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _busca,
                    autofocus: true,
                    onChanged: (v) => setState(() => _filtro = v),
                    decoration: InputDecoration(
                      hintText: 'Buscar',
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

            // O jogo que você procura quase nunca está cadastrado nos dois
            // casos que abrem esta folha: o jogo de outra pessoa que você
            // acabou de jogar, e o jogo que chegou numa troca. Sem esta saída,
            // seria preciso fechar, cadastrar, e achar tudo de novo.
            if (widget.mostrarEscape) ...[
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: viz.serie(0).withValues(alpha: 0.14),
                  child:
                      Icon(widget.escapeIcone, color: viz.serie(0), size: 20),
                ),
                title: Text(widget.escapeTitulo),
                subtitle: Text(widget.escapeSubtitulo),
                onTap: () =>
                    Navigator.of(context).pop(const PickGameResult.buscar()),
              ),
              Divider(height: 1, color: viz.gridline),
            ],

            Expanded(
              child: visiveis.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _filtro.isEmpty
                              ? 'Nenhum jogo na coleção ainda.'
                              : 'Nenhum jogo com "$_filtro".',
                          textAlign: TextAlign.center,
                          style: text.bodySmall,
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: visiveis.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: viz.gridline,
                        indent: 16,
                        endIndent: 16,
                      ),
                      itemBuilder: (context, i) {
                        final e = visiveis[i];
                        return ListTile(
                          leading: SizedBox(
                            width: 38,
                            height: 48,
                            child: GameCover(
                              url: e.game.thumbUrl ?? e.game.imageUrl,
                              name: e.game.displayName,
                              borderRadius: 6,
                            ),
                          ),
                          title: Text(
                            e.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            e.neverPlayed
                                ? 'nunca jogado'
                                : 'última ${desdeQuando(e.lastPlayed)}',
                          ),
                          onTap: () => Navigator.of(context)
                              .pop(PickGameResult.jogo(e)),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
