import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:Kelivo/shared/widgets/app_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_switch.dart';
import '../../../theme/app_font_weights.dart';

Future<void> showConversationMcpSheet(
  BuildContext context, {
  required String conversationId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  await showAppPopupSheet<void>(
    context: context,
    title: l10n.mcpConversationSheetTitle,
    showCloseButton: false,
    actions: [
      appPopupDoneAction(
        semanticLabel: l10n.homePageDone,
        onTap: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
    ],
    isScrollControlled: true,
    builder: (_) => _ConversationMcpSheet(conversationId: conversationId),
  );
}

class _ConversationMcpSheet extends StatelessWidget {
  const _ConversationMcpSheet({required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final mcp = context.watch<McpProvider>();
    final chat = context.watch<ChatService>();

    final selected = chat.getConversationMcpServers(conversationId).toSet();
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

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.45,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.mcpConversationSheetSubtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (servers.isNotEmpty) ...[
                    TextButton.icon(
                      onPressed: () async {
                        final ids = servers
                            .map((e) => e.id)
                            .toList(growable: false);
                        await context
                            .read<ChatService>()
                            .setConversationMcpServers(conversationId, ids);
                      },
                      icon: Icon(Lucide.Check, size: 16, color: cs.primary),
                      label: Text(l10n.mcpConversationSheetSelectAll),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () async {
                        await context
                            .read<ChatService>()
                            .setConversationMcpServers(
                              conversationId,
                              const <String>[],
                            );
                      },
                      icon: Icon(Lucide.X, size: 16, color: cs.primary),
                      label: Text(l10n.mcpConversationSheetClearAll),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: servers.isEmpty
                    ? Center(
                        child: Text(
                          l10n.mcpConversationSheetNoRunning,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        itemBuilder: (context, index) {
                          final s = servers[index];
                          final tools = s.tools;
                          final enabledTools = tools
                              .where((t) => t.enabled)
                              .length;
                          final isSelected = selected.contains(s.id);
                          void setSelected(bool value) => context
                              .read<ChatService>()
                              .toggleConversationMcpServer(
                                conversationId,
                                s.id,
                                value,
                              );

                          return AppListGroup(
                            child: AppListTile(
                              selected: isSelected,
                              onTap: () => setSelected(!isSelected),
                              leading: Icon(
                                Lucide.Terminal,
                                size: 24,
                                color: cs.primary,
                              ),
                              title: Text(
                                s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: AppFontWeights.emphasis,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    tag(l10n.mcpConversationSheetConnected),
                                    tag(
                                      l10n.mcpConversationSheetToolsCount(
                                        enabledTools,
                                        tools.length,
                                      ),
                                    ),
                                    tag(
                                      s.transport == McpTransportType.inmemory
                                          ? l10n.mcpTransportTagInmemory
                                          : (s.transport == McpTransportType.sse
                                                ? 'SSE'
                                                : 'HTTP'),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: AppSwitch(
                                value: isSelected,
                                onChanged: setSelected,
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemCount: servers.length,
                      ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
