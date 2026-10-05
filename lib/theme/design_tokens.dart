import 'package:flutter/material.dart';

class AppColors {
  static const Color textMuted = Colors.black54;
  static const Color destructiveRed = Color(0xFFE53935);

  static const double modalBarrierAlphaLight = 0.25;
  static const double modalBarrierAlphaDark = 0.72;

  static const Color dialogSurfaceLight = Color(0xE0E8E8E8);
  static const Color dialogSurfaceDark = Color(0xE02C2C2C);
  static const Color dialogTitleLight = Color(0xD9000000);
  static const Color dialogTitleDark = Color(0xE6FFFFFF);
  static const Color dialogBodyLight = Color(0x8C000000);
  static const Color dialogBodyDark = Color(0x99FFFFFF);
  static const Color dialogSecondaryFillLight = Color(0x1A000000);
  static const Color dialogSecondaryFillDark = Color(0x1FFFFFFF);
  static const Color dialogSecondaryForegroundLight = Color(0xD9000000);
  static const Color dialogSecondaryForegroundDark = Color(0xD9FFFFFF);
  static const Color dialogPressOverlayLight = Color(0x1A000000);
  static const Color dialogPressOverlayDark = Color(0x33FFFFFF);
  static const double dialogPressedAlphaLiftLight = 0.06;
  static const double dialogPressedAlphaLiftDark = 0.10;

  static Color modalBarrierColor(Brightness brightness) =>
      Colors.black.withValues(
        alpha: brightness == Brightness.dark
            ? modalBarrierAlphaDark
            : modalBarrierAlphaLight,
      );

  static Color dialogSurface(Brightness brightness) =>
      brightness == Brightness.dark ? dialogSurfaceDark : dialogSurfaceLight;
  static Color dialogTitle(Brightness brightness) =>
      brightness == Brightness.dark ? dialogTitleDark : dialogTitleLight;
  static Color dialogBody(Brightness brightness) =>
      brightness == Brightness.dark ? dialogBodyDark : dialogBodyLight;
  static Color dialogSecondaryFill(Brightness brightness) =>
      brightness == Brightness.dark
      ? dialogSecondaryFillDark
      : dialogSecondaryFillLight;
  static Color dialogSecondaryForeground(Brightness brightness) =>
      brightness == Brightness.dark
      ? dialogSecondaryForegroundDark
      : dialogSecondaryForegroundLight;
  static Color dialogPressOverlay(Brightness brightness) =>
      brightness == Brightness.dark
      ? dialogPressOverlayDark
      : dialogPressOverlayLight;
  static double dialogPressedAlphaLift(Brightness brightness) =>
      brightness == Brightness.dark
      ? dialogPressedAlphaLiftDark
      : dialogPressedAlphaLiftLight;

  /// iOS systemGroupedBackground behind grouped settings cards.
  static const Color groupedBackgroundLight = Color(0xFFF2F2F7);
  static const Color groupedBackgroundDark = Color(0xFF000000);

  /// iOS secondarySystemGroupedBackground for grouped settings cards.
  static const Color groupedSurfaceLight = Color(0xFFFFFFFF);
  static const Color groupedSurfaceDark = Color(0xFF1C1C1E);

  /// Picker sheet/dialog surface between the page and grouped card in dark mode.
  static const Color pickerModalBackgroundDark = Color(0xFF121212);

  /// Secondary label used by grouped-list headings and leading icons.
  static const Color secondaryLabelLight = Color(0xFF8E8E93);
  static const Color secondaryLabelDark = Color(0xFF98989D);

  /// Grouped-list separators: softer than opaque popover separators in light mode.
  static const Color listDividerLight = Color(0xFFE8E8ED);
  static const Color listDividerDark = Color(0xFF3A3A3C);
  static const Color listPressedLight = Color(0xFFEEEFF1);
  static const Color listPressedDark = Color(0xFF2C2C2E);

  /// Neutral card behind expanded hosted context summaries.
  static const Color contextSummarySurfaceLight = Color(0xFFE5E5EA);
  static const Color contextSummarySurfaceDark = Color(0xFF2C2C2E);

  static const Color switchOffTrackLight = Color(0xFFE5E5EA);
  static const Color switchOffTrackDark = Color(0xFF2C2C2E);
  static const Color switchOffThumbLight = Color(0xFFFFFFFF);
  static const Color switchOffThumbDark = Color(0xFFE5E5EA);

  static Color groupedBackground(Brightness brightness) =>
      brightness == Brightness.dark
      ? groupedBackgroundDark
      : groupedBackgroundLight;

  /// Uses the app's selected page background: palette surface or neutral mode.
  static Color groupedBackgroundFor(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static Color groupedSurface(Brightness brightness) =>
      brightness == Brightness.dark ? groupedSurfaceDark : groupedSurfaceLight;

  static Color pickerModalBackground(Brightness brightness) =>
      brightness == Brightness.dark
      ? pickerModalBackgroundDark
      : groupedBackgroundLight;

  static Color secondaryLabel(Brightness brightness) =>
      brightness == Brightness.dark ? secondaryLabelDark : secondaryLabelLight;

  static Color listDivider(Brightness brightness) =>
      brightness == Brightness.dark ? listDividerDark : listDividerLight;

  static Color listPressed(Brightness brightness) =>
      brightness == Brightness.dark ? listPressedDark : listPressedLight;

  /// Accent-tinted pressed state for rows whose idle surface follows the palette.
  static Color listPressedFor(ThemeData theme) {
    final tileColor = theme.listTileTheme.tileColor;
    if (tileColor == null || tileColor.a == 0) {
      return listPressed(theme.brightness);
    }

    final alpha = theme.brightness == Brightness.dark ? 0.28 : 0.20;
    final palettePressed = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: alpha),
      listGroupSurfaceFor(theme),
    );
    return tileColor.a < 1
        ? Color.lerp(
            listPressed(theme.brightness),
            palettePressed,
            tileColor.a,
          )!
        : palettePressed;
  }

  /// Keeps the divider visibly related to the active list palette.
  static Color listDividerFor(ThemeData theme) {
    final tileColor = theme.listTileTheme.tileColor;
    if (tileColor == null || tileColor.a == 0) {
      return listDivider(theme.brightness);
    }

    final paletteDivider = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: 0.12),
      listGroupSurfaceFor(theme),
    );
    return tileColor.a < 1
        ? Color.lerp(
            listDivider(theme.brightness),
            paletteDivider,
            tileColor.a,
          )!
        : paletteDivider;
  }

  /// Resolves the current row surface without transparent-to-black tweening.
  ///
  /// During `AnimatedTheme`, Flutter lerps an opaque palette tile color from
  /// `Colors.transparent`, whose RGB channels are black. Recover the opaque
  /// target tint and blend it over the neutral group surface at the same alpha
  /// so rows and their group surface transition together without flashing dark.
  static Color listGroupSurfaceFor(ThemeData theme) {
    final tileColor = theme.listTileTheme.tileColor;
    if (tileColor == null || tileColor.a == 0) {
      return groupedSurface(theme.brightness);
    }
    if (tileColor.a >= 1) return tileColor;

    final alpha = tileColor.a;
    int unpremultiply(int channel) =>
        (channel / alpha).round().clamp(0, 255).toInt();
    final target = Color.fromARGB(
      255,
      unpremultiply(tileColor.red),
      unpremultiply(tileColor.green),
      unpremultiply(tileColor.blue),
    );
    return Color.lerp(groupedSurface(theme.brightness), target, alpha)!;
  }

  /// Idle row fill; neutral mode remains transparent over its parent surface.
  static Color listTileBackgroundFor(ThemeData theme) {
    final tileColor = theme.listTileTheme.tileColor;
    if (tileColor == null || tileColor.a == 0) return Colors.transparent;
    return tileColor.a < 1 ? listGroupSurfaceFor(theme) : tileColor;
  }

  static Color contextSummarySurface(Brightness brightness) =>
      brightness == Brightness.dark
      ? contextSummarySurfaceDark
      : contextSummarySurfaceLight;

  static Color switchOffTrack(Brightness brightness) =>
      brightness == Brightness.dark ? switchOffTrackDark : switchOffTrackLight;

  static Color switchOffThumb(Brightness brightness) =>
      brightness == Brightness.dark ? switchOffThumbDark : switchOffThumbLight;
}

class AppShadows {
  static List<BoxShadow> soft = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];
}

abstract final class AppRadius {
  static const double sm = 6;
  static const double listIcon = 15;
  static const double md = 20;
  static const double capsule = 28;
  static const double dialogButton = 22;
  static const double dialogSurface = 38;
}

class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}
