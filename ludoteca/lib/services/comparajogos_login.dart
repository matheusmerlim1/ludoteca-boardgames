import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'comparajogos_partidas.dart';

/// Endereços do login do Comparajogos.
class ComparajogosWeb {
  static const site = 'https://www.comparajogos.com.br';

  /// Começa o login (o site manda para o fórum deles e volta) e cai na
  /// página de partidas do usuário.
  static final login = WebUri('$site/api/auth/login?returnPath=%2Fplays');

  /// Página leve da mesma origem, só para ter onde rodar o `fetch` do token
  /// com os cookies da sessão.
  static final paginaLeve = WebUri('$site/robots.txt');

  /// Troca a sessão (cookie) por um JWT, igual ao site faz. Devolve nulo sem
  /// sessão. Roda dentro do WebView, então o cookie nunca passa pelo app.
  static const jsToken = r'''
    const r = await fetch('/api/auth/token' + (renovar ? '?refresh=1' : ''),
                          {cache: 'no-store', credentials: 'include'});
    if (!r.ok) return null;
    const t = (await r.text()).trim();
    return /^[A-Za-z0-9-_=]+\.[A-Za-z0-9-_=]+\.?[A-Za-z0-9-_.+/=]*$/.test(t) ? t : null;
  ''';

  /// Se a página carregada é o site já de volta do login (e não o fórum ou
  /// o meio do caminho do SSO).
  static bool voltouDoLogin(WebUri? url) {
    if (url == null) return false;
    if (url.host != 'www.comparajogos.com.br') return false;
    final p = url.path;
    return !p.startsWith('/f/') && !p.startsWith('/api/auth');
  }

  /// Pede o token a um WebView já aberto no site.
  static Future<String?> tokenPelo(
    InAppWebViewController c, {
    bool renovar = false,
  }) async {
    final r = await c.callAsyncJavaScript(
      functionBody: jsToken,
      arguments: {'renovar': renovar},
    );
    final v = r?.value;
    return (v is String && v.isNotEmpty) ? v : null;
  }

  /// Esquece a sessão: apaga os cookies do WebView do app (ele só é usado
  /// para isto).
  static Future<void> sair() => CookieManager.instance().deleteAllCookies();
}

/// Busca o token com um WebView invisível, que usa a sessão guardada pelo
/// login (os cookies do WebView ficam na área privada do app).
class FonteDeTokenWebView implements FonteDeToken {
  @override
  Future<String?> token({bool renovar = false}) async {
    final carregou = Completer<InAppWebViewController>();
    final web = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: ComparajogosWeb.paginaLeve),
      onLoadStop: (c, _) {
        if (!carregou.isCompleted) carregou.complete(c);
      },
      onReceivedError: (c, req, erro) {
        if (req.isForMainFrame == true && !carregou.isCompleted) {
          carregou.completeError(EnvioException('Sem conexão com o Comparajogos.'));
        }
      },
    );
    try {
      await web.run();
      final c = await carregou.future.timeout(const Duration(seconds: 20));
      return await ComparajogosWeb.tokenPelo(c, renovar: renovar)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw EnvioException('O Comparajogos demorou demais para responder.');
    } finally {
      await web.dispose();
    }
  }
}
