import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/mcp_provider.dart';
import '../widgets/mcp_server_edit_sheet.dart';
import '../widgets/mcp_json_edit_sheet.dart';
import '../widgets/mcp_timeout_sheet.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/design_tokens.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_tile.dart';

class McpPage extends StatelessWidget {
  const McpPage({super.key});

  Color _statusColor(BuildContext context, McpStatus s) {
    final cs = Theme.of(context).colorScheme;
    switch (s) {
      case McpStatus.connected:
        return Colors.green;
      case McpStatus.connecting:
        return cs.primary;
      case McpStatus.error:
      case McpStatus.idle:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final mcp = context.watch<McpProvider>();
    final servers = mcp.servers.toList();

    Future<void> showErrorDetails(
      String serverId,
      String? message,
      String name,
    ) async {
      final cs = Theme.of(context).colorScheme;
      final l10n = AppLocalizations.of(context)!;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.mcpPageErrorDialogTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: AppFontWeights.emphasis,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white10
                          : const Color(0xFFF7F7F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      message?.isNotEmpty == true
                          ? message!
                          : l10n.mcpPageErrorNoDetails,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(ctx).maybePop(),
                          icon: Icon(Lucide.X, size: 16, color: cs.primary),
                          label: Text(
                            l10n.mcpPageClose,
                            style: TextStyle(color: cs.primary),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            backgroundColor:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white10
                                : const Color(0xFFF2F3F5),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.35),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final mcpProvider = ctx.read<McpProvider>();
                            await mcpProvider.reconnect(serverId);
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                          },
                          icon: const Icon(Lucide.RefreshCw, size: 18),
                          label: Text(l10n.mcpPageReconnect),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return AppScaffold(
      extendBodyBehindAppBar: false,
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.mcpPageBackTooltip,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(l10n.mcpAssistantSheetTitle),
      actions: [
        AppButtonIslandButton(
          icon: Lucide.Timer,
          semanticLabel: l10n.mcpTimeoutSettingsTooltip,
          onTap: () async => showMcpTimeoutSheet(context),
        ),
        AppButtonIslandButton(
          icon: Lucide.Edit,
          semanticLabel: l10n.mcpJsonEditButtonTooltip,
          onTap: () async => showMcpJsonEditSheet(context),
        ),
        AppButtonIslandButton(
          icon: Lucide.Plus,
          semanticLabel: l10n.mcpPageAddMcpTooltip,
          onTap: () async => showMcpServerEditSheet(context),
        ),
      ],
      body: servers.isEmpty
          ? Center(
              child: Text(
                l10n.mcpPageNoServers,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: servers.length,
              itemBuilder: (context, index) {
                final s = servers[index];
                final st = mcp.statusFor(s.id);
                final err = mcp.errorFor(s.id);

                Widget tagStyled(String text, {Color? color}) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (color ?? cs.primary).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: (color ?? cs.primary).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 11,
                      color: color ?? cs.primary,
                      fontWeight: AppFontWeights.emphasis,
                    ),
                  ),
                );

                final isDark = Theme.of(context).brightness == Brightness.dark;
                final cardRadius = BorderRadius.circular(AppRadius.md);
                final statusIcon = Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white10
                            : const Color(0xFFF2F3F5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Lucide.Terminal, size: 20, color: cs.primary),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: st == McpStatus.connecting
                          ? SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  cs.primary,
                                ),
                              ),
                            )
                          : Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: s.enabled
                                    ? _statusColor(context, st)
                                    : cs.outline,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: cs.surface,
                                  width: 1.5,
                                ),
                              ),
                            ),
                    ),
                  ],
                );
                final tags = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    tagStyled(
                      st == McpStatus.connected
                          ? l10n.mcpPageStatusConnected
                          : (st == McpStatus.connecting
                                ? l10n.mcpPageStatusConnecting
                                : l10n.mcpPageStatusDisconnected),
                      color: st == McpStatus.connected
                          ? Colors.green
                          : (st == McpStatus.connecting
                                ? cs.primary
                                : Colors.redAccent),
                    ),
                    tagStyled(
                      s.transport == McpTransportType.inmemory
                          ? l10n.mcpTransportTagInmemory
                          : (s.transport == McpTransportType.sse
                                ? l10n.mcpTransportTagSse
                                : l10n.mcpTransportTagHttp),
                    ),
                    tagStyled(
                      l10n.mcpPageToolsCount(
                        s.tools.where((t) => t.enabled).length,
                        s.tools.length,
                      ),
                    ),
                    if (!s.enabled)
                      tagStyled(
                        l10n.mcpPageStatusDisabled,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                  ],
                );
                final subtitle = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    tags,
                    if (st == McpStatus.error && (err?.isNotEmpty ?? false))
                      Row(
                        children: [
                          const Icon(
                            Lucide.MessageCircleWarning,
                            size: 14,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.mcpPageConnectionFailed,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                showErrorDetails(s.id, err, s.name),
                            child: Text(l10n.mcpPageDetails),
                          ),
                        ],
                      ),
                  ],
                );
                final row = Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white10
                        : Colors.white.withValues(alpha: 0.96),
                    borderRadius: cardRadius,
                    border: Border.all(
                      color: cs.outlineVariant.withValues(
                        alpha: isDark ? 0.1 : 0.08,
                      ),
                      width: 0.6,
                    ),
                  ),
                  child: AppListTile(
                    onTap: () async {
                      await showMcpServerEditSheet(context, serverId: s.id);
                    },
                    leading: statusIcon,
                    title: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    subtitle: subtitle,
                    trailing: Icon(
                      Lucide.ChevronRight,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    minLeadingWidth: 42,
                    horizontalTitleGap: 12,
                    minVerticalPadding: 11,
                  ),
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Slidable(
                    key: ValueKey('mcp-${s.id}'),
                    endActionPane: ActionPane(
                      motion: const StretchMotion(),
                      extentRatio: 0.42,
                      children: [
                        CustomSlidableAction(
                          autoClose: true,
                          backgroundColor: Colors.transparent,
                          child: Container(
                            width: double.infinity,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? cs.error.withValues(alpha: 0.22)
                                  : cs.error.withValues(alpha: 0.14),
                              // Match list card radius for consistency
                              borderRadius: cardRadius,
                              border: Border.all(
                                color: cs.error.withValues(alpha: 0.35),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            alignment: Alignment.center,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Lucide.Trash2,
                                    color: cs.error,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    l10n.mcpPageDelete,
                                    style: TextStyle(
                                      color: cs.error,
                                      fontWeight: AppFontWeights.emphasis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          onPressed: (_) async {
                            final prov = context.read<McpProvider>();
                            final prev = prov.getById(s.id);
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (dctx) => AlertDialog(
                                backgroundColor: cs.surface,
                                title: Text(l10n.mcpPageConfirmDeleteTitle),
                                content: Text(l10n.mcpPageConfirmDeleteContent),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dctx).pop(false),
                                    child: Text(l10n.mcpPageCancel),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dctx).pop(true),
                                    child: Text(l10n.mcpPageDelete),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            await prov.removeServer(s.id);
                            if (!context.mounted) return;
                            showAppSnackBar(
                              context,
                              message: l10n.mcpPageServerDeleted,
                              type: NotificationType.info,
                              actionLabel: l10n.mcpPageUndo,
                              onAction: () {
                                if (prev == null) return;
                                Future(() async {
                                  final newId = await prov.addServer(
                                    enabled: prev.enabled,
                                    name: prev.name,
                                    transport: prev.transport,
                                    url: prev.url,
                                    headers: prev.headers,
                                  );
                                  // Try to refresh tools when back online
                                  try {
                                    await prov.refreshTools(newId);
                                  } catch (_) {}
                                });
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    child: row,
                  ),
                );
              },
            ),
    );
  }
}

// --- iOS-style tactile helpers ---

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
