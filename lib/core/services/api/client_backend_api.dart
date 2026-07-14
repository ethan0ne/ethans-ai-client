import 'package:dio/dio.dart';

import '../../models/model_types.dart';

/// Talks to the `/__client/*` routes of the AI Inspector backend — the
/// Kelivo-hosted-client product line's own account/billing API, separate
/// from the per-provider adapters in `core/services/api` that call AI
/// providers directly (see kelivo-arch.md 1.1/8).
class ClientBackendApi {
  ClientBackendApi({required this.baseUrl, Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl));

  final String baseUrl;
  final Dio _dio;

  /// [kelivo-hosted] Full authorize URL for the OIDC login WebView to
  /// navigate to — `GET /__client/auth/oidc/start` on the backend, which
  /// stashes PKCE/state/nonce server-side (this is a BFF flow: the backend
  /// holds the IdP client_secret, never shipped in the app) and 307s to
  /// account.ethan0ne.com's actual authorization_endpoint. [returnUri] is
  /// only ever set by the Linux system-browser exception — every other
  /// platform drives this from an in-app WebView and instead intercepts
  /// the navigation to `GET /auth/oidc/complete` (see `oidc_login_page.dart`).
  String oidcStartUrl({String? returnUri}) {
    final uri = Uri.parse('$baseUrl/__client/auth/oidc/start').replace(
      queryParameters: returnUri != null ? {'return_uri': returnUri} : null,
    );
    return uri.toString();
  }

  /// [kelivo-hosted] Redeems the one-time ticket handed back by the OIDC
  /// callback for this session's real access token — see
  /// `app/services/client_oidc.py`'s `issue_ticket`/`redeem_ticket` for why
  /// the token itself never appears in a URL the WebView/browser can see.
  Future<ClientAuthTokenResult> exchangeOidcTicket(String ticket) async {
    try {
      final res = await _dio.post(
        '/__client/auth/oidc/exchange',
        data: {'ticket': ticket},
      );
      final token = res.data['access_token'] as String;
      return ClientAuthTokenResult.success(token);
    } on DioException catch (e) {
      return ClientAuthTokenResult.failure(_extractError(e));
    }
  }

  Future<ClientUserInfo?> fetchMe(String token) async {
    final result = await fetchMeResult(token);
    return result.user;
  }

  /// Same call as [fetchMe], but distinguishes "token rejected by the
  /// server" (401/403 — the token is genuinely invalid/expired) from any
  /// other failure (timeout, DNS, 5xx, offline). Callers that decide
  /// whether to sign the user out (`AuthProvider._restore`) need this
  /// distinction: only the former should ever clear a stored token, since
  /// the latter can happen at any point purely from a flaky network and
  /// says nothing about the token's validity.
  Future<ClientMeResult> fetchMeResult(String token) async {
    try {
      final res = await _dio.get(
        '/__client/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return ClientMeResult.success(
        ClientUserInfo.fromJson(res.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return const ClientMeResult.unauthorized();
      }
      return const ClientMeResult.networkError();
    }
  }

  /// [kelivo-hosted] Sets (or, with `modelId: null`, clears) the account's
  /// preferred title-generation model — mirrors the local BYOK
  /// `SettingsProvider.setTitleModel`/`resetTitleModel`, pushed server-side
  /// so `generateTitle` and the server's own post-first-reply auto-title
  /// hook (backend/app/services/client_chat_task.py) know which hosted
  /// model to use.
  Future<bool> updateTitleModel(String token, String? modelId) async {
    try {
      await _dio.patch(
        '/__client/auth/me',
        data: {'title_model_id': modelId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on DioException {
      return false;
    }
  }

  /// [kelivo-hosted] Asks the server to (re)generate this conversation's
  /// title — BYOK's `ChatApiService.generateText` has no hosted branch
  /// (there's no direct provider the client could call for a hosted
  /// account), so the LLM call happens server-side instead. [modelId]
  /// overrides the account's title-model preference for this call only.
  Future<ClientGenerateTitleResult> generateTitle(
    String token,
    String conversationId, {
    String? modelId,
  }) async {
    try {
      final res = await _dio.post(
        '/__client/conversations/$conversationId/generate-title',
        data: {if (modelId != null) 'model_id': modelId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return ClientGenerateTitleResult.success(res.data['title'] as String);
    } on DioException catch (e) {
      return ClientGenerateTitleResult.failure(_extractError(e));
    }
  }

  /// Models available through the platform-held-key gateway
  /// (kelivo-arch.md 4) — display only for now, not yet wired into chat
  /// sending (that lands with the AI-proxy step).
  Future<ClientModelListResult> fetchModels(String token) async {
    try {
      final res = await _dio.get(
        '/__client/models',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final list = (res.data as List)
          .map((e) => ClientModelInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      return ClientModelListResult.success(list);
    } on DioException catch (e) {
      return ClientModelListResult.failure(_extractError(e));
    }
  }

  /// [kelivo-hosted] `role -> model_id` map (OCR/suggestion/translation/
  /// context-compression today — see `DefaultModelRole` server-side)
  /// admin-assigned via `ClientDefaultModelsView.vue`. `ClientBackendSession.refresh`
  /// caches this alongside the model list; a role missing from the map
  /// means no admin has assigned one yet — the caller decides the fallback
  /// (see each feature's own model-resolution code).
  Future<Map<String, String>> fetchDefaultModels(String token) async {
    try {
      final res = await _dio.get(
        '/__client/models/defaults',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final out = <String, String>{};
      for (final e in (res.data as List)) {
        final m = e as Map<String, dynamic>;
        final role = m['role'] as String?;
        final modelId = m['model_id'] as String?;
        if (role != null && modelId != null) out[role] = modelId;
      }
      return out;
    } on DioException catch (_) {
      return const {};
    }
  }

  /// Submits a prompt and returns immediately — the assistant reply is
  /// generated by a detached background task on the server
  /// (kelivo-arch.md 5), so the caller doesn't block on it here. Poll
  /// [getMessage] with the returned `assistantMessageId` to watch it
  /// progress through pending -> streaming -> done/failed, including after
  /// reconnecting from a dropped connection or backgrounded app.
  Future<ClientSendMessageResult> sendMessage(
    String token, {
    required String modelId,
    required String content,
    String? conversationId,
    // `data:<mime>;base64,<...>` strings — same encoding
    // `_encodeBase64File` already produces for BYOK providers' vision input
    // (chat_api_service.dart), reused as-is (kelivo-arch.md 5's image
    // support: no separate upload step).
    List<String>? images,
    // [kelivo-hosted] Non-image file attachments (PDF/txt/etc) — raw bytes,
    // same `data:<mime>;base64,<...>` encoding `images` uses, plus a
    // filename/mimeType the server can't infer from the data URL alone
    // (image mime types are self-describing enough; document ones aren't).
    // Sent to the upstream model as a native file content part
    // (`build_upstream_content` in client_message_files.py) — the server
    // never extracts text from these itself. See `hosted.dart`'s
    // `_sendHostedStream`.
    List<Map<String, String>>? documents,
    // [kelivo-hosted] kelivo-arch.md §5 — assistant-level settings that used
    // to be computed client-side (system prompt with memory/instructions/
    // world-book already baked in, generation params) and then silently
    // discarded before reaching the hosted backend. See hosted.dart.
    String? systemPrompt,
    double? temperature,
    double? topP,
    int? maxTokens,
    // [kelivo-hosted] Generation options for image-type models — only
    // meaningful when `modelId` resolves to
    // `ClientModelCatalogEntry.model_type == "image"` server-side
    // (`client_chat_task.py`'s `_generate_loop`/`_stream_image_generation`).
    // Same persist-on-conversation lifecycle as `temperature`/`topP`/
    // `maxTokens` above.
    String? imageGenSize,
    int? imageGenCount,
    // [kelivo-hosted] Generation options for video-type models — only
    // meaningful when `modelId` resolves to
    // `ClientModelCatalogEntry.model_type == "video"` server-side. Same
    // persist-on-conversation lifecycle as the image generation options
    // above.
    int? videoDuration,
    String? videoAspectRatio,
    String? videoResolution,
    bool? videoExtendMode,
    // [kelivo-hosted] the Flutter `Assistant.id` driving this turn — lets
    // the server look up this assistant's synced `enable_memory` flag/
    // memories for tool-calling (see `client_memory_tools.py`).
    String? assistantId,
    // [kelivo-hosted] OpenAI function-calling-format tool defs for the
    // assistant's currently-connected/enabled MCP servers — dynamic and
    // client-owned (which servers are connected right now), unlike the
    // server-known memory/local tools, so it has to ride along on every
    // send instead of being resolved from a DB row. Persisted onto the
    // conversation server-side (`ClientConversation.mcp_tools`) and merged
    // into the upstream `tools` list; see hosted.dart.
    List<Map<String, dynamic>>? mcpTools,
    // [kelivo-hosted] One-shot features (translation/OCR/hosted suggestion &
    // context-compression generation) never pass `conversationId`, so this
    // turn always creates a brand-new conversation server-side — setting
    // this excludes that conversation from `GET /conversations` (and gets
    // it age-cleaned) instead of permanently cluttering the user's real
    // conversation list. Only meaningful together with `conversationId ==
    // null`; the server ignores it when reusing an existing conversation.
    bool ephemeral = false,
    // [kelivo-hosted] Prior conversation history to seed a brand-new
    // conversation with — see `SendMessageRequest.seed_messages`'s
    // docstring (client_chat.py). Each entry is
    // `{'role', 'content', 'images'?, 'documents'?}`
    // (`ChatService.buildHostedSeedMessages`'s output shape — `documents`
    // already uses this same `{'filename', 'mimeType', 'data'}` convention
    // the top-level `documents` param above does). Ignored server-side
    // when [conversationId] already exists, so safe to pass unconditionally.
    List<Map<String, dynamic>>? seedMessages,
  }) async {
    try {
      final res = await _dio.post(
        '/__client/messages',
        data: {
          'model_id': modelId,
          'content': content,
          if (conversationId != null) 'conversation_id': conversationId,
          if (images != null && images.isNotEmpty) 'images': images,
          if (documents != null && documents.isNotEmpty)
            'documents': documents
                .map(
                  (d) => {
                    'filename': d['filename'] ?? 'file',
                    'mime_type': d['mimeType'] ?? 'application/octet-stream',
                    'data': d['data'] ?? '',
                  },
                )
                .toList(),
          if (systemPrompt != null) 'system_prompt': systemPrompt,
          if (temperature != null) 'temperature': temperature,
          if (topP != null) 'top_p': topP,
          if (maxTokens != null) 'max_tokens': maxTokens,
          if (imageGenSize != null) 'image_size': imageGenSize,
          if (imageGenCount != null) 'image_count': imageGenCount,
          if (videoDuration != null) 'video_duration': videoDuration,
          if (videoAspectRatio != null) 'video_aspect_ratio': videoAspectRatio,
          if (videoResolution != null) 'video_resolution': videoResolution,
          if (videoExtendMode != null) 'video_extend_mode': videoExtendMode,
          if (assistantId != null) 'assistant_id': assistantId,
          if (mcpTools != null) 'mcp_tools': mcpTools,
          if (ephemeral) 'ephemeral': true,
          if (seedMessages != null && seedMessages.isNotEmpty)
            'seed_messages': seedMessages
                .map(
                  (m) => {
                    'role': m['role'],
                    'content': m['content'],
                    if (m['images'] != null) 'images': m['images'],
                    if (m['documents'] != null)
                      'documents': (m['documents'] as List)
                          .map(
                            (d) => {
                              'filename': d['filename'] ?? 'file',
                              'mime_type':
                                  d['mimeType'] ?? 'application/octet-stream',
                              'data': d['data'] ?? '',
                            },
                          )
                          .toList(),
                  },
                )
                .toList(),
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return ClientSendMessageResult.success(
        conversationId: res.data['conversation_id'] as String,
        userMessageId: res.data['user_message_id'] as String,
        assistantMessageId: res.data['assistant_message_id'] as String,
      );
    } on DioException catch (e) {
      return ClientSendMessageResult.failure(_extractError(e));
    }
  }

  /// [kelivo-hosted] Regenerate produces another *version* of [messageId]'s
  /// reply — sharing its `group_id` (returned below) rather than submitting
  /// the prompt again as an unrelated new turn (which used to create a
  /// second, duplicate user+assistant pair server-side; see
  /// `ClientMessage.group_id`'s docstring on the backend). Poll [getMessage]
  /// with the returned `assistantMessageId` the same way [sendMessage] is
  /// polled.
  Future<ClientRegenerateResult> regenerateMessage(
    String token,
    String messageId, {
    String? modelId,
    String? systemPrompt,
    double? temperature,
    double? topP,
    int? maxTokens,
    String? imageGenSize,
    int? imageGenCount,
    int? videoDuration,
    String? videoAspectRatio,
    String? videoResolution,
    bool? videoExtendMode,
    String? assistantId,
    List<Map<String, dynamic>>? mcpTools,
  }) async {
    try {
      final res = await _dio.post(
        '/__client/messages/$messageId/regenerate',
        data: {
          if (modelId != null) 'model_id': modelId,
          if (systemPrompt != null) 'system_prompt': systemPrompt,
          if (temperature != null) 'temperature': temperature,
          if (topP != null) 'top_p': topP,
          if (maxTokens != null) 'max_tokens': maxTokens,
          if (imageGenSize != null) 'image_size': imageGenSize,
          if (imageGenCount != null) 'image_count': imageGenCount,
          if (videoDuration != null) 'video_duration': videoDuration,
          if (videoAspectRatio != null) 'video_aspect_ratio': videoAspectRatio,
          if (videoResolution != null) 'video_resolution': videoResolution,
          if (videoExtendMode != null) 'video_extend_mode': videoExtendMode,
          if (assistantId != null) 'assistant_id': assistantId,
          if (mcpTools != null) 'mcp_tools': mcpTools,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return ClientRegenerateResult.success(
        assistantMessageId: res.data['assistant_message_id'] as String,
        groupId: res.data['group_id'] as String,
        version: res.data['version'] as int,
      );
    } on DioException catch (e) {
      return ClientRegenerateResult.failure(_extractError(e));
    }
  }

  /// [kelivo-hosted] Registers an edit to a USER message as a new version
  /// sharing [messageId]'s `group_id` — the hosted counterpart of
  /// [regenerateMessage] but for the user side of a turn, called from
  /// `ChatService.appendMessageVersion` for `hostedSynced` conversations.
  /// Without this, an edit only ever lived in the editing device's local
  /// storage: it never reached the server, so no other device could see it
  /// or page between versions, and the next hosted regenerate would still
  /// prompt from the stale original text.
  Future<ClientEditMessageResult> editUserMessage(
    String token,
    String messageId,
    String content,
  ) async {
    try {
      final res = await _dio.post(
        '/__client/messages/$messageId/edit',
        data: {'content': content},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return ClientEditMessageResult.success(
        messageId: res.data['message_id'] as String,
        groupId: res.data['group_id'] as String,
        version: res.data['version'] as int,
      );
    } on DioException catch (e) {
      return ClientEditMessageResult.failure(_extractError(e));
    }
  }

  Future<ClientChatMessage?> getMessage(String token, String messageId) async {
    try {
      final res = await _dio.get(
        '/__client/messages/$messageId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return ClientChatMessage.fromJson(res.data as Map<String, dynamic>);
    } on DioException {
      return null;
    }
  }

  /// [kelivo-hosted] Posts back the results of client-device-only tool
  /// calls (`clipboard_tool`/`text_to_speech`/`ask_user_input_v0`) executed
  /// locally in response to a `status == "awaiting_tool"` message's
  /// `pendingToolCalls` — resumes server-side generation. Returns
  /// immediately (202); the caller keeps polling [getMessage] the same way
  /// it already does for the initial send.
  Future<bool> submitToolResults(
    String token,
    String messageId,
    List<Map<String, String>> results,
  ) async {
    try {
      await _dio.post(
        '/__client/messages/$messageId/tool-results',
        data: {'results': results},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on DioException {
      return false;
    }
  }

  /// [kelivo-hosted] The "stop generating" button, for a hosted reply —
  /// generation keeps running server-side regardless of whether the client
  /// is still polling (kelivo-arch.md 5's whole design), so stopping the
  /// local poll loop alone never actually stopped generation. This tells
  /// the server to interrupt it (see `ClientMessage.cancel_requested`).
  /// Best-effort — a failure here just means the local poll loop already
  /// stopped and the server keeps generating unseen, same as before this
  /// existed, so callers fire-and-forget it.
  Future<bool> cancelMessage(String token, String messageId) async {
    try {
      await _dio.post(
        '/__client/messages/$messageId/cancel',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on DioException {
      return false;
    }
  }

  Future<List<ClientChatMessage>?> listConversationMessages(
    String token,
    String conversationId,
  ) async {
    try {
      final res = await _dio.get(
        '/__client/conversations/$conversationId/messages',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (res.data as List)
          .map((e) => ClientChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException {
      return null;
    }
  }

  /// [kelivo-hosted] Conversation-list sync (kelivo-arch.md 5) — used to
  /// discover conversations created (or hidden/deleted) on another device
  /// that this device never saw locally. Returns null on any failure so
  /// the caller can no-op the sync rather than wipe local state.
  Future<List<ClientConversationSummary>?> listConversations(
    String token,
  ) async {
    try {
      final res = await _dio.get(
        '/__client/conversations',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (res.data as List)
          .map(
            (e) =>
                ClientConversationSummary.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException {
      return null;
    }
  }

  /// [kelivo-hosted] Pushes a locally-changed title to the server
  /// (kelivo-arch.md 5) — last-writer-wins, no per-field diffing. A 404
  /// (already gone) is treated the same as success by the caller.
  Future<bool> updateConversationTitle(
    String token,
    String conversationId,
    String title,
  ) async {
    try {
      await _dio.patch(
        '/__client/conversations/$conversationId',
        data: {'title': title},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on DioException catch (e) {
      return e.response?.statusCode == 404;
    }
  }

  /// [kelivo-hosted] Soft-deletes (hides) the conversation server-side
  /// (kelivo-arch.md 5) — a 404 (already gone) is treated the same as
  /// success by the caller.
  Future<bool> deleteConversation(String token, String conversationId) async {
    try {
      await _dio.delete(
        '/__client/conversations/$conversationId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on DioException catch (e) {
      return e.response?.statusCode == 404;
    }
  }

  /// [kelivo-hosted] Soft-deletes (hides) the message server-side
  /// (kelivo-arch.md 5) — a 404 (already gone) is treated the same as
  /// success by the caller.
  Future<bool> deleteMessage(String token, String messageId) async {
    try {
      await _dio.delete(
        '/__client/messages/$messageId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on DioException catch (e) {
      return e.response?.statusCode == 404;
    }
  }

  /// [kelivo-hosted] Assistant cloud sync — full-list pull, used on
  /// launch/login to decide whether to adopt the cloud copy or seed local
  /// defaults (see `AssistantProvider._load`). Returns null on failure so
  /// the caller can no-op rather than wipe local state.
  Future<List<ClientAssistantSummary>?> listAssistants(String token) async {
    try {
      final res = await _dio.get(
        '/__client/assistants',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return (res.data as List)
          .map(
            (e) => ClientAssistantSummary.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException {
      return null;
    }
  }

  /// Full-row upsert — the client always sends its complete
  /// `Assistant.toJson()` payload, last-writer-wins, no per-field diffing
  /// (same convention as `updateConversationTitle`).
  Future<bool> upsertAssistant(
    String token,
    String clientId, {
    required Map<String, dynamic> data,
    required bool enableMemory,
    List<String> localToolIds = const [],
  }) async {
    try {
      await _dio.put(
        '/__client/assistants/$clientId',
        data: {
          'data': data,
          'enable_memory': enableMemory,
          'local_tool_ids': localToolIds,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on DioException {
      return false;
    }
  }

  Future<bool> deleteAssistant(String token, String clientId) async {
    try {
      await _dio.delete(
        '/__client/assistants/$clientId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on DioException catch (e) {
      return e.response?.statusCode == 404;
    }
  }

  /// [kelivo-hosted] Manual memory management (assistant_settings_edit_memory_tab.dart's
  /// "管理记忆" list) for a `cloudHosted` assistant — reads the same
  /// `client_assistant_memories` rows the model's own `create_memory`/
  /// `edit_memory`/`delete_memory` tool calls write during hosted chat
  /// (`client_memory_tools.py`), so memories the model saved show up here,
  /// and ones added manually here reach the model on its next turn.
  Future<ClientAssistantMemoryListResult> listAssistantMemories(
    String token,
    String assistantClientId,
  ) async {
    try {
      final res = await _dio.get(
        '/__client/assistants/$assistantClientId/memories',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final list = (res.data as List)
          .map(
            (e) =>
                ClientAssistantMemoryInfo.fromJson(e as Map<String, dynamic>),
          )
          .toList();
      return ClientAssistantMemoryListResult.success(list);
    } on DioException catch (e) {
      return ClientAssistantMemoryListResult.failure(_extractError(e));
    }
  }

  Future<ClientAssistantMemoryInfo?> createAssistantMemory(
    String token,
    String assistantClientId,
    String content,
  ) async {
    try {
      final res = await _dio.post(
        '/__client/assistants/$assistantClientId/memories',
        data: {'content': content},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return ClientAssistantMemoryInfo.fromJson(
        res.data as Map<String, dynamic>,
      );
    } on DioException {
      return null;
    }
  }

  Future<ClientAssistantMemoryInfo?> updateAssistantMemory(
    String token,
    String assistantClientId,
    int memoryId,
    String content,
  ) async {
    try {
      final res = await _dio.patch(
        '/__client/assistants/$assistantClientId/memories/$memoryId',
        data: {'content': content},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return ClientAssistantMemoryInfo.fromJson(
        res.data as Map<String, dynamic>,
      );
    } on DioException {
      return null;
    }
  }

  Future<bool> deleteAssistantMemory(
    String token,
    String assistantClientId,
    int memoryId,
  ) async {
    try {
      await _dio.delete(
        '/__client/assistants/$assistantClientId/memories/$memoryId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on DioException catch (e) {
      return e.response?.statusCode == 404;
    }
  }

  String? _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return e.message;
  }
}

class ClientAuthTokenResult {
  const ClientAuthTokenResult.success(this.token) : error = null;
  const ClientAuthTokenResult.failure(this.error) : token = null;

  final String? token;
  final String? error;
  bool get isSuccess => error == null;
}

/// Outcome of [ClientBackendApi.fetchMeResult] — see its doc comment for why
/// "unauthorized" and "networkError" are kept apart instead of collapsing
/// to a single nullable result the way the other `/__client/*` calls do.
class ClientMeResult {
  const ClientMeResult.success(this.user)
    : unauthorized = false,
      networkError = false;
  const ClientMeResult.unauthorized()
    : user = null,
      unauthorized = true,
      networkError = false;
  const ClientMeResult.networkError()
    : user = null,
      unauthorized = false,
      networkError = true;

  final ClientUserInfo? user;
  final bool unauthorized;
  final bool networkError;
  bool get isSuccess => user != null;
}

class ClientUserInfo {
  ClientUserInfo({
    required this.id,
    required this.email,
    required this.username,
    required this.status,
    required this.balance,
  });

  factory ClientUserInfo.fromJson(Map<String, dynamic> json) {
    return ClientUserInfo(
      id: json['id'] as String,
      email: json['email'] as String,
      username: json['username'] as String?,
      status: json['status'] as String,
      balance: (json['balance'] as num).toDouble(),
    );
  }

  final String id;
  final String email;
  final String? username;
  final String status;
  final double balance;
}

class ClientModelListResult {
  const ClientModelListResult.success(this.models) : error = null;
  const ClientModelListResult.failure(this.error) : models = null;

  final List<ClientModelInfo>? models;
  final String? error;
  bool get isSuccess => error == null;
}

class ClientModelInfo {
  ClientModelInfo({
    required this.modelId,
    required this.displayName,
    this.type = ModelType.chat,
    this.input = const [Modality.text],
    this.output = const [Modality.text],
    this.abilities = const [],
    this.imageSizes = const [],
    this.videoDurations = '',
    this.videoResolutions = const [],
    this.videoAspectRatios = const [],
    this.videoExtendDurations = '',
  });

  /// Capability fields (`model_type`/`input_modalities`/`output_modalities`/
  /// `abilities`) are admin-curated server-side (kelivo-arch.md 4) — they
  /// mirror `ModelInfo`'s shape 1:1 so `HostedProvider` (model_provider.dart)
  /// can build a `ModelInfo` straight from this instead of guessing
  /// capabilities from the model id string via `ModelRegistry.infer`.
  factory ClientModelInfo.fromJson(Map<String, dynamic> json) {
    return ClientModelInfo(
      modelId: json['model_id'] as String,
      displayName: json['display_name'] as String,
      type: _parseModelType(json['model_type'] as String?),
      input: _parseModalities(json['input_modalities']),
      output: _parseModalities(json['output_modalities']),
      abilities: _parseAbilities(json['abilities']),
      imageSizes: _parseStringList(json['image_sizes']),
      videoDurations: json['video_durations'] as String? ?? '',
      videoResolutions: _parseStringList(json['video_resolutions']),
      videoAspectRatios: _parseStringList(json['video_aspect_ratios']),
      videoExtendDurations: json['video_extend_durations'] as String? ?? '',
    );
  }

  final String modelId;
  final String displayName;
  final ModelType type;
  final List<Modality> input;
  final List<Modality> output;
  final List<ModelAbility> abilities;
  final List<String> imageSizes;
  final String videoDurations;
  final List<String> videoResolutions;
  final List<String> videoAspectRatios;
  final String videoExtendDurations;

  static ModelType _parseModelType(String? value) {
    if (value == 'embedding') return ModelType.embedding;
    if (value == 'image') return ModelType.image;
    if (value == 'video') return ModelType.video;
    return ModelType.chat;
  }

  static List<Modality> _parseModalities(dynamic value) {
    if (value is! List) return const [Modality.text];
    final result = [
      for (final v in value)
        if (v == 'text') Modality.text else if (v == 'image') Modality.image,
    ];
    return result.isEmpty ? const [Modality.text] : result;
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is! List) return const [];
    return [
      for (final v in value)
        if (v is String) v,
    ];
  }

  static List<ModelAbility> _parseAbilities(dynamic value) {
    if (value is! List) return const [];
    return [
      for (final v in value)
        if (v == 'tool')
          ModelAbility.tool
        else if (v == 'reasoning')
          ModelAbility.reasoning,
    ];
  }
}

class ClientGenerateTitleResult {
  const ClientGenerateTitleResult.success(this.title) : error = null;
  const ClientGenerateTitleResult.failure(this.error) : title = null;

  final String? title;
  final String? error;
  bool get isSuccess => error == null;
}

class ClientSendMessageResult {
  const ClientSendMessageResult.success({
    required this.conversationId,
    required this.userMessageId,
    required this.assistantMessageId,
  }) : error = null;

  const ClientSendMessageResult.failure(this.error)
    : conversationId = null,
      userMessageId = null,
      assistantMessageId = null;

  final String? conversationId;
  final String? userMessageId;
  final String? assistantMessageId;
  final String? error;
  bool get isSuccess => error == null;
}

class ClientRegenerateResult {
  const ClientRegenerateResult.success({
    required this.assistantMessageId,
    required this.groupId,
    required this.version,
  }) : error = null;

  const ClientRegenerateResult.failure(this.error)
    : assistantMessageId = null,
      groupId = null,
      version = null;

  final String? assistantMessageId;
  final String? groupId;
  final int? version;
  final String? error;
  bool get isSuccess => error == null;
}

class ClientEditMessageResult {
  const ClientEditMessageResult.success({
    required this.messageId,
    required this.groupId,
    required this.version,
  }) : error = null;

  const ClientEditMessageResult.failure(this.error)
    : messageId = null,
      groupId = null,
      version = null;

  final String? messageId;
  final String? groupId;
  final int? version;
  final String? error;
  bool get isSuccess => error == null;
}

/// [kelivo-hosted] Row shape of `GET /__client/conversations`
/// (kelivo-arch.md 5) — deliberately smaller than the local `Conversation`
/// Hive model, just enough for `ChatService.syncConversationList` to
/// discover/reconcile conversations.
class ClientConversationSummary {
  ClientConversationSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ClientConversationSummary.fromJson(Map<String, dynamic> json) {
    return ClientConversationSummary(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// [kelivo-hosted] Row shape of `GET /__client/assistants` — `data` is the
/// Flutter `Assistant`'s entire `toJson()` payload, round-tripped verbatim
/// through `Assistant.fromJson` by the caller.
class ClientAssistantSummary {
  ClientAssistantSummary({
    required this.clientId,
    required this.data,
    required this.enableMemory,
    required this.updatedAt,
  });

  factory ClientAssistantSummary.fromJson(Map<String, dynamic> json) {
    return ClientAssistantSummary(
      clientId: json['client_id'] as String,
      data: Map<String, dynamic>.from(json['data'] as Map),
      enableMemory: json['enable_memory'] as bool,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final String clientId;
  final Map<String, dynamic> data;
  final bool enableMemory;
  final DateTime updatedAt;
}

class ClientAssistantMemoryListResult {
  const ClientAssistantMemoryListResult.success(this.memories) : error = null;
  const ClientAssistantMemoryListResult.failure(this.error) : memories = null;

  final List<ClientAssistantMemoryInfo>? memories;
  final String? error;
  bool get isSuccess => error == null;
}

/// [kelivo-hosted] Row shape of `GET/POST/PATCH .../assistants/{id}/memories`
/// — `id` is a plain int (the JSON-Schema `"type": "integer"` the
/// create_memory/edit_memory/delete_memory tool defs already declare, see
/// `client_memory_tools.py`), not a UUID like this app's other client-owned
/// tables.
class ClientAssistantMemoryInfo {
  ClientAssistantMemoryInfo({
    required this.id,
    required this.content,
    required this.updatedAt,
  });

  factory ClientAssistantMemoryInfo.fromJson(Map<String, dynamic> json) {
    return ClientAssistantMemoryInfo(
      id: json['id'] as int,
      content: json['content'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  final int id;
  final String content;
  final DateTime updatedAt;
}

/// [kelivo-hosted] An image attached to a `ClientChatMessage`, straight off
/// the backend's structured `ClientMessageOut.images` (see
/// `backend/app/schemas/client_chat.py`). Replaces the old convention of
/// scraping `![image](url)` markdown out of `content` — the server no
/// longer embeds that, so this is the only source of a hosted message's
/// attached images.
class ClientMessageImage {
  ClientMessageImage({
    required this.id,
    required this.direction,
    required this.mimeType,
    required this.sizeBytes,
    required this.url,
    required this.createdAt,
  });

  factory ClientMessageImage.fromJson(Map<String, dynamic> json) {
    return ClientMessageImage(
      id: json['id'] as String,
      direction: json['direction'] as String,
      mimeType: json['mime_type'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
      url: json['url'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  final String id;
  // "upload" | "generated"
  final String direction;
  final String mimeType;
  final int sizeBytes;
  // Authenticated file route (`/__client/message-images/{id}/file`) —
  // fetching it requires the same `Authorization: Bearer <jwt>` header as
  // every other `/__client/*` call.
  final String url;
  final DateTime createdAt;
}

/// [kelivo-hosted] A non-image file attachment (PDF/txt/etc) on a
/// `ClientChatMessage`, off the backend's structured `ClientMessageOut.files`
/// — the server keeps the original bytes (`save_uploaded_documents`) and
/// forwards them to the upstream model as a native file content part, same
/// as `ClientMessageImage`'s `url`.
class ClientMessageFile {
  ClientMessageFile({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.url,
    required this.createdAt,
  });

  factory ClientMessageFile.fromJson(Map<String, dynamic> json) {
    return ClientMessageFile(
      id: json['id'] as String,
      filename: json['filename'] as String,
      mimeType: json['mime_type'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
      url: json['url'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  final String id;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String url;
  final DateTime createdAt;
}

class ClientChatMessage {
  ClientChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.modelId,
    required this.content,
    this.images = const [],
    this.files = const [],
    this.reasoningText,
    required this.status,
    required this.error,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.groupId,
    this.version = 0,
    this.pendingToolCalls,
    required this.createdAt,
  });

  factory ClientChatMessage.fromJson(Map<String, dynamic> json) {
    return ClientChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      role: json['role'] as String,
      modelId: json['model_id'] as String?,
      content: json['content'] as String,
      images:
          (json['images'] as List?)
              ?.map(
                (e) => ClientMessageImage.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      files:
          (json['files'] as List?)
              ?.map(
                (e) => ClientMessageFile.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      reasoningText: json['reasoning_text'] as String?,
      status: json['status'] as String,
      error: json['error'] as String?,
      promptTokens: json['prompt_tokens'] as int?,
      completionTokens: json['completion_tokens'] as int?,
      totalTokens: json['total_tokens'] as int?,
      groupId: json['group_id'] as String?,
      version: (json['version'] as int?) ?? 0,
      pendingToolCalls: (json['pending_tool_calls'] as List?)
          ?.map((e) => PendingToolCall.fromJson(e as Map<String, dynamic>))
          .toList(),
      // Backend serializes UTC-aware timestamps (`datetime.now(timezone.utc)`)
      // — `.toLocal()` here matches how every locally-created `ChatMessage`
      // already gets its `timestamp` (`DateTime.now()`, already local); a
      // hosted message pulled via sync without this showed the raw UTC/DB
      // time verbatim (e.g. several hours off from every other message in
      // the same conversation, depending on the device's timezone).
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  final String id;
  final String conversationId;
  final String role;
  final String? modelId;
  final String content;
  final List<ClientMessageImage> images;
  final List<ClientMessageFile> files;
  // Reasoning/chain-of-thought text streamed alongside `content`, if the
  // model produced any (see backend `ClientMessage.reasoning_text`).
  final String? reasoningText;
  // "pending" | "streaming" | "awaiting_tool" | "done" | "failed" | "cancelled"
  final String status;
  final String? error;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  // [kelivo-hosted] regenerate versioning (backend `ClientMessage.group_id`/
  // `.version`) — every version of the same turn shares `groupId`. Mapped to
  // a local `hosted:$groupId` string on `ChatMessage.groupId` by
  // `chat_service.dart` so the existing BYOK version-pager collapses/pages
  // through them unmodified.
  final String? groupId;
  final int version;
  // [kelivo-hosted] Populated only while `status == "awaiting_tool"` — see
  // `PendingToolCall`'s doc comment.
  final List<PendingToolCall>? pendingToolCalls;
  final DateTime createdAt;

  bool get isFinished =>
      status == 'done' || status == 'failed' || status == 'cancelled';
}

/// [kelivo-hosted] A client-device-only tool call (`clipboard_tool`/
/// `text_to_speech`/`ask_user_input_v0`) the server parked generation on —
/// the hosted counterpart of what `ToolHandlerService.buildToolCallHandler`
/// already executes locally for BYOK. `hosted.dart` runs each of these
/// through the same `onToolCall` handler BYOK providers already use, then
/// posts results back via `ClientBackendApi.submitToolResults`.
class PendingToolCall {
  PendingToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  factory PendingToolCall.fromJson(Map<String, dynamic> json) {
    return PendingToolCall(
      id: json['id'] as String,
      name: json['name'] as String,
      arguments: Map<String, dynamic>.from(json['arguments'] as Map),
    );
  }

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}
