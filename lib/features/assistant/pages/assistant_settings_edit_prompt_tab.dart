part of 'assistant_settings_edit_page.dart';

class _PromptTab extends StatefulWidget {
  const _PromptTab({required this.assistantId});
  final String assistantId;

  @override
  State<_PromptTab> createState() => _PromptTabState();
}

class _PromptTabState extends State<_PromptTab> {
  late final TextEditingController _sysCtrl;
  late final TextEditingController _tmplCtrl;
  bool _showTemplatePreview = false;

  @override
  void initState() {
    super.initState();
    final ap = context.read<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;
    _sysCtrl = TextEditingController(text: a.systemPrompt);
    _tmplCtrl = TextEditingController(text: a.messageTemplate);
  }

  @override
  void didUpdateWidget(covariant _PromptTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assistantId != widget.assistantId) {
      final ap = context.read<AssistantProvider>();
      final a = ap.getById(widget.assistantId)!;
      _sysCtrl.text = a.systemPrompt;
      _tmplCtrl.text = a.messageTemplate;
      _showTemplatePreview = false;
    }
  }

  @override
  void dispose() {
    _sysCtrl.dispose();
    _tmplCtrl.dispose();
    super.dispose();
  }

  Future<void> _importSystemPrompt() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const [
          'txt',
          'md',
          'json',
          'js',
          'html',
          'xml',
          'py',
          'java',
          'kt',
          'dart',
          'ts',
          'tsx',
          'markdown',
          'mdx',
          'yml',
          'yaml',
        ],
      );
      if (res == null || res.files.isEmpty) return;
      final picked = res.files.first;
      String? content;
      if (picked.bytes != null && picked.bytes!.isNotEmpty) {
        content = utf8.decode(picked.bytes!, allowMalformed: true);
      } else if (!kIsWeb && picked.path != null && picked.path!.isNotEmpty) {
        content = await File(picked.path!).readAsString();
      }
      if (!mounted) return;
      if (content == null || content.trim().isEmpty) {
        showAppSnackBar(
          context,
          message: l10n.assistantEditSystemPromptImportEmpty,
          type: NotificationType.error,
        );
        return;
      }
      _sysCtrl.text = content;
      _sysCtrl.selection = TextSelection.collapsed(
        offset: _sysCtrl.text.length,
      );
      final ap = context.read<AssistantProvider>();
      final a = ap.getById(widget.assistantId);
      if (a != null) {
        await ap.updateAssistant(a.copyWith(systemPrompt: _sysCtrl.text));
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.assistantEditSystemPromptImportSuccess,
        type: NotificationType.success,
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.assistantEditSystemPromptImportFailed,
        type: NotificationType.error,
      );
    }
  }

  Future<void> _applySystemPromptChange(String value) async {
    final ap = context.read<AssistantProvider>();
    final a = ap.getById(widget.assistantId);
    if (a == null) return;
    _sysCtrl.text = value;
    _sysCtrl.selection = TextSelection.collapsed(offset: _sysCtrl.text.length);
    await ap.updateAssistant(a.copyWith(systemPrompt: value));
    if (mounted) setState(() {});
  }

  Future<String?> _showPromptMobileSheet({
    required String title,
    required String initial,
    required String hint,
    required List<_PromptVariableGroup> variableGroups,
  }) {
    final editorKey = GlobalKey<_PromptTextMobileSheetState>();
    return showAppPopupSheet<String>(
      context: context,
      title: title,
      actions: [
        appPopupDoneAction(
          semanticLabel: AppLocalizations.of(
            context,
          )!.assistantEditEmojiDialogSave,
          onTap: () => editorKey.currentState?._submit(),
        ),
      ],
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _PromptTextMobileSheet(
        key: editorKey,
        initial: initial,
        hint: hint,
        variableGroups: variableGroups,
      ),
    );
  }

  Future<String?> _showPromptDesktopDialog({
    required String title,
    required String initial,
    required String hint,
    required List<_PromptVariableGroup> variableGroups,
  }) {
    return showAppDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'assistant-prompt-editor',
      builder: (_) {
        return _PromptTextDesktopDialog(
          title: title,
          initial: initial,
          hint: hint,
          variableGroups: variableGroups,
        );
      },
    );
  }

  List<_PromptVariableGroup> _systemPromptVariableGroups(
    AppLocalizations l10n,
  ) => [
    _PromptVariableGroup(
      title: l10n.assistantEditPromptVariableGroupDevice,
      items: [
        (l10n.assistantEditVariableDate, '{cur_date}'),
        (l10n.assistantEditVariableTime, '{cur_time}'),
        (l10n.assistantEditVariableDatetime, '{cur_datetime}'),
        (l10n.assistantEditVariableLocale, '{locale}'),
        (l10n.assistantEditVariableTimezone, '{timezone}'),
        (l10n.assistantEditVariableSystemVersion, '{system_version}'),
        (l10n.assistantEditVariableDeviceInfo, '{device_info}'),
        (l10n.assistantEditVariableBatteryLevel, '{battery_level}'),
      ],
    ),
    _PromptVariableGroup(
      title: l10n.assistantEditPromptVariableGroupModel,
      items: [
        (l10n.assistantEditVariableModelId, '{model_id}'),
        (l10n.assistantEditVariableModelName, '{model_name}'),
      ],
    ),
    _PromptVariableGroup(
      title: l10n.assistantEditPromptVariableGroupIdentity,
      items: [
        (l10n.assistantEditVariableNickname, '{nickname}'),
        (l10n.assistantEditVariableAssistantName, '{assistant_name}'),
      ],
    ),
  ];

  List<_PromptVariableGroup> _templateVariableGroups(AppLocalizations l10n) => [
    _PromptVariableGroup(
      title: l10n.assistantEditPromptVariableGroupMessage,
      items: [
        (l10n.assistantEditVariableRole, '{{ role }}'),
        (l10n.assistantEditVariableMessage, '{{ message }}'),
      ],
    ),
    _PromptVariableGroup(
      title: l10n.assistantEditPromptVariableGroupTime,
      items: [
        (l10n.assistantEditVariableTime, '{{ time }}'),
        (l10n.assistantEditVariableDate, '{{ date }}'),
      ],
    ),
  ];

  Future<void> _openPromptEditor({required bool systemPrompt}) async {
    final l10n = AppLocalizations.of(context)!;
    final platform = Theme.of(context).platform;
    final bool isDesktop =
        kIsWeb ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.windows;
    final controller = systemPrompt ? _sysCtrl : _tmplCtrl;
    final initial = controller.text;
    final title = systemPrompt
        ? l10n.assistantEditSystemPromptTitle
        : l10n.assistantEditMessageTemplateTitle;
    final hint = systemPrompt
        ? l10n.assistantEditSystemPromptHint
        : '{{ message }}';
    final variables = systemPrompt
        ? _systemPromptVariableGroups(l10n)
        : _templateVariableGroups(l10n);
    final String? next = isDesktop
        ? await _showPromptDesktopDialog(
            title: title,
            initial: initial,
            hint: hint,
            variableGroups: variables,
          )
        : await _showPromptMobileSheet(
            title: title,
            initial: initial,
            hint: hint,
            variableGroups: variables,
          );
    if (!mounted || next == null || next == controller.text) return;
    if (systemPrompt) {
      await _applySystemPromptChange(next);
      return;
    }
    final ap = context.read<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId);
    if (assistant == null) return;
    _tmplCtrl.text = next;
    await ap.updateAssistant(assistant.copyWith(messageTemplate: next));
    if (mounted) setState(() {});
  }

  Future<void> _openSystemPromptEditor() =>
      _openPromptEditor(systemPrompt: true);

  Future<void> _openTemplateEditor() => _openPromptEditor(systemPrompt: false);

  Future<void> _createPresetMessage(Assistant assistant, String role) async {
    final l10n = AppLocalizations.of(context)!;
    final editorKey = GlobalKey<_PresetMessageCreatePopupState>();
    final title = role == 'assistant'
        ? l10n.assistantEditPresetAddAssistant
        : l10n.assistantEditPresetAddUser;
    final content = await showAppPopupSheet<String>(
      context: context,
      title: title,
      closeSemanticLabel: l10n.assistantEditEmojiDialogCancel,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.assistantEditEmojiDialogSave,
          onTap: () => editorKey.currentState?._submit(),
        ),
      ],
      isScrollControlled: false,
      extendBodyBehindHeader: true,
      useSafeArea: true,
      builder: (_) => _PresetMessageCreatePopup(key: editorKey, role: role),
    );
    final text = content?.trim();
    if (!mounted || text == null || text.isEmpty) return;
    final provider = context.read<AssistantProvider>();
    final current = provider.getById(assistant.id);
    if (current == null) return;
    final messages = List<PresetMessage>.of(current.presetMessages)
      ..add(PresetMessage(role: role, content: text));
    await provider.updateAssistant(current.copyWith(presetMessages: messages));
  }

  Future<void> _deletePresetMessage(
    Assistant assistant,
    PresetMessage message,
  ) async {
    final provider = context.read<AssistantProvider>();
    final current = provider.getById(assistant.id) ?? assistant;
    final messages = List<PresetMessage>.of(current.presetMessages)
      ..removeWhere((item) => item.id == message.id);
    await provider.updateAssistant(current.copyWith(presetMessages: messages));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ap = context.watch<AssistantProvider>();
    final assistant = ap.getById(widget.assistantId)!;
    final now = DateTime.now();
    final sampleMessage = l10n.assistantEditSampleMessage;
    final template = assistant.messageTemplate;

    String compactText(String value, String emptyLabel) {
      final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      return normalized.isEmpty ? emptyLabel : normalized;
    }

    String applyTemplate(String value) =>
        PromptTransformer.applyMessageTemplate(
          value.trim().isEmpty ? '{{ message }}' : value,
          role: 'user',
          message: sampleMessage,
          now: now,
        );

    Widget templatePreview() {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Text(
                    l10n.assistantEditSampleUser,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: const BorderRadiusDirectional.only(
                      topStart: Radius.circular(16),
                      topEnd: Radius.circular(16),
                      bottomStart: Radius.circular(16),
                      bottomEnd: Radius.circular(4),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Text(
                      applyTemplate(template),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: AppScaffold.scrollPadding(
        context,
        const EdgeInsets.fromLTRB(16, 8, 16, 16),
      ),
      children: [
        AppListGroupHeader(
          title: l10n.assistantEditSystemPromptTitle,
          first: true,
          trailing: AppListGroupHeaderActions(
            children: [
              AppListGroupHeaderAction(
                icon: Lucide.Pencil,
                size: 18,
                semanticLabel: l10n.assistantEditSystemPromptTitle,
                onTap: _openSystemPromptEditor,
              ),
              AppListGroupHeaderAction(
                icon: Icons.file_open,
                size: 19,
                semanticLabel: l10n.assistantEditSystemPromptImportButton,
                onTap: _importSystemPrompt,
              ),
            ],
          ),
        ),
        AppListGroup(
          child: AppListTile(
            title: Text(
              compactText(
                assistant.systemPrompt,
                l10n.assistantEditPromptEmpty,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              l10n.assistantEditPromptCharacterCount(
                assistant.systemPrompt.characters.length,
              ),
            ),
            trailing: const Icon(Lucide.ChevronRight, size: 18),
            minVerticalPadding: 12,
            onTap: _openSystemPromptEditor,
          ),
        ),
        AppListGroupHeader(title: l10n.assistantEditMessageTemplateTitle),
        AppListGroup.list(
          children: [
            AppListTile(
              title: Text(
                compactText(template, l10n.assistantEditMessageTemplateDefault),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: template.trim().isEmpty
                  ? null
                  : Text(
                      l10n.assistantEditPromptCharacterCount(
                        template.characters.length,
                      ),
                    ),
              trailing: const Icon(Lucide.Pencil, size: 18),
              minVerticalPadding: 12,
              onTap: _openTemplateEditor,
            ),
            const AppListDivider.forTile(hasLeading: false),
            AppListTile(
              leading: const Icon(Lucide.Eye, size: 20),
              title: Text(l10n.assistantEditPreviewTitle),
              trailing: Icon(
                _showTemplatePreview ? Lucide.ChevronUp : Lucide.ChevronDown,
                size: 18,
              ),
              minVerticalPadding: 10,
              onTap: () =>
                  setState(() => _showTemplatePreview = !_showTemplatePreview),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: _showTemplatePreview
                  ? templatePreview()
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        AppListGroupHeader(
          title: l10n.assistantEditPresetTitle,
          trailing: Builder(
            builder: (buttonContext) => AppListGroupHeaderAction(
              icon: Lucide.Plus,
              semanticLabel: l10n.assistantEditPresetAddMenuTitle,
              onTap: () => unawaited(
                showFrostedPopupMenuAt(
                  buttonContext,
                  globalPosition: popupMenuAnchorForContext(buttonContext),
                  title: l10n.assistantEditPresetAddMenuTitle,
                  items: [
                    FrostedPopupMenuItem(
                      icon: Lucide.User,
                      label: l10n.assistantEditPresetAddUser,
                      onPressed: () => _createPresetMessage(assistant, 'user'),
                    ),
                    FrostedPopupMenuItem(
                      icon: Lucide.Bot,
                      label: l10n.assistantEditPresetAddAssistant,
                      onPressed: () =>
                          _createPresetMessage(assistant, 'assistant'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AppListGroup.list(
          children: [
            if (assistant.presetMessages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Text(
                  l10n.assistantEditPresetEmpty,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            for (
              var index = 0;
              index < assistant.presetMessages.length;
              index++
            ) ...[
              Builder(
                builder: (context) {
                  final message = assistant.presetMessages[index];
                  final isAssistant = message.role == 'assistant';
                  final iconColor = isAssistant ? cs.secondary : cs.primary;
                  final roleLabel = isAssistant
                      ? l10n.assistantEditPresetRoleAssistant
                      : l10n.assistantEditPresetRoleUser;
                  return AppListTile(
                    leading: SizedBox(
                      width: 32,
                      height: 32,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isAssistant ? Lucide.Bot : Lucide.User,
                          size: 18,
                          color: iconColor,
                        ),
                      ),
                    ),
                    title: Text(roleLabel),
                    subtitle: Text(
                      message.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Builder(
                      builder: (buttonContext) => IosIconButton(
                        icon: Lucide.Ellipsis,
                        size: 19,
                        minSize: 40,
                        semanticLabel: l10n.assistantEditPresetActionsTitle,
                        onTap: () => unawaited(
                          showFrostedPopupMenuAt(
                            buttonContext,
                            globalPosition: popupMenuAnchorForContext(
                              buttonContext,
                            ),
                            title: l10n.assistantEditPresetActionsTitle,
                            items: [
                              FrostedPopupMenuItem(
                                icon: Lucide.Pencil,
                                label: l10n.assistantEditPresetEditDialogTitle,
                                onPressed: () => _showEditPresetDialog(
                                  context,
                                  assistant,
                                  message,
                                ),
                              ),
                              FrostedPopupMenuItem(
                                icon: Lucide.Trash2,
                                label: l10n.quickPhraseDeleteButton,
                                onPressed: () =>
                                    _deletePresetMessage(assistant, message),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    minLeadingWidth: 32,
                    horizontalTitleGap: 10,
                    minVerticalPadding: 10,
                    onTap: () =>
                        _showEditPresetDialog(context, assistant, message),
                  );
                },
              ),
              if (index != assistant.presetMessages.length - 1)
                const AppListDivider.forTile(hasLeading: true),
            ],
          ],
        ),
      ],
    );
  }
}

class _HoverTextButton extends StatefulWidget {
  const _HoverTextButton({
    required this.label,
    required this.onTap,
    this.color,
    this.dense = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool dense;

  @override
  State<_HoverTextButton> createState() => _HoverTextButtonState();
}

class _HoverTextButtonState extends State<_HoverTextButton> {
  bool _hover = false;
  bool _press = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = _press
        ? (widget.color ?? cs.primary).withValues(alpha: 0.8)
        : (widget.color ?? cs.primary);
    final EdgeInsets padding = widget.dense
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    final Color bg = (_hover || _press)
        ? (isDark
              ? Colors.white.withValues(alpha: _press ? 0.12 : 0.08)
              : Colors.black.withValues(alpha: _press ? 0.08 : 0.06))
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _press = true),
        onTapUp: (_) => setState(() => _press = false),
        onTapCancel: () => setState(() => _press = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: textColor,
              fontWeight: AppFontWeights.emphasis,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetMessageCreatePopup extends StatefulWidget {
  const _PresetMessageCreatePopup({super.key, required this.role});

  final String role;

  @override
  State<_PresetMessageCreatePopup> createState() =>
      _PresetMessageCreatePopupState();
}

class _PresetMessageCreatePopupState extends State<_PresetMessageCreatePopup> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      key: ValueKey(PopupContentSurfaceScope.isDialogOf(context)),
      primary: !PopupContentSurfaceScope.isDialogOf(context),
      padding: PopupContentFrame.scrollPadding(
        context,
        EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
      ),
      child: AppListGroup.list(
        children: [
          AppListTile(
            title: AppTextField(
              controller: _controller,
              minLines: 5,
              maxLines: null,
              scrollPhysics: const NeverScrollableScrollPhysics(),
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: widget.role == 'assistant'
                    ? l10n.assistantEditPresetInputHintAssistant
                    : l10n.assistantEditPresetInputHintUser,
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
    );
  }

  void _submit() {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    Navigator.of(context, rootNavigator: true).pop(content);
  }
}

class _PromptTextMobileSheet extends StatefulWidget {
  const _PromptTextMobileSheet({
    super.key,
    required this.initial,
    required this.hint,
    required this.variableGroups,
  });

  final String initial;
  final String hint;
  final List<_PromptVariableGroup> variableGroups;

  @override
  State<_PromptTextMobileSheet> createState() => _PromptTextMobileSheetState();
}

class _PromptTextMobileSheetState extends State<_PromptTextMobileSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final availableHeight = MediaQuery.sizeOf(context).height - bottom;
    return SizedBox(
      height: availableHeight * 0.96,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: AppListGroup(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: AppTextField(
                  // This editor is the sheet's scrollable content; use the
                  // package-provided controller for its native drag activity.
                  key: ValueKey(PopupContentSurfaceScope.isDialogOf(context)),
                  scrollController: PopupContentSurfaceScope.isDialogOf(context)
                      ? null
                      : PrimaryScrollController.maybeOf(context),
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _PromptVariableMenuButton(
              groups: widget.variableGroups,
              controller: _controller,
              focusNode: _focusNode,
            ),
          ],
        ),
      ),
    );
  }

  void _submit() => Navigator.of(context).pop(_controller.text);
}

class _PromptTextDesktopDialog extends StatefulWidget {
  const _PromptTextDesktopDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.variableGroups,
  });

  final String title;
  final String initial;
  final String hint;
  final List<_PromptVariableGroup> variableGroups;

  @override
  State<_PromptTextDesktopDialog> createState() =>
      _PromptTextDesktopDialogState();
}

class _PromptTextDesktopDialogState extends State<_PromptTextDesktopDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(
                  alpha: isDark ? 0.22 : 0.18,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: AppFontWeights.emphasis,
                            ),
                          ),
                        ),
                        _HoverTextButton(
                          label: MaterialLocalizations.of(
                            context,
                          ).closeButtonLabel,
                          color: cs.onSurface,
                          onTap: () => Navigator.of(context).maybePop(),
                          dense: true,
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.6,
                    color: cs.outlineVariant.withValues(alpha: 0.14),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white10
                                    : const Color(0xFFF7F7F9),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              child: AppTextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                autofocus: true,
                                expands: true,
                                maxLines: null,
                                minLines: null,
                                keyboardType: TextInputType.multiline,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: InputDecoration(
                                  hintText: widget.hint,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    14,
                                    14,
                                    14,
                                    14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _PromptVariableMenuButton(
                            groups: widget.variableGroups,
                            controller: _controller,
                            focusNode: _focusNode,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _HoverTextButton(
                        label: AppLocalizations.of(
                          context,
                        )!.assistantEditEmojiDialogSave,
                        color: cs.primary,
                        onTap: () =>
                            Navigator.of(context).pop(_controller.text),
                        dense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptVariableGroup {
  const _PromptVariableGroup({required this.title, required this.items});

  final String title;
  final List<(String, String)> items;
}

class _PromptVariableMenuButton extends StatelessWidget {
  const _PromptVariableMenuButton({
    required this.groups,
    required this.controller,
    required this.focusNode,
  });

  final List<_PromptVariableGroup> groups;
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppListTile(
      leading: const Icon(Lucide.Code, size: 20),
      title: Text(l10n.assistantEditPromptInsertVariable),
      subtitle: Text(l10n.assistantEditPromptVariablePickerSubtitle),
      trailing: const Icon(Lucide.ChevronRight, size: 18),
      minVerticalPadding: 8,
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 20,
      horizontalTitleGap: 12,
      onTap: () {
        final anchor = popupMenuAnchorForContext(context);
        unawaited(
          showFrostedPopupMenuAt(
            context,
            globalPosition: anchor,
            title: l10n.assistantEditPromptInsertVariable,
            items: [
              for (final group in groups)
                FrostedPopupMenuItem(
                  icon: Lucide.FolderOpen,
                  label: group.title,
                  children: [
                    for (final item in group.items)
                      FrostedPopupMenuItem(
                        icon: Lucide.Code,
                        label: item.$1,
                        description: item.$2,
                        onPressed: () => _insertPromptVariable(
                          controller,
                          focusNode,
                          item.$2,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

void _insertPromptVariable(
  TextEditingController controller,
  FocusNode focusNode,
  String token,
) {
  final text = controller.text;
  final selection = controller.selection;
  final start = selection.start >= 0 && selection.start <= text.length
      ? selection.start
      : text.length;
  final end = selection.end >= start && selection.end <= text.length
      ? selection.end
      : start;
  controller.value = controller.value.copyWith(
    text: text.replaceRange(start, end, token),
    selection: TextSelection.collapsed(offset: start + token.length),
    composing: TextRange.empty,
  );
  focusNode.requestFocus();
}

Future<void> _showEditPresetDialog(
  BuildContext context,
  Assistant a,
  PresetMessage m,
) async {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  final controller = TextEditingController(text: m.content);
  final platform = Theme.of(context).platform;
  final isDesktop =
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.windows;
  Future<bool> save() async {
    final text = controller.text.trim();
    if (text.isEmpty) return false;
    final list = List<PresetMessage>.of(a.presetMessages);
    final idx = list.indexWhere((e) => e.id == m.id);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(content: text);
    }
    await context.read<AssistantProvider>().updateAssistant(
      a.copyWith(presetMessages: list),
    );
    return true;
  }

  if (isDesktop) {
    try {
      await showAppDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AppDialogFrame(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.assistantEditPresetEditDialogTitle,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: AppFontWeights.emphasis,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          ctx,
                        ).closeButtonTooltip,
                        icon: const Icon(Lucide.X, size: 18),
                        color: cs.onSurface,
                        onPressed: () => Navigator.of(ctx).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AppTextField(
                    controller: controller,
                    minLines: 3,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: m.role == 'assistant'
                          ? l10n.assistantEditPresetInputHintAssistant
                          : l10n.assistantEditPresetInputHintUser,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _IosButton(
                        label: l10n.assistantEditEmojiDialogCancel,
                        onTap: () => Navigator.of(ctx).pop(),
                        filled: false,
                        neutral: true,
                        dense: true,
                      ),
                      const SizedBox(width: 8),
                      _IosButton(
                        label: l10n.assistantEditEmojiDialogSave,
                        onTap: () async {
                          if (await save() && ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                        },
                        filled: true,
                        neutral: false,
                        dense: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
    return;
  }
  try {
    await showAppPopupSheet<void>(
      context: context,
      title: l10n.assistantEditPresetEditDialogTitle,
      extendBodyBehindHeader: true,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.assistantEditEmojiDialogSave,
          onTap: () async {
            if (await save() && context.mounted) {
              Navigator.of(context, rootNavigator: true).pop();
            }
          },
        ),
      ],
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            key: ValueKey(PopupContentSurfaceScope.isDialogOf(ctx)),
            primary: !PopupContentSurfaceScope.isDialogOf(ctx),
            padding: PopupContentFrame.scrollPadding(
              ctx,
              EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                AppTextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: null,
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  decoration: InputDecoration(
                    hintText: m.role == 'assistant'
                        ? l10n.assistantEditPresetInputHintAssistant
                        : l10n.assistantEditPresetInputHintUser,
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark
                        ? Colors.white10
                        : const Color(0xFFF7F7F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: cs.primary.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  } finally {
    controller.dispose();
  }
}
