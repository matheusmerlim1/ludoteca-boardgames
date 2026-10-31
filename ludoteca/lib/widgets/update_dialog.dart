import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Oferece a versão nova: mostra o que mudou, baixa com progresso e abre o
/// instalador do Android.
Future<void> showUpdateDialog(
  BuildContext context,
  AppRelease release, {
  UpdateService? service,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _UpdateDialog(release: release, service: service ?? UpdateService()),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release, required this.service});

  final AppRelease release;
  final UpdateService service;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progresso;
  bool _baixando = false;
  String? _erro;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = widget.release;
    final mb = r.apkSize > 0
        ? ' (${(r.apkSize / 1048576).toStringAsFixed(1)} MB)'
        : '';

    return AlertDialog(
      title: Text('Versão ${r.version} disponível'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r.notes.isNotEmpty) ...[
              Text(r.notes, style: text.bodyMedium),
              const SizedBox(height: 12),
            ],
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
