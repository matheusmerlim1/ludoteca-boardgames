import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/suggestion.dart';
import '../services/backup_service.dart';
import '../services/bgg_service.dart';
import '../services/comparajogos_service.dart';
import '../services/share_service.dart';
import '../services/tag_backfill_service.dart';
import '../services/game_catalog.dart';
import '../state/collection_store.dart';
import '../theme.dart';
import '../utils/format.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final BackupService _backup =
      BackupService(repository: context.read<CollectionStore>().repository);

  bool _ocupado = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CollectionStore>();
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    final jogos = store.allEntries.where((e) => !e.game.isGrouped).length;
    final expansoes = store.allEntries.where((e) => e.game.isGrouped).length;
    final partidas =
        store.allEntries.fold<int>(0, (s, e) => s + e.loggedPlays);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _CartaoSugestoes(store: store),
          const SizedBox(height: 16),
          _CartaoTemas(store: store),
          const SizedBox(height: 16),
          _CartaoToken(store: store),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Backup', style: text.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Seus dados ficam só neste celular — não existe conta nem '
                    'servidor. Isso também significa que trocar de aparelho '
                    'ou perder o telefone leva a coleção junto. Exporte de vez '
                    'em quando e guarde o arquivo no Drive ou no seu e-mail.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _ocupado ? null : _exportar,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Exportar backup'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _ocupado ? null : _restaurar,
                    icon: const Icon(Icons.restore),
                    label: const Text('Restaurar de um arquivo'),
                  ),
                  if (_ocupado) ...[
                    const SizedBox(height: 14),
                    const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Na coleção', style: text.titleMedium),
                  const SizedBox(height: 12),
                  _Linha(rotulo: 'Jogos', valor: '$jogos'),
                  _Linha(rotulo: 'Expansões', valor: '$expansoes'),
                  _Linha(
                    rotulo: 'Partidas registradas no app',
                    valor: '$partidas',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sobre', style: text.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Ludoteca 1.0.0',
                    style: text.bodySmall?.copyWith(color: viz.inkPrimary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Nomes, capas, número de jogadores, duração e peso vêm da '
                    'Comparajogos, que também sugere o preço em reais. O '
                    'BoardGameGeek entra como fonte extra se você configurar '
                    'um token.\n\n'
                    'Quanto você pagou, as partidas e as anotações são seus, '
                    'digitados por você — nada disso vem de fora.',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportar() async {
    setState(() => _ocupado = true);
    try {
      await _backup.exportAndShare();
    } on BackupException catch (e) {
      _aviso(e.message);
    } catch (e) {
      _aviso('Não consegui exportar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _restaurar() async {
    setState(() => _ocupado = true);

    try {
      final arquivo = await _backup.readBackupFile();
      if (!mounted) return;

      final store = context.read<CollectionStore>();
      final atuais = store.allEntries.length;

      // Restaurar é destrutivo: apaga a coleção atual. O diálogo diz
      // exatamente o que sai e o que entra, com números.
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restaurar backup?'),
          content: Text(
            'Isto apaga o que está no app agora '
            '($atuais ${atuais == 1 ? 'item' : 'itens'}) e coloca no lugar '
            'o conteúdo do arquivo: ${arquivo.jogos} '
            '${arquivo.jogos == 1 ? 'item' : 'itens'} e ${arquivo.partidas} '
            '${arquivo.partidas == 1 ? 'partida' : 'partidas'}.\n\n'
            'Não tem como desfazer. Se a coleção atual ainda não está salva '
            'em nenhum backup, cancele e exporte primeiro.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Substituir'),
            ),
          ],
        ),
      );

      if (confirmado != true) return;

      final r = await _backup.restore(arquivo.dados);
      if (!mounted) return;

      await store.load();
      if (!mounted) return;

      _aviso(
        'Restaurado: ${r.jogos} ${r.jogos == 1 ? 'item' : 'itens'} e '
        '${r.partidas} ${r.partidas == 1 ? 'partida' : 'partidas'}.',
      );
    } on BackupException catch (e) {
      // "cancelado" é o usuário fechando o seletor, não um erro para exibir.
      if (e.message != 'cancelado') _aviso(e.message);
    } catch (e) {
      _aviso('Não consegui restaurar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
    );
  }
}

/// Ideias de melhoria do próprio app.
///
/// A ideia aparece no meio do uso — "isto aqui devia ser assim" acontece com o
/// celular na mão, no minuto em que a coisa incomoda. Uma anotação que exige
/// sair do app e abrir outro aplicativo simplesmente não é feita, e a ideia se
/// perde.
///
/// O que já foi feito não some, desce: serve para não pedir duas vezes a mesma
/// coisa e para lembrar o que já foi pedido. E "Compartilhar" existe porque a
/// lista só vale quando chega em quem vai implementar.
class _CartaoSugestoes extends StatefulWidget {
  const _CartaoSugestoes({required this.store});

  final CollectionStore store;

  @override
  State<_CartaoSugestoes> createState() => _CartaoSugestoesState();
}

class _CartaoSugestoesState extends State<_CartaoSugestoes> {
  final _texto = TextEditingController();
  bool _aberto = false;

  @override
  void initState() {
    super.initState();
    // A lista vem do banco na carga do app; isto cobre quem chegou aqui com o
    // app já aberto desde antes de a tabela existir.
    widget.store.carregarSugestoes();
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final viz = context.viz;

    final lista = widget.store.suggestions;
    final abertas = widget.store.suggestionsAbertas;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Sugestões de melhoria', style: text.titleMedium),
                ),
                if (lista.isNotEmpty)
                  Text(
                    abertas == 0
                        ? 'todas feitas'
                        : '$abertas ${abertas == 1 ? 'aberta' : 'abertas'}',
                    style: text.labelSmall?.copyWith(
                      color: abertas == 0 ? viz.good : viz.inkSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Anote aqui o que você quer que o app faça diferente, na hora em '
              'que percebe. A lista fica guardada no aparelho e serve de pauta '
              'para a próxima versão.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _texto,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _adicionar(),
              decoration: const InputDecoration(
                labelText: 'Nova sugestão',
                hintText: 'ex.: deixar editar o valor da troca depois',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _adicionar,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar sugestão'),
            ),
            if (lista.isNotEmpty) ...[
              const SizedBox(height: 8),
              // Fechada por padrão: a lista cresce, e Ajustes não pode virar
              // uma tela de rolagem infinita por causa dela.
              TextButton.icon(
                onPressed: () => setState(() => _aberto = !_aberto),
                icon: Icon(
                  _aberto ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(
                  _aberto
                      ? 'Esconder a lista'
                      : 'Ver as ${lista.length} '
                          '${lista.length == 1 ? 'sugestão' : 'sugestões'}',
                ),
              ),
              if (_aberto) ...[
                const SizedBox(height: 4),
                for (final s in lista) _linha(s, text, viz),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () => _compartilhar(lista),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Compartilhar a lista'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _linha(Suggestion s, TextTheme text, VizColors viz) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: s.done,
            visualDensity: VisualDensity.compact,
            onChanged: (v) => widget.store.marcarSugestao(s.id!, v ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.text,
                  style: text.bodySmall?.copyWith(
                    color: s.done ? viz.inkMuted : viz.inkPrimary,
                    decoration: s.done ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  data(s.createdAt),
                  style: text.labelSmall?.copyWith(color: viz.inkMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => widget.store.removerSugestao(s.id!),
            icon: const Icon(Icons.delete_outline, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Apagar',
          ),
        ],
      ),
    );
  }

  Future<void> _adicionar() async {
    final texto = _texto.text.trim();
    if (texto.isEmpty) return;

    await widget.store.addSugestao(texto);
    _texto.clear();
    if (!mounted) return;
    setState(() => _aberto = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sugestão anotada.')),
    );
  }

  Future<void> _compartilhar(List<Suggestion> lista) async {
    const servico = ShareService();
    final linhas = <String>[
      '💡 Ludoteca — sugestões de melhoria',
      '',
      for (final s in lista)
        '${s.done ? '[x]' : '[ ]'} ${s.text}  (${data(s.createdAt)})',
    ];
    await servico.compartilhar(
      linhas.join('\n'),
      assunto: 'Sugestões para a Ludoteca',
    );
  }
}

/// Preenchimento de temas dos jogos já cadastrados.
///
/// Sem isto o filtro por tema nasce inútil numa coleção existente: jogos
/// digitados à mão não têm etiqueta nenhuma, e preencher dezenas um a um não é
/// trabalho que se peça a alguém.
class _CartaoTemas extends StatefulWidget {
  const _CartaoTemas({required this.store});

  final CollectionStore store;

  @override
  State<_CartaoTemas> createState() => _CartaoTemasState();
}

class _CartaoTemasState extends State<_CartaoTemas> {
  TagBackfillService? _servico;
  int _feitos = 0;
  int _total = 0;
  BackfillReport? _relatorio;

  bool get _rodando => _servico != null;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final store = widget.store;

    final comTema = store.allEntries
        .where((e) => store.tagsOf(e.id).isNotEmpty)
        .length;
    final total = store.allEntries.length;
    final semCapa = store.allEntries
        .where((e) =>
            (e.game.imageUrl?.isEmpty ?? true) &&
            (e.game.thumbUrl?.isEmpty ?? true))
        .length;
    // Um jogo pode estar nas duas contas; o que interessa aqui é quantos a
    // varredura vai visitar, não a soma dos dois buracos.
    final faltando = store.allEntries
        .where((e) =>
            store.tagsOf(e.id).isEmpty ||
            ((e.game.imageUrl?.isEmpty ?? true) &&
                (e.game.thumbUrl?.isEmpty ?? true)))
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Capas, temas e mecânicas', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              faltando == 0 && total > 0
                  ? 'Todos os $total jogos já têm capa e tema.'
                  : 'Jogo cadastrado à mão ou vindo da planilha entra sem '
                      'imagem e sem tema — é por isso que a lista mostra as '
                      'iniciais no lugar da miniatura. Hoje: '
                      '$semCapa ${semCapa == 1 ? 'jogo sem capa' : 'jogos sem capa'}, '
                      '${total - comTema} sem tema, de $total.',
              style: text.bodySmall,
            ),
            if (faltando > 0) ...[
              const SizedBox(height: 6),
              Text(
                'A busca é pelo nome do jogo, então pode errar. No fim eu mostro '
                'quais não achei e quais casaram com um nome diferente do seu.',
                style: text.labelSmall?.copyWith(color: viz.inkMuted),
              ),
            ],
            if (_rodando) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: _total == 0 ? null : _feitos / _total,
              ),
              const SizedBox(height: 8),
              Text('$_feitos de $_total', style: text.bodySmall),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _servico?.cancel(),
                child: const Text('Parar'),
              ),
            ] else ...[
              const SizedBox(height: 14),
              if (faltando > 0)
                FilledButton.icon(
                  onPressed: () => _buscar(todos: false),
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    'Buscar capas e temas de $faltando '
                    '${faltando == 1 ? 'jogo' : 'jogos'}',
                  ),
                ),
              if (faltando > 0) const SizedBox(height: 8),
              // Rebuscar todos existe porque o app passou a ler o **estilo**
              // (Festivo, Estratégico, Temático) do catálogo. Quem preencheu
              // antes disso ficaria sem estilo para sempre.
              OutlinedButton.icon(
                onPressed: total == 0 ? null : () => _buscar(todos: true),
                icon: const Icon(Icons.refresh),
                label: Text(
                  faltando == 0
                      ? 'Atualizar os $total (traz o estilo)'
                      : 'Rebuscar todos os $total',
                ),
              ),
            ],
            if (_relatorio != null) ...[
              const SizedBox(height: 14),
              _Resultado(relatorio: _relatorio!),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _buscar({required bool todos}) async {
    final store = widget.store;
    final catalogo = ComparajogosService();
    final servico = TagBackfillService(
      catalogo: catalogo,
      repository: store.repository,
    );

    setState(() {
      _servico = servico;
      _relatorio = null;
      _feitos = 0;
      _total = 0;
    });

    try {
      final r = await servico.run(
        todos: todos,
        onProgress: (feitos, total) {
          if (!mounted) return;
          setState(() {
            _feitos = feitos;
            _total = total;
          });
        },
      );
      await store.refresh();
      if (mounted) setState(() => _relatorio = r);
    } finally {
      catalogo.dispose();
      if (mounted) setState(() => _servico = null);
    }
  }
}

class _Resultado extends StatelessWidget {
  const _Resultado({required this.relatorio});

  final BackfillReport relatorio;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    final problemas = relatorio.problemas;
    final aproximados = relatorio.aproximados;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: viz.good),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${relatorio.preenchidos} '
                '${relatorio.preenchidos == 1 ? 'jogo preenchido' : 'jogos preenchidos'}'
                '${relatorio.capas > 0 ? ', ${relatorio.capas} com capa nova' : ''}'
                '${relatorio.cancelado ? ' (interrompido)' : ''}.',
                style: text.bodySmall?.copyWith(color: viz.inkPrimary),
              ),
            ),
          ],
        ),

        // Os que casaram com nome diferente são onde o erro se esconde: um
        // "Catan" que virou "Catan Junior" traz os temas errados.
        if (aproximados.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'CONFIRA ESTES — o nome encontrado é diferente do seu',
            style: text.labelSmall?.copyWith(color: viz.warning),
          ),
          const SizedBox(height: 6),
          for (final i in aproximados.take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${i.game.displayName}  →  ${i.matchedName}',
                style: text.bodySmall,
              ),
            ),
        ],

        if (problemas.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'SEM TEMA (${problemas.length})',
            style: text.labelSmall?.copyWith(color: viz.inkMuted),
          ),
          const SizedBox(height: 6),
          for (final i in problemas.take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${i.game.displayName} — ${_motivo(i.outcome)}',
                style: text.bodySmall,
              ),
            ),
          if (problemas.length > 12)
            Text('e mais ${problemas.length - 12}...', style: text.labelSmall),
        ],
      ],
    );
  }

  String _motivo(BackfillOutcome o) => switch (o) {
        BackfillOutcome.naoEncontrado => 'não achei no catálogo — sem capa e sem tema',
        BackfillOutcome.semTags => 'o catálogo não tem tema nem capa para ele',
        BackfillOutcome.falhou => 'falhou na busca',
        BackfillOutcome.preenchido => '',
      };
}

/// Cartão do token da API do BGG.
///
/// Existe porque o BGG passou a exigir cadastro de aplicativo e token na XML
/// API (bloqueio ativo desde o fim de outubro de 2025). Sem token, todo
/// endpoint responde 401 — e como a home do site continua abrindo normalmente,
/// o sintoma parece problema de internet quando não é. O texto aqui diz isso
/// explicitamente para o usuário não caçar o problema no lugar errado.
class _CartaoToken extends StatefulWidget {
  const _CartaoToken({required this.store});

  final CollectionStore store;

  @override
  State<_CartaoToken> createState() => _CartaoTokenState();
}

class _CartaoTokenState extends State<_CartaoToken> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.store.bggToken ?? '');

  bool _visivel = false;
  bool _testando = false;
  String? _resultado;
  bool _resultadoOk = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;
    final temToken = widget.store.hasBggToken;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Token do BGG', style: text.titleMedium)),
                Icon(
                  temToken ? Icons.check_circle : Icons.error_outline,
                  size: 18,
                  color: temToken ? viz.good : viz.warning,
                ),
                const SizedBox(width: 5),
                Text(
                  temToken ? 'configurado' : 'não configurado',
                  style: text.labelSmall?.copyWith(
                    color: temToken ? viz.good : viz.inkSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Opcional. A busca do app já funciona pelo Comparajogos, que tem '
              'os nomes em português e o preço em reais. O BGG serve como '
              'segunda fonte, com uma base maior.\n\n'
              'Ele passou a exigir cadastro de aplicativo: sem token, a API '
              'recusa tudo, mesmo com o site abrindo normalmente. O cadastro '
              'ainda passa por análise deles depois de enviado.\n\n'
              'O cadastro é gratuito e feito uma vez: entre em '
              'boardgamegeek.com/using_the_xml_api com a sua conta do BGG '
              'logada, registre um aplicativo e cole o token aqui.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              obscureText: !_visivel,
              // Token é uma cadeia longa sem espaço: teclado sem
              // autocorreção nem letra maiúscula automática.
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Token',
                hintText: 'cole o token aqui',
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _visivel ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  tooltip: _visivel ? 'Esconder' : 'Mostrar',
                  onPressed: () => setState(() => _visivel = !_visivel),
                ),
              ),
            ),
            if (_resultado != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    _resultadoOk ? Icons.check_circle : Icons.error_outline,
                    size: 15,
                    color: _resultadoOk ? viz.good : viz.critical,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _resultado!,
                      style: text.bodySmall?.copyWith(
                        color: _resultadoOk ? viz.good : viz.critical,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _testando ? null : _salvarETestar,
                    child: Text(_testando ? 'Testando...' : 'Salvar e testar'),
                  ),
                ),
                if (temToken) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _testando ? null : _remover,
                    child: const Text('Remover'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Salva e faz uma busca real. Testar de verdade é melhor que só validar o
  /// formato: um token com formato certo mas revogado passaria na validação e
  /// falharia depois, na hora de cadastrar um jogo.
  Future<void> _salvarETestar() async {
    final token = _controller.text.trim();

    setState(() {
      _testando = true;
      _resultado = null;
    });

    await widget.store.setBggToken(token);

    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _testando = false;
        _resultadoOk = false;
        _resultado = 'Token removido. A busca de jogos fica indisponível.';
      });
      return;
    }

    final bgg = BggService(token: token, maxAttempts: 3);
    try {
      final r = await bgg.search('Catan', comCapas: false);
      if (!mounted) return;
      setState(() {
        _testando = false;
        _resultadoOk = true;
        _resultado = 'Funcionou. O BGG respondeu com '
            '${r.length} ${r.length == 1 ? 'resultado' : 'resultados'} '
            'para "Catan".';
      });
    } on CatalogAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _testando = false;
        _resultadoOk = false;
        _resultado = e.message;
      });
    } on CatalogException catch (e) {
      if (!mounted) return;
      setState(() {
        _testando = false;
        _resultadoOk = false;
        _resultado = e.message;
      });
    } finally {
      bgg.dispose();
    }
  }

  Future<void> _remover() async {
    _controller.clear();
    await widget.store.setBggToken(null);
    if (!mounted) return;
    setState(() {
      _resultadoOk = false;
      _resultado = 'Token removido.';
    });
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(rotulo, style: text.bodyMedium)),
          Text(
            valor,
            style: text.bodyMedium?.copyWith(
              color: viz.inkPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
