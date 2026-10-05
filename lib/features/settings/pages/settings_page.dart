import 'package:flutter/material.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../model/pages/default_model_page.dart';
import 'account_settings_page.dart';
import 'theme_settings_page.dart';
import '../widgets/app_language_select_sheet.dart';
import '../../assistant/pages/assistant_settings_page.dart';
import 'about_page.dart';
import 'log_viewer_page.dart';
import '../../quick_phrase/pages/quick_phrases_page.dart';
import 'storage_space_page.dart';
import 'laboratory_page.dart';
import '../../../core/services/storage/storage_usage_service.dart';
import '../../../theme/design_tokens.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/pages/webview_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.onSelectConversation});

  final ValueChanged<String>? onSelectConversation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final listTopPadding = AppScaffold.scrollContentTop(context);
    final pageBackground = AppColors.groupedBackgroundFor(context);
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    final locale = settings.appLocale;
    final languageLabel = settings.isFollowingSystemLocale
        ? l10n.settingsPageSystemMode
        : switch (locale.languageCode) {
            'zh' when (locale.scriptCode ?? '').toLowerCase() == 'hant' =>
              l10n.languageDisplayTraditionalChinese,
            'zh' => l10n.displaySettingsPageLanguageChineseLabel,
            _ => l10n.displaySettingsPageLanguageEnglishLabel,
          };

    // Section labels follow the grouped-list hierarchy used by settings pages.
    Widget header(String text, {bool first = false}) =>
        AppListGroupHeader(title: text, first: first);

    return AppScaffold(
      backgroundColor: pageBackground,
      extendBodyBehindAppBar: true,
      showTopScrollOverlay: true,
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(l10n.settingsPageTitle),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          listTopPadding,
          AppSpacing.md,
          AppScaffold.scrollContentBottom(context),
        ),
        children: [
          if (!settings.hasAnyActiveModel)
            Material(
              color: cs.errorContainer.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Lucide.MessageCircleWarning,
                      size: 18,
                      color: cs.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.settingsPageWarningMessage,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!settings.hasAnyActiveModel) const SizedBox(height: 12),

          header(l10n.authSettingsAccountSection, first: true),
          _settingsSectionCard(
            context,
            children: [
              _settingsNavRow(
                context,
                icon: Lucide.User,
                label: l10n.authSettingsProfileTitle,
                detailText:
                    auth.user?.nickname ??
                    auth.user?.username ??
                    auth.user?.email,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountSettingsPage(),
                  ),
                ),
              ),
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.ChartColumnBig,
                label: l10n.authSettingsViewUsage,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const WebViewPage(
                      url: 'https://ai-cpa-dash.ethan0ne.com',
                    ),
                  ),
                ),
              ),
            ],
          ),

          header(l10n.settingsPageModelsServicesSection),
          _settingsSectionCard(
            context,
            children: [
              _settingsNavRow(
                context,
                icon: Lucide.Bot,
                label: l10n.settingsPageAssistant,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AssistantSettingsPage(),
                    ),
                  );
                },
              ),
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.Heart,
                label: l10n.settingsPageDefaultModel,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DefaultModelPage()),
                  );
                },
              ),
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.Zap,
                label: l10n.settingsPageQuickPhrase,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const QuickPhrasesPage()),
                  );
                },
              ),
            ],
          ),

          header(l10n.settingsPageGeneralSection),
          _settingsSectionCard(
            context,
            children: [
              _settingsNavRow(
                context,
                icon: Lucide.Languages,
                label: l10n.displaySettingsPageLanguageTitle,
                detailText: languageLabel,
                onTap: () => showAppLanguageSelector(context),
              ),
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.SunMoon,
                label: l10n.settingsPageAppearanceAndTheme,
                detailText: switch (settings.themeMode) {
                  ThemeMode.system => l10n.settingsPageSystemMode,
                  ThemeMode.light => l10n.settingsPageLightMode,
                  ThemeMode.dark => l10n.settingsPageDarkMode,
                },
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ThemeSettingsPage()),
                ),
              ),
              _settingsDivider(context),
              _ChatStorageSummaryTile(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StorageSpacePage()),
                ),
              ),
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.BadgeInfo,
                label: l10n.settingsPageAbout,
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const AboutPage()));
                },
              ),
              if (settings.requestLogEnabled || settings.flutterLogEnabled) ...[
                _settingsDivider(context),
                _settingsNavRow(
                  context,
                  icon: Lucide.FileText,
                  label: l10n.settingsPageLogs,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LogViewerPage()),
                    );
                  },
                ),
              ],
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.Sparkles,
                label: l10n.settingsPageLaboratory,
                onTap: () async {
                  final selectedConversationId = await Navigator.of(context)
                      .push<String>(
                        MaterialPageRoute(
                          builder: (_) => const LaboratoryPage(),
                        ),
                      );
                  if (!context.mounted || selectedConversationId == null) {
                    return;
                  }
                  Navigator.of(context).pop();
                  onSelectConversation?.call(selectedConversationId);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Grouped settings list widgets ---

Widget _settingsSectionCard(
  BuildContext context, {
  required List<Widget> children,
}) {
  return AppListGroup.list(children: children);
}

Widget _settingsDivider(BuildContext context) {
  return AppListDivider(indent: 56, endIndent: 12, height: 1, thickness: 1);
}

class _ChatStorageSummaryTile extends StatefulWidget {
  const _ChatStorageSummaryTile({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ChatStorageSummaryTile> createState() =>
      _ChatStorageSummaryTileState();
}

class _ChatStorageSummaryTileState extends State<_ChatStorageSummaryTile> {
  late Future<StorageUsageReport> _future;

  @override
  void initState() {
    super.initState();
    _future = StorageUsageService.computeReport();
  }

  String _fmtBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return FutureBuilder<StorageUsageReport>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final detailText = snapshot.connectionState != ConnectionState.done
            ? l10n.settingsPageCalculating
            : l10n.settingsPageFilesCount(
                data?.totalFiles ?? 0,
                _fmtBytes(data?.totalBytes ?? 0),
              );
        return _settingsNavRow(
          context,
          icon: Lucide.HardDrive,
          label: l10n.settingsPageChatStorage,
          detailText: detailText,
          onTap: widget.onTap,
        );
      },
    );
  }
}

Widget _settingsNavRow(
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
