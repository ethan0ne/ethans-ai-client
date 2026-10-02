import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/palettes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/services/haptics.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import '../../../theme/design_tokens.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/app_switch.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: AppFontWeights.semibold,
          color: cs.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );

    return AppScaffold(
      backgroundColor: AppColors.groupedBackgroundFor(context),
      extendBodyBehindAppBar: false,
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(l10n.displaySettingsPageThemeSettingsTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          if (!kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android &&
              settings.dynamicColorSupported) ...[
            header(l10n.themeSettingsPageDynamicColorSection),
            _iosSectionCard(
              children: [
                _iosSwitchRow(
                  context,
                  icon: Lucide.Palette,
                  label: l10n.themeSettingsPageUseDynamicColorTitle,
                  subtitle: l10n.themeSettingsPageUseDynamicColorSubtitle,
                  value: settings.useDynamicColor,
                  onChanged: (v) =>
                      context.read<SettingsProvider>().setUseDynamicColor(v),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _iosSectionCard(
            children: [
              _iosSwitchRow(
                context,
                icon: Lucide.Square,
                label: l10n.themeSettingsPageUsePureBackgroundTitle,
                subtitle: l10n.themeSettingsPageUsePureBackgroundSubtitle,
                value: settings.usePureBackground,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setUsePureBackground(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Palette,
                label: l10n.themeSettingsPageUseAccentColorOnlyTitle,
                subtitle: l10n.themeSettingsPageUseAccentColorOnlySubtitle,
                value: settings.useAccentColorOnly,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setUseAccentColorOnly(v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // header(l10n.themeSettingsPageColorPalettesSection),
          _iosSectionCard(
            children: [
              for (int i = 0; i < ThemePalettes.all.length; i++) ...[
                _paletteRow(
                  context,
                  palette: ThemePalettes.all[i],
                  selected: settings.themePaletteId == ThemePalettes.all[i].id,
                  onTap: () => context.read<SettingsProvider>().setThemePalette(
                    ThemePalettes.all[i].id,
                  ),
                ),
                if (i != ThemePalettes.all.length - 1) _iosDivider(context),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// --- iOS-style helpers ---

Widget _iosSectionCard({required List<Widget> children}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final settings = context.watch<SettingsProvider>();
      final Color bg = settings.usePureBackground
          ? (isDark ? Colors.black : const Color(0xFFFFFFFF))
          : (isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96));
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
            width: 0.6,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: children),
        ),
      );
    },
  );
}

Widget _iosDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 6,
    thickness: 0.6,
    indent: 12,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

Widget _iosSwitchRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  final cs = Theme.of(context).colorScheme;
  final brightness = Theme.of(context).brightness;
  return AppListTile(
    onTap: () => onChanged(!value),
    leading: Icon(icon, size: 24, color: AppColors.secondaryLabel(brightness)),
    title: Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 16,
        color: cs.onSurface,
        fontWeight: FontWeight.w400,
      ),
    ),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
    trailing: AppSwitch(
      value: value,
      activeTrackColor: cs.primary,
      semanticLabel: label,
      onChanged: onChanged,
    ),
  );
}

Widget _paletteRow(
  BuildContext context, {
  required ThemePalette palette,
  required bool selected,
  required VoidCallback onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final title = Localizations.localeOf(context).languageCode == 'zh'
      ? palette.displayNameZh
      : palette.displayNameEn;
  final color = palette.light.primary;
  return AppListTile(
    onTapFeedback: () {
      if (context.read<SettingsProvider>().hapticsOnListItemTap) {
        Haptics.soft();
      }
    },
    onTap: onTap,
    selected: selected,
    leading: Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
    ),
    title: Text(
      title,
      style: TextStyle(
        fontSize: 15,
        color: cs.onSurface.withValues(alpha: 0.9),
        fontWeight: FontWeight.w400,
      ),
    ),
    trailing: selected
        ? Icon(Lucide.Check, size: 18, color: cs.primary)
        : const SizedBox(width: 18, height: 18),
    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    horizontalTitleGap: 16,
    minVerticalPadding: 12,
  );
}
