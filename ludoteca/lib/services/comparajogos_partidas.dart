import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

/// De onde vem o token de acesso do Comparajogos.
///
/// O site não tem chave de API: o login é uma sessão de navegador (cookie),
/// e o próprio site troca essa sessão por um JWT curto em
/// `GET /api/auth/token`. No app, quem guarda a sessão é o WebView (ver
/// `comparajogos_login.dart`); aqui só importa receber o JWT. A interface
/// existe para os testes trocarem o WebView por um token fixo.
abstract class FonteDeToken {
  /// O JWT atual, ou nulo quando ninguém está logado (ou a sessão expirou).
  ///
  /// [renovar] pede um token novo em vez do que estiver guardado — usado
  /// quando a API recusou o anterior.
  Future<String?> token({bool renovar = false});
}

/// Quem está logado, lido do próprio JWT.
class ContaComparajogos {
  const ContaComparajogos({
    required this.id,
    required this.username,
    this.nome,
  });

  final int id;
  final String username;
  final String? nome;

  /// Nome para mostrar: o nome de exibição, ou o de usuário.
  String get exibicao => (nome == null || nome!.trim().isEmpty) ? username : nome!;

  /// Lê o JWT do Comparajogos. O id do usuário é o `sub` — é assim que o
  /// próprio site faz (`id: parseInt(e.sub)`).
  ///
  /// Nulo se o texto não for um JWT com `sub` numérico.
  static ContaComparajogos? doToken(String? jwt) {
    if (jwt == null) return null;
    final partes = jwt.split('.');
    if (partes.length < 2) return null;
    try {
      final carga = utf8.decode(base64Url.decode(base64Url.normalize(partes[1])));
      final m = jsonDecode(carga);
      if (m is! Map) return null;
      final id = int.tryParse('${m['sub']}');
      if (id == null) return null;
      return ContaComparajogos(
        id: id,
        username: '${m['username'] ?? ''}',
        nome: m['name'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Erro ao enviar para o Comparajogos.
class EnvioException implements Exception {
  EnvioException(this.message, {this.definitivo = false});

  final String message;

  /// Verdadeiro quando tentar de novo não adianta (ex.: o jogo não existe lá).
  /// Falso para falta de rede, sessão expirada e afins — esses voltam para a
  /// fila e são tentados de novo depois.
  final bool definitivo;

  @override
  String toString() => message;
}

/// Sem sessão: o usuário precisa entrar de novo em Ajustes.
class SemLoginException extends EnvioException {
  SemLoginException()
      : super('Entre na sua conta do Comparajogos em Ajustes para enviar.');
}

/// Um jogador da partida, como vai para o Comparajogos.
class JogadorParaEnviar {
  const JogadorParaEnviar({required this.nome, this.pontos, this.venceu = false});

  final String nome;
  final double? pontos;
  final bool venceu;
}

/// A partida já traduzida para o que o Comparajogos entende.
class PartidaParaEnviar {
  const PartidaParaEnviar({
    required this.nomesJogo,
    this.bggId,
    required this.data,
    this.duracaoMinutos,
    this.notas,
    this.jogadores = const [],
    this.expansoes = const [],
  });

  /// Para achar o jogo lá quando não há [bggId] (nome em português e o
  /// principal; o primeiro que existir lá vence).
  final List<String> nomesJogo;
  final int? bggId;
  final DateTime data;
  final int? duracaoMinutos;
  final String? notas;
  final List<JogadorParaEnviar> jogadores;

  /// Expansões usadas na partida (vão como `addons`).
  final List<({List<String> nomes, int? bggId})> expansoes;
}

/// Grava e apaga partidas na conta do usuário no Comparajogos.
///
/// As mutations são as mesmas que o site usa na tela /play/add (lidas do
/// código dele em 11/11/2026): `insert_play_one` com os participantes e
/// expansões aninhados, e `deletePlayAndAssociations` para apagar. Não é uma
/// API documentada — se o site mudar, o envio falha e a partida fica na fila,
/// sem perder nada no celular.
class EnvioDePartidas {
  EnvioDePartidas({required this.fonte, http.Client? client})
      : _client = client ?? http.Client();

  final FonteDeToken fonte;
  final http.Client _client;

  static const _endpoint = 'https://api.comparajogos.com.br/v1/graphql';

  String? _token;

  Future<Map<String, dynamic>> _gql(
    String query,
    Map<String, dynamic> variables, {
    bool jaRenovou = false,
  }) async {
    _token ??= await fonte.token();
    if (_token == null) throw SemLoginException();

    late http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: jsonEncode({'query': query, 'variables': variables}),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw EnvioException('O Comparajogos demorou demais para responder.');
    } catch (_) {
      throw EnvioException('Sem conexão com o Comparajogos.');
    }

    Map<String, dynamic>? corpo;
    try {
      final c = jsonDecode(utf8.decode(res.bodyBytes));
      if (c is Map<String, dynamic>) corpo = c;
    } catch (_) {}

    final erros = corpo?['errors'];
    final msg = (erros is List && erros.isNotEmpty)
        ? '${(erros.first as Map?)?['message'] ?? ''}'
        : '';

    // Token vencido: o Hasura responde 200 com "JWTExpired"/"invalid-jwt".
    final tokenRecusado = res.statusCode == 401 ||
        msg.contains('JWT') ||
        msg.contains('jwt') ||
        msg.contains('invalid-headers');
    if (tokenRecusado) {
      _token = null;
      if (jaRenovou) throw SemLoginException();
      _token = await fonte.token(renovar: true);
      if (_token == null) throw SemLoginException();
      return _gql(query, variables, jaRenovou: true);
    }

    if (res.statusCode != 200 || corpo == null) {
      throw EnvioException('O Comparajogos respondeu ${res.statusCode}.');
    }
    if (msg.isNotEmpty) {
      throw EnvioException('O Comparajogos recusou: $msg');
    }
    return (corpo['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  /// Quem está logado agora, ou nulo.
  Future<ContaComparajogos?> conta() async {
    _token ??= await fonte.token();
    return ContaComparajogos.doToken(_token);
  }

  Future<ContaComparajogos> _contaObrigatoria() async {
    final c = await conta();
    if (c == null) throw SemLoginException();
    return c;
  }

  /// Id do jogo no Comparajogos: pelo id do BGG quando há, senão pelo nome.
  Future<int> _produto(List<String> nomes, int? bggId) async {
    if (bggId != null) {
      final d = await _gql(r'''
        query ProdutoPorBgg($bgg: Int!) {
          product(where: {bgg_id: {_eq: $bgg}}, limit: 1) { id }
        }
      ''', {'bgg': bggId});
      final l = (d['product'] as List?) ?? const [];
      if (l.isNotEmpty) return (l.first as Map)['id'] as int;
    }

    for (final termo in nomes.map((n) => n.trim()).where((n) => n.isNotEmpty)) {
      // Nome exato primeiro (sem diferenciar maiúsculas); é o que evita
      // casar "Azul" com "Azul: Pavilhão de Verão".
      final d = await _gql(r'''
        query ProdutoPorNome($nome: String!) {
          product(where: {name: {_ilike: $nome}}, limit: 1, order_by: {id: asc}) { id }
        }
      ''', {'nome': _semCuringas(termo)});
      final l = (d['product'] as List?) ?? const [];
      if (l.isNotEmpty) return (l.first as Map)['id'] as int;
    }

    throw EnvioException(
      'Não achei "${nomes.where((n) => n.trim().isNotEmpty).firstOrNull ?? '?'}" no Comparajogos.',
      definitivo: true,
    );
  }

  /// Escapa `%` e `_`, que no `_ilike` são curingas.
  static String _semCuringas(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  static String _normal(String s) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().trim().split('')) {
      final i = de.indexOf(ch);
      b.write(i >= 0 ? para[i] : ch);
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Se o nome do placar é o próprio dono da conta.
  ///
  /// Aceita o nome de usuário, o nome de exibição inteiro ou só o primeiro
  /// nome dele — no placar do app costuma estar "Matheus", e no Comparajogos
  /// "Matheus Merlim".
  static bool ehODono(String nomeNoPlacar, ContaComparajogos conta) {
    final n = _normal(nomeNoPlacar);
    if (n.isEmpty) return false;
    if (n == _normal(conta.username)) return true;
    final nome = _normal(conta.nome ?? '');
    if (nome.isEmpty) return false;
    return n == nome || n == nome.split(' ').first;
  }

  /// O participante que representa o dono da conta, criado se ainda não há.
  /// O site faz o mesmo na primeira vez que alguém abre a tela de partida.
  Future<int> _participanteDono(ContaComparajogos c) async {
    final d = await _gql(r'''
      query Dono($me: Int!) {
        play_participant(
          where: {user_id: {_eq: $me}, participant_user_id: {_eq: $me}}
          limit: 1
        ) { id }
      }
    ''', {'me': c.id});
    final l = (d['play_participant'] as List?) ?? const [];
    if (l.isNotEmpty) return (l.first as Map)['id'] as int;

    final n = await _gql(r'''
      mutation CriaDono($object: play_participant_insert_input!) {
        insert_play_participant_one(object: $object) { id }
      }
    ''', {
      'object': {'name': c.exibicao, 'participant_user_id': c.id},
    });
    return (n['insert_play_participant_one'] as Map)['id'] as int;
  }

  /// Participante com esse nome na lista do usuário, criado se não existe.
  Future<int> _participante(String nome, ContaComparajogos c) async {
    final d = await _gql(r'''
      query Jogador($me: Int!, $nome: String!) {
        play_participant(
          where: {user_id: {_eq: $me}, name: {_ilike: $nome}}
          limit: 1
          order_by: {id: asc}
        ) { id }
      }
    ''', {'me': c.id, 'nome': _semCuringas(nome.trim())});
    final l = (d['play_participant'] as List?) ?? const [];
    if (l.isNotEmpty) return (l.first as Map)['id'] as int;

    final n = await _gql(r'''
      mutation CriaJogador($object: play_participant_insert_input!) {
        insert_play_participant_one(object: $object) { id }
      }
    ''', {
      'object': {'name': nome.trim()},
    });
    return (n['insert_play_participant_one'] as Map)['id'] as int;
  }

  /// Cria a partida e devolve o id dela no Comparajogos.
  Future<int> criar(PartidaParaEnviar p) async {
    final c = await _contaObrigatoria();
    final produto = await _produto(p.nomesJogo, p.bggId);

    final addons = <int>{};
    for (final e in p.expansoes) {
      try {
        final id = await _produto(e.nomes, e.bggId);
        if (id != produto) addons.add(id);
      } on EnvioException catch (err) {
        // Expansão que o Comparajogos não conhece não impede a partida.
        if (!err.definitivo) rethrow;
      }
    }

    // O site exige ao menos um participante. Sem placar, vai só o dono.
    final jogadores = p.jogadores.where((j) => j.nome.trim().isNotEmpty).toList();
    final participantes = <Map<String, Object?>>[];
    final usados = <int>{};
    if (jogadores.isEmpty) {
      participantes.add({
        'participant_id': await _participanteDono(c),
        'turn_order': 1,
        'total_points': 0,
        'is_winner': false,
      });
    } else {
      for (final j in jogadores) {
        final id = ehODono(j.nome, c)
            ? await _participanteDono(c)
            : await _participante(j.nome, c);
        if (!usados.add(id)) continue; // o mesmo nome duas vezes
        participantes.add({
          'participant_id': id,
          'turn_order': participantes.length + 1,
          'total_points': j.pontos ?? 0,
          'is_winner': j.venceu,
        });
      }
    }

    final d = p.data;
    final data = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    final r = await _gql(r'''
      mutation insertPlay($object: play_insert_input!) {
        insert_play_one(object: $object) { id }
      }
    ''', {
      'object': {
        'product_id': produto,
        'date': data,
        // O site guarda a duração em segundos.
        'duration': (p.duracaoMinutos ?? 0) * 60,
        'notes': p.notas,
        'location_id': null,
        'scorepad': null,
        // MANUAL: o vencedor é o que o app marcou. Com MAX o site recalcula
        // pelo maior placar, o que erra em jogo cooperativo ou de menor
        // pontuação.
        'win_condition': 'MANUAL',
        'public': true,
        'draft': false,
        'participants': {'data': participantes},
        'addons': {
          'data': [for (final a in addons) {'product_id': a}],
        },
        'images': {'data': <Object>[]},
      },
    });
    final criada = r['insert_play_one'];
    if (criada is! Map || criada['id'] is! int) {
      throw EnvioException('O Comparajogos não confirmou a partida.');
    }
    return criada['id'] as int;
  }

  /// Apaga a partida no Comparajogos, com placar, expansões e fotos.
  Future<void> apagar(int idNoComparajogos) async {
    await _contaObrigatoria();
    await _gql(r'''
      mutation deletePlayAndAssociations($playId: Int!) {
        delete_play_image(where: {play_id: {_eq: $playId}}) { affected_rows }
        delete_play_addon(where: {play_id: {_eq: $playId}}) { affected_rows }
        delete_play_play_participant(where: {play_id: {_eq: $playId}}) { affected_rows }
        delete_play_by_pk(id: $playId) { id }
      }
    ''', {'playId': idNoComparajogos});
  }

  void dispose() => _client.close();
}
