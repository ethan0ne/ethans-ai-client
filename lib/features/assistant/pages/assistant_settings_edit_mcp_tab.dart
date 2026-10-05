part of 'assistant_settings_edit_page.dart';

class _McpTab extends StatelessWidget {
  const _McpTab({required this.assistantId});
  final String assistantId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final mcp = context.watch<McpProvider>();
    final ap = context.watch<AssistantProvider>();
    final assistant = ap.getById(assistantId)!;

    final selected = assistant.mcpServerIds.toSet();
    final servers = mcp.servers
        .where((server) => mcp.statusFor(server.id) == McpStatus.connected)
        .toList();

    Future<void> updateSelected(Set<String> ids) {
      return context.read<AssistantProvider>().updateAssistant(
        assistant.copyWith(mcpServerIds: ids.toList(growable: false)),
      );
    }

    return ListView(
      padding: AppScaffold.scrollPadding(
        context,
        const EdgeInsets.fromLTRB(16, 12, 16, 16),
      ),
      children: [
        _iosSectionCard(
          children: [
            if (servers.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
                child: Center(
                  child: Text(
                    l10n.assistantEditMcpNoServersDescription,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              )
            else
              for (final entry in servers.asMap().entries) ...[
                if (entry.key > 0) _iosDivider(context),
                _McpServerRow(
                  server: entry.value,
                  selected: selected.contains(entry.value.id),
                  onChanged: (enabled) async {
                    final ids = selected.toSet();
                    if (enabled) {
                      ids.add(entry.value.id);
                    } else {
                      ids.remove(entry.value.id);
                    }
                    await updateSelected(ids);
                  },
                ),
              ],
          ],
        ),
      ],
    );
  }
}

class _McpServerRow extends StatelessWidget {
  const _McpServerRow({
    required this.server,
    required this.selected,
    required this.onChanged,
  });

  final McpServerConfig server;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final enabledToolCount = server.tools.where((tool) => tool.enabled).length;
    return AppListTile(
      onTapFeedback: () {
        if (context.read<SettingsProvider>().hapticsOnListItemTap) {
          Haptics.soft();
        }
        FocusManager.instance.primaryFocus?.unfocus();
      },
      onTap: () => onChanged(!selected),
      leading: Icon(Lucide.Hammer, size: 24, color: cs.primary),
      title: Text(
        server.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
      ),
      subtitle: Text(
        l10n.assistantEditMcpToolsCountTag(
          enabledToolCount.toString(),
          server.tools.length.toString(),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: AppSwitch(value: selected, onChanged: onChanged),
      minVerticalPadding: 8,
    );
  }
}
