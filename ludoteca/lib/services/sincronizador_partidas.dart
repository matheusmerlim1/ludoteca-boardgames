import 'dart:async';

import '../data/game_repository.dart';
import '../models/game.dart';
import 'comparajogos_partidas.dart';

/// Resultado de uma rodada de envio.
class RodadaDeEnvio {
  const RodadaDeEnvio({
    this.enviadas = 0,
    this.apagadas = 0,
    this.falharam = 0,
    this.semLogin = false,
    this.erro,
  });

  final int enviadas;
  final int apagadas;

  /// Saíram da fila de vez (o motivo fica gravado na partida).
  final int falharam;

  /// Parou porque a sessão acabou: falta entrar de novo em Ajustes.
  final bool semLogin;

  /// Parou por falta de rede ou erro passageiro; o resto fica na fila.
  final String? erro;
}

/// Leva a fila de partidas para o Comparajogos.
///
/// A fila mora no banco (`plays.cj_pendente` e a tabela `cj_apagar`), então
/// nada se perde com o app fechado ou sem rede: o que não foi, vai na próxima
/// rodada — a cada partida registrada e a cada abertura do app.
///
/// Uma rodada por vez. Pedir outra no meio só agenda mais uma volta ao fim,
/// para o que entrou na fila durante o envio não esperar a próxima abertura.
class SincronizadorDePartidas {
  SincronizadorDePartidas({required this.repo, required this.envio});

  final GameRepository repo;
  final EnvioDePartidas envio;

  Future<RodadaDeEnvio>? _rodando;
  bool _deNovo = false;

  Future<RodadaDeEnvio> sincronizar() {
    if (_rodando != null) {
      _deNovo = true;
      return _rodando!;
    }
    final f = _rodadas().whenComplete(() => _rodando = null);
    _rodando = f;
    return f;
  }

  Future<RodadaDeEnvio> _rodadas() async {
    RodadaDeEnvio r;
    do {
      _deNovo = false;
      r = await _umaRodada();
    } while (_deNovo && r.erro == null && !r.semLogin);
    return r;
  }

  Future<RodadaDeEnvio> _umaRodada() async {
    var enviadas = 0, apagadas = 0, falharam = 0;
    try {
      // Apagar antes de enviar: uma edição apaga a cópia velha e manda a nova.
      for (final cj in await repo.partidasParaApagarNoComparajogos()) {
        await envio.apagar(cj);
        await repo.apagadaNoComparajogos(cj);
        apagadas++;
      }

      for (final item in await repo.partidasParaEnviar()) {
        final play = await repo.playById(item.playId);
        if (play == null) continue;

        // Editada depois de enviada: some a versão de lá antes de ir a nova.
        if (item.cjId != null) {
          await envio.apagar(item.cjId!);
          await repo.esquecerEnvio(item.playId);
        }

        final PartidaParaEnviar partida;
        try {
          partida = await montar(repo, play.gameId, item.playId);
        } on EnvioException catch (e) {
          await repo.falharEnvio(item.playId, e.message);
          falharam++;
          continue;
        }

        final int cjId;
        try {
          cjId = await envio.criar(partida);
        } on SemLoginException {
          rethrow;
        } on EnvioException catch (e) {
          if (!e.definitivo) rethrow;
          await repo.falharEnvio(item.playId, e.message);
          falharam++;
          continue;
        }

        final aindaExiste =
            await repo.gravarEnvio(item.playId, versao: item.versao, cjId: cjId);
        if (!aindaExiste) {
          // Apagada aqui enquanto ia (o "desfazer" do aviso): apaga lá também.
          await repo.enfileirarApagarNoComparajogos(cjId);
          _deNovo = true;
        }
        enviadas++;
      }
      return RodadaDeEnvio(
          enviadas: enviadas, apagadas: apagadas, falharam: falharam);
    } on SemLoginException {
      return RodadaDeEnvio(
          enviadas: enviadas,
          apagadas: apagadas,
          falharam: falharam,
          semLogin: true);
    } on EnvioException catch (e) {
      return RodadaDeEnvio(
          enviadas: enviadas,
          apagadas: apagadas,
          falharam: falharam,
          erro: e.message);
    }
  }

  /// Traduz a partida do app para o formato do Comparajogos.
  ///
  /// Caixa de série jogada vira o próprio jogo da partida; expansão vira
  /// `addon` do jogo-base — é como o Comparajogos separa as duas coisas.
  static Future<PartidaParaEnviar> montar(
    GameRepository repo,
    int gameId,
    int playId,
  ) async {
    final play = await repo.playById(playId);
    final jogo = await repo.gameById(gameId);
    if (play == null || jogo == null) {
      throw EnvioException('A partida não existe mais.', definitivo: true);
    }

    var principal = jogo;
    final expansoes = <({List<String> nomes, int? bggId})>[];
    if (play.itemGameId != null && play.itemGameId != jogo.id) {
      final item = await repo.gameById(play.itemGameId!);
      if (item != null) {
        if (item.linkKind == LinkKind.expansao) {
          expansoes.add((nomes: _nomes(item), bggId: item.bggId));
        } else {
          principal = item;
        }
      }
    }

    final placar = await repo.scoresFor(playId);
    return PartidaParaEnviar(
      nomesJogo: _nomes(principal),
      bggId: principal.bggId,
      data: play.playedAt,
      // Sem cronometrar, o app conta a média do jogo (a mesma que a folha de
      // registro mostra em "Média"); lá vai o mesmo número, e não zero.
      duracaoMinutos: play.hasMeasuredDuration
          ? play.durationMinutes
          : (jogo.averagePlaytime ?? principal.averagePlaytime),
      notas: play.notes,
      jogadores: [
        for (final s in placar)
          JogadorParaEnviar(nome: s.playerName, pontos: s.score, venceu: s.won),
      ],
      expansoes: expansoes,
    );
  }

  static List<String> _nomes(Game g) => [
        if (g.namePt != null && g.namePt!.trim().isNotEmpty) g.namePt!,
        g.name,
      ];
}
