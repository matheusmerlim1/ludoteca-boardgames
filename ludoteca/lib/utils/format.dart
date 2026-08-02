/// Formatação pt-BR feita à mão, para não depender do pacote `intl`
/// (que costuma brigar com a versão do Flutter instalada).
library;

const _meses = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

const _mesesLongos = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// Agrupa a parte inteira com ponto: 1234567 -> "1.234.567".
String _agrupaMilhar(String inteiro) {
  final buf = StringBuffer();
  for (var i = 0; i < inteiro.length; i++) {
    if (i > 0 && (inteiro.length - i) % 3 == 0) buf.write('.');
    buf.write(inteiro[i]);
  }
  return buf.toString();
}

/// "R$ 1.234,56". Com [casas] = 0 arredonda para real inteiro.
String dinheiro(num valor, {int casas = 2, bool simbolo = true}) {
  final negativo = valor < 0;
  final texto = valor.abs().toStringAsFixed(casas);
  final partes = texto.split('.');
  final inteiro = _agrupaMilhar(partes[0]);
  final corpo = partes.length > 1 ? '$inteiro,${partes[1]}' : inteiro;
  return '${negativo ? '-' : ''}${simbolo ? 'R\$ ' : ''}$corpo';
}

/// Versão curta para eixos de gráfico: "R$ 1,2 mil", "R$ 340".
String dinheiroCurto(num valor) {
  final v = valor.abs();
  if (v >= 1000000) {
    return 'R\$ ${_semZeroSobrando(valor / 1000000)} mi';
  }
  if (v >= 1000) {
    return 'R\$ ${_semZeroSobrando(valor / 1000)} mil';
  }
  return dinheiro(valor, casas: 0);
}

String _semZeroSobrando(double v) {
  final s = v.toStringAsFixed(1).replaceAll('.', ',');
  return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
}

/// "12/03/2025"
String data(DateTime d) =>
    '${_pad(d.day)}/${_pad(d.month)}/${d.year}';

/// "mar/2025"
String mesAno(DateTime d) => '${_meses[d.month - 1]}/${d.year}';

/// "mar" — para eixo x quando o ano já está no título.
String mesCurto(DateTime d) => _meses[d.month - 1];

/// "março de 2025"
String mesAnoLongo(DateTime d) => '${_mesesLongos[d.month - 1]} de ${d.year}';

String _pad(int n) => n.toString().padLeft(2, '0');

/// Chave ordenável de mês: "2025-03".
String chaveMes(DateTime d) => '${d.year}-${_pad(d.month)}';

DateTime mesDaChave(String chave) {
  final p = chave.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]));
}

/// Só a data, sem hora — evita que fuso/hora suje comparações.
DateTime soData(DateTime d) => DateTime(d.year, d.month, d.day);

String isoData(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

DateTime? parseIsoData(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// "hoje", "ontem", "há 5 dias", "há 3 meses", "há 2 anos", "nunca".
String desdeQuando(DateTime? d, {String vazio = 'nunca'}) {
  if (d == null) return vazio;
  final hoje = soData(DateTime.now());
  final dias = hoje.difference(soData(d)).inDays;

  if (dias < 0) return data(d);
  if (dias == 0) return 'hoje';
  if (dias == 1) return 'ontem';
  if (dias < 30) return 'há $dias dias';

  final meses = _mesesEntre(soData(d), hoje);
  if (meses < 12) return 'há $meses ${meses == 1 ? 'mês' : 'meses'}';

  final anos = meses ~/ 12;
  return 'há $anos ${anos == 1 ? 'ano' : 'anos'}';
}

/// Meses completos entre duas datas (>= 0).
int _mesesEntre(DateTime de, DateTime ate) {
  var m = (ate.year - de.year) * 12 + (ate.month - de.month);
  if (ate.day < de.day) m -= 1;
  return m < 0 ? 0 : m;
}

/// Meses de posse, com piso 1 para não estourar o custo/mês de uma
/// compra recente (um jogo comprado hoje não custa "infinito por mês").
int mesesDePosse(DateTime? compra, {DateTime? ate}) {
  if (compra == null) return 0;
  final fim = soData(ate ?? DateTime.now());
  final m = _mesesEntre(soData(compra), fim);
  return m < 1 ? 1 : m;
}

/// "4 partidas", "1 partida", "nunca jogado".
String contagemPartidas(int n) {
  if (n == 0) return 'nunca jogado';
  return '$n ${n == 1 ? 'partida' : 'partidas'}';
}

/// "2–4 jogadores", "2 jogadores", "—".
String faixaJogadores(int? min, int? max) {
  if (min == null && max == null) return '—';
  final a = min ?? max!;
  final b = max ?? min!;
  if (a == b) return '$a ${a == 1 ? 'jogador' : 'jogadores'}';
  return '$a–$b jogadores';
}

/// "30–60 min", "45 min", "—".
String faixaDuracao(int? min, int? max) {
  if (min == null && max == null) return '—';
  final a = min ?? max!;
  final b = max ?? min!;
  if (a == b) return '$a min';
  return '$a–$b min';
}

/// Minutos em forma legível: 45 -> "45min", 100 -> "1h40", 120 -> "2h".
String duracao(int minutos) {
  if (minutos < 0) return '—';
  if (minutos < 60) return '${minutos}min';
  final h = minutos ~/ 60;
  final m = minutos % 60;
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}

/// Horas acumuladas: 12.5 -> "12,5 h". Acima de 100 arredonda, porque a casa
/// decimal de "137,4 horas" não informa nada.
String horas(double h) {
  if (h >= 100) return '${h.round()} h';
  final s = h.toStringAsFixed(1).replaceAll('.', ',');
  return '${s.endsWith(',0') ? s.substring(0, s.length - 2) : s} h';
}

/// Pontuação de uma partida: 87 -> "87", 12.5 -> "12,5".
///
/// Guarda casa decimal porque existe placar fracionado (e placar negativo, em
/// jogo de penalidade), mas o caso comum é inteiro e não deve virar "87,0".
String pontos(double p) {
  if (p == p.roundToDouble()) return p.round().toString();
  return p.toStringAsFixed(1).replaceAll('.', ',');
}

/// Marca de estimativa. Um número estimado exibido como se fosse medido é o
/// tipo de detalhe que faz o usuário desconfiar de todo o resto.
String talvez(String valor, {required bool estimado}) =>
    estimado ? '≈ $valor' : valor;

/// Peso do BGG: 2.7 -> "2,7".
String peso(double? p) =>
    p == null || p == 0 ? '—' : p.toStringAsFixed(1).replaceAll('.', ',');

/// "38%" — para legenda de pizza.
String porcento(double fracao, {int casas = 0}) =>
    '${(fracao * 100).toStringAsFixed(casas).replaceAll('.', ',')}%';

/// Lê valor em dinheiro digitado à mão, aceitando as duas convenções.
///
/// "1.234,56" (pt-BR) e "1234.56" (teclado numérico do Android, que às vezes
/// só oferece ponto) precisam dar o mesmo número — senão um deslize de
/// pontuação transforma R$ 1.234 em R$ 1,234.
double? parseMoeda(String? bruto) {
  if (bruto == null) return null;
  var t = bruto.trim();
  if (t.isEmpty) return null;

  t = t.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (t.isEmpty || t == '-') return null;

  if (t.contains(',')) {
    // Vírgula presente: ela é o separador decimal, ponto é milhar.
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else {
    // Sem vírgula, o ponto é ambíguo de verdade: "1.500" pode ser mil e
    // quinhentos (milhar pt-BR) ou um e meio (decimal). O que desempata é
    // quantos dígitos vêm depois — separador de milhar é sempre seguido de
    // exatamente 3, e valor em dinheiro tem 1 ou 2 casas decimais.
    final partes = t.split('.');
    if (partes.length > 2) {
      // "1.234.567" — vários pontos só existem como milhar.
      t = t.replaceAll('.', '');
    } else if (partes.length == 2 && partes[1].length == 3) {
      // "1.500" -> 1500. Já "349.90" e "1.5" seguem como decimal.
      t = t.replaceAll('.', '');
    }
  }

  return double.tryParse(t);
}

/// Campo de dinheiro vazio deve virar 0, não null, para os totais somarem.
double parseMoedaOuZero(String? bruto) => parseMoeda(bruto) ?? 0;

/// Valor para preencher um campo editável: sem "R$", com vírgula decimal, e
/// vazio quando é zero (para o campo aparecer com o placeholder).
String moedaParaCampo(double v) =>
    v == 0 ? '' : dinheiro(v, simbolo: false);

const _acentos = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
const _semAcento = 'aaaaaeeeeiiiiooooouuuucn';

/// Normaliza um nome de jogo para comparação.
///
/// Existe porque o mesmo jogo tem grafias diferentes entre catálogos e entre o
/// que você digitou à mão: "Catan: Navegadores", "CATAN – Navegadores",
/// "catan navegadores". Sem isso, o app não reconhece que já tem o jogo.
///
/// Comparar por id não resolve: cada fonte tem a sua numeração, e um jogo
/// cadastrado à mão não tem id de fonte nenhuma.
String normalizaNome(String bruto) {
  var s = bruto.toLowerCase().trim();

  final buf = StringBuffer();
  for (final c in s.split('')) {
    final i = _acentos.indexOf(c);
    buf.write(i >= 0 ? _semAcento[i] : c);
  }
  s = buf.toString();

  // Pontuação vira espaço, e espaços repetidos colapsam.
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  return s;
}

int? parseInteiro(String? bruto) {
  if (bruto == null) return null;
  final t = bruto.trim().replaceAll(RegExp(r'[^0-9\-]'), '');
  if (t.isEmpty) return null;
  return int.tryParse(t);
}
