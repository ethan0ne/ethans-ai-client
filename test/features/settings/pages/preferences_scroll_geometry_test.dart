import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/settings/pages/display_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/top_scroll_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final pages = <String, Widget>{
    'preferences': const DisplaySettingsPage(),
    'chat display': const ChatItemDisplaySettingsPage(),
    'rendering': const RenderingSettingsPage(),
    'behavior': const BehaviorStartupSettingsPage(),
    'iOS background': const IosBackgroundSettingsPage(),
    'haptics': const HapticsSettingsPage(),
  };

  for (final topInset in [0.0, 47.0]) {
    for (final entry in pages.entries) {
      testWidgets(
        '${entry.key}: screen-top scroll viewport (inset $topInset)',
        (tester) async {
          tester.view.physicalSize = const Size(375, 664);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = FakeViewPadding(top: topInset);
          tester.view.viewPadding = FakeViewPadding(top: topInset);
          addTearDown(tester.view.reset);
          final settings = SettingsProvider();
          addTearDown(settings.dispose);
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: settings,
              child: MaterialApp(
                locale: const Locale('zh'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: entry.value,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final list = find.byType(ListView);
          // A negative-positioned mask alone cannot satisfy this: the actual
          // viewport must include both the status bar and the navigation bar.
          expect(tester.getTopLeft(list).dy, 0);
          expect(tester.getSize(list).height, 664);
          expect(
            tester
                .widget<ListView>(list)
                .padding!
                .resolve(TextDirection.ltr)
                .top,
            topInset + 56 + 10,
          );
          final overlay = find.byType(TopScrollOverlay);
          expect(tester.getTopLeft(overlay).dy, 0);
          final fade = tester.widget<TopScrollOverlay>(overlay);
          expect(fade.topBandHeight, topInset == 0 ? 32 : topInset);
          expect(fade.gradientHeight, 56);
          final opacity = find.ancestor(
            of: overlay,
            matching: find.byType(AnimatedOpacity),
          );
          expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);

          if (entry.key == 'preferences') {
            final row = find.text('渲染设置');
            final rowBefore = tester.getTopLeft(row).dy;
            final scroll = tester.state<ScrollableState>(
              find.byType(Scrollable),
            );
            // Move this real settings row into the toolbar's fading area.
            final offset = rowBefore - (topInset + 28);
            scroll.position.jumpTo(offset);
            await tester.pumpAndSettle();
            expect(tester.getTopLeft(row).dy, closeTo(topInset + 28, 0.01));
            expect(tester.getTopLeft(list).dy, 0);
            expect(tester.getTopLeft(overlay).dy, 0);
            expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
            scroll.position.jumpTo(0);
            await tester.pumpAndSettle();
            expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
