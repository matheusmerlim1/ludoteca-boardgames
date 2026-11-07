import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Versão nova: mostra o que mudou, baixa com progresso e abre o instalador
/// do Android.
///
/// Com [automatico] (a consulta que roda a cada abertura), o download começa
/// sozinho — ninguém precisa tocar em "baixar". O último passo continua sendo
/// a tela "Atualizar" do próprio Android: app fora da loja não pode se
/// instalar sem essa confirmação.
Future<void> showUpdateDialog(
  BuildContext context,
  AppRelease release, {
  UpdateService? service,
  bool automatico = false,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(
      release: release,
      service: service ?? UpdateService(),
      automatico: automatico,
    ),
  );
}

/// Caixa da primeira abertura depois de atualizar: o que entrou na versão
/// instalada.
Future<void> showNovidadesDialog(
  BuildContext context, {
  required String version,
  required String notes,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Ludoteca atualizada para $version'),
      content: SingleChildScrollView(child: NotasDaVersao(notes: notes)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// O "o que mudou" em duas listas: Novidades e Correções.
class NotasDaVersao extends StatelessWidget {
  const NotasDaVersao({super.key, required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final n = ReleaseNotes.parse(notes);
    if (n.isEmpty) {
      return Text('Melhorias gerais.', style: text.bodyMedium);
    }

    Widget secao(String titulo, IconData icone, List<String> itens) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icone, size: 18),
                  const SizedBox(width: 6),
                  Text(titulo, style: text.titleSmall),
                ],
              ),
              const SizedBox(height: 4),
              for (final i in itens)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: text.bodyMedium),
                      Expanded(child: Text(i, style: text.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (n.novidades.isNotEmpty)
          secao('Novidades', Icons.auto_awesome, n.novidades),
        if (n.correcoes.isNotEmpty)
          secao('Correções', Icons.build_outlined, n.correcoes),
        if (n.outros.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(n.outros, style: text.bodyMedium),
          ),
      ],
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.release,
    required this.service,
    required this.automatico,
  });

  final AppRelease release;
  final UpdateService service;
  final bool automatico;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progresso;
  bool _baixando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    if (widget.automatico) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _baixarEInstalar());
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = widget.release;
    final mb = r.apkSize > 0
        ? ' (${(r.apkSize / 1048576).toStringAsFixed(1)} MB)'
        : '';

    return AlertDialog(
      title: Text('Atualizando para a versão ${r.version}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            NotasDaVersao(notes: r.notes),
            Text(
              'Seus dados continuam no aparelho: a atualização troca só o '
              'app.$mb',
              style: text.bodySmall,
            ),
            if (_baixando) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progresso),
              const SizedBox(height: 6),
              Text(
                _progresso == null
                    ? 'Baixando…'
                    : 'Baixando… ${(_progresso! * 100).round()}%',
                style: text.bodySmall,
              ),
            ],
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(
                _erro!,
                style: text.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _baixando ? null : () => Navigator.pop(context),
          child: const Text('Agora não'),
        ),
        FilledButton(
          onPressed: _baixando ? null : _baixarEInstalar,
          child: Text(_erro == null ? 'Baixar e instalar' : 'Tentar de novo'),
        ),
      ],
    );
  }

  Future<void> _baixarEInstalar() async {
    setState(() {
      _baixando = true;
      _progresso = null;
      _erro = null;
    });
    try {
      final apk = await widget.service.download(
        widget.release,
        onProgress: (v) {
          if (mounted) setState(() => _progresso = v);
        },
      );
      await widget.service.install(apk);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _baixando = false;
          _erro = 'Não consegui atualizar: $e';
        });
      }
    }
  }
}
