import 'package:flutter/material.dart';
import 'tts_services_page.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_group.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../theme/design_tokens.dart';
import '../../backup/pages/backup_page.dart';
import '../../mcp/pages/mcp_page.dart';
import '../../search/pages/search_services_page.dart';
import '../../stats/pages/stats_page.dart';
import '../../translate/pages/translate_page.dart';
import '../../chat/pages/chat_history_page.dart';
import 'display_settings_page.dart';
import 'debug_development_page.dart';
import 'network_proxy_page.dart';

class LaboratoryPage extends StatelessWidget {
  const LaboratoryPage({super.key});

  @override
  Widget build(BuildContext context) {
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
      title: AppScaffoldTitle(l10n.settingsPageLaboratory),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          AppScaffold.scrollContentTop(context),
          16,
          AppScaffold.scrollContentBottom(context),
        ),
        children: [
          AppListGroup.list(
            children: [
              AppSettingsNavTile(
                icon: Lucide.Languages,
                label: l10n.desktopNavTranslateTooltip,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TranslatePage()),
                ),
              ),
              const AppListDivider.forTile(hasLeading: true),
              AppSettingsNavTile(
                icon: Lucide.History,
                label: l10n.chatHistoryPageTitle,
                onTap: () async {
                  final selectedConversationId = await Navigator.of(context)
                      .push<String>(
                        MaterialPageRoute(
                          builder: (_) => const ChatHistoryPage(),
                        ),
                      );
                  if (context.mounted && selectedConversationId != null) {
                    Navigator.of(context).pop(selectedConversationId);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppListGroup.list(
            children: [
              AppSettingsNavTile(
                icon: Lucide.Terminal,
                label: l10n.settingsPageMcp,
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const McpPage())),
              ),
              const AppListDivider.forTile(hasLeading: true),
              AppSettingsNavTile(
                icon: Lucide.Volume2,
                label: l10n.settingsPageTts,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TtsServicesPage()),
                ),
              ),
              const AppListDivider.forTile(hasLeading: true),
              AppSettingsNavTile(
                icon: Lucide.Earth,
                label: l10n.settingsPageSearch,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchServicesPage()),
                ),
              ),
              const AppListDivider.forTile(hasLeading: true),
              AppSettingsNavTile(
                icon: Lucide.EthernetPort,
                label: l10n.settingsPageNetworkProxy,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NetworkProxyPage()),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppListGroup.list(
            children: [
              AppSettingsNavTile(
                icon: Lucide.Monitor,
                label: l10n.settingsPageDisplay,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DisplaySettingsPage(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppListGroup.list(
            children: [
              AppSettingsNavTile(
                icon: Lucide.Database,
                label: l10n.settingsPageBackup,
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const BackupPage())),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppListGroup.list(
            children: [
              AppSettingsNavTile(
                icon: Lucide.ChartColumnBig,
                label: l10n.settingsPageStatistics,
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const StatsPage())),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppListGroup.list(
            children: [
              AppSettingsNavTile(
                icon: Lucide.Code,
                label: l10n.settingsPageDebugAndDevelopment,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DebugDevelopmentPage(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
