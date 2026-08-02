import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/game.dart';
import '../models/play.dart';
import '../utils/format.dart';

/// Monta e compartilha textos da coleção.
///
/// Texto simples, não imagem: o WhatsApp e o Instagram Direct aceitam texto de
/// qualquer tamanho, e a folha de compartilhamento do Android deixa **você**
/// escolher para onde vai — o app não precisa integrar com cada rede uma a uma.
///
/// (O Instagram Stories só aceita imagem; para lá, o caminho é um print da
/// aba "Mês", que já é feita para ser vista de relance.)
class ShareService {
  const ShareService();

  /// A lista de jogos que está na tela, um por linha.
  ///
  /// Recebe a lista **já filtrada** e não filtra de novo: se você separou os
  /// jogos para 2 pessoas e mandou, é essa lista que tem de chegar do outro
  /// lado. Filtrar por dentro faria o texto discordar do que você viu.
  ///
  /// Só o nome, sem número de jogadores nem contagem de partidas: quem recebe
  /// quer saber o que você tem, e uma coluna de números a mais em cada linha
  /// só atrapalha a leitura no celular.
  String textoDaColecao(List<GameEntry> entries, {String? filtro}) {
    final lista = [...entries]..sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    if (lista.isEmpty) {
      return filtro == null
          ? 'Minha coleção ainda está vazia.'
          : 'Nenhum jogo meu com esse filtro ($filtro).';
    }

    final linhas = <String>[
      '🎲 Minha coleção — ${lista.length} '
          '${lista.length == 1 ? 'jogo' : 'jogos'}',
      // Sem isto, uma lista filtrada chega parecendo a coleção inteira.
      if (filtro != null) '($filtro)',
      '',
      for (final e in lista) '• ${e.displayName}',
    ];

    return linhas.join('\n');
  }

  /// As partidas de um mês, por jogo e em ordem de quem mais foi à mesa.
  String textoDoMes(
    DateTime mes,
    List<Play> plays,
    GameEntry? Function(int) porId,
  ) {
    final doMes = plays.where(
      (p) => p.playedAt.year == mes.year && p.playedAt.month == mes.month,
    );

    final contagem = <int, int>{};
    for (final p in doMes) {
      contagem[p.gameId] = (contagem[p.gameId] ?? 0) + 1;
    }

    if (contagem.isEmpty) {
      return '🎲 ${mesAnoLongo(mes)}: nenhuma partida registrada.';
    }

    final ordenado = contagem.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        final na = porId(a.key)?.displayName ?? '';
        final nb = porId(b.key)?.displayName ?? '';
        return na.toLowerCase().compareTo(nb.toLowerCase());
      });

    final partidas = contagem.values.fold<int>(0, (a, b) => a + b);

    // Horas do mês, somando o cronometrado com a média de cada jogo.
    var minutos = 0;
    for (final e in ordenado) {
      final jogo = porId(e.key);
      final media = jogo?.game.averagePlaytime;
      if (media != null) minutos += media * e.value;
    }

    final linhas = <String>[
      '🎲 ${mesAnoLongo(mes)}',
      '$partidas ${partidas == 1 ? 'partida' : 'partidas'} · '
          '${ordenado.length} ${ordenado.length == 1 ? 'jogo' : 'jogos'}'
          '${minutos > 0 ? ' · ${horas(minutos / 60)} de mesa' : ''}',
      '',
    ];

    for (final e in ordenado) {
      final nome = porId(e.key)?.displayName ?? 'Removido';
      linhas.add('• $nome — ${e.value}×');
    }

    return linhas.join('\n');
  }

  /// Abre a folha de compartilhamento do Android com o texto.
  Future<void> compartilhar(String texto, {String? assunto}) async {
    await SharePlus.instance.share(
      ShareParams(text: texto, subject: assunto),
    );
  }

  /// Compartilha uma imagem PNG já renderizada.
  ///
  /// O arquivo vai para o diretório temporário porque é isso que ele é: um
  /// intermediário para a folha do Android ler. Guardar na galeria exigiria
  /// permissão de armazenamento para um arquivo que ninguém quer de volta.
  ///
  /// O nome leva o mês para o arquivo que chega no WhatsApp não se chamar
  /// "image.png" no meio de outros vinte.
  Future<void> compartilharImagem(
    Uint8List png, {
    required String nomeDoArquivo,
    String? texto,
    String? assunto,
  }) async {
    final dir = await getTemporaryDirectory();
    final arquivo = File('${dir.path}/$nomeDoArquivo');
    await arquivo.writeAsBytes(png, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(arquivo.path, mimeType: 'image/png')],
        text: texto,
        subject: assunto,
      ),
    );
  }
}

/// Transforma em PNG o que está desenhado dentro de um [RepaintBoundary].
///
/// O `pixelRatio` 3 é o que separa uma imagem que dá para ler de uma borrada:
/// a captura sai no tamanho lógico do widget (uns 360 pontos de largura), e
/// mandar isso cru pelo WhatsApp entrega um retângulo pixelado.
Future<Uint8List?> capturaPng(GlobalKey chave, {double escala = 3}) async {
  final objeto = chave.currentContext?.findRenderObject();
  if (objeto is! RenderRepaintBoundary) return null;

  final imagem = await objeto.toImage(pixelRatio: escala);
  try {
    final bytes = await imagem.toByteData(format: ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  } finally {
    imagem.dispose();
  }
}
