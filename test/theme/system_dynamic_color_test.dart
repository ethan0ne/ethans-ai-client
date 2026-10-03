import 'package:Kelivo/theme/design_tokens.dart';
import 'package:Kelivo/theme/palettes.dart';
import 'package:Kelivo/theme/system_dynamic_color_builder.dart';
import 'package:Kelivo/theme/theme_factory.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:dynamic_color/samples.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in Brightness.values) {
    test(
      'system palette overrides the saved default palette ($brightness)',
      () {
        final system = SampleColorSchemes.green(brightness).harmonized();
        for (final background in [true, false]) {
          for (final foreground in [true, false]) {
            for (final accent in [true, false]) {
              final theme = buildAppThemeForPalette(
                ThemePalettes.defaultPalette,
                brightness: brightness,
                dynamicScheme: system,
                paletteBackgroundEnabled: background,
                paletteForegroundEnabled: foreground,
                paletteAccentEnabled: accent,
              );
              final fallback = brightness == Brightness.light
                  ? ThemePalettes.defaultPalette.light
                  : ThemePalettes.defaultPalette.dark;
              final surface = background
                  ? system.surface
                  : AppColors.groupedBackground(brightness);
              expect(theme.scaffoldBackgroundColor, surface);
              expect(
                theme.colorScheme.primary,
                accent ? system.primary : fallback.primary,
              );
              expect(
                theme.listTileTheme.tileColor,
                foreground
                    ? Color.alphaBlend(
                        system.primary.withValues(
                          alpha: brightness == Brightness.light ? 0.06 : 0.08,
                        ),
                        surface,
                      )
                    : Colors.transparent,
              );
            }
          }
        }
      },
    );

    test(
      'manual palette is restored without a system palette ($brightness)',
      () {
        final theme = buildAppThemeForPalette(
          ThemePalettes.green,
          brightness: brightness,
          paletteBackgroundEnabled: true,
          paletteForegroundEnabled: true,
          paletteAccentEnabled: true,
        );
        final manual = brightness == Brightness.light
            ? ThemePalettes.green.light
            : ThemePalettes.green.dark;
        expect(theme.colorScheme.primary, manual.primary);
        expect(theme.scaffoldBackgroundColor, manual.surface);
        expect(theme.listTileTheme.tileColor?.a, 1);

        final neutral = buildAppThemeForPalette(
          ThemePalettes.defaultPalette,
          brightness: brightness,
          paletteBackgroundEnabled: true,
          paletteForegroundEnabled: true,
          paletteAccentEnabled: true,
        );
        expect(
          neutral.scaffoldBackgroundColor,
          AppColors.groupedBackground(brightness),
        );
        expect(neutral.listTileTheme.tileColor, Colors.transparent);
      },
    );
  }

  group('system palette lifecycle', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DynamicColorPlugin.channel, null);
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
        'refreshes on resume only on Android ($platform)',
        (tester) async {
          var palette = SampleCorePalettes.green;
          var reads = 0;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(DynamicColorPlugin.channel, (
                call,
              ) async {
                if (call.method != DynamicColorPlugin.methodName) return null;
                reads++;
                // Match the typed core-palette array returned by Android.
                // ignore: deprecated_member_use
                return Int64List.fromList(palette.asList());
              });
          ColorScheme? light;
          ColorScheme? dark;
          await tester.pumpWidget(
            SystemDynamicColorBuilder(
              builder: (l, d) {
                light = l;
                dark = d;
                return const SizedBox();
              },
            ),
          );
          await tester.pumpAndSettle();
          expect(
            light?.primary,
            SampleColorSchemes.green(Brightness.light).primary,
          );
          expect(
            dark?.primary,
            SampleColorSchemes.green(Brightness.dark).primary,
          );
          final initialReads = reads;

          palette = SampleCorePalettes.orange;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          final refreshed = platform == TargetPlatform.android;
          expect(reads, initialReads + (refreshed ? 1 : 0));
          expect(
            light?.primary,
            (refreshed
                    ? SampleColorSchemes.orange(Brightness.light)
                    : SampleColorSchemes.green(Brightness.light))
                .primary,
          );
          expect(
            dark?.primary,
            (refreshed
                    ? SampleColorSchemes.orange(Brightness.dark)
                    : SampleColorSchemes.green(Brightness.dark))
                .primary,
          );
          await tester.pumpWidget(const SizedBox());
        },
        variant: TargetPlatformVariant({platform}),
      );
    }

    testWidgets(
      'unavailable system palette falls back without throwing',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(DynamicColorPlugin.channel, (call) async {
              if (call.method == DynamicColorPlugin.methodName) {
                throw PlatformException(code: 'unavailable');
              }
              return null;
            });
        ThemeData? theme;
        await tester.pumpWidget(
          SystemDynamicColorBuilder(
            builder: (light, dark) {
              theme = buildAppThemeForPalette(
                ThemePalettes.green,
                brightness: Brightness.light,
                dynamicScheme: light,
                paletteBackgroundEnabled: true,
                paletteForegroundEnabled: true,
                paletteAccentEnabled: true,
              );
              return const SizedBox();
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(theme?.colorScheme.primary, ThemePalettes.green.light.primary);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant({TargetPlatform.android}),
    );
  });
}
