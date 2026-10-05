import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_popup_sheet.dart';
import '../../../shared/widgets/app_list_group.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/popup_content_frame.dart';
import '../../../theme/design_tokens.dart';

/// Matches Financial-Memory's native-name / translated-subtitle language picker.
Future<void> showAppLanguageSelector(BuildContext context) async {
  final settings = context.read<SettingsProvider>();
  final current = settings.isFollowingSystemLocale
      ? 'system'
      : settings.appLocale.languageCode == 'en'
      ? 'en_US'
      : settings.appLocale.scriptCode == 'Hant'
      ? 'zh_Hant'
      : 'zh_CN';
  final selected = await showPopupContentFrame<String>(
    context,
    maxWidth: 620,
    maxHeight: 700,
    fitContent: true,
    largeSheet: true,
    builder: (ctx, isDialog) =>
        _AppLanguagePicker(current: current, isDialog: isDialog),
  );
  if (selected == null || !context.mounted) return;
  switch (selected) {
    case 'system':
      await settings.setAppLocaleFollowSystem();
    case 'zh_CN':
      await settings.setAppLocale(const Locale('zh', 'CN'));
    case 'zh_Hant':
      await settings.setAppLocale(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
    case 'en_US':
      await settings.setAppLocale(const Locale('en', 'US'));
  }
}

class _AppLanguagePicker extends StatelessWidget {
  const _AppLanguagePicker({required this.current, required this.isDialog});

  final String current;
  final bool isDialog;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final primary = Theme.of(context).colorScheme.primary;
    // Primary names are autonyms; subtitles follow the current interface language.
    final languages = [
      ('zh_CN', '简体中文', l10n.displaySettingsPageLanguageSimplifiedSubtitle),
      ('zh_Hant', '繁體中文', l10n.displaySettingsPageLanguageTraditionalSubtitle),
      ('en_US', 'English', l10n.displaySettingsPageLanguageEnglishSubtitle),
    ];
    Widget option(String code, String title, {String? subtitle}) => AppListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: code == current
          ? Icon(Icons.check_circle, color: primary, size: 22)
          : null,
      holdHighlightThroughNavigation: false,
      onTap: () => Navigator.of(context).pop(code),
    );

    return PopupContentFrame(
      title: l10n.displaySettingsPageLanguageTitle,
      isDialog: isDialog,
      showCloseButton: false,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.homePageDone,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
      child: Builder(
        builder: (ctx) => SingleChildScrollView(
          key: ValueKey(isDialog),
          primary: !isDialog,
          padding: PopupContentFrame.scrollPadding(
            ctx,
            const EdgeInsets.fromLTRB(16, 0, 16, 24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppListGroup.list(
                children: [option('system', l10n.settingsPageSystemMode)],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppListGroup.list(
                children: [
                  for (var index = 0; index < languages.length; index++) ...[
                    if (index > 0) const AppListDivider(),
                    option(
                      languages[index].$1,
                      languages[index].$2,
                      subtitle: languages[index].$1 == current
                          ? l10n.displaySettingsPageLanguageCurrentSelection
                          : languages[index].$3,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
