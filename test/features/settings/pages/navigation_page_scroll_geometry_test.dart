import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/auth/pages/login_page.dart';
import 'package:Kelivo/features/settings/pages/debug_page.dart';
import 'package:Kelivo/features/search/pages/search_services_page.dart';
import 'package:Kelivo/features/provider/pages/provider_network_page.dart';
import 'package:Kelivo/features/provider/pages/provider_balance_page.dart';
import 'package:Kelivo/features/provider/pages/multi_key_manager_page.dart';
import 'package:Kelivo/features/model/pages/default_model_page.dart';
import 'package:Kelivo/features/provider/pages/providers_page.dart';
import 'package:Kelivo/features/provider/pages/provider_detail_page.dart';
import 'package:Kelivo/features/settings/pages/theme_settings_page.dart';
import 'package:Kelivo/features/settings/pages/network_proxy_page.dart';
import 'package:Kelivo/features/settings/pages/tts_settings_page.dart';
import 'package:Kelivo/features/settings/pages/more_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/layouts/app_scaffold.dart';
import 'package:Kelivo/shared/widgets/top_scroll_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final pages = <String, Widget>{
    'login': const LoginPage(),
    'debug': const DebugPage(),
    'search': const SearchServicesPage(),
    'provider network': const ProviderNetworkPage(
      providerKey: 'Test',
      providerDisplayName: 'Test',
    ),
    'provider balance': const ProviderBalancePage(
      providerKey: 'Test',
      providerDisplayName: 'Test',
    ),
    'keys': const MultiKeyManagerPage(
      providerKey: 'Test',
      providerDisplayName: 'Test',
    ),
    'theme': const ThemeSettingsPage(),
    'proxy': const NetworkProxyPage(),
    'default model': const DefaultModelPage(),
    'TTS': const TtsSettingsPage(),
    'more': const MorePage(),
    'providers': const ProvidersPage(),
    'provider detail': const ProviderDetailPage(
      keyName: 'Test',
      displayName: 'Test',
    ),
  };
  for (final inset in [0.0, 47.0]) {
    for (final page in pages.entries) {
      testWidgets('${page.key} viewport includes navigation (inset $inset)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(375, 664);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(top: inset);
        tester.view.viewPadding = FakeViewPadding(top: inset);
        addTearDown(tester.view.reset);
        final settings = SettingsProvider();
        addTearDown(settings.dispose);
        await tester.pump(const Duration(milliseconds: 300));
        for (var i = 0; i < 16; i++) {
          final name = i == 0 ? 'Test' : 'Test$i';
          await settings.setProviderConfig(
            name,
            ProviderConfig(
              id: name,
              apiKey: '',
              enabled: true,
              name: name,
              baseUrl: 'https://example.test',
              providerType: ProviderKind.openai,
              models: const ['a', 'b'],
            ),
          );
        }
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: settings,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: page.value,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final viewport = (page.key == 'providers' || page.key == 'login')
            ? find.byType(CustomScrollView)
            : page.key == 'more'
            ? find.byType(SingleChildScrollView)
            : find.byType(ListView);
        expect(tester.getTopLeft(viewport.first).dy, 0);
        final overlay = find.byType(TopScrollOverlay);
        expect(tester.getTopLeft(overlay).dy, 0);
        final scrollables = tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        );
        final vertical = scrollables.firstWhere(
          (s) => axisDirectionToAxis(s.position.axisDirection) == Axis.vertical,
        );
        if (vertical.position.maxScrollExtent > 16) {
          vertical.position.jumpTo(
            120.clamp(0, vertical.position.maxScrollExtent).toDouble(),
          );
          await tester.pumpAndSettle();
          final opacity = find.ancestor(
            of: overlay,
            matching: find.byType(AnimatedOpacity),
          );
          expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
          expect(tester.getTopLeft(viewport.first).dy, 0);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
    'nested tab lists include the full toolbar extension as scroll padding',
    (tester) async {
      tester.view.physicalSize = const Size(375, 664);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 47);
      tester.view.viewPadding = const FakeViewPadding(top: 47);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AppScaffold(
            title: const Text('Tabs'),
            appBarBottom: const PreferredSize(
              preferredSize: Size.fromHeight(52),
              child: SizedBox(height: 52),
            ),
            body: PageView(
              children: [
                Builder(
                  builder: (context) => ListView(
                    padding: AppScaffold.scrollPadding(
                      context,
                      const EdgeInsets.all(12),
                    ),
                    children: List.generate(
                      30,
                      (i) => SizedBox(height: 50, child: Text('Row $i')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byType(ListView);
      expect(tester.getTopLeft(list).dy, 0);
      expect(
        tester.widget<ListView>(list).padding!.resolve(TextDirection.ltr).top,
        47 + 56 + 52 + 10,
      );
      await tester.drag(list, const Offset(0, -200));
      await tester.pumpAndSettle();
      final overlay = find.byType(TopScrollOverlay);
      expect(tester.widget<TopScrollOverlay>(overlay).gradientHeight, 108);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: overlay,
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('platform scroll offset drives the shared screen-top mask', (
    tester,
  ) async {
    final offset = ValueNotifier<double>(0);
    addTearDown(offset.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppScaffold(
          title: const Text('Web'),
          topScrollOffset: offset,
          body: const SizedBox.expand(),
        ),
      ),
    );
    final overlay = find.byType(TopScrollOverlay);
    final opacity = find.ancestor(
      of: overlay,
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.getTopLeft(overlay).dy, 0);
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
    offset.value = 17;
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
    offset.value = 0;
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
    await tester.pumpWidget(const SizedBox());
    offset.value = 100; // The disposed page must have removed its listener.
    expect(tester.takeException(), isNull);
  });
  testWidgets('switching tabs uses the visible page scroll position', (
    tester,
  ) async {
    final pages = PageController();
    final first = ScrollController();
    final second = ScrollController();
    addTearDown(pages.dispose);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppScaffold(
          title: const Text('Tabs'),
          body: PageView(
            controller: pages,
            children: [
              for (final controller in [first, second])
                Builder(
                  builder: (context) => ListView.builder(
                    controller: controller,
                    key: PageStorageKey(
                      controller == first ? 'first' : 'second',
                    ),
                    padding: AppScaffold.scrollPadding(
                      context,
                      const EdgeInsets.all(16),
                    ),
                    itemCount: 50,
                    itemExtent: 50,
                    itemBuilder: (_, i) => Text('Row $i'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final overlay = find.byType(TopScrollOverlay);
    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: overlay, matching: find.byType(AnimatedOpacity)),
        )
        .opacity;
    first.jumpTo(200);
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    pages.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    second.jumpTo(200);
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    pages.jumpToPage(0);
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    first.jumpTo(0);
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await tester.pumpWidget(const SizedBox());
  });
}
