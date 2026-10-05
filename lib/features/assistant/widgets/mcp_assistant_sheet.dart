import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import '../../../shared/widgets/app_button_island.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/app_list_group.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../shared/widgets/app_switch.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';

Future<void> showAssistantMcpSheet(
  BuildContext context, {
  required String assistantId,
}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final connectedServerIds = context
      .read<McpProvider>()
      .servers
      .where(
        (server) =>
            context.read<McpProvider>().statusFor(server.id) ==
            McpStatus.connected,
      )
      .map((server) => server.id)
      .toList(growable: false);

  Future<void> setAll(bool enabled) async {
    final assistant = context.read<AssistantProvider>().getById(assistantId);
    if (assistant == null) return;
    await context.read<AssistantProvider>().updateAssistant(
      assistant.copyWith(
        mcpServerIds: enabled ? connectedServerIds : const <String>[],
      ),
    );
  }

  await showAppPopupSheet<void>(
    context: context,
    title: l10n.mcpAssistantSheetTitle,
    showCloseButton: false,
    actions: [
      if (connectedServerIds.isNotEmpty)
        AppButtonIslandButton(
          icon: Icons.more_horiz,
          semanticLabel: MaterialLocalizations.of(context).showMenuTooltip,
          menuTitle: l10n.mcpAssistantSheetTitle,
          menuItems: [
            FrostedPopupMenuItem(
              icon: Icons.check_rounded,
              label: l10n.mcpAssistantSheetSelectAll,
              onPressed: () => setAll(true),
            ),
            FrostedPopupMenuItem(
              icon: Icons.close_rounded,
              label: l10n.mcpAssistantSheetClearAll,
              onPressed: () => setAll(false),
            ),
          ],
        ),
      appPopupDoneAction(
        semanticLabel: l10n.homePageDone,
        onTap: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
    ],
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AssistantMcpSheet(assistantId: assistantId),
  );
}

class _AssistantMcpSheet extends StatelessWidget {
  const _AssistantMcpSheet({required this.assistantId});
  final String assistantId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final mcp = context.watch<McpProvider>();
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(assistantId)!;

    final selected = a.mcpServerIds.toSet();
    final servers = mcp.servers
        .where((s) => mcp.statusFor(s.id) == McpStatus.connected)
        .toList();

    Widget tag(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: cs.primary,
          fontWeight: AppFontWeights.semibold,
        ),
      ),
    );

    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: servers.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            l10n.assistantEditMcpNoServersMessage,
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemBuilder: (context, index) {
                          final s = servers[index];
                          final tools = s.tools;
                          final enabledTools = tools
                              .where((t) => t.enabled)
                              .length;
                          final isSelected = selected.contains(s.id);
                          return AppListGroup(
                            child: AppListTile(
                              onTap: () async {
                                Haptics.light();
                                final set = a.mcpServerIds.toSet();
                                if (isSelected) {
                                  set.remove(s.id);
                                } else {
                                  set.add(s.id);
                                }
                                await context
                                    .read<AssistantProvider>()
                                    .updateAssistant(
                                      a.copyWith(mcpServerIds: set.toList()),
                                    );
                              },
                              leading: Icon(
                                Lucide.Hammer,
                                size: 18,
                                color: cs.primary,
                              ),
                              title: Text(
                                s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  color: cs.onSurface,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  tag(
                                    l10n.assistantEditMcpToolsCountTag(
                                      enabledTools.toString(),
                                      tools.length.toString(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AppSwitch(
                                    value: isSelected,
                                    onChanged: (v) async {
                                      final set = a.mcpServerIds.toSet();
                                      if (v) {
                                        set.add(s.id);
                                      } else {
                                        set.remove(s.id);
                                      }
                                      await context
                                          .read<AssistantProvider>()
                                          .updateAssistant(
                                            a.copyWith(
                                              mcpServerIds: set.toList(),
                                            ),
                                          );
                                    },
                                  ),
                                ],
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              minVerticalPadding: 6,
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemCount: servers.length,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
