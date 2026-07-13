import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/model_override_payload_parser.dart';
import '../../../core/utils/multimodal_input_utils.dart';
import '../../../core/utils/openai_model_compat.dart';
import '../../../utils/assistant_regex.dart';
import '../../../core/models/assistant_regex.dart';
import '../controllers/stream_controller.dart' as stream_ctrl;
import '../controllers/generation_controller.dart';
import 'ask_user_interaction_service.dart';
import 'message_builder_service.dart';
import 'tool_approval_service.dart';

/// Callback types for UI updates from MessageGenerationService
typedef OnMessagesChanged = void Function();
typedef OnConversationLoadingChanged =
    void Function(String conversationId, bool loading);
typedef OnScrollToBottom = void Function();
typedef OnShowError = void Function(String message);
typedef OnShowWarning = void Function(String message);
typedef OnHapticFeedback = void Function();

const String conversationIdHeaderName = 'X-Conversation-Id';
const String _conversationIdHeaderNameLower = 'x-conversation-id';

Map<String, String>? buildConversationRequestHeaders({
  required String conversationId,
  Map<String, String>? customHeaders,
}) {
  final headers = <String, String>{
    if (customHeaders != null)
      for (final entry in customHeaders.entries)
        if (entry.key.toLowerCase() != _conversationIdHeaderNameLower)
          entry.key: entry.value,
  };
  final normalizedConversationId = conversationId.trim();
  if (normalizedConversationId.isNotEmpty) {
    headers[conversationIdHeaderName] = normalizedConversationId;
  }
  return headers.isEmpty ? null : headers;
}

/// Result of preparing a message generation
class PreparedGeneration {
  final List<Map<String, dynamic>> apiMessages;
  final List<Map<String, dynamic>> toolDefs;
  // [kelivo-hosted] MCP-only subset of [toolDefs] — the only part the hosted
  // provider branch forwards to the server; see hosted.dart.
  final List<Map<String, dynamic>> mcpToolDefs;
  final ToolCallHandler? onToolCall;
  final bool hasBuiltInSearch;
  final List<String> lastUserImagePaths;
  // [kelivo-hosted] Non-media file attachments (PDF/etc) on the last user
  // message — see `MessageBuilderService.processUserMessagesForApi`.
  final List<DocumentAttachment> lastUserDocuments;

  PreparedGeneration({
    required this.apiMessages,
    required this.toolDefs,
    required this.mcpToolDefs,
    this.onToolCall,
    required this.hasBuiltInSearch,
    required this.lastUserImagePaths,
    required this.lastUserDocuments,
  });
}

/// Service for handling message generation orchestration.
///
/// This service coordinates:
/// - Message creation (user + assistant placeholder)
/// - API message preparation with all injections
/// - Stream execution and management
/// - Reasoning state initialization
///
/// UI updates are communicated through callbacks to maintain separation.
class MessageGenerationService {
  MessageGenerationService({
    required this.chatService,
    required this.messageBuilderService,
    required this.generationController,
    required this.streamController,
    required this.contextProvider,
  });

  final ChatService chatService;
  final MessageBuilderService messageBuilderService;
  final GenerationController generationController;
  final stream_ctrl.StreamController streamController;
  final BuildContext contextProvider;

  // Callbacks for UI updates (set by home_page)
  OnMessagesChanged? onMessagesChanged;
  OnConversationLoadingChanged? onConversationLoadingChanged;
  OnScrollToBottom? onScrollToBottom;
  OnShowError? onShowError;
  OnShowWarning? onShowWarning;
  OnHapticFeedback? onHapticFeedback;

  /// Called when file processing starts.
  VoidCallback? onFileProcessingStarted;

  /// Called when file processing finishes.
  VoidCallback? onFileProcessingFinished;

  /// Check if reasoning is enabled for given budget
  bool isReasoningEnabled(int? budget) {
    if (budget == null) return true;
    if (budget == -1) return true;
    return budget >= 1024;
  }

  /// Prepare API messages with all injections applied.
  Future<PreparedGeneration> prepareApiMessagesWithInjections({
    required List<ChatMessage> messages,
    required Map<String, int> versionSelections,
    required Conversation? currentConversation,
    required SettingsProvider settings,
    required Assistant? assistant,
    required String? assistantId,
    required String providerKey,
    required String modelId,
    ToolApprovalService? approvalService,
    AskUserInteractionService? askUserService,
  }) async {
    final cfg = settings.getProviderConfig(providerKey);
    final kind = ProviderConfig.classify(
      providerKey,
      explicitType: cfg.providerType,
    );
    final includeToolMessages = switch (kind) {
      // [kelivo-hosted] kelivo-arch.md §5
      ProviderKind.openai ||
      ProviderKind.claude ||
      ProviderKind.google ||
      ProviderKind.hosted => true,
    };

    onFileProcessingStarted?.call();

    // Build API messages
    final apiMessages = messageBuilderService.buildApiMessages(
      messages: messages,
      versionSelections: versionSelections,
      currentConversation: currentConversation,
      includeToolMessages: includeToolMessages,
    );

    // Apply assistant replace-only regexes at send-time (visual stays unchanged).
    if (assistant != null && assistant.regexRules.isNotEmpty) {
      for (int i = 0; i < apiMessages.length; i++) {
        final role = (apiMessages[i]['role'] ?? '').toString();
        if (role != 'assistant') continue;
        final raw = (apiMessages[i]['content'] ?? '').toString();
        if (raw.isEmpty) continue;
        apiMessages[i]['content'] = applyAssistantRegexes(
          raw,
          assistant: assistant,
          scope: AssistantRegexScope.assistant,
          target: AssistantRegexTransformTarget.send,
        );
      }
    }

    // Process user messages (documents, OCR, templates)
    final processedUserMessages = await messageBuilderService
        .processUserMessagesForApi(apiMessages, settings, assistant);
    final lastUserImagePaths = processedUserMessages.imagePaths;
    final lastUserDocuments = processedUserMessages.documents;

    // Signal processing finished
    onFileProcessingFinished?.call();

    // Inject prompts
    messageBuilderService.injectSystemPrompt(apiMessages, assistant, modelId);
    await messageBuilderService.injectMemoryAndRecentChats(
      apiMessages,
      assistant,
      currentConversationId: currentConversation?.id,
      // [kelivo-hosted] hosted sends now get their `<memories>` block and
      // create/edit/delete_memory tool wiring injected server-side
      // (client_chat_task.py / client_memory_tools.py) using the account's
      // synced `ClientAssistant.enable_memory` flag — injecting it here too
      // would just duplicate the block; the memory *tools* themselves are
      // resolved server-side too (client_memory_tools.py), not through
      // `onToolCall` (which hosted.dart does use, for the client-device-only
      // ones — see this function's `onToolCall` construction below).
      skipMemory: kind == ProviderKind.hosted,
    );

    final hasBuiltInSearch = messageBuilderService.hasBuiltInSearch(
      settings,
      providerKey,
      modelId,
    );
    messageBuilderService.injectSearchPrompt(
      apiMessages,
      settings,
      assistant,
      hasBuiltInSearch,
    );
    await messageBuilderService.injectInstructionPrompts(
      apiMessages,
      assistantId,
    );
    await messageBuilderService.injectWorldBookPrompts(
      apiMessages,
      assistantId,
    );

    // Apply context limit and inline images
    messageBuilderService.applyContextLimit(apiMessages, assistant);
    await messageBuilderService.inlineLocalImages(apiMessages);

    // Prepare tools
    final toolDefs = generationController.buildToolDefinitions(
      settings,
      assistant,
      providerKey,
      modelId,
      hasBuiltInSearch,
    );
    final mcpToolDefs = generationController.buildMcpToolDefinitions(
      settings,
      assistant,
      providerKey,
      modelId,
    );
    // [kelivo-hosted] `toolDefs` only ever holds *client-declared* tools
    // (search/memory/local/MCP) — for hosted sends that's not the full
    // picture: the server independently decides to offer/call
    // `ask_user_input_v0`/`clipboard_tool`/`text_to_speech`/memory tools
    // based on the account's synced `ClientAssistant` row, regardless of
    // what `toolDefs` this device happened to build (e.g. an assistant with
    // no search/memory/local-tools/MCP enabled locally still gets an empty
    // `toolDefs` here even though the server may still park generation on
    // `awaiting_tool` for one of those). Gating `onToolCall` on
    // `toolDefs.isNotEmpty` left it `null` in exactly that case — hosted.dart
    // then throws on `pendingToolCalls` (`onToolCall == null`), silently
    // auto-fails the call with a synthetic error, and the model can just
    // re-ask/re-park, so the UI sits on the streaming/typing indicator
    // forever instead of ever showing e.g. the ask-user question sheet.
    final onToolCall = (toolDefs.isNotEmpty || kind == ProviderKind.hosted)
        ? generationController.buildToolCallHandler(
            settings,
            assistant,
            approvalService: approvalService,
            askUserService: askUserService,
          )
        : null;

    return PreparedGeneration(
      apiMessages: apiMessages,
      toolDefs: toolDefs,
      mcpToolDefs: mcpToolDefs,
      onToolCall: onToolCall,
      hasBuiltInSearch: hasBuiltInSearch,
      lastUserImagePaths: lastUserImagePaths,
      lastUserDocuments: lastUserDocuments,
    );
  }

  /// Create user message from input data.
  Future<ChatMessage> createUserMessage({
    required String conversationId,
    required ChatInputData input,
    required Assistant? assistant,
  }) async {
    return chatService.addMessage(
      conversationId: conversationId,
      role: 'user',
      content: MessageGenerationService.buildPersistedUserMessageContent(
        input,
        assistant: assistant,
      ),
    );
  }

  /// Build the persisted content string for a user message.
  static String buildPersistedUserMessageContent(
    ChatInputData input, {
    required Assistant? assistant,
  }) {
    final content = input.text.trim();
    final imageMarkers = input.imagePaths.map((p) => '\n[image:$p]').join();
    final docMarkers = input.documents
        .map((d) => '\n[file:${d.path}|${d.fileName}|${d.mime}]')
        .join();

    final processedUserText = applyAssistantRegexes(
      content,
      assistant: assistant,
      scope: AssistantRegexScope.user,
      target: AssistantRegexTransformTarget.persist,
    );

    return processedUserText + imageMarkers + docMarkers;
  }

  /// Create assistant message placeholder.
  Future<ChatMessage> createAssistantPlaceholder({
    required String conversationId,
    required String modelId,
    required String providerKey,
    String? groupId,
    int version = 0,
  }) async {
    return chatService.addMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
      groupId: groupId,
      version: version,
    );
  }

  /// Initialize reasoning state for a message if reasoning is enabled.
  Future<void> initializeReasoningState({
    required String messageId,
    required bool enableReasoning,
  }) async {
    if (enableReasoning) {
      final rd = stream_ctrl.ReasoningData();
      streamController.reasoning[messageId] = rd;
      await chatService.updateMessage(
        messageId,
        reasoningStartAt: DateTime.now(),
      );
    }
  }

  /// Build GenerationContext for streaming.
  stream_ctrl.GenerationContext buildGenerationContext({
    required ChatMessage assistantMessage,
    required PreparedGeneration prepared,
    required List<String> userImagePaths,
    required List<DocumentAttachment> userDocuments,
    required bool allowImagesApiRouting,
    required String providerKey,
    required String modelId,
    required Assistant? assistant,
    required SettingsProvider settings,
    required bool supportsReasoning,
    required bool enableReasoning,
    required bool generateTitleOnFinish,
    String? regenerateOfServerMessageId,
    String? imageGenSize,
    int? imageGenCount,
    int? videoDuration,
    String? videoAspectRatio,
    String? videoResolution,
    bool? videoExtendMode,
  }) {
    final bool ocrActive =
        settings.ocrEnabled &&
        settings.ocrModelProvider != null &&
        settings.ocrModelId != null;

    return stream_ctrl.GenerationContext(
      assistantMessage: assistantMessage,
      apiMessages: prepared.apiMessages,
      userImagePaths: userImagePaths,
      userDocuments: userDocuments,
      allowImagesApiRouting: allowImagesApiRouting,
      providerKey: providerKey,
      modelId: modelId,
      assistant: assistant,
      settings: settings,
      config: settings.getProviderConfig(providerKey),
      toolDefs: prepared.toolDefs,
      mcpToolDefs: prepared.mcpToolDefs,
      onToolCall: prepared.onToolCall,
      extraHeaders: buildConversationRequestHeaders(
        conversationId: assistantMessage.conversationId,
        customHeaders: generationController.buildCustomHeaders(assistant),
      ),
      extraBody: _mergeImageGenOptions(
        generationController.buildCustomBody(assistant),
        imageGenSize: imageGenSize,
        imageGenCount: imageGenCount,
        videoDuration: videoDuration,
        videoAspectRatio: videoAspectRatio,
        videoResolution: videoResolution,
        videoExtendMode: videoExtendMode,
      ),
      supportsReasoning: supportsReasoning,
      enableReasoning: enableReasoning,
      streamOutput: assistant?.streamOutput ?? true,
      ocrActive: ocrActive,
      generateTitleOnFinish: generateTitleOnFinish,
      // [kelivo-hosted] kelivo-arch.md §5/§6
      conversationId: assistantMessage.conversationId,
      regenerateOfServerMessageId: regenerateOfServerMessageId,
    );
  }

  /// Merge UI-selected image generation options (size/n) into the custom
  /// request body, without dropping any assistant-configured custom body
  /// entries.
  Map<String, dynamic>? _mergeImageGenOptions(
    Map<String, dynamic>? customBody, {
    String? imageGenSize,
    int? imageGenCount,
    int? videoDuration,
    String? videoAspectRatio,
    String? videoResolution,
    bool? videoExtendMode,
  }) {
    if (imageGenSize == null &&
        imageGenCount == null &&
        videoDuration == null &&
        videoAspectRatio == null &&
        videoResolution == null &&
        videoExtendMode == null) {
      return customBody;
    }
    final merged = <String, dynamic>{...?customBody};
    if (imageGenSize != null) merged['size'] = imageGenSize;
    if (imageGenCount != null) merged['n'] = imageGenCount;
    if (videoDuration != null) merged['video_duration'] = videoDuration;
    if (videoAspectRatio != null) {
      merged['video_aspect_ratio'] = videoAspectRatio;
    }
    if (videoResolution != null) merged['video_resolution'] = videoResolution;
    if (videoExtendMode != null) merged['video_extend_mode'] = videoExtendMode;
    return merged;
  }

  /// Get current model and provider, preferring the conversation's own
  /// override, then the assistant's default, then the global default.
  ({String? providerKey, String? modelId}) getModelConfig(
    SettingsProvider settings,
    Assistant? assistant, [
    Conversation? conversation,
  ]) {
    return (
      providerKey:
          conversation?.chatModelProvider ??
          assistant?.chatModelProvider ??
          settings.currentModelProvider,
      modelId:
          conversation?.chatModelId ??
          assistant?.chatModelId ??
          settings.currentModelId,
    );
  }

  /// Calculate version info for regeneration.
  ({String? targetGroupId, int nextVersion, int lastKeep})
  calculateRegenerationVersioning({
    required ChatMessage message,
    required List<ChatMessage> messages,
    required bool assistantAsNewReply,
  }) {
    final idx = messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) {
      return (targetGroupId: null, nextVersion: 0, lastKeep: -1);
    }

    String? targetGroupId;
    int nextVersion = 0;
    int lastKeep;

    if (message.role == 'assistant') {
      lastKeep = idx;
      if (assistantAsNewReply) {
        targetGroupId = null;
        nextVersion = 0;
      } else {
        targetGroupId = message.groupId ?? message.id;
        int maxVer = -1;
        for (final m in messages) {
          final gid = (m.groupId ?? m.id);
          if (gid == targetGroupId) {
            if (m.version > maxVer) maxVer = m.version;
          }
        }
        nextVersion = maxVer + 1;
      }
    } else {
      // User message
      final userGroupId = message.groupId ?? message.id;
      int userFirst = -1;
      for (int i = 0; i < messages.length; i++) {
        final gid0 = (messages[i].groupId ?? messages[i].id);
        if (gid0 == userGroupId) {
          userFirst = i;
          break;
        }
      }
      if (userFirst < 0) userFirst = idx;

      int aid = -1;
      for (int i = userFirst + 1; i < messages.length; i++) {
        if (messages[i].role == 'assistant') {
          aid = i;
          break;
        }
      }

      if (aid >= 0) {
        lastKeep = aid;
        targetGroupId = messages[aid].groupId ?? messages[aid].id;
        int maxVer = -1;
        for (final m in messages) {
          final gid = (m.groupId ?? m.id);
          if (gid == targetGroupId) {
            if (m.version > maxVer) maxVer = m.version;
          }
        }
        nextVersion = maxVer + 1;
      } else {
        lastKeep = userFirst;
        targetGroupId = null;
        nextVersion = 0;
      }
    }

    return (
      targetGroupId: targetGroupId,
      nextVersion: nextVersion,
      lastKeep: lastKeep,
    );
  }

  /// Remove trailing messages after regeneration cut point.
  @visibleForTesting
  static List<String> collectTrailingMessageIdsForRemoval({
    required List<ChatMessage> messages,
    required int lastKeep,
    required String? targetGroupId,
  }) {
    if (lastKeep >= messages.length - 1) {
      return const [];
    }

    final keepGroups = <String>{};
    for (int i = 0; i <= lastKeep && i < messages.length; i++) {
      keepGroups.add(messages[i].groupId ?? messages[i].id);
    }
    if (targetGroupId != null) keepGroups.add(targetGroupId);

    final removeIds = <String>[];
    for (final message in messages.sublist(lastKeep + 1)) {
      final groupId = message.groupId ?? message.id;
      if (!keepGroups.contains(groupId)) {
        removeIds.add(message.id);
      }
    }
    return removeIds;
  }

  /// Remove trailing messages after regeneration cut point.
  Future<List<String>> removeTrailingMessages({
    required List<ChatMessage> messages,
    required int lastKeep,
    required String? targetGroupId,
  }) async {
    final removeIds = collectTrailingMessageIdsForRemoval(
      messages: messages,
      lastKeep: lastKeep,
      targetGroupId: targetGroupId,
    );

    for (final id in removeIds) {
      try {
        await chatService.deleteMessage(id);
      } catch (_) {}
      streamController.reasoning.remove(id);
      streamController.toolParts.remove(id);
      streamController.reasoningSegments.remove(id);
    }

    return removeIds;
  }

  bool _shouldIncludeAudioForProvider(
    SettingsProvider settings, {
    required String providerKey,
    required String modelId,
  }) {
    final cfg = settings.getProviderConfig(providerKey);
    if (ProviderConfig.classify(providerKey, explicitType: cfg.providerType) !=
        ProviderKind.openai) {
      return false;
    }
    final override = ModelOverridePayloadParser.modelOverride(
      cfg.modelOverrides,
      modelId,
    );
    final upstreamModelId = resolveApiModelIdOverride(override, modelId);
    return isLongCatOmniModelId(upstreamModelId);
  }

  bool supportsAudioAttachmentsForProvider(
    SettingsProvider settings, {
    required String providerKey,
    required String modelId,
  }) {
    return _shouldIncludeAudioForProvider(
      settings,
      providerKey: providerKey,
      modelId: modelId,
    );
  }

  String _effectiveAttachmentMime(DocumentAttachment attachment) {
    return resolveDocumentAttachmentMime(attachment);
  }

  bool inputContainsAudioAttachments(ChatInputData input) {
    for (final attachment in input.documents) {
      if (isAudioMime(_effectiveAttachmentMime(attachment))) {
        return true;
      }
    }
    return false;
  }

  bool apiMessagesContainAudioAttachments(List<Map<String, dynamic>> messages) {
    for (final message in messages) {
      if ((message['role'] ?? '').toString() != 'user') continue;
      final parsed = messageBuilderService.parseInputFromRaw(
        (message['content'] ?? '').toString(),
      );
      if (parsed.documents.any(
        (attachment) => isAudioMime(_effectiveAttachmentMime(attachment)),
      )) {
        return true;
      }
    }
    return false;
  }

  List<String> _filterMediaPathsForProvider(
    List<String> paths, {
    required bool includeAudio,
  }) {
    return paths
        .where((path) {
          final mime = inferMediaMimeFromSource(
            path,
            fallbackMime: 'image/png',
          );
          if (isAudioMime(mime)) return includeAudio;
          return isImageMime(mime) || isVideoMime(mime);
        })
        .toList(growable: false);
  }

  /// Build user image paths considering OCR mode.
  List<String> buildUserImagePaths({
    required ChatInputData? input,
    required List<String> lastUserImagePaths,
    required SettingsProvider settings,
    required String providerKey,
    required String modelId,
  }) {
    final bool ocrActive =
        settings.ocrEnabled &&
        settings.ocrModelProvider != null &&
        settings.ocrModelId != null;

    final includeAudio = _shouldIncludeAudioForProvider(
      settings,
      providerKey: providerKey,
      modelId: modelId,
    );

    if (input != null) {
      final currentMediaPaths = <String>[];
      for (final d in input.documents) {
        final effectiveMime = _effectiveAttachmentMime(d);
        if (isVideoMime(effectiveMime) ||
            (includeAudio && isAudioMime(effectiveMime))) {
          currentMediaPaths.add(d.path);
        }
      }
      return _filterMediaPathsForProvider(<String>[
        if (!ocrActive) ...input.imagePaths,
        ...currentMediaPaths,
      ], includeAudio: includeAudio);
    }

    return _filterMediaPathsForProvider(
      lastUserImagePaths
          .where((path) {
            if (!ocrActive) return true;
            return !isImageMime(
              inferMediaMimeFromSource(path, fallbackMime: 'image/png'),
            );
          })
          .toList(growable: false),
      includeAudio: includeAudio,
    );
  }

  /// [kelivo-hosted] Mirrors [buildUserImagePaths] for non-media file
  /// attachments — [input] is set for a fresh send (today's picked files),
  /// null for a regenerate/resend, where [lastUserDocuments] (reconstructed
  /// from history, see `PreparedGeneration.lastUserDocuments`) is used
  /// instead. Only `hosted.dart` reads this (native file content parts) —
  /// every other provider still gets its file content the existing way,
  /// inlined as text by `processUserMessagesForApi`.
  List<DocumentAttachment> buildUserDocuments({
    required ChatInputData? input,
    required List<DocumentAttachment> lastUserDocuments,
  }) {
    if (input != null) {
      return input.documents
          .where((d) {
            final mime = _effectiveAttachmentMime(d);
            return !isVideoMime(mime) && !isAudioMime(mime);
          })
          .toList(growable: false);
    }
    return lastUserDocuments;
  }
}
