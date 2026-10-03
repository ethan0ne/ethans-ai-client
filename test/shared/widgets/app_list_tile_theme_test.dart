import 'package:Kelivo/shared/widgets/app_list_tile.dart';
import 'package:Kelivo/theme/design_tokens.dart';
import 'package:Kelivo/theme/palettes.dart';
import 'package:Kelivo/theme/theme_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpTile(
  WidgetTester tester,
  ThemeData theme, {
  bool selected = false,
  BorderRadius? borderRadius,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    home: Scaffold(
      body: AppListTile(
        title: const Text('Settings row'),
        selected: selected,
        borderRadius: borderRadius,
        onTap: () {},
      ),
    ),
  ),
);

BoxDecoration tileDecoration(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.byWidgetPredicate(
      (widget) => widget is DecoratedBox && widget.child is ListTile,
    ),
  );
  return box.decoration as BoxDecoration;
}

Color? tileBackground(WidgetTester tester) => tileDecoration(tester).color;

void main() {
  testWidgets(
    'custom palettes give shared idle rows a nonwhite tonal background',
    (tester) async {
      for (final palette in ThemePalettes.all) {
        if (palette.id == ThemePalettes.defaultId) continue;
        for (final theme in [
          buildLightThemeForScheme(palette.light),
          buildDarkThemeForScheme(palette.dark),
          buildLightThemeForScheme(palette.light, pureBackground: true),
        ]) {
          await pumpTile(tester, theme);
          expect(tileBackground(tester), isNot(Colors.white));
          expect(tileBackground(tester)?.a, 1.0);
        }
      }
    },
  );

  testWidgets('default and accent-only themes retain the parent background', (
    tester,
  ) async {
    for (final palette in [ThemePalettes.defaultPalette, ThemePalettes.green]) {
      await pumpTile(
        tester,
        buildLightThemeForScheme(palette.light, neutralBackground: true),
      );
      expect(tileBackground(tester), Colors.transparent);
    }
  });

  testWidgets('selected stays neutral while pressed feedback follows palette', (
    tester,
  ) async {
    final theme = buildLightThemeForScheme(ThemePalettes.green.light);
    await pumpTile(tester, theme, selected: true);
    expect(tileBackground(tester), AppColors.listPressedLight);
    expect(
      tileDecoration(tester).borderRadius,
      const BorderRadius.all(Radius.circular(AppRadius.md)),
    );

    await pumpTile(tester, theme);
    final idleBackground = tileBackground(tester);
    expect(tileDecoration(tester).borderRadius, isNull);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppListTile)),
    );
    await tester.pump();
    expect(tileBackground(tester), AppColors.listPressedFor(theme));
    expect(tileBackground(tester), isNot(AppColors.listPressedLight));
    expect(tileDecoration(tester).borderRadius, isNull);
    await gesture.cancel();
    await tester.pump();
    expect(tileBackground(tester), idleBackground);
    expect(tileDecoration(tester).borderRadius, isNull);
  });

  test('custom list groups and separators follow their palette', () {
    final theme = buildLightThemeForScheme(ThemePalettes.green.light);
    expect(AppColors.listGroupSurfaceFor(theme), theme.listTileTheme.tileColor);
    expect(AppColors.listDividerFor(theme), isNot(AppColors.listDividerLight));

    final neutralTheme = buildLightThemeForScheme(
      ThemePalettes.green.light,
      neutralBackground: true,
    );
    expect(
      AppColors.listGroupSurfaceFor(neutralTheme),
      AppColors.groupedSurfaceLight,
    );
    expect(AppColors.listDividerFor(neutralTheme), AppColors.listDividerLight);
    expect(AppColors.listPressedFor(neutralTheme), AppColors.listPressedLight);
  });

  testWidgets('standalone rows can explicitly round their press feedback', (
    tester,
  ) async {
    const radius = BorderRadius.all(Radius.circular(12));
    await pumpTile(
      tester,
      buildLightThemeForScheme(ThemePalettes.green.light),
      borderRadius: radius,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppListTile)),
    );
    await tester.pump();
    expect(tileDecoration(tester).borderRadius, radius);
    await gesture.cancel();
    await tester.pump();
  });
}
