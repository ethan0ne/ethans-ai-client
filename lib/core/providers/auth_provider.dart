import 'dart:async';

import 'package:flutter/foundation.dart';
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
class AuthProvider extends ChangeNotifier {
  AuthProvider({ClientBackendApi? api, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    _api = api ?? ClientBackendApi(baseUrl: clientBackendBaseUrl);
    // The backend passively renews a near-expiry access token on any
    // authenticated `/__client/*` request and hands it back via a response
    // header (see `client_deps.py::_maybe_renew_access_token`) — this hook
    // is how any `ClientBackendApi` instance anywhere in the app (most call
    // sites construct their own, not `_api` above) gets that new token
    // persisted. Set once here since this provider is constructed once for
    // the app's lifetime.
    ClientBackendApi.onTokenRenewed = _applyRenewedAccessToken;
    _restore();
  }

  static const _tokenKey = 'client_auth_token';
  static const _refreshTokenKey = 'client_auth_refresh_token';

  late final ClientBackendApi _api;
  final FlutterSecureStorage _storage;

  Future<void> _applyRenewedAccessToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
    _token = token;
    ClientBackendSession.token = token;
  }

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

  Future<void> _restore() async {
    final saved = await _storage.read(key: _tokenKey);
    if (saved == null) {
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    _token = saved;
    var result = await _api.fetchMeResult(saved);
    if (result.unauthorized) {
      // Access token rejected by the server (401/403) — try to silently
      // trade the stored refresh token for a new one before giving up and
      // forcing the user back through sign-in; this is the whole point of
      // having a refresh token instead of a single 24h-lived JWT.
      if (await _tryRefresh()) {
        result = await _api.fetchMeResult(_token!);
      }
    }
    if (result.unauthorized) {
      // Still rejected (no refresh token, or it's genuinely expired/
      // revoked too) — drop everything rather than getting stuck showing a
      // signed-in shell that every request then rejects.
      await _clearStoredTokens();
      _token = null;
      _status = AuthStatus.signedOut;
      ClientBackendSession.clear();
    } else if (result.networkError) {
      // Couldn't reach the server (offline, timeout, 5xx) — this says
      // nothing about whether the token is still valid, so keep it and
      // stay signed in rather than force a logout the user didn't cause.
      // `_user` stays null until a later refresh succeeds; every read site
      // already null-checks it (`auth.user?.email`, etc).
      _status = AuthStatus.signedIn;
      ClientBackendSession.token = _token;
      unawaited(ClientBackendSession.refresh());
    } else {
      _user = result.user;
      _status = AuthStatus.signedIn;
      // [kelivo-hosted] kelivo-arch.md §8 — keep the synchronous session
      // mirror in sync so `SettingsProvider.getProviderConfig` can
      // synthesize the hosted ProviderConfig without a direct AuthProvider
      // reference.
      ClientBackendSession.token = _token;
      unawaited(ClientBackendSession.refresh());
    }
    notifyListeners();
  }

  /// Redeems the stored refresh token for a new access/refresh pair and
  /// persists both. Returns whether it succeeded — `false` means there's no
  /// usable refresh token (missing, expired, revoked, or a network error),
  /// in which case [_token] is left untouched for the caller to fall back
  /// on its own unauthorized-handling.
  Future<bool> _tryRefresh() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) return false;
    final result = await _api.refreshToken(refreshToken);
    if (!result.isSuccess) return false;
    await _storage.write(key: _tokenKey, value: result.token!);
    await _storage.write(key: _refreshTokenKey, value: result.refreshToken!);
    _token = result.token;
    ClientBackendSession.token = _token;
    return true;
  }

  Future<void> _clearStoredTokens() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  /// [kelivo-hosted] Finishes an OIDC sign-in — [ticket] is the one-time
  /// value `OidcLoginPage` pulled off the backend's `/auth/oidc/complete`
  /// (WebView interception) or loopback callback (Linux system-browser
  /// exception), redeemed here for the real session token exactly like
  /// [login] used to turn a password into one.
  Future<bool> completeOidcLogin(String ticket) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    final result = await _api.exchangeOidcTicket(ticket);
    if (!result.isSuccess) {
      _busy = false;
      _lastError = result.error;
      notifyListeners();
      return false;
    }
    final token = result.token!;
    final refreshToken = result.refreshToken!;
    final me = await _api.fetchMe(token);
    _busy = false;
    if (me == null) {
      _lastError = 'login_failed';
      notifyListeners();
      return false;
    }
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    _token = token;
    _user = me;
    _status = AuthStatus.signedIn;
    // [kelivo-hosted] kelivo-arch.md §8
    ClientBackendSession.token = token;
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
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken != null) {
      unawaited(_api.logout(refreshToken));
    }
    await _clearStoredTokens();
    _token = null;
    _user = null;
    _status = AuthStatus.signedOut;
    // [kelivo-hosted] kelivo-arch.md §8
    ClientBackendSession.clear();
    await chatService?.clearHostedSyncedConversations();
    await assistantProvider?.clearCloudHostedAssistants();
    notifyListeners();
  }
}
