import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Uma versão publicada na página de releases do GitHub.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.apkUrl,
    required this.apkSize,
    required this.notes,
  });

  final String version;
  final String apkUrl;
  final int apkSize;
  final String notes;
}

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Procura versão nova do app na página de releases do repositório e instala.
///
/// O app não está em loja, então quem atualiza é ele mesmo: cada versão
/// publicada é um release `vX.Y.Z` com o APK anexado (ver
/// `ferramentas/publicar-versao.ps1`). A consulta é à API pública do GitHub,
/// sem token — o limite de 60 por hora por IP sobra para uma consulta por
/// abertura do app.
///
/// O APK baixado vai para o cache do app e é entregue ao instalador do
/// Android pelo canal nativo do `MainActivity`. Na primeira vez o Android
/// pede para liberar "instalar apps desconhecidos" para a Ludoteca.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _latest = 'https://api.github.com/repos/'
      'matheusmerlim1/ludoteca-boardgames/releases/latest';
  static const _canal = MethodChannel('ludoteca/atualizacao');

  /// Versão instalada (o `versionName` do APK, ex.: "1.1.0").
  Future<String> installedVersion() async =>
      await _canal.invokeMethod<String>('versao') ?? '0.0.0';

  /// O release mais novo, se for posterior ao instalado; senão `null`.
  Future<AppRelease?> checkForUpdate() async {
    final release = await latestRelease();
    if (release == null) return null;
    final atual = await installedVersion();
    return isNewer(release.version, atual) ? release : null;
  }

  /// Último release publicado com um APK anexado.
  Future<AppRelease?> latestRelease() async {
    late http.Response res;
    try {
      res = await _client.get(Uri.parse(_latest), headers: const {
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw UpdateException('A página de versões demorou para responder.');
    } on SocketException {
      throw UpdateException('Sem conexão para procurar atualização.');
    }
    // 404 = ainda não há release publicado.
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw UpdateException(
          'A página de versões respondeu ${res.statusCode}.');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final assets = (json['assets'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final apk = assets.where(
        (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'));
    if (apk.isEmpty) return null;
    return AppRelease(
      version: (json['tag_name'] as String? ?? '').replaceFirst('v', ''),
      apkUrl: apk.first['browser_download_url'] as String,
      apkSize: (apk.first['size'] as num?)?.toInt() ?? 0,
      notes: (json['body'] as String? ?? '').trim(),
    );
  }

  /// Baixa o APK para o cache, avisando o progresso (0 a 1), e devolve o
  /// arquivo.
  Future<File> download(
    AppRelease release, {
    void Function(double progresso)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final arquivo = File(p.join(dir.path, 'ludoteca-${release.version}.apk'));
    final req = http.Request('GET', Uri.parse(release.apkUrl));
    final res = await _client.send(req);
    if (res.statusCode != 200) {
      throw UpdateException('O download respondeu ${res.statusCode}.');
    }
    final total = res.contentLength ?? release.apkSize;
    var recebido = 0;
    final saida = arquivo.openWrite();
    try {
      await for (final pedaco in res.stream) {
        saida.add(pedaco);
        recebido += pedaco.length;
        if (total > 0) onProgress?.call(recebido / total);
      }
    } finally {
      await saida.close();
    }
    if (total > 0 && recebido != total) {
      throw UpdateException('O download veio incompleto. Tente de novo.');
    }
    return arquivo;
  }

  /// Abre o instalador do Android com o APK baixado.
  Future<void> install(File apk) =>
      _canal.invokeMethod('instalar', {'caminho': apk.path});

  /// `true` se [a] é posterior a [b] ("1.10.0" > "1.9.2").
  static bool isNewer(String a, String b) {
    List<int> partes(String v) => v
        .split('+')
        .first
        .split('.')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList();
    final x = partes(a), y = partes(b);
    for (var i = 0; i < 3; i++) {
      final dx = i < x.length ? x[i] : 0, dy = i < y.length ? y[i] : 0;
      if (dx != dy) return dx > dy;
    }
    return false;
  }
}
