import 'dart:io' show File;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/models/assistant.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/app_list_group.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/widgets/emoji_text.dart';
import '../../../utils/avatar_cache.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../theme/app_font_weights.dart';

// Show an assistant picker for moving a topic.
// - Mobile: bottom sheet
// - Desktop: custom dialog
// Returns selected assistant id, or null if cancelled.
Future<String?> showAssistantMoveSelector(
  BuildContext context, {
  String? excludeAssistantId,
}) async {
  final isDesktop =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  final ap = context.read<AssistantProvider>();
  final List<Assistant> assistants = excludeAssistantId == null
      ? List.of(ap.assistants)
      : ap.assistants.where((a) => a.id != excludeAssistantId).toList();

  if (!isDesktop) {
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l10n.sideDrawerChooseAssistantTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: AppFontWeights.emphasis,
                        ),
                      ),
                    ),
                    ...assistants.map((a) => _assistantRow(ctx, a)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Desktop: custom dialog with hover effects, no ripples, no header divider
  String? result;
  await showAppDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'assistant-move-selector',
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx)!;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(ctx).maybePop(),
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {},
              child: AppDialogSurface(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 560,
                    minWidth: 420,
                    maxHeight: 560,
                  ),
                  child: AppListGroup(
                    backgroundColor: Colors.transparent,
                    borderRadius: BorderRadius.circular(38),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header (no divider below)
                        SizedBox(
                          height: 48,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.sideDrawerChooseAssistantTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: AppFontWeights.emphasis,
                                    ),
                                  ),
                                ),
                                _SmallIconBtn2(
                                  icon: Icons.close,
                                  onTap: () => Navigator.of(ctx).maybePop(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                            itemCount: assistants.length,
                            itemBuilder: (c, i) => _DeskAssistantRow(
                              assistant: assistants[i],
                              onTap: (id) {
                                result = id;
                                Navigator.of(ctx).maybePop();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  return result;
}

Widget _assistantAvatar(BuildContext context, Assistant a, {double size = 28}) {
  final cs = Theme.of(context).colorScheme;
  final av = (a.avatar ?? '').trim();
  if (av.isNotEmpty) {
    if (av.startsWith('http')) {
      return FutureBuilder<String?>(
        future: AvatarCache.getPath(av),
        builder: (ctx, snap) {
          final p = snap.data;
          if (p != null && File(p).existsSync()) {
            return ClipOval(
              child: Image(
                image: FileImage(File(p)),
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            );
          }
          return ClipOval(
            child: Image.network(
              av,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => _assistantInitial(cs, a.name, size),
            ),
          );
        },
      );
    } else if (!kIsWeb && (av.startsWith('/') || av.contains(':'))) {
      final fixed = SandboxPathResolver.fix(av);
      final f = File(fixed);
      if (f.existsSync()) {
        return ClipOval(
          child: Image(
            image: FileImage(f),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      }
    } else {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: EmojiText(
          (av.isNotEmpty ? av : '🙂'),
          fontSize: size * 0.5,
          optimizeEmojiAlign: true,
        ),
      );
    }
  }
  return _assistantInitial(cs, a.name, size);
}

Widget _assistantInitial(ColorScheme cs, String name, double size) {
  final letter = name.trim().isNotEmpty ? name.trim()[0] : '?';
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: cs.primary.withValues(alpha: 0.15),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(
      letter,
      style: TextStyle(
        color: cs.primary,
        fontSize: size * 0.42,
        fontWeight: AppFontWeights.emphasis,
      ),
    ),
  );
}

Widget _assistantRow(BuildContext context, Assistant a) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: AppListTile(
      dense: true,
      leading: _assistantAvatar(context, a, size: 24),
      title: Text(
        a.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
      ),
      onTapFeedback: Haptics.light,
      onTap: () => Navigator.of(context).pop(a.id),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minLeadingWidth: 24,
      horizontalTitleGap: 10,
    ),
  );
}

class _SmallIconBtn2 extends StatefulWidget {
  const _SmallIconBtn2({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  State<_SmallIconBtn2> createState() => _SmallIconBtn2State();
}

class _SmallIconBtn2State extends State<_SmallIconBtn2> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hover
        ? (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05))
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(widget.icon, size: 18, color: cs.onSurface),
        ),
      ),
    );
  }
}

class _DeskAssistantRow extends StatelessWidget {
  const _DeskAssistantRow({required this.assistant, required this.onTap});
  final Assistant assistant;
  final void Function(String id) onTap;

  @override
  Widget build(BuildContext context) => AppDialogControlTile(
    leading: _assistantAvatar(context, assistant, size: 22),
    title: Text(assistant.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    onTap: () => onTap(assistant.id),
    minLeadingWidth: 22,
    horizontalTitleGap: 10,
  );
}
