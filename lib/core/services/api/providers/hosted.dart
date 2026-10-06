part of '../chat_api_service.dart';

const _hostedToolExecutionStoragePrefix = 'hosted_tool_execution_v1_';
final Map<String, Future<String>> _hostedToolOwnerKeys =
    <String, Future<String>>{};
final Map<String, Future<_HostedToolExecutionResult>> _hostedToolInFlight =
    <String, Future<_HostedToolExecutionResult>>{};
final Map<String, String> _hostedToolCompletedResults = <String, String>{};

class _HostedToolExecutionResult {
  const _HostedToolExecutionResult({
    required this.executionKey,
    this.result,
    this.messageResumed = false,
  });

  final String executionKey;
  final String? result;
  final bool messageResumed;
}

String _hostedToolExecutionStorageKey(String messageId, String toolCallId) {
  return '$_hostedToolExecutionStoragePrefix${messageId}_call_${base64Url.encode(utf8.encode(toolCallId))}';
}

String _hostedToolMessageOwnerStorageKey(String messageId) =>
    '$_hostedToolExecutionStoragePrefix${messageId}_owner';

Future<String> _loadOrCreateHostedToolOwnerKey(String messageId) {
  return _hostedToolOwnerKeys.putIfAbsent(messageId, () async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = _hostedToolMessageOwnerStorageKey(messageId);
    var ownerKey = prefs.getString(storageKey);
    if (ownerKey == null || ownerKey.isEmpty) {
      final random = Random.secure();
      ownerKey = List<int>.generate(
        32,
        (_) => random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      if (!await prefs.setString(storageKey, ownerKey)) {
        throw StateError(
          'Could not persist the hosted tool execution identity.',
        );
      }
    }
    return ownerKey;
  });
}

Future<Map<String, String>> _loadOrCreateHostedToolExecution(
  String messageId,
  String toolCallId,
) async {
  final prefs = await SharedPreferences.getInstance();
  final storageKey = _hostedToolExecutionStorageKey(messageId, toolCallId);
  final saved = prefs.getString(storageKey);
  final ownerKey = await _loadOrCreateHostedToolOwnerKey(messageId);
  if (saved != null) {
    try {
      final value = jsonDecode(saved) as Map<String, dynamic>;
      final executionKey = value['execution_key']?.toString();
      final phase = value['phase']?.toString();
      if (executionKey != null && phase != null) {
        return {'execution_key': executionKey, 'phase': phase};
      }
    } on FormatException {
      // Replace corrupt local bookkeeping with a fresh execution identity.
    } on TypeError {
      // Replace corrupt local bookkeeping with a fresh execution identity.
    }
  }
  final checkpoint = {'execution_key': ownerKey, 'phase': 'prepared'};
  if (!await prefs.setString(storageKey, jsonEncode(checkpoint))) {
    throw StateError('Could not persist the hosted tool execution checkpoint.');
  }
  return checkpoint;
}

Future<void> _markHostedToolExecutionStarted(
  String messageId,
  String toolCallId,
  String executionKey,
) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = await prefs.setString(
    _hostedToolExecutionStorageKey(messageId, toolCallId),
    jsonEncode({'execution_key': executionKey, 'phase': 'started'}),
  );
  if (!saved) {
    throw StateError('Could not persist the hosted tool execution checkpoint.');
  }
}

Future<void> _clearHostedToolExecutions(String messageId) async {
  final prefs = await SharedPreferences.getInstance();
  final prefix = '$_hostedToolExecutionStoragePrefix${messageId}_';
  for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
    await prefs.remove(key);
  }
  await prefs.remove(_hostedToolMessageOwnerStorageKey(messageId));
  _hostedToolOwnerKeys.remove(messageId);
  _hostedToolCompletedResults.removeWhere(
    (key, _) => key.startsWith('$messageId\u0000'),
  );
  _hostedToolInFlight.removeWhere(
    (key, _) => key.startsWith('$messageId\u0000'),
  );
}

Future<Map<String, dynamic>> _waitForHostedToolExecutionClaim(
  ClientBackendApi api,
  String token,
  String messageId,
  String toolCallId,
  String executionKey,
) async {
  for (var attempt = 0; attempt < 120; attempt++) {
    final claim = await api.claimToolExecution(
      token,
      messageId,
      toolCallId,
      executionKey,
    );
    final status = claim?['status']?.toString();
    if (claim != null && status != 'in_progress') return claim;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw TimeoutException('Another device is still handling this tool call.');
}

Future<_HostedToolExecutionResult> _executeHostedToolOnce({
  required ClientBackendApi api,
  required String token,
  required String messageId,
  required String toolCallId,
  required String toolName,
  required Map<String, dynamic> arguments,
  required ToolCallHandler? onToolCall,
}) async {
  final cacheKey = '$messageId\u0000$toolCallId';
  final cachedResult = _hostedToolCompletedResults[cacheKey];
  if (cachedResult != null) {
    final checkpoint = await _loadOrCreateHostedToolExecution(
      messageId,
      toolCallId,
    );
    return _HostedToolExecutionResult(
      executionKey: checkpoint['execution_key']!,
      result: cachedResult,
    );
  }
  final existing = _hostedToolInFlight[cacheKey];
  if (existing != null) return existing;

  final future = () async {
    final checkpoint = await _loadOrCreateHostedToolExecution(
      messageId,
      toolCallId,
    );
    final claim = await _waitForHostedToolExecutionClaim(
      api,
      token,
      messageId,
      toolCallId,
      checkpoint['execution_key']!,
    );
    final status = claim['status']?.toString();
    if (status == 'resumed') {
      return _HostedToolExecutionResult(
        executionKey: checkpoint['execution_key']!,
        messageResumed: true,
      );
    }
    if (status == 'completed') {
      final result =
          claim['result']?.toString() ??
          jsonEncode({
            'type': 'tool_error',
            'error': 'completed_result_missing',
            'tool': toolName,
          });
      final executionKey =
          claim['execution_key']?.toString() ?? checkpoint['execution_key']!;
      _hostedToolCompletedResults[cacheKey] = result;
      return _HostedToolExecutionResult(
        executionKey: executionKey,
        result: result,
      );
    }

    String result;
    if (checkpoint['phase'] == 'started') {
      // The app may have exited after a side effect but before it could
      // save/post the result. Never execute that call again.
      result = jsonEncode({
        'type': 'tool_error',
        'error': 'execution_outcome_unknown',
        'message':
            'The client restarted during this tool call; it was not repeated.',
        'tool': toolName,
      });
    } else {
      try {
        await _markHostedToolExecutionStarted(
          messageId,
          toolCallId,
          checkpoint['execution_key']!,
        );
        if (onToolCall == null) {
          throw StateError('Tool execution is unavailable for this message.');
        }
        result = await onToolCall(toolName, arguments, toolCallId: toolCallId);
      } catch (e) {
        result = jsonEncode({
          'type': 'tool_error',
          'error': 'execution_error',
          'message': e.toString(),
          'tool': toolName,
        });
      }
    }
    _hostedToolCompletedResults[cacheKey] = result;
    return _HostedToolExecutionResult(
      executionKey: checkpoint['execution_key']!,
      result: result,
    );
  }();
  _hostedToolInFlight[cacheKey] = future;
  try {
    return await future;
  } finally {
    _hostedToolInFlight.remove(cacheKey);
  }
}

// [kelivo-hosted] kelivo-arch.md §5 — bridges the hosted-client backend's
// submit-then-SSE async task engine into the same `Stream<ChatStreamChunk>`
// shape every other provider produces, so the rest of the app (chat bubble
// rendering, regenerate, `ChatProvider`/`ChatService` persistence) doesn't
// need to know this provider works differently under the hood. Unlike every
// other provider here (stateless — the full `messages` history is resent
// every call), the hosted backend is stateful: it only needs the latest
// user message plus a `conversationId` it already has history for.
//
// `conversationId` is always the local Kelivo `Conversation.id` — Kelivo
// generates that id itself the moment a chat is started (before any network
// call), and the backend creates a matching server-side conversation row on
// first use rather than minting its own id (kelivo-arch.md §6 "Plan A":
// local id == server id from the start, no rename step needed).
Stream<ChatStreamChunk> _sendHostedStream({
  required ProviderConfig config,
  required String modelId,
  required List<Map<String, dynamic>> messages,
  required String? conversationId,
  // Controls progressive delivery to callers that explicitly request a
  // non-streaming result. Normal hosted chat forces this on in
  // MessageGenerationService, including for older assistants with a stored
  // `streamOutput=false`; auxiliary hosted requests may still choose false.
  bool stream = true,
  // [kelivo-hosted] kelivo-arch.md §5 image support — local file paths from
  // the chat input bar's image picker, same shape every BYOK provider
  // already gets via `sendMessageStream`. Encoded to base64 data URLs here
  // (reusing `ChatApiService._encodeBase64File`, the exact helper BYOK's
  // OpenAI branch already uses for vision input) and sent inline in the
  // `POST /messages` body — the hosted backend decodes/stores/dedupes them
  // server-side (app/services/client_message_images.py), no separate
  // upload step.
  List<String>? userImagePaths,
  // Button-inserted tokens paired with either a stored image id or a draft
  // image index. Ordinary `@` text never reaches this sidecar.
  List<Map<String, dynamic>>? attachmentSegments,
  // [kelivo-hosted] Non-media file attachments (PDF/etc) for this turn —
  // sent as native file content parts (raw bytes, base64), not the
  // extracted-text template every other provider gets — see
  // `_stripHostedFileBlocks`.
  List<DocumentAttachment>? userDocuments,
  // [kelivo-hosted] kelivo-arch.md §5 — set by `ChatActions.resumeStaleHostedGenerations`
  // when re-attaching to a message that's still `isStreaming: true` from a
  // previous app session and whose server-side generation is confirmed
  // still in progress (see `ChatService.messagesNeedingResume`). Skips
  // `POST /messages` entirely — there's already an assistant message id to
  // reconnect to, submitting a new prompt would start a second, unwanted reply.
  String? resumeAssistantMessageId,
  // [kelivo-hosted] the caller's `ChatMessage.content` already persisted for
  // [resumeAssistantMessageId] (e.g. `"Hello, how can I hel"` from a partial
  // generation cut short by a force-quit). The chunk-accumulation logic on
  // the caller side (`StreamingState.fullContentRaw`, seeded from that same
  // persisted content) only ever appends each yielded chunk's `content` —
  // it has no idea the server's full current content and the client's
  // already-known content overlap. Seeding `previousContent` with this
  // instead of `''` is what keeps the first resumed SSE delta to just
  // the genuinely-new suffix, instead of re-sending the whole thing and
  // duplicating it.
  String resumeKnownContent = '',
  // [kelivo-hosted] Same idea as [resumeKnownContent], for the reasoning
  // channel — without this, resuming (e.g. after a force-quit, or another
  // device's `resumeStaleHostedGenerations` reattaching to a still-running
  // generation) would recompute the reasoning delta from an empty string
  // and re-append the *entire* already-known reasoning text on top of what
  // the caller already has, doubling it in the UI.
  String resumeKnownReasoning = '',
  // [kelivo-hosted] kelivo-arch.md §5 — server id of the reply being
  // regenerated. When set (and [resumeAssistantMessageId] isn't), calls
  // `POST /messages/{id}/regenerate` instead of [ClientBackendApi.sendMessage]
  // — regenerate must NOT resubmit the prompt as a new turn, since that used
  // to create a second, unrelated user+assistant pair server-side that every
  // other device syncing this conversation had no way to recognize as "just
  // another version of the same reply" (see backend `ClientMessage.group_id`).
  String? regenerateOfServerMessageId,
  // [kelivo-hosted] kelivo-arch.md §5 — assistant-level generation params.
  // Every other provider branch in `chat_api_service.dart` already forwards
  // these; this one silently dropped them (along with the system prompt
  // below), so hosted replies never actually reflected the current
  // assistant's configured temperature/top-p/max-tokens.
  double? temperature,
  double? topP,
  int? maxTokens,
  // [kelivo-hosted] The chat/assistant's reasoning-strength setting
  // (`ChatApiService.sendMessageStream`'s `thinkingBudget`) — every other
  // provider branch already forwards this into its own request; this one
  // used to drop it on the floor entirely (not even accepted as a
  // parameter), so hosted-mode sends ignored whatever thinking strength the
  // user had configured. Forwarded to `ClientBackendApi.sendMessage`/
  // `regenerateMessage`, persisted server-side the same way `temperature`/
  // `topP`/`maxTokens` are (`ClientConversation.thinking_budget`), and
  // applied by `client_chat_task.py`'s `_stream_completion`.
  int? thinkingBudget,
  // [kelivo-hosted] Generation options for image-type models — forwarded
  // from `chat_api_service.dart`'s `sendMessageStream` (which pulls them
  // out of `extraBody` for this branch specifically, since this function
  // doesn't take `extraBody` itself) straight through to
  // `ClientBackendApi.sendMessage`/`regenerateMessage`, which persist them
  // onto the conversation server-side the same way `temperature`/`topP`/
  // `maxTokens` are. Only meaningful when the selected model is an image
  // model (`ChatApiService.isImageGenerationModel`) — the server ignores
  // them otherwise.
  String? imageGenSize,
  int? imageGenCount,
  // [kelivo-hosted] Same forwarding contract as `imageGenSize`/
  // `imageGenCount` above but for video-type models (xAI
  // `/v1/videos/generations`/`/edits`/`/extensions`). Only meaningful when
  // the selected model is a video model
  // (`ChatApiService.isVideoGenerationModel`) — the server ignores them
  // otherwise. `videoExtendMode` only matters once a video is already in
  // play (auto-detected server-side); the server ignores it too when there
  // is none.
  int? videoDuration,
  String? videoAspectRatio,
  String? videoResolution,
  bool? videoExtendMode,
  // [kelivo-hosted] The current assistant's cloud-synced id (see
  // `AssistantProvider`'s `/__client/assistants` sync) — lets
  // `client_chat_task.py` look up this assistant's `enable_memory` flag and
  // memory records server-side, instead of the client baking a `<memories>`
  // block into `systemPrompt` itself (see `injectMemoryAndRecentChats`,
  // which now skips that for hosted sends since the server does it here).
  String? assistantId,
  // Per-conversation active instruction cards. Assistant defaults are sent
  // only as the initial value for a new conversation.
  List<String>? instructionInjectionIds,
  // [kelivo-hosted] Executes client-device-only tool calls
  // (`clipboard_tool`/`text_to_speech`/`ask_user_input_v0`) the server
  // parked generation on (`ClientChatMessage.pendingToolCalls`, message
  // `status == "awaiting_tool"`) — the same `ToolCallHandler` every other
  // provider branch already gets (built once by
  // `ToolHandlerService.buildToolCallHandler`), so hosted local-tool calls
  // dispatch through the identical BYOK execution logic
  // (`LocalToolsService.tryHandleToolCall`/`AskUserInteractionService`).
  // `create_memory`/`edit_memory`/`delete_memory`/`get_time_info`/
  // `calculate` never appear here — the server resolves those itself before
  // ever pausing (client_local_tools.py/client_memory_tools.py).
  ToolCallHandler? onToolCall,
  // [kelivo-hosted] OpenAI function-calling-format tool defs for the
  // client's currently-connected/enabled MCP servers (kelivo-arch.md §5
  // MCP) — dynamic and client-owned, so unlike the fixed
  // `clipboard_tool`/`text_to_speech`/`ask_user_input_v0` set above, this
  // rides along on the request instead of being resolved from a DB row.
  // Sent with every send/regenerate (persisted server-side onto
  // `ClientConversation.mcp_tools`, same lifecycle as `systemPrompt`); when
  // the server parks generation on one of these tool names it shows up in
  // `pendingToolCalls` exactly like the client-device-only tools above, and
  // `onToolCall` (already generic over tool name — see
  // `ToolHandlerService.buildToolCallHandler`) resolves it against the
  // matching MCP server.
  List<Map<String, dynamic>>? mcpTools,
  // User-started anonymous conversation; persisted for audit but excluded
  // from user history and memory writes.
  bool anonymous = false,
  // [kelivo-hosted] Marks the conversation this call creates (only takes
  // effect when [conversationId] is null, i.e. a genuinely new send — never
  // relevant to [resumeAssistantMessageId]/[regenerateOfServerMessageId])
  // as one-shot: excluded from `GET /conversations`, age-cleaned by the
  // backend's retention sweep. Used by translation/OCR and, under hosted
  // providers, chat-suggestion/context-compression generation — none of
  // which want their throwaway conversation cluttering the user's real
  // conversation list.
  bool ephemeral = false,
  // [kelivo-hosted] `ChatService.buildHostedSeedMessages`'s output — prior
  // conversation history to seed a brand-new `conversation_id` with (a
  // locally-forked conversation, most notably) before this turn's own
  // prompt. Forwarded to `ClientBackendApi.sendMessage` as-is; the caller
  // is responsible for only building/passing this on a conversation's
  // actual first hosted send (checking `Conversation.hostedSynced`) — the
  // server itself also ignores it once [conversationId] already exists
  // (see `SendMessageRequest.seed_messages`'s docstring), so passing it
  // redundantly on a later turn is harmless, just wasted work.
  List<Map<String, dynamic>>? seedMessages,
  Future<void> Function()? beforeSubmit,
  // Hosted send-time snapshot of context-inclusion choices.
  Map<String, bool>? messageContextStates,
}) async* {
  final token = config.apiKey;
  if (token.isEmpty) {
    throw HttpException("Not signed in to Ethan's AI");
  }
  final api = ClientBackendApi(baseUrl: config.baseUrl);

  // [kelivo-hosted] `messages` already has the system prompt (with memory/
  // instructions/world-book baked in by `prepareApiMessagesWithInjections`)
  // injected as the first entry, exactly like every BYOK provider gets —
  // this provider just never read it before, only ever extracting the last
  // user turn's plain text and discarding everything else.
  final systemPrompt =
      messages.firstWhere(
            (m) => m['role'] == 'system',
            orElse: () => const <String, dynamic>{},
          )['content']
          as String?;

  final String assistantMessageId;
  // [kelivo-hosted] see `ChatStreamChunk.userMessageProviderId` — only set on
  // a genuinely new send (not a resume), same lifecycle as
  // `assistantMessageId` below.
  String? userMessageId;
  if (resumeAssistantMessageId != null) {
    assistantMessageId = resumeAssistantMessageId;
  } else if (regenerateOfServerMessageId != null) {
    await beforeSubmit?.call();
    final regenResult = await api.regenerateMessage(
      token,
      regenerateOfServerMessageId,
      modelId: modelId,
      systemPrompt: systemPrompt,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      thinkingBudget: thinkingBudget,
      imageGenSize: imageGenSize,
      imageGenCount: imageGenCount,
      videoDuration: videoDuration,
      videoAspectRatio: videoAspectRatio,
      videoResolution: videoResolution,
      videoExtendMode: videoExtendMode,
      assistantId: assistantId,
      instructionInjectionIds: instructionInjectionIds,
      mcpTools: mcpTools,
    );
    if (!regenResult.isSuccess) {
      throw HttpException(regenResult.error ?? 'Failed to regenerate message');
    }
    assistantMessageId = regenResult.assistantMessageId!;
    yield ChatStreamChunk(
      content: '',
      isDone: false,
      totalTokens: 0,
      providerMessageId: assistantMessageId,
    );
  } else {
    final rawContent = _lastUserMessageContent(messages);
    // `processUserMessagesForApi` still inlines the `## user sent a file:
    // ...` text template into `content` for every provider uniformly
    // (BYOK needs it, has no native file input) — strip it back out here so
    // hosted's own `content` stays just the user's own words; the file
    // itself goes via `documents` below instead, as raw bytes.
    final content = _stripHostedFileBlocks(rawContent);
    final documents = userDocuments == null || userDocuments.isEmpty
        ? null
        : await Future.wait(
            userDocuments.map((d) async {
              // NOT `ChatApiService._encodeBase64File(withPrefix: true)` —
              // its mime guess (`_mimeFromPath`) is image-oriented and
              // falls back to `image/png` for anything it doesn't
              // recognize (PDFs included), mislabeling the data URL
              // itself. The backend derives the stored mime type from
              // that embedded tag, not from `mimeType` below, so a
              // mislabeled PDF got sent upstream as an `image_url` part
              // and the model choked trying to decode PNG bytes that were
              // actually a PDF. `d.mime` (from the file picker, the actual
              // known type) is authoritative here.
              final fixed = SandboxPathResolver.fix(d.path);
              final bytes = await File(fixed).readAsBytes();
              final dataUrl = 'data:${d.mime};base64,${base64Encode(bytes)}';
              return {
                'filename': d.fileName,
                'mimeType': d.mime,
                'data': dataUrl,
              };
            }),
          );
    final images = userImagePaths == null || userImagePaths.isEmpty
        ? null
        : await Future.wait(
            userImagePaths.map(
              (p) => ChatApiService._encodeBase64File(p, withPrefix: true),
            ),
          );

    final uploadIds = <String>[];
    for (var index = 0; index < (images?.length ?? 0); index++) {
      final dataUrl = images![index];
      final comma = dataUrl.indexOf(',');
      if (comma < 0) continue;
      final mime = dataUrl.substring(5, dataUrl.indexOf(';'));
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      final path = userImagePaths![index];
      final filename = path.split(RegExp(r'[/\\]')).last;
      uploadIds.add(
        await api.uploadMedia(
          token,
          filename: filename.isEmpty ? 'image-$index' : filename,
          mimeType: mime,
          bytes: bytes,
        ),
      );
    }
    for (final document in documents ?? const <Map<String, String>>[]) {
      final dataUrl = document['data']!;
      final comma = dataUrl.indexOf(',');
      if (comma < 0) continue;
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      uploadIds.add(
        await api.uploadMedia(
          token,
          filename: document['filename']!,
          mimeType: document['mimeType']!,
          bytes: bytes,
        ),
      );
    }

    await beforeSubmit?.call();
    final sendResult = await api.sendMessage(
      token,
      modelId: modelId,
      content: content,
      conversationId: conversationId,
      uploadIds: uploadIds,
      imageReferences: attachmentSegments,
      systemPrompt: systemPrompt,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      thinkingBudget: thinkingBudget,
      imageGenSize: imageGenSize,
      imageGenCount: imageGenCount,
      videoDuration: videoDuration,
      videoAspectRatio: videoAspectRatio,
      videoResolution: videoResolution,
      videoExtendMode: videoExtendMode,
      assistantId: assistantId,
      instructionInjectionIds: instructionInjectionIds,
      mcpTools: mcpTools,
      anonymous: anonymous,
      ephemeral: ephemeral,
      seedMessages: seedMessages,
      messageContextStates: messageContextStates,
    );
    if (!sendResult.isSuccess) {
      throw HttpException(sendResult.error ?? 'Failed to send message');
    }
    assistantMessageId = sendResult.assistantMessageId!;
    userMessageId = sendResult.userMessageId;

    // A successful submit response is the server-delivery acknowledgement.
    // Yield it before any optional follow-up read so the UI can clear its
    // sending state as soon as the backend accepts the message.
    yield ChatStreamChunk(
      content: '',
      isDone: false,
      totalTokens: 0,
      providerMessageId: assistantMessageId,
      userMessageProviderId: userMessageId,
    );

    // The structured-reference field was added after the first hosted-chat
    // protocol. An old backend (or a backend whose new container was not
    // restarted) can silently ignore that unknown JSON field and still start
    // a successful text-only generation. Do not let that failure masquerade
    // as a model-vision problem: verify the canonical user row before the
    // background generation is allowed to run.
    final hasAttachmentReference =
        (attachmentSegments ?? const <Map<String, dynamic>>[]).any(
          (segment) => segment['type'] == 'attachment',
        );
    if (hasAttachmentReference && userMessageId != null) {
      final persisted = await api.getMessage(token, userMessageId);
      final persistedHasAttachmentReference =
          persisted?.attachmentReferences.any(
            (segment) => segment['type'] == 'attachment',
          ) ??
          false;
      if (!persistedHasAttachmentReference) {
        throw HttpException(
          'Hosted backend does not support structured attachment references. '
          'Restart or update the self-hosted backend before sending this message.',
        );
      }
    }
  }

  final initialContent = resumeAssistantMessageId != null
      ? resumeKnownContent
      : '';
  final initialReasoning = resumeAssistantMessageId != null
      ? resumeKnownReasoning
      : '';
  var previousContent = StringBuffer()..write(initialContent);
  var previousReasoning = StringBuffer()..write(initialReasoning);
  var contentOffsetBytes = utf8.encode(initialContent).length;
  var reasoningOffsetBytes = utf8.encode(initialReasoning).length;
  String? previousActivitySignature;
  var reconnectDelayMs = 500;
  while (true) {
    var toolResultsSubmitted = false;
    try {
      await for (final msg in api.streamMessage(
        token,
        assistantMessageId,
        contentOffsetBytes: contentOffsetBytes,
        reasoningOffsetBytes: reasoningOffsetBytes,
      )) {
        final requestedContentOffset = contentOffsetBytes;
        final requestedReasoningOffset = reasoningOffsetBytes;
        late final String delta;
        var terminalContentReset = false;
        var terminalReasoningReset = false;
        if (msg.contentStartByte == requestedContentOffset) {
          delta = msg.content;
          previousContent.write(delta);
          contentOffsetBytes += utf8.encode(delta).length;
        } else if (msg.contentStartByte == 0 &&
            msg.content.startsWith(previousContent.toString())) {
          // Compatibility with an older backend that ignores the cursor and
          // still returns the complete accumulated message.
          final accumulated = previousContent.toString();
          delta = msg.content.substring(accumulated.length);
          previousContent = StringBuffer()..write(msg.content);
          contentOffsetBytes += utf8.encode(delta).length;
        } else {
          // The server reset this draft (such as when it starts a new tool
          // round). Resume from the new byte-zero snapshot.
          delta = msg.content;
          terminalContentReset = msg.isFinished;
          previousContent = StringBuffer()..write(msg.content);
          contentOffsetBytes = utf8.encode(msg.content).length;
        }

        final reasoningText = msg.reasoningText ?? '';
        late final String reasoningDelta;
        if (msg.reasoningStartByte == requestedReasoningOffset) {
          reasoningDelta = reasoningText;
          previousReasoning.write(reasoningDelta);
          reasoningOffsetBytes += utf8.encode(reasoningDelta).length;
        } else if (msg.reasoningStartByte == 0 &&
            reasoningText.startsWith(previousReasoning.toString())) {
          final accumulated = previousReasoning.toString();
          reasoningDelta = reasoningText.substring(accumulated.length);
          previousReasoning = StringBuffer()..write(reasoningText);
          reasoningOffsetBytes += utf8.encode(reasoningDelta).length;
        } else {
          reasoningDelta = reasoningText;
          terminalReasoningReset = msg.isFinished;
          previousReasoning = StringBuffer()..write(reasoningText);
          reasoningOffsetBytes = utf8.encode(reasoningText).length;
        }
        final activitySignature = jsonEncode(msg.agentActivity);
        final activityChanged = activitySignature != previousActivitySignature;
        if (activityChanged) previousActivitySignature = activitySignature;
        if (delta.isNotEmpty || reasoningDelta.isNotEmpty) {
          reconnectDelayMs = 500;
        }

        if (msg.status == 'failed') {
          await _clearHostedToolExecutions(assistantMessageId);
          // `isDone: true` here would route this chunk through
          // `_handleStreamFinish` (chat_actions.dart) — the NORMAL-completion
          // handler, which cancels this stream's subscription as part of
          // finishing. Once that happens, this generator's execution never
          // resumes past the `yield` below, so the `throw` on the next line
          // would never actually run — `_handleStreamError` (and the real
          // error message) never gets a chance to fire, and the message lands
          // "done" with whatever content had streamed so far (often empty).
          // `isDone: false` instead routes this through `_handleContentChunk`,
          // which doesn't cancel anything — any partial content/reasoning
          // still reaches `state.fullContentRaw` before the `throw` below
          // propagates through `onError` into `_handleStreamError`, which is
          // what actually turns `msg.error` into visible bubble content.
          if (delta.isNotEmpty ||
              reasoningDelta.isNotEmpty ||
              activityChanged) {
            yield ChatStreamChunk(
              content: delta,
              reasoning: reasoningDelta.isEmpty ? null : reasoningDelta,
              isDone: false,
              totalTokens: msg.totalTokens ?? 0,
              usage: _usageFrom(msg),
              providerMessageId: assistantMessageId,
              hostedAgentActivity: activityChanged ? msg.agentActivity : null,
            );
          }
          throw HttpException(msg.error ?? 'Hosted generation failed');
        }
        if (msg.status == 'awaiting_tool' && msg.pendingToolCalls != null) {
          if (activityChanged) {
            yield ChatStreamChunk(
              content: '',
              isDone: false,
              totalTokens: 0,
              providerMessageId: assistantMessageId,
              hostedAgentActivity: msg.agentActivity,
            );
          }
          // [kelivo-hosted] Run each client-device-only tool call the server is
          // parked on, then post results back so it can resume — same
          // `onToolCall` handler BYOK providers already invoke for their own
          // (in-process) tool-calling loop, just triggered from an SSE status
          // of a streamed `tool_calls` delta.
          final results = <Map<String, String>>[];
          var messageAlreadyResumed = false;
          for (final call in msg.pendingToolCalls!) {
            final execution = await _executeHostedToolOnce(
              api: api,
              token: token,
              messageId: assistantMessageId,
              toolCallId: call.id,
              toolName: call.name,
              arguments: call.arguments,
              onToolCall: onToolCall,
            );
            if (execution.messageResumed) {
              messageAlreadyResumed = true;
              break;
            }
            results.add({
              'tool_call_id': call.id,
              'result': execution.result ?? '',
              'execution_key': execution.executionKey,
            });
          }
          if (!messageAlreadyResumed) {
            await api.submitToolResults(token, assistantMessageId, results);
          }
          toolResultsSubmitted = true;
          break;
        }
        if (msg.isFinished) {
          await _clearHostedToolExecutions(assistantMessageId);
          yield ChatStreamChunk(
            content: stream ? delta : previousContent.toString(),
            reasoning: reasoningDelta.isEmpty ? null : reasoningDelta,
            isDone: true,
            totalTokens: msg.totalTokens ?? 0,
            usage: _usageFrom(msg),
            providerMessageId: assistantMessageId,
            replaceContent: terminalContentReset,
            replaceReasoning: terminalReasoningReset,
            hostedAgentActivity: activityChanged ? msg.agentActivity : null,
          );
          return;
        }
        if ((stream && (delta.isNotEmpty || reasoningDelta.isNotEmpty)) ||
            activityChanged) {
          yield ChatStreamChunk(
            content: stream ? delta : '',
            reasoning: stream && reasoningDelta.isNotEmpty
                ? reasoningDelta
                : null,
            isDone: false,
            totalTokens: 0,
            providerMessageId: assistantMessageId,
            hostedAgentActivity: activityChanged ? msg.agentActivity : null,
          );
        }
      }
    } on TimeoutException {
      // The SSE byte stream did not deliver even a heartbeat in time. Treat
      // it like a dropped connection and resume from the current cursors.
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // A message deleted on another device is an expected end to the local
        // subscription; keep the already received partial reply.
        yield ChatStreamChunk(
          content: stream ? '' : previousContent.toString(),
          isDone: true,
          totalTokens: 0,
          providerMessageId: assistantMessageId,
        );
        return;
      }
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw HttpException(
          'Hosted chat session expired; please sign in again',
        );
      }
      final statusCode = e.response?.statusCode;
      final retryableStatus =
          statusCode == null ||
          statusCode >= 500 ||
          statusCode == 408 ||
          statusCode == 425 ||
          statusCode == 429;
      if (!retryableStatus) {
        rethrow;
      }
    }
    if (toolResultsSubmitted) continue;
    await Future.delayed(Duration(milliseconds: reconnectDelayMs));
    reconnectDelayMs = (reconnectDelayMs * 2).clamp(500, 5000).toInt();
  }
}

/// Backend token counts (`client_chat_task.py`'s usage-chunk capture) only
/// ever arrive on the terminal SSE event once `status` is `done`/`failed` — null
/// while still generating. Absent entirely if the upstream provider didn't
/// report usage (see `ClientChatMessage`'s doc comment).
TokenUsage? _usageFrom(ClientChatMessage msg) {
  if (msg.promptTokens == null &&
      msg.completionTokens == null &&
      msg.totalTokens == null) {
    return null;
  }
  return TokenUsage(
    promptTokens: msg.promptTokens ?? 0,
    completionTokens: msg.completionTokens ?? 0,
    totalTokens: msg.totalTokens ?? 0,
  );
}

String _lastUserMessageContent(List<Map<String, dynamic>> messages) {
  for (final m in messages.reversed) {
    if (m['role'] == 'user') {
      final c = m['content'];
      if (c is String) return c;
      // Multimodal content (list of parts) — image parts are sent
      // separately via `userImagePaths` (see `_sendHostedStream`), not
      // embedded in `content`, so only the text parts belong here.
      if (c is List) {
        return c
            .whereType<Map>()
            .where((p) => p['type'] == 'text')
            .map((p) => (p['text'] ?? '').toString())
            .join('\n');
      }
    }
  }
  return '';
}

// [kelivo-hosted] `MessageBuilderService.processUserMessagesForApi`
// (message_builder_service.dart) still inlines each attached file's
// locally-extracted text into `content` as `## user sent a file: <name>\n
// <content>\n```\n<text>\n```\n</content>` — the convention every BYOK
// provider needs (no native file input, this text block is the only way to
// hand them a file's contents). Hosted doesn't need this: the file's raw
// bytes go via the structured `documents` field instead (see
// `_sendHostedStream`'s use of `userDocuments`, sent as a native file
// content part server-side — `build_upstream_content` in
// client_message_files.py), so the template is just noise here — strip it
// back out rather than touching `processUserMessagesForApi` itself, which
// every other provider still needs unchanged.
final RegExp _hostedFileBlockRe = RegExp(
  r'## user sent a file: (.+?)\n<content>\n```\n(.*?)\n```\n</content>\n*',
  dotAll: true,
);

// [kelivo-hosted] `[image:<local path>]` / `[file:<path>|<name>|<mime>]`
// markers (`message_generation_service.dart`'s
// `buildPersistedUserMessageContent`) are on-device-only artifacts for this
// device's own transcript rendering — the real bytes already travel
// separately via `images`/`documents` (`userImagePaths`/`userDocuments`
// above). `processUserMessagesForApi` re-emits these same markers into
// `content` (needed for BYOK providers, which parse them back out
// per-provider before building their own request), but hosted never does
// that parsing — left unstripped here, a marker leaks the sending device's
// local filesystem path straight into `content` sent to the hosted backend.
// For a video-generation model that leak is worse than cosmetic: that
// `content` becomes the literal `prompt` string relayed to the upstream
// provider (client_chat_task.py's `_last_user_text`/`_stream_video_generation`),
// so an unstripped marker was reaching the real AI model as prompt text.
final RegExp _hostedImageMarkerRe = RegExp(r'\n?\[image:[^\]]*\]');
final RegExp _hostedFileMarkerRe = RegExp(r'\n?\[file:[^\]]*\]');

String _stripHostedFileBlocks(String content) {
  return content
      .replaceAll(_hostedFileBlockRe, '')
      .replaceAll(_hostedImageMarkerRe, '')
      .replaceAll(_hostedFileMarkerRe, '')
      .trim();
}
