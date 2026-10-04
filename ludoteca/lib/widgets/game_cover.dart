import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Capa do jogo, com cache em disco.
///
/// Depois de baixada uma vez a imagem fica no celular, então a coleção abre
/// normalmente sem internet — só o cadastro de jogo novo precisa de rede.
///
/// **Reinstalar o app apaga esse cache.** Todas as capas precisam ser baixadas
/// de novo na primeira abertura, e se a rede falhar nesse momento a coleção
/// inteira aparece sem capa. Por isso a falha de download não é desenhada igual
/// à ausência de capa: uma é "este jogo não tem imagem cadastrada", a outra é
/// "não consegui baixar agora", e tratar as duas como a mesma tela de iniciais
/// esconde justamente a que tem conserto.
class GameCover extends StatefulWidget {
  const GameCover({
    super.key,
    required this.url,
    required this.name,
    this.borderRadius = 12,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final String name;
  final double borderRadius;
  final BoxFit fit;

  @override
  State<GameCover> createState() => _GameCoverState();
}

class _GameCoverState extends State<GameCover> {
  /// Muda para forçar o `CachedNetworkImage` a tentar o download de novo — a
  /// chave nova descarta o estado de erro do widget anterior.
  int _tentativa = 0;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final url = widget.url;

    if (url == null || url.isEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: _Placeholder(name: widget.name),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        key: ValueKey('$url#$_tentativa'),
        imageUrl: url,
        fit: widget.fit,
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (context, _) => _Skeleton(),
        errorWidget: (context, _, __) => _Placeholder(
          name: widget.name,
          // Tocar tenta baixar de novo. Sem isso, uma queda de rede de dez
          // segundos deixa a lista sem capa até você fechar e abrir o app.
          onTentarDeNovo: () => setState(() => _tentativa++),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(color: context.viz.gridline);
  }
}

/// Sem capa: as iniciais do jogo sobre um fundo neutro. Nunca uma cor de
/// série — isso é ausência de dado, não identidade de uma categoria.
///
/// Com [onTentarDeNovo], as iniciais ganham uma marca de "não baixou": o jogo
/// **tem** capa cadastrada e o download é que falhou. É a diferença entre um
/// dado que não existe e um que só não chegou.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.name, this.onTentarDeNovo});

  final String name;
  final VoidCallback? onTentarDeNovo;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;

    return GestureDetector(
      onTap: onTentarDeNovo,
      child: Container(
        color: viz.gridline,
        alignment: Alignment.center,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  _iniciais(name),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: viz.inkMuted,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            if (onTentarDeNovo != null)
              Positioned(
                right: 2,
                bottom: 2,
                child: Icon(
                  Icons.cloud_off,
                  size: 12,
                  color: viz.inkMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _iniciais(String nome) {
    final palavras = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty && RegExp(r'[A-Za-zÀ-ÿ0-9]').hasMatch(p[0]))
        .toList();
    if (palavras.isEmpty) return '?';
    if (palavras.length == 1) {
      return palavras.first.substring(0, palavras.first.length.clamp(0, 2)).toUpperCase();
    }
    return (palavras[0][0] + palavras[1][0]).toUpperCase();
  }
}
