import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../model/pages/default_model_page.dart';
import 'display_settings_page.dart';
import '../../mcp/pages/mcp_page.dart';
import '../../assistant/pages/assistant_settings_page.dart';
import 'about_page.dart';
import 'tts_services_page.dart';
import 'log_viewer_page.dart';
import '../../search/pages/search_services_page.dart';
import '../../backup/pages/backup_page.dart';
import '../../quick_phrase/pages/quick_phrases_page.dart';
import 'network_proxy_page.dart';
import 'storage_space_page.dart';
import '../../stats/pages/stats_page.dart';
import '../../../core/services/storage/storage_usage_service.dart';
import '../../../core/services/haptics.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import '../../../theme/design_tokens.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/app_switch.dart';
import '../../../shared/pages/webview_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final brightness = Theme.of(context).brightness;
    final safeTopInset = mediaQuery.padding.top > mediaQuery.viewPadding.top
        ? mediaQuery.padding.top
        : mediaQuery.viewPadding.top;
    final listTopPadding =
        safeTopInset +
        AppScaffold.defaultToolbarHeight +
        AppScaffold.defaultAppBarContentGap;
    final pageBackground = AppColors.groupedBackgroundFor(context);
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();

    String modeLabel(ThemeMode m) {
      switch (m) {
        case ThemeMode.dark:
          return l10n.settingsPageDarkMode;
        case ThemeMode.light:
          return l10n.settingsPageLightMode;
        case ThemeMode.system:
          return l10n.settingsPageSystemMode;
      }
    }

    Future<void> pickThemeMode() async {
      final settingsProvider = context.read<SettingsProvider>();
      final selected = await showModalBottomSheet<ThemeMode>(
        context: context,
        backgroundColor: AppColors.pickerModalBackground(brightness),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetOption(
                    ctx,
                    icon: Lucide.Monitor,
                    label: modeLabel(ThemeMode.system),
                    onTap: () => Navigator.of(ctx).pop(ThemeMode.system),
                  ),
                  _sheetDivider(ctx),
                  _sheetOption(
                    ctx,
                    icon: Lucide.Sun,
                    label: modeLabel(ThemeMode.light),
                    onTap: () => Navigator.of(ctx).pop(ThemeMode.light),
                  ),
                  _sheetDivider(ctx),
                  _sheetOption(
                    ctx,
                    icon: Lucide.Moon,
                    label: modeLabel(ThemeMode.dark),
                    onTap: () => Navigator.of(ctx).pop(ThemeMode.dark),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (selected != null) {
        await settingsProvider.setThemeMode(selected);
      }
    }

    Future<void> setAutoCleanupMedia(bool value) async {
      final ok = await context.read<AuthProvider>().setAutoCleanupMedia(value);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存附件清理设置失败')));
      }
    }

    // Section labels follow the grouped-list hierarchy used by settings pages.
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
          AppSpacing.md,
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
                label: auth.user?.email ?? '',
                onTap: null,
              ),
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.ChartColumnBig,
                label: l10n.authSettingsViewUsage,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WebViewPage(
                        url: 'https://ai-cpa-dash.ethan0ne.com',
                      ),
                    ),
                  );
                },
              ),
              _settingsDivider(context),
              _settingsSwitchRow(
                context,
                icon: Lucide.Trash2,
                title: '超出配额时自动清理附件',
                subtitle:
                    '已用 ${((auth.user?.mediaUsedBytes ?? 0) / 1024 / 1024 / 1024).toStringAsFixed(2)} / ${((auth.user?.mediaQuotaBytes ?? 0) / 1024 / 1024 / 1024).toStringAsFixed(2)} GB',
                value: auth.user?.autoCleanupMedia ?? true,
                onChanged: setAutoCleanupMedia,
              ),
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.LogOut,
                label: l10n.authSettingsLogout,
                onTap: () async {
                  // [kelivo-hosted] This page is itself a pushed route (on
                  // top of `AuthGate`'s root route) — `AuthProvider.logout`
                  // flips `AuthGate`'s state to `signedOut` underneath, but
                  // that alone doesn't pop *this* route off the stack, so
                  // without the `popUntil` below the user stays stuck
                  // looking at the (now-defunct) settings page instead of
                  // landing on `LoginPage`. Capture the navigator before
                  // the `await` since `context` shouldn't be used across an
                  // async gap.
                  final navigator = Navigator.of(context);
                  final assistantProvider = context.read<AssistantProvider>();
                  await context.read<AuthProvider>().logout(
                    context.read<ChatService>(),
                    assistantProvider,
                  );
                  navigator.popUntil((route) => route.isFirst);
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
                icon: Lucide.SunMoon,
                label: l10n.settingsPageColorMode,
                detailText: modeLabel(settings.themeMode),
                onTap: pickThemeMode,
              ),
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.Monitor,
                label: l10n.settingsPageDisplay,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DisplaySettingsPage(),
                    ),
                  );
                },
              ),
              _settingsDivider(context),
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
            ],
          ),

          header(l10n.settingsPageModelsServicesSection),
          _settingsSectionCard(
            context,
            children: [
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
                icon: Lucide.Earth,
                label: l10n.settingsPageSearch,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SearchServicesPage(),
                    ),
                  );
                },
              ),
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.Volume2,
                label: l10n.settingsPageTts,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TtsServicesPage()),
                  );
                },
              ),
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.Terminal,
                label: l10n.settingsPageMcp,
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const McpPage()));
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
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.EthernetPort,
                label: l10n.settingsPageNetworkProxy,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NetworkProxyPage()),
                  );
                },
              ),
            ],
          ),

          header(l10n.settingsPageDataSection),
          _settingsSectionCard(
            context,
            children: [
              _settingsNavRow(
                context,
                icon: Lucide.Database,
                label: l10n.settingsPageBackup,
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const BackupPage()));
                },
              ),
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.HardDrive,
                label: l10n.settingsPageChatStorage,
                detailBuilder: (_) => const _ChatStorageSummary(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StorageSpacePage()),
                  );
                },
              ),
            ],
          ),

          header(l10n.settingsPageAboutSection),
          _settingsSectionCard(
            context,
            children: [
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
              _settingsDivider(context),
              _settingsNavRow(
                context,
                icon: Lucide.ChartColumnBig,
                label: l10n.settingsPageStatistics,
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const StatsPage()));
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
              // _iosDivider(context),
              // _iosNavRow(
              //   context,
              //   icon: Lucide.Share2,
              //   label: l10n.settingsPageShare,
              //   onTap: () async {
              //     // Provide anchor rect from overlay for iPad share sheet
              //     Rect anchor;
              //     try {
              //       final overlay = Overlay.of(context);
              //       final ro = overlay?.context.findRenderObject();
              //       if (ro is RenderBox && ro.hasSize) {
              //         final center = ro.size.center(Offset.zero);
              //         final global = ro.localToGlobal(center);
              //         anchor = Rect.fromCenter(center: global, width: 1, height: 1);
              //       } else {
              //         final size = MediaQuery.of(context).size;
              //         anchor = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
              //       }
              //     } catch (_) {
              //       final size = MediaQuery.of(context).size;
              //       anchor = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
              //     }
              //     await Share.share(l10n.settingsShare, sharePositionOrigin: anchor);
              //   },
              // ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
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
  return Card(
    color: AppColors.groupedSurface(Theme.of(context).brightness),
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}

Widget _settingsDivider(BuildContext context) {
  final brightness = Theme.of(context).brightness;
  return Divider(
    height: 1,
    thickness: 1,
    indent: 56,
    color: AppColors.listDivider(brightness),
  );
}

class _ChatStorageSummary extends StatefulWidget {
  const _ChatStorageSummary();

  @override
  State<_ChatStorageSummary> createState() => _ChatStorageSummaryState();
}

class _ChatStorageSummaryState extends State<_ChatStorageSummary> {
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
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      color: cs.onSurface.withValues(alpha: 0.6),
      fontSize: 13,
    );

    return FutureBuilder<StorageUsageReport>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(l10n.settingsPageCalculating, style: style);
        }
        final count = data?.totalFiles ?? 0;
        final size = _fmtBytes(data?.totalBytes ?? 0);
        return Text(l10n.settingsPageFilesCount(count, size), style: style);
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

Widget _settingsSwitchRow(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  final cs = Theme.of(context).colorScheme;
  return AppListTile(
    onTap: () => onChanged(!value),
    onTapFeedback: () {
      if (context.read<SettingsProvider>().hapticsOnListItemTap) {
        Haptics.soft();
      }
    },
    leading: Icon(
      icon,
      size: 24,
      color: AppColors.secondaryLabel(Theme.of(context).brightness),
    ),
    title: Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 16,
        color: cs.onSurface,
        fontWeight: FontWeight.w400,
      ),
    ),
    subtitle: Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
    ),
    trailing: AppSwitch(
      value: value,
      activeTrackColor: cs.primary,
      semanticLabel: title,
      onChanged: onChanged,
    ),
  );
}

// Bottom sheet iOS-style option with tactile feedback (no ripple)
Widget _sheetOption(
  BuildContext context, {
  required IconData icon,
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
    leading: Icon(icon, size: 20, color: cs.onSurface),
    title: Text(label, style: TextStyle(fontSize: 15, color: cs.onSurface)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    minLeadingWidth: 24,
    horizontalTitleGap: 12,
    minVerticalPadding: 14,
  );
}

Widget _sheetDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 1,
    thickness: 0.6,
    indent: 52,
    endIndent: 16,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}
