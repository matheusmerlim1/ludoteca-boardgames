import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/game.dart';
import '../services/game_catalog.dart';
import '../state/collection_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/game_cover.dart';
import 'game_detail_screen.dart';

/// Cadastro e edição de jogo.
///
/// Três formas de chegar aqui:
/// - [fromBgg] preenchido → jogo novo com a ficha do BGG já dentro;
/// - [existing] preenchido → editando um jogo da coleção;
/// - nenhum dos dois → cadastro manual em branco.
class GameFormScreen extends StatefulWidget {
  const GameFormScreen({
    super.key,
    this.fromBgg,
    this.existing,
    this.ownershipInicial,
  });

  /// Tipo já escolhido por quem abriu a tela.
  final Ownership? ownershipInicial;

  final CatalogGameDetails? fromBgg;
  final Game? existing;

  @override
  State<GameFormScreen> createState() => _GameFormScreenState();
}

class _GameFormScreenState extends State<GameFormScreen> {
  final _form = GlobalKey<FormState>();

  late TextEditingController _namePt;
  late TextEditingController _name;
  late TextEditingController _year;
  late TextEditingController _minPlayers;
  late TextEditingController _maxPlayers;
  late TextEditingController _bestPlayers;
  late TextEditingController _minTime;
  late TextEditingController _maxTime;
  late TextEditingController _weight;
  late TextEditingController _price;
  late TextEditingController _sleeves;
  late TextEditingController _accessories;
  late TextEditingController _manualPlays;
  late TextEditingController _notes;

  DateTime? _purchaseDate;
  DateTime? _manualLastPlayed;
  LinkKind? _linkKind;
  int? _parentId;
  Ownership _ownership = Ownership.propria;

  String? _imageUrl;
  String? _thumbUrl;
  int? _bggId;

  /// Procedência do preço sugerido, quando houver. Nulo = o usuário digitou.
  String? _notaPreco;

  bool _salvando = false;

  bool get _editando => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final g = widget.existing;
    final b = widget.fromBgg;

    _namePt = TextEditingController(text: g?.namePt ?? '');
    _name = TextEditingController(text: g?.name ?? b?.name ?? '');
    _year = TextEditingController(text: _num(g?.year ?? b?.year));
    _minPlayers =
        TextEditingController(text: _num(g?.minPlayers ?? b?.minPlayers));
    _maxPlayers =
        TextEditingController(text: _num(g?.maxPlayers ?? b?.maxPlayers));
    _bestPlayers =
        TextEditingController(text: _num(g?.bestPlayers ?? b?.bestPlayers));
    _minTime = TextEditingController(text: _num(g?.minPlaytime ?? b?.minPlaytime));
    _maxTime = TextEditingController(text: _num(g?.maxPlaytime ?? b?.maxPlaytime));
    _weight = TextEditingController(
      text: (g?.weight ?? b?.weight)?.toStringAsFixed(2).replaceAll('.', ',') ?? '',
    );

    // Ao cadastrar um jogo novo, o preço de referência da fonte entra como
    // **sugestão**. Editando um jogo já salvo ele nunca aparece: o valor que
    // está lá é o que você pagou, e sobrescrever isso com o preço de hoje
    // apagaria a informação real.
    final precoSugerido = (g == null) ? b?.referencePrice : null;
    _price = TextEditingController(
      text: moedaParaCampo(g?.price ?? precoSugerido ?? 0),
    );
    _notaPreco = precoSugerido == null ? null : b?.priceNote;
    _sleeves = TextEditingController(text: moedaParaCampo(g?.sleeveCost ?? 0));
    _accessories =
        TextEditingController(text: moedaParaCampo(g?.accessoryCost ?? 0));

    _manualPlays = TextEditingController(
      text: (g?.manualPlayCount ?? 0) == 0 ? '' : '${g!.manualPlayCount}',
    );
    _notes = TextEditingController(text: g?.notes ?? '');

    _purchaseDate = g?.purchaseDate;
    _manualLastPlayed = g?.manualLastPlayed;
    _linkKind = g?.linkKind ?? ((b?.isExpansion ?? false) ? LinkKind.expansao : null);
    _parentId = g?.parentId;
    _ownership = g?.ownership ?? widget.ownershipInicial ?? Ownership.propria;

    _imageUrl = g?.imageUrl ?? b?.imageUrl;
    _thumbUrl = g?.thumbUrl ?? b?.thumbUrl;
    _bggId = g?.bggId ?? b?.bggId;
  }

  static String _num(int? v) => v == null ? '' : '$v';

  @override
  void dispose() {
    for (final c in [
      _namePt,
      _name,
      _year,
      _minPlayers,
      _maxPlayers,
      _bestPlayers,
      _minTime,
      _maxTime,
      _weight,
      _price,
      _sleeves,
      _accessories,
      _manualPlays,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CollectionStore>();
    final viz = context.viz;

    // Um jogo não pode ser expansão de si mesmo.
    final opcoesBase = store.baseGameOptions
        .where((e) => e.game.id != widget.existing?.id)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar jogo' : 'Novo jogo'),
        actions: [
          TextButton(
            onPressed: _salvando ? null : _salvar,
            child: Text(_salvando ? 'Salvando...' : 'Salvar'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
          children: [
            if (_imageUrl != null || _thumbUrl != null) _previaCapa(),

            _Grupo(
              titulo: 'O que este jogo é para você',
              descricao: 'Só o que é seu entra nos custos. Um jogo de outra '
                  'pessoa conta as partidas e as horas, mas não o dinheiro.',
              children: [
                SegmentedButton<Ownership>(
                  segments: const [
                    ButtonSegment(
                      value: Ownership.propria,
                      label: Text('Minha'),
                      icon: Icon(Icons.inventory_2_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: Ownership.jogada,
                      label: Text('Só joguei'),
                      icon: Icon(Icons.casino_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: Ownership.desejada,
                      label: Text('Quero'),
                      icon: Icon(Icons.favorite_border, size: 16),
                    ),
                  ],
                  selected: {_ownership},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      setState(() => _ownership = s.first),
                ),
              ],
            ),

            _Grupo(
              titulo: 'Identificação',
              children: [
                TextFormField(
                  controller: _namePt,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome em português',
                    helperText: 'Opcional. É o nome que aparece na lista.',
                  ),
                ),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome original *',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'O jogo precisa de um nome'
                      : null,
                ),
                TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Ano'),
                ),
              ],
            ),

            _Grupo(
              titulo: 'Jogadores e duração',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minPlayers,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration:
                            const InputDecoration(labelText: 'Mín. jogadores'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _maxPlayers,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration:
                            const InputDecoration(labelText: 'Máx. jogadores'),
                        validator: _validaFaixaJogadores,
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _bestPlayers,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Melhor com',
                    helperText: 'Nº de jogadores mais votado no BGG.',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minTime,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration:
                            const InputDecoration(labelText: 'Mín. minutos'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _maxTime,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration:
                            const InputDecoration(labelText: 'Máx. minutos'),
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Peso',
                    helperText: 'Complexidade de 1 a 5, como no BGG.',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final d = parseMoeda(v);
                    if (d == null) return 'Número inválido';
                    if (d < 1 || d > 5) return 'O peso vai de 1 a 5';
                    return null;
                  },
                ),
              ],
            ),

            // Jogo de outra pessoa não tem custo seu — o próprio grupo acima
            // diz isso. Manter os campos aqui convidaria a preencher um preço
            // que o app depois ignora de propósito, e o número ficaria no banco
            // parecendo dinheiro seu.
            if (_ownership != Ownership.jogada)
            _Grupo(
              titulo: 'Custos',
              children: [
                _CampoDinheiro(
                  controller: _price,
                  label: 'Preço pago pela caixa',
                  // O texto de apoio diz de onde o número veio. Sem isso, um
                  // campo já preenchido parece um fato — e preço de hoje não é
                  // o que você pagou anos atrás.
                  helper: _notaPreco == null
                      ? null
                      : 'Sugestão do Comparajogos ($_notaPreco). '
                          'Troque pelo valor que você pagou.',
                ),
                _CampoDinheiro(
                  controller: _sleeves,
                  label: 'Sleeves',
                  helper: 'Quanto você gastou protegendo as cartas.',
                ),
                _CampoDinheiro(
                  controller: _accessories,
                  label: 'Acessórios',
                  helper: 'Insertos, organizadores, moedas de metal...',
                ),
                _CampoData(
                  label: 'Data da compra',
                  valor: _purchaseDate,
                  helper: 'Sem ela não dá para calcular custo por mês.',
                  onChange: (d) => setState(() => _purchaseDate = d),
                ),
              ],
            ),

            _Grupo(
              titulo: 'Histórico anterior',
              descricao: 'Para trazer o que já estava na planilha sem precisar '
                  'lançar partida por partida. As partidas registradas no app '
                  'somam em cima disto.',
              children: [
                TextFormField(
                  controller: _manualPlays,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Partidas já jogadas',
                  ),
                ),
                _CampoData(
                  label: 'Última vez que jogou',
                  valor: _manualLastPlayed,
                  onChange: (d) => setState(() => _manualLastPlayed = d),
                ),
              ],
            ),

            _Grupo(
              titulo: 'Agrupamento',
              descricao: 'Itens agrupados somem da lista principal e o custo '
                  'deles entra no total do jogo-pai — uma linha só na estante.',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _linkKind != null,
                  title: const Text('Faz parte de outro jogo'),
                  onChanged: (v) => setState(() {
                    _linkKind = v ? LinkKind.expansao : null;
                    if (!v) _parentId = null;
                  }),
                ),
                if (_linkKind != null) ...[
                  SegmentedButton<LinkKind>(
                    segments: const [
                      ButtonSegment(
                        value: LinkKind.expansao,
                        label: Text('Expansão'),
                      ),
                      ButtonSegment(
                        value: LinkKind.serie,
                        label: Text('Caixa da série'),
                      ),
                    ],
                    selected: {_linkKind!},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _linkKind = s.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _linkKind == LinkKind.expansao
                          ? 'Não joga sozinha: precisa do jogo-base.'
                          : 'Joga sozinha, mas conta como o mesmo jogo. É o '
                              'caso do Unmatched, onde cada caixa é um jogo '
                              'completo e você não quer seis linhas na estante '
                              'com as partidas divididas entre elas.',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: context.viz.inkMuted),
                    ),
                  ),
                ],
                if (_linkKind != null)
                  // DropdownButton dentro de InputDecorator em vez de
                  // DropdownButtonFormField: o parâmetro deste último foi
                  // renomeado (`value` -> `initialValue`) entre versões do
                  // Flutter, e este par tem API estável há anos.
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Faz parte de qual jogo',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _parentId,
                        isExpanded: true,
                        isDense: true,
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Nenhum (item avulso)'),
                          ),
                          for (final e in opcoesBase)
                            DropdownMenuItem<int?>(
                              value: e.game.id,
                              child: Text(
                                e.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _parentId = v),
                      ),
                    ),
                  ),
              ],
            ),

            _Grupo(
              titulo: 'Anotações',
              children: [
                TextFormField(
                  controller: _notes,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Onde comprou, com quem costuma jogar, '
                        'o que achou...',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            FilledButton(
              onPressed: _salvando ? null : _salvar,
              // "Adicionar à coleção" só cabe quando o jogo é seu. Para o que
              // você jogou na casa de alguém, esse rótulo diz o contrário do
              // que o botão faz — e a dúvida aparece bem na hora de confirmar.
              child: Text(switch ((editando: _editando, tipo: _ownership)) {
                (editando: true, tipo: _) => 'Salvar alterações',
                (editando: false, tipo: Ownership.jogada) =>
                  'Salvar e registrar a partida',
                (editando: false, tipo: Ownership.desejada) =>
                  'Adicionar aos desejados',
                (editando: false, tipo: Ownership.propria) =>
                  'Adicionar à coleção',
              }),
            ),
            if (_bggId != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Dados do BGG #$_bggId',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: viz.inkMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previaCapa() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Center(
        child: SizedBox(
          width: 130,
          height: 130,
          child: GameCover(
            url: _imageUrl ?? _thumbUrl,
            name: _name.text.isEmpty ? '?' : _name.text,
            borderRadius: 12,
          ),
        ),
      ),
    );
  }

  String? _validaFaixaJogadores(String? _) {
    final min = parseInteiro(_minPlayers.text);
    final max = parseInteiro(_maxPlayers.text);
    if (min != null && max != null && max < min) {
      return 'O máximo não pode ser menor que o mínimo';
    }
    return null;
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) {
      // Um erro num campo dobrado dentro da lista pode estar fora de vista.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confira os campos destacados.')),
      );
      return;
    }

    setState(() => _salvando = true);

    final store = context.read<CollectionStore>();
    final anterior = widget.existing;

    final jogo = Game(
      id: anterior?.id,
      bggId: _bggId,
      name: _name.text.trim(),
      namePt: _namePt.text.trim().isEmpty ? null : _namePt.text.trim(),
      year: parseInteiro(_year.text),
      minPlayers: parseInteiro(_minPlayers.text),
      maxPlayers: parseInteiro(_maxPlayers.text),
      bestPlayers: parseInteiro(_bestPlayers.text),
      minPlaytime: parseInteiro(_minTime.text),
      maxPlaytime: parseInteiro(_maxTime.text),
      weight: parseMoeda(_weight.text),
      imageUrl: _imageUrl,
      thumbUrl: _thumbUrl,
      parentId: _linkKind != null ? _parentId : null,
      linkKind: _linkKind,
      ownership: _ownership,
      targetPrice: anterior?.targetPrice,
      lastPrice: anterior?.lastPrice,
      lastPriceAt: anterior?.lastPriceAt,
      price: parseMoedaOuZero(_price.text),
      sleeveCost: parseMoedaOuZero(_sleeves.text),
      accessoryCost: parseMoedaOuZero(_accessories.text),
      purchaseDate: _purchaseDate,
      manualPlayCount: parseInteiro(_manualPlays.text) ?? 0,
      manualLastPlayed: _manualLastPlayed,
      // Venda é gerenciada na tela de detalhe, não aqui — preservar o que já
      // estava evita que editar o preço "ressuscite" um jogo vendido.
      sold: anterior?.sold ?? false,
      soldPrice: anterior?.soldPrice,
      soldDate: anterior?.soldDate,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: anterior?.createdAt,
    );

    try {
      // Devolve o id do jogo salvo: quem chamou usa para vincular as expansões
      // escolhidas em seguida.
      final int idSalvo;
      if (_editando) {
        await store.saveGame(jogo);
        idSalvo = jogo.id!;
      } else {
        // Tema e mec\u00e2nica s\u00f3 v\u00eam do cat\u00e1logo. Num cadastro manual a lista \u00e9
        // vazia, e o jogo fica sem tema at\u00e9 o preenchimento em lote alcan\u00e7\u00e1-lo.
        idSalvo = await store.addGame(
          jogo,
          tags: widget.fromBgg?.tags ?? const [],
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(idSalvo);

      // Cadastrou um jogo que não é seu? A única razão para fazer isso é
      // registrar a partida que você acabou de jogar. Abrir a ficha na hora
      // evita o vaivém de salvar, achar na lista (onde ele nem aparece por
      // padrão) e só então abrir.
      if (!_editando &&
          widget.ownershipInicial == null &&
          _ownership == Ownership.jogada) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GameDetailScreen(gameId: idSalvo),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch ((editando: _editando, tipo: _ownership)) {
            (editando: true, tipo: _) => '${jogo.displayName} atualizado.',
            // Ele não entrou na estante de ninguém: entrou no seu histórico.
            (editando: false, tipo: Ownership.jogada) =>
              '${jogo.displayName} salvo como jogo de outra pessoa.',
            (editando: false, tipo: Ownership.desejada) =>
              '${jogo.displayName} entrou na lista de desejos.',
            (editando: false, tipo: Ownership.propria) =>
              '${jogo.displayName} entrou na coleção.',
          }),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não consegui salvar: $e')),
      );
    }
  }
}

class _Grupo extends StatelessWidget {
  const _Grupo({
    required this.titulo,
    this.descricao,
    required this.children,
  });

  final String titulo;
  final String? descricao;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: text.titleMedium),
          if (descricao != null) ...[
            const SizedBox(height: 4),
            Text(descricao!, style: text.bodySmall),
          ],
          const SizedBox(height: 12),
          for (final c in children)
            Padding(padding: const EdgeInsets.only(bottom: 14), child: c),
        ],
      ),
    );
  }
}

class _CampoDinheiro extends StatelessWidget {
  const _CampoDinheiro({
    required this.controller,
    required this.label,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixText: 'R\$ ',
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        return parseMoeda(v) == null ? 'Valor inválido' : null;
      },
    );
  }
}

class _CampoData extends StatelessWidget {
  const _CampoData({
    required this.label,
    required this.valor,
    required this.onChange,
    this.helper,
  });

  final String label;
  final DateTime? valor;
  final ValueChanged<DateTime?> onChange;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        // O rótulo fica fixo no topo: o campo nunca está "vazio" de verdade,
        // ele sempre mostra ou a data ou o convite para escolher.
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              valor == null ? 'não informada' : data(valor!),
              style: text.bodyMedium?.copyWith(
                color: valor == null ? viz.inkMuted : viz.inkPrimary,
              ),
            ),
          ),
          if (valor != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Limpar',
              visualDensity: VisualDensity.compact,
              onPressed: () => onChange(null),
            ),
          IconButton(
            icon: const Icon(Icons.calendar_today, size: 18),
            tooltip: 'Escolher data',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: valor ?? soData(DateTime.now()),
                firstDate: DateTime(1980),
                lastDate: soData(DateTime.now()),
                helpText: label,
              );
              if (d != null) onChange(soData(d));
            },
          ),
        ],
      ),
    );
  }
}
