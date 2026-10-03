import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/settings/pages/theme_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:Kelivo/shared/widgets/app_list_tile.dart';
import 'package:Kelivo/shared/widgets/app_switch.dart';
import 'package:Kelivo/theme/palettes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpPage(
  WidgetTester tester,
  SettingsProvider settings,
  Locale locale,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ThemeSettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final locale in [
    const Locale('en'),
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    testWidgets('appearance selects and persists color mode ($locale)', (
      tester,
    ) async {
      final settings = SettingsProvider();
      addTearDown(settings.dispose);
      await pumpPage(tester, settings, locale);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ThemeSettingsPage)),
      )!;
      expect(
        find.text(l10n.themeSettingsPageAppearanceSection),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.text(l10n.themeSettingsPageAppearanceSection).last)
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.text(l10n.themeSettingsPageColorApplicationSection),
              )
              .dy,
        ),
      );
      for (final (mode, label, value) in [
        (ThemeMode.light, l10n.settingsPageLightMode, 'light'),
        (ThemeMode.dark, l10n.settingsPageDarkMode, 'dark'),
        (ThemeMode.system, l10n.settingsPageSystemMode, 'system'),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(settings.themeMode, mode);
        expect(find.text(label), findsOneWidget);
        final group = tester.widget<AppListGroup>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AppListGroup),
          ),
        );
        final rows = group.children!.whereType<AppListTile>().toList();
        expect(rows, hasLength(3));
        expect(rows.where((row) => row.selected), hasLength(1));
        expect(rows.where((row) => row.trailing is Icon), hasLength(1));
        expect(rows.firstWhere((row) => row.selected).title, isA<Text>());
        expect(
          (rows.firstWhere((row) => row.selected).title as Text).data,
          label,
        );
        expect(rows.every((row) => !row.showSelectedBackground), isTrue);
        expect(find.byType(Dialog), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('theme_mode_v1'), value);
        expect(find.byType(BottomSheet), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'system mode hides manual palettes and restores selection ($locale)',
      (tester) async {
        final settings = SettingsProvider();
        addTearDown(settings.dispose);
        await pumpPage(tester, settings, locale);
        settings.setDynamicColorSupported(true);
        await settings.setThemePalette(ThemePalettes.green.id);
        await settings.setUseDynamicColor(true);
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(ThemeSettingsPage)),
        )!;
        final manualName = locale.languageCode == 'zh'
            ? ThemePalettes.defaultPalette.displayNameZh
            : ThemePalettes.defaultPalette.displayNameEn;
        expect(
          find.text(l10n.themeSettingsPageDynamicColorSection),
          findsNothing,
        );
        expect(
          find.text(l10n.themeSettingsPageColorPalettesSection),
          findsOneWidget,
        );
        expect(find.text(manualName), findsNothing);
        expect(
          find.text(l10n.themeSettingsPageBackgroundColorTitle),
          findsOneWidget,
        );
        expect(
          find.text(l10n.themeSettingsPageForegroundColorTitle),
          findsOneWidget,
        );
        expect(
          find.text(l10n.themeSettingsPageAccentColorTitle),
          findsOneWidget,
        );

        await Scrollable.ensureVisible(
          tester.element(find.byType(AppSwitch)),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        final paletteGroup = tester.widget<AppListGroup>(
          find.ancestor(
            of: find.byType(AppSwitch),
            matching: find.byType(AppListGroup),
          ),
        );
        expect(paletteGroup.children, hasLength(1));

        await tester.tap(find.byType(AppSwitch));
        await tester.pumpAndSettle();
        expect(settings.useDynamicColor, isFalse);
        expect(find.text(manualName), findsOneWidget);
        expect(settings.themePaletteId, ThemePalettes.green.id);

        await Scrollable.ensureVisible(
          tester.element(find.byType(AppSwitch)),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(AppSwitch));
        await tester.pumpAndSettle();
        expect(settings.useDynamicColor, isTrue);
        expect(find.text(manualName), findsNothing);
        expect(settings.themePaletteId, ThemePalettes.green.id);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({TargetPlatform.android}),
    );
  }

  testWidgets(
    'unsupported devices show manual colors despite a saved system preference',
    (tester) async {
      final settings = SettingsProvider();
      addTearDown(settings.dispose);
      await pumpPage(tester, settings, const Locale('en'));
      await settings.setUseDynamicColor(true);
      settings.setDynamicColorSupported(false);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(ThemePalettes.defaultPalette.displayNameEn),
        200,
      );
      expect(find.byType(AppSwitch), findsNothing);
      expect(
        find.text(ThemePalettes.defaultPalette.displayNameEn),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
