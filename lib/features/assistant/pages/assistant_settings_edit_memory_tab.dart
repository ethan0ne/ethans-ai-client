part of 'assistant_settings_edit_page.dart';

/// A memory row shown by `_MemoryTab`, regardless of whether it backs onto
/// the local `MemoryProvider` (BYOK) or the cloud `client_assistant_memories`
/// table (`cloudHosted` assistants) — both sources expose the same
/// `{id, content}` shape, this just erases which one a given row came from
/// so the rendering/edit-sheet code below doesn't need to branch on it.
class _MemoryRow {
  const _MemoryRow({required this.id, required this.content});
  final int id;
  final String content;
}

String _memoryPreview(String content) =>
    content.replaceAll(RegExp(r'\s+'), ' ').trim();

class _MemoryEditorPopup extends StatefulWidget {
  const _MemoryEditorPopup({
    super.key,
    required this.initial,
    required this.canDelete,
    required this.onSave,
    required this.onDelete,
  });

  final String initial;
  final bool canDelete;
  final Future<bool> Function(String content) onSave;
  final Future<bool> Function() onDelete;

  @override
  State<_MemoryEditorPopup> createState() => _MemoryEditorPopupState();
}

class _MemoryEditorPopupState extends State<_MemoryEditorPopup> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  Future<void> save() async {
    final content = _controller.text.trim();
    if (content.isEmpty || !mounted) return;
    if (await widget.onSave(content) && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> delete() async {
    if (await widget.onDelete() && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
            16,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
        ),
        child: Column(
          children: [
            AppListGroup.list(
              children: [
                AppListTile(
                  title: AppTextField(
                    controller: _controller,
                    minLines: 5,
                    maxLines: null,
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: l10n.assistantEditMemoryDialogHint,
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
            if (widget.canDelete) ...[
              const SizedBox(height: 12),
              AppListGroup.list(
                children: [
                  AppListTile(
                    leading: const Icon(
                      Lucide.Trash2,
                      size: 20,
                      color: AppColors.destructiveRed,
                    ),
                    title: Text(
                      l10n.chatMessageWidgetDeleteMemory,
                      style: const TextStyle(color: AppColors.destructiveRed),
                    ),
                    onTap: delete,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryEditorPopup extends StatefulWidget {
  const _SummaryEditorPopup({
    super.key,
    required this.title,
    required this.initial,
    required this.onSave,
    required this.onDelete,
  });

  final String title;
  final String initial;
  final Future<void> Function(String content) onSave;
  final Future<bool> Function() onDelete;

  @override
  State<_SummaryEditorPopup> createState() => _SummaryEditorPopupState();
}

class _SummaryEditorPopupState extends State<_SummaryEditorPopup> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  Future<void> save() async {
    await widget.onSave(_controller.text.trim());
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> delete() async {
    if (await widget.onDelete() && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
            16,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
        ),
        child: Column(
          children: [
            AppListGroup.list(
              children: [
                AppListTile(
                  title: Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.secondaryLabel(
                        Theme.of(context).brightness,
                      ),
                    ),
                  ),
                  minVerticalPadding: 12,
                ),
                const AppListDivider.forTile(hasLeading: false),
                AppListTile(
                  title: AppTextField(
                    controller: _controller,
                    minLines: 5,
                    maxLines: null,
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: l10n.assistantEditSummaryDialogHint,
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
            const SizedBox(height: 12),
            AppListGroup.list(
              children: [
                AppListTile(
                  leading: const Icon(
                    Lucide.Trash2,
                    size: 20,
                    color: AppColors.destructiveRed,
                  ),
                  title: Text(
                    l10n.assistantEditDeleteSummaryTitle,
                    style: const TextStyle(color: AppColors.destructiveRed),
                  ),
                  onTap: delete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryTab extends StatefulWidget {
  const _MemoryTab({required this.assistantId});
  final String assistantId;

  @override
  State<_MemoryTab> createState() => _MemoryTabState();
}

class _MemoryTabState extends State<_MemoryTab> {
  // null = not yet loaded (or not a cloud-hosted assistant, in which case it
  // stays null forever and `MemoryProvider` is used instead).
  List<_MemoryRow>? _cloudMemories;
  bool _cloudLoadFailed = false;

  bool get _isCloudHosted =>
      context
          .read<AssistantProvider>()
          .getById(widget.assistantId)
          ?.cloudHosted ??
      false;

  @override
  void initState() {
    super.initState();
    if (_isCloudHosted) _reloadCloudMemories();
  }

  @override
  void didUpdateWidget(covariant _MemoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assistantId != widget.assistantId) {
      _cloudMemories = null;
      _cloudLoadFailed = false;
      if (_isCloudHosted) _reloadCloudMemories();
    }
  }

  Future<void> _reloadCloudMemories() async {
    final token = ClientBackendSession.token;
    if (token == null) {
      if (mounted) setState(() => _cloudLoadFailed = true);
      return;
    }
    final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
    final result = await api.listAssistantMemories(token, widget.assistantId);
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _cloudMemories = [
          for (final m in result.memories!)
            _MemoryRow(id: m.id, content: m.content),
        ];
        _cloudLoadFailed = false;
      } else {
        _cloudLoadFailed = true;
      }
    });
  }

  /// Creates or updates a memory — cloud-hosted assistants block on the
  /// server call and reconcile `_cloudMemories` from the response (same
  /// "confirm with server before treating as real" rule as assistant
  /// creation); BYOK assistants keep using `MemoryProvider` as before.
  Future<bool> _saveMemory(
    BuildContext context, {
    int? id,
    required String content,
  }) async {
    if (_isCloudHosted) {
      final token = ClientBackendSession.token;
      if (token == null) {
        if (context.mounted) _showCloudSaveError(context);
        return false;
      }
      final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
      final result = id == null
          ? await api.createAssistantMemory(token, widget.assistantId, content)
          : await api.updateAssistantMemory(
              token,
              widget.assistantId,
              id,
              content,
            );
      if (result == null) {
        if (context.mounted) _showCloudSaveError(context);
        return false;
      }
      if (mounted) {
        setState(() {
          final rows = List<_MemoryRow>.of(_cloudMemories ?? const []);
          final row = _MemoryRow(id: result.id, content: result.content);
          final idx = rows.indexWhere((r) => r.id == result.id);
          if (idx == -1) {
            rows.add(row);
          } else {
            rows[idx] = row;
          }
          _cloudMemories = rows;
        });
      }
      return true;
    }
    final mp = context.read<MemoryProvider>();
    if (id == null) {
      await mp.add(assistantId: widget.assistantId, content: content);
    } else {
      await mp.update(id: id, content: content);
    }
    return true;
  }

  Future<bool> _deleteMemory(BuildContext context, int id) async {
    if (_isCloudHosted) {
      final token = ClientBackendSession.token;
      if (token == null) {
        if (context.mounted) _showCloudSaveError(context);
        return false;
      }
      final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
      final ok = await api.deleteAssistantMemory(token, widget.assistantId, id);
      if (!ok) {
        if (context.mounted) _showCloudSaveError(context);
        return false;
      }
      if (mounted) {
        setState(() {
          _cloudMemories = [
            for (final r in _cloudMemories ?? const <_MemoryRow>[])
              if (r.id != id) r,
          ];
        });
      }
      return true;
    }
    await context.read<MemoryProvider>().delete(id: id);
    return true;
  }

  void _showCloudSaveError(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(
      context,
      message: l10n.assistantEditMemoryCloudSaveFailed,
      type: NotificationType.error,
    );
  }

  Future<void> _showAddEditSheet(
    BuildContext context, {
    int? id,
    String initial = '',
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final editorKey = GlobalKey<_MemoryEditorPopupState>();
    await showAppPopupSheet<void>(
      context: context,
      title: l10n.assistantEditMemoryDialogTitle,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.assistantEditEmojiDialogSave,
          onTap: () => unawaited(editorKey.currentState?.save()),
        ),
      ],
      extendBodyBehindHeader: true,
      builder: (popupContext) => _MemoryEditorPopup(
        key: editorKey,
        initial: initial,
        canDelete: id != null,
        onSave: (content) => _saveMemory(context, id: id, content: content),
        onDelete: () => id == null
            ? Future<bool>.value(false)
            : _deleteMemory(popupContext, id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;
    final bool cloudLoading;
    final List<_MemoryRow> memories;
    if (a.cloudHosted) {
      cloudLoading = _cloudMemories == null && !_cloudLoadFailed;
      memories = _cloudMemories ?? const <_MemoryRow>[];
    } else {
      cloudLoading = false;
      final mp = context.watch<MemoryProvider>();
      // Ensure provider loads persisted memories once
      try {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          mp.initialize();
        });
      } catch (_) {}
      memories = [
        for (final m in mp.getForAssistant(widget.assistantId))
          _MemoryRow(id: m.id, content: m.content),
      ];
    }

    return ListView(
      padding: AppScaffold.scrollPadding(
        context,
        const EdgeInsets.fromLTRB(16, 8, 16, 16),
      ),
      children: [
        AppListGroup.list(
          children: [
            _iosSwitchRow(
              context,
              icon: Lucide.bookHeart,
              label: l10n.assistantEditMemorySwitchTitle,
              value: a.enableMemory,
              onChanged: (v) async {
                await context.read<AssistantProvider>().updateAssistant(
                  a.copyWith(enableMemory: v),
                );
              },
            ),
            const AppListDivider.forTile(hasLeading: true),
            _iosSwitchRow(
              context,
              icon: Lucide.History,
              label: l10n.assistantEditRecentChatsSwitchTitle,
              value: a.enableRecentChatsReference,
              onChanged: (v) async {
                await context.read<AssistantProvider>().updateAssistant(
                  a.copyWith(enableRecentChatsReference: v),
                );
              },
            ),
            if (a.enableRecentChatsReference) ...[
              const AppListDivider.forTile(hasLeading: true),
              _RecentChatsSummaryFrequencySection(assistant: a),
            ],
          ],
        ),
        AppListGroupHeader(
          title: l10n.assistantEditManageMemoryTitle,
          trailing: AppListGroupHeaderAction(
            icon: Lucide.Plus,
            semanticLabel: l10n.assistantEditAddMemoryButton,
            onTap: () => _showAddEditSheet(context),
          ),
        ),
        AppListGroup.list(
          children: [
            if (cloudLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_cloudLoadFailed)
              AppListTile(
                leading: Icon(Lucide.CircleAlert, size: 20, color: cs.error),
                title: Text(
                  l10n.assistantEditMemoryCloudLoadFailed,
                  style: TextStyle(color: cs.error),
                ),
                trailing: IosIconButton(
                  icon: Lucide.RefreshCw,
                  size: 18,
                  minSize: 40,
                  semanticLabel: l10n.assistantEditMemoryCloudLoadFailed,
                  onTap: () {
                    setState(() => _cloudLoadFailed = false);
                    _reloadCloudMemories();
                  },
                ),
                minVerticalPadding: 12,
              )
            else if (memories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Text(
                  l10n.assistantEditMemoryEmpty,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              )
            else ...[
              for (var index = 0; index < memories.length; index++) ...[
                Builder(
                  builder: (context) {
                    final memory = memories[index];
                    return AppListTile(
                      title: Text(
                        _memoryPreview(memory.content),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        Lucide.ChevronRight,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      minVerticalPadding: 12,
                      onTapFeedback: _assistantSettingsListFeedback(context),
                      onTap: () => _showAddEditSheet(
                        context,
                        id: memory.id,
                        initial: memory.content,
                      ),
                    );
                  },
                ),
                if (index != memories.length - 1)
                  const AppListDivider.forTile(hasLeading: false),
              ],
            ],
          ],
        ),
        AppListGroupHeader(title: l10n.assistantEditManageSummariesTitle),
        Builder(
          builder: (context) {
            final chatService = context.watch<ChatService>();
            final summaries = chatService
                .getConversationsWithSummaryForAssistant(widget.assistantId);

            if (summaries.isEmpty) {
              return AppListGroup(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Text(
                    l10n.assistantEditSummaryEmpty,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              );
            }

            return AppListGroup.list(
              children: [
                for (var index = 0; index < summaries.length; index++) ...[
                  Builder(
                    builder: (context) {
                      final conversation = summaries[index];
                      return AppListTile(
                        title: Text(
                          conversation.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          conversation.summary ?? '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          Lucide.ChevronRight,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        minVerticalPadding: 12,
                        onTapFeedback: _assistantSettingsListFeedback(context),
                        onTap: () => _showEditSummarySheet(
                          context,
                          conversation,
                          chatService,
                        ),
                      );
                    },
                  ),
                  if (index != summaries.length - 1)
                    const AppListDivider.forTile(hasLeading: false),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _showEditSummarySheet(
    BuildContext context,
    Conversation conversation,
    ChatService chatService,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final editorKey = GlobalKey<_SummaryEditorPopupState>();
    await showAppPopupSheet<void>(
      context: context,
      title: l10n.assistantEditSummaryDialogTitle,
      extendBodyBehindHeader: true,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.assistantEditEmojiDialogSave,
          onTap: () => unawaited(editorKey.currentState?.save()),
        ),
      ],
      builder: (popupContext) => _SummaryEditorPopup(
        key: editorKey,
        title: conversation.title,
        initial: conversation.summary ?? '',
        onSave: (text) async {
          if (text.isEmpty) {
            await chatService.clearConversationSummary(conversation.id);
          } else {
            await chatService.updateConversationSummary(
              conversation.id,
              text,
              conversation.lastSummarizedMessageCount,
            );
          }
        },
        onDelete: () =>
            _confirmDeleteSummary(popupContext, conversation.id, chatService),
      ),
    );
  }

  Future<bool> _confirmDeleteSummary(
    BuildContext context,
    String conversationId,
    ChatService chatService,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.assistantEditDeleteSummaryTitle),
        content: Text(l10n.assistantEditDeleteSummaryContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.homePageCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.assistantEditClearButton),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await chatService.clearConversationSummary(conversationId);
    }
    return confirmed == true;
  }
}

class _RecentChatsSummaryFrequencySection extends StatelessWidget {
  const _RecentChatsSummaryFrequencySection({required this.assistant});

  final Assistant assistant;

  List<int> _frequencyOptions() => <int>{
    ...Assistant.recentChatsSummaryMessageCountOptions,
    assistant.recentChatsSummaryMessageCount,
  }.toList()..sort();

  Future<void> _showFrequencyMenu(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final assistantProvider = context.read<AssistantProvider>();
    final selected = assistant.recentChatsSummaryMessageCount;
    final options = _frequencyOptions();

    await showFrostedPopupMenuAt(
      context,
      globalPosition: popupMenuAnchorForContext(context),
      title: l10n.assistantEditRecentChatsSummaryFrequencyTitle,
      items: [
        for (final count in options)
          FrostedPopupMenuItem(
            icon: null,
            label: l10n.assistantEditRecentChatsSummaryFrequencyOption(count),
            isOption: true,
            selected: count == selected,
            dividerAfter: count == options.last,
            onPressed: () {
              if (count == selected) return;
              unawaited(
                assistantProvider.updateAssistant(
                  assistant.copyWith(recentChatsSummaryMessageCount: count),
                ),
              );
            },
          ),
        FrostedPopupMenuItem(
          icon: Lucide.Pencil,
          label: l10n.assistantEditRecentChatsSummaryFrequencyCustomButton,
          onPressed: () => unawaited(_showCustomCountInput(context)),
        ),
      ],
    );
  }

  Future<void> _showCustomCountInput(BuildContext context) async {
    final assistantProvider = context.read<AssistantProvider>();
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => _CustomSummaryFrequencyDialog(
        initialCount: assistant.recentChatsSummaryMessageCount,
        onSave: (count) async {
          if (count != assistant.recentChatsSummaryMessageCount) {
            await assistantProvider.updateAssistant(
              assistant.copyWith(recentChatsSummaryMessageCount: count),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selected = assistant.recentChatsSummaryMessageCount;

    return Builder(
      builder: (rowContext) => AppSettingsNavTile(
        icon: Lucide.FileClock,
        label: l10n.assistantEditRecentChatsSummaryFrequencyTitle,
        detailText: l10n.assistantEditRecentChatsSummaryFrequencyOption(
          selected,
        ),
        onTapFeedback: _assistantSettingsListFeedback(rowContext),
        onTap: () => unawaited(_showFrequencyMenu(rowContext)),
      ),
    );
  }
}

class _CustomSummaryFrequencyDialog extends StatefulWidget {
  const _CustomSummaryFrequencyDialog({
    required this.initialCount,
    required this.onSave,
  });

  final int initialCount;
  final Future<void> Function(int count) onSave;

  @override
  State<_CustomSummaryFrequencyDialog> createState() =>
      _CustomSummaryFrequencyDialogState();
}

class _CustomSummaryFrequencyDialogState
    extends State<_CustomSummaryFrequencyDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialCount.toString(),
  );

  int? get _parsedValue {
    final value = int.tryParse(_controller.text.trim());
    return value != null && value > 0 ? value : null;
  }

  Future<void> _submit() async {
    final value = _parsedValue;
    final l10n = AppLocalizations.of(context)!;
    if (value == null) {
      showAppSnackBar(
        context,
        message: l10n.assistantEditRecentChatsSummaryFrequencyCustomInvalid,
        type: NotificationType.error,
      );
      return;
    }
    await widget.onSave(value);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isValid = _parsedValue != null;
    return AppAlertDialog(
      title: Text(l10n.assistantEditRecentChatsSummaryFrequencyCustomTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.assistantEditRecentChatsSummaryFrequencyCustomDescription,
            ),
            const SizedBox(height: 12),
            IosFormTextField(
              label: l10n.assistantEditRecentChatsSummaryFrequencyCustomLabel,
              controller: _controller,
              hintText: l10n.assistantEditRecentChatsSummaryFrequencyCustomHint,
              inlineLabel: false,
              showLabel: false,
              textAlign: TextAlign.start,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_parsedValue != null) unawaited(_submit());
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.assistantEditEmojiDialogCancel),
        ),
        TextButton(
          onPressed: isValid ? () => unawaited(_submit()) : null,
          child: Text(l10n.assistantEditEmojiDialogSave),
        ),
      ],
    );
  }
}
