import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:Kelivo/shared/widgets/popup_content_frame.dart';

import 'package:flutter/material.dart';
import '../../../shared/layouts/app_scaffold.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/assistant_regex.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_switch.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/design_tokens.dart';

class AssistantRegexTab extends StatefulWidget {
  const AssistantRegexTab({super.key, required this.assistantId});
  final String assistantId;

  @override
  State<AssistantRegexTab> createState() => _AssistantRegexTabState();
}

class _AssistantRegexTabState extends State<AssistantRegexTab> {
  String? _draggedRuleId;

  void _finishDragging(String id) {
    if (!mounted || _draggedRuleId != id) return;
    setState(() => _draggedRuleId = null);
  }

  void _reorder(int oldIndex, int newIndex) {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    ap.reorderAssistantRegex(
      assistantId: widget.assistantId,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  Future<void> _addOrEdit({AssistantRegex? rule}) async {
    await addOrEditAssistantRegexRule(context, widget.assistantId, rule: rule);
  }

  Future<void> _setRuleEnabled(AssistantRegex rule, bool enabled) async {
    await _setAssistantRegexRuleEnabled(
      context,
      widget.assistantId,
      rule.id,
      enabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final assistant = context.watch<AssistantProvider>().getById(
      widget.assistantId,
    );
    if (assistant == null) return const SizedBox.shrink();
    final rules = assistant.regexRules;
    final restingRules = rules
        .where((rule) => rule.id != _draggedRuleId)
        .toList();

    if (rules.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Lucide.Wand2,
              size: 64,
              color: cs.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.assistantEditRegexDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        AppScaffold.scrollContentTop(context),
        16,
        AppScaffold.scrollContentBottom(context),
      ),
      itemCount: rules.length,
      buildDefaultDragHandles: false,
      onReorderStart: (index) {
        setState(() => _draggedRuleId = rules[index].id);
      },
      proxyDecorator: (child, index, animation) => _RegexDragProxy(
        animation: animation,
        onLanded: () => _finishDragging(rules[index].id),
        child: child,
      ),
      onReorderItem: (oldIndex, newIndex) {
        _reorder(oldIndex, newIndex);
        final draggedId = _draggedRuleId;
        if (draggedId != null) _finishDragging(draggedId);
      },
      itemBuilder: (context, index) {
        final rule = rules[index];
        return KeyedSubtree(
          key: ValueKey('assistant-regex-${rule.id}'),
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: _RegexRuleCard(
              rule: rule,
              onTap: () => _addOrEdit(rule: rule),
              onToggleEnabled: (enabled) => _setRuleEnabled(rule, enabled),
              desktop: false,
              isFirst:
                  restingRules.isNotEmpty && rule.id == restingRules.first.id,
              isLast:
                  restingRules.isNotEmpty && rule.id == restingRules.last.id,
            ),
          ),
        );
      },
    );
  }
}

class AssistantRegexDesktopPane extends StatefulWidget {
  const AssistantRegexDesktopPane({super.key, required this.assistantId});
  final String assistantId;

  @override
  State<AssistantRegexDesktopPane> createState() =>
      _AssistantRegexDesktopPaneState();
}

class _AssistantRegexDesktopPaneState extends State<AssistantRegexDesktopPane> {
  void _reorder(int oldIndex, int newIndex) {
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    ap.reorderAssistantRegex(
      assistantId: widget.assistantId,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  Future<void> _addOrEdit({AssistantRegex? rule}) async {
    await addOrEditAssistantRegexRule(context, widget.assistantId, rule: rule);
  }

  Future<void> _setRuleEnabled(AssistantRegex rule, bool enabled) async {
    await _setAssistantRegexRuleEnabled(
      context,
      widget.assistantId,
      rule.id,
      enabled,
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
    if (assistant == null) return const SizedBox.shrink();
    final rules = assistant.regexRules;

    return Container(
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.assistantEditPageRegexTab,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: AppFontWeights.emphasis,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.assistantEditRegexDescription,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                IosCardPress(
                  onTap: () => _addOrEdit(),
                  borderRadius: BorderRadius.circular(12),
                  baseColor: isDark
                      ? Colors.white10
                      : cs.primary.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  pressedBlendStrength: 0.18,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Plus, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        l10n.assistantEditAddRegexButton,
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: AppFontWeights.emphasis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rules.isEmpty
                ? Center(
                    child: Text(
                      l10n.assistantEditRegexDescription,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: rules.length,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) {
                          final t = Curves.easeOut.transform(animation.value);
                          return Transform.scale(
                            scale: 0.985 + 0.015 * t,
                            child: child,
                          );
                        },
                      );
                    },
                    onReorderItem: _reorder,
                    itemBuilder: (context, index) {
                      final rule = rules[index];
                      return KeyedSubtree(
                        key: ValueKey('assistant-regex-desktop-${rule.id}'),
                        child: ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RegexRuleCard(
                              rule: rule,
                              onTap: () => _addOrEdit(rule: rule),
                              onToggleEnabled: (enabled) =>
                                  _setRuleEnabled(rule, enabled),
                              desktop: true,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RegexRuleCard extends StatefulWidget {
  const _RegexRuleCard({
    required this.rule,
    required this.onTap,
    required this.onToggleEnabled,
    required this.desktop,
    this.isFirst = false,
    this.isLast = false,
  });

  final AssistantRegex rule;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleEnabled;
  final bool desktop;
  final bool isFirst;
  final bool isLast;

  @override
  State<_RegexRuleCard> createState() => _RegexRuleCardState();
}

class _RegexRuleCardState extends State<_RegexRuleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final outlineColor = widget.desktop && _hovered
        ? cs.primary.withValues(alpha: 0.55)
        : null;
    final isDragProxy = !widget.desktop && _RegexDragAppearance.of(context);
    final corner = Radius.circular(AppRadius.md);
    final rowRadius = widget.desktop
        ? BorderRadius.all(corner)
        : BorderRadius.vertical(
            top: isDragProxy || widget.isFirst ? corner : Radius.zero,
            bottom: isDragProxy || widget.isLast ? corner : Radius.zero,
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AppListGroup(
        borderRadius: rowRadius,
        outlineColor: outlineColor,
        outlineWidth: 0.7,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: rowRadius,
              child: AppListTile(
                borderRadius: rowRadius,
                onTap: widget.onTap,
                title: Text(
                  widget.rule.name.isEmpty
                      ? l10n.assistantRegexUntitled
                      : widget.rule.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                subtitle: Text(
                  _regexRuleSubtitle(l10n, widget.rule),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: AppSwitch(
                  value: widget.rule.enabled,
                  semanticLabel:
                      '${widget.rule.name.isEmpty ? l10n.assistantRegexUntitled : widget.rule.name} · ${l10n.assistantRegexEnabledLabel}',
                  onChanged: widget.onToggleEnabled,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                minVerticalPadding: 14,
              ),
            ),
            if (!widget.desktop && !isDragProxy && !widget.isLast)
              const AppListDivider.forTile(
                hasLeading: false,
                horizontalPadding: 14,
                trailingPadding: 14,
              ),
          ],
        ),
      ),
    );
  }
}

String _regexRuleSubtitle(AppLocalizations l10n, AssistantRegex rule) {
  final details = <String>[
    if (rule.scopes.contains(AssistantRegexScope.user))
      l10n.assistantRegexScopeUser,
    if (rule.scopes.contains(AssistantRegexScope.assistant))
      l10n.assistantRegexScopeAssistant,
    if (rule.visualOnly) l10n.assistantRegexScopeVisualOnly,
    if (rule.replaceOnly) l10n.assistantRegexScopeReplaceOnly,
  ];
  return details.join(' · ');
}

class _RegexDragAppearance extends InheritedWidget {
  const _RegexDragAppearance({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RegexDragAppearance>() !=
      null;

  @override
  bool updateShouldNotify(_RegexDragAppearance oldWidget) => false;
}

class _RegexDragProxy extends StatefulWidget {
  const _RegexDragProxy({
    required this.animation,
    required this.onLanded,
    required this.child,
  });

  final Animation<double> animation;
  final VoidCallback onLanded;
  final Widget child;

  @override
  State<_RegexDragProxy> createState() => _RegexDragProxyState();
}

class _RegexDragProxyState extends State<_RegexDragProxy> {
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
      child: _RegexDragAppearance(child: widget.child),
    ),
  );
}

class _RegexFormData {
  const _RegexFormData({
    required this.name,
    required this.pattern,
    required this.replacement,
    required this.scopes,
    required this.enabled,
    required this.visualOnly,
    required this.replaceOnly,
  }) : deleteRequested = false;

  const _RegexFormData.delete()
    : name = '',
      pattern = '',
      replacement = '',
      scopes = const [],
      enabled = false,
      visualOnly = false,
      replaceOnly = false,
      deleteRequested = true;

  final String name;
  final String pattern;
  final String replacement;
  final List<AssistantRegexScope> scopes;
  final bool enabled;
  final bool visualOnly;
  final bool replaceOnly;
  final bool deleteRequested;
}

List<AssistantRegexScope> _normalizeRegexScopes(
  Iterable<AssistantRegexScope> scopes,
) {
  final set = {...scopes};
  return AssistantRegexScope.values
      .where((scope) => set.contains(scope))
      .toList(growable: false);
}

Future<void> _setAssistantRegexRuleEnabled(
  BuildContext context,
  String assistantId,
  String ruleId,
  bool enabled,
) async {
  final provider = context.read<AssistantProvider>();
  final assistant = provider.getById(assistantId);
  if (assistant == null) return;

  final rules = List<AssistantRegex>.of(assistant.regexRules);
  final index = rules.indexWhere((rule) => rule.id == ruleId);
  if (index < 0 || rules[index].enabled == enabled) return;
  rules[index] = rules[index].copyWith(enabled: enabled);
  await provider.updateAssistant(assistant.copyWith(regexRules: rules));
}

Future<void> addOrEditAssistantRegexRule(
  BuildContext context,
  String assistantId, {
  AssistantRegex? rule,
}) async {
  final ap = context.read<AssistantProvider>();
  final data = await _showRegexEditor(context, rule: rule);
  if (!context.mounted || data == null) return;
  final assistant = ap.getById(assistantId);
  if (assistant == null) return;

  final rules = List<AssistantRegex>.of(assistant.regexRules);
  if (data.deleteRequested) {
    if (rule == null) return;
    rules.removeWhere((candidate) => candidate.id == rule.id);
    await ap.updateAssistant(assistant.copyWith(regexRules: rules));
    return;
  }

  final updated = AssistantRegex(
    id: rule?.id ?? const Uuid().v4(),
    name: data.name,
    pattern: data.pattern,
    replacement: data.replacement,
    scopes: _normalizeRegexScopes(data.scopes),
    visualOnly: data.visualOnly,
    replaceOnly: data.replaceOnly,
    enabled: data.enabled,
  );
  if (rule == null) {
    rules.add(updated);
  } else {
    final index = rules.indexWhere((candidate) => candidate.id == rule.id);
    if (index == -1) {
      rules.add(updated);
    } else {
      rules[index] = updated;
    }
  }
  await ap.updateAssistant(assistant.copyWith(regexRules: rules));
}

Future<_RegexFormData?> _showRegexEditor(
  BuildContext context, {
  AssistantRegex? rule,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final formKey = GlobalKey<_RegexEditSheetState>();
  return showAppPopupSheet<_RegexFormData>(
    context: context,
    title: rule == null
        ? l10n.assistantRegexAddTitle
        : l10n.assistantRegexEditTitle,
    actions: [
      appPopupDoneAction(
        semanticLabel: rule == null
            ? l10n.assistantRegexAddAction
            : l10n.assistantRegexSaveAction,
        onTap: () => formKey.currentState?._submit(),
      ),
    ],
    isScrollControlled: true,
    extendBodyBehindHeader: true,
    builder: (_) => _RegexEditSheet(key: formKey, rule: rule),
  );
}

class _RegexEditSheet extends StatefulWidget {
  const _RegexEditSheet({super.key, this.rule});

  final AssistantRegex? rule;

  @override
  State<_RegexEditSheet> createState() => _RegexEditSheetState();
}

class _RegexEditSheetState extends State<_RegexEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _patternController;
  late final TextEditingController _replacementController;
  late final Set<AssistantRegexScope> _scopes;
  late bool _enabled;
  late bool _visualOnly;
  late bool _replaceOnly;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.rule?.name ?? '');
    _patternController = TextEditingController(
      text: widget.rule?.pattern ?? '',
    );
    _replacementController = TextEditingController(
      text: widget.rule?.replacement ?? '',
    );
    _scopes = {
      ...(widget.rule?.scopes ??
          <AssistantRegexScope>[AssistantRegexScope.user]),
    };
    _enabled = widget.rule?.enabled ?? true;
    _visualOnly = widget.rule?.visualOnly ?? false;
    _replaceOnly = widget.rule?.replaceOnly ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _patternController.dispose();
    _replacementController.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameController.text.trim();
    final pattern = _patternController.text.trim();
    if (name.isEmpty || pattern.isEmpty || _scopes.isEmpty) {
      showAppSnackBar(
        context,
        message: l10n.assistantRegexValidationError,
        type: NotificationType.warning,
      );
      return;
    }
    try {
      RegExp(pattern);
    } catch (_) {
      showAppSnackBar(
        context,
        message: l10n.assistantRegexInvalidPattern,
        type: NotificationType.warning,
      );
      return;
    }
    Navigator.of(context).pop(
      _RegexFormData(
        name: name,
        pattern: pattern,
        replacement: _replacementController.text,
        scopes: _scopes.toList(),
        enabled: _enabled,
        visualOnly: _visualOnly,
        replaceOnly: _replaceOnly,
      ),
    );
  }

  void _delete() {
    if (widget.rule == null) return;
    Navigator.of(context).pop(const _RegexFormData.delete());
  }

  void _setScope(AssistantRegexScope scope, bool selected) {
    setState(() {
      if (selected) {
        _scopes.add(scope);
      } else {
        _scopes.remove(scope);
      }
    });
  }

  void _setVisualOnly(bool selected) {
    setState(() {
      _visualOnly = selected;
      if (selected) _replaceOnly = false;
    });
  }

  void _setReplaceOnly(bool selected) {
    setState(() {
      _replaceOnly = selected;
      if (selected) _visualOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
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
                  controller: _nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.assistantRegexNameLabel,
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
                  controller: _patternController,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    labelText: l10n.assistantRegexPatternLabel,
                    border: InputBorder.none,
                  ),
                ),
                minVerticalPadding: 12,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppListGroup.list(
            children: [
              AppListTile(
                title: AppTextField(
                  controller: _replacementController,
                  minLines: 4,
                  maxLines: null,
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: l10n.assistantRegexReplacementLabel,
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
          const SizedBox(height: 16),
          AppListGroupHeader(title: l10n.assistantRegexSettingsTitle),
          AppListGroup.list(
            children: [
              AppListTile(
                onTap: () => setState(() => _enabled = !_enabled),
                title: Text(l10n.assistantRegexEnabledLabel),
                trailing: AppSwitch(
                  value: _enabled,
                  semanticLabel: l10n.assistantRegexEnabledLabel,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
                minVerticalPadding: 8,
              ),
              const AppListDivider(),
              AppListTile(
                onTap: () => _setScope(
                  AssistantRegexScope.user,
                  !_scopes.contains(AssistantRegexScope.user),
                ),
                title: Text(l10n.assistantRegexScopeUser),
                trailing: AppSwitch(
                  value: _scopes.contains(AssistantRegexScope.user),
                  semanticLabel: l10n.assistantRegexScopeUser,
                  onChanged: (value) =>
                      _setScope(AssistantRegexScope.user, value),
                ),
                minVerticalPadding: 8,
              ),
              const AppListDivider(),
              AppListTile(
                onTap: () => _setScope(
                  AssistantRegexScope.assistant,
                  !_scopes.contains(AssistantRegexScope.assistant),
                ),
                title: Text(l10n.assistantRegexScopeAssistant),
                trailing: AppSwitch(
                  value: _scopes.contains(AssistantRegexScope.assistant),
                  semanticLabel: l10n.assistantRegexScopeAssistant,
                  onChanged: (value) =>
                      _setScope(AssistantRegexScope.assistant, value),
                ),
                minVerticalPadding: 8,
              ),
              const AppListDivider(),
              AppListTile(
                onTap: () => _setVisualOnly(!_visualOnly),
                title: Text(l10n.assistantRegexScopeVisualOnly),
                trailing: AppSwitch(
                  value: _visualOnly,
                  semanticLabel: l10n.assistantRegexScopeVisualOnly,
                  onChanged: _setVisualOnly,
                ),
                minVerticalPadding: 8,
              ),
              const AppListDivider(),
              AppListTile(
                onTap: () => _setReplaceOnly(!_replaceOnly),
                title: Text(l10n.assistantRegexScopeReplaceOnly),
                trailing: AppSwitch(
                  value: _replaceOnly,
                  semanticLabel: l10n.assistantRegexScopeReplaceOnly,
                  onChanged: _setReplaceOnly,
                ),
                minVerticalPadding: 8,
              ),
            ],
          ),
          if (widget.rule != null) ...[
            const SizedBox(height: 16),
            AppListGroup.list(
              children: [
                AppListTile(
                  onTap: _delete,
                  leading: Icon(
                    Lucide.Trash2,
                    size: 18,
                    color: AppColors.destructiveRed,
                  ),
                  title: Text(
                    l10n.assistantRegexDeleteButton,
                    style: const TextStyle(color: AppColors.destructiveRed),
                  ),
                  minVerticalPadding: 12,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
