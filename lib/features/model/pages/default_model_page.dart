import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../shared/widgets/app_switch.dart';
import '../widgets/model_select_sheet.dart';
import '../widgets/ocr_prompt_sheet.dart';
import '../utils/ocr_model_capability.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/brand_assets.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_group.dart';
import '../../../shared/widgets/app_list_tile.dart';

class DefaultModelPage extends StatelessWidget {
  const DefaultModelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    Future<ModelSelection?> pickConfiguredModel(
      String? providerKey,
      String? modelId,
    ) {
      return showModelSelector(
        context,
        initialProviderKey: providerKey,
        initialModelId: modelId,
      );
    }

    return AppScaffold(
      backgroundColor: cs.surface,

      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.defaultModelPageBackTooltip,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(l10n.defaultModelPageTitle),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          AppScaffold.scrollContentTop(context),
          16,
          AppScaffold.scrollContentBottom(context),
        ),
        children: [
          _ModelCard(
            icon: Lucide.MessageCircle,
            title: l10n.defaultModelPageChatModelTitle,
            subtitle: l10n.defaultModelPageChatModelSubtitle,
            modelProvider: settings.currentModelProvider,
            modelId: settings.currentModelId,
            onReset: () async {
              await settings.resetCurrentModel();
            },
            onPick: () async {
              final sel = await pickConfiguredModel(
                settings.currentModelProvider,
                settings.currentModelId,
              );
              if (sel != null) {
                await settings.setCurrentModel(sel.providerKey, sel.modelId);
              }
            },
          ),
          if (!settings.isHostedLoggedIn) ...[
            const SizedBox(height: 16),
            _ModelCard(
              icon: Lucide.NotebookTabs,
              title: l10n.defaultModelPageTitleModelTitle,
              subtitle: l10n.defaultModelPageTitleModelSubtitle,
              modelProvider: settings.titleModelProvider,
              modelId: settings.titleModelId,
              fallbackProvider: settings.currentModelProvider,
              fallbackModelId: settings.currentModelId,
              locked: settings.isHostedLoggedIn,
              onReset: () async {
                await settings.resetTitleModel();
              },
              onPick: () async {
                final sel = await pickConfiguredModel(
                  settings.titleModelProvider,
                  settings.titleModelId,
                );
                if (sel != null) {
                  await settings.setTitleModel(sel.providerKey, sel.modelId);
                }
              },
              configAction: () => _showTitlePromptSheet(context),
            ),
            const SizedBox(height: 16),
            _ModelCard(
              icon: Lucide.FileText,
              title: l10n.defaultModelPageSummaryModelTitle,
              subtitle: l10n.defaultModelPageSummaryModelSubtitle,
              modelProvider: settings.summaryModelProvider,
              modelId: settings.summaryModelId,
              fallbackProvider:
                  settings.titleModelProvider ?? settings.currentModelProvider,
              fallbackModelId: settings.titleModelId ?? settings.currentModelId,
              locked: settings.isHostedLoggedIn,
              onReset: () async {
                await settings.resetSummaryModel();
              },
              onPick: () async {
                final sel = await pickConfiguredModel(
                  settings.summaryModelProvider,
                  settings.summaryModelId,
                );
                if (sel != null) {
                  await settings.setSummaryModel(sel.providerKey, sel.modelId);
                }
              },
              configAction: () => _showSummaryPromptSheet(context),
            ),
            const SizedBox(height: 16),
            _ModelCard(
              icon: Lucide.MessagesSquare,
              title: l10n.defaultModelPageSuggestionModelTitle,
              subtitle: l10n.defaultModelPageSuggestionModelSubtitle,
              modelProvider: settings.suggestionModelProvider,
              modelId: settings.suggestionModelId,
              disabledWhenUnset: true,
              locked: settings.isHostedLoggedIn,
              onReset: () async {
                await settings.resetSuggestionModel();
              },
              onPick: () async {
                final sel = await pickConfiguredModel(
                  settings.suggestionModelProvider,
                  settings.suggestionModelId,
                );
                if (sel != null) {
                  await settings.setSuggestionModel(
                    sel.providerKey,
                    sel.modelId,
                  );
                }
              },
              configAction: () => _showSuggestionPromptSheet(context),
            ),
            const SizedBox(height: 16),
            _ModelCard(
              icon: Lucide.package2,
              title: l10n.defaultModelPageCompressModelTitle,
              subtitle: l10n.defaultModelPageCompressModelSubtitle,
              modelProvider: settings.compressModelProvider,
              modelId: settings.compressModelId,
              fallbackProvider:
                  settings.summaryModelProvider ??
                  settings.titleModelProvider ??
                  settings.currentModelProvider,
              fallbackModelId:
                  settings.summaryModelId ??
                  settings.titleModelId ??
                  settings.currentModelId,
              locked: settings.isHostedLoggedIn,
              onReset: () async {
                await settings.resetCompressModel();
              },
              onPick: () async {
                final sel = await pickConfiguredModel(
                  settings.compressModelProvider,
                  settings.compressModelId,
                );
                if (sel != null) {
                  await settings.setCompressModel(sel.providerKey, sel.modelId);
                }
              },
              configAction: () => _showCompressPromptSheet(context),
            ),
            const SizedBox(height: 16),
            _ModelCard(
              icon: Lucide.Languages,
              title: l10n.defaultModelPageTranslateModelTitle,
              subtitle: l10n.defaultModelPageTranslateModelSubtitle,
              modelProvider: settings.translateModelProvider,
              modelId: settings.translateModelId,
              fallbackProvider: settings.currentModelProvider,
              fallbackModelId: settings.currentModelId,
              locked: settings.isHostedLoggedIn,
              onReset: () async {
                await settings.resetTranslateModel();
              },
              onPick: () async {
                final sel = await pickConfiguredModel(
                  settings.translateModelProvider,
                  settings.translateModelId,
                );
                if (sel != null) {
                  await settings.setTranslateModel(
                    sel.providerKey,
                    sel.modelId,
                  );
                }
              },
              configAction: () => _showTranslatePromptSheet(context),
            ),
            if (!settings.isHostedLoggedIn) ...[
              const SizedBox(height: 16),
              _ModelCard(
                icon: Lucide.Eye,
                title: l10n.defaultModelPageOcrModelTitle,
                subtitle: l10n.defaultModelPageOcrModelSubtitle,
                modelProvider: settings.ocrModelProvider,
                modelId: settings.ocrModelId,
                disabledWhenUnset: true,
                onReset: () async {
                  await settings.resetOcrModel();
                },
                onPick: () async {
                  final sel = await pickConfiguredModel(
                    settings.ocrModelProvider,
                    settings.ocrModelId,
                  );
                  if (sel != null) {
                    if (!modelSupportsOcrImageInput(
                      settings,
                      sel.providerKey,
                      sel.modelId,
                    )) {
                      if (!context.mounted) return;
                      showAppSnackBar(
                        context,
                        message:
                            l10n.defaultModelPageOcrModelRequiresImageInput,
                        type: NotificationType.error,
                      );
                      return;
                    }
                    await settings.setOcrModel(sel.providerKey, sel.modelId);
                  }
                },
                configAction: () => showOcrPromptSheet(context),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _showTitlePromptSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final controller = TextEditingController(text: settings.titlePrompt);
    var thinkingEnabled = settings.titleGenerationThinkingEnabled;
    try {
      await showAppPopupSheet(
        context: context,
        title: l10n.defaultModelPageTitleModelTitle,
        actions: [
          appPopupDoneAction(
            semanticLabel: l10n.defaultModelPageSave,
            onTap: () async {
              await settings.setTitlePrompt(controller.text.trim());
              await settings.setTitleGenerationThinkingEnabled(thinkingEnabled);
              if (context.mounted) {
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
        builder: (ctx) => StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 0,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TitleThinkingSwitchRow(
                      value: thinkingEnabled,
                      l10n: l10n,
                      onChanged: (value) =>
                          setSheetState(() => thinkingEnabled = value),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      l10n.defaultModelPagePromptLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppTextField(
                      controller: controller,
                      maxLines: 6,
                      decoration: InputDecoration(
                        hintText: l10n.defaultModelPageTitlePromptHint,
                        filled: true,
                        fillColor: Theme.of(ctx).brightness == Brightness.dark
                            ? Colors.white10
                            : const Color(0xFFF2F3F5),
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
                    const SizedBox(height: 6),
                    Text(
                      l10n.defaultModelPageTitleVars('{content}', '{locale}'),
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            controller.text =
                                SettingsProvider.defaultTitlePrompt;
                            setSheetState(() => thinkingEnabled = true);
                          },
                          child: Text(l10n.defaultModelPageResetDefault),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showTranslatePromptSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final controller = TextEditingController(text: settings.translatePrompt);
    await showAppPopupSheet(
      context: context,
      title: l10n.defaultModelPageTranslateModelTitle,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.defaultModelPageSave,
          onTap: () async {
            await settings.setTranslatePrompt(controller.text.trim());
            if (context.mounted) {
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
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 0,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.defaultModelPagePromptLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  controller: controller,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: l10n.defaultModelPageTranslatePromptHint,
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark
                        ? Colors.white10
                        : const Color(0xFFF2F3F5),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        await settings.resetTranslatePrompt();
                        controller.text = settings.translatePrompt;
                      },
                      child: Text(l10n.defaultModelPageResetDefault),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.defaultModelPageTranslateVars(
                    '{source_text}',
                    '{target_lang}',
                  ),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSummaryPromptSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final controller = TextEditingController(text: settings.summaryPrompt);
    await showAppPopupSheet(
      context: context,
      title: l10n.defaultModelPageSummaryModelTitle,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.defaultModelPageSave,
          onTap: () async {
            await settings.setSummaryPrompt(controller.text.trim());
            if (context.mounted) {
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
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 0,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.defaultModelPagePromptLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  controller: controller,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: l10n.defaultModelPageSummaryPromptHint,
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark
                        ? Colors.white10
                        : const Color(0xFFF2F3F5),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        await settings.resetSummaryPrompt();
                        controller.text = settings.summaryPrompt;
                      },
                      child: Text(l10n.defaultModelPageResetDefault),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.defaultModelPageSummaryVars(
                    '{previous_summary}',
                    '{user_messages}',
                  ),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCompressPromptSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final controller = TextEditingController(text: settings.compressPrompt);
    await showAppPopupSheet(
      context: context,
      title: l10n.defaultModelPageCompressModelTitle,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.defaultModelPageSave,
          onTap: () async {
            await settings.setCompressPrompt(controller.text.trim());
            if (context.mounted) {
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
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 0,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.defaultModelPagePromptLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  controller: controller,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: l10n.defaultModelPageCompressPromptHint,
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark
                        ? Colors.white10
                        : const Color(0xFFF2F3F5),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        await settings.resetCompressPrompt();
                        controller.text = settings.compressPrompt;
                      },
                      child: Text(l10n.defaultModelPageResetDefault),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.defaultModelPageCompressVars('{content}', '{locale}'),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSuggestionPromptSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final controller = TextEditingController(text: settings.suggestionPrompt);
    await showAppPopupSheet(
      context: context,
      title: l10n.defaultModelPageSuggestionModelTitle,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.defaultModelPageSave,
          onTap: () async {
            await settings.setSuggestionPrompt(controller.text.trim());
            if (context.mounted) {
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
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 0,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.defaultModelPagePromptLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  controller: controller,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: l10n.defaultModelPageSuggestionPromptHint,
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark
                        ? Colors.white10
                        : const Color(0xFFF2F3F5),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        await settings.resetSuggestionPrompt();
                        controller.text = settings.suggestionPrompt;
                      },
                      child: Text(l10n.defaultModelPageResetDefault),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.defaultModelPageSuggestionVars('{content}', '{locale}'),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.modelProvider,
    required this.modelId,
    required this.onPick,
    this.onReset,
    this.fallbackProvider,
    this.fallbackModelId,
    this.disabledWhenUnset = false,
    this.configAction,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? modelProvider;
  final String? modelId;
  final String? fallbackProvider;
  final String? fallbackModelId;
  final bool disabledWhenUnset;
  final VoidCallback onPick;
  final VoidCallback? onReset;
  final VoidCallback? configAction;
  // [kelivo-hosted] Set by [DefaultModelPage] whenever `settings.isHostedLoggedIn`
  // — every model slot except chat is centrally managed server-side while
  // logged in (kelivo-arch.md 1.1), so picking/resetting a model here would
  // be immediately overridden by `SettingsProvider`'s own getters anyway
  // (see `hostedDefaultModelFor`). Disables the tap-to-pick row and the
  // reset button, and swaps in a lock glyph + distinct "server has no
  // default assigned" copy when [modelId] is null so that reads as "the
  // platform hasn't turned this on" rather than "tap to configure".
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.read<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;

    // Check if using fallback (not explicitly set)
    final usingFallback = modelProvider == null || modelId == null;

    // Use fallback values if needed
    final effectiveProvider = modelProvider ?? fallbackProvider;
    final effectiveModelId = modelId ?? fallbackModelId;

    String? providerName;
    String? modelDisplay;
    if (effectiveProvider != null && effectiveModelId != null) {
      final cfg = settings.getProviderConfig(effectiveProvider);
      providerName = cfg.name.isNotEmpty ? cfg.name : effectiveProvider;
      final ov = cfg.modelOverrides[effectiveModelId] as Map?;
      if (ov != null) {
        final overrideName = (ov['name'] as String?)?.trim();
        if (overrideName != null && overrideName.isNotEmpty) {
          modelDisplay = overrideName;
        } else {
          final apiId = (ov['apiModelId'] ?? ov['api_model_id'])
              ?.toString()
              .trim();
          modelDisplay = (apiId != null && apiId.isNotEmpty)
              ? apiId
              : effectiveModelId;
        }
      } else {
        modelDisplay = effectiveModelId;
      }
    }

    // Override display text if using fallback
    if (usingFallback) {
      modelDisplay = locked
          ? l10n.defaultModelPageServerNotConfigured
          : (disabledWhenUnset
                ? l10n.defaultModelPageNotEnabled
                : l10n.defaultModelPageUseCurrentModel);
    }
    final baseBg = isDark
        ? Colors.white10
        : Colors.white.withValues(alpha: 0.96);
    return Container(
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ),
                if (locked)
                  Tooltip(
                    message: l10n.defaultModelPageServerManagedTooltip,
                    child: Icon(
                      Lucide.Lock,
                      size: 16,
                      color: cs.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                if (onReset != null && !usingFallback && !locked)
                  Tooltip(
                    message: l10n.defaultModelPageResetDefault,
                    child: _TactileIconButton(
                      icon: Lucide.RotateCcw,
                      color: cs.onSurface,
                      size: 20,
                      onTap: onReset!,
                    ),
                  ),
                if (configAction != null)
                  _TactileIconButton(
                    icon: Lucide.Settings,
                    color: cs.onSurface,
                    size: 20,
                    onTap: configAction!,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // description under title
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            const SizedBox(height: 8),
            _TactileRow(
              onTap: locked ? null : onPick,
              builder: (pressed) {
                final bg = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
                final overlay = isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05);
                final pressedBg = Color.alphaBlend(overlay, bg);
                return AnimatedScale(
                  scale: pressed ? 0.98 : 1.0,
                  duration: const Duration(milliseconds: 110),
                  curve: Curves.easeOutCubic,
                  child: AnimatedContainer(
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
                        _BrandAvatar(
                          name: modelDisplay ?? (providerName ?? '?'),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            modelDisplay ?? (providerName ?? '-'),
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
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({required this.name, this.size = 20});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = BrandAssets.assetForName(name);
    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final dark = Theme.of(context).brightness == Brightness.dark;
        final ColorFilter? tint = (dark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.62,
          height: size * 0.62,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(
          asset,
          width: size * 0.62,
          height: size * 0.62,
          fit: BoxFit.contain,
        );
      }
    } else {
      inner = Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: AppFontWeights.emphasis,
          fontSize: size * 0.42,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}

class _TitleThinkingSwitchRow extends StatelessWidget {
  const _TitleThinkingSwitchRow({
    required this.value,
    required this.l10n,
    required this.onChanged,
  });

  final bool value;
  final AppLocalizations l10n;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppListGroup(
      child: AppListTile(
        title: Text(l10n.titleModelThinkingTitle),
        trailing: AppSwitch(
          value: value,
          semanticLabel: l10n.titleModelThinkingTitle,
          onChanged: onChanged,
        ),
        onTap: () => onChanged(!value),
        onTapFeedback: Haptics.light,
      ),
    );
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
    final pressColor = base.withValues(alpha: 0.7);
    final icon = Icon(
      widget.icon,
      size: widget.size,
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

class _TactileRow extends StatefulWidget {
  const _TactileRow({required this.builder, this.onTap});
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;
  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null
          ? null
          : (_) async {
              // Keep pressed state for a short moment to avoid flicker
              await Future.delayed(const Duration(milliseconds: 60));
              if (mounted) _setPressed(false);
            },
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (context.read<SettingsProvider>().hapticsOnListItemTap) {
                Haptics.soft();
              }
              widget.onTap!.call();
            },
      child: widget.builder(_pressed),
    );
  }
}
