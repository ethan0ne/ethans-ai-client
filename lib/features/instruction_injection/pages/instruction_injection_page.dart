import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:Kelivo/shared/widgets/popup_content_frame.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/instruction_injection.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/instruction_injection_group_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../assistant/utils/assistant_prompt_asset_sync.dart';

class InstructionInjectionPage extends StatefulWidget {
  const InstructionInjectionPage({
    super.key,
    required this.assistantId,
    this.embedded = false,
  });

  final String assistantId;
  final bool embedded;

  @override
  State<InstructionInjectionPage> createState() =>
      _InstructionInjectionPageState();
}

class _InstructionInjectionPageState extends State<InstructionInjectionPage> {
  static const List<String> _textExtensions = <String>[
    'txt',
    'json',
    'yaml',
    'yml',
    'lua',
    'md',
    'log',
    'ini',
    'conf',
    'cfg',
    'csv',
    'py',
    'js',
    'ts',
    'toml',
    'xml',
    'sql',
    'sh',
  ];

  Future<void> _saveItems(List<InstructionInjection> items) async {
    final assistant = context.read<AssistantProvider>().getById(
      widget.assistantId,
    );
    if (assistant == null) return;
    await saveAssistantPromptAssets(
      context,
      assistant.copyWith(instructionInjections: items),
    );
  }

  Future<void> _showAddEditSheet({InstructionInjection? item}) async {
    final cs = Theme.of(context).colorScheme;
    final editorKey = GlobalKey<_InstructionInjectionEditSheetState>();

    final result = await showAppPopupSheet<Map<String, String>?>(
      context: context,
      title: item == null
          ? AppLocalizations.of(context)!.instructionInjectionAddTitle
          : AppLocalizations.of(context)!.instructionInjectionEditTitle,
      actions: [
        appPopupDoneAction(
          semanticLabel: AppLocalizations.of(context)!.quickPhraseSaveButton,
          onTap: () => editorKey.currentState?._submit(),
        ),
      ],
      isScrollControlled: true,
      extendBodyBehindHeader: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return InstructionInjectionEditSheet(key: editorKey, item: item);
      },
    );

    if (!mounted) return;
    if (result == null) return;

    final title = result['title']?.trim() ?? '';
    final prompt = result['prompt']?.trim() ?? '';
    final group = result['group']?.trim() ?? '';
    if (title.isEmpty || prompt.isEmpty) return;

    final assistant = context.read<AssistantProvider>().getById(
      widget.assistantId,
    );
    if (assistant == null) return;
    final items = [...assistant.instructionInjections];
    if (item == null) {
      items.add(
        InstructionInjection(
          id: const Uuid().v4(),
          title: title,
          prompt: prompt,
          group: group,
        ),
      );
    } else {
      final index = items.indexWhere((candidate) => candidate.id == item.id);
      if (index < 0) return;
      items[index] = item.copyWith(title: title, prompt: prompt, group: group);
    }
    await _saveItems(items);
  }

  Future<void> _deleteItem(InstructionInjection item) async {
    final assistant = context.read<AssistantProvider>().getById(
      widget.assistantId,
    );
    if (assistant == null) return;
    await saveAssistantPromptAssets(
      context,
      assistant.copyWith(
        instructionInjections: assistant.instructionInjections
            .where((candidate) => candidate.id != item.id)
            .toList(),
        activeInstructionInjectionIds: assistant.activeInstructionInjectionIds
            .where((id) => id != item.id)
            .toList(),
      ),
    );
  }

  Future<void> _reorderWithinGroup(
    String group,
    int oldIndex,
    int newIndex,
  ) async {
    final assistant = context.read<AssistantProvider>().getById(
      widget.assistantId,
    );
    if (assistant == null) return;
    final items = [...assistant.instructionInjections];
    final matching = <int>[];
    for (var i = 0; i < items.length; i++) {
      if (items[i].group.trim() == group.trim()) matching.add(i);
    }
    if (oldIndex < 0 || oldIndex >= matching.length) return;
    final removed = items.removeAt(matching[oldIndex]);
    final after = <int>[];
    for (var i = 0; i < items.length; i++) {
      if (items[i].group.trim() == group.trim()) after.add(i);
    }
    final insertionIndex = newIndex >= after.length
        ? (after.isEmpty ? items.length : after.last + 1)
        : after[newIndex];
    items.insert(insertionIndex, removed);
    await _saveItems(items);
  }

  Future<String?> _readPickedFileAsString(PlatformFile file) async {
    try {
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        return utf8.decode(file.bytes!, allowMalformed: true);
      }
    } catch (_) {}
    final path = file.path;
    if (path == null || path.isEmpty) return null;
    try {
      return await File(path).readAsString();
    } catch (_) {
      try {
        final bytes = await File(path).readAsBytes();
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _importFromFiles() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: _textExtensions,
        withData: true,
      );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final List<InstructionInjection> imports = [];

    for (final file in result.files) {
      final name = file.name.trim();
      final ext = (file.extension ?? '').toLowerCase();
      if (!_textExtensions.contains(ext)) continue;
      final content = await _readPickedFileAsString(file);
      final prompt = content ?? '';
      if (name.isEmpty || prompt.trim().isEmpty) continue;
      imports.add(
        InstructionInjection(
          id: const Uuid().v4(),
          title: name,
          prompt: prompt,
        ),
      );
    }

    if (!mounted) return;
    if (imports.isNotEmpty) {
      final assistant = context.read<AssistantProvider>().getById(
        widget.assistantId,
      );
      if (assistant != null) {
        await _saveItems([...assistant.instructionInjections, ...imports]);
      }
    }
    if (!mounted) return;

    showAppSnackBar(
      context,
      message: l10n.instructionInjectionImportSuccess(imports.length),
      type: imports.isEmpty
          ? NotificationType.warning
          : NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final assistant = context.watch<AssistantProvider>().getById(
      widget.assistantId,
    );
    final groupUi = context.watch<InstructionInjectionGroupProvider>();
    final items =
        assistant?.instructionInjections ?? const <InstructionInjection>[];

    final Map<String, List<InstructionInjection>> grouped =
        <String, List<InstructionInjection>>{};
    for (final item in items) {
      final g = item.group.trim();
      (grouped[g] ??= <InstructionInjection>[]).add(item);
    }
    final groupNames = grouped.keys.toList()
      ..sort((a, b) {
        final aa = a.trim();
        final bb = b.trim();
        if (aa.isEmpty && bb.isNotEmpty) return -1;
        if (aa.isNotEmpty && bb.isEmpty) return 1;
        return aa.toLowerCase().compareTo(bb.toLowerCase());
      });

    final inPage = AppScaffold.scrollPadding(context, EdgeInsets.zero).top > 0;
    final embeddedActions = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Tooltip(
            message: l10n.instructionInjectionImportTooltip,
            child: _TactileIconButton(
              icon: Lucide.Import,
              color: cs.onSurface,
              size: 22,
              onTap: _importFromFiles,
            ),
          ),
          Tooltip(
            message: l10n.instructionInjectionAddTooltip,
            child: _TactileIconButton(
              icon: Lucide.Plus,
              color: cs.onSurface,
              size: 22,
              onTap: () => _showAddEditSheet(),
            ),
          ),
        ],
      ),
    );
    final body = items.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Lucide.Layers,
                  size: 64,
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.embedded
                      ? l10n.assistantEditInstructionInjectionEmptyDescription
                      : l10n.instructionInjectionEmptyMessage,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )
        : ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              widget.embedded
                  ? AppScaffold.scrollPadding(
                      context,
                      const EdgeInsets.all(16),
                    ).top
                  : AppScaffold.scrollContentTop(context),
              16,
              AppScaffold.scrollContentBottom(context),
            ),
            children: [
              if (widget.embedded && inPage) embeddedActions,
              for (final groupName in groupNames) ...[
                _GroupHeader(
                  title: groupName.trim().isEmpty
                      ? l10n.instructionInjectionUngroupedGroup
                      : groupName.trim(),
                  collapsed: groupUi.isCollapsed(groupName),
                  onToggle: () => context
                      .read<InstructionInjectionGroupProvider>()
                      .toggleCollapsed(groupName),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: groupUi.isCollapsed(groupName)
                      ? const SizedBox.shrink()
                      : ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: grouped[groupName]?.length ?? 0,
                          buildDefaultDragHandles: false,
                          proxyDecorator: (child, index, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (context, _) {
                                final t = Curves.easeOut.transform(
                                  animation.value,
                                );
                                return Transform.scale(
                                  scale: 0.98 + 0.02 * t,
                                  child: child,
                                );
                              },
                            );
                          },
                          onReorderItem: (oldIndex, newIndex) {
                            _reorderWithinGroup(groupName, oldIndex, newIndex);
                          },
                          itemBuilder: (context, index) {
                            final item = grouped[groupName]![index];
                            final displayTitle = item.title.trim().isEmpty
                                ? l10n.instructionInjectionDefaultTitle
                                : item.title;
                            return KeyedSubtree(
                              key: ValueKey(
                                'reorder-instruction-injection-${item.id}',
                              ),
                              child: ReorderableDelayedDragStartListener(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Slidable(
                                    key: ValueKey(item.id),
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
                                                  ? cs.error.withValues(
                                                      alpha: 0.22,
                                                    )
                                                  : cs.error.withValues(
                                                      alpha: 0.14,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: cs.error.withValues(
                                                  alpha: 0.35,
                                                ),
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
                                                      fontWeight: AppFontWeights
                                                          .emphasis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          onPressed: (_) => _deleteItem(item),
                                        ),
                                      ],
                                    ),
                                    child: AppListGroup(
                                      child: AppListTile(
                                        onTapFeedback: Haptics.soft,
                                        onTap: () =>
                                            _showAddEditSheet(item: item),
                                        leading: Icon(
                                          Lucide.Layers,
                                          size: 18,
                                          color: cs.primary,
                                        ),
                                        title: Text(
                                          displayTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        subtitle: Text(
                                          item.prompt,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.7,
                                            ),
                                          ),
                                        ),
                                        trailing: Icon(
                                          Lucide.ChevronRight,
                                          size: 16,
                                          color: cs.onSurface.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
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
                ),
              ],
            ],
          );

    if (!widget.embedded) {
      return AppScaffold(
        leadingIslands: [
          [
            AppButtonIslandButton(
              icon: Lucide.ArrowLeft,
              semanticLabel: l10n.instructionInjectionBackTooltip,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ],
        title: AppScaffoldTitle(l10n.instructionInjectionTitle),
        actions: [
          AppButtonIslandButton(
            icon: Lucide.Import,
            semanticLabel: l10n.instructionInjectionImportTooltip,
            onTap: _importFromFiles,
          ),
          AppButtonIslandButton(
            icon: Lucide.Plus,
            semanticLabel: l10n.instructionInjectionAddTooltip,
            onTap: () => _showAddEditSheet(),
          ),
        ],
        body: body,
      );
    }
    if (inPage) {
      if (items.isNotEmpty) return body;
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: AppScaffold.scrollPadding(
              context,
              const EdgeInsets.all(16),
            ),
            sliver: SliverToBoxAdapter(child: embeddedActions),
          ),
          SliverFillRemaining(hasScrollBody: false, child: body),
        ],
      );
    }
    return Column(
      children: [
        embeddedActions,
        Expanded(child: body),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.collapsed,
    required this.onToggle,
  });

  final String title;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: AppListGroupHeader(
        title: title,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: SizedBox(
          width: 18,
          height: 18,
          child: Center(
            child: AnimatedRotation(
              turns: collapsed ? 0.0 : 0.25,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: Icon(
                Lucide.ChevronRight,
                size: 16,
                color: textBase.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InstructionInjectionEditSheet extends StatefulWidget {
  const InstructionInjectionEditSheet({super.key, required this.item});

  final InstructionInjection? item;

  @override
  State<InstructionInjectionEditSheet> createState() =>
      _InstructionInjectionEditSheetState();
}

class _InstructionInjectionEditSheetState
    extends State<InstructionInjectionEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _groupController;
  late final TextEditingController _promptController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item?.title ?? '');
    _groupController = TextEditingController(text: widget.item?.group ?? '');
    _promptController = TextEditingController(text: widget.item?.prompt ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _groupController.dispose();
    _promptController.dispose();
    super.dispose();
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
            MediaQuery.of(context).viewInsets.bottom + 16,
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
                      labelText: l10n.instructionInjectionNameLabel,
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
                  leading: const Icon(Icons.folder_outlined, size: 20),
                  title: AppTextField(
                    controller: _groupController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.instructionInjectionGroupLabel,
                      hintText: l10n.instructionInjectionGroupHint,
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
                    controller: _promptController,
                    minLines: 5,
                    maxLines: null,
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l10n.instructionInjectionNoteHint,
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

  void _submit() {
    Navigator.of(context).pop({
      'title': _titleController.text,
      'group': _groupController.text,
      'prompt': _promptController.text,
    });
  }
}

class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final press = base.withValues(alpha: 0.7);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          widget.icon,
          size: widget.size,
          color: _pressed ? press : base,
        ),
      ),
    );
  }
}
