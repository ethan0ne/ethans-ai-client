import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import '../../../core/services/android_background.dart';
import '../../../core/services/ios_background_generation.dart';
import '../../../core/services/notification_service.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/services/haptics.dart';
import 'package:file_picker/file_picker.dart';
import 'google_fonts_picker_page.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import '../../../theme/design_tokens.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/popup_content_frame.dart';
import '../../../shared/widgets/app_switch.dart';

enum _FontTarget { app, code }

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

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
      title: AppScaffoldTitle(l10n.settingsPageDisplay),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          AppScaffold.scrollContentTop(context),
          16,
          AppScaffold.scrollContentBottom(context),
        ),
        children: [
          _iosSectionCard(
            children: [
              _iosNavRow(
                context,
                icon: Lucide.MessageCircleMore,
                label: l10n.displaySettingsPageChatItemDisplayTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChatItemDisplaySettingsPage(),
                  ),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.TextInitial,
                label: l10n.displaySettingsPageRenderingSettingsTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RenderingSettingsPage(),
                  ),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.eclipse,
                label: l10n.displaySettingsPageBehaviorStartupTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BehaviorStartupSettingsPage(),
                  ),
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Vibrate,
                label: l10n.displaySettingsPageHapticsSettingsTitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HapticsSettingsPage(),
                  ),
                ),
              ),
              _iosDivider(context),
              if (Platform.isAndroid)
                _iosNavRow(
                  context,
                  icon: Lucide.Monitor,
                  label: l10n.displaySettingsPageAndroidBackgroundChatTitle,
                  detailBuilder: (ctx) {
                    final sp = ctx.watch<SettingsProvider>();
                    switch (sp.androidBackgroundChatMode) {
                      case AndroidBackgroundChatMode.off:
                        return Text(
                          l10n.androidBackgroundStatusOff,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        );
                      case AndroidBackgroundChatMode.on:
                        return Text(
                          l10n.androidBackgroundStatusOn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        );
                      case AndroidBackgroundChatMode.onNotify:
                        return Text(
                          l10n.androidBackgroundStatusOther,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        );
                    }
                  },
                  onTap: () => _showAndroidBackgroundChatSheet(context),
                ),
              if (Platform.isAndroid) _iosDivider(context),
              if (Platform.isIOS)
                _iosNavRow(
                  context,
                  icon: Lucide.Activity,
                  label: l10n.displaySettingsPageIosBackgroundChatTitle,
                  detailBuilder: (ctx) {
                    final sp = ctx.watch<SettingsProvider>();
                    return Text(
                      sp.iosBackgroundGenerationEnabled
                          ? l10n.iosBackgroundStatusOn
                          : l10n.iosBackgroundStatusOff,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    );
                  },
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const IosBackgroundSettingsPage(),
                    ),
                  ),
                ),
              if (Platform.isIOS) _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.MessageSquare,
                label: l10n.displaySettingsPageChatMessageBackgroundTitle,
                detailBuilder: (ctx) {
                  final sp = ctx.watch<SettingsProvider>();
                  String labelOf() {
                    switch (sp.chatMessageBackgroundStyle) {
                      case ChatMessageBackgroundStyle.frosted:
                        return l10n
                            .displaySettingsPageChatMessageBackgroundFrosted;
                      case ChatMessageBackgroundStyle.solid:
                        return l10n
                            .displaySettingsPageChatMessageBackgroundSolid;
                      case ChatMessageBackgroundStyle.defaultStyle:
                        return l10n
                            .displaySettingsPageChatMessageBackgroundDefault;
                    }
                  }

                  return Text(
                    labelOf(),
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showChatMessageBackgroundSheet(context),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Type,
                label: l10n.displaySettingsPageAppFontTitle,
                detailBuilder: (ctx) {
                  final sp = ctx.watch<SettingsProvider>();
                  final fam = sp.appFontFamily;
                  final useLocal = (sp.appFontLocalAlias ?? '').isNotEmpty;
                  final text = useLocal
                      ? l10n.displaySettingsPageFontLocalFileLabel
                      : (fam == null || fam.isEmpty)
                      ? l10n.desktopFontFamilySystemDefault
                      : fam;
                  return Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showMobileFontSourceSheet(
                  context,
                  target: _FontTarget.app,
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Code,
                label: l10n.displaySettingsPageCodeFontTitle,
                detailBuilder: (ctx) {
                  final sp = ctx.watch<SettingsProvider>();
                  final fam = sp.codeFontFamily;
                  final useLocal = (sp.codeFontLocalAlias ?? '').isNotEmpty;
                  final text = useLocal
                      ? l10n.displaySettingsPageFontLocalFileLabel
                      : (fam == null || fam.isEmpty)
                      ? l10n.desktopFontFamilyMonospaceDefault
                      : fam;
                  return Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showMobileFontSourceSheet(
                  context,
                  target: _FontTarget.code,
                ),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.CaseSensitive,
                label: l10n.displaySettingsPageChatFontSizeTitle,
                detailBuilder: (ctx) {
                  final scale = ctx.watch<SettingsProvider>().chatFontScale;
                  return Text(
                    '${(scale * 100).round()}%',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showChatFontSizeSheet(context),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.ArrowDown,
                label: l10n.displaySettingsPageAutoScrollIdleTitle,
                detailBuilder: (ctx) {
                  final sp = ctx.watch<SettingsProvider>();
                  if (!sp.autoScrollEnabled) {
                    return Text(
                      l10n.displaySettingsPageAutoScrollDisabledLabel,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    );
                  }
                  final seconds = sp.autoScrollIdleSeconds;
                  return Text(
                    '${seconds.round()}s',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showAutoScrollIdleSheet(context),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Image,
                label: l10n.displaySettingsPageChatBackgroundMaskTitle,
                detailBuilder: (ctx) {
                  final v = ctx
                      .watch<SettingsProvider>()
                      .chatBackgroundMaskStrength;
                  return Text(
                    '${(v * 100).round()}%',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showChatBackgroundMaskSheet(context),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.RectangleHorizontal,
                label: l10n.displaySettingsPageChatInputBackgroundOpacityTitle,
                detailBuilder: (ctx) {
                  final brightness = Theme.of(ctx).brightness;
                  final settings = ctx.watch<SettingsProvider>();
                  final opacity = settings.chatInputBackgroundOpacityFor(
                    brightness,
                  );
                  return Text(
                    '${(opacity * 100).round()}%',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  );
                },
                onTap: () => _showChatInputBackgroundOpacitySheet(context),
              ),
            ],
          ),
          // Inline cards replaced by sheet-triggering rows above.
        ],
      ),
    );
  }

  Future<void> _showMobileFontSourceSheet(
    BuildContext context, {
    required _FontTarget target,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final family = target == _FontTarget.app
        ? settings.appFontFamily
        : settings.codeFontFamily;
    final localAlias = target == _FontTarget.app
        ? settings.appFontLocalAlias
        : settings.codeFontLocalAlias;
    final isGoogle = target == _FontTarget.app
        ? settings.appFontIsGoogle
        : settings.codeFontIsGoogle;
    final selectedSource = (localAlias?.isNotEmpty ?? false)
        ? 'local'
        : isGoogle
        ? 'google'
        : family == null || family.isEmpty
        ? 'reset'
        : null;
    final choice = await showAppPopupSheet<String>(
      context: context,
      title: target == _FontTarget.app
          ? l10n.displaySettingsPageAppFontTitle
          : l10n.displaySettingsPageCodeFontTitle,
      extendBodyBehindHeader: true,
      builder: (ctx) => _displayChoicePopupContent(
        ctx,
        selected: selectedSource,
        options: [
          ('local', l10n.fontPickerChooseLocalFile),
          ('google', l10n.fontPickerGetFromGoogleFonts),
          ('reset', l10n.displaySettingsPageFontResetLabel),
        ],
      ),
    );
    if (choice == null) return;
    if (!context.mounted) return;

    if (choice == 'local') {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf'],
      );
      final path = res?.files.singleOrNull?.path;
      if (path == null) return;
      if (!context.mounted) return;
      if (target == _FontTarget.app) {
        await settings.setAppFontFromLocal(path: path);
      } else {
        await settings.setCodeFontFromLocal(path: path);
      }
      return;
    }
    if (choice == 'google') {
      final title = target == _FontTarget.app
          ? l10n.displaySettingsPageAppFontTitle
          : l10n.displaySettingsPageCodeFontTitle;
      final selected = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => GoogleFontsPickerPage(title: title)),
      );
      if (selected == null || selected.isEmpty) return;
      if (!context.mounted) return;
      if (target == _FontTarget.app) {
        await settings.setAppFontFromGoogle(selected);
      } else {
        await settings.setCodeFontFromGoogle(selected);
      }
      return;
    }
    if (choice == 'reset') {
      if (target == _FontTarget.app) {
        await settings.clearAppFont();
      } else {
        await settings.clearCodeFont();
      }
    }
  }

  Future<void> _showChatMessageBackgroundSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final currentStyle = context
        .read<SettingsProvider>()
        .chatMessageBackgroundStyle;
    final selectedStyle = switch (currentStyle) {
      ChatMessageBackgroundStyle.defaultStyle => 'default',
      ChatMessageBackgroundStyle.frosted => 'frosted',
      ChatMessageBackgroundStyle.solid => 'solid',
    };
    final choice = await showAppPopupSheet<String>(
      context: context,
      title: l10n.displaySettingsPageChatMessageBackgroundTitle,
      extendBodyBehindHeader: true,
      builder: (ctx) => _displayChoicePopupContent(
        ctx,
        selected: selectedStyle,
        options: [
          ('default', l10n.displaySettingsPageChatMessageBackgroundDefault),
          ('frosted', l10n.displaySettingsPageChatMessageBackgroundFrosted),
          ('solid', l10n.displaySettingsPageChatMessageBackgroundSolid),
        ],
      ),
    );
    if (choice == null) return;
    if (!context.mounted) return;

    final sp = context.read<SettingsProvider>();
    switch (choice) {
      case 'frosted':
        await sp.setChatMessageBackgroundStyle(
          ChatMessageBackgroundStyle.frosted,
        );
        break;
      case 'solid':
        await sp.setChatMessageBackgroundStyle(
          ChatMessageBackgroundStyle.solid,
        );
        break;
      default:
        await sp.setChatMessageBackgroundStyle(
          ChatMessageBackgroundStyle.defaultStyle,
        );
    }
  }

  Future<void> _showAndroidBackgroundChatSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final choice = await showAppPopupSheet<String>(
      context: context,
      title: l10n.displaySettingsPageAndroidBackgroundChatTitle,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetOption(
                ctx,
                label: l10n.androidBackgroundOptionOn,
                onTap: () => Navigator.of(ctx).pop('on'),
              ),
              _sheetDividerNoIcon(ctx),
              _sheetOption(
                ctx,
                label: l10n.androidBackgroundOptionOnNotify,
                onTap: () => Navigator.of(ctx).pop('on_notify'),
              ),
              _sheetDividerNoIcon(ctx),
              _sheetOption(
                ctx,
                label: l10n.androidBackgroundOptionOff,
                onTap: () => Navigator.of(ctx).pop('off'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    if (!context.mounted) return;

    final sp = context.read<SettingsProvider>();
    final notificationTitle = l10n.androidBackgroundNotificationTitle;
    final notificationText = l10n.androidBackgroundNotificationText;
    switch (choice) {
      case 'on_notify':
        await sp.setAndroidBackgroundChatMode(
          AndroidBackgroundChatMode.onNotify,
        );
        try {
          await AndroidBackgroundManager.ensureInitialized(
            notificationTitle: notificationTitle,
            notificationText: notificationText,
          );
          await AndroidBackgroundManager.setEnabled(true);
          await NotificationService.ensureInitialized();
          await NotificationService.ensureAndroidNotificationsPermission();
        } catch (_) {}
        break;
      case 'on':
        await sp.setAndroidBackgroundChatMode(AndroidBackgroundChatMode.on);
        try {
          await AndroidBackgroundManager.ensureInitialized(
            notificationTitle: notificationTitle,
            notificationText: notificationText,
          );
          await AndroidBackgroundManager.setEnabled(true);
          // Prepare notification channel as well to avoid FGS notification issues on some ROMs
          await NotificationService.ensureInitialized();
        } catch (_) {}
        break;
      default:
        await sp.setAndroidBackgroundChatMode(AndroidBackgroundChatMode.off);
        try {
          await AndroidBackgroundManager.setEnabled(false);
        } catch (_) {}
    }
  }

  Future<void> _showChatFontSizeSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showAppPopupSheet(
      context: context,
      title: l10n.displaySettingsPageChatFontSizeTitle,
      showCloseButton: false,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.homePageDone,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final isDark = theme.brightness == Brightness.dark;
                final scale = context.watch<SettingsProvider>().chatFontScale;
                return _displaySettingsSliderGroup(
                  context,
                  icon: Lucide.CaseSensitive,
                  title: l10n.displaySettingsPageChatFontSizeTitle,
                  control: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '50%',
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SfSliderTheme(
                              data: SfSliderThemeData(
                                activeTrackHeight: 8,
                                inactiveTrackHeight: 8,
                                overlayRadius: 14,
                                activeTrackColor: cs.primary,
                                inactiveTrackColor: cs.onSurface.withValues(
                                  alpha: isDark ? 0.25 : 0.20,
                                ),
                                tooltipBackgroundColor: cs.primary,
                                tooltipTextStyle: TextStyle(
                                  color: cs.onPrimary,
                                  fontWeight: AppFontWeights.semibold,
                                ),
                                activeTickColor: cs.onSurface.withValues(
                                  alpha: isDark ? 0.45 : 0.35,
                                ),
                                inactiveTickColor: cs.onSurface.withValues(
                                  alpha: isDark ? 0.30 : 0.25,
                                ),
                                activeMinorTickColor: cs.onSurface.withValues(
                                  alpha: isDark ? 0.34 : 0.28,
                                ),
                                inactiveMinorTickColor: cs.onSurface.withValues(
                                  alpha: isDark ? 0.24 : 0.20,
                                ),
                              ),
                              child: SfSlider(
                                value: scale,
                                min: 0.5,
                                max: 1.50001,
                                stepSize: 0.05,
                                showTicks: true,
                                showLabels: true,
                                interval: 0.1,
                                minorTicksPerInterval: 1,
                                enableTooltip: true,
                                shouldAlwaysShowTooltip: false,
                                tooltipShape: const SfPaddleTooltipShape(),
                                labelFormatterCallback: (value, text) =>
                                    (value as double).toStringAsFixed(1),
                                thumbIcon: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: isDark
                                        ? []
                                        : [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.08,
                                              ),
                                              blurRadius: 8,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                  ),
                                ),
                                onChanged: (v) => context
                                    .read<SettingsProvider>()
                                    .setChatFontScale(
                                      (v as double).clamp(0.5, 1.5),
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(scale * 100).round()}%',
                            style: TextStyle(color: cs.onSurface, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white12
                              : const Color(0xFFF2F3F5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          l10n.displaySettingsPageChatFontSampleText,
                          style: TextStyle(
                            fontSize:
                                16 *
                                context.watch<SettingsProvider>().chatFontScale,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAutoScrollIdleSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showAppPopupSheet(
      context: context,
      title: l10n.displaySettingsPageAutoScrollIdleTitle,
      showCloseButton: false,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.homePageDone,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final isDark = theme.brightness == Brightness.dark;
                final sp = context.watch<SettingsProvider>();
                final seconds = sp.autoScrollIdleSeconds;
                final enabled = sp.autoScrollEnabled;
                return _displaySettingsSliderGroup(
                  context,
                  icon: Lucide.ArrowDown,
                  title: l10n.displaySettingsPageAutoScrollEnableTitle,
                  subtitle: l10n.displaySettingsPageAutoScrollIdleSubtitle,
                  onTap: () => context
                      .read<SettingsProvider>()
                      .setAutoScrollEnabled(!enabled),
                  trailing: AppSwitch(
                    value: enabled,
                    onChanged: (v) => context
                        .read<SettingsProvider>()
                        .setAutoScrollEnabled(v),
                  ),
                  control: Row(
                    children: [
                      Text(
                        '2s',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SfSliderTheme(
                          data: SfSliderThemeData(
                            activeTrackHeight: 8,
                            inactiveTrackHeight: 8,
                            overlayRadius: 14,
                            activeTrackColor: cs.primary,
                            inactiveTrackColor: cs.onSurface.withValues(
                              alpha: isDark ? 0.25 : 0.20,
                            ),
                            tooltipBackgroundColor: cs.primary,
                            tooltipTextStyle: TextStyle(
                              color: cs.onPrimary,
                              fontWeight: AppFontWeights.semibold,
                            ),
                            activeTickColor: cs.onSurface.withValues(
                              alpha: isDark ? 0.45 : 0.35,
                            ),
                            inactiveTickColor: cs.onSurface.withValues(
                              alpha: isDark ? 0.30 : 0.25,
                            ),
                            activeMinorTickColor: cs.onSurface.withValues(
                              alpha: isDark ? 0.34 : 0.28,
                            ),
                            inactiveMinorTickColor: cs.onSurface.withValues(
                              alpha: isDark ? 0.24 : 0.20,
                            ),
                          ),
                          child: SfSlider(
                            value: seconds.toDouble(),
                            min: 2.0,
                            max: 64.0,
                            stepSize: 2.0,
                            showTicks: true,
                            showLabels: true,
                            interval: 10.0,
                            minorTicksPerInterval: 1,
                            enableTooltip: true,
                            shouldAlwaysShowTooltip: false,
                            tooltipShape: const SfPaddleTooltipShape(),
                            labelFormatterCallback: (value, text) =>
                                value.toInt().toString(),
                            thumbIcon: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                                boxShadow: isDark
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.08,
                                          ),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                              ),
                            ),
                            onChanged: enabled
                                ? (v) => context
                                      .read<SettingsProvider>()
                                      .setAutoScrollIdleSeconds(
                                        (v as double).round(),
                                      )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        enabled
                            ? '${seconds.round()}s'
                            : l10n.displaySettingsPageAutoScrollDisabledLabel,
                        style: TextStyle(
                          color: cs.onSurface.withValues(
                            alpha: enabled ? 1.0 : 0.5,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showChatBackgroundMaskSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await showAppPopupSheet(
      context: context,
      title: l10n.displaySettingsPageChatBackgroundMaskTitle,
      showCloseButton: false,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.homePageDone,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final isDark = theme.brightness == Brightness.dark;
                final strength = context
                    .watch<SettingsProvider>()
                    .chatBackgroundMaskStrength;
                return _displaySettingsSliderGroup(
                  context,
                  icon: Lucide.Image,
                  title: l10n.displaySettingsPageChatBackgroundMaskTitle,
                  control: Row(
                    children: [
                      Text(
                        '0%',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SfSliderTheme(
                          data: SfSliderThemeData(
                            activeTrackHeight: 8,
                            inactiveTrackHeight: 8,
                            overlayRadius: 14,
                            activeTrackColor: cs.primary,
                            inactiveTrackColor: cs.onSurface.withValues(
                              alpha: isDark ? 0.25 : 0.20,
                            ),
                            tooltipBackgroundColor: cs.primary,
                            tooltipTextStyle: TextStyle(
                              color: cs.onPrimary,
                              fontWeight: AppFontWeights.semibold,
                            ),
                            activeTickColor: cs.onSurface.withValues(
                              alpha: isDark ? 0.45 : 0.35,
                            ),
                            inactiveTickColor: cs.onSurface.withValues(
                              alpha: isDark ? 0.30 : 0.25,
                            ),
                            activeMinorTickColor: cs.onSurface.withValues(
                              alpha: isDark ? 0.34 : 0.28,
                            ),
                            inactiveMinorTickColor: cs.onSurface.withValues(
                              alpha: isDark ? 0.24 : 0.20,
                            ),
                          ),
                          child: SfSlider(
                            value: (strength * 100).roundToDouble(),
                            min: 0.0,
                            max: 200.0001,
                            stepSize: 5.0,
                            showTicks: true,
                            showLabels: true,
                            interval: 50,
                            minorTicksPerInterval: 1,
                            enableTooltip: true,
                            shouldAlwaysShowTooltip: false,
                            tooltipShape: const SfPaddleTooltipShape(),
                            labelFormatterCallback: (value, text) =>
                                '${(value as double).round()}%',
                            thumbIcon: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                                boxShadow: isDark
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.08,
                                          ),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                              ),
                            ),
                            onChanged: (v) => context
                                .read<SettingsProvider>()
                                .setChatBackgroundMaskStrength(
                                  ((v as double) / 100.0).clamp(0.0, 2.0),
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(strength * 100).round()}%',
                        style: TextStyle(color: cs.onSurface, fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showChatInputBackgroundOpacitySheet(
    BuildContext context,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await showAppPopupSheet(
      context: context,
      title: l10n.displaySettingsPageChatInputBackgroundOpacityTitle,
      showCloseButton: false,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.homePageDone,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final isDark = theme.brightness == Brightness.dark;
                final l10n = AppLocalizations.of(context)!;
                final settings = context.watch<SettingsProvider>();
                return _displaySettingsSliderGroup(
                  context,
                  icon: Lucide.RectangleHorizontal,
                  title:
                      l10n.displaySettingsPageChatInputBackgroundOpacityTitle,
                  control: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _chatInputOpacitySlider(
                        context,
                        label: l10n.settingsPageLightMode,
                        brightness: Brightness.light,
                        opacity: settings.chatInputBackgroundOpacityLight,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 18),
                      _chatInputOpacitySlider(
                        context,
                        label: l10n.settingsPageDarkMode,
                        brightness: Brightness.dark,
                        opacity: settings.chatInputBackgroundOpacityDark,
                        isDark: isDark,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _chatInputOpacitySlider(
    BuildContext context, {
    required String label,
    required Brightness brightness,
    required double opacity,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 13,
            fontWeight: AppFontWeights.semibold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '0%',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SfSliderTheme(
                data: SfSliderThemeData(
                  activeTrackHeight: 8,
                  inactiveTrackHeight: 8,
                  overlayRadius: 14,
                  activeTrackColor: cs.primary,
                  inactiveTrackColor: cs.onSurface.withValues(
                    alpha: isDark ? 0.25 : 0.20,
                  ),
                  tooltipBackgroundColor: cs.primary,
                  tooltipTextStyle: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: AppFontWeights.semibold,
                  ),
                  activeTickColor: cs.onSurface.withValues(
                    alpha: isDark ? 0.45 : 0.35,
                  ),
                  inactiveTickColor: cs.onSurface.withValues(
                    alpha: isDark ? 0.30 : 0.25,
                  ),
                  activeMinorTickColor: cs.onSurface.withValues(
                    alpha: isDark ? 0.34 : 0.28,
                  ),
                  inactiveMinorTickColor: cs.onSurface.withValues(
                    alpha: isDark ? 0.24 : 0.20,
                  ),
                ),
                child: SfSlider(
                  value: (opacity * 100).roundToDouble(),
                  min: 0.0,
                  max: 100.0001,
                  stepSize: 5.0,
                  showTicks: true,
                  showLabels: true,
                  interval: 25,
                  minorTicksPerInterval: 1,
                  enableTooltip: true,
                  shouldAlwaysShowTooltip: false,
                  tooltipShape: const SfPaddleTooltipShape(),
                  labelFormatterCallback: (value, text) =>
                      '${(value as double).round()}%',
                  thumbIcon: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      boxShadow: isDark
                          ? []
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                    ),
                  ),
                  onChanged: (v) => context
                      .read<SettingsProvider>()
                      .setChatInputBackgroundOpacity(
                        brightness,
                        ((v as double) / 100.0).clamp(0.0, 1.0),
                      ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(opacity * 100).round()}%',
              style: TextStyle(color: cs.onSurface, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

// --- iOS-style helpers ---

Widget _iosSectionCard({required List<Widget> children}) {
  return AppListGroup.list(children: children);
}

Widget _iosDivider(BuildContext context) {
  return AppListDivider(indent: 54, endIndent: 12, height: 1, thickness: 1);
}

Widget _noticeCard(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: cs.primaryContainer.withValues(alpha: isDark ? 0.20 : 0.35),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: cs.primary.withValues(alpha: 0.10), width: 0.6),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Lucide.BadgeInfo, size: 18, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 13,
                  fontWeight: AppFontWeights.semibold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.72),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _plainFootnote(BuildContext context, String text) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text(
      text,
      style: TextStyle(
        color: cs.onSurface.withValues(alpha: 0.58),
        fontSize: 12,
        height: 1.35,
      ),
    ),
  );
}

class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final pressColor = base.withValues(alpha: 0.7);
    final icon = Icon(
      widget.icon,
      size: 22,
      color: _pressed ? pressColor : base,
    );
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          widget.onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: icon,
        ),
      ),
    );
  }
}

Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  String? detailText,
  Widget Function(BuildContext ctx)? detailBuilder,
}) {
  return AppSettingsNavTile(
    icon: icon,
    label: label,
    onTap: onTap,
    detailText: detailText,
    detailBuilder: detailBuilder,
  );
}

Widget _iosSwitchRow(
  BuildContext context, {
  IconData? icon,
  required String label,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  final cs = Theme.of(context).colorScheme;
  return AppListTile(
    onTap: () => onChanged(!value),
    leading: icon == null
        ? null
        : Icon(
            icon,
            size: 24,
            color: AppColors.secondaryLabel(Theme.of(context).brightness),
          ),
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
    subtitle: subtitle == null || subtitle.isEmpty
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

Widget _sheetOption(
  BuildContext context, {
  IconData? icon,
  required String label,
  required VoidCallback onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  return AppListTile(
    onTapFeedback: () {
      if (context.read<SettingsProvider>().hapticsOnListItemTap) {
        Haptics.soft();
      }
    },
    onTap: onTap,
    leading: icon == null ? null : Icon(icon, size: 20, color: cs.onSurface),
    title: Text(label, style: TextStyle(fontSize: 15, color: cs.onSurface)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    minLeadingWidth: 24,
    horizontalTitleGap: 12,
    minVerticalPadding: 14,
  );
}

Widget _sheetDividerNoIcon(BuildContext context) {
  return const AppListDivider(indent: 16, endIndent: 16, thickness: 0.6);
}

Widget _displayChoicePopupContent<T>(
  BuildContext context, {
  required List<(T, String)> options,
  T? selected,
}) {
  final isDialog = PopupContentSurfaceScope.isDialogOf(context);
  final primary = Theme.of(context).colorScheme.primary;
  return SingleChildScrollView(
    key: ValueKey(isDialog),
    primary: !isDialog,
    padding: PopupContentFrame.scrollPadding(
      context,
      const EdgeInsets.fromLTRB(16, 0, 16, 24),
    ),
    child: AppListGroup.list(
      children: [
        for (var index = 0; index < options.length; index++) ...[
          if (index > 0) const AppListDivider(),
          AppListTile(
            title: Text(options[index].$2),
            trailing: options[index].$1 == selected
                ? Icon(Icons.check_circle, color: primary, size: 22)
                : null,
            holdHighlightThroughNavigation: false,
            onTapFeedback: () {
              if (context.read<SettingsProvider>().hapticsOnListItemTap) {
                Haptics.soft();
              }
            },
            onTap: () => Navigator.of(context).pop(options[index].$1),
          ),
        ],
      ],
    ),
  );
}

Widget _displaySettingsSliderGroup(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? trailing,
  VoidCallback? onTap,
  required Widget control,
}) {
  final brightness = Theme.of(context).brightness;
  return AppListGroup.list(
    children: [
      AppListTile(
        onTapFeedback: onTap == null
            ? null
            : () {
                if (context.read<SettingsProvider>().hapticsOnListItemTap) {
                  Haptics.soft();
                }
              },
        onTap: onTap,
        leading: Icon(
          icon,
          size: 24,
          color: AppColors.secondaryLabel(brightness),
        ),
        title: Text(title, style: const TextStyle(fontSize: 16)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: const TextStyle(fontSize: 13)),
        trailing: trailing,
        minVerticalPadding: 10,
      ),
      const AppListDivider.forTile(hasLeading: true),
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(56, 8, 16, 14),
        child: control,
      ),
    ],
  );
}

Future<void> _showMobileMessageNavModeSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final currentMode = context
      .read<SettingsProvider>()
      .mobileMessageNavButtonsMode;
  final choice = await showAppPopupSheet<MobileMessageNavButtonsMode>(
    context: context,
    title: l10n.displaySettingsPageMessageNavButtonsTitle,
    extendBodyBehindHeader: true,
    builder: (ctx) => _displayChoicePopupContent(
      ctx,
      selected: currentMode,
      options: [
        (
          MobileMessageNavButtonsMode.always,
          l10n.displaySettingsPageMessageNavButtonsModeAlways,
        ),
        (
          MobileMessageNavButtonsMode.scroll,
          l10n.displaySettingsPageMessageNavButtonsModeScroll,
        ),
        (
          MobileMessageNavButtonsMode.never,
          l10n.displaySettingsPageMessageNavButtonsModeNever,
        ),
      ],
    ),
  );
  if (choice == null) return;
  if (!context.mounted) return;
  await context.read<SettingsProvider>().setMobileMessageNavButtonsMode(choice);
}

// --- Subpages ---

class ChatItemDisplaySettingsPage extends StatelessWidget {
  const ChatItemDisplaySettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
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
      title: AppScaffoldTitle(l10n.displaySettingsPageChatItemDisplayTitle),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          AppScaffold.scrollContentTop(context),
          16,
          AppScaffold.scrollContentBottom(context),
        ),
        children: [
          _iosSectionCard(
            children: [
              _iosSwitchRow(
                context,
                icon: Lucide.User,
                label: l10n.displaySettingsPageShowUserAvatarTitle,
                value: sp.showUserAvatar,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowUserAvatar(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.MessageCircle,
                label: l10n.displaySettingsPageShowUserNameTitle,
                value: sp.showUserName,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowUserName(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.clock,
                label: l10n.displaySettingsPageShowUserTimestampTitle,
                value: sp.showUserTimestamp,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowUserTimestamp(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Ellipsis,
                label: l10n.displaySettingsPageShowUserMessageActionsTitle,
                value: sp.showUserMessageActions,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setShowUserMessageActions(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Bot,
                label: l10n.displaySettingsPageChatModelIconTitle,
                value: sp.showModelIcon,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowModelIcon(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Bot,
                label: l10n.displaySettingsPageUseNewAssistantAvatarUxTitle,
                value: sp.useNewAssistantAvatarUx,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setUseNewAssistantAvatarUx(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.MessageSquare,
                label: l10n.displaySettingsPageShowModelNameTitle,
                value: sp.showModelName,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowModelName(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.clock,
                label: l10n.displaySettingsPageShowModelTimestampTitle,
                value: sp.showModelTimestamp,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowModelTimestamp(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Globe,
                label: l10n.displaySettingsPageShowProviderInChatMessageTitle,
                value: sp.showProviderInChatMessage,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setShowProviderInChatMessage(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Type,
                label: l10n.displaySettingsPageShowTokenStatsTitle,
                value: sp.showTokenStats,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowTokenStats(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RenderingSettingsPage extends StatelessWidget {
  const RenderingSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
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
      title: AppScaffoldTitle(l10n.displaySettingsPageRenderingSettingsTitle),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          AppScaffold.scrollContentTop(context),
          16,
          AppScaffold.scrollContentBottom(context),
        ),
        children: [
          _iosSectionCard(
            children: [
              _iosSwitchRow(
                context,
                icon: Lucide.Hash,
                label: l10n.displaySettingsPageEnableDollarLatexTitle,
                value: sp.enableDollarLatex,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setEnableDollarLatex(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Code,
                label: l10n.displaySettingsPageEnableMathTitle,
                value: sp.enableMathRendering,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setEnableMathRendering(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.TextSelect,
                label: l10n.displaySettingsPageEnableUserMarkdownTitle,
                value: sp.enableUserMarkdown,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setEnableUserMarkdown(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Brain,
                label: l10n.displaySettingsPageEnableReasoningMarkdownTitle,
                value: sp.enableReasoningMarkdown,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setEnableReasoningMarkdown(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.MessageSquare,
                label: l10n.displaySettingsPageEnableAssistantMarkdownTitle,
                value: sp.enableAssistantMarkdown,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setEnableAssistantMarkdown(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.FoldVertical,
                label: l10n.displaySettingsPageAutoCollapseCodeBlockTitle,
                value: sp.autoCollapseCodeBlock,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setAutoCollapseCodeBlock(v),
              ),
              if (sp.autoCollapseCodeBlock) ...[
                _iosDivider(context),
                const _AutoCollapseCodeBlockLinesRow(),
              ],
              if (Platform.isAndroid || Platform.isIOS) ...[
                _iosDivider(context),
                _iosSwitchRow(
                  context,
                  icon: Lucide.WrapText,
                  label: l10n.displaySettingsPageMobileCodeBlockWrapTitle,
                  value: sp.mobileCodeBlockWrap,
                  onChanged: (v) => context
                      .read<SettingsProvider>()
                      .setMobileCodeBlockWrap(v),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AutoCollapseCodeBlockLinesRow extends StatefulWidget {
  const _AutoCollapseCodeBlockLinesRow();
  @override
  State<_AutoCollapseCodeBlockLinesRow> createState() =>
      _AutoCollapseCodeBlockLinesRowState();
}

class _AutoCollapseCodeBlockLinesRowState
    extends State<_AutoCollapseCodeBlockLinesRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final sp = context.read<SettingsProvider>();
    _controller = TextEditingController(
      text: '${sp.autoCollapseCodeBlockLines}',
    );
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus) _commit();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    final sp = context.read<SettingsProvider>();
    final raw = _controller.text.trim();
    final parsed = int.tryParse(raw) ?? sp.autoCollapseCodeBlockLines;
    final next = parsed.clamp(1, 999);
    sp.setAutoCollapseCodeBlockLines(next);
    final text = '$next';
    if (_controller.text != text) {
      _controller.value = _controller.value.copyWith(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sp = context.watch<SettingsProvider>();

    // Keep controller in sync when not editing
    if (!_focusNode.hasFocus) {
      final t = '${sp.autoCollapseCodeBlockLines}';
      if (_controller.text != t) _controller.text = t;
    }

    final baseColor = cs.onSurface.withValues(alpha: 0.9);
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.28),
        width: 0.8,
      ),
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.primary, width: 1.0),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Icon(Lucide.ListOrdered, size: 20, color: baseColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.displaySettingsPageAutoCollapseCodeBlockLinesTitle,
              style: TextStyle(fontSize: 15, color: baseColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, maxWidth: 80),
              child: AppTextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? Colors.white10 : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  border: baseBorder,
                  enabledBorder: baseBorder,
                  focusedBorder: focusBorder,
                ),
                onSubmitted: (_) => _commit(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.displaySettingsPageAutoCollapseCodeBlockLinesUnit,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class BehaviorStartupSettingsPage extends StatelessWidget {
  const BehaviorStartupSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
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
      title: AppScaffoldTitle(l10n.displaySettingsPageBehaviorStartupTitle),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          AppScaffold.scrollContentTop(context),
          16,
          AppScaffold.scrollContentBottom(context),
        ),
        children: [
          _iosSectionCard(
            children: [
              _iosSwitchRow(
                context,
                icon: Lucide.Brain,
                label: l10n.displaySettingsPageAutoCollapseThinkingTitle,
                value: sp.autoCollapseThinking,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setAutoCollapseThinking(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.ListTree,
                label: l10n.displaySettingsPageCollapseThinkingStepsTitle,
                value: sp.collapseThinkingSteps,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setCollapseThinkingSteps(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.FileText,
                label: l10n.displaySettingsPageShowToolResultSummaryTitle,
                value: sp.showToolResultSummary,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setShowToolResultSummary(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.TextSelect,
                label: l10n.displaySettingsPageInsertSuggestionOnlyTitle,
                value: sp.insertSuggestionOnTapOnly,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setInsertSuggestionOnTapOnly(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.RefreshCw,
                label: l10n
                    .displaySettingsPageRegenerateDeleteTrailingMessagesTitle,
                value: sp.regenerateDeleteTrailingMessages,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setRegenerateDeleteTrailingMessages(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.MessageCircleWarning,
                label: l10n.displaySettingsPageShowRegenerateConfirmDialogTitle,
                value: sp.showRegenerateConfirmDialog,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setShowRegenerateConfirmDialog(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.BadgeInfo,
                label: l10n.displaySettingsPageShowUpdatesTitle,
                value: sp.showAppUpdates,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowAppUpdates(v),
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.ChevronRight,
                label: l10n.displaySettingsPageMessageNavButtonsTitle,
                detailBuilder: (_) =>
                    Text(switch (sp.mobileMessageNavButtonsMode) {
                      MobileMessageNavButtonsMode.always =>
                        l10n.displaySettingsPageMessageNavButtonsModeAlways,
                      MobileMessageNavButtonsMode.scroll =>
                        l10n.displaySettingsPageMessageNavButtonsModeScroll,
                      MobileMessageNavButtonsMode.never =>
                        l10n.displaySettingsPageMessageNavButtonsModeNever,
                    }),
                onTap: () => _showMobileMessageNavModeSheet(context),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Calendar,
                label: l10n.displaySettingsPageShowChatListDateTitle,
                value: sp.showChatListDate,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setShowChatListDate(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Crop,
                label: l10n.displaySettingsPageEnableImageCropperTitle,
                subtitle: l10n.displaySettingsPageEnableImageCropperSubtitle,
                value: sp.imageCropperEnabled,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setImageCropperEnabled(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.panelLeft,
                label:
                    l10n.displaySettingsPageKeepSidebarOpenOnAssistantTapTitle,
                value: sp.keepSidebarOpenOnAssistantTap,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setKeepSidebarOpenOnAssistantTap(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.ListTree,
                label: l10n.displaySettingsPageKeepSidebarOpenOnTopicTapTitle,
                value: sp.keepSidebarOpenOnTopicTap,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setKeepSidebarOpenOnTopicTap(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.UnfoldVertical,
                label: l10n
                    .displaySettingsPageKeepAssistantListExpandedOnSidebarCloseTitle,
                value: sp.keepAssistantListExpandedOnSidebarClose,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setKeepAssistantListExpandedOnSidebarClose(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Shuffle,
                label: l10n.displaySettingsPageNewChatOnAssistantSwitchTitle,
                value: sp.newChatOnAssistantSwitch,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setNewChatOnAssistantSwitch(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Trash2,
                label: l10n.displaySettingsPageNewChatAfterDeleteTitle,
                value: sp.newChatAfterDelete,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setNewChatAfterDelete(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.MessageCirclePlus,
                label: l10n.displaySettingsPageNewChatOnLaunchTitle,
                value: sp.newChatOnLaunch,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setNewChatOnLaunch(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.CornerDownLeft,
                label: l10n.displaySettingsPageEnterToSendTitle,
                value: sp.enterToSendOnMobile,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setEnterToSendOnMobile(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class IosBackgroundSettingsPage extends StatefulWidget {
  const IosBackgroundSettingsPage({super.key});

  @override
  State<IosBackgroundSettingsPage> createState() =>
      _IosBackgroundSettingsPageState();
}

class _IosBackgroundSettingsPageState extends State<IosBackgroundSettingsPage> {
  late Future<IosBackgroundGenerationStatus> _statusFuture;

  @override
  void initState() {
    super.initState();
    _statusFuture = IosBackgroundGenerationService.instance.getStatus();
  }

  void _refreshStatus() {
    setState(() {
      _statusFuture = IosBackgroundGenerationService.instance.getStatus();
    });
  }

  Future<void> _setBackgroundNotificationsEnabled(bool enabled) async {
    final settings = context.read<SettingsProvider>();
    if (!enabled) {
      await settings.setIosBackgroundNotificationsEnabled(false);
      _refreshStatus();
      return;
    }

    final granted = await IosBackgroundGenerationService.instance
        .requestNotificationAuthorization();
    if (!mounted) return;
    await settings.setIosBackgroundNotificationsEnabled(granted);
    _refreshStatus();
  }

  Future<void> _openAppSettings() async {
    await IosBackgroundGenerationService.instance.openAppSettings();
    if (!mounted) return;
    _refreshStatus();
  }

  Future<void> _openNotificationSettings() async {
    await IosBackgroundGenerationService.instance.openNotificationSettings();
    if (!mounted) return;
    _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();

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
      title: AppScaffoldTitle(l10n.iosBackgroundSettingsPageTitle),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          AppScaffold.scrollContentTop(context),
          16,
          AppScaffold.scrollContentBottom(context),
        ),
        children: [
          _noticeCard(
            context,
            title: l10n.iosBackgroundLimitNoticeTitle,
            body: l10n.iosBackgroundLimitNoticeBody,
          ),
          const SizedBox(height: 12),
          _iosSectionCard(
            children: [
              _iosSwitchRow(
                context,
                icon: Lucide.Activity,
                label: l10n.iosBackgroundGenerationEnableTitle,
                subtitle: l10n.iosBackgroundGenerationEnableSubtitle,
                value: sp.iosBackgroundGenerationEnabled,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setIosBackgroundGenerationEnabled(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.RefreshCw,
                label: l10n.iosBackgroundTaskRefreshTitle,
                subtitle: l10n.iosBackgroundTaskRefreshSubtitle,
                value: sp.iosBackgroundTaskRefreshEnabled,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setIosBackgroundTaskRefreshEnabled(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Timer,
                label: l10n.iosLiveActivityTitle,
                subtitle: l10n.iosLiveActivitySubtitle,
                value: sp.iosLiveActivityEnabled,
                onChanged: (v) => context
                    .read<SettingsProvider>()
                    .setIosLiveActivityEnabled(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.MessageCircle,
                label: l10n.iosBackgroundNotificationsTitle,
                subtitle: l10n.iosBackgroundNotificationsSubtitle,
                value: sp.iosBackgroundNotificationsEnabled,
                onChanged: _setBackgroundNotificationsEnabled,
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<IosBackgroundGenerationStatus>(
            future: _statusFuture,
            builder: (context, snapshot) {
              final status = snapshot.data;
              return _iosSectionCard(
                children: [
                  _iosNavRow(
                    context,
                    icon: Lucide.BadgeInfo,
                    label: l10n.iosBackgroundNativeStatusTitle,
                    detailText: status == null
                        ? l10n.iosBackgroundNativeStatusUnavailable
                        : status.liveActivitiesEnabled
                        ? l10n.iosBackgroundLiveActivityAvailable
                        : l10n.iosBackgroundLiveActivityUnavailable,
                    onTap: _openAppSettings,
                  ),
                  _iosDivider(context),
                  _iosNavRow(
                    context,
                    icon: Lucide.MessageCircle,
                    label: status?.notificationsAuthorized == true
                        ? l10n.iosBackgroundNotificationsAuthorized
                        : l10n.iosBackgroundNotificationsNotAuthorized,
                    onTap: _openNotificationSettings,
                  ),
                ],
              );
            },
          ),
          if (sp.iosLiveActivityEnabled) ...[
            const SizedBox(height: 12),
            _plainFootnote(context, l10n.iosBackgroundUnsupportedLiveActivity),
          ],
        ],
      ),
    );
  }
}

class HapticsSettingsPage extends StatelessWidget {
  const HapticsSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sp = context.watch<SettingsProvider>();
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
      title: AppScaffoldTitle(l10n.displaySettingsPageHapticsSettingsTitle),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          AppScaffold.scrollContentTop(context),
          16,
          AppScaffold.scrollContentBottom(context),
        ),
        children: [
          _iosSectionCard(
            children: [
              _iosSwitchRow(
                context,
                icon: Lucide.Vibrate,
                label: l10n.displaySettingsPageHapticsGlobalTitle,
                value: sp.hapticsGlobalEnabled,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsGlobalEnabled(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.toggleRight,
                label: l10n.displaySettingsPageHapticsIosSwitchTitle,
                value: sp.hapticsIosSwitch,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsIosSwitch(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.panelRight,
                label: l10n.displaySettingsPageHapticsOnSidebarTitle,
                value: sp.hapticsOnDrawer,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsOnDrawer(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.ListOrdered,
                label: l10n.displaySettingsPageHapticsOnListItemTapTitle,
                value: sp.hapticsOnListItemTap,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsOnListItemTap(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Square,
                label: l10n.displaySettingsPageHapticsOnCardTapTitle,
                value: sp.hapticsOnCardTap,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsOnCardTap(v),
              ),
              _iosDivider(context),
              _iosSwitchRow(
                context,
                icon: Lucide.Vibrate,
                label: l10n.displaySettingsPageHapticsOnGenerateTitle,
                value: sp.hapticsOnGenerate,
                onChanged: (v) =>
                    context.read<SettingsProvider>().setHapticsOnGenerate(v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
