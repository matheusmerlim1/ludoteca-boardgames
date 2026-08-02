import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/game_repository.dart';
import '../utils/format.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Exporta e restaura a coleção em JSON.
///
/// Os dados vivem só neste celular — nada de servidor, nada de conta. A troca
/// é que **perder o aparelho é perder a coleção**, então o backup aqui não é
/// enfeite: é a única cópia possível. O arquivo sai pelo menu de
/// compartilhamento do Android, para você mandar para o Drive, o e-mail ou o
/// seu próprio WhatsApp.
class BackupService {
  BackupService({GameRepository? repository})
      : _repo = repository ?? GameRepository();

  final GameRepository _repo;

  /// Gera o arquivo e abre o menu de compartilhamento.
  Future<void> exportAndShare() async {
    final dados = await _repo.exportAll();
    final json = const JsonEncoder.withIndent('  ').convert(dados);

    final dir = await getTemporaryDirectory();
    final nome = 'ludoteca-${isoData(DateTime.now())}.json';
    final arquivo = File(p.join(dir.path, nome));
    await arquivo.writeAsString(json);

    // share_plus 12: `SharePlus.instance.share(ShareParams(...))`.
    // A forma antiga (`Share.shareXFiles([...])`) está deprecada.
    final resultado = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(arquivo.path, mimeType: 'application/json')],
        subject: 'Backup da Ludoteca',
        text: 'Backup da coleção em ${data(DateTime.now())}.',
      ),
    );

    if (resultado.status == ShareResultStatus.unavailable) {
      throw BackupException(
        'Não achei nenhum app para receber o arquivo. '
        'O backup ficou salvo em ${arquivo.path}',
      );
    }
  }

  /// Quantos itens um arquivo contém, sem gravar nada ainda.
  ///
  /// Serve para a tela poder dizer "isto vai substituir 42 jogos por 60" antes
  /// de apagar qualquer coisa.
  Future<({Map<String, Object?> dados, int jogos, int partidas})>
      readBackupFile() async {
    // file_picker 11: métodos estáticos. Antes era `FilePicker.platform.*`.
    final escolha = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (escolha == null || escolha.files.isEmpty) {
      throw BackupException('cancelado');
    }

    final arquivo = escolha.files.first;

    final conteudo = arquivo.bytes != null
        ? utf8.decode(arquivo.bytes!)
        : await File(arquivo.path!).readAsString();

    final Object? decodificado;
    try {
      decodificado = jsonDecode(conteudo);
    } on FormatException {
      throw BackupException(
        'Esse arquivo não é um backup válido da Ludoteca '
        '(não consegui ler o JSON).',
      );
    }

    if (decodificado is! Map<String, Object?>) {
      throw BackupException('Esse arquivo não é um backup da Ludoteca.');
    }

    if (!decodificado.containsKey('jogos')) {
      throw BackupException(
        'Esse JSON não parece um backup da Ludoteca — não achei a lista de '
        'jogos dentro dele.',
      );
    }

    final schema = decodificado['schema'];
    if (schema is int && schema > 1) {
      throw BackupException(
        'Esse backup foi feito por uma versão mais nova do app (schema '
        '$schema). Atualize a Ludoteca antes de restaurar.',
      );
    }

    return (
      dados: decodificado,
      jogos: (decodificado['jogos'] as List?)?.length ?? 0,
      partidas: (decodificado['partidas'] as List?)?.length ?? 0,
    );
  }

  /// Substitui a coleção atual. Só chame depois de o usuário confirmar.
  Future<({int jogos, int partidas})> restore(
    Map<String, Object?> dados,
  ) async {
    try {
      return await _repo.importAll(dados);
    } catch (e) {
      throw BackupException('A restauração falhou no meio: $e');
    }
  }
}
