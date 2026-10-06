import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_input_data.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/quick_phrase.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import '../utils/model_display_helper.dart';
import 'chat_input_bar.dart';
import 'model_icon.dart';

/// Callback for checking if a model supports tool calling.
typedef IsToolModelCallback = bool Function(String providerKey, String modelId);

/// Callback for checking if a model supports reasoning.
typedef IsReasoningModelCallback =
    bool Function(String providerKey, String modelId);

/// Callback for checking if reasoning is enabled.
typedef IsReasoningEnabledCallback = bool Function(int? budget);
typedef PickFilesCallback = Future<void> Function({bool allowImages});

/// Widget that wraps ChatInputBar with all the necessary logic and callbacks.
///
/// This widget extracts the _buildChatInputBar logic from HomePageState
/// to reduce coupling and improve maintainability.
class ChatInputSection extends StatelessWidget {
  const ChatInputSection({
    super.key,
    required this.inputBarKey,
    required this.inputFocus,
    required this.inputController,
    required this.mediaController,
    required this.isTablet,
    required this.isLoading,
    required this.isToolModel,
    required this.isReasoningModel,
    required this.isReasoningEnabled,
    this.onSelectModel,
    this.onOpenMcp,
    this.onLongPressMcp,
    this.onSetSearchEnabled,
    this.onSelectBuiltInSearch,
    this.onSelectSearchService,
    this.onOpenSearchServices,
    this.onConfigureReasoning,
    this.onSend,
    this.onStop,
    this.hasQueuedInput = false,
    this.queuedPreviewText,
    this.onCancelQueuedInput,
    this.onSelectQuickPhrase,
    this.onToggleOcr,
    this.onOpenMiniMap,
    this.onPickCamera,
    this.onPickPhotos,
    this.onPickPhotosOrVideo,
    this.imageReferenceCandidates = const [],
    this.onRefreshImageReferenceCandidates,
    this.onUploadFiles,
    this.onSetInstructionInjectionActive,
    this.onOpenWorldBook, // 新增世界书支持桌面端
    this.onLongPressLearning,
    this.onClearContext,
    this.onCompressContext,
    this.conversationId,
    this.sendButtonTooltip,
    this.hasVideoInHistory = false,
  });

  final GlobalKey inputBarKey;
  final FocusNode inputFocus;
  final AttachmentChipEditingController inputController;
  final ChatInputBarController mediaController;
  final bool isTablet;
  final bool isLoading;

  // Model capability checkers
  final IsToolModelCallback isToolModel;
  final IsReasoningModelCallback isReasoningModel;
  final IsReasoningEnabledCallback isReasoningEnabled;

  // Callbacks
  final VoidCallback? onSelectModel;
  final VoidCallback? onOpenMcp;
  final VoidCallback? onLongPressMcp;
  final Future<void> Function(bool)? onSetSearchEnabled;
  final Future<void> Function(bool)? onSelectBuiltInSearch;
  final Future<void> Function(int?)? onSelectSearchService;
  final VoidCallback? onOpenSearchServices;
  final VoidCallback? onConfigureReasoning;
  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;
  final VoidCallback? onStop;
  final bool hasQueuedInput;
  final String? queuedPreviewText;
  final VoidCallback? onCancelQueuedInput;
  final ValueChanged<QuickPhrase>? onSelectQuickPhrase;
  final VoidCallback? onToggleOcr;
  final VoidCallback? onOpenMiniMap;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickPhotos;
  final VoidCallback? onPickPhotosOrVideo;
  final List<ChatImageReferenceCandidate> imageReferenceCandidates;
  final Future<List<ChatImageReferenceCandidate>> Function()?
  onRefreshImageReferenceCandidates;
  final PickFilesCallback? onUploadFiles;
  final Future<void> Function(String id, bool active)?
  onSetInstructionInjectionActive;
  final VoidCallback? onOpenWorldBook;
  final VoidCallback? onLongPressLearning;
  final VoidCallback? onClearContext;
  final VoidCallback? onCompressContext;
  final String? conversationId;
  final String? sendButtonTooltip;
  // [kelivo-hosted] Forwarded straight through to ChatInputBar — see that
  // widget's `hasVideoInHistory` docstring.
  final bool hasVideoInHistory;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final ap = context.watch<AssistantProvider>();
    final a = ap.currentAssistant;
    final chatService = context.watch<ChatService>();
    final conversation = conversationId == null
        ? null
        : chatService.getConversation(conversationId!);
    final quickPhraseProvider = context.watch<QuickPhraseProvider>();
    final quickPhrases = <QuickPhrase>[
      ...quickPhraseProvider.globalPhrases,
      if (a != null) ...quickPhraseProvider.getForAssistant(a.id),
    ];

    // Use unified helper to get model identifiers, preferring this
    // conversation's own override over the assistant/global default.
    final override = conversationId != null
        ? context.watch<ChatService>().getConversationChatModel(conversationId!)
        : null;
    final modelIds = getActiveModelIds(settings, assistant: a);
    final pk = override?.$1 ?? modelIds.providerKey;
    final mid = override?.$2 ?? modelIds.modelId;
    final cfg = pk == null ? null : settings.getProviderConfig(pk);
    final isHosted =
        pk != null &&
        cfg != null &&
        ProviderConfig.classify(pk, explicitType: cfg.providerType) ==
            ProviderKind.hosted;
    final isImageGeneration =
        cfg != null &&
        mid != null &&
        ChatApiService.isImageGenerationModel(cfg, mid);
    final isVideoGeneration =
        cfg != null &&
        mid != null &&
        ChatApiService.isVideoGenerationModel(cfg, mid);
    final isEmbedding =
        cfg != null && mid != null && ChatApiService.isEmbeddingModel(cfg, mid);
    final supportsImageInput =
        cfg != null &&
        mid != null &&
        !isImageGeneration &&
        !isVideoGeneration &&
        !isEmbedding &&
        ChatApiService.supportsImageInput(cfg, mid);
    final maxReferenceImages = cfg != null && mid != null
        ? ChatApiService.maxReferenceImages(cfg, mid)
        : 0;
    final maxReferenceVideos = cfg != null && mid != null
        ? ChatApiService.maxReferenceVideos(cfg, mid)
        : 0;
    final canAttachImages =
        supportsImageInput ||
        (isImageGeneration && maxReferenceImages > 0) ||
        (isVideoGeneration &&
            (maxReferenceImages > 0 || maxReferenceVideos > 0));
    final referenceMode = !isHosted || isEmbedding
        ? AttachmentReferenceMode.disabled
        : isImageGeneration
        ? (maxReferenceImages > 0
              ? AttachmentReferenceMode.imageGeneration
              : AttachmentReferenceMode.disabled)
        : isVideoGeneration
        ? (maxReferenceImages > 0 || maxReferenceVideos > 0
              ? AttachmentReferenceMode.videoGeneration
              : AttachmentReferenceMode.disabled)
        : AttachmentReferenceMode.chat;

    // Enforce model capabilities: disable MCP selection if model doesn't support tools
    _enforceModelCapabilities(context, settings, ap, a, pk, mid);

    final isDesktop = _isDesktopPlatform(context);
    final hasWorldBooks = a?.worldBooks.isNotEmpty ?? false;

    return ChatInputBar(
      key: inputBarKey,
      onSelectModel: onSelectModel,
      conversationId: conversationId,
      onOpenMcp: onOpenMcp,
      onLongPressMcp: onLongPressMcp,
      onStop: onStop,
      modelIcon: (pk != null && mid != null)
          ? CurrentModelIcon(
              providerKey: pk,
              modelId: mid,
              size: 40,
              withBackground: true,
              backgroundColor: Colors.transparent,
            )
          : null,
      focusNode: inputFocus,
      controller: inputController,
      mediaController: mediaController,
      onConfigureReasoning: onConfigureReasoning,
      reasoningActive: isReasoningEnabled(
        (context.watch<AssistantProvider>().currentAssistant?.thinkingBudget) ??
            settings.thinkingBudget,
      ),
      supportsReasoning: (pk != null && mid != null)
          ? isReasoningModel(pk, mid)
          : false,
      onSetSearchEnabled: onSetSearchEnabled,
      onSelectBuiltInSearch: onSelectBuiltInSearch,
      onSelectSearchService: onSelectSearchService,
      onOpenSearchServices: onOpenSearchServices,
      onSend: onSend,
      loading: isLoading,
      sendButtonTooltip: sendButtonTooltip,
      hasQueuedInput: hasQueuedInput,
      queuedPreviewText: queuedPreviewText,
      onCancelQueuedInput: onCancelQueuedInput,
      showMcpButton: _shouldShowMcpButton(context, settings, a, pk, mid),
      mcpActive: _isMcpActive(context, a),
      quickPhrases: quickPhrases,
      onSelectQuickPhrase: onSelectQuickPhrase,
      // OCR is a BYOK-only feature; hosted users do not configure auxiliary
      // models in the client.
      showOcrButton:
          !settings.isHostedLoggedIn &&
          settings.ocrModelProvider != null &&
          settings.ocrModelId != null,
      onToggleOcr: onToggleOcr,
      // Platform-specific attachment and map actions.
      showMiniMapButton: isTablet,
      onOpenMiniMap: isTablet ? onOpenMiniMap : null,
      onPickCamera: canAttachImages ? (isDesktop ? null : onPickCamera) : null,
      onPickPhotos: canAttachImages ? (isDesktop ? null : onPickPhotos) : null,
      onPickPhotosOrVideo: canAttachImages
          ? (isDesktop ? null : onPickPhotosOrVideo)
          : null,
      referenceMode: referenceMode,
      maxReferenceImages: maxReferenceImages,
      maxReferenceVideos: maxReferenceVideos,
      supportsImageInput: supportsImageInput,
      isEmbeddingModel: isEmbedding,
      isImageGenerationModel: isImageGeneration,
      isVideoGenerationModel: isVideoGeneration,
      imageReferenceCandidates: imageReferenceCandidates,
      onRefreshImageReferenceCandidates: onRefreshImageReferenceCandidates,
      onUploadFiles: onUploadFiles == null
          ? null
          : () => onUploadFiles!.call(allowImages: canAttachImages),
      onSetInstructionInjectionActive: onSetInstructionInjectionActive,
      activeInstructionInjectionIds:
          conversation?.instructionInjectionIds ??
          a?.activeInstructionInjectionIds ??
          const <String>[],
      onOpenWorldBook: hasWorldBooks ? onOpenWorldBook : null,
      onLongPressLearning: onLongPressLearning,
      onClearContext: onClearContext,
      onCompressContext: onCompressContext,
      hasVideoInHistory: hasVideoInHistory,
    );
  }

  bool _isDesktopPlatform(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  void _enforceModelCapabilities(
    BuildContext context,
    SettingsProvider settings,
    AssistantProvider ap,
    Assistant? a,
    String? pk,
    String? mid,
  ) {
    if (pk == null || mid == null) return;

    final supportsTools = isToolModel(pk, mid);
    if (!supportsTools && (a?.mcpServerIds.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final aa = ap.currentAssistant;
        if (aa != null && aa.mcpServerIds.isNotEmpty) {
          ap.updateAssistant(aa.copyWith(mcpServerIds: const <String>[]));
        }
      });
    }

    final supportsReasoning = isReasoningModel(pk, mid);
    if (!supportsReasoning && a != null) {
      final enabledNow = isReasoningEnabled(
        a.thinkingBudget ?? settings.thinkingBudget,
      );
      if (enabledNow) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final aa = ap.currentAssistant;
          if (aa != null) {
            await ap.updateAssistant(aa.copyWith(thinkingBudget: 0));
          }
        });
      }
    }
  }

  bool _shouldShowMcpButton(
    BuildContext context,
    SettingsProvider settings,
    Assistant? a,
    String? pk,
    String? mid,
  ) {
    if (pk == null || mid == null) return false;
    final hasEnabledMcp = context.watch<McpProvider>().hasAnyEnabled;
    return isToolModel(pk, mid) && hasEnabledMcp;
  }

  bool _isMcpActive(BuildContext context, Assistant? a) {
    final connected = context.watch<McpProvider>().connectedServers;
    final selected = a?.mcpServerIds ?? const <String>[];
    if (selected.isEmpty || connected.isEmpty) return false;
    return connected.any((s) => selected.contains(s.id));
  }
}
