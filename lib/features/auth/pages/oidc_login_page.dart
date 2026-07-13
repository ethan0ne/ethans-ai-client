import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/services/api/client_backend_api.dart';
import '../../../core/services/api/client_backend_config.dart';
import '../../../l10n/app_localizations.dart';

/// [kelivo-hosted] Drives the account.ethan0ne.com OIDC login. Every
/// platform except Linux does this entirely inside an in-app WebView — the
/// backend does the whole authorization_code+PKCE exchange itself (BFF:
/// `client_oidc.py`), so this page only ever needs to watch for the
/// WebView navigating to the backend's own `GET /auth/oidc/complete`
/// landing page and read the one-time `ticket` off its query string, never
/// touching a system browser. Linux has no WebView support in this app
/// (see `webview_page.dart`'s existing Linux fallback), so it's an
/// explicit exception: open the system browser instead, and stand up a
/// local loopback HTTP server to receive the callback that would
/// otherwise have gone to the WebView.
///
/// Pops `null` on success, or an error code string on failure — either the
/// backend's own `error` query param (`account_pending`/`account_banned`,
/// see `client_auth.py`'s `oidc_callback`) or `''` for anything else
/// (network failure, user closed the WebView, ticket exchange rejected).
/// `login_page.dart` maps known codes to a specific message.
class OidcLoginPage extends StatefulWidget {
  const OidcLoginPage({super.key});

  @override
  State<OidcLoginPage> createState() => _OidcLoginPageState();
}

class _OidcLoginPageState extends State<OidcLoginPage> {
  late final ClientBackendApi _api;
  WebViewController? _controller;
  HttpServer? _loopbackServer;
  bool _finishing = false;
  bool _pageLoading = true;

  bool get _isLinux => defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    _api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
    if (_isLinux) {
      scheduleMicrotask(_runLoopbackFlow);
    } else {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: _onNavigationRequest,
            onPageStarted: (_) => setState(() => _pageLoading = true),
            onPageFinished: (_) => setState(() => _pageLoading = false),
          ),
        )
        ..loadRequest(Uri.parse(_api.oidcStartUrl()));
    }
  }

  @override
  void dispose() {
    unawaited(_loopbackServer?.close(force: true));
    super.dispose();
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    // Path-only match — deliberately not also checking `uri.host` against
    // `clientBackendBaseUrl`'s host: the backend's own
    // `client_oidc_redirect_uri` (what the IdP actually redirects back to)
    // is configured independently server-side and legitimately can differ
    // (e.g. `127.0.0.1` there vs `localhost` here in local dev), which made
    // a host check false-negative and let this raw completion page render
    // in the WebView instead of being intercepted. The real security
    // boundary is the ticket itself — single-use, short-TTL, redeemed via
    // an authenticated POST (see `client_oidc.py` `redeem_ticket`) — not
    // this navigation match, so relying on the path alone here is fine.
    if (uri != null && uri.path == '/__client/auth/oidc/complete') {
      unawaited(
        _finish(uri.queryParameters['ticket'], uri.queryParameters['error']),
      );
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _runLoopbackFlow() async {
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _loopbackServer = server;
      final returnUri = 'http://127.0.0.1:${server.port}/callback';
      final launched = await launchUrl(
        Uri.parse(_api.oidcStartUrl(returnUri: returnUri)),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _fail('');
        return;
      }
      final request = await server.first.timeout(const Duration(minutes: 5));
      final params = request.uri.queryParameters;
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body>Signed in — you can close this window.</body></html>',
        );
      await request.response.close();
      await _finish(params['ticket'], params['error']);
    } catch (_) {
      _fail('');
    } finally {
      unawaited(server?.close(force: true));
      _loopbackServer = null;
    }
  }

  Future<void> _finish(String? ticket, String? error) async {
    if (_finishing) return;
    _finishing = true;
    if (ticket == null || ticket.isEmpty) {
      _fail(error ?? '');
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.completeOidcLogin(ticket);
    if (!mounted) return;
    Navigator.of(context).pop(ok ? null : (auth.lastError ?? ''));
  }

  void _fail(String errorCode) {
    if (!mounted) return;
    Navigator.of(context).pop(errorCode);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // [kelivo-hosted] macOS runs with `TitleBarStyle.hidden` (main.dart) —
    // the native traffic lights float over the content with no reserved
    // space of their own, so a plain `AppBar` sits right under them.
    // `image_viewer_page.dart` already worked around this the same way for
    // its own custom top bar; this page is one of the few `Scaffold(appBar:
    // AppBar(...))` pages actually pushed full-screen on desktop (reached
    // straight from `AuthGate`/`LoginPage`, not nested inside
    // `DesktopHomePage`'s own chrome like most other settings pages are),
    // so it needs the same fix.
    final macInset = Platform.isMacOS ? 22.0 : 0.0;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight + macInset),
        child: Padding(
          padding: EdgeInsets.only(top: macInset),
          child: AppBar(title: Text(l10n.authOidcPageTitle)),
        ),
      ),
      body: SafeArea(
        child: _controller != null
            ? Column(
                children: [
                  if (_pageLoading) const LinearProgressIndicator(),
                  Expanded(child: WebViewWidget(controller: _controller!)),
                ],
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(l10n.authOidcSigningIn),
                  ],
                ),
              ),
      ),
    );
  }
}
