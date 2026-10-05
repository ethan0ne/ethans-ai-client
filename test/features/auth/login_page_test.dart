import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/api/client_backend_api.dart';
import 'package:Kelivo/features/auth/pages/login_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/shared/widgets/app_button_island.dart';
import 'package:Kelivo/shared/widgets/app_list_tile.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CatalogApi extends ClientBackendApi {
  CatalogApi(this.load) : super(baseUrl: 'https://api.example');
  final Future<List<ClientLoginProvider>> Function() load;
  @override
  Future<List<ClientLoginProvider>> fetchLoginProviders() => load();
}

Widget app(ClientBackendApi api, {double scale = 1, bool dark = false}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: LoginPage(api: api),
  );
}

void main() {
  test(
    'catalog decodes server names and resolves icons against the API origin',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.path, '/__client/auth/oidc/providers');
            expect(request.headers.containsKey('Authorization'), isFalse);
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: [
                  {
                    'id': 'custom',
                    'name': 'Organization',
                    'icon_url': '/__client/auth/oidc/icons/logo.png',
                  },
                  {'id': 'other', 'name': 'Another provider', 'icon_url': null},
                ],
              ),
            );
          },
        ),
      );
      final providers = await ClientBackendApi(
        baseUrl: 'https://api.example',
        dio: dio,
      ).fetchLoginProviders();
      expect(providers.map((p) => p.id), ['custom', 'other']);
      expect(providers.first.name, 'Organization');
      expect(
        providers.first.iconUrl,
        'https://api.example/__client/auth/oidc/icons/logo.png',
      );
      expect(providers.last.iconUrl, isNull);
    },
  );

  test('selected provider and loopback callback reach the OIDC start URL', () {
    final api = CatalogApi(() async => []);
    final uri = Uri.parse(
      api.oidcStartUrl(
        providerId: 'custom id&1',
        returnUri: 'http://127.0.0.1:4567/callback',
      ),
    );
    expect(uri.queryParameters['provider_id'], 'custom id&1');
    expect(uri.queryParameters['return_uri'], 'http://127.0.0.1:4567/callback');
    expect(Uri.parse(api.oidcStartUrl()).queryParameters, isEmpty);
  });

  testWidgets('signed-out globe changes and persists the app language', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_locale_v1': 'en_US'});
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'US',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = SettingsProvider();
    addTearDown(settings.dispose);
    final api = CatalogApi(
      () async => const [
        ClientLoginProvider(id: 'custom', name: 'Organization'),
      ],
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: Consumer<SettingsProvider>(
          builder: (context, settings, _) => MaterialApp(
            locale: settings.appLocaleForMaterialApp,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LoginPage(api: api),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final globe = find.byIcon(Lucide.Globe);
    expect(
      find.ancestor(of: globe, matching: find.byType(AppButtonIsland)),
      findsOneWidget,
    );
    expect(tester.getCenter(globe).dx, greaterThan(375 / 2));
    expect(
      tester.getCenter(globe).dy,
      lessThan(tester.getTopLeft(find.text('Log in to continue')).dy),
    );
    await tester.tap(globe);
    await tester.pumpAndSettle();
    for (final name in ['简体中文', '繁體中文', 'English']) {
      expect(find.text(name), findsWidgets);
    }
    final simplifiedRow = find.widgetWithText(AppListTile, '简体中文');
    expect(
      find.descendant(
        of: simplifiedRow,
        matching: find.text('Chinese, Simplified'),
      ),
      findsOneWidget,
    );
    final englishRow = find.widgetWithText(AppListTile, 'English');
    expect(
      find.descendant(of: englishRow, matching: find.text('Current selection')),
      findsOneWidget,
    );
    expect(find.byIcon(Lucide.Check), findsNothing);
    await tester.tap(find.text('简体中文').first);
    await tester.pumpAndSettle();
    expect(settings.appLocale.languageCode, 'zh');
    expect(find.text('需要登录后继续'), findsOneWidget);
    expect(find.text('使用 Organization 登录'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_locale_v1'), 'zh_CN');

    await tester.tap(globe);
    await tester.pumpAndSettle();
    for (final name in ['简体中文', '繁體中文', 'English']) {
      expect(find.text(name), findsWidgets);
    }
    expect(find.text('当前选择'), findsOneWidget);
    expect(find.text('英语'), findsOneWidget);
    await tester.tap(find.text('繁體中文').first);
    await tester.pumpAndSettle();
    expect(find.text('需要登入後繼續'), findsOneWidget);
    expect(prefs.getString('app_locale_v1'), 'zh_Hant');

    // Language names remain recognizable in a Traditional Chinese UI too.
    await tester.tap(globe);
    await tester.pumpAndSettle();
    for (final name in ['简体中文', '繁體中文', 'English']) {
      expect(find.text(name), findsWidgets);
    }
    expect(find.text('目前選擇'), findsOneWidget);
    expect(find.text('英語'), findsOneWidget);
    // Dismissing without selecting leaves the saved language unchanged.
    Navigator.of(tester.element(find.byType(LoginPage))).pop();
    await tester.pumpAndSettle();
    expect(prefs.getString('app_locale_v1'), 'zh_Hant');

    await tester.tap(globe);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').first);
    await tester.pumpAndSettle();
    expect(find.text('Log in to continue'), findsOneWidget);
    expect(prefs.getString('app_locale_v1'), 'en_US');

    await tester.tap(globe);
    await tester.pumpAndSettle();
    final traditional = AppLocalizations.of(
      tester.element(find.byType(LoginPage)),
    )!;
    await tester.tap(find.text(traditional.settingsPageSystemMode));
    await tester.pumpAndSettle();
    expect(settings.isFollowingSystemLocale, isTrue);
    expect(prefs.getString('app_locale_v1'), 'system');
    expect(find.text('Log in to continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders only the server catalog in supplied order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        CatalogApi(
          () async => const [
            ClientLoginProvider(id: 'custom', name: "Ethan's Account"),
            ClientLoginProvider(id: 'google', name: 'Google'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Log in to continue'), findsOneWidget);
    final first = find.text("Sign in with Ethan's Account");
    final second = find.text('Sign in with Google');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(find.text('Sign in with Apple'), findsNothing);
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading, failure, retry and empty state stay actionable', (
    tester,
  ) async {
    final pending = Completer<List<ClientLoginProvider>>();
    var calls = 0;
    final api = CatalogApi(
      () => ++calls == 1 ? pending.future : Future.value([]),
    );
    await tester.pumpWidget(app(api));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load login options.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.text('No login options are currently available.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final providerCount in [1, 12]) {
      testWidgets(
        'gradient stays fixed during overscroll (${dark ? "dark" : "light"}, $providerCount providers)',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(375, 812));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final providers = List.generate(
            providerCount,
            (i) => ClientLoginProvider(id: '$i', name: 'Organization $i'),
          );
          await tester.pumpWidget(
            app(CatalogApi(() async => providers), dark: dark),
          );
          await tester.pumpAndSettle();
          final gradient = find.descendant(
            of: find.byType(LoginPage),
            matching: find.byType(ShaderMask),
          );
          expect(gradient, findsOneWidget);
          final gradientBounds = tester.getRect(gradient);
          final title = find.text('Log in to continue');
          final titleTop = tester.getTopLeft(title).dy;
          expect(titleTop, lessThan(100));
          final scroll = tester.state<ScrollableState>(find.byType(Scrollable));

          final gesture = await tester.startGesture(const Offset(180, 400));
          await gesture.moveBy(const Offset(0, 30));
          await tester.pump();
          await gesture.moveBy(const Offset(0, 180));
          await tester.pump();
          expect(scroll.position.pixels, lessThan(0));
          expect(tester.getTopLeft(title).dy, greaterThan(titleTop));
          expect(tester.getRect(gradient), gradientBounds);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(scroll.position.pixels, closeTo(0, 0.01));
          expect(tester.getRect(gradient), gradientBounds);

          if (providerCount > 1) {
            await tester.drag(
              find.byType(SingleChildScrollView),
              const Offset(0, -250),
            );
            await tester.pumpAndSettle();
            expect(scroll.position.pixels, greaterThan(0));
            expect(tester.getRect(gradient), gradientBounds);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('small screens and large text can scroll without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final providers = List.generate(
      8,
      (i) =>
          ClientLoginProvider(id: '$i', name: 'A long organization account $i'),
    );
    await tester.pumpWidget(
      app(CatalogApi(() async => providers), scale: 2, dark: true),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1500),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text('Sign in with A long organization account 7'),
      findsOneWidget,
    );
  });
}
