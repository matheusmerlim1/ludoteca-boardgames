import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game.dart';
import '../services/bgg_service.dart';
import '../services/comparajogos_service.dart';
import '../services/game_catalog.dart';
import '../state/collection_store.dart';
import '../theme.dart';
import '../widgets/expansion_picker_sheet.dart';
import '../widgets/game_cover.dart';
import 'game_form_screen.dart';

/// Busca de jogos para cadastrar.
///
/// A fonte padrão é o **Comparajogos**: funciona sem cadastro, traz nome em
/// português e preço em reais. O **BoardGameGeek** aparece como segunda opção
/// só quando há um token aprovado configurado em Ajustes — sem token ele
/// responde 401 em tudo, e oferecer a opção seria oferecer um erro.
///
/// O caminho feliz é: digitar o nome, tocar no jogo, conferir o preço e salvar.
/// Nome, capa, número de jogadores, duração e peso vêm preenchidos.
class AddGameScreen extends StatefulWidget {
  const AddGameScreen({super.key, this.ownershipInicial});

  /// Tipo já definido por quem chamou. Vem preenchido quando esta tela é
  /// aberta pelo fluxo de registrar a partida de um jogo que não é seu.
  final Ownership? ownershipInicial;

  @override
  State<AddGameScreen> createState() => _AddGameScreenState();
}

class _AddGameScreenState extends State<AddGameScreen> {
  /// Fonte padrão: funciona sem cadastro e devolve nomes em português.
  final _comparajogos = ComparajogosService();

  /// Só entra em jogo se o usuário tiver um token aprovado configurado.
  final _bgg = BggService();

  late CatalogSource _fonte;

  GameCatalog get _catalogo =>
      _fonte == CatalogSource.bgg ? _bgg : _comparajogos;

  final _controller = TextEditingController();

  Timer? _debounce;
  List<CatalogSearchResult> _resultados = const [];
  bool _buscando = false;
  String? _erro;

  /// Verdadeiro quando o erro é falta de token: a tela troca o botão de
  /// "tentar de novo" por um caminho para Ajustes, já que insistir não resolve.
  bool _erroDeToken = false;

  bool _jaBuscou = false;

  /// Guarda o termo da busca em andamento para descartar resposta atrasada de
  /// uma busca anterior — sem isso, digitar rápido faz o resultado de "cat"
  /// sobrescrever o de "catan".
  String _termoEmVoo = '';

  @override
  void initState() {
    super.initState();
    // O token vem do banco, via store. Sem ele o BGG responde 401 em tudo,
    // então nem faz sentido oferecê-lo como fonte.
    final token = context.read<CollectionStore>().bggToken;
    _bgg.token = token;
    _fonte = CatalogSource.comparajogos;
  }

  bool get _bggDisponivel => _bgg.hasToken;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _bgg.dispose();
    _comparajogos.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() {
        _resultados = const [];
        _erro = null;
        _jaBuscou = false;
      });
      return;
    }
    // Espera a digitação parar: rajada de requisição não ajuda ninguém.
    _debounce = Timer(const Duration(milliseconds: 550), () => _buscar(v));
  }

  Future<void> _buscar(String termo) async {
    final alvo = termo.trim();
    if (alvo.length < 2) return;

    setState(() {
      _buscando = true;
      _erro = null;
      _erroDeToken = false;
      _termoEmVoo = alvo;
    });

    try {
      final r = await _catalogo.search(alvo);
      if (!mounted || _termoEmVoo != alvo) return;
      setState(() {
        _resultados = r;
        _buscando = false;
        _jaBuscou = true;
      });
    } on CatalogAuthException catch (e) {
      if (!mounted || _termoEmVoo != alvo) return;
      setState(() {
        _erro = e.message;
        _erroDeToken = true;
        _buscando = false;
        _jaBuscou = true;
      });
    } on CatalogException catch (e) {
      if (!mounted || _termoEmVoo != alvo) return;
      setState(() {
        _erro = e.message;
        _buscando = false;
        _jaBuscou = true;
      });
    } catch (e) {
      if (!mounted || _termoEmVoo != alvo) return;
      setState(() {
        _erro = 'Algo deu errado na busca: $e';
        _buscando = false;
        _jaBuscou = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar jogo'),
        actions: [
          TextButton(
            onPressed: _adicionarManualmente,
            child: const Text('Manual'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: _buscar,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Nome do jogo',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscando
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _controller.clear();
                              _onChanged('');
                            },
                          ),
              ),
            ),
          ),
          // O seletor de fonte só aparece quando há de fato uma escolha:
          // sem token aprovado, o BGG responde 401 em tudo e oferecê-lo seria
          // um botão que só leva a erro.
          if (_bggDisponivel)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Text('Buscar em', style: text.labelSmall),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SegmentedButton<CatalogSource>(
                      segments: const [
                        ButtonSegment(
                          value: CatalogSource.comparajogos,
                          label: Text('Comparajogos'),
                        ),
                        ButtonSegment(
                          value: CatalogSource.bgg,
                          label: Text('BGG'),
                        ),
                      ],
                      selected: {_fonte},
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      onSelectionChanged: (s) {
                        setState(() {
                          _fonte = s.first;
                          _resultados = const [];
                          _erro = null;
                          _jaBuscou = false;
                        });
                        if (_controller.text.trim().length >= 2) {
                          _buscar(_controller.text);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          Container(height: 1, color: viz.gridline),
          Expanded(child: _corpo(text, viz)),
        ],
      ),
    );
  }

  Widget _corpo(TextTheme text, VizColors viz) {
    if (_erro != null) {
      // Falta de token não é problema de rede e não melhora tentando de novo,
      // então a ação principal aqui é ir configurar, não repetir a busca.
      if (_erroDeToken) {
        return _Aviso(
          icone: Icons.key_off,
          titulo: 'O BGG agora exige um token',
          mensagem: '${_erro!}\n\nO cadastro é gratuito e feito uma vez, em '
              'boardgamegeek.com/using_the_xml_api, com a sua conta do BGG '
              'logada.',
          acao: 'Abrir Ajustes',
          onAcao: () {
            // Volta para a casca e deixa o usuário na aba de Ajustes.
            Navigator.of(context).pop();
          },
          acaoSecundaria: 'Cadastrar manualmente',
          onAcaoSecundaria: _adicionarManualmente,
        );
      }

      return _Aviso(
        icone: Icons.wifi_off,
        titulo: 'Não deu para buscar no ${_fonte.label}',
        mensagem: _erro!,
        acao: 'Tentar de novo',
        onAcao: () => _buscar(_controller.text),
        acaoSecundaria: 'Cadastrar manualmente',
        onAcaoSecundaria: _adicionarManualmente,
      );
    }

    if (_controller.text.trim().length < 2) {
      return _Aviso(
        icone: Icons.travel_explore,
        titulo: 'Busque pelo nome',
        mensagem: _fonte == CatalogSource.comparajogos
            ? 'A busca é no Comparajogos, que tem os nomes em português e o '
                'preço em reais. O preço vem preenchido como sugestão — troque '
                'pelo que você realmente pagou.'
            : 'A busca é no BoardGameGeek, então funciona melhor com o nome '
                'original do jogo. O nome em português você ajusta depois.',
      );
    }

    if (_buscando && _resultados.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_jaBuscou && _resultados.isEmpty) {
      return _Aviso(
        icone: Icons.search_off,
        titulo: 'Nada encontrado',
        mensagem: 'O  não achou "${_controller.text.trim()}". '
            'Tente o nome original, ou cadastre o jogo manualmente.',
        acao: 'Cadastrar manualmente',
        onAcao: _adicionarManualmente,
      );
    }

    final store = context.watch<CollectionStore>();

    return ListView.separated(
      itemCount: _resultados.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: viz.gridline,
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, i) {
        final r = _resultados[i];
        return _ResultTile(
          result: r,
          // Por nome, não por id: o id do resultado é da fonte que está sendo
          // usada, e a coleção pode ter o jogo cadastrado à mão ou vindo da
          // outra fonte.
          jaTem: store.alreadyOwned(name: r.name),
          onTap: () => _selecionar(r),
        );
      },
    );
  }

  Future<void> _selecionar(CatalogSearchResult r) async {
    final store = context.read<CollectionStore>();

    // Já está na coleção? Melhor avisar antes de duplicar.
    final existente = await store.repository.findByBggId(r.id);
    if (!mounted) return;

    if (existente != null) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Você já tem esse jogo'),
          content: Text(
            '"${existente.displayName}" já está na sua coleção. '
            'Quer cadastrar outra cópia mesmo assim?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Cadastrar de novo'),
            ),
          ],
        ),
      );
      if (continuar != true || !mounted) return;
    }

    // Busca a ficha completa com um indicador modal — são poucos segundos,
    // mas a fila do BGG pode esticar isso.
    final detalhes = await showDialog<CatalogGameDetails>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CarregandoDetalhes(catalogo: _catalogo, id: r.id),
    );

    if (detalhes == null || !mounted) return;

    final novoId = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => GameFormScreen(
          fromBgg: detalhes,
          ownershipInicial: widget.ownershipInicial,
        ),
      ),
    );

    if (!mounted) return;

    // Salvou o jogo-base e o BGG conhece expansões dele: oferece a lista.
    // Nada entra sem marcação — ver ExpansionPickerSheet.
    if (novoId != null && detalhes.expansions.isNotEmpty) {
      await _oferecerExpansoes(novoId, detalhes);
    }

    // Devolve o id para quem chamou. O fluxo de registrar partida de um jogo
    // que não é seu precisa dele para abrir a folha de partida em seguida.
    if (mounted) Navigator.of(context).pop(novoId);
  }

  Future<void> _oferecerExpansoes(int paiId, CatalogGameDetails pai) async {
    final escolhidas = await ExpansionPickerSheet.show(
      context,
      gameName: pai.name,
      expansions: pai.expansions,
    );
    if (escolhidas == null || escolhidas.itens.isEmpty || !mounted) return;

    final itens = escolhidas.itens;
    final tipo = escolhidas.tipo;

    final store = context.read<CollectionStore>();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Buscando os dados...')),
          ],
        ),
      ),
    );

    var inseridas = 0;
    String? falha;

    try {
      // Em lotes: uma requisição por lote em vez de uma por expansão. O BGG
      // não gosta de listas enormes de id numa só chamada.
      // Em lotes: uma requisição por lote em vez de uma por item. Nenhuma das
      // duas fontes gosta de listas enormes de id numa só chamada.
      for (var i = 0; i < itens.length; i += 20) {
        final lote = itens.skip(i).take(20).map((e) => e.id).toList();
        final fichas = await _catalogo.detailsBatch(lote);

        for (final f in fichas) {
          // Vai direto no repositório e recarrega uma vez no fim: usar
          // store.addGame aqui dispararia um reload por expansão.
          await store.repository.insertGame(Game(
            // `f.bggId`, não `f.id`: no Comparajogos o id da fonte é dele, e
            // gravá-lo no campo do BGG faria o app achar que conhece um jogo
            // do BGG que não existe.
            bggId: f.bggId,
            name: f.name,
            year: f.year,
            minPlayers: f.minPlayers,
            maxPlayers: f.maxPlayers,
            bestPlayers: f.bestPlayers,
            minPlaytime: f.minPlaytime,
            maxPlaytime: f.maxPlaytime,
            weight: f.weight,
            imageUrl: f.imageUrl,
            thumbUrl: f.thumbUrl,
            linkKind: tipo,
            parentId: paiId,
          ));
          inseridas++;
        }
      }
    } on CatalogException catch (e) {
      falha = e.message;
    } catch (e) {
      falha = 'Algo deu errado: $e';
    }

    await store.refresh();

    if (!mounted) return;
    Navigator.of(context).pop(); // fecha o diálogo de progresso

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          falha != null
              // Parcial é informação útil: diz quantos entraram antes de falhar.
              ? '$inseridas de ${itens.length} adicionados. $falha'
              : '$inseridas ${tipo.contar(inseridas)} '
                  '${inseridas == 1 ? 'adicionada' : 'adicionadas'} a '
                  '${pai.name}.',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _adicionarManualmente() async {
    final novoId = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => GameFormScreen(
          ownershipInicial: widget.ownershipInicial,
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop(novoId);
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    required this.jaTem,
    required this.onTap,
  });

  final CatalogSearchResult result;
  final bool jaTem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: SizedBox(
        width: 44,
        height: 56,
        child: GameCover(
          url: result.thumbUrl,
          name: result.name,
          borderRadius: 6,
        ),
      ),
      title: Text(result.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (result.year != null) '${result.year}',
          if (result.isExpansion) 'expansão',
          if (jaTem) 'já na sua coleção',
        ].join(' · '),
        style: text.bodySmall?.copyWith(
          color: jaTem ? viz.inkMuted : viz.inkSecondary,
        ),
      ),
      trailing: Icon(
        jaTem ? Icons.check_circle_outline : Icons.add_circle_outline,
        color: jaTem ? viz.good : viz.inkMuted,
      ),
    );
  }
}

/// Diálogo que busca os detalhes e se fecha devolvendo o resultado.
class _CarregandoDetalhes extends StatefulWidget {
  const _CarregandoDetalhes({required this.catalogo, required this.id});

  /// Qualquer fonte: o diálogo não sabe se é Comparajogos ou BGG.
  final GameCatalog catalogo;
  final int id;

  @override
  State<_CarregandoDetalhes> createState() => _CarregandoDetalhesState();
}

class _CarregandoDetalhesState extends State<_CarregandoDetalhes> {
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final d = await widget.catalogo.details(widget.id);
      if (mounted) Navigator.of(context).pop(d);
    } on CatalogException catch (e) {
      if (mounted) setState(() => _erro = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) {
      return AlertDialog(
        title: const Text('Não consegui buscar a ficha'),
        content: Text(_erro!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () {
              setState(() => _erro = null);
              _carregar();
            },
            child: const Text('Tentar de novo'),
          ),
        ],
      );
    }

    return const AlertDialog(
      content: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 16),
          Expanded(child: Text('Buscando no BGG...')),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icone,
    required this.titulo,
    required this.mensagem,
    this.acao,
    this.onAcao,
    this.acaoSecundaria,
    this.onAcaoSecundaria,
  });

  final IconData icone;
  final String titulo;
  final String mensagem;
  final String? acao;
  final VoidCallback? onAcao;
  final String? acaoSecundaria;
  final VoidCallback? onAcaoSecundaria;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 56, 32, 32),
      children: [
        Icon(icone, size: 40, color: viz.inkMuted),
        const SizedBox(height: 16),
        Text(titulo, textAlign: TextAlign.center, style: text.titleMedium),
        const SizedBox(height: 8),
        Text(mensagem, textAlign: TextAlign.center, style: text.bodySmall),
        if (acao != null) ...[
          const SizedBox(height: 20),
          Center(child: FilledButton(onPressed: onAcao, child: Text(acao!))),
        ],
        if (acaoSecundaria != null) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: onAcaoSecundaria,
              child: Text(acaoSecundaria!),
            ),
          ),
        ],
      ],
    );
  }
}
