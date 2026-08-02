import 'package:flutter_test/flutter_test.dart';
import 'package:ludoteca/models/game.dart';
import 'package:ludoteca/models/play.dart';
import 'package:ludoteca/services/share_service.dart';

/// Testes do texto que vai para o WhatsApp / Instagram.
///
/// O que importa aqui não é o formato bonito, é o conteúdo estar certo: nada
/// de mandar para os amigos um jogo que você vendeu, ou uma contagem errada.

GameEntry _e(
  int id,
  String nome, {
  Ownership ownership = Ownership.propria,
  bool sold = false,
  LinkKind? linkKind,
  int? minP,
  int? maxP,
  int? minT,
  int? maxT,
}) {
  return GameEntry(
    game: Game(
      id: id,
      name: nome,
      ownership: ownership,
      sold: sold,
      soldPrice: sold ? 100 : null,
      linkKind: linkKind,
      parentId: linkKind == null ? null : 1,
      minPlayers: minP,
      maxPlayers: maxP,
      minPlaytime: minT,
      maxPlaytime: maxT,
    ),
    loggedPlays: 0,
  );
}

void main() {
  const servico = ShareService();

  group('texto da coleção', () {
    test('manda só o nome, sem número de jogadores', () {
      final texto = servico.textoDaColecao([
        _e(1, 'Wingspan', minP: 1, maxP: 5),
        _e(2, 'Azul', minP: 2, maxP: 4),
      ]);

      expect(texto, contains('2 jogos'));
      expect(texto, contains('• Azul'));
      expect(texto, contains('• Wingspan'));
      // A faixa de jogadores polui a lista sem ajudar quem lê no celular.
      expect(texto, isNot(contains('jogadores)')));
    });

    test('sai em ordem alfabética', () {
      final texto = servico.textoDaColecao([
        _e(1, 'Zumbi'),
        _e(2, 'Azul'),
      ]);
      expect(texto.indexOf('Azul'), lessThan(texto.indexOf('Zumbi')));
    });

    test('manda exatamente o que recebeu, sem filtrar de novo', () {
      // Quem decide o recorte é o filtro da tela. Se o serviço filtrasse por
      // conta própria, o texto discordaria da lista que você estava vendo —
      // que é o pior desfecho possível para um botão de compartilhar.
      final texto = servico.textoDaColecao([
        _e(1, 'Meu'),
        _e(2, 'Vendido', sold: true),
        _e(3, 'Unmatched: Buffy', linkKind: LinkKind.serie),
      ]);

      expect(texto, contains('Meu'));
      expect(texto, contains('Vendido'));
      expect(texto, contains('Buffy'));
      expect(texto, contains('3 jogos'));
    });

    test('a lista filtrada chega dizendo qual era o filtro', () {
      final texto = servico.textoDaColecao(
        [_e(1, 'Azul')],
        filtro: 'para 2 jogadores',
      );

      // Sem isto, o amigo conclui que a sua coleção inteira é um jogo só.
      expect(texto, contains('para 2 jogadores'));
      expect(texto, contains('1 jogo'));
    });

    test('filtro sem resultado explica que foi o filtro', () {
      final texto = servico.textoDaColecao([], filtro: 'nunca jogados');
      expect(texto, contains('nunca jogados'));
      expect(texto, isNot(contains('vazia')));
    });

    test('coleção vazia diz isso, em vez de mandar um cabeçalho solto', () {
      expect(servico.textoDaColecao([]), contains('vazia'));
    });
  });

  group('texto do mês', () {
    final jogos = {
      1: _e(1, 'Wingspan', minT: 40, maxT: 70),
      2: _e(2, 'Azul', minT: 30, maxT: 30),
    };
    GameEntry? porId(int id) => jogos[id];

    List<Play> partidas(int mes, Map<int, int> contagem) => [
          for (final e in contagem.entries)
            for (var n = 0; n < e.value; n++)
              Play(gameId: e.key, playedAt: DateTime(2026, mes, 10)),
        ];

    test('conta partidas, jogos e horas', () {
      // Wingspan 3× (média 55 min) + Azul 2× (30 min) = 225 min = 3,8 h.
      final texto = servico.textoDoMes(
        DateTime(2026, 7),
        partidas(7, {1: 3, 2: 2}),
        porId,
      );

      expect(texto, contains('julho de 2026'));
      expect(texto, contains('5 partidas'));
      expect(texto, contains('2 jogos'));
      expect(texto, contains('de mesa'));
    });

    test('ordena por quem mais foi à mesa', () {
      final texto = servico.textoDoMes(
        DateTime(2026, 7),
        partidas(7, {1: 1, 2: 4}),
        porId,
      );
      expect(texto.indexOf('Azul'), lessThan(texto.indexOf('Wingspan')));
      expect(texto, contains('• Azul — 4×'));
    });

    test('ignora partidas de outros meses', () {
      final texto = servico.textoDoMes(
        DateTime(2026, 7),
        [...partidas(7, {1: 2}), ...partidas(6, {2: 9})],
        porId,
      );

      expect(texto, contains('2 partidas'));
      expect(texto, isNot(contains('Azul')));
    });

    test('mês sem partida diz isso', () {
      final texto = servico.textoDoMes(DateTime(2026, 7), const [], porId);
      expect(texto, contains('nenhuma partida'));
    });

    test('jogo removido não quebra o texto', () {
      final texto = servico.textoDoMes(
        DateTime(2026, 7),
        partidas(7, {99: 1}),
        porId,
      );
      expect(texto, contains('Removido'));
    });

    test('sem duração cadastrada, não inventa horas', () {
      final semDuracao = {3: _e(3, 'Sem duração')};
      final texto = servico.textoDoMes(
        DateTime(2026, 7),
        partidas(7, {3: 2}),
        (id) => semDuracao[id],
      );

      expect(texto, contains('2 partidas'));
      expect(texto, isNot(contains('de mesa')));
    });
  });
}
