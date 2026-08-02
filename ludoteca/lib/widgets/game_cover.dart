import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Capa do jogo, com cache em disco.
///
/// Depois de baixada uma vez a imagem fica no celular, então a coleção abre
/// normalmente sem internet — só o cadastro de jogo novo precisa de rede.
class GameCover extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    if (url == null || url!.isEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: _Placeholder(name: name),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: url!,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (context, _) => _Skeleton(),
        errorWidget: (context, _, __) => _Placeholder(name: name),
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
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final viz = context.viz;
    return Container(
      color: viz.gridline,
      alignment: Alignment.center,
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
