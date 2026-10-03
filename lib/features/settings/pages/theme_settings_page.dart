import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
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

const double _themeOptionHorizontalPadding = 20;
const double _themePaletteHorizontalPadding = 24;

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final settings = context.watch<SettingsProvider>();
    final canUseDynamicColor =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        settings.dynamicColorSupported;
    final showManualPalettes = !canUseDynamicColor || !settings.useDynamicColor;

    Widget header(String text, {bool first = false}) => Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg - AppSpacing.md,
        first ? 0 : AppSpacing.lg,
        AppSpacing.lg - AppSpacing.md,
        AppSpacing.xs,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          text,
          textAlign: TextAlign.start,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: AppFontWeights.semibold,
            color: AppColors.secondaryLabel(brightness),
          ),
        ),
      ),
    );

    return AppScaffold(
      backgroundColor: AppColors.groupedBackgroundFor(context),

      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(l10n.settingsPageAppearanceAndTheme),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          AppScaffold.scrollContentTop(context),
          16,
          16,
        ),
        children: [
          header(l10n.themeSettingsPageAppearanceSection, first: true),
          _iosSectionCard(
            children: [
              _appearanceOptionRow(
                context,
                icon: Lucide.Monitor,
                label: l10n.settingsPageSystemMode,
                mode: ThemeMode.system,
                selected: settings.themeMode == ThemeMode.system,
              ),
              _iosDivider(context),
              _appearanceOptionRow(
                context,
                icon: Lucide.Sun,
                label: l10n.settingsPageLightMode,
                mode: ThemeMode.light,
                selected: settings.themeMode == ThemeMode.light,
              ),
              _iosDivider(context),
              _appearanceOptionRow(
                context,
                icon: Lucide.Moon,
                label: l10n.settingsPageDarkMode,
                mode: ThemeMode.dark,
                selected: settings.themeMode == ThemeMode.dark,
              ),
            ],
          ),
          header(l10n.themeSettingsPageColorApplicationSection),
          _iosSectionCard(
            children: [
              _themeColorOptionRow(
                context,
                icon: Lucide.Square,
                label: l10n.themeSettingsPageBackgroundColorTitle,
                subtitle: l10n.themeSettingsPageBackgroundColorSubtitle,
                selected: settings.themeBackgroundColorEnabled,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setThemeBackgroundColorEnabled(v),
              ),
              _iosDivider(context),
              _themeColorOptionRow(
                context,
                icon: Lucide.MessageCircle,
                label: l10n.themeSettingsPageForegroundColorTitle,
                subtitle: l10n.themeSettingsPageForegroundColorSubtitle,
                selected: settings.themeForegroundColorEnabled,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setThemeForegroundColorEnabled(v),
              ),
              _iosDivider(context),
              _themeColorOptionRow(
                context,
                icon: Lucide.Palette,
                label: l10n.themeSettingsPageAccentColorTitle,
                subtitle: l10n.themeSettingsPageAccentColorSubtitle,
                selected: settings.themeAccentColorEnabled,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setThemeAccentColorEnabled(v),
              ),
            ],
          ),
          header(l10n.themeSettingsPageColorPalettesSection),
          _iosSectionCard(
            children: [
              if (canUseDynamicColor)
                _iosSwitchRow(
                  context,
                  icon: Lucide.Palette,
                  label: l10n.themeSettingsPageUseDynamicColorTitle,
                  subtitle: l10n.themeSettingsPageUseDynamicColorSubtitle,
                  value: settings.useDynamicColor,
                  onChanged: (v) =>
                      context.read<SettingsProvider>().setUseDynamicColor(v),
                ),
              if (canUseDynamicColor && showManualPalettes)
                _iosDivider(
                  context,
                  horizontalPadding: _themePaletteHorizontalPadding,
                ),
              if (showManualPalettes)
                for (int i = 0; i < ThemePalettes.all.length; i++) ...[
                  _paletteRow(
                    context,
                    palette: ThemePalettes.all[i],
                    selected:
                        settings.themePaletteId == ThemePalettes.all[i].id,
                    onTap: () => context
                        .read<SettingsProvider>()
                        .setThemePalette(ThemePalettes.all[i].id),
                  ),
                  if (i != ThemePalettes.all.length - 1)
                    _iosDivider(
                      context,
                      horizontalPadding: _themePaletteHorizontalPadding,
                    ),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

Widget _appearanceOptionRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required ThemeMode mode,
  required bool selected,
}) {
  final cs = Theme.of(context).colorScheme;
  return AppListTile(
    onTapFeedback: () {
      if (context.read<SettingsProvider>().hapticsOnListItemTap) {
        Haptics.soft();
      }
    },
    onTap: () => context.read<SettingsProvider>().setThemeMode(mode),
    selected: selected,
    showSelectedBackground: false,
    holdHighlightThroughNavigation: false,
    leading: Icon(
      icon,
      size: 24,
      color: AppColors.secondaryLabel(Theme.of(context).brightness),
    ),
    title: Text(label, style: TextStyle(fontSize: 16, color: cs.onSurface)),
    trailing: selected
        ? Icon(Lucide.Check, size: 18, color: cs.primary)
        : const SizedBox(width: 18, height: 18),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: _themeOptionHorizontalPadding,
    ),
    minVerticalPadding: 10,
  );
}

Widget _themeColorOptionRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String subtitle,
  required bool selected,
  required ValueChanged<bool> onChanged,
}) {
  final cs = Theme.of(context).colorScheme;
  final brightness = Theme.of(context).brightness;
  return AppListTile(
    onTapFeedback: () {
      if (context.read<SettingsProvider>().hapticsOnListItemTap) {
        Haptics.soft();
      }
    },
    onTap: () => onChanged(!selected),
    selected: selected,
    selectedColor: cs.onSurface,
    showSelectedBackground: false,
    holdHighlightThroughNavigation: false,
    leading: Icon(icon, size: 24, color: AppColors.secondaryLabel(brightness)),
    title: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 16, color: cs.onSurface),
    ),
    subtitle: Text(
      subtitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, height: 1.2, color: cs.onSurfaceVariant),
    ),
    trailing: selected
        ? Icon(Lucide.Check, size: 18, color: cs.primary)
        : const SizedBox(width: 18, height: 18),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: _themeOptionHorizontalPadding,
    ),
    minVerticalPadding: 10,
  );
}

// --- iOS-style helpers ---

Widget _iosSectionCard({required List<Widget> children}) {
  return AppListGroup.list(children: children);
}

Widget _iosDivider(
  BuildContext context, {
  double horizontalPadding = _themeOptionHorizontalPadding,
}) {
  return AppListDivider.forTile(
    hasLeading: true,
    horizontalPadding: horizontalPadding,
    minLeadingWidth: 24,
    horizontalTitleGap: 16,
    trailingPadding: horizontalPadding,
    height: 1,
    thickness: 1,
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
    contentPadding: const EdgeInsets.symmetric(
      horizontal: _themePaletteHorizontalPadding,
    ),
    minVerticalPadding: 12,
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
    showSelectedBackground: false,
    holdHighlightThroughNavigation: false,
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
    contentPadding: const EdgeInsets.symmetric(
      horizontal: _themePaletteHorizontalPadding,
    ),
    horizontalTitleGap: 16,
    minVerticalPadding: 12,
  );
}
