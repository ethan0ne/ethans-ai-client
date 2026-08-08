import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/api/client_backend_api.dart';
import '../services/api/client_backend_config.dart';
import '../services/api/client_backend_session.dart';
import '../services/chat/chat_service.dart';
import 'assistant_provider.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Owns the Kelivo-hosted-client account session: JWT persistence, sign
/// in/up/out, and the current user's profile/balance. Separate from
/// `UserProvider` (local display name/avatar only, no account concept —
/// see kelivo-arch.md 8).
class AuthProvider extends ChangeNotifier with WidgetsBindingObserver {
  AuthProvider({ClientBackendApi? api, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    _api = api ?? ClientBackendApi(baseUrl: clientBackendBaseUrl);
    // All ClientBackendApi instances share these callbacks because most
    // hosted call sites construct a short-lived API object per request.
    ClientBackendApi.onTokenRenewed = _applyRenewedAccessToken;
    ClientBackendApi.onUnauthorized = _handleUnauthorized;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restore());
  }

  static const _tokenKey = 'client_auth_token';
  static const _refreshTokenKey = 'client_auth_refresh_token';

  late final ClientBackendApi _api;
  final FlutterSecureStorage _storage;
  Timer? _refreshTimer;
  Future<ClientAuthTokenResult>? _refreshInFlight;
  Future<void> _tokenWriteInFlight = Future<void>.value();
  int _sessionGeneration = 0;
  bool _isRestoring = true;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  String? _token;
  String? get token => _token;

  ClientUserInfo? _user;
  ClientUserInfo? get user => _user;

  String? _lastError;
  String? get lastError => _lastError;

  bool _busy = false;
  bool get busy => _busy;

  /// Applies the backend's optional passive-renewal header only when it was
  /// generated for the access token that is still current. This prevents a
  /// slow response from an older request overwriting a newer token.
  Future<void> _applyRenewedAccessToken(
    String requestToken,
    String renewedToken,
  ) {
    late Future<void> operation;
    operation = _tokenWriteInFlight.then(
      (_) => _applyRenewedAccessTokenOnce(requestToken, renewedToken),
    );
    _tokenWriteInFlight = operation.catchError((_) {});
    return operation;
  }

  Future<void> _applyRenewedAccessTokenOnce(
    String requestToken,
    String renewedToken,
  ) async {
    if (_status == AuthStatus.signedOut || _token != requestToken) return;
    await _storage.write(key: _tokenKey, value: renewedToken);
    if (_status == AuthStatus.signedOut || _token != requestToken) return;
    _token = renewedToken;
    _setSessionMirror();
  }

  Future<void> _restore() async {
    final generation = _sessionGeneration;
    try {
      final savedToken = await _storage.read(key: _tokenKey);
      final savedRefreshToken = await _storage.read(key: _refreshTokenKey);
      if (generation != _sessionGeneration) return;

      if (savedToken == null && savedRefreshToken == null) {
        _status = AuthStatus.signedOut;
        notifyListeners();
        return;
      }

      _token = savedToken;
      var result = savedToken == null
          ? const ClientMeResult.networkError()
          : await _api.fetchMeResult(savedToken);
      if (generation != _sessionGeneration) return;

      if (result.unauthorized || savedToken == null) {
        final refreshed = await _refreshTokens();
        if (generation != _sessionGeneration) return;
        if (refreshed.isSuccess) {
          result = await _api.fetchMeResult(_token!);
        } else if (refreshed.isTransientFailure) {
          // A timeout/DNS/5xx response says nothing about the validity of
          // the stored credentials. Keep them and retry later instead of
          // turning a temporary outage into a forced sign-in.
          result = const ClientMeResult.networkError();
        }
      }

      if (generation != _sessionGeneration) return;
      if (result.unauthorized) {
        await _invalidateLocalSession();
        return;
      }

      _status = AuthStatus.signedIn;
      if (result.user != null) _user = result.user;
      _setSessionMirror();
      _startRefreshTimer();
      if (_token != null) unawaited(ClientBackendSession.refresh());
      notifyListeners();
    } finally {
      if (generation == _sessionGeneration) _isRestoring = false;
    }
  }

  /// All refresh calls share one future because the backend rotates refresh
  /// tokens and therefore cannot safely receive concurrent redemptions.
  Future<ClientAuthTokenResult> _refreshTokens() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    late Future<ClientAuthTokenResult> future;
    future = _refreshTokensOnce().whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
    _refreshInFlight = future;
    return future;
  }

  Future<ClientAuthTokenResult> _refreshTokensOnce() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) {
      return const ClientAuthTokenResult.failure(
        'missing_refresh_token',
        statusCode: 401,
      );
    }

    final generation = _sessionGeneration;
    final result = await _api.refreshToken(refreshToken);
    if (!result.isSuccess || generation != _sessionGeneration) return result;

    // Persist the rotated refresh token first. If the process is killed
    // between these writes, an old access token can still use this new
    // refresh token; the reverse ordering could strand the session with a
    // new access token and an already-revoked refresh token.
    await _storage.write(key: _refreshTokenKey, value: result.refreshToken!);
    await _storage.write(key: _tokenKey, value: result.token!);
    _token = result.token;
    _setSessionMirror();
    return result;
  }

  Future<void> _clearStoredTokens() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  void _setSessionMirror() {
    ClientBackendSession.token = _token;
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(hours: 6), (_) {
      unawaited(_refreshInBackground());
    });
  }

  Future<void> _refreshInBackground() async {
    if (_status != AuthStatus.signedIn) return;
    final result = await _refreshTokens();
    if (!result.isSuccess && !result.isTransientFailure) {
      await _invalidateLocalSession();
    }
  }

  /// Handles a 401 from any authenticated API call. A request that already
  /// observed another request refresh the token can retry with the current
  /// token without redeeming the refresh token again.
  Future<String?> _handleUnauthorized(String failedAccessToken) async {
    if (_isRestoring || _status != AuthStatus.signedIn) return null;
    if (_token != failedAccessToken) return _token;

    final result = await _refreshTokens();
    if (result.isSuccess) return result.token;
    if (!result.isTransientFailure) await _invalidateLocalSession();
    return null;
  }

  Future<void> _invalidateLocalSession() async {
    if (_status == AuthStatus.signedOut && _token == null) return;
    _sessionGeneration++;
    _isRestoring = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _status = AuthStatus.signedOut;
    _token = null;
    _user = null;
    ClientBackendSession.clear();
    await _tokenWriteInFlight;
    await _clearStoredTokens();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshInBackground());
    }
  }

  /// [kelivo-hosted] Finishes an OIDC sign-in — [ticket] is the one-time
  /// value `OidcLoginPage` pulled off the backend's `/auth/oidc/complete`
  /// (WebView interception) or loopback callback (Linux system-browser
  /// exception), redeemed here for the real session token.
  Future<bool> completeOidcLogin(String ticket) async {
    final generation = ++_sessionGeneration;
    _isRestoring = false;
    _busy = true;
    _lastError = null;
    notifyListeners();

    final result = await _api.exchangeOidcTicket(ticket);
    if (generation != _sessionGeneration) return false;
    if (!result.isSuccess) {
      _busy = false;
      _lastError = result.error;
      notifyListeners();
      return false;
    }

    final token = result.token!;
    final refreshToken = result.refreshToken!;
    final me = await _api.fetchMe(token);
    if (generation != _sessionGeneration) return false;
    _busy = false;
    if (me == null) {
      _lastError = 'login_failed';
      notifyListeners();
      return false;
    }

    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _tokenKey, value: token);
    _token = token;
    _user = me;
    _status = AuthStatus.signedIn;
    _setSessionMirror();
    _startRefreshTimer();
    unawaited(ClientBackendSession.refresh());
    notifyListeners();
    return true;
  }

  /// [chatService]/[assistantProvider] are optional only so existing tests
  /// that don't care about chat history/assistants can keep calling
  /// `logout()` bare; real call sites must pass both so hosted-synced
  /// conversations and cloud-hosted assistants don't leak to the next
  /// signed-in (or signed-out) session on the same device.
  Future<void> logout([
    ChatService? chatService,
    AssistantProvider? assistantProvider,
  ]) async {
    // Invalidate callbacks before any await so an old in-flight response
    // cannot resurrect this session after the user signs out.
    ++_sessionGeneration;
    _isRestoring = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _status = AuthStatus.signedOut;
    _token = null;
    _user = null;
    ClientBackendSession.clear();
    final refreshInFlight = _refreshInFlight;
    if (refreshInFlight != null) await refreshInFlight;
    await _tokenWriteInFlight;
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    await _clearStoredTokens();
    if (refreshToken != null) unawaited(_api.logout(refreshToken));
    await chatService?.clearHostedSyncedConversations();
    await assistantProvider?.clearCloudHostedAssistants();
    notifyListeners();
  }

  @override
  void dispose() {
    ++_sessionGeneration;
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
