/// Uma troca de jogos: o que saiu, o que entrou e como o dinheiro se dividiu.
///
/// Trocar não é vender nem doar: nenhum dinheiro entra e nenhum sai. O que
/// acontece é que o valor investido nos jogos que saíram **passa** para os que
/// entraram — eles foram pagos com o que você já tinha. Sem isso o jogo novo
/// nasceria com custo zero e um custo por partida irreal, e o total investido
/// da coleção despencaria sem você ter recuperado nada.
///
/// A troca é N por M de propósito: o caso real é "dei um jogo grande e recebi
/// dois menores" ou "juntei três para receber um". Um único `traded_for_id` no
/// jogo não dava conta disso.
library;

/// Um jogo entrando numa troca.
class TrocaEntrada {
  const TrocaEntrada({required this.gameId, this.valorReferencia});

  final int gameId;

  /// Quanto este jogo vale, para servir de **peso** no rateio.
  ///
  /// É valor de mercado, não dinheiro que você pagou: quem paga a conta é o
  /// jogo que saiu. Nulo = usa o preço já cadastrado no jogo.
  final double? valorReferencia;
}

/// Uma ponta da troca, já com o nome, para a ficha não consultar de novo.
class TradeParte {
  const TradeParte({
    required this.gameId,
    required this.nome,
    required this.precoAntes,
    this.valorReferencia,
    this.parte,
  });

  final int gameId;
  final String nome;

  /// Preço que o jogo tinha antes da troca mexer nele. É o que o desfazer
  /// devolve — recalcular por subtração erra assim que a mesma ponta entra em
  /// duas trocas.
  final double precoAntes;

  /// Só de quem entrou: o peso usado no rateio.
  final double? valorReferencia;

  /// Só de quem entrou: quanto do investido coube a este jogo.
  final double? parte;
}

/// Uma troca inteira, como ela ficou gravada.
class Trade {
  const Trade({
    required this.id,
    required this.quando,
    required this.saiu,
    required this.entrou,
  });

  final int id;
  final DateTime quando;
  final List<TradeParte> saiu;
  final List<TradeParte> entrou;

  /// Quanto de investimento a troca moveu.
  double get total => entrou.fold(0.0, (s, p) => s + (p.parte ?? 0));

  bool envolve(int gameId) =>
      saiu.any((p) => p.gameId == gameId) ||
      entrou.any((p) => p.gameId == gameId);
}

/// Arredonda para centavos. Dinheiro em `double` acumula sobra de binário, e
/// R$ 124,99999999 na tela é o tipo de detalhe que faz duvidar do resto.
double centavos(double v) => (v * 100).roundToDouble() / 100;

/// Divide [total] entre os [pesos], proporcionalmente.
///
/// Esta é a regra que o app promete: um jogo de 500 trocado por um de 300 e um
/// de 100 deixa 75% dos 500 no primeiro e 25% no segundo — os valores dos jogos
/// que entraram servem só para dizer **em que proporção** dividir.
///
/// Dois casos de borda, ambos com resposta em vez de erro:
/// - peso zero ou negativo não puxa nada para si;
/// - se **nenhum** peso for positivo (jogos cadastrados sem preço), divide em
///   partes iguais — é o palpite menos errado, e melhor que deixar tudo no
///   primeiro da lista.
///
/// A sobra do arredondamento vai para a maior parte, para a soma das partes
/// bater exatamente com o total. Um centavo perdido por troca vira diferença
/// visível no total da coleção depois de algumas dezenas delas.
List<double> rateio(double total, List<double> pesos) {
  if (pesos.isEmpty) return const [];

  final positivos = pesos.map((p) => p > 0 ? p : 0.0).toList();
  final soma = positivos.fold(0.0, (a, b) => a + b);

  final partes = soma <= 0
      ? List<double>.filled(pesos.length, centavos(total / pesos.length))
      : positivos.map((p) => centavos(total * p / soma)).toList();

  final sobra = centavos(total - partes.fold(0.0, (a, b) => a + b));
  if (sobra != 0) {
    var maior = 0;
    for (var i = 1; i < partes.length; i++) {
      if (partes[i] > partes[maior]) maior = i;
    }
    partes[maior] = centavos(partes[maior] + sobra);
  }

  return partes;
}
