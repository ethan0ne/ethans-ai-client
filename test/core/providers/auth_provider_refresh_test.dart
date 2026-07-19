import 'package:dio/dio.dart';
import 'package:Kelivo/core/providers/auth_provider.dart';
import 'package:Kelivo/core/services/api/client_backend_api.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the platform channel `flutter_secure_storage`
/// otherwise talks to — there's no native implementation available under
/// `flutter test`, and mocking at this layer (rather than a MethodChannel
/// mock) is the pattern the plugin itself documents for platform-interface
/// packages (see `FlutterSecureStoragePlatform.instance` setter doc).
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final _values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    return _values[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return _values.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.of(_values);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }
}

/// Fakes the `/__client/auth/*` HTTP surface `AuthProvider._restore` and
/// `_tryRefresh` drive, without touching the network — access tokens
/// starting with `old` are rejected (401) to simulate expiry; refreshing
/// `old-refresh` succeeds once (rotates to `new-refresh`), then is
/// single-use like the real backend.
class _FakeAuthInterceptor extends Interceptor {
  bool refreshTokenConsumed = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/__client/auth/me') {
      final authHeader = options.headers['Authorization'] as String?;
      if (authHeader == 'Bearer new-token') {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'id': 'u1',
              'email': 'a@example.com',
              'username': null,
              'status': 'active',
              'balance': 0.0,
              'title_model_id': null,
              'created_at': '2026-01-01T00:00:00Z',
            },
          ),
        );
        return;
      }
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 401),
        ),
      );
      return;
    }
    if (options.path == '/__client/auth/refresh') {
      final body = options.data as Map;
      if (body['refresh_token'] == 'old-refresh' && !refreshTokenConsumed) {
        refreshTokenConsumed = true;
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {'access_token': 'new-token', 'refresh_token': 'new-refresh'},
          ),
        );
        return;
      }
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 401),
        ),
      );
      return;
    }
    handler.reject(
      DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStoragePlatform fakeStorage;
  late _FakeAuthInterceptor fakeInterceptor;
  late ClientBackendApi api;
  late FlutterSecureStorage storage;

  setUp(() {
    fakeStorage = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = fakeStorage;
    fakeInterceptor = _FakeAuthInterceptor();
    final dio = Dio(BaseOptions())..interceptors.add(fakeInterceptor);
    api = ClientBackendApi(baseUrl: 'https://example.invalid', dio: dio);
    storage = const FlutterSecureStorage();
  });

  test('an expired access token is silently refreshed on restore', () async {
    await storage.write(key: 'client_auth_token', value: 'old-token');
    await storage.write(key: 'client_auth_refresh_token', value: 'old-refresh');

    final auth = AuthProvider(api: api, storage: storage);
    // _restore() runs fire-and-forget from the constructor; wait for it.
    await Future.doWhile(() async {
      await Future<void>.delayed(Duration.zero);
      return auth.status == AuthStatus.unknown;
    });

    expect(auth.status, AuthStatus.signedIn);
    expect(auth.token, 'new-token');
    expect(await storage.read(key: 'client_auth_token'), 'new-token');
    expect(await storage.read(key: 'client_auth_refresh_token'), 'new-refresh');
  });

  test('signs out when there is no refresh token to fall back on', () async {
    await storage.write(key: 'client_auth_token', value: 'old-token');
    // No refresh token stored.

    final auth = AuthProvider(api: api, storage: storage);
    await Future.doWhile(() async {
      await Future<void>.delayed(Duration.zero);
      return auth.status == AuthStatus.unknown;
    });

    expect(auth.status, AuthStatus.signedOut);
    expect(auth.token, isNull);
    expect(await storage.read(key: 'client_auth_token'), isNull);
  });

  test('signs out when the refresh token itself is rejected', () async {
    await storage.write(key: 'client_auth_token', value: 'old-token');
    await storage.write(key: 'client_auth_refresh_token', value: 'garbage');

    final auth = AuthProvider(api: api, storage: storage);
    await Future.doWhile(() async {
      await Future<void>.delayed(Duration.zero);
      return auth.status == AuthStatus.unknown;
    });

    expect(auth.status, AuthStatus.signedOut);
    expect(await storage.read(key: 'client_auth_refresh_token'), isNull);
  });
}
