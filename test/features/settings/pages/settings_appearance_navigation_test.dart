import 'package:Kelivo/core/providers/auth_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/settings/pages/display_settings_page.dart';
import 'package:Kelivo/features/settings/pages/settings_page.dart';
import 'package:Kelivo/features/settings/pages/theme_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/app_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedOutAuth extends ChangeNotifier implements AuthProvider {
  @override
  Null get user => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets(
      'appearance lives in settings and reports current mode ($locale)',
      (tester) async {
        final settings = SettingsProvider();
        final auth = _SignedOutAuth();
        addTearDown(settings.dispose);
        addTearDown(auth.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ],
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const SettingsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SettingsPage)),
        )!;
        final entry = find.text(l10n.settingsPageAppearanceAndTheme);
        await tester.scrollUntilVisible(entry, 180);
        AppSettingsNavTile appearanceRow() => tester.widget<AppSettingsNavTile>(
          find.ancestor(of: entry, matching: find.byType(AppSettingsNavTile)),
        );
        for (final (mode, label) in [
          (ThemeMode.system, l10n.settingsPageSystemMode),
          (ThemeMode.light, l10n.settingsPageLightMode),
          (ThemeMode.dark, l10n.settingsPageDarkMode),
        ]) {
          await settings.setThemeMode(mode);
          await tester.pumpAndSettle();
          expect(appearanceRow().detailText, label);
        }
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(ThemeSettingsPage), findsOneWidget);
        expect(find.text(l10n.settingsPageAppearanceAndTheme), findsOneWidget);
        await tester.tap(find.text(l10n.settingsPageLightMode));
        await tester.pumpAndSettle();
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        expect(appearanceRow().detailText, l10n.settingsPageLightMode);

        final preferences = find.text(l10n.settingsPageDisplay);
        await tester.scrollUntilVisible(preferences, 180);
        await tester.tap(preferences);
        await tester.pumpAndSettle();
        expect(find.byType(DisplaySettingsPage), findsOneWidget);
        expect(find.text(l10n.settingsPageAppearanceAndTheme), findsNothing);
        expect(
          find.text(l10n.displaySettingsPageThemeSettingsTitle),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
