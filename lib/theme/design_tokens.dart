import 'package:flutter/material.dart';

class AppColors {
  static const Color textMuted = Colors.black54;

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
}

class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}
