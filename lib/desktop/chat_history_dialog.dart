import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:Kelivo/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../icons/lucide_adapter.dart';
import '../l10n/app_localizations.dart';
import '../shared/animations/widgets.dart';
import '../shared/widgets/snackbar.dart';
import '../core/services/chat/chat_service.dart';
import '../core/models/conversation.dart';
import '../theme/app_font_weights.dart';

Future<String?> showChatHistoryDesktopDialog(
  BuildContext context, {
  String? assistantId,
}) {
  return showAppDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _ChatHistoryDesktopDialog(assistantId: assistantId),
  );
}

class _ChatHistoryDesktopDialog extends StatefulWidget {
  const _ChatHistoryDesktopDialog({required this.assistantId});
  final String? assistantId;

  @override
  State<_ChatHistoryDesktopDialog> createState() =>
      _ChatHistoryDesktopDialogState();
}

class _ChatHistoryDesktopDialogState extends State<_ChatHistoryDesktopDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searching = false;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final chatService = context.watch<ChatService>();
    final List<Conversation> all = chatService
        .getAllConversations()
        .where(
          (c) =>
              widget.assistantId == null ||
              c.assistantId == widget.assistantId ||
              c.assistantId == null,
        )
        .toList();

    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all.where((c) => c.title.toLowerCase().contains(q)).toList();
    final pinned = filtered.where((c) => c.isPinned).toList();
    final others = filtered.where((c) => !c.isPinned).toList();

    return AppDialogFrame(
      elevation: 12,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 560,
          minWidth: 420,
          maxHeight: 640,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kAppDialogRadius),
          child: Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.chatHistoryPageTitle,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: AppFontWeights.emphasis,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: l10n.chatHistoryPageSearchTooltip,
                        icon: AnimatedIconSwap(
                          child: Icon(
                            _searching ? Lucide.X : Lucide.Search,
                            key: ValueKey(_searching ? 'x' : 'search'),
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            if (_searching) _searchCtrl.clear();
                            _searching = !_searching;
                          });
                        },
                      ),
                      IconButton(
                        tooltip: l10n.chatHistoryPageDeleteAllTooltip,
                        icon: const Icon(Lucide.Trash2),
                        onPressed: () async {
                          final svc = context.read<ChatService>();
                          final confirm = await showAppDialog<bool>(
                            context: context,
                            builder: (ctx) => AppAlertDialog(
                              title: Text(
                                l10n.chatHistoryPageDeleteAllDialogTitle,
                              ),
                              content: Text(
                                l10n.chatHistoryPageDeleteAllDialogContent,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text(l10n.chatHistoryPageCancel),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: Text(
                                    l10n.chatHistoryPageDelete,
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (!context.mounted) return;
                          if (confirm == true) {
                            final idsToDelete = svc
                                .getAllConversations()
                                .where(
                                  (c) =>
                                      c.assistantId == widget.assistantId &&
                                      !c.isPinned,
                                )
                                .map((c) => c.id)
                                .toList();
                            var blockedByCompaction = false;
                            for (final id in idsToDelete) {
                              if (!await svc.deleteConversation(id)) {
                                blockedByCompaction = true;
                              }
                            }
                            if (!context.mounted) return;
                            if (blockedByCompaction) {
                              showAppSnackBar(
                                context,
                                message:
                                    l10n.hostedContextDeleteDuringCompaction,
                                type: NotificationType.info,
                              );
                            }
                            showAppSnackBar(
                              context,
                              message: l10n.chatHistoryPageDeletedAllSnackbar,
                              type: NotificationType.success,
                            );
                          }
                        },
                      ),
                      IconButton(
                        tooltip: l10n.sideDrawerCancel,
                        icon: const Icon(Lucide.X),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),

                // Search bar (toggle)
                AnimatedSize(
                  duration: kAnim,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !_searching
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: AppTextField(
                            controller: _searchCtrl,
                            autofocus: true,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: l10n.chatHistoryPageSearchHint,
                              filled: true,
                              fillColor: isDark
                                  ? Colors.white10
                                  : const Color(0xFFF2F3F5),
                              isDense: true,
                              isCollapsed: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Colors.transparent,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Colors.transparent,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: cs.primary.withValues(alpha: 0.3),
                                ),
                              ),
                              prefixIcon: Icon(
                                Lucide.Search,
                                color: cs.onSurface.withValues(alpha: 0.7),
                                size: 18,
                              ),
                              suffixIcon: (q.isNotEmpty)
                                  ? IconButton(
                                      icon: Icon(
                                        Lucide.X,
                                        size: 16,
                                        color: cs.onSurface.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                            ),
                            style: TextStyle(fontSize: 14),
                            textAlignVertical: TextAlignVertical.center,
                          ),
                        ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            l10n.chatHistoryPageNoConversations,
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        )
                      : Scrollbar(
                          controller: _scrollCtrl,
                          child: ListView(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                            children: [
                              if (pinned.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    0,
                                    4,
                                    0,
                                    8,
                                  ),
                                  child: Text(
                                    l10n.chatHistoryPagePinnedSection,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: AppFontWeights.semibold,
                                      color: cs.primary,
                                    ),
                                  ),
                                ),
                                for (final c in pinned)
                                  _ConversationTileDesktop(
                                    conversation: c,
                                    onTap: () =>
                                        Navigator.of(context).pop(c.id),
                                  ),
                                const SizedBox(height: 8),
                              ],
                              if (others.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    0,
                                    4,
                                    0,
                                    8,
                                  ),
                                  child: Text(
                                    l10n.chatHistoryPageRecentSection,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: AppFontWeights.semibold,
                                      color: cs.primary,
                                    ),
                                  ),
                                ),
                                for (final c in others)
                                  _ConversationTileDesktop(
                                    conversation: c,
                                    onTap: () =>
                                        Navigator.of(context).pop(c.id),
                                  ),
                              ],
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationTileDesktop extends StatelessWidget {
  const _ConversationTileDesktop({required this.conversation, this.onTap});
  final Conversation conversation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final format = DateFormat(
      locale.languageCode == 'zh'
          ? 'yyyy年M月d日 HH:mm:ss'
          : 'yyyy-MM-dd HH:mm:ss',
    );
    return AppDialogControlTile(
      leading: Icon(
        Lucide.MessageSquare,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
      minLeadingWidth: 20,
      title: Text(
        conversation.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(format.format(conversation.updatedAt)),
      trailing: _PinButtonDesktop(conversation: conversation),
      onTap: onTap,
    );
  }
}

class _PinButtonDesktop extends StatelessWidget {
  const _PinButtonDesktop({required this.conversation});
  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final pinned = conversation.isPinned;
    return InkWell(
      onTap: () async {
        await context.read<ChatService>().togglePinConversation(
          conversation.id,
        );
      },
      borderRadius: BorderRadius.circular(999),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.grey.withValues(alpha: 0.12),
      hoverColor: Colors.grey.withValues(alpha: 0.08),
      child: AnimatedContainer(
        duration: kAnim,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: pinned ? cs.primary.withValues(alpha: 0.12) : cs.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedIconSwap(
              child: Icon(
                pinned ? Lucide.PinOff : Lucide.Pin,
                key: ValueKey(pinned ? 'pinOff' : 'pin'),
                size: 16,
                color: pinned
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedTextSwap(
              text: pinned
                  ? l10n.chatHistoryPagePinned
                  : l10n.chatHistoryPagePin,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: AppFontWeights.semibold,
                color: pinned
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
