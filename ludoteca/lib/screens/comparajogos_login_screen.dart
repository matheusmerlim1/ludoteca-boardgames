import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/comparajogos_login.dart';
import '../services/comparajogos_partidas.dart';

/// Login no Comparajogos dentro do app.
///
/// É a própria página de login deles, num WebView. O app não vê a senha: só
/// percebe quando o site voltou do login e pede a ele o token, como o site
/// faz. A sessão fica guardada nos cookies do WebView, na área privada do app.
///
/// Devolve a conta logada, ou nulo se a pessoa voltou sem entrar.
class ComparajogosLoginScreen extends StatefulWidget {
  const ComparajogosLoginScreen({super.key});

  @override
  State<ComparajogosLoginScreen> createState() =>
      _ComparajogosLoginScreenState();
}

class _ComparajogosLoginScreenState extends State<ComparajogosLoginScreen> {
  double _progresso = 0;
  bool _conferindo = false;
  bool _terminou = false;

  Future<void> _aoCarregar(InAppWebViewController c, WebUri? url) async {
    if (_terminou || _conferindo || !ComparajogosWeb.voltouDoLogin(url)) return;
    _conferindo = true;
    try {
      final token = await ComparajogosWeb.tokenPelo(c);
      final conta = ContaComparajogos.doToken(token);
      if (conta != null && mounted) {
        _terminou = true;
        Navigator.of(context).pop(conta);
      }
    } catch (_) {
      // Ainda não logou (ou a página não deixou rodar o script): segue na tela.
    } finally {
      _conferindo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cor = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrar no Comparajogos'),
        bottom: _progresso < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progresso == 0 ? null : _progresso,
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          Material(
            color: cor.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Text(
                'Entre com e-mail e senha. "Entrar com Google" e "com Facebook" '
                'não funcionam dentro de outro app (o Google bloqueia). Se a '
                'sua conta foi criada pelo Google, use "Esqueci minha senha" '
                'para criar uma senha e entre com ela.',
                style: text.bodySmall
                    ?.copyWith(color: cor.onSecondaryContainer),
              ),
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: ComparajogosWeb.login),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
              ),
              onProgressChanged: (_, p) =>
                  setState(() => _progresso = p / 100),
              onLoadStop: _aoCarregar,
              // O site é uma SPA: depois do login a URL muda sem recarregar.
              onUpdateVisitedHistory: (c, url, _) => _aoCarregar(c, url),
            ),
          ),
        ],
      ),
    );
  }
}
