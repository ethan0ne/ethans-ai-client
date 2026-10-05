import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:Kelivo/shared/widgets/popup_content_frame.dart';
import 'package:flutter/material.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/models/quick_phrase.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import '../../../core/providers/settings_provider.dart';
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
  String? _draggedPhraseId;

  @override
  void initState() {
    super.initState();
    // Provider will handle loading
  }

  void _finishDragging(String id) {
    if (!mounted || _draggedPhraseId != id) return;
    setState(() => _draggedPhraseId = null);
  }

  Future<void> _showAddEditSheet({QuickPhrase? phrase}) async {
    final quickPhraseProvider = context.read<QuickPhraseProvider>();
    final l10n = AppLocalizations.of(context)!;
    final editorKey = GlobalKey<_QuickPhraseEditSheetState>();

    final result = await showAppPopupSheet<Map<String, String>?>(
      context: context,
      title: phrase == null
          ? l10n.quickPhraseAddTitle
          : l10n.quickPhraseEditTitle,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.quickPhraseSaveButton,
          onTap: () => editorKey.currentState?._submit(),
        ),
      ],
      isScrollControlled: true,
      extendBodyBehindHeader: true,
      builder: (_) {
        return _QuickPhraseEditSheet(
          key: editorKey,
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

    final quickPhraseProvider = context.watch<QuickPhraseProvider>();
    final phrases = widget.assistantId == null
        ? quickPhraseProvider.globalPhrases
        : quickPhraseProvider.getForAssistant(widget.assistantId!);
    final restingPhrases = phrases
        .where((phrase) => phrase.id != _draggedPhraseId)
        .toList();

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
                AppScaffold.scrollContentBottom(context),
              ),
              itemCount: phrases.length,
              buildDefaultDragHandles: false,
              onReorderStart: (index) {
                setState(() => _draggedPhraseId = phrases[index].id);
              },
              proxyDecorator: (child, index, animation) =>
                  _SettingsQuickPhraseDragProxy(
                    animation: animation,
                    onLanded: () => _finishDragging(phrases[index].id),
                    child: child,
                  ),
              onReorderItem: (oldIndex, newIndex) async {
                // Update immediately for smooth drop animation
                final reorder = context
                    .read<QuickPhraseProvider>()
                    .reorderPhrases(
                      oldIndex: oldIndex,
                      newIndex: newIndex,
                      assistantId: widget.assistantId,
                    );
                final draggedId = _draggedPhraseId;
                if (draggedId != null) _finishDragging(draggedId);
                await reorder;
              },
              itemBuilder: (context, index) {
                final phrase = phrases[index];
                return KeyedSubtree(
                  key: ValueKey('reorder-settings-quick-phrase-${phrase.id}'),
                  child: ReorderableDelayedDragStartListener(
                    index: index,
                    child: _SettingsQuickPhraseCard(
                      phrase: phrase,
                      onDelete: () => _deletePhrase(phrase),
                      onTap: () => _showAddEditSheet(phrase: phrase),
                      isFirst:
                          restingPhrases.isNotEmpty &&
                          phrase.id == restingPhrases.first.id,
                      isLast:
                          restingPhrases.isNotEmpty &&
                          phrase.id == restingPhrases.last.id,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _SettingsQuickPhraseCard extends StatelessWidget {
  const _SettingsQuickPhraseCard({
    required this.phrase,
    required this.onDelete,
    required this.onTap,
    required this.isFirst,
    required this.isLast,
  });

  final QuickPhrase phrase;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDragProxy = _SettingsQuickPhraseDragAppearance.of(context);
    final corner = Radius.circular(AppRadius.md);
    final rowRadius = BorderRadius.vertical(
      top: isDragProxy || isFirst ? corner : Radius.zero,
      bottom: isDragProxy || isLast ? corner : Radius.zero,
    );

    return AppListGroup(
      borderRadius: rowRadius,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: rowRadius,
            child: Slidable(
              key: ValueKey('slidable-settings-quick-phrase-${phrase.id}'),
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
                        borderRadius: BorderRadius.circular(AppRadius.md),
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
                            Icon(Lucide.Trash2, color: cs.error, size: 18),
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
                    onPressed: (_) => onDelete(),
                  ),
                ],
              ),
              child: AppListTile(
                onTapFeedback: () {
                  if (context.read<SettingsProvider>().hapticsOnListItemTap) {
                    Haptics.soft();
                  }
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                onTap: onTap,
                leading: Icon(Lucide.Zap, size: 18, color: cs.primary),
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
                  size: 18,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                minLeadingWidth: 18,
                horizontalTitleGap: 8,
                minVerticalPadding: 14,
              ),
            ),
          ),
          if (!isDragProxy && !isLast)
            const AppListDivider.forTile(
              hasLeading: true,
              horizontalPadding: 14,
              minLeadingWidth: 18,
              horizontalTitleGap: 8,
              leadingWidth: 18,
              trailingPadding: 14,
            ),
        ],
      ),
    );
  }
}

class _SettingsQuickPhraseDragAppearance extends InheritedWidget {
  const _SettingsQuickPhraseDragAppearance({required super.child});

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<
            _SettingsQuickPhraseDragAppearance
          >() !=
      null;

  @override
  bool updateShouldNotify(_SettingsQuickPhraseDragAppearance oldWidget) =>
      false;
}

class _SettingsQuickPhraseDragProxy extends StatefulWidget {
  const _SettingsQuickPhraseDragProxy({
    required this.animation,
    required this.onLanded,
    required this.child,
  });

  final Animation<double> animation;
  final VoidCallback onLanded;
  final Widget child;

  @override
  State<_SettingsQuickPhraseDragProxy> createState() =>
      _SettingsQuickPhraseDragProxyState();
}

class _SettingsQuickPhraseDragProxyState
    extends State<_SettingsQuickPhraseDragProxy> {
  @override
  void dispose() {
    final onLanded = widget.onLanded;
    WidgetsBinding.instance.addPostFrameCallback((_) => onLanded());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.animation,
    builder: (context, child) => Transform.scale(
      scale: 0.98 + 0.02 * Curves.easeOutBack.transform(widget.animation.value),
      child: child,
    ),
    child: Material(
      elevation: 0,
      shadowColor: Colors.transparent,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: _SettingsQuickPhraseDragAppearance(child: widget.child),
    ),
  );
}

class _QuickPhraseEditSheet extends StatefulWidget {
  const _QuickPhraseEditSheet({
    super.key,
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

  void _submit() {
    Navigator.of(
      context,
    ).pop({'title': _titleController.text, 'content': _contentController.text});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: ValueKey(PopupContentSurfaceScope.isDialogOf(context)),
        primary: !PopupContentSurfaceScope.isDialogOf(context),
        padding: PopupContentFrame.scrollPadding(
          context,
          EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
        ),
        child: Column(
          children: [
            AppListGroup.list(
              children: [
                AppListTile(
                  leading: const Icon(Icons.title_rounded, size: 20),
                  title: AppTextField(
                    controller: _titleController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.quickPhraseTitleLabel,
                      border: InputBorder.none,
                    ),
                  ),
                  minVerticalPadding: 8,
                  minLeadingWidth: 24,
                  horizontalTitleGap: 12,
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppListGroup.list(
              children: [
                AppListTile(
                  title: AppTextField(
                    controller: _contentController,
                    minLines: 5,
                    maxLines: null,
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l10n.quickPhraseContentLabel,
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  minVerticalPadding: 12,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
