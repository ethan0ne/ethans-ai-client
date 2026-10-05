part of 'assistant_settings_edit_page.dart';

class _BasicSettingsTab extends StatefulWidget {
  const _BasicSettingsTab({required this.assistantId});
  final String assistantId;

  @override
  State<_BasicSettingsTab> createState() => _BasicSettingsTabState();
}

class _BasicSettingsTabState extends State<_BasicSettingsTab> {
  late final TextEditingController _thinkingCtrl;
  late final TextEditingController _maxTokensCtrl;
  // Temporarily hidden with the chat background setting; see
  // docs/product/cross-client-feature-gaps.md and retain for restoration.
  // late final TextEditingController _backgroundCtrl;

  @override
  void initState() {
    super.initState();
    final ap = context.read<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;
    _thinkingCtrl = TextEditingController(
      text: a.thinkingBudget?.toString() ?? '',
    );
    _maxTokensCtrl = TextEditingController(text: a.maxTokens?.toString() ?? '');
    // _backgroundCtrl = TextEditingController(text: a.background ?? '');
  }

  @override
  void didUpdateWidget(covariant _BasicSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assistantId != widget.assistantId) {
      final ap = context.read<AssistantProvider>();
      final a = ap.getById(widget.assistantId)!;
      _thinkingCtrl.text = a.thinkingBudget?.toString() ?? '';
      _maxTokensCtrl.text = a.maxTokens?.toString() ?? '';
      // _backgroundCtrl.text = a.background ?? '';
    }
  }

  @override
  void dispose() {
    _thinkingCtrl.dispose();
    _maxTokensCtrl.dispose();
    // _backgroundCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(widget.assistantId)!;

    return ListView(
      padding: AppScaffold.scrollPadding(
        context,
        const EdgeInsets.fromLTRB(16, 8, 16, 16),
      ),
      children: [
        // Basic generation and model settings.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: _iosSectionCard(
            children: [
              // Temperature
              _iosNavRow(
                context,
                icon: Lucide.Thermometer,
                label: l10n.assistantEditTemperatureTitle,
                detailText: a.temperature != null
                    ? a.temperature!.toStringAsFixed(2)
                    : l10n.assistantEditParameterDisabled,
                onTap: () => _showTemperatureSheet(context, a),
              ),
              _iosDivider(context),
              // Top P
              _iosNavRow(
                context,
                icon: Lucide.Wand2,
                label: l10n.assistantEditTopPTitle,
                detailText: a.topP != null
                    ? a.topP!.toStringAsFixed(2)
                    : l10n.assistantEditParameterDisabled,
                onTap: () => _showTopPSheet(context, a),
              ),
              if (!isHostedProviderAssistant(context, a)) ...[
                _iosDivider(context),
                // Context messages are a BYOK-only local history limit.
                _iosNavRow(
                  context,
                  icon: Lucide.MessagesSquare,
                  label: l10n.assistantEditContextMessagesTitle,
                  detailText: a.limitContextMessages
                      ? a.contextMessageSize.toString()
                      : l10n.assistantEditParameterDisabled2,
                  onTap: () => _showContextMessagesSheet(context, a),
                ),
              ],
              // [kelivo-hosted] kelivo-arch.md §5 — the hosted backend has
              // no transport for thinking budget at all (unlike temperature/
              // top_p/max_tokens, which it now does support server-side) —
              // hiding this avoids letting the user configure a value that
              // can never take effect.
              if (!isHostedProviderAssistant(context, a)) ...[
                _iosDivider(context),
                // Thinking budget
                _iosNavRow(
                  context,
                  icon: Lucide.Brain,
                  label: l10n.assistantEditThinkingBudgetTitle,
                  detailText: a.thinkingBudget?.toString() ?? '-',
                  onTap: () async {
                    final settingsProvider = context.read<SettingsProvider>();
                    final assistantProvider = context.read<AssistantProvider>();
                    final currentBudget = a.thinkingBudget;
                    if (currentBudget != null) {
                      settingsProvider.setThinkingBudget(currentBudget);
                    }
                    await showReasoningBudgetSheet(
                      context,
                      modelProvider: a.chatModelProvider,
                      modelId: a.chatModelId,
                    );
                    if (!context.mounted) return;
                    final chosen = settingsProvider.thinkingBudget;
                    await assistantProvider.updateAssistant(
                      a.copyWith(thinkingBudget: chosen),
                    );
                  },
                ),
              ],
              _iosDivider(context),
              // Max tokens
              _iosNavRow(
                context,
                icon: Lucide.Hash,
                label: l10n.assistantEditMaxTokensTitle,
                detailText:
                    a.maxTokens?.toString() ?? l10n.assistantEditMaxTokensHint,
                onTap: () => _showMaxTokensDialog(context, a),
              ),
              if (!isHostedProviderAssistant(context, a)) ...[
                _iosDivider(context),
                // Hosted replies are streamed and persisted by the server;
                // there is no per-assistant client switch to apply here.
                _iosSwitchRow(
                  context,
                  icon: Lucide.Zap,
                  label: l10n.assistantEditStreamOutputTitle,
                  value: a.streamOutput,
                  onChanged: (v) => context
                      .read<AssistantProvider>()
                      .updateAssistant(a.copyWith(streamOutput: v)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Chat model card (moved down, styled like DefaultModelPage)
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white10
                : Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Lucide.MessageCircle, size: 18, color: cs.onSurface),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.assistantEditChatModelTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: AppFontWeights.semibold,
                        ),
                      ),
                    ),
                    if (a.chatModelProvider != null && a.chatModelId != null)
                      Tooltip(
                        message: l10n.defaultModelPageResetDefault,
                        child: _TactileIconButton(
                          icon: Lucide.RotateCcw,
                          color: cs.onSurface,
                          size: 20,
                          onTap: () async {
                            await context
                                .read<AssistantProvider>()
                                .updateAssistant(
                                  a.copyWith(clearChatModel: true),
                                );
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.assistantEditChatModelSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                _TactileRow(
                  onTap: () async {
                    final assistantProvider = context.read<AssistantProvider>();
                    final sel = await showModelSelector(
                      context,
                      initialProviderKey: a.chatModelProvider,
                      initialModelId: a.chatModelId,
                    );
                    if (!context.mounted || sel == null) return;
                    await assistantProvider.updateAssistant(
                      a.copyWith(
                        chatModelProvider: sel.providerKey,
                        chatModelId: sel.modelId,
                      ),
                    );
                  },
                  pressedScale: 0.98,
                  builder: (pressed) {
                    final bg = isDark
                        ? Colors.white10
                        : const Color(0xFFF2F3F5);
                    final overlay = isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.05);
                    final pressedBg = Color.alphaBlend(overlay, bg);
                    final l10n = AppLocalizations.of(context)!;
                    final settings = context.read<SettingsProvider>();
                    String display = l10n.assistantEditModelUseGlobalDefault;
                    if (a.chatModelProvider != null && a.chatModelId != null) {
                      try {
                        final cfg = settings.getProviderConfig(
                          a.chatModelProvider!,
                        );
                        final ov = cfg.modelOverrides[a.chatModelId] as Map?;
                        final mdl =
                            (ov != null &&
                                (ov['name'] as String?)?.isNotEmpty == true)
                            ? (ov['name'] as String)
                            : a.chatModelId!;
                        display = mdl;
                      } catch (_) {
                        display = a.chatModelId ?? '';
                      }
                    }
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: pressed ? pressedBg : bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _BrandAvatarLike(name: display, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              display,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: AppFontWeights.semibold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Temporarily hidden pending cross-client support. See
        // docs/product/cross-client-feature-gaps.md; keep this UI commented
        // here so it can be restored when the behavior is aligned.
        /*
        _iosSectionCard(
          children: [
            _iosSwitchRow(
              context,
              icon: Lucide.User,
              label: l10n.assistantEditUseAssistantAvatarTitle,
              value: a.useAssistantAvatar,
              onChanged: (v) => context
                  .read<AssistantProvider>()
                  .updateAssistant(a.copyWith(useAssistantAvatar: v)),
            ),
            _iosDivider(context),
            _iosSwitchRow(
              context,
              icon: Lucide.CaseSensitive,
              label: l10n.assistantEditUseAssistantNameTitle,
              value: a.useAssistantName,
              onChanged: (v) => context
                  .read<AssistantProvider>()
                  .updateAssistant(a.copyWith(useAssistantName: v)),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Chat background (separate iOS card)
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white10
                : Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Lucide.Image, size: 18, color: cs.onSurface),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.assistantEditChatBackgroundTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: AppFontWeights.semibold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.assistantEditChatBackgroundDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                if ((a.background ?? '').isEmpty) ...[
                  _TactileRow(
                    onTap: () => _pickBackground(context, a),
                    pressedScale: 0.98,
                    builder: (pressed) {
                      final bg = isDark
                          ? Colors.white10
                          : const Color(0xFFF2F3F5);
                      final overlay = isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.05);
                      final pressedBg = Color.alphaBlend(overlay, bg);
                      final iconColor = cs.onSurface.withValues(alpha: 0.75);
                      final textColor = cs.onSurface.withValues(alpha: 0.9);
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: pressed ? pressedBg : bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 2.0),
                              child: Icon(
                                Icons.image,
                                size: 18,
                                color: iconColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.assistantEditChooseImageButton,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: AppFontWeights.semibold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _IosButton(
                          label: l10n.assistantEditChooseImageButton,
                          icon: Icons.image,
                          onTap: () => _pickBackground(context, a),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _IosButton(
                          label: l10n.assistantEditClearButton,
                          icon: Lucide.X,
                          onTap: () =>
                              context.read<AssistantProvider>().updateAssistant(
                                a.copyWith(clearBackground: true),
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
                if ((a.background ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _BackgroundPreview(path: a.background!),
                  ),
                ],
              ],
            ),
          ),
        ),
        */
      ],
    );
  }

  /*
  // Temporarily hidden with the chat background setting; see
  // docs/product/cross-client-feature-gaps.md and retain for restoration.
  Future<void> _pickBackground(BuildContext context, Assistant a) async {
    try {
      final assistantProvider = context.read<AssistantProvider>();
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (!context.mounted || file == null) return;
      await assistantProvider.updateAssistant(
        a.copyWith(background: file.path),
      );
    } catch (_) {}
  }
  */

  Future<void> _showTemperatureSheet(BuildContext context, Assistant a) async {
    final l10n = AppLocalizations.of(context)!;
    await showAppPopupSheet(
      context: context,
      title: l10n.assistantEditTemperatureTitle,
      showCloseButton: false,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.homePageDone,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Builder(
              builder: (context) {
                final assistant =
                    context.watch<AssistantProvider>().getById(
                      widget.assistantId,
                    ) ??
                    a;
                final enabled = assistant.temperature != null;
                final value = assistant.temperature ?? 0.6;
                return _assistantParameterGroup(
                  context,
                  icon: Lucide.Thermometer,
                  title: l10n.assistantEditTemperatureTitle,
                  subtitle: enabled
                      ? l10n.assistantEditTemperatureDescription
                      : l10n.assistantEditParameterDisabled,
                  enabled: enabled,
                  onChanged: (nextEnabled) {
                    final next = nextEnabled
                        ? assistant.copyWith(temperature: value)
                        : assistant.copyWith(clearTemperature: true);
                    unawaited(
                      context.read<AssistantProvider>().updateAssistant(next),
                    );
                  },
                  control: _SliderTileNew(
                    value: value.clamp(0.0, 2.0),
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    label: value.toStringAsFixed(2),
                    onChanged: (nextValue) =>
                        context.read<AssistantProvider>().updateAssistant(
                          assistant.copyWith(temperature: nextValue),
                        ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTopPSheet(BuildContext context, Assistant a) async {
    final l10n = AppLocalizations.of(context)!;
    await showAppPopupSheet(
      context: context,
      title: l10n.assistantEditTopPTitle,
      showCloseButton: false,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.homePageDone,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
      isScrollControlled: false,
      builder: (_) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Builder(
              builder: (context) {
                final assistant =
                    context.watch<AssistantProvider>().getById(
                      widget.assistantId,
                    ) ??
                    a;
                final enabled = assistant.topP != null;
                final value = assistant.topP ?? 1.0;
                return _assistantParameterGroup(
                  context,
                  icon: Lucide.Wand2,
                  title: l10n.assistantEditTopPTitle,
                  subtitle: enabled
                      ? l10n.assistantEditTopPDescription
                      : l10n.assistantEditParameterDisabled,
                  enabled: enabled,
                  onChanged: (nextEnabled) {
                    final next = nextEnabled
                        ? assistant.copyWith(topP: value)
                        : assistant.copyWith(clearTopP: true);
                    unawaited(
                      context.read<AssistantProvider>().updateAssistant(next),
                    );
                  },
                  control: _SliderTileNew(
                    value: value.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    label: value.toStringAsFixed(2),
                    onChanged: (nextValue) => context
                        .read<AssistantProvider>()
                        .updateAssistant(assistant.copyWith(topP: nextValue)),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showContextMessagesSheet(
    BuildContext context,
    Assistant a,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await showAppPopupSheet(
      context: context,
      title: l10n.assistantEditContextMessagesTitle,
      showCloseButton: false,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.homePageDone,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
      isScrollControlled: false,
      builder: (_) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Builder(
              builder: (context) {
                final assistant =
                    context.watch<AssistantProvider>().getById(
                      widget.assistantId,
                    ) ??
                    a;
                final enabled = assistant.limitContextMessages;
                final value = _clampContextMessages(
                  assistant.contextMessageSize,
                );
                return _assistantParameterGroup(
                  context,
                  icon: Lucide.MessagesSquare,
                  title: l10n.assistantEditContextMessagesTitle,
                  subtitle: enabled
                      ? l10n.assistantEditContextMessagesDescription
                      : l10n.assistantEditParameterDisabled2,
                  enabled: enabled,
                  onChanged: (nextEnabled) {
                    final next =
                        nextEnabled &&
                            assistant.contextMessageSize < _contextMessageMin
                        ? assistant.copyWith(
                            limitContextMessages: true,
                            contextMessageSize: _contextMessageMin,
                          )
                        : assistant.copyWith(limitContextMessages: nextEnabled);
                    unawaited(
                      context.read<AssistantProvider>().updateAssistant(next),
                    );
                  },
                  control: _SliderTileNew(
                    value: value.toDouble(),
                    min: _contextMessageMin.toDouble(),
                    max: _contextMessageMax.toDouble(),
                    divisions: _contextMessageMax - _contextMessageMin,
                    label: value.toString(),
                    customLabelStops: const <double>[
                      1.0,
                      64.0,
                      128.0,
                      256.0,
                      512.0,
                      1024.0,
                    ],
                    onLabelTap: () async {
                      final assistantProvider = context
                          .read<AssistantProvider>();
                      final chosen = await _showContextMessageInputDialog(
                        context,
                        initialValue: value,
                      );
                      if (!context.mounted || chosen == null) return;
                      final current =
                          assistantProvider.getById(widget.assistantId) ??
                          assistant;
                      await assistantProvider.updateAssistant(
                        current.copyWith(contextMessageSize: chosen),
                      );
                    },
                    onChanged: (nextValue) =>
                        context.read<AssistantProvider>().updateAssistant(
                          assistant.copyWith(
                            contextMessageSize: _clampContextMessages(
                              nextValue,
                            ),
                          ),
                        ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMaxTokensDialog(BuildContext context, Assistant a) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    await showAppDialog<void>(
      context: context,
      builder: (_) => _MaxTokensDialog(
        initialValue: a.maxTokens?.toString() ?? '',
        title: l10n.assistantEditMaxTokensTitle,
        hintText: l10n.assistantEditMaxTokensHint,
        description: l10n.assistantEditMaxTokensDescription,
        cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
        saveLabel: l10n.assistantSettingsAddSheetSave,
        onSave: (parsed, isEmpty) async {
          final current = context.read<AssistantProvider>().getById(a.id) ?? a;
          await context.read<AssistantProvider>().updateAssistant(
            current.copyWith(maxTokens: parsed, clearMaxTokens: isEmpty),
          );
        },
      ),
    );
  }
}

class _AssistantNameDialog extends StatefulWidget {
  const _AssistantNameDialog({
    required this.initialValue,
    required this.title,
    required this.cancelLabel,
    required this.saveLabel,
    required this.onSave,
  });

  final String initialValue;
  final String title;
  final String cancelLabel;
  final String saveLabel;
  final Future<void> Function(String name) onSave;

  @override
  State<_AssistantNameDialog> createState() => _AssistantNameDialogState();
}

class _AssistantNameDialogState extends State<_AssistantNameDialog> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_controller.text.trim());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppAlertDialog(
      title: Text(widget.title),
      content: IosFormTextField(
        label: widget.title,
        controller: _controller,
        inlineLabel: false,
        showLabel: false,
        textInputAction: TextInputAction.done,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}

class _MaxTokensDialog extends StatefulWidget {
  const _MaxTokensDialog({
    required this.initialValue,
    required this.title,
    required this.hintText,
    required this.description,
    required this.cancelLabel,
    required this.saveLabel,
    required this.onSave,
  });

  final String initialValue;
  final String title;
  final String hintText;
  final String description;
  final String cancelLabel;
  final String saveLabel;
  final Future<void> Function(int? value, bool isEmpty) onSave;

  @override
  State<_MaxTokensDialog> createState() => _MaxTokensDialogState();
}

class _MaxTokensDialogState extends State<_MaxTokensDialog> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rawValue = _controller.text.trim();
    final parsed = rawValue.isEmpty ? null : int.tryParse(rawValue);
    if (rawValue.isNotEmpty && parsed == null) return;

    setState(() => _saving = true);
    try {
      await widget.onSave(parsed, rawValue.isEmpty);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IosFormTextField(
            label: widget.title,
            controller: _controller,
            hintText: widget.hintText,
            showLabel: false,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.start,
            textInputAction: TextInputAction.done,
            autofocus: true,
          ),
          const SizedBox(height: 8),
          Text(
            widget.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}

/*
// Temporarily hidden with the chat background setting; retain for restoration.
class _BackgroundPreview extends StatefulWidget {
  const _BackgroundPreview({required this.path});
  final String path;

  @override
  State<_BackgroundPreview> createState() => _BackgroundPreviewState();
}

class _BackgroundPreviewState extends State<_BackgroundPreview> {
  Size? _size;

  @override
  void initState() {
    super.initState();
    _resolveSize();
  }

  @override
  void didUpdateWidget(covariant _BackgroundPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _size = null;
      _resolveSize();
    }
  }

  Future<void> _resolveSize() async {
    try {
      if (widget.path.startsWith('http')) {
        // Skip network size probe; render with a sensible max height
        setState(() => _size = null);
        return;
      }
      final file = File(SandboxPathResolver.fix(widget.path));
      if (!await file.exists()) {
        setState(() => _size = null);
        return;
      }
      final bytes = await file.readAsBytes();
      final img = await decodeImageFromList(bytes);
      final s = Size(img.width.toDouble(), img.height.toDouble());
      if (mounted) setState(() => _size = s);
    } catch (_) {
      if (mounted) setState(() => _size = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNetwork = widget.path.startsWith('http');
    final imageWidget = isNetwork
        ? Image.network(widget.path, fit: BoxFit.contain)
        : (() {
            final fixed = SandboxPathResolver.fix(widget.path);
            final f = File(fixed);
            if (!f.existsSync()) {
              // Gracefully fallback to empty box when local file missing (e.g., imported from mobile)
              return const SizedBox.shrink();
            }
            return Image.file(f, fit: BoxFit.contain);
          })();
    // When size known, maintain aspect ratio; otherwise cap the height to avoid overflow
    if (_size != null && _size!.width > 0 && _size!.height > 0) {
      final ratio = _size!.width / _size!.height;
      return SizedBox(
        width: double.infinity,
        child: AspectRatio(aspectRatio: ratio, child: imageWidget),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 280,
        minHeight: 100,
        minWidth: double.infinity,
      ),
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 400, height: 240, child: imageWidget),
      ),
    );
  }
}
*/

class _SliderTileNew extends StatelessWidget {
  const _SliderTileNew({
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.label,
    required this.onChanged,
    this.customLabelStops,
    this.onLabelTap,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final List<double>? customLabelStops;
  final VoidCallback? onLabelTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final useCustomLabels =
        customLabelStops != null && customLabelStops!.isNotEmpty;
    final stops = useCustomLabels
        ? (customLabelStops!.where((v) => v >= min && v <= max).toSet().toList()
            ..sort())
        : const <double>[];

    final active = cs.primary;
    final inactive = cs.onSurface.withValues(alpha: isDark ? 0.25 : 0.20);
    final double clamped = value.clamp(min, max);
    final double? step = (divisions != null && divisions! > 0)
        ? (max - min) / divisions!
        : null;
    // Compute a readable major interval and minor tick count
    final total = (max - min).abs();
    double interval;
    if (total <= 0) {
      interval = 1;
    } else if ((divisions ?? 0) <= 20) {
      interval = total / 4; // up to 5 major ticks inc endpoints
    } else if ((divisions ?? 0) <= 50) {
      interval = total / 5;
    } else {
      interval = total / 8;
    }
    if (interval <= 0) interval = 1;
    int minor = 0;
    if (step != null && step > 0) {
      // Ensure minor ticks align with the chosen step size
      minor = ((interval / step) - 1).round();
      if (minor < 0) minor = 0;
      if (minor > 8) minor = 8;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SfSliderTheme(
                    data: SfSliderThemeData(
                      activeTrackHeight: 8,
                      inactiveTrackHeight: 8,
                      overlayRadius: 14,
                      activeTrackColor: active,
                      inactiveTrackColor: inactive,
                      // Waterdrop tooltip uses theme primary background with onPrimary text
                      tooltipBackgroundColor: cs.primary,
                      tooltipTextStyle: TextStyle(
                        color: cs.onPrimary,
                        fontWeight: AppFontWeights.semibold,
                      ),
                      thumbStrokeColor: Colors.transparent,
                      thumbStrokeWidth: 0,
                      activeTickColor: cs.onSurface.withValues(
                        alpha: isDark ? 0.45 : 0.35,
                      ),
                      inactiveTickColor: cs.onSurface.withValues(
                        alpha: isDark ? 0.30 : 0.25,
                      ),
                      activeMinorTickColor: cs.onSurface.withValues(
                        alpha: isDark ? 0.34 : 0.28,
                      ),
                      inactiveMinorTickColor: cs.onSurface.withValues(
                        alpha: isDark ? 0.24 : 0.20,
                      ),
                    ),
                    child: SfSlider(
                      value: clamped,
                      min: min,
                      max: max,
                      stepSize: step,
                      enableTooltip: true,
                      // Show the paddle tooltip only while interacting
                      shouldAlwaysShowTooltip: false,
                      showTicks: true,
                      showLabels: !useCustomLabels,
                      interval: interval,
                      minorTicksPerInterval: minor,
                      activeColor: active,
                      inactiveColor: inactive,
                      tooltipTextFormatterCallback: (actual, text) => label,
                      tooltipShape: const SfPaddleTooltipShape(),
                      labelFormatterCallback: (actual, formattedText) {
                        // Prefer integers for wide ranges, keep 2 decimals for 0..1
                        if (total <= 2.0) return actual.toStringAsFixed(2);
                        if (actual == actual.roundToDouble()) {
                          return actual.toStringAsFixed(0);
                        }
                        return actual.toStringAsFixed(1);
                      },
                      thumbIcon: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                          boxShadow: isDark
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                      ),
                      onChanged: (v) =>
                          onChanged(v is num ? v.toDouble() : (v as double)),
                    ),
                  ),
                  if (useCustomLabels && stops.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (_, __) {
                        final range = (max - min).abs();
                        return SizedBox(
                          height: 18,
                          child: Stack(
                            fit: StackFit.expand,
                            children: stops.map((v) {
                              final t = range == 0
                                  ? 0.0
                                  : ((v - min) / range).clamp(0.0, 1.0);
                              return Align(
                                alignment: Alignment(-1 + t * 2, 0),
                                child: Text(
                                  v == v.roundToDouble()
                                      ? v.toInt().toString()
                                      : v.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurface.withValues(alpha: 0.65),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ValuePill(text: label, onTap: onLabelTap),
          ],
        ),
        // Remove explicit min/max captions since ticks already indicate range
      ],
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({required this.text, this.onTap});
  final String text;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      behavior: onTap != null
          ? HitTestBehavior.opaque
          : HitTestBehavior.deferToChild,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: cs.primary.withValues(alpha: isDark ? 0.28 : 0.22),
          ),
          boxShadow: isDark ? [] : AppShadows.soft,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            text,
            style: TextStyle(
              color: cs.primary,
              fontWeight: AppFontWeights.emphasis,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

extension _AssistantAvatarActions on _AssistantDetailOutlinePageState {
  Future<void> _showAssistantNameDialog(BuildContext context, Assistant a) {
    final l10n = AppLocalizations.of(context)!;
    return showAppDialog<void>(
      context: context,
      builder: (_) => _AssistantNameDialog(
        initialValue: a.name,
        title: l10n.assistantEditAssistantNameLabel,
        cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
        saveLabel: l10n.assistantSettingsAddSheetSave,
        onSave: (name) async {
          final assistantProvider = context.read<AssistantProvider>();
          final current = assistantProvider.getById(a.id) ?? a;
          await assistantProvider.updateAssistant(current.copyWith(name: name));
        },
      ),
    );
  }

  void _showAvatarPicker(BuildContext context, Assistant a) {
    final l10n = AppLocalizations.of(context)!;
    unawaited(
      showFrostedPopupMenuAt(
        context,
        globalPosition: popupMenuAnchorForContext(context),
        title: l10n.assistantEditUseAssistantAvatarTitle,
        items: [
          FrostedPopupMenuItem(
            icon: Lucide.Image,
            label: l10n.assistantEditAvatarChooseImage,
            onPressed: () => unawaited(_pickLocalImage(context, a)),
          ),
          FrostedPopupMenuItem(
            icon: Icons.emoji_emotions_outlined,
            label: l10n.assistantEditAvatarChooseEmoji,
            onPressed: () async {
              final assistantProvider = context.read<AssistantProvider>();
              final emoji = await _pickEmoji(context);
              if (!context.mounted || emoji == null) return;
              await assistantProvider.updateAssistant(
                a.copyWith(avatar: emoji),
              );
            },
          ),
          FrostedPopupMenuItem(
            icon: Lucide.Link2,
            label: l10n.assistantEditAvatarEnterLink,
            onPressed: () => unawaited(_inputAvatarUrl(context, a)),
          ),
          FrostedPopupMenuItem(
            icon: Lucide.User,
            label: l10n.assistantEditAvatarImportQQ,
            onPressed: () => unawaited(_inputQQAvatar(context, a)),
          ),
          FrostedPopupMenuItem(
            icon: Lucide.RotateCcw,
            label: l10n.assistantEditAvatarReset,
            onPressed: () => unawaited(
              context.read<AssistantProvider>().updateAssistant(
                a.copyWith(clearAvatar: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickEmoji(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    String value = '';
    bool validGrapheme(String s) {
      final trimmed = s.characters.take(1).toString().trim();
      return trimmed.isNotEmpty && trimmed == s.trim();
    }

    final List<String> quick = const [
      '😀',
      '😁',
      '😂',
      '🤣',
      '😃',
      '😄',
      '😅',
      '😊',
      '😍',
      '😘',
      '😗',
      '😙',
      '😚',
      '🙂',
      '🤗',
      '🤩',
      '🫶',
      '🤝',
      '👍',
      '👎',
      '👋',
      '🙏',
      '💪',
      '🔥',
      '✨',
      '🌟',
      '💡',
      '🎉',
      '🎊',
      '🎈',
      '🌈',
      '☀️',
      '🌙',
      '⭐',
      '⚡',
      '☁️',
      '❄️',
      '🌧️',
      '🍎',
      '🍊',
      '🍋',
      '🍉',
      '🍇',
      '🍓',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥝',
      '🍅',
      '🥕',
      '🌽',
      '🍞',
      '🧀',
      '🍔',
      '🍟',
      '🍕',
      '🌮',
      '🌯',
      '🍣',
      '🍜',
      '🍰',
      '🍪',
      '🍩',
      '🍫',
      '🍻',
      '☕',
      '🧋',
      '🥤',
      '⚽',
      '🏀',
      '🏈',
      '🎾',
      '🏐',
      '🎮',
      '🎧',
      '🎸',
      '🎹',
      '🎺',
      '📚',
      '✏️',
      '💼',
      '💻',
      '🖥️',
      '📱',
      '🛩️',
      '✈️',
      '🚗',
      '🚕',
      '🚙',
      '🚌',
      '🚀',
      '🛰️',
      '🧠',
      '🫀',
      '💊',
      '🩺',
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐸',
      '🐵',
    ];
    return showAppDialog<String>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final media = MediaQuery.of(ctx);
            final avail = media.size.height - media.viewInsets.bottom;
            final double gridHeight = (avail * 0.28).clamp(120.0, 220.0);
            return AppAlertDialog(
              scrollable: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: cs.surface,
              title: Text(l10n.assistantEditEmojiDialogTitle),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: EmojiText(
                        value.isEmpty
                            ? '🙂'
                            : value.characters.take(1).toString(),
                        fontSize: 40,
                        optimizeEmojiAlign: true,
                        nudge: Offset.zero, // picker preview: no extra nudge
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: (v) => setLocal(() => value = v),
                      onSubmitted: (_) {
                        if (validGrapheme(value)) {
                          Navigator.of(
                            ctx,
                          ).pop(value.characters.take(1).toString());
                        }
                      },
                      decoration: InputDecoration(
                        hintText: l10n.assistantEditEmojiDialogHint,
                        filled: true,
                        fillColor: Theme.of(ctx).brightness == Brightness.dark
                            ? Colors.white10
                            : const Color(0xFFF2F3F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.transparent),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.transparent),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: cs.primary.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: gridHeight,
                      child: GridView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 8,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                        itemCount: quick.length,
                        itemBuilder: (c, i) {
                          final e = quick[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.of(ctx).pop(e),
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: EmojiText(
                                e,
                                fontSize: 20,
                                optimizeEmojiAlign: true,
                                nudge:
                                    Offset.zero, // picker grid: no extra nudge
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.assistantEditEmojiDialogCancel),
                ),
                TextButton(
                  onPressed: validGrapheme(value)
                      ? () => Navigator.of(
                          ctx,
                        ).pop(value.characters.take(1).toString())
                      : null,
                  child: Text(
                    l10n.assistantEditEmojiDialogSave,
                    style: TextStyle(
                      color: validGrapheme(value)
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.38),
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _inputAvatarUrl(BuildContext context, Assistant a) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        bool valid(String s) =>
            s.trim().startsWith('http://') || s.trim().startsWith('https://');
        String value = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AppAlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: cs.surface,
              title: Text(l10n.assistantEditImageUrlDialogTitle),
              content: AppTextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.assistantEditImageUrlDialogHint,
                  filled: true,
                  fillColor: Theme.of(ctx).brightness == Brightness.dark
                      ? Colors.white10
                      : const Color(0xFFF2F3F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                onChanged: (v) => setLocal(() => value = v),
                onSubmitted: (_) {
                  if (valid(value)) Navigator.of(ctx).pop(true);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.assistantEditImageUrlDialogCancel),
                ),
                TextButton(
                  onPressed: valid(value)
                      ? () => Navigator.of(ctx).pop(true)
                      : null,
                  child: Text(
                    l10n.assistantEditImageUrlDialogSave,
                    style: TextStyle(
                      color: valid(value)
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.38),
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok == true) {
      final url = controller.text.trim();
      if (!context.mounted || url.isEmpty) return;
      final assistantProvider = context.read<AssistantProvider>();
      await assistantProvider.updateAssistant(a.copyWith(avatar: url));
    }
  }

  Future<void> _inputQQAvatar(BuildContext context, Assistant a) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final assistantProvider = context.read<AssistantProvider>();
        final dialogNavigator = Navigator.of(ctx);
        String value = '';
        bool valid(String s) => RegExp(r'^[0-9]{5,12}$').hasMatch(s.trim());
        String randomQQ() {
          final lengths = <int>[5, 6, 7, 8, 9, 10, 11];
          final weights = <int>[1, 20, 80, 100, 500, 5000, 80];
          final total = weights.fold<int>(0, (a, b) => a + b);
          final rnd = math.Random();
          int roll = rnd.nextInt(total) + 1;
          int chosenLen = lengths.last;
          int acc = 0;
          for (int i = 0; i < lengths.length; i++) {
            acc += weights[i];
            if (roll <= acc) {
              chosenLen = lengths[i];
              break;
            }
          }
          final sb = StringBuffer();
          final firstGroups = <List<int>>[
            [1, 2],
            [3, 4],
            [5, 6, 7, 8],
            [9],
          ];
          final firstWeights = <int>[128, 4, 2, 1];
          final firstTotal = firstWeights.fold<int>(0, (a, b) => a + b);
          int r2 = rnd.nextInt(firstTotal) + 1;
          int idx = 0;
          int a2 = 0;
          for (int i = 0; i < firstGroups.length; i++) {
            a2 += firstWeights[i];
            if (r2 <= a2) {
              idx = i;
              break;
            }
          }
          final group = firstGroups[idx];
          sb.write(group[rnd.nextInt(group.length)]);
          for (int i = 1; i < chosenLen; i++) {
            sb.write(rnd.nextInt(10));
          }
          return sb.toString();
        }

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AppAlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: cs.surface,
              title: Text(l10n.assistantEditQQAvatarDialogTitle),
              content: AppTextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: l10n.assistantEditQQAvatarDialogHint,
                  filled: true,
                  fillColor: Theme.of(ctx).brightness == Brightness.dark
                      ? Colors.white10
                      : const Color(0xFFF2F3F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                onChanged: (v) => setLocal(() => value = v),
                onSubmitted: (_) {
                  if (valid(value)) Navigator.of(ctx).pop(true);
                },
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(
                  onPressed: () async {
                    const int maxTries = 20;
                    bool applied = false;
                    for (int i = 0; i < maxTries; i++) {
                      final qq = randomQQ();
                      final url =
                          'https://q2.qlogo.cn/headimg_dl?dst_uin=$qq&spec=100';
                      try {
                        final resp = await http
                            .get(Uri.parse(url))
                            .timeout(const Duration(seconds: 5));
                        if (resp.statusCode == 200 &&
                            resp.bodyBytes.isNotEmpty) {
                          await assistantProvider.updateAssistant(
                            a.copyWith(avatar: url),
                          );
                          applied = true;
                          break;
                        }
                      } catch (_) {}
                    }
                    if (applied) {
                      if (dialogNavigator.mounted && dialogNavigator.canPop()) {
                        dialogNavigator.pop(false);
                      }
                    } else {
                      if (!context.mounted) return;
                      showAppSnackBar(
                        context,
                        message: l10n.assistantEditQQAvatarFailedMessage,
                        type: NotificationType.error,
                      );
                    }
                  },
                  child: Text(l10n.assistantEditQQAvatarRandomButton),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(l10n.assistantEditQQAvatarDialogCancel),
                    ),
                    TextButton(
                      onPressed: valid(value)
                          ? () => Navigator.of(ctx).pop(true)
                          : null,
                      child: Text(
                        l10n.assistantEditQQAvatarDialogSave,
                        style: TextStyle(
                          color: valid(value)
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.38),
                          fontWeight: AppFontWeights.semibold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    if (ok == true) {
      final qq = controller.text.trim();
      if (!context.mounted || qq.isEmpty) return;
      final assistantProvider = context.read<AssistantProvider>();
      final url = 'https://q2.qlogo.cn/headimg_dl?dst_uin=$qq&spec=100';
      await assistantProvider.updateAssistant(a.copyWith(avatar: url));
    }
  }

  Future<void> _pickLocalImage(BuildContext context, Assistant a) async {
    if (kIsWeb) {
      await _inputAvatarUrl(context, a);
      return;
    }
    try {
      final assistantProvider = context.read<AssistantProvider>();
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 90,
      );
      if (!context.mounted || file == null) return;
      await assistantProvider.updateAssistant(a.copyWith(avatar: file.path));
      return;
    } on PlatformException {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.assistantEditGalleryErrorMessage,
        type: NotificationType.error,
      );
      await _inputAvatarUrl(context, a);
      return;
    } catch (_) {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.assistantEditGeneralErrorMessage,
        type: NotificationType.error,
      );
      await _inputAvatarUrl(context, a);
      return;
    }
  }
}
