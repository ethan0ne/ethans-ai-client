import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/client_backend_session.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/logging/flutter_logger.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/widgets/chat_message_widget.dart' show ToolUIPart;
import '../widgets/file_processing_indicator.dart' show FileProcessingStatus;
import '../services/message_builder_service.dart';
import '../services/message_generation_service.dart';
import '../services/chat_suggestion_service.dart';
import 'chat_actions.dart';
import 'chat_controller.dart';
import 'generation_controller.dart';
import 'stream_controller.dart' as stream_ctrl;

enum CompressContextLimitMode { start, recent, unlimited }

class CompressContextOptions {
  const CompressContextOptions({required this.mode, this.maxChars});

  static const int defaultMaxChars = 6000;

  final CompressContextLimitMode mode;
  final int? maxChars;
}

String buildCompressContextContent(
  String joined,
  CompressContextOptions options,
) {
  if (options.mode == CompressContextLimitMode.unlimited) return joined;
  final maxChars = options.maxChars ?? CompressContextOptions.defaultMaxChars;
  if (maxChars <= 0 || joined.length <= maxChars) return joined;
  return switch (options.mode) {
    CompressContextLimitMode.start => joined.substring(0, maxChars),
    CompressContextLimitMode.recent => joined.substring(
      joined.length - maxChars,
    ),
    CompressContextLimitMode.unlimited => joined,
  };
}

String buildConversationTextForCompression(List<ChatMessage> messages) {
  return messages
      .where((m) => m.content.trim().isNotEmpty)
      .map(
        (m) => '${m.role == "assistant" ? "Assistant" : "User"}: ${m.content}',
      )
      .join('\n\n');
}

List<ChatMessage> selectForkConversationMessages({
  required List<ChatMessage> messages,
  required ChatMessage targetMessage,
  Map<String, int> versionSelections = const <String, int>{},
}) {
  final Map<String, List<ChatMessage>> byGroup = <String, List<ChatMessage>>{};
  final List<String> groupOrder = <String>[];
  for (final message in messages) {
    final groupId = message.groupId ?? message.id;
    byGroup
        .putIfAbsent(groupId, () {
          groupOrder.add(groupId);
          return <ChatMessage>[];
        })
        .add(message);
  }

  final targetGroup = (targetMessage.groupId ?? targetMessage.id);
  final targetOrderIndex = groupOrder.indexOf(targetGroup);
  if (targetOrderIndex < 0) return const <ChatMessage>[];

  final selected = <ChatMessage>[];
  for (final groupId in groupOrder.take(targetOrderIndex + 1)) {
    final versions = byGroup[groupId]!
      ..sort((a, b) => a.version.compareTo(b.version));
    final targetVersionIndex = versions.indexWhere(
      (message) => message.id == targetMessage.id,
    );
    if (targetVersionIndex >= 0) {
      selected.add(versions[targetVersionIndex]);
      continue;
    }

    final selectedVersion = versionSelections[groupId];
    final selectedIndex =
        selectedVersion != null &&
            selectedVersion >= 0 &&
            selectedVersion < versions.length
        ? selectedVersion
        : versions.length - 1;
    selected.add(versions[selectedIndex]);
  }
  return selected;
}

class BatchDeleteGroupPlan {
  const BatchDeleteGroupPlan({
    required this.groupId,
    required this.versionsBefore,
    required this.deletedMessageIds,
    required this.nextVersionSelection,
  });

  final String groupId;
  final List<ChatMessage> versionsBefore;
  final Set<String> deletedMessageIds;
  final int? nextVersionSelection;
}

class BatchDeletePlan {
  const BatchDeletePlan({
    required this.groups,
    required this.nextVersionSelections,
    required this.clearedVersionSelectionGroupIds,
  });

  static const empty = BatchDeletePlan(
    groups: <String, BatchDeleteGroupPlan>{},
    nextVersionSelections: <String, int>{},
    clearedVersionSelectionGroupIds: <String>{},
  );

  final Map<String, BatchDeleteGroupPlan> groups;
  final Map<String, int> nextVersionSelections;
  final Set<String> clearedVersionSelectionGroupIds;

  bool get isEmpty => groups.isEmpty;

  Set<String> get deletedMessageIds => {
    for (final group in groups.values) ...group.deletedMessageIds,
  };
}

/// ViewModel for the home page, combining actions + services.
///
/// This ViewModel:
/// - Holds all page state (conversation, messages, loading, etc.)
/// - Calls ChatActions for business operations
/// - Notifies UI of state changes via ChangeNotifier
/// - Handles conversation switching/creation
///
/// UI layer only needs to:
/// - Listen to this ViewModel
/// - Call simple methods like sendMessage(), regenerate(), etc.
/// - Handle UI-specific concerns (snackbars, scrolling, animations)
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required this._chatService,
    required this._messageBuilderService,
    required this._messageGenerationService,
    required this._generationController,
    required this._streamController,
    required this._chatController,
    required this._contextProvider,
    required this.getTitleForLocale,
  }) {
    // Initialize ChatActions
    _chatActions = ChatActions(
      chatService: _chatService,
      chatController: _chatController,
      streamController: _streamController,
      generationController: _generationController,
      messageGenerationService: _messageGenerationService,
      contextProvider: _contextProvider,
      viewModel: this,
    );

    // Wire up callbacks
    _chatActions.onMessagesChanged = _onMessagesChanged;
    _chatActions.onLoadingChanged = _onLoadingChanged;
    _chatActions.onContentUpdated = _onContentUpdated;
    _chatActions.onStreamError = _onStreamError;
    _chatActions.onMaybeGenerateTitle = _onMaybeGenerateTitle;
    _chatActions.onMaybeGenerateSummary = _onMaybeGenerateSummary;
    _chatActions.onMaybeGenerateSuggestions = _onMaybeGenerateSuggestions;
    _chatActions.onStreamFinished = _onStreamFinished;
    _chatActions.onAssistantMessageFinished = _onAssistantMessageFinished;
    _chatActions.onFileProcessingStarted = _onFileProcessingStarted;
    _chatActions.onFileProcessingFinished = _onFileProcessingFinished;
    _chatActions.onFileProcessingProgress = _onFileProcessingProgress;
  }

  // ============================================================================
  // Dependencies
  // ============================================================================

  final ChatService _chatService;
  // ignore: unused_field - Reserved for future use (direct message building)
  final MessageBuilderService _messageBuilderService;
  // ignore: unused_field - Reserved for future use (direct generation control)
  final MessageGenerationService _messageGenerationService;
  final GenerationController _generationController;
  final stream_ctrl.StreamController _streamController;
  final ChatController _chatController;
  final BuildContext _contextProvider;
  final ChatSuggestionService _suggestionService =
      const ChatSuggestionService();
  late final ChatActions _chatActions;
  QueuedChatInput? _queuedInput;
  bool _isDrainingQueuedInput = false;

  /// Function to get localized title
  final String Function(BuildContext context) getTitleForLocale;

  // ============================================================================
  // Callbacks for UI (set by HomePage)
  // ============================================================================

  /// Called when an error occurs (UI should show snackbar).
  void Function(String error)? onError;

  /// Called when a warning occurs (UI should show snackbar).
  void Function(String warning)? onWarning;

  /// Called when streaming finishes (UI may show notification).
  VoidCallback? onStreamFinished;

  /// Called when a successful assistant reply is finalized.
  void Function(ChatMessage message)? onAssistantMessageFinished;

  /// Called to schedule inline image sanitization.
  void Function(String messageId, String content, {bool immediate})?
  onScheduleImageSanitize;

  /// Called when scrolling to bottom is needed.
  VoidCallback? onScrollToBottom;

  /// Called for haptic feedback.
  VoidCallback? onHapticFeedback;

  /// Called when conversation is successfully switched (for animations).
  VoidCallback? onConversationSwitched;

  // ============================================================================
  // State Getters (delegate to ChatController)
  // ============================================================================

  Conversation? get currentConversation => _chatController.currentConversation;
  List<ChatMessage> get messages => _chatController.messages;
  Map<String, int> get versionSelections => _chatController.versionSelections;
  Set<String> get loadingConversationIds =>
      _chatController.loadingConversationIds;
  Map<String, StreamSubscription<dynamic>> get conversationStreams =>
      _chatController.conversationStreams;

  /// StreamController state getters
  Map<String, stream_ctrl.ReasoningData> get reasoning =>
      _streamController.reasoning;
  Map<String, List<stream_ctrl.ReasoningSegmentData>> get reasoningSegments =>
      _streamController.reasoningSegments;
  Map<String, stream_ctrl.ContentSplitData> get contentSplits =>
      _streamController.contentSplits;
  Map<String, List<ToolUIPart>> get toolParts => _streamController.toolParts;

  /// Whether the current conversation is actively generating.
  bool get isCurrentConversationLoading =>
      _chatController.isCurrentConversationLoading;

  QueuedChatInput? get currentQueuedInput {
    final cid = currentConversation?.id;
    final queued = _queuedInput;
    if (cid == null || queued == null || queued.conversationId != cid) {
      return null;
    }
    return queued;
  }

  final ValueNotifier<FileProcessingStatus> isProcessingFiles =
      ValueNotifier<FileProcessingStatus>(FileProcessingStatus.idle);

  // ============================================================================
  // Internal Callbacks
  // ============================================================================

  void _onMessagesChanged() {
    _chatController.invalidateCache();
    _chatController.refreshLoadedMessageCount();
    notifyListeners();
  }

  void _onLoadingChanged(String conversationId, bool loading) {
    notifyListeners();
    if (!loading) {
      unawaited(_drainQueuedInputIfReady(conversationId));
    }
  }

  void _onContentUpdated(String messageId, String content, int totalTokens) {
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      messages[index] = messages[index].copyWith(
        content: content,
        totalTokens: totalTokens,
      );
      _chatController.invalidateCache();
      // NOTE: Do NOT call notifyListeners() here!
      // Streaming content updates are now handled by StreamingContentNotifier
      // via ValueListenableBuilder, which only rebuilds the streaming message widget.
      // Calling notifyListeners() here would trigger a full page rebuild and cause lag.
    }
  }

  void _onStreamError(String error) {
    onError?.call(error);
  }

  void _onMaybeGenerateTitle(String conversationId) {
    // Trigger title generation asynchronously
    _maybeGenerateTitleFor(conversationId);
  }

  void _onMaybeGenerateSummary(String conversationId) {
    // Trigger summary generation asynchronously
    _maybeGenerateSummaryFor(conversationId);
  }

  void _onMaybeGenerateSuggestions(String conversationId) {
    _maybeGenerateSuggestionsFor(conversationId);
  }

  void _onStreamFinished() {
    onStreamFinished?.call();
  }

  void _onAssistantMessageFinished(ChatMessage message) {
    onAssistantMessageFinished?.call(message);
  }

  void _onFileProcessingStarted() {
    isProcessingFiles.value = const FileProcessingStatus(active: true);
  }

  void _onFileProcessingFinished() {
    isProcessingFiles.value = FileProcessingStatus.idle;
  }

  void _onFileProcessingProgress(int current, int total) {
    isProcessingFiles.value = FileProcessingStatus(
      active: true,
      progress: total > 0 ? current / total : null,
    );
  }

  // ============================================================================
  // Public Methods - Message Actions
  // ============================================================================

  /// Send a new message or queue it if the current conversation is busy.
  Future<ChatInputSubmissionResult> sendMessage(ChatInputData input) async {
    final content = input.text.trim();
    if (content.isEmpty &&
        input.imagePaths.isEmpty &&
        input.documents.isEmpty) {
      return ChatInputSubmissionResult.rejected;
    }

    final conversation = currentConversation;
    if (conversation == null) {
      // Create new conversation first
      await createNewConversation();
    }

    if (currentConversation == null) {
      onError?.call('no_conversation');
      return ChatInputSubmissionResult.rejected;
    }

    final activeConversation = currentConversation!;
    if (_chatController.isConversationLoading(activeConversation.id)) {
      if (_queuedInput != null) {
        return ChatInputSubmissionResult.rejected;
      }
      _queuedInput = QueuedChatInput(
        conversationId: activeConversation.id,
        input: _cloneInput(input),
      );
      notifyListeners();
      return ChatInputSubmissionResult.queued;
    }

    final success = await _sendMessageToConversation(input, activeConversation);
    return success
        ? ChatInputSubmissionResult.sent
        : ChatInputSubmissionResult.rejected;
  }

  ChatInputData? cancelCurrentQueuedInput() {
    final queued = currentQueuedInput;
    if (queued == null || _isDrainingQueuedInput) return null;
    _queuedInput = null;
    notifyListeners();
    return _cloneInput(queued.input);
  }

  Future<bool> _sendMessageToConversation(
    ChatInputData input,
    Conversation conversation,
  ) async {
    final content = input.text.trim();
    if (content.isEmpty &&
        input.imagePaths.isEmpty &&
        input.documents.isEmpty) {
      return false;
    }

    _chatActions.onScheduleImageSanitize = onScheduleImageSanitize;

    await _clearSuggestionsFor(conversation.id);

    if (input.documents.isNotEmpty) {
      isProcessingFiles.value = const FileProcessingStatus(active: true);
    }

    onHapticFeedback?.call();
    onScrollToBottom?.call();

    final result = await _chatActions.sendMessage(
      input: input,
      conversation: conversation,
    );

    if (!result.success) {
      if (result.errorMessage == 'no_model') {
        onWarning?.call('no_model');
      } else if (result.errorMessage != 'empty_input') {
        onError?.call(result.errorMessage ?? 'unknown_error');
      }
      return false;
    }

    onScrollToBottom?.call();
    return true;
  }

  ChatInputData _cloneInput(ChatInputData input) {
    return ChatInputData(
      text: input.text,
      imagePaths: List<String>.of(input.imagePaths),
      documents: List<DocumentAttachment>.of(input.documents),
      allowImagesApiRouting: input.allowImagesApiRouting,
    );
  }

  Future<void> _drainQueuedInputIfReady(String conversationId) async {
    if (_isDrainingQueuedInput) return;
    final queued = _queuedInput;
    final conversation = currentConversation;
    if (queued == null || conversation == null) return;
    if (queued.conversationId != conversationId ||
        conversation.id != conversationId) {
      return;
    }
    if (_chatController.isConversationLoading(conversationId)) return;

    _isDrainingQueuedInput = true;
    _queuedInput = null;
    notifyListeners();

    final input = queued.input;
    final success = await _sendMessageToConversation(input, conversation);
    if (!success) {
      _queuedInput = queued;
    }

    _isDrainingQueuedInput = false;
    notifyListeners();
  }

  /// Regenerate response at a specific message.
  Future<bool> regenerateAtMessage(
    ChatMessage message, {
    bool assistantAsNewReply = false,
    bool allowImagesApiRouting = true,
    int? videoDuration,
    String? videoAspectRatio,
    String? videoResolution,
    bool? videoExtendMode,
    String? imageGenSize,
    int? imageGenCount,
  }) async {
    final conversation = currentConversation;
    if (conversation == null) {
      return false;
    }

    // Set up image sanitization callback before regenerating
    _chatActions.onScheduleImageSanitize = onScheduleImageSanitize;

    onHapticFeedback?.call();
    await _clearSuggestionsFor(conversation.id);

    final result = await _chatActions.regenerateAtMessage(
      message: message,
      conversation: conversation,
      assistantAsNewReply: assistantAsNewReply,
      allowImagesApiRouting: allowImagesApiRouting,
      videoDuration: videoDuration,
      videoAspectRatio: videoAspectRatio,
      videoResolution: videoResolution,
      videoExtendMode: videoExtendMode,
      imageGenSize: imageGenSize,
      imageGenCount: imageGenCount,
    );

    if (!result.success) {
      if (result.errorMessage == 'no_model') {
        onWarning?.call('no_model');
      } else {
        onError?.call(result.errorMessage ?? 'unknown_error');
      }
      return false;
    }

    return true;
  }

  Future<bool> continueAssistantMessageAfterToolAnswer(
    ChatMessage message, {
    bool allowImagesApiRouting = true,
  }) async {
    final conversation = currentConversation;
    if (conversation == null) {
      return false;
    }

    _chatActions.onScheduleImageSanitize = onScheduleImageSanitize;
    await _clearSuggestionsFor(conversation.id);

    final result = await _chatActions.continueAssistantMessageAfterToolAnswer(
      message: message,
      conversation: conversation,
      allowImagesApiRouting: allowImagesApiRouting,
    );

    if (!result.success) {
      if (result.errorMessage == 'no_model') {
        onWarning?.call('no_model');
      } else {
        onError?.call(result.errorMessage ?? 'unknown_error');
      }
      return false;
    }

    return true;
  }

  /// Cancel the active streaming.
  Future<void> cancelStreaming() async {
    await _chatActions.cancelStreaming(currentConversation);
  }

  /// Delete a message and adjust version selections.
  ///
  /// Returns the list of message IDs to clean up UI state for.
  /// The UI layer should handle confirmation dialog before calling this.
  Future<void> deleteMessage({
    required ChatMessage message,
    required Map<String, List<ChatMessage>> byGroup,
  }) async {
    final gid = (message.groupId ?? message.id);
    final versBefore = List<ChatMessage>.of(
      byGroup[gid] ?? const <ChatMessage>[],
    )..sort((a, b) => a.version.compareTo(b.version));
    await _deleteMessageVersions(
      gid: gid,
      versionsBefore: versBefore,
      deletedMessageIds: <String>{message.id},
    );
  }

  Future<void> deleteAllMessageVersions({
    required ChatMessage message,
    required Map<String, List<ChatMessage>> byGroup,
  }) async {
    final gid = (message.groupId ?? message.id);
    final versBefore = List<ChatMessage>.of(
      byGroup[gid] ?? const <ChatMessage>[],
    )..sort((a, b) => a.version.compareTo(b.version));
    await _deleteMessageVersions(
      gid: gid,
      versionsBefore: versBefore,
      deletedMessageIds: versBefore.map((m) => m.id).toSet(),
    );
  }

  @visibleForTesting
  static int? computeNextVersionSelection({
    required List<ChatMessage> versionsBefore,
    required Set<String> deletedMessageIds,
    required int? oldSelection,
  }) {
    final sorted = List<ChatMessage>.of(versionsBefore)
      ..sort((a, b) => a.version.compareTo(b.version));
    if (sorted.isEmpty) return null;

    final remainingCount = sorted
        .where((message) => !deletedMessageIds.contains(message.id))
        .length;
    if (remainingCount <= 0) return null;

    int newSelection = oldSelection ?? (sorted.length - 1);
    final deletedIndices = <int>[];
    for (int i = 0; i < sorted.length; i++) {
      if (deletedMessageIds.contains(sorted[i].id)) {
        deletedIndices.add(i);
      }
    }

    for (final deletedIndex in deletedIndices) {
      if (deletedIndex < newSelection) {
        newSelection -= 1;
      } else if (deletedIndex == newSelection) {
        newSelection = newSelection > 0 ? newSelection - 1 : 0;
      }
    }

    if (newSelection < 0) return 0;
    if (newSelection > remainingCount - 1) return remainingCount - 1;
    return newSelection;
  }

  @visibleForTesting
  static BatchDeletePlan buildBatchDeletePlan({
    required List<ChatMessage> messages,
    required Set<String> selectedMessageIds,
    required Map<String, int> versionSelections,
    bool deleteAllVersions = false,
  }) {
    if (selectedMessageIds.isEmpty || messages.isEmpty) {
      return BatchDeletePlan.empty;
    }

    final byGroup = <String, List<ChatMessage>>{};
    final deletedByGroup = <String, Set<String>>{};
    for (final message in messages) {
      final groupId = message.groupId ?? message.id;
      byGroup.putIfAbsent(groupId, () => <ChatMessage>[]).add(message);
      if (selectedMessageIds.contains(message.id)) {
        deletedByGroup.putIfAbsent(groupId, () => <String>{});
        if (!deleteAllVersions) {
          deletedByGroup[groupId]!.add(message.id);
        }
      }
    }

    if (deletedByGroup.isEmpty) return BatchDeletePlan.empty;

    final groups = <String, BatchDeleteGroupPlan>{};
    final nextVersionSelections = <String, int>{};
    final clearedVersionSelectionGroupIds = <String>{};

    for (final entry in deletedByGroup.entries) {
      final groupId = entry.key;
      final versionsBefore = List<ChatMessage>.of(
        byGroup[groupId] ?? const <ChatMessage>[],
      )..sort((a, b) => a.version.compareTo(b.version));
      final deletedMessageIds = deleteAllVersions
          ? versionsBefore.map((message) => message.id).toSet()
          : Set<String>.of(entry.value);
      final oldSelection =
          versionSelections[groupId] ??
          (versionsBefore.isNotEmpty ? versionsBefore.length - 1 : 0);
      final nextVersionSelection = computeNextVersionSelection(
        versionsBefore: versionsBefore,
        deletedMessageIds: deletedMessageIds,
        oldSelection: oldSelection,
      );

      groups[groupId] = BatchDeleteGroupPlan(
        groupId: groupId,
        versionsBefore: versionsBefore,
        deletedMessageIds: deletedMessageIds,
        nextVersionSelection: nextVersionSelection,
      );

      if (nextVersionSelection == null) {
        clearedVersionSelectionGroupIds.add(groupId);
      } else {
        nextVersionSelections[groupId] = nextVersionSelection;
      }
    }

    return BatchDeletePlan(
      groups: groups,
      nextVersionSelections: nextVersionSelections,
      clearedVersionSelectionGroupIds: clearedVersionSelectionGroupIds,
    );
  }

  Future<void> deleteMessages({
    required Set<String> messageIds,
    bool deleteAllVersions = false,
  }) async {
    final conversation = currentConversation;
    if (conversation == null || messageIds.isEmpty) return;

    await _clearSuggestionsFor(conversation.id);

    final allMessages = _chatService.getMessagesRange(
      conversation.id,
      start: 0,
      limit: _chatService.getMessageCount(conversation.id),
    );
    final plan = buildBatchDeletePlan(
      messages: allMessages,
      selectedMessageIds: messageIds,
      versionSelections: _chatController.versionSelections,
      deleteAllVersions: deleteAllVersions,
    );
    if (plan.isEmpty) return;

    for (final id in plan.deletedMessageIds) {
      _streamController.clearMessageState(id);
    }

    for (final groupId in plan.clearedVersionSelectionGroupIds) {
      _chatController.versionSelections.remove(groupId);
      await _chatService.clearSelectedVersion(conversation.id, groupId);
    }
    for (final entry in plan.nextVersionSelections.entries) {
      _chatController.versionSelections[entry.key] = entry.value;
      await _chatService.setSelectedVersion(
        conversation.id,
        entry.key,
        entry.value,
      );
    }

    final messagesToDelete = allMessages
        .where((message) => plan.deletedMessageIds.contains(message.id))
        .toList();
    for (final message in messagesToDelete) {
      await _chatService.deleteMessage(message.id);
    }

    _chatController.reloadMessages();
    notifyListeners();
  }

  Future<void> _deleteMessageVersions({
    required String gid,
    required List<ChatMessage> versionsBefore,
    required Set<String> deletedMessageIds,
  }) async {
    if (deletedMessageIds.isEmpty) return;

    final cid = currentConversation?.id;
    if (cid != null) {
      await _clearSuggestionsFor(cid);
    }

    final oldSel =
        versionSelections[gid] ??
        (versionsBefore.isNotEmpty ? versionsBefore.length - 1 : 0);
    final newSel = computeNextVersionSelection(
      versionsBefore: versionsBefore,
      deletedMessageIds: deletedMessageIds,
      oldSelection: oldSel,
    );

    // Clean up message UI state
    for (final id in deletedMessageIds) {
      _streamController.clearMessageState(id);
    }

    // Adjust selected version index for this group
    if (newSel == null) {
      _chatController.versionSelections.remove(gid);
    } else {
      _chatController.versionSelections[gid] = newSel;
    }

    if (currentConversation != null) {
      try {
        if (newSel == null) {
          await _chatService.clearSelectedVersion(currentConversation!.id, gid);
        } else {
          await _chatService.setSelectedVersion(
            currentConversation!.id,
            gid,
            newSel,
          );
        }
      } catch (_) {}
    }

    final messagesToDelete = versionsBefore
        .where((message) => deletedMessageIds.contains(message.id))
        .toList();
    for (final message in messagesToDelete) {
      await _chatService.deleteMessage(message.id);
    }

    // Reload messages
    _chatController.reloadMessages();
    notifyListeners();
  }

  // ============================================================================
  // Public Methods - Conversation Management
  // ============================================================================

  DateTime? _lastHostedResyncAt;
  static const _hostedResyncThrottle = Duration(seconds: 12);

  /// [kelivo-hosted] Re-pulls the currently open hosted conversation's
  /// messages from the server — called when the app regains foreground
  /// focus (mobile `AppLifecycleState.resumed` / desktop window refocus),
  /// since messages sent from another device while this one was
  /// backgrounded otherwise only show up after switching conversations away
  /// and back (see `switchConversation`'s own `syncMissingHostedMessages`
  /// call below). Also re-syncs the conversation list/titles — if the app
  /// was backgrounded (or killed and relaunched) right after sending the
  /// conversation's first message, the server's own auto-title
  /// (client_chat_task.py) may have finished while nothing client-side was
  /// around to pick it up via `_maybeGenerateTitleFor`'s normal
  /// stream-finished hook. Throttled so rapid focus churn doesn't spam the
  /// server.
  void resyncCurrentHostedConversation() {
    final now = DateTime.now();
    if (_lastHostedResyncAt != null &&
        now.difference(_lastHostedResyncAt!) < _hostedResyncThrottle) {
      return;
    }
    _lastHostedResyncAt = now;
    // [kelivo-hosted] Assistant cloud sync (AssistantProvider._pullFromCloud)
    // — piggybacks on the same foreground/window-focus-regain trigger as
    // the hosted message resync below, so an assistant edited on another
    // device shows up here on the same cadence a message would, rather than
    // only ever refreshing once at app launch. Independent of whether a
    // conversation happens to be open, unlike the message resync below.
    unawaited(_contextProvider.read<AssistantProvider>().refreshFromCloud());

    final convo = currentConversation;
    if (convo == null) return;
    // Sync before resume (see `switchConversation`'s identical ordering
    // note) — a message this device never saw before backgrounding only
    // becomes visible to `messagesNeedingResume`'s scan once this insert
    // completes.
    unawaited(
      _chatActions.syncMissingHostedMessages(convo).then((_) {
        // [kelivo-hosted] kelivo-arch.md §5 — `syncMissingHostedMessages`
        // writes corrected `groupId`/`version` values (regenerate versioning
        // across devices) straight into `ChatService`'s Hive box, but
        // `ChatController`'s already-built `_messages`/collapsed-version
        // cache (populated once, synchronously, before this sync started)
        // never re-reads it on its own — without this, a regenerated
        // version pair stays visibly un-folded until the conversation is
        // closed and reopened a SECOND time.
        // [kelivo-hosted] `reloadMessages()` preserves the previously-loaded
        // window's SIZE (chat_controller.dart's `visibleCount` is derived
        // from the stale pre-reload `_messages.length`) — fine for small
        // in-place edits, but wrong here: if this device had only a small
        // window loaded (e.g. right after first opening the conversation)
        // when a regenerated sibling version synced in, the reload re-fetches
        // the SAME small window size at a shifted position, which can leave
        // one of the two version siblings outside `_messages` entirely — the
        // exact same class of bug `syncMissingHostedMessages`'s original
        // fix (chat_actions.dart) already worked around by using
        // `loadEndWindow()` instead of `reloadMessages()`.
        if (currentConversation?.id == convo.id) {
          _chatController.loadEndWindow();
        }
        unawaited(_chatActions.resumeStaleHostedGenerations(convo));
      }),
    );
    unawaited(
      _chatService.syncConversationList().then((_) {
        if (currentConversation?.id == convo.id) {
          _chatController.updateCurrentConversation(
            _chatService.getConversation(convo.id),
          );
          notifyListeners();
        }
      }),
    );
  }

  Timer? _hostedWatchTimer;
  static const _hostedWatchInterval = Duration(seconds: 3);

  /// [kelivo-hosted] While a hosted conversation stays open on this device,
  /// `switchConversation`'s discover-and-resume sequence
  /// (`syncMissingHostedMessages` + `resumeStaleHostedGenerations`) only
  /// ever runs once, at the moment it's opened. If another device starts
  /// generating a reply in this *same* conversation afterward — while this
  /// device is just sitting on it, not switching away and back — nothing
  /// re-triggers that discovery, so the new message never appears here at
  /// all until the user leaves and re-enters, or the app is backgrounded
  /// and foregrounded (`resyncCurrentHostedConversation`, throttled to once
  /// per 12s). This periodically repeats that same discovery on a short
  /// interval so a message another device starts mid-visit gets picked up
  /// (and then live-polled via `resumeStaleHostedGenerations`'s normal
  /// `_sendHostedStream` reattachment) without requiring either of those
  /// coarser triggers. Skipped whenever this device already has an active
  /// generation for the conversation — either a self-initiated send
  /// (`isConversationLoading`) or an already-resumed one (a live entry in
  /// `chatController.conversationStreams`; `resumeStaleHostedGenerations`
  /// itself never flips `isConversationLoading`, only `_executeGeneration`
  /// registering the stream subscription does). Without the second check,
  /// `messagesNeedingResume` would keep finding the same still-`isStreaming`
  /// message every tick and start a second, duplicate poll loop against the
  /// same server message id on top of the one already running.
  void _startHostedWatch(String conversationId) {
    _hostedWatchTimer?.cancel();
    _hostedWatchTimer = Timer.periodic(_hostedWatchInterval, (_) {
      _hostedWatchTick(conversationId);
    });
  }

  void _stopHostedWatch() {
    _hostedWatchTimer?.cancel();
    _hostedWatchTimer = null;
  }

  void _hostedWatchTick(String conversationId) {
    if (currentConversation?.id != conversationId) {
      _stopHostedWatch();
      return;
    }
    unawaited(_syncAndResumeHosted(conversationId));
  }

  /// [kelivo-hosted] Shared by the periodic watcher tick and the manual
  /// refresh button (`refreshHostedConversation`) — pulls in any messages
  /// this device hasn't seen yet and reattaches to any still-generating one
  /// found. Returns false (no-op) if there's no hosted session, or if this
  /// device already has an active generation of its own for the
  /// conversation — either self-initiated (`isConversationLoading`) or an
  /// already-resumed one (`conversationStreams`; `resumeStaleHostedGenerations`
  /// never flips `isConversationLoading` itself, only `_executeGeneration`
  /// registering the stream subscription does) — re-running in that case
  /// would call `resumeStaleHostedGenerations` on a message this device is
  /// already polling, starting a second, duplicate poll loop against the
  /// same server message id.
  Future<bool> _syncAndResumeHosted(String conversationId) async {
    if (ClientBackendSession.token == null) return false;
    if (_chatController.isConversationLoading(conversationId)) return false;
    if (_chatController.conversationStreams.containsKey(conversationId)) {
      return false;
    }
    final convo = _chatService.getConversation(conversationId);
    if (convo == null) return false;
    await _chatActions.syncMissingHostedMessages(convo);
    if (currentConversation?.id != conversationId) return true;
    await _chatActions.resumeStaleHostedGenerations(convo);
    return true;
  }

  /// Whether the currently open conversation has ever synced with the
  /// hosted backend — gates the manual "sync with server" button in the
  /// chat app bar (a BYOK conversation has no server-side state to sync).
  bool get isCurrentConversationHosted =>
      currentConversation?.hostedSynced == true;

  /// [kelivo-hosted] Manual counterpart to the periodic watcher — lets the
  /// user force an immediate re-sync (message content/status, plus the
  /// conversation title/list) instead of waiting for the next periodic
  /// tick, the throttled app-resume resync, or a conversation
  /// switch-away-and-back. Returns false if nothing was actually synced
  /// (see `_syncAndResumeHosted`) — the caller can use that to skip showing
  /// a success confirmation.
  Future<bool> refreshHostedConversation() async {
    final convo = currentConversation;
    if (convo == null || !convo.hostedSynced) return false;
    final ran = await _syncAndResumeHosted(convo.id);
    await _chatService.syncConversationList();
    if (currentConversation?.id == convo.id) {
      _chatController.updateCurrentConversation(
        _chatService.getConversation(convo.id),
      );
      notifyListeners();
    }
    return ran;
  }

  /// Switch to an existing conversation.
  Future<void> switchConversation(String id) async {
    final assistantProvider = _contextProvider.read<AssistantProvider>();

    // Flush current conversation progress before switching
    await _chatActions.flushConversationProgress(currentConversation);

    // Reset processing state on switch
    isProcessingFiles.value = FileProcessingStatus.idle;

    if (currentConversation?.id == id) return;
    _stopHostedWatch();

    _chatService.setCurrentConversation(id);
    final convo = _chatService.getConversation(id);
    if (convo != null) {
      final convoAssistantId = convo.assistantId;
      if (convoAssistantId != null &&
          assistantProvider.currentAssistantId != convoAssistantId &&
          assistantProvider.getById(convoAssistantId) != null) {
        await assistantProvider.setCurrentAssistant(convoAssistantId);
      }
      _chatController.setCurrentConversation(convo);
      _streamController.clearGeminiThoughtSigs();
      notifyListeners();
      onConversationSwitched?.call();
      unawaited(_drainQueuedInputIfReady(id));
      // [kelivo-hosted] kelivo-arch.md §5 — sync before resume, not
      // "alongside" (the previous ordering fired both unawaited at once): a
      // message discovered here for the first time (still generating on
      // another device) only becomes visible to
      // `ChatService.messagesNeedingResume`'s local scan once
      // `syncMissingHostedMessages` has actually inserted it. Racing that
      // insert against `resumeStaleHostedGenerations`'s synchronous scan
      // meant a message discovered mid-generation never got its resume-poll
      // started — it just sat there with whatever stale/empty content it
      // was inserted with (isStreaming: true forever), only fixed by the
      // next cold launch's `_resetStaleStreamingFlags` reconciliation.
      unawaited(
        _chatActions.syncMissingHostedMessages(convo).then((_) {
          // See the identical note in `resyncCurrentHostedConversation` —
          // `loadEndWindow()` not `reloadMessages()`, since the latter's
          // reload window size is derived from the stale pre-sync
          // `_messages.length` and can leave a just-synced regenerated
          // sibling version outside the reloaded window.
          if (currentConversation?.id == convo.id) {
            _chatController.loadEndWindow();
          }
          unawaited(_chatActions.resumeStaleHostedGenerations(convo));
        }),
      );
      _startHostedWatch(id);
    }
  }

  /// Create a new conversation.
  Future<void> createNewConversation() async {
    // Flush current conversation progress before creating new
    await _chatActions.flushConversationProgress(currentConversation);
    if (!_contextProvider.mounted) return;

    // Reset processing state on create
    isProcessingFiles.value = FileProcessingStatus.idle;

    final ap = _contextProvider.read<AssistantProvider>();
    final assistantId = ap.currentAssistantId;
    final a = ap.currentAssistant;

    final conversation = await _chatService.createDraftConversation(
      title: getTitleForLocale(_contextProvider),
      assistantId: assistantId,
    );

    _chatController.setCurrentConversation(conversation);
    _streamController.clearAllState();
    notifyListeners();

    // Inject assistant preset messages into new conversation (ordered)
    try {
      final presets = ap.getPresetMessagesForAssistant(a?.id);
      if (presets.isNotEmpty && currentConversation != null) {
        for (final pm in presets) {
          final role = (pm['role'] == 'assistant') ? 'assistant' : 'user';
          final content = (pm['content'] ?? '').trim();
          if (content.isEmpty) continue;
          await _chatService.addMessage(
            conversationId: currentConversation!.id,
            role: role,
            content: content,
          );
          _chatController.reloadMessages();
          notifyListeners();
        }
      }
    } catch (_) {}

    onScrollToBottom?.call();
  }

  Future<void> toggleTemporaryConversation() async {
    final convo = currentConversation;
    if (convo == null || messages.isNotEmpty) return;

    await _chatActions.flushConversationProgress(currentConversation);
    if (!_contextProvider.mounted) return;

    isProcessingFiles.value = FileProcessingStatus.idle;

    if (_chatService.isTemporaryConversation(convo.id)) {
      await createNewConversation();
      return;
    }

    final ap = _contextProvider.read<AssistantProvider>();
    final conversation = await _chatService.createDraftConversation(
      title: AppLocalizations.of(_contextProvider)!.temporaryChatTitle,
      assistantId: ap.currentAssistantId,
      temporary: true,
    );

    _chatController.setCurrentConversation(conversation);
    _streamController.clearAllState();
    notifyListeners();
    onScrollToBottom?.call();
  }

  /// Fork conversation at a specific message.
  Future<void> forkConversation(ChatMessage message) async {
    final allMessages = _chatController
        .allMessagesForCurrentConversationContext();
    final selected = selectForkConversationMessages(
      messages: allMessages,
      targetMessage: message,
      versionSelections: versionSelections,
    );
    if (selected.isEmpty) return;

    final newConvo = await _chatService.forkConversation(
      title: getTitleForLocale(_contextProvider),
      assistantId: currentConversation?.assistantId,
      sourceMessages: selected,
    );

    // Switch to the new conversation
    _chatService.setCurrentConversation(newConvo.id);
    _chatController.setCurrentConversation(newConvo);
    _restoreMessageUiState();
    notifyListeners();
    onConversationSwitched?.call();
    onScrollToBottom?.call();
  }

  /// Clear context (toggle truncate at tail).
  Future<void> clearContext() async {
    final convo = currentConversation;
    if (convo == null) return;

    final defaultTitle = getTitleForLocale(_contextProvider);
    await _clearSuggestionsFor(convo.id);
    final updated = await _chatService.toggleTruncateAtTail(
      convo.id,
      defaultTitle: defaultTitle,
    );
    if (updated != null) {
      _chatController.updateCurrentConversation(updated);
      notifyListeners();
    }
  }

  /// Compress context: summarize messages via LLM, create new conversation with summary.
  /// Returns null on success, or an error key string on failure.
  Future<String?> compressContext({
    required CompressContextOptions options,
  }) async {
    final convo = currentConversation;
    if (convo == null) return 'no_conversation';

    // Get messages and collapse to selected versions
    final allMsgs = _chatController.allMessagesForCurrentConversationContext();
    final collapsed = collapseVersions(allMsgs);
    if (collapsed.isEmpty) return 'no_messages';

    // Build conversation text for compression
    final joined = buildConversationTextForCompression(collapsed);
    if (joined.trim().isEmpty) return 'no_messages';

    final content = buildCompressContextContent(joined, options);
    final locale = Localizations.localeOf(_contextProvider).toLanguageTag();

    // Resolve model: compress model → summary model → title model → assistant model → global default
    final settings = _contextProvider.read<SettingsProvider>();
    final ap = _contextProvider.read<AssistantProvider>();
    final assistant = convo.assistantId != null
        ? ap.getById(convo.assistantId!)
        : ap.currentAssistant;

    final resolved = ChatApiService.resolveTextUtilityModel(settings, [
      (settings.compressModelProvider, settings.compressModelId),
      (settings.summaryModelProvider, settings.summaryModelId),
      (settings.titleModelProvider, settings.titleModelId),
      (assistant?.chatModelProvider, assistant?.chatModelId),
      (settings.currentModelProvider, settings.currentModelId),
    ]);
    if (resolved == null) return 'no_model';
    final (cfg, mdlId) = resolved;

    // Build compression prompt from settings template
    final prompt = settings.compressPrompt
        .replaceAll('{content}', content)
        .replaceAll('{locale}', locale);

    try {
      final summary = (await ChatApiService.generateText(
        config: cfg,
        modelId: mdlId,
        prompt: prompt,
      )).trim();

      if (summary.isEmpty) return 'empty_summary';

      // Create new conversation with the summary as its first turn.
      final newConvo = await _chatService.createDraftConversation(
        title: convo.title,
        assistantId: convo.assistantId,
      );

      // Switch to the new conversation first — `sendMessage` below reads
      // `currentConversation`.
      _chatService.setCurrentConversation(newConvo.id);
      _chatController.setCurrentConversation(
        _chatService.getConversation(newConvo.id) ?? newConvo,
      );
      _streamController.clearAllState();
      notifyListeners();
      onConversationSwitched?.call();
      onScrollToBottom?.call();

      // [kelivo-hosted] Actually *send* the summary through the normal send
      // path — not `_chatService.addMessage`, which only writes a local
      // Hive row and never reaches the server. That used to leave the
      // summary as an unanswered, un-transmitted draft: under a hosted
      // provider it's especially broken, since `_sendHostedStream` only
      // ever forwards the *last* user-role message in a send's context
      // (`_lastUserMessageContent` in hosted.dart) — the server has no
      // history at all for this brand-new conversation, so the summary
      // would silently never reach the model on any subsequent send, not
      // even once. Routing through `sendMessage` makes it a real first
      // turn (persisted server-side for hosted, and immediately answered)
      // exactly like a user typing it in would.
      await sendMessage(ChatInputData(text: summary));

      return null; // success
    } catch (e) {
      return e.toString();
    }
  }

  /// Update current conversation reference.
  void updateCurrentConversation(Conversation? conversation) {
    _chatController.updateCurrentConversation(conversation);
    notifyListeners();
  }

  /// Reload messages from storage.
  void reloadMessages() {
    _chatController.reloadMessages();
    notifyListeners();
  }

  bool loadMoreBefore() {
    final loaded = _chatController.loadMoreBefore();
    if (!loaded) return false;
    _restoreMessageUiState();
    notifyListeners();
    return true;
  }

  bool loadMoreAfter() {
    final loaded = _chatController.loadMoreAfter();
    if (!loaded) return false;
    _restoreMessageUiState();
    notifyListeners();
    return true;
  }

  bool loadUntilMessageVisible(String messageId) {
    final loaded = _chatController.loadUntilMessageVisible(messageId);
    if (!loaded) return false;
    _restoreMessageUiState();
    notifyListeners();
    return true;
  }

  /// Set selected version for a message group.
  Future<void> setSelectedVersion(String groupId, int version) async {
    final cid = currentConversation?.id;
    if (cid != null) {
      await _clearSuggestionsFor(cid);
    }
    await _chatController.setSelectedVersion(groupId, version);
    notifyListeners();
  }

  // ============================================================================
  // Public Methods - UI State
  // ============================================================================

  /// Restore per-message UI states after switching conversations.
  void restoreMessageUiState() {
    _restoreMessageUiState();
    notifyListeners();
  }

  void _restoreMessageUiState() {
    for (int i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.role == 'assistant') {
        _streamController.restoreMessageUiState(
          m,
          getToolEventsFromDb: (id) => _chatService.getToolEvents(id),
          getGeminiThoughtSigFromDb: (id) =>
              _chatService.getGeminiThoughtSignature(id),
        );

        // Clean content from gemini thought signatures
        final cleanedContent = _streamController.captureGeminiThoughtSignature(
          m.content,
          m.id,
        );
        if (cleanedContent != m.content) {
          final updated = m.copyWith(content: cleanedContent);
          messages[i] = updated;
          unawaited(_chatService.updateMessage(m.id, content: cleanedContent));
        }

        // Clean up any inline base64 images persisted from earlier runs
        onScheduleImageSanitize?.call(
          m.id,
          messages[i].content,
          immediate: true,
        );
      }
    }
  }

  /// Serialize reasoning segments to JSON string.
  String serializeReasoningSegments(
    List<stream_ctrl.ReasoningSegmentData> segments,
  ) {
    return _streamController.serializeReasoningSegments(segments);
  }

  /// Collapse message versions to show only selected version per group.
  List<ChatMessage> collapseVersions(List<ChatMessage> items) {
    return _chatController.collapseVersions(items);
  }

  /// Group messages by their groupId.
  Map<String, List<ChatMessage>> groupMessagesByGroup() {
    return _chatController.groupMessagesByGroup();
  }

  /// Get clear context label based on current state.
  String getClearContextLabel(
    String Function(String, String) withCountFormatter,
    String defaultLabel,
  ) {
    final assistant = _contextProvider
        .read<AssistantProvider>()
        .currentAssistant;
    final configured = (assistant?.limitContextMessages ?? true)
        ? (assistant?.contextMessageSize ?? 0)
        : 0;
    final completeMessages = _chatController
        .allMessagesForCurrentConversationContext();
    final collapsed = collapseVersions(completeMessages);
    final remaining = computeClearContextRemainingMessageCount(
      completeMessages: completeMessages,
      collapsedMessages: collapsed,
      truncateIndex: currentConversation?.truncateIndex ?? -1,
    );
    if (configured > 0) {
      final actual = remaining > configured ? configured : remaining;
      return withCountFormatter(actual.toString(), configured.toString());
    }
    return defaultLabel;
  }

  @visibleForTesting
  static int computeClearContextRemainingMessageCount({
    required List<ChatMessage> completeMessages,
    required List<ChatMessage> collapsedMessages,
    required int truncateIndex,
  }) {
    var safeTruncateIndex = truncateIndex;
    if (safeTruncateIndex < 0 || safeTruncateIndex > completeMessages.length) {
      safeTruncateIndex = 0;
    }
    final firstIndexByGroup = <String, int>{};
    for (var i = 0; i < completeMessages.length; i++) {
      final groupId = completeMessages[i].groupId ?? completeMessages[i].id;
      firstIndexByGroup.putIfAbsent(groupId, () => i);
    }

    var remaining = 0;
    for (final message in collapsedMessages) {
      if (message.content.trim().isEmpty) continue;
      final groupId = message.groupId ?? message.id;
      final firstIndex = firstIndexByGroup[groupId];
      if (firstIndex != null && firstIndex >= safeTruncateIndex) {
        remaining++;
      }
    }
    return remaining;
  }

  // ============================================================================
  // Title Generation
  // ============================================================================

  /// Generate title for a conversation if needed.
  Future<void> _maybeGenerateTitleFor(
    String conversationId, {
    bool force = false,
  }) async {
    final convo = _chatService.getConversation(conversationId);
    if (convo == null) return;
    if (!force &&
        convo.title.isNotEmpty &&
        convo.title != getTitleForLocale(_contextProvider)) {
      return;
    }

    if (convo.hostedSynced) {
      // [kelivo-hosted] Title generation for hosted conversations happens
      // entirely server-side (client_chat_task.py, right after the first
      // assistant reply — see `generate_conversation_title`), and is
      // already committed by the time this fires: the server only flips
      // the reply's status to "done" (which is what makes the client's
      // poll loop in providers/hosted.dart see it as finished and call
      // here) AFTER that title attempt completes. So there's no client-side
      // generation to do — `ChatApiService.generateText` has no hosted
      // branch anyway (see side_drawer.dart's `_regenerateTitle`, which
      // calls the dedicated `/generate-title` endpoint instead for the
      // manual case). Just pull the already-generated title in.
      if (force) return;
      await _chatService.syncConversationList();
      if (currentConversation?.id == conversationId) {
        _chatController.updateCurrentConversation(
          _chatService.getConversation(conversationId),
        );
        notifyListeners();
      }
      return;
    }

    final settings = _contextProvider.read<SettingsProvider>();
    final assistantProvider = _contextProvider.read<AssistantProvider>();

    // Get assistant for this conversation
    final assistant = convo.assistantId != null
        ? assistantProvider.getById(convo.assistantId!)
        : assistantProvider.currentAssistant;

    // Decide model: prefer title model, else fall back to assistant's model, then to global default
    final resolved = ChatApiService.resolveTextUtilityModel(settings, [
      (settings.titleModelProvider, settings.titleModelId),
      (assistant?.chatModelProvider, assistant?.chatModelId),
      (settings.currentModelProvider, settings.currentModelId),
    ]);
    if (resolved == null) return;
    final (cfg, mdlId) = resolved;
    final budget = settings.titleGenerationThinkingBudgetFor(
      assistant?.thinkingBudget,
    );

    // Build content from messages (truncate to reasonable length)
    final msgs = _chatService.getMessages(convo.id);
    final tIndex = convo.truncateIndex;
    final List<ChatMessage> sourceAll = (tIndex >= 0 && tIndex <= msgs.length)
        ? msgs.sublist(tIndex)
        : msgs;
    final List<ChatMessage> source = collapseVersions(sourceAll);
    final joined = source
        .where((m) => m.content.isNotEmpty)
        .map(
          (m) =>
              '${m.role == 'assistant' ? 'Assistant' : 'User'}: ${m.content}',
        )
        .join('\n\n');
    final content = joined.length > 3000 ? joined.substring(0, 3000) : joined;
    final locale = Localizations.localeOf(_contextProvider).toLanguageTag();

    String prompt = settings.titlePrompt
        .replaceAll('{locale}', locale)
        .replaceAll('{content}', content);

    try {
      final title = (await ChatApiService.generateText(
        config: cfg,
        modelId: mdlId,
        prompt: prompt,
        thinkingBudget: budget,
      )).trim();
      if (title.isNotEmpty) {
        await _chatService.renameConversation(convo.id, title);
        if (currentConversation?.id == convo.id) {
          _chatController.updateCurrentConversation(
            _chatService.getConversation(convo.id),
          );
          notifyListeners();
        }
      }
    } catch (e) {
      FlutterLogger.log(
        '[TitleGen] Generation failed: $e',
        tag: 'HomeViewModel',
      );
      // Ignore title generation failure silently
    }
  }

  /// Force generate title for the current conversation.
  Future<void> generateTitle({bool force = false}) async {
    final cid = currentConversation?.id;
    if (cid != null) {
      await _maybeGenerateTitleFor(cid, force: force);
    }
  }

  // ============================================================================
  // Summary Generation
  // ============================================================================

  /// Generate summary for a conversation if conditions are met.
  /// Triggers after the configured number of new messages since last summary.
  Future<void> _maybeGenerateSummaryFor(String conversationId) async {
    final convo = _chatService.getConversation(conversationId);
    if (convo == null) return;

    final settings = _contextProvider.read<SettingsProvider>();
    final msgCount = convo.messageIds.length;
    final assistantProvider = _contextProvider.read<AssistantProvider>();

    // Get assistant for this conversation
    final assistant = convo.assistantId != null
        ? assistantProvider.getById(convo.assistantId!)
        : assistantProvider.currentAssistant;

    final budget = assistant?.thinkingBudget ?? settings.thinkingBudget;

    // Only generate summary if assistant has recent chats reference enabled
    if (assistant?.enableRecentChatsReference != true) return;

    final triggerMessageCount =
        assistant?.recentChatsSummaryMessageCount ??
        Assistant.defaultRecentChatsSummaryMessageCount;
    if (msgCount == 0 ||
        msgCount - convo.lastSummarizedMessageCount < triggerMessageCount) {
      return;
    }

    // Use summary model if configured, else fall back to title model, then current model
    final resolved = ChatApiService.resolveTextUtilityModel(settings, [
      (settings.summaryModelProvider, settings.summaryModelId),
      (settings.titleModelProvider, settings.titleModelId),
      (assistant?.chatModelProvider, assistant?.chatModelId),
      (settings.currentModelProvider, settings.currentModelId),
    ]);
    if (resolved == null) return;
    final (cfg, mdlId) = resolved;

    // Get all messages and filter user messages
    final msgs = _chatService.getMessages(convo.id);
    final allUserMsgs = msgs
        .where((m) => m.role == 'user' && m.content.trim().isNotEmpty)
        .toList();

    if (allUserMsgs.isEmpty) return;

    // Get previous summary (empty string if first time)
    final previousSummary = (convo.summary ?? '').trim();

    // Get only the recent user messages since last summarization
    // Calculate how many user messages were in the last summarized state
    final lastSummarizedMsgCount = (convo.lastSummarizedMessageCount < 0)
        ? 0
        : convo.lastSummarizedMessageCount;
    final msgsAtLastSummary = msgs.take(lastSummarizedMsgCount).toList();
    final userMsgsAtLastSummary = msgsAtLastSummary
        .where((m) => m.role == 'user' && m.content.trim().isNotEmpty)
        .length;

    // Get new user messages since last summary
    final newUserMsgs = allUserMsgs.skip(userMsgsAtLastSummary).toList();
    if (newUserMsgs.isEmpty) return;

    final recentMessages = newUserMsgs
        .map((m) => m.content.trim())
        .join('\n\n');

    // Truncate if too long
    final content = recentMessages.length > 2000
        ? recentMessages.substring(0, 2000)
        : recentMessages;

    final prompt = settings.summaryPrompt
        .replaceAll('{previous_summary}', previousSummary)
        .replaceAll('{user_messages}', content);

    try {
      final summary = (await ChatApiService.generateText(
        config: cfg,
        modelId: mdlId,
        prompt: prompt,
        thinkingBudget: budget,
      )).trim();

      if (summary.isNotEmpty) {
        await _chatService.updateConversationSummary(
          convo.id,
          summary,
          msgCount,
        );
        if (currentConversation?.id == convo.id) {
          _chatController.updateCurrentConversation(
            _chatService.getConversation(convo.id),
          );
          notifyListeners();
        }
      }
    } catch (_) {
      // Keep old summary on failure, ignore silently
    }
  }

  // ============================================================================
  // Chat Suggestions
  // ============================================================================

  Future<void> _clearSuggestionsFor(String conversationId) async {
    final convo = _chatService.getConversation(conversationId);
    if (convo == null || convo.chatSuggestions.isEmpty) return;
    await _chatService.clearConversationSuggestions(conversationId);
    if (currentConversation?.id == conversationId) {
      _chatController.updateCurrentConversation(
        _chatService.getConversation(conversationId),
      );
      notifyListeners();
    }
  }

  Future<void> _maybeGenerateSuggestionsFor(String conversationId) async {
    final convo = _chatService.getConversation(conversationId);
    if (convo == null) return;

    final settings = _contextProvider.read<SettingsProvider>();
    final provKey = settings.suggestionModelProvider;
    final mdlId = settings.suggestionModelId;
    if (provKey == null || mdlId == null) return;

    final msgs = collapseVersions(_chatService.getMessages(convo.id));
    final lastAssistant = msgs.cast<ChatMessage?>().lastWhere(
      (m) =>
          m != null &&
          m.role == 'assistant' &&
          !m.isStreaming &&
          m.content.trim().isNotEmpty,
      orElse: () => null,
    );
    if (lastAssistant == null) return;

    final assistantProvider = _contextProvider.read<AssistantProvider>();
    final assistant = convo.assistantId != null
        ? assistantProvider.getById(convo.assistantId!)
        : assistantProvider.currentAssistant;
    final locale = Localizations.localeOf(_contextProvider).toLanguageTag();
    final budget = assistant?.thinkingBudget ?? settings.thinkingBudget;

    try {
      await _chatService.clearConversationSuggestions(conversationId);
      final suggestions = await _suggestionService.generate(
        settings: settings,
        providerKey: provKey,
        modelId: mdlId,
        messages: msgs,
        truncateIndex: convo.truncateIndex,
        locale: locale,
        thinkingBudget: budget,
      );
      if (suggestions.isEmpty) return;

      final latest = _chatService.getConversation(conversationId);
      if (latest == null ||
          latest.messageIds.length != convo.messageIds.length) {
        return;
      }

      await _chatService.updateConversationSuggestions(
        conversationId,
        suggestions,
      );
      if (currentConversation?.id == conversationId) {
        _chatController.updateCurrentConversation(
          _chatService.getConversation(conversationId),
        );
        notifyListeners();
      }
    } catch (e) {
      FlutterLogger.log(
        '[SuggestionGen] Generation failed: $e',
        tag: 'HomeViewModel',
      );
    }
  }

  // ============================================================================
  // Model Capability Checks
  // ============================================================================

  bool isReasoningModel(String providerKey, String modelId) {
    return _generationController.isReasoningModel(providerKey, modelId);
  }

  bool isToolModel(String providerKey, String modelId) {
    return _generationController.isToolModel(providerKey, modelId);
  }

  bool isReasoningEnabled(int? budget) {
    return _generationController.isReasoningEnabled(budget);
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Flush current conversation progress (for switching/creating).
  Future<void> flushCurrentConversationProgress() async {
    await _chatActions.flushConversationProgress(currentConversation);
  }

  /// Clean up message state (reasoning, tools, etc.) for removed messages.
  void cleanupMessageState(List<String> messageIds) {
    for (final id in messageIds) {
      _streamController.clearMessageState(id);
    }
  }
}
