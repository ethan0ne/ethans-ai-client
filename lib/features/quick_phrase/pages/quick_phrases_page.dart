import 'package:flutter/material.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/models/quick_phrase.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/design_tokens.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_tile.dart';

class QuickPhrasesPage extends StatefulWidget {
  const QuickPhrasesPage({super.key, this.assistantId});

  final String?
  assistantId; // null = global phrases, non-null = assistant-specific

  @override
  State<QuickPhrasesPage> createState() => _QuickPhrasesPageState();
}

class _QuickPhrasesPageState extends State<QuickPhrasesPage> {
  @override
  void initState() {
    super.initState();
    // Provider will handle loading
  }

  Future<void> _showAddEditSheet({QuickPhrase? phrase}) async {
    final cs = Theme.of(context).colorScheme;
    final quickPhraseProvider = context.read<QuickPhraseProvider>();

    final result = await showModalBottomSheet<Map<String, String>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _QuickPhraseEditSheet(
          phrase: phrase,
          assistantId: widget.assistantId,
        );
      },
    );

    if (!mounted) return;

    if (result != null) {
      final title = result['title']?.trim() ?? '';
      final content = result['content']?.trim() ?? '';

      if (title.isEmpty || content.isEmpty) return;

      if (phrase == null) {
        // Add new
        final newPhrase = QuickPhrase(
          id: const Uuid().v4(),
          title: title,
          content: content,
          isGlobal: widget.assistantId == null,
          assistantId: widget.assistantId,
        );
        await quickPhraseProvider.add(newPhrase);
      } else {
        // Update existing
        await quickPhraseProvider.update(
          phrase.copyWith(title: title, content: content),
        );
      }
    }
  }

  Future<void> _deletePhrase(QuickPhrase phrase) async {
    await context.read<QuickPhraseProvider>().delete(phrase.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final quickPhraseProvider = context.watch<QuickPhraseProvider>();
    final phrases = widget.assistantId == null
        ? quickPhraseProvider.globalPhrases
        : quickPhraseProvider.getForAssistant(widget.assistantId!);

    return AppScaffold(
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.quickPhraseBackTooltip,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(
        widget.assistantId == null
            ? l10n.quickPhraseGlobalTitle
            : l10n.quickPhraseAssistantTitle,
      ),
      actions: [
        AppButtonIslandButton(
          icon: Lucide.Plus,
          semanticLabel: l10n.quickPhraseAddTooltip,
          onTap: () => _showAddEditSheet(),
        ),
      ],
      body: phrases.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Lucide.Zap,
                    size: 64,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.quickPhraseEmptyMessage,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding: EdgeInsets.fromLTRB(
                16,
                AppScaffold.scrollContentTop(context),
                16,
                16,
              ),
              itemCount: phrases.length,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                // Smooth scale, no shadow/elevation
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final t = Curves.easeOut.transform(animation.value);
                    return Transform.scale(
                      scale: 0.98 + 0.02 * t,
                      child: child,
                    );
                  },
                );
              },
              onReorderItem: (oldIndex, newIndex) {
                // Update immediately for smooth drop animation
                context.read<QuickPhraseProvider>().reorderPhrases(
                  oldIndex: oldIndex,
                  newIndex: newIndex,
                  assistantId: widget.assistantId,
                );
              },
              itemBuilder: (context, index) {
                final phrase = phrases[index];
                return KeyedSubtree(
                  key: ValueKey('reorder-quick-phrase-${phrase.id}'),
                  child: ReorderableDelayedDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Slidable(
                        key: ValueKey(phrase.id),
                        endActionPane: ActionPane(
                          motion: const StretchMotion(),
                          extentRatio: 0.35,
                          children: [
                            CustomSlidableAction(
                              autoClose: true,
                              backgroundColor: Colors.transparent,
                              child: Container(
                                width: double.infinity,
                                height: double.infinity,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? cs.error.withValues(alpha: 0.22)
                                      : cs.error.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
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
                                        l10n.quickPhraseDeleteButton,
                                        style: TextStyle(
                                          color: cs.error,
                                          fontWeight: AppFontWeights.emphasis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              onPressed: (_) => _deletePhrase(phrase),
                            ),
                          ],
                        ),
                        child: AppListGroup(
                          child: AppListTile(
                            onTapFeedback: Haptics.soft,
                            onTap: () => _showAddEditSheet(phrase: phrase),
                            leading: Icon(
                              Lucide.Zap,
                              size: 18,
                              color: cs.primary,
                            ),
                            title: Text(
                              phrase.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            subtitle: Text(
                              phrase.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                            trailing: Icon(
                              Lucide.ChevronRight,
                              size: 16,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            minLeadingWidth: 18,
                            horizontalTitleGap: 8,
                            minVerticalPadding: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _QuickPhraseEditSheet extends StatefulWidget {
  const _QuickPhraseEditSheet({
    required this.phrase,
    required this.assistantId,
  });

  final QuickPhrase? phrase;
  final String? assistantId;

  @override
  State<_QuickPhraseEditSheet> createState() => _QuickPhraseEditSheetState();
}

class _QuickPhraseEditSheetState extends State<_QuickPhraseEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.phrase?.title ?? '');
    _contentController = TextEditingController(
      text: widget.phrase?.content ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 12),
            Center(
              child: Text(
                widget.phrase == null
                    ? l10n.quickPhraseAddTitle
                    : l10n.quickPhraseEditTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: AppFontWeights.semibold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.quickPhraseTitleLabel,
                filled: true,
                fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.primary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: l10n.quickPhraseContentLabel,
                alignLabelWithHint: true,
                filled: true,
                fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.primary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _IosOutlineButton(
                    label: l10n.quickPhraseCancelButton,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _IosFilledButton(
                    label: l10n.quickPhraseSaveButton,
                    onTap: () {
                      Navigator.of(context).pop({
                        'title': _titleController.text,
                        'content': _contentController.text,
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IosOutlineButton extends StatefulWidget {
  const _IosOutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  State<_IosOutlineButton> createState() => _IosOutlineButtonState();
}

class _IosOutlineButtonState extends State<_IosOutlineButton> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) =>
          Future.delayed(const Duration(milliseconds: 80), () => _set(false)),
      onTapCancel: () => _set(false),
      onTap: () {
        Haptics.soft();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withValues(alpha: 0.5)),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: cs.primary,
              fontWeight: AppFontWeights.semibold,
            ),
          ),
        ),
      ),
    );
  }
}

class _IosFilledButton extends StatefulWidget {
  const _IosFilledButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  State<_IosFilledButton> createState() => _IosFilledButtonState();
}

class _IosFilledButtonState extends State<_IosFilledButton> {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) =>
          Future.delayed(const Duration(milliseconds: 80), () => _set(false)),
      onTapCancel: () => _set(false),
      onTap: () {
        Haptics.soft();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: cs.onPrimary,
              fontWeight: AppFontWeights.semibold,
            ),
          ),
        ),
      ),
    );
  }
}
