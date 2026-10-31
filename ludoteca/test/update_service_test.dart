import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ludoteca/services/update_service.dart';

void main() {
  group('isNewer', () {
    test('compara número a número, não como texto', () {
      expect(UpdateService.isNewer('1.10.0', '1.9.2'), isTrue);
      expect(UpdateService.isNewer('1.9.2', '1.10.0'), isFalse);
    });

    test('mesma versão não é atualização', () {
      expect(UpdateService.isNewer('1.1.0', '1.1.0'), isFalse);
      expect(UpdateService.isNewer('1.1', '1.1.0'), isFalse);
    });

    test('ignora o número de build depois do +', () {
      expect(UpdateService.isNewer('1.2.0+5', '1.1.0'), isTrue);
      expect(UpdateService.isNewer('1.1.0+9', '1.1.0'), isFalse);
    });
  });

  group('latestRelease', () {
    test('lê a tag e o APK anexado', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'tag_name': 'v1.2.0',
              'body': 'Corrige o gráfico do mês.',
              'assets': [
                {'name': 'notas.txt', 'browser_download_url': 'x', 'size': 1},
                {
                  'name': 'ludoteca-1.2.0.apk',
                  'browser_download_url': 'https://exemplo/ludoteca.apk',
                  'size': 2048,
                },
              ],
            }),
            200,
          ));
      final r = await UpdateService(client: client).latestRelease();
      expect(r!.version, '1.2.0');
      expect(r.apkUrl, 'https://exemplo/ludoteca.apk');
      expect(r.apkSize, 2048);
      expect(r.notes, 'Corrige o gráfico do mês.');
    });

    test('sem release publicado devolve null', () async {
      final client = MockClient((_) async => http.Response('{}', 404));
      expect(await UpdateService(client: client).latestRelease(), isNull);
    });

    test('release sem APK devolve null', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode({'tag_name': 'v2.0.0', 'assets': []}), 200));
      expect(await UpdateService(client: client).latestRelease(), isNull);
    });
  });
}
