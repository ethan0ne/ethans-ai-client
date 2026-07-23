import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/chat_input_data.dart'
    show ChatInputData, DocumentAttachment;
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../utils/app_directories.dart';
import '../api/chat_api_service.dart';
import '../api/client_backend_api.dart';
import '../api/client_backend_config.dart';
import '../api/client_backend_session.dart';

/// [kelivo-hosted] JSON-encodes a hosted message's structured `images` list
/// (`ClientChatMessage.images`, see client_backend_api.dart) onto
/// `ChatMessage.hostedImagesJson` — null when there are none, so
/// `chat_message_widget.dart` can tell "no images" apart from "not a hosted
/// message at all" the same way.
String? _encodeHostedImagesJson(List<ClientMessageImage> images) {
  if (images.isEmpty) return null;
  return jsonEncode(
    images
        .map((img) => {'id': img.id, 'url': img.url, 'mimeType': img.mimeType})
        .toList(),
  );
}

/// [kelivo-hosted] Same idea as [_encodeHostedImagesJson], for a hosted
/// message's structured `files` list (non-image attachments).
String? _encodeHostedFilesJson(List<ClientMessageFile> files) {
  if (files.isEmpty) return null;
  return jsonEncode(
    files
        .map(
          (f) => {
            'id': f.id,
            'filename': f.filename,
            'mimeType': f.mimeType,
            'url': f.url,
          },
        )
        .toList(),
  );
}

/// [kelivo-hosted] Same idea as [_encodeHostedImagesJson], for a hosted
/// message's `search_citations` (the `search_web` tool's raw `items` for
/// whichever call the server executed for this turn — see
/// `ChatMessage.hostedSearchCitationsJson`'s docstring for why this can't be
/// reconstructed any other way).
String? _encodeHostedSearchCitationsJson(
  List<Map<String, dynamic>>? citations,
) {
  if (citations == null || citations.isEmpty) return null;
  return jsonEncode(citations);
}

class _HostedAttachmentRef {
  const _HostedAttachmentRef({
    required this.url,
    required this.mimeType,
    this.filename,
  });
  final String url;
  final String mimeType;
  final String? filename;
}

/// [kelivo-hosted] Inverse of [_encodeHostedImagesJson]/[_encodeHostedFilesJson]
/// — used by [ChatService._buildHostedSeedMessage] to re-fetch a hosted
/// message's attachments when seeding a forked conversation's history.
/// Tolerant of either JSON shape (`filename` is only ever present on the
/// files list) since both get decoded through this one path.
List<_HostedAttachmentRef> _decodeHostedAttachmentRefs(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final decoded = jsonDecode(json) as List;
    return decoded
        .map((e) {
          final m = e as Map<String, dynamic>;
          final url = m['url'] as String?;
          final mimeType = m['mimeType'] as String?;
          if (url == null || url.isEmpty || mimeType == null) return null;
          return _HostedAttachmentRef(
            url: url,
            mimeType: mimeType,
            filename: m['filename'] as String?,
          );
        })
        .whereType<_HostedAttachmentRef>()
        .toList();
  } catch (_) {
    return const [];
  }
}

class _ParsedLocalMarkers {
  const _ParsedLocalMarkers(this.text, this.imagePaths, this.documents);
  final String text;
  final List<String> imagePaths;
  final List<DocumentAttachment> documents;
}

/// [kelivo-hosted] Strips `[image:<path>]`/`[file:<path>|<name>|<mime>]`
/// markers (`message_generation_service.dart`'s
/// `buildPersistedUserMessageContent`) out of a local/BYOK-style message's
/// `content`, returning the plain text plus the extracted attachment
/// paths — used by [ChatService._buildHostedSeedMessage] to re-encode a
/// forked conversation's local attachments for the seed payload. Same
/// regex/parsing convention as `message_builder_service.dart`'s
/// `parseInputFromRaw` and `chat_message_widget.dart`'s `_parseUserContent`
/// — duplicated locally rather than reused because both of those are tied
/// to widget-tree-scoped classes (`BuildContext`/`StatelessWidget` state)
/// this data-layer service has no business depending on.
_ParsedLocalMarkers _parseLocalAttachmentMarkers(String raw) {
  final imgRe = RegExp(r'\[image:(.+?)\]');
  final fileRe = RegExp(r'\[file:(.+?)\|(.+?)\|(.+?)\]');
  final images = <String>[];
  final docs = <DocumentAttachment>[];
  final buffer = StringBuffer();
  int idx = 0;
  while (idx < raw.length) {
    final imgMatch = imgRe.matchAsPrefix(raw, idx);
    final fileMatch = fileRe.matchAsPrefix(raw, idx);
    if (imgMatch != null) {
      final path = imgMatch.group(1)?.trim();
      if (path != null && path.isNotEmpty) images.add(path);
      idx = imgMatch.end;
      continue;
    }
    if (fileMatch != null) {
      final path = fileMatch.group(1)?.trim() ?? '';
      final name = fileMatch.group(2)?.trim() ?? 'file';
      final mime = fileMatch.group(3)?.trim() ?? 'text/plain';
      if (path.isNotEmpty) {
        docs.add(DocumentAttachment(path: path, fileName: name, mime: mime));
      }
      idx = fileMatch.end;
      continue;
    }
    buffer.write(raw[idx]);
    idx++;
  }
  return _ParsedLocalMarkers(buffer.toString().trim(), images, docs);
}

/// [kelivo-hosted] Result of reconciling a stale-streaming hosted message
/// against the server's authoritative state — see `_reconcileHostedMessage`.
class _HostedReconcileResult {
  _HostedReconcileResult(this.message, this.stillInProgress);

  final ChatMessage message;
  final bool stillInProgress;
}

class ChatService extends ChangeNotifier {
  static const String _conversationsBoxName = 'conversations';
  static const String _messagesBoxName = 'messages';
  static const String _toolEventsBoxName = 'tool_events_v1';
  static const String _activeStreamingKey = '_active_streaming_ids';
  static const int defaultInitialMessageMin = 2;
  static const int defaultInitialMessageMax = 240;
  static const int defaultInitialTextBudget = 20000;
  static const int defaultHistoryPageSize = 20;
  static const int defaultLoadedWindowMax = 360;

  late Box<Conversation> _conversationsBox;
  late Box<ChatMessage> _messagesBox;
  late Box
  _toolEventsBox; // key: assistantMessageId, value: List<Map<String,dynamic>>
  String _sigKey(String id) => 'sig_$id';

  String? _currentConversationId;
  final Map<String, List<ChatMessage>> _messagesCache = {};
  final Map<String, Conversation> _draftConversations = {};
  final Set<String> _temporaryConversationIds = <String>{};
  final Map<String, List<Map<String, dynamic>>> _temporaryToolEvents =
      <String, List<Map<String, dynamic>>>{};
  final Map<String, String> _temporaryGeminiThoughtSigs = <String, String>{};

  // Localized default title for new conversations; set by UI on startup.
  String _defaultConversationTitle = 'New Chat';
  void setDefaultConversationTitle(String title) {
    if (title.trim().isEmpty) return;
    _defaultConversationTitle = title.trim();
  }

  bool _initialized = false;
  bool get initialized => _initialized;

  String? get currentConversationId => _currentConversationId;

  bool isTemporaryConversation(String? id) {
    return id != null && _temporaryConversationIds.contains(id);
  }

  Future<void> init() async {
    if (_initialized) return;

    // Initialize Hive with platform-specific directory
    final appDataDir = await AppDirectories.getAppDataDirectory();
    await Hive.initFlutter(appDataDir.path);

    // Register adapters if not already registered
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ConversationAdapter());
    }

    _conversationsBox = await Hive.openBox<Conversation>(_conversationsBoxName);
    _messagesBox = await Hive.openBox<ChatMessage>(_messagesBoxName);
    _toolEventsBox = await Hive.openBox(_toolEventsBoxName);

    // Migrate any persisted message content that references old iOS sandbox paths
    await _migrateSandboxPaths();

    // Reset any stale isStreaming flags left over from a previous app crash or
    // force-quit.  After a fresh launch no message can be actively streaming.
    await _resetStaleStreamingFlags();

    _initialized = true;
    notifyListeners();
  }

  List<Conversation> getAllConversations() {
    if (!_initialized) return [];
    final conversations = _conversationsBox.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  List<Conversation> getPinnedConversations() {
    return getAllConversations().where((c) => c.isPinned).toList();
  }

  Conversation? getConversation(String id) {
    if (!_initialized) return null;
    return _conversationsBox.get(id) ?? _draftConversations[id];
  }

  Conversation? _conversationForMessages(String conversationId) {
    if (!_initialized) return _draftConversations[conversationId];
    return _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
  }

  int getMessageCount(String conversationId) {
    final conversation = _conversationForMessages(conversationId);
    return conversation?.messageIds.length ?? 0;
  }

  int getMessageIndex(String conversationId, String messageId) {
    final conversation = _conversationForMessages(conversationId);
    if (conversation == null) return -1;
    return conversation.messageIds.indexOf(messageId);
  }

  Map<String, int> getFirstMessageIndicesForGroups(
    String conversationId,
    Iterable<String> groupIds,
  ) {
    final remaining = groupIds.where((id) => id.isNotEmpty).toSet();
    if (remaining.isEmpty) return const <String, int>{};

    final result = <String, int>{};
    final count = getMessageCount(conversationId);
    for (
      var start = 0;
      start < count && remaining.isNotEmpty;
      start += defaultLoadedWindowMax
    ) {
      final range = getMessagesRange(
        conversationId,
        start: start,
        limit: defaultLoadedWindowMax,
      );
      for (var offset = 0; offset < range.length; offset++) {
        final message = range[offset];
        final groupId = message.groupId ?? message.id;
        if (remaining.remove(groupId)) {
          result[groupId] = start + offset;
          if (remaining.isEmpty) break;
        }
      }
    }

    return result;
  }

  List<ChatMessage> getMessagesForGroups(
    String conversationId,
    Iterable<String> groupIds,
  ) {
    final remaining = groupIds.where((id) => id.isNotEmpty).toSet();
    if (remaining.isEmpty) return const <ChatMessage>[];

    final result = <ChatMessage>[];
    final count = getMessageCount(conversationId);
    for (var start = 0; start < count; start += defaultLoadedWindowMax) {
      final range = getMessagesRange(
        conversationId,
        start: start,
        limit: defaultLoadedWindowMax,
      );
      for (final message in range) {
        final groupId = message.groupId ?? message.id;
        if (remaining.contains(groupId)) {
          result.add(message);
        }
      }
    }

    return result;
  }

  ChatMessage? _messageForConversation(
    String conversationId,
    String messageId,
  ) {
    if (_temporaryConversationIds.contains(conversationId)) {
      final messages = _messagesCache[conversationId];
      if (messages == null) return null;
      for (final message in messages) {
        if (message.id == messageId) return message;
      }
      return null;
    }
    return _messagesBox.get(messageId);
  }

  List<ChatMessage> getMessages(String conversationId) {
    if (!_initialized) return [];

    // Check cache first
    if (_messagesCache.containsKey(conversationId)) {
      return _messagesCache[conversationId]!;
    }

    // Load from storage
    final conversation =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    if (conversation == null) return [];

    final messages = <ChatMessage>[];
    for (final messageId in conversation.messageIds) {
      final message = _messageForConversation(conversationId, messageId);
      if (message != null) {
        messages.add(message);
      }
    }

    // Cache the result
    _messagesCache[conversationId] = messages;
    return messages;
  }

  List<ChatMessage> getMessagesRange(
    String conversationId, {
    required int start,
    required int limit,
  }) {
    if (!_initialized || limit <= 0) return const <ChatMessage>[];

    final conversation = _conversationForMessages(conversationId);
    if (conversation == null || conversation.messageIds.isEmpty) {
      return const <ChatMessage>[];
    }

    final ids = conversation.messageIds;
    final safeStart = start.clamp(0, ids.length).toInt();
    final end = (safeStart + limit).clamp(safeStart, ids.length).toInt();
    if (safeStart >= end) return const <ChatMessage>[];

    final messages = <ChatMessage>[];
    for (var i = safeStart; i < end; i++) {
      final message = _messageForConversation(conversationId, ids[i]);
      if (message != null) messages.add(message);
    }
    return messages;
  }

  List<ChatMessage> getRecentMessages(
    String conversationId, {
    int minMessages = defaultInitialMessageMin,
    int textBudget = defaultInitialTextBudget,
    int maxMessages = defaultInitialMessageMax,
  }) {
    if (!_initialized) return const <ChatMessage>[];

    final conversation = _conversationForMessages(conversationId);
    if (conversation == null || conversation.messageIds.isEmpty) {
      return const <ChatMessage>[];
    }

    final ids = conversation.messageIds;
    final minCount = minMessages.clamp(1, ids.length).toInt();
    final maxCount = maxMessages < minCount ? minCount : maxMessages;
    final budget = textBudget <= 0 ? defaultInitialTextBudget : textBudget;

    var start = ids.length;
    var loaded = 0;
    var weight = 0;
    while (start > 0 && loaded < maxCount) {
      start--;
      final message = _messageForConversation(conversationId, ids[start]);
      if (message == null) continue;
      loaded++;
      weight += _estimateInitialLoadWeight(message);
      if (loaded >= minCount && weight >= budget) break;
    }

    if (loaded.isOdd && start > 0 && loaded < maxCount) {
      start--;
    }

    return getMessagesRange(
      conversationId,
      start: start,
      limit: ids.length - start,
    );
  }

  int _estimateInitialLoadWeight(ChatMessage message) {
    final len = message.content.length;
    if (message.role == 'user') return len < 200 ? 200 : len;
    if (message.role == 'assistant') return (len * 0.8).round();
    return len;
  }

  Future<Conversation> createConversation({
    String? title,
    String? assistantId,
  }) async {
    if (!_initialized) await init();
    _discardTemporaryConversation(_currentConversationId);

    final conversation = Conversation(
      title: title ?? _defaultConversationTitle,
      assistantId: assistantId,
    );

    await _conversationsBox.put(conversation.id, conversation);
    _currentConversationId = conversation.id;
    notifyListeners();
    return conversation;
  }

  // Create a draft conversation that is not persisted until first message arrives.
  Future<Conversation> createDraftConversation({
    String? title,
    String? assistantId,
    bool temporary = false,
  }) async {
    if (!_initialized) await init();
    _discardTemporaryConversation(_currentConversationId);
    final conversation = Conversation(
      title: title ?? _defaultConversationTitle,
      assistantId: assistantId,
    );
    _draftConversations[conversation.id] = conversation;
    if (temporary) {
      _temporaryConversationIds.add(conversation.id);
      _messagesCache[conversation.id] = <ChatMessage>[];
    }
    _currentConversationId = conversation.id;
    notifyListeners();
    return conversation;
  }

  void _discardTemporaryConversation(String? id) {
    if (id == null || !_temporaryConversationIds.remove(id)) return;
    final messages = _messagesCache[id] ?? const <ChatMessage>[];
    for (final message in messages) {
      _temporaryToolEvents.remove(message.id);
      _temporaryGeminiThoughtSigs.remove(message.id);
    }
    _draftConversations.remove(id);
    _messagesCache.remove(id);
    if (_currentConversationId == id) {
      _currentConversationId = null;
    }
  }

  Future<void> deleteConversation(String id) async {
    if (!_initialized) return;

    final deleted =
        await _deleteDraftConversation(id) ||
        await _deletePersistedConversation(id);
    if (!deleted) return;

    // Delete orphaned files (not referenced by any remaining conversation)
    await _cleanupOrphanUploads();

    // [kelivo-hosted] Fire-and-forget server-side soft-delete
    // (kelivo-arch.md 5) — the local delete already happened above, this
    // just keeps the hosted conversation hidden from the server's own
    // GET /conversations so it doesn't come back via a future sync/pull.
    unawaited(_deleteHostedConversation(id));

    notifyListeners();
  }

  Future<void> _deleteHostedConversation(String conversationId) async {
    final token = ClientBackendSession.token;
    if (token == null) return;
    try {
      final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
      await api.deleteConversation(token, conversationId);
    } catch (_) {}
  }

  Future<bool> _deleteDraftConversation(String id) async {
    if (!_draftConversations.containsKey(id)) return false;

    _draftConversations.remove(id);
    _temporaryConversationIds.remove(id);
    final messages = _messagesCache[id] ?? const <ChatMessage>[];
    for (final message in messages) {
      _temporaryToolEvents.remove(message.id);
      _temporaryGeminiThoughtSigs.remove(message.id);
    }
    _messagesCache.remove(id);
    if (_currentConversationId == id) {
      _currentConversationId = null;
    }
    return true;
  }

  Future<bool> _deletePersistedConversation(String id) async {
    final conversation = _conversationsBox.get(id);
    if (conversation == null) return false;

    for (final messageId in conversation.messageIds) {
      final msg = _messagesBox.get(messageId);
      if (msg != null && msg.role == 'assistant') {
        try {
          await _toolEventsBox.delete(msg.id);
        } catch (_) {}
        try {
          await _toolEventsBox.delete(_sigKey(msg.id));
        } catch (_) {}
      }
      await _messagesBox.delete(messageId);
    }

    await _conversationsBox.delete(id);
    _messagesCache.remove(id);

    if (_currentConversationId == id) {
      _currentConversationId = null;
    }
    return true;
  }

  Future<void> deleteConversationsForAssistant(String assistantId) async {
    if (!_initialized) await init();

    final targetId = assistantId.trim();
    if (targetId.isEmpty) return;

    final persistedConversationIds = _conversationsBox.values
        .where((conversation) => conversation.assistantId == targetId)
        .map((conversation) => conversation.id)
        .toList(growable: false);
    final draftConversationIds = _draftConversations.values
        .where((conversation) => conversation.assistantId == targetId)
        .map((conversation) => conversation.id)
        .toList(growable: false);

    var deleted = false;
    for (final conversationId in draftConversationIds) {
      deleted = await _deleteDraftConversation(conversationId) || deleted;
    }
    for (final conversationId in persistedConversationIds) {
      deleted = await _deletePersistedConversation(conversationId) || deleted;
    }

    if (!deleted) return;
    await _cleanupOrphanUploads();
    notifyListeners();
  }

  /// [kelivo-hosted] Wipes every locally-cached conversation that is known
  /// to the hosted backend (`hostedSynced == true`) — called on client
  /// account logout so the next signed-in account (or a signed-out guest)
  /// never sees the previous account's hosted chat history. Local-only
  /// conversations (BYOK, never synced) are left untouched. This does NOT
  /// touch the server copy — the account's data still exists there and is
  /// re-pulled on next login.
  Future<void> clearHostedSyncedConversations() async {
    if (!_initialized) await init();

    final persistedConversationIds = _conversationsBox.values
        .where((conversation) => conversation.hostedSynced)
        .map((conversation) => conversation.id)
        .toList(growable: false);
    final draftConversationIds = _draftConversations.values
        .where((conversation) => conversation.hostedSynced)
        .map((conversation) => conversation.id)
        .toList(growable: false);

    var deleted = false;
    for (final conversationId in draftConversationIds) {
      deleted = await _deleteDraftConversation(conversationId) || deleted;
    }
    for (final conversationId in persistedConversationIds) {
      deleted = await _deletePersistedConversation(conversationId) || deleted;
    }

    if (!deleted) return;
    await _cleanupOrphanUploads();
    notifyListeners();
  }

  Set<String> _extractAttachmentPaths(String content) {
    final out = <String>{};
    final imgRe = RegExp(r"\[image:(.+?)\]");
    for (final m in imgRe.allMatches(content)) {
      final pth = m.group(1)?.trim();
      if (pth != null &&
          pth.isNotEmpty &&
          !pth.startsWith('http') &&
          !pth.startsWith('data:')) {
        out.add(SandboxPathResolver.fix(pth));
      }
    }
    final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");
    for (final m in fileRe.allMatches(content)) {
      final pth = m.group(1)?.trim();
      if (pth != null &&
          pth.isNotEmpty &&
          !pth.startsWith('http') &&
          !pth.startsWith('data:')) {
        out.add(SandboxPathResolver.fix(pth));
      }
    }
    return out;
  }

  Future<void> _migrateSandboxPaths() async {
    try {
      // No-op if empty
      if (_messagesBox.isEmpty) return;
      final imgRe = RegExp(r"\[image:(.+?)\]");
      final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");

      for (final key in _messagesBox.keys) {
        final msg = _messagesBox.get(key);
        if (msg == null) continue;
        final content = msg.content;
        String updated = content;
        bool changed = false;

        // Rewrite image paths
        updated = updated.replaceAllMapped(imgRe, (m) {
          final raw = (m.group(1) ?? '').trim();
          final fixed = SandboxPathResolver.fix(raw);
          if (fixed != raw) changed = true;
          return '[image:$fixed]';
        });

        // Rewrite file attachment paths
        updated = updated.replaceAllMapped(fileRe, (m) {
          final raw = (m.group(1) ?? '').trim();
          final name = (m.group(2) ?? '').trim();
          final mime = (m.group(3) ?? '').trim();
          final fixed = SandboxPathResolver.fix(raw);
          if (fixed != raw) changed = true;
          return '[file:$fixed|$name|$mime]';
        });

        if (changed && updated != content) {
          final newMsg = msg.copyWith(content: updated);
          await _messagesBox.put(msg.id, newMsg);
        }
      }
    } catch (_) {
      // best-effort migration; ignore errors
    }
  }

  /// Reset stale isStreaming flags left over from a previous app crash or
  /// force-quit.  After a fresh launch no message can be actively streaming,
  /// so any persisted `isStreaming: true` is stale and must be cleared to
  /// avoid stuck loading indicators.
  ///
  /// Uses a tracked set of streaming message IDs for O(1) lookup instead of
  /// scanning every message in the box.
  Future<void> _resetStaleStreamingFlags() async {
    try {
      final raw = _toolEventsBox.get(_activeStreamingKey);
      if (raw == null) return;
      final ids = (raw as List).cast<String>();
      if (ids.isEmpty) return;
      // [kelivo-hosted] kelivo-arch.md §5 — ids that turn out to still be
      // genuinely in progress server-side stay tracked here (instead of
      // being cleared like every other id) so a later `resumeIfNeeded` call
      // (see below) has something to find once the UI layer is ready to
      // actually resume polling for them.
      final stillPending = <String>[];
      for (final id in ids) {
        final msg = _messagesBox.get(id);
        if (msg == null || !msg.isStreaming) continue;
        final reconciled = await _reconcileHostedMessage(msg);
        if (reconciled == null) {
          await _messagesBox.put(id, msg.copyWith(isStreaming: false));
          continue;
        }
        await _messagesBox.put(id, reconciled.message);
        if (reconciled.stillInProgress) stillPending.add(id);
      }
      if (stillPending.isEmpty) {
        await _toolEventsBox.delete(_activeStreamingKey);
      } else {
        await _toolEventsBox.put(_activeStreamingKey, stillPending);
      }
    } catch (_) {
      // best-effort; ignore errors
    }
  }

  /// [kelivo-hosted] kelivo-arch.md §5 — a hosted-provider message force-quit
  /// mid-generation isn't actually lost: the server kept generating
  /// regardless of the client (that's the whole point of the submit-then-poll
  /// design), so the local partial-content snapshot left behind by the dead
  /// polling loop is very likely stale, not final. Fetch the server's
  /// authoritative state once instead of just discarding it.
  ///
  /// If the server says generation is still in progress, `isStreaming` stays
  /// true (rather than being force-cleared) and the id stays tracked — this
  /// method only refreshes the content snapshot and reports the status back;
  /// actually re-entering the polling loop happens later, in
  /// [messagesNeedingResume]/`ChatActions.resumeStaleHostedGenerations`, once
  /// a conversation using this message is actually opened in the UI (there's
  /// no live `StreamingContentNotifier` to update yet at this point — this
  /// runs during `init()`, before any `HomeViewModel`/`ChatActions` exists).
  ///
  /// Returns null (caller falls back to the plain "clear isStreaming, keep
  /// whatever partial text was last saved" behavior) for non-hosted
  /// messages, or if the fetch itself fails — e.g. offline at cold-launch.
  /// [kelivo-hosted] A `status == 'failed'` message with no content ever
  /// reached the client while it was still streaming: no live
  /// `_handleStreamError` ran to fall back to `msg.error`, because the app
  /// was killed (`_reconcileHostedMessage`) or this device never even had
  /// the message locally in the first place (`syncMissingHostedMessages`).
  /// Both cold-launch reconciliation paths need this same fallback, or the
  /// failure reason is silently dropped and the message just looks blank.
  String _contentOrFailureReason(ClientChatMessage serverMsg) {
    if (serverMsg.status == 'failed' && serverMsg.content.isEmpty) {
      return serverMsg.error ?? 'Hosted generation failed';
    }
    return serverMsg.content;
  }

  Future<_HostedReconcileResult?> _reconcileHostedMessage(
    ChatMessage msg,
  ) async {
    final serverId = msg.hostedServerMessageId;
    if (serverId == null) return null;
    final token = ClientBackendSession.token;
    if (token == null) return null;
    try {
      final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
      final serverMsg = await api.getMessage(token, serverId);
      if (serverMsg == null) return null;
      final stillInProgress = !serverMsg.isFinished;
      return _HostedReconcileResult(
        msg.copyWith(
          content: _contentOrFailureReason(serverMsg),
          hostedImagesJson: _encodeHostedImagesJson(serverMsg.images),
          hostedFilesJson: _encodeHostedFilesJson(serverMsg.files),
          hostedSearchCitationsJson: _encodeHostedSearchCitationsJson(
            serverMsg.searchCitations,
          ),
          isStreaming: stillInProgress,
          totalTokens: serverMsg.totalTokens,
          promptTokens: serverMsg.promptTokens,
          completionTokens: serverMsg.completionTokens,
          isError: serverMsg.status == 'failed',
        ),
        stillInProgress,
      );
    } catch (_) {
      return null;
    }
  }

  /// [kelivo-hosted] kelivo-arch.md §5 — called once a hosted stream reaches
  /// `isDone` (`chat_actions.dart`'s `_finishStreaming`). The live polling
  /// loop (`hosted.dart`'s `_sendHostedStream`) only ever forwards
  /// content/reasoning deltas through `ChatStreamChunk` — that type has no
  /// images/files field at all — so a hosted-generated image or video
  /// attached to this reply is never written to the local message while the
  /// stream is actually being watched; only [_reconcileHostedMessage]'s
  /// cold-launch path did that. In practice this meant a freshly-finished
  /// generation showed no attachment (video generation especially: the
  /// bubble was left showing whatever placeholder text the server streamed
  /// while the job was pending) until the app restarted or the conversation
  /// was reopened, which happens to also call [_reconcileHostedMessage] via
  /// [syncMissingHostedMessages]/cold-launch resume. This does the same
  /// server round-trip immediately instead of waiting for one of those to
  /// happen incidentally. Returns the updated message (already persisted to
  /// Hive) so the caller can push it into its own in-memory list without a
  /// second read, or null if this wasn't a hosted message / the fetch
  /// failed (nothing to reconcile, or a transient network issue — the next
  /// cold-launch/conversation-open reconciliation will catch it).
  Future<ChatMessage?> reconcileHostedAttachmentsNow(String messageId) async {
    final msg = _messagesBox.get(messageId);
    if (msg == null) return null;
    final reconciled = await _reconcileHostedMessage(msg);
    if (reconciled == null) return null;
    await _messagesBox.put(messageId, reconciled.message);
    return reconciled.message;
  }

  /// [kelivo-hosted] Builds `SendMessageRequest.seed_messages` for
  /// [conversationId]'s FIRST-EVER hosted send — see that field's docstring
  /// (client_chat.py) for why this exists: a hosted conversation's history
  /// lives entirely server-side, so a locally-forked conversation
  /// (`forkConversation`) with a brand-new `conversation_id` would
  /// otherwise start every model call with zero context about what was
  /// forked. Only meaningful when the conversation isn't `hostedSynced` yet
  /// — the caller (`hosted.dart`) is responsible for that check; this just
  /// does the encoding work. [excludeMessageIds] skips messages this very
  /// send is already submitting on its own (the current turn's user message,
  /// going out via `content`/`images`/`documents` directly, and the empty
  /// assistant placeholder) — neither should also appear as its own seed
  /// history entry.
  ///
  /// Best-effort per attachment: a single image/file that fails to read
  /// (missing local file, dead hosted URL, network hiccup) is silently
  /// dropped rather than failing the whole send — losing one stale
  /// attachment out of a forked history is far better than blocking the
  /// user's actual new message over it.
  Future<List<Map<String, dynamic>>> buildHostedSeedMessages(
    String conversationId, {
    Set<String> excludeMessageIds = const {},
  }) async {
    final convo =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    if (convo == null) return const [];
    final seeds = <Map<String, dynamic>>[];
    for (final id in convo.messageIds) {
      if (excludeMessageIds.contains(id)) continue;
      final msg = _messagesBox.get(id);
      if (msg == null) continue;
      if (msg.role != 'user' && msg.role != 'assistant') continue;
      final seed = await _buildHostedSeedMessage(msg);
      if (seed != null) seeds.add(seed);
    }
    return seeds;
  }

  Future<Map<String, dynamic>?> _buildHostedSeedMessage(ChatMessage msg) async {
    final images = <String>[];
    final documents = <Map<String, dynamic>>[];
    String content;

    if (msg.hostedImagesJson != null || msg.hostedFilesJson != null) {
      // Hosted-origin message — `content` already has no local markers
      // baked in (see `hostedImagesJson`'s doc comment), so re-fetch each
      // attachment's bytes fresh via its authenticated URL instead.
      content = msg.content;
      for (final img in _decodeHostedAttachmentRefs(msg.hostedImagesJson)) {
        final dataUrl = await _fetchAsDataUrl(img.url, img.mimeType);
        if (dataUrl != null) images.add(dataUrl);
      }
      for (final f in _decodeHostedAttachmentRefs(msg.hostedFilesJson)) {
        final dataUrl = await _fetchAsDataUrl(f.url, f.mimeType);
        if (dataUrl != null) {
          documents.add({
            'filename': f.filename ?? 'file',
            'mimeType': f.mimeType,
            'data': dataUrl,
          });
        }
      }
    } else {
      // Local/BYOK-style message — attachments are `[image:path]`/
      // `[file:path|name|mime]` markers baked directly into `content` (see
      // `message_generation_service.dart`'s `buildPersistedUserMessageContent`).
      final parsed = _parseLocalAttachmentMarkers(msg.content);
      content = parsed.text;
      for (final path in parsed.imagePaths) {
        try {
          images.add(await ChatApiService.encodeLocalFileAsDataUrl(path));
        } catch (_) {}
      }
      for (final doc in parsed.documents) {
        try {
          final dataUrl = await ChatApiService.encodeLocalFileAsDataUrl(
            doc.path,
          );
          documents.add({
            'filename': doc.fileName,
            'mimeType': doc.mime,
            'data': dataUrl,
          });
        } catch (_) {}
      }
    }

    if (content.isEmpty && images.isEmpty && documents.isEmpty) return null;
    return {
      'role': msg.role,
      'content': content,
      if (images.isNotEmpty) 'images': images,
      if (documents.isNotEmpty) 'documents': documents,
    };
  }

  /// [kelivo-hosted] Builds the editable [ChatInputData] for [message] when
  /// a user opens the inline edit box (`HomePageController._enterUserMessageEdit`).
  /// Local/BYOK-style messages just parse the `[image:...]`/`[file:...]`
  /// markers already baked into `content`. Hosted-origin messages have no
  /// such markers (`hostedImagesJson`/`hostedFilesJson` is the only record
  /// of their attachments — see that field's docstring), so each one is
  /// downloaded into the same upload directory `_cleanupOrphanUploads`
  /// already tracks: once the edit is saved, the new version's `content`
  /// references these paths permanently (mirrors how the ORIGINAL send
  /// already keeps local markers alongside `hostedImagesJson` for the
  /// sending device's own instant local display), so nothing here is a
  /// throwaway temp file that cleanup or a "clear cache" tap could yank out
  /// from under the still-open edit.
  /// [kelivo-hosted] Number of attachments [buildEditInputData] will try to
  /// download for a hosted-origin message — a pure `hostedImagesJson`/
  /// `hostedFilesJson` decode, no network I/O, so callers can know the
  /// count up front (e.g. to render that many loading placeholders) without
  /// waiting on the actual downloads.
  int hostedAttachmentCount(ChatMessage message) {
    return _decodeHostedAttachmentRefs(message.hostedImagesJson).length +
        _decodeHostedAttachmentRefs(message.hostedFilesJson).length;
  }

  /// Text-only, synchronous counterpart to [buildEditInputData] — lets a
  /// caller show a clean (marker-free) initial value in the edit box the
  /// instant editing starts, before that async call (which also has to
  /// download hosted attachments) resolves. See its own `text` handling for
  /// why the raw marker must never be shown as-is.
  String stripLocalAttachmentMarkersText(String raw) =>
      _parseLocalAttachmentMarkers(raw).text;

  Future<ChatInputData> buildEditInputData(ChatMessage message) async {
    if (message.hostedImagesJson == null && message.hostedFilesJson == null) {
      final parsed = _parseLocalAttachmentMarkers(message.content);
      return ChatInputData(
        text: parsed.text,
        imagePaths: parsed.imagePaths,
        documents: parsed.documents,
      );
    }
    final imagePaths = <String>[];
    for (final img in _decodeHostedAttachmentRefs(message.hostedImagesJson)) {
      final path = await _downloadHostedAttachmentToUpload(
        img.url,
        img.mimeType,
      );
      if (path != null) imagePaths.add(path);
    }
    final docs = <DocumentAttachment>[];
    for (final f in _decodeHostedAttachmentRefs(message.hostedFilesJson)) {
      final filename = f.filename ?? 'file';
      final path = await _downloadHostedAttachmentToUpload(
        f.url,
        f.mimeType,
        suggestedName: filename,
      );
      if (path != null) {
        docs.add(
          DocumentAttachment(path: path, fileName: filename, mime: f.mimeType),
        );
      }
    }
    // `message.content` for a hosted-origin message may still carry the
    // `[image:...]`/`[file:...]` markers this device itself baked in when
    // it originally sent/edited this message (see
    // `MessageGenerationService.buildPersistedUserMessageContent`) — those
    // markers are never the source of truth for attachments here (that's
    // `hostedImagesJson`/`hostedFilesJson`, already downloaded into
    // `imagePaths`/`docs` above), so strip them from the text shown in the
    // edit box rather than dumping the raw marker literally into it. Only
    // `.text` is used from this parse — its `imagePaths`/`documents` are
    // discarded, since using them too would duplicate what's already been
    // downloaded above.
    return ChatInputData(
      text: _parseLocalAttachmentMarkers(message.content).text,
      imagePaths: imagePaths,
      documents: docs,
    );
  }

  Future<String?> _downloadHostedAttachmentToUpload(
    String url,
    String mimeType, {
    String? suggestedName,
  }) async {
    if (url.isEmpty) return null;
    try {
      final token = ClientBackendSession.token;
      final headers = token != null ? {'Authorization': 'Bearer $token'} : null;
      final res = await http.get(Uri.parse(url), headers: headers);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final dir = await AppDirectories.getUploadDirectory();
      if (!await dir.exists()) await dir.create(recursive: true);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final name = suggestedName != null && suggestedName.isNotEmpty
          ? 'edit_${stamp}_$suggestedName'
          : 'edit_$stamp.${AppDirectories.extFromMime(mimeType)}';
      final path = '${dir.path}/$name';
      await File(path).writeAsBytes(res.bodyBytes, flush: true);
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchAsDataUrl(String url, String mimeType) async {
    if (url.isEmpty) return null;
    try {
      final token = ClientBackendSession.token;
      final headers = token != null ? {'Authorization': 'Bearer $token'} : null;
      final res = await http.get(Uri.parse(url), headers: headers);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return 'data:$mimeType;base64,${base64Encode(res.bodyBytes)}';
    } catch (_) {
      return null;
    }
  }

  /// [kelivo-hosted] kelivo-arch.md §5 — assistant messages in
  /// [conversationId] left `isStreaming: true` by [_resetStaleStreamingFlags]
  /// because the server confirmed generation is still genuinely in
  /// progress. Called by `ChatActions.resumeStaleHostedGenerations` when a
  /// conversation is opened (`HomeViewModel.switchConversation`) — that's
  /// the point a real `StreamingContentNotifier` exists again to resume
  /// polling into.
  List<ChatMessage> messagesNeedingResume(String conversationId) {
    final convo =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    if (convo == null) return const [];
    final result = <ChatMessage>[];
    for (final id in convo.messageIds) {
      final m = _messagesBox.get(id);
      if (m != null && m.isStreaming && m.hostedServerMessageId != null) {
        result.add(m);
      }
    }
    return result;
  }

  /// [kelivo-hosted] kelivo-arch.md §5 — pulls any server-side messages for
  /// [conversationId] that this device never persisted locally (created on
  /// another device, or lost to a kill between the server accepting a send
  /// and this device writing it to Hive) and inserts them in the right spot.
  /// Called from `ChatActions.syncMissingHostedMessages`, itself called
  /// alongside `resumeStaleHostedGenerations` whenever a conversation is
  /// opened (`HomeViewModel.switchConversation`). Idempotent: messages
  /// already known locally (matched by `hostedServerMessageId`) are left
  /// untouched, so a repeat call with nothing new is a no-op.
  ///
  /// Always attempted when authenticated rather than gated on "does this
  /// conversation look hosted" — a pure-BYOK conversation just gets an empty
  /// list back quickly (the server has no rows for a `conversation_id` it's
  /// never seen), which is simpler and just as correct as trying to guess
  /// from local message shape first.
  Future<void> syncMissingHostedMessages(String conversationId) async {
    if (!_initialized) return;
    final token = ClientBackendSession.token;
    if (token == null) return;
    final convo =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    if (convo == null) return;

    List<ClientChatMessage>? serverMessages;
    try {
      final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
      serverMessages = await api.listConversationMessages(
        token,
        conversationId,
      );
    } catch (_) {
      serverMessages = null;
    }
    if (serverMessages == null || serverMessages.isEmpty) return;
    final serverMessagesNonNull = serverMessages;

    // hostedServerMessageId -> local ChatMessage id, for whatever's already known.
    final localIdByServerId = <String, String>{};
    String? knownProviderId;
    // [kelivo-hosted] a message that was just sent from THIS device may
    // already exist in `convo.messageIds` before its `hostedServerMessageId`
    // is known (that field is only set once the first stream chunk/poll
    // response arrives — see `chat_actions.dart`'s `_handleContentChunk`).
    // If `switchConversation` (and thus this sync) races that narrow window,
    // matching purely by `hostedServerMessageId` would miss it and create a
    // second, duplicate local message for the same server row. Track the
    // most recent still-streaming, not-yet-tagged local message per role so
    // it can be claimed instead of duplicated below.
    final unclaimedStreamingIdByRole = <String, String>{};
    for (final id in convo.messageIds) {
      final m = _messagesBox.get(id);
      if (m == null) continue;
      final serverId = m.hostedServerMessageId;
      if (serverId != null) {
        localIdByServerId[serverId] = id;
        knownProviderId ??= m.providerId;
      } else if (m.isStreaming) {
        unclaimedStreamingIdByRole[m.role] = id;
      }
    }

    // Rebuild the message order, keeping every existing local message in its
    // original relative position and only inserting genuinely-new server
    // messages at the correct point (per server `seq`) — a purely
    // append-everything-unmatched-at-the-end approach would reorder any
    // conversation that mixes hosted messages with local-only (BYOK) ones.
    final serverIndexByLocalId = <String, int>{};
    for (var i = 0; i < serverMessagesNonNull.length; i++) {
      final localId = localIdByServerId[serverMessagesNonNull[i].id];
      if (localId != null) serverIndexByLocalId[localId] = i;
    }

    final newOrder = <String>[];
    var changed = false;
    var nextServerIdxToPlace = 0;
    Future<void> flushServerUpTo(int idxExclusive) async {
      while (nextServerIdxToPlace < idxExclusive) {
        final serverMsg = serverMessagesNonNull[nextServerIdxToPlace];
        nextServerIdxToPlace++;
        if (localIdByServerId.containsKey(serverMsg.id)) continue;
        final claimedLocalId = !serverMsg.isFinished
            ? unclaimedStreamingIdByRole.remove(serverMsg.role)
            : null;
        if (claimedLocalId != null) {
          final existing = _messagesBox.get(claimedLocalId);
          if (existing != null) {
            await _messagesBox.put(
              claimedLocalId,
              existing.copyWith(hostedServerMessageId: serverMsg.id),
            );
            localIdByServerId[serverMsg.id] = claimedLocalId;
            newOrder.add(claimedLocalId);
            continue;
          }
        }
        changed = true;
        final pulled = ChatMessage(
          role: serverMsg.role,
          content: _contentOrFailureReason(serverMsg),
          hostedImagesJson: _encodeHostedImagesJson(serverMsg.images),
          hostedFilesJson: _encodeHostedFilesJson(serverMsg.files),
          hostedSearchCitationsJson: _encodeHostedSearchCitationsJson(
            serverMsg.searchCitations,
          ),
          // [kelivo-hosted] kelivo-arch.md §5 — without this, `ChatMessage`'s
          // constructor default (`timestamp ?? DateTime.now()`) stamps this
          // message with whenever THIS device happened to sync, not when it
          // was actually sent/generated — showing e.g. every message pulled
          // in one sync batch with the exact same time, or a regenerated
          // version appearing to predate the original.
          timestamp: serverMsg.createdAt,
          modelId: serverMsg.modelId,
          providerId: knownProviderId,
          conversationId: conversationId,
          isStreaming: !serverMsg.isFinished,
          hostedServerMessageId: serverMsg.id,
          totalTokens: serverMsg.totalTokens,
          promptTokens: serverMsg.promptTokens,
          completionTokens: serverMsg.completionTokens,
          isError: serverMsg.status == 'failed',
        );
        await _messagesBox.put(pulled.id, pulled);
        newOrder.add(pulled.id);
        // Without this, the regenerate-versioning canonicalization pass
        // below (`localIdByServerId[serverMsg.id]`) can never find a
        // message pulled for the FIRST time on this device — exactly the
        // "first login / first ever open of this conversation" case, since
        // that's precisely when every message here is brand new to this
        // map. Every such message silently kept its default self-groupId
        // forever, so a regenerated pair synced down for the first time
        // never collapsed into one turn with a pager.
        localIdByServerId[serverMsg.id] = pulled.id;
      }
    }

    for (final id in convo.messageIds) {
      final anchorIdx = serverIndexByLocalId[id];
      if (anchorIdx != null) {
        await flushServerUpTo(anchorIdx);
        newOrder.add(id);
        nextServerIdxToPlace = anchorIdx + 1;
      } else if (!newOrder.contains(id)) {
        // Local-only message (never synced with the server, e.g. BYOK) —
        // keep it in its original relative position instead of moving it.
        newOrder.add(id);
      }
    }
    await flushServerUpTo(serverMessagesNonNull.length);

    // [kelivo-hosted] kelivo-arch.md §5 — regenerate/edit versioning. Every
    // version of the same turn shares the server's `group_id` (see backend
    // `ClientMessage.group_id`'s docstring); map it onto the LOCAL
    // `ChatMessage.groupId` field the existing BYOK version-pager already
    // understands (`ChatController.collapseVersions` groups by
    // `groupId ?? id`), so regenerated/edited siblings pulled from another
    // device collapse into one turn with a working "< 1/2 >" pager instead
    // of showing up as unrelated extra turns. Deliberately keyed off the
    // server's own ids (not this device's local ones) so every device
    // derives the exact same string independently, with no extra
    // round-trip needed to agree on it.
    //
    // Keyed off `serverMsg.groupId ?? serverMsg.id` — NOT just
    // `serverMsg.groupId` — and applied to every synced message, not only
    // ones that already have a non-null `group_id`. The *first* message of
    // a group (the original reply/prompt a regenerate/edit was based on)
    // never gets its own `group_id` column set server-side — only later
    // versions do, each pointing back at that original's server id (see
    // `regenerate_message`/`edit_user_message`'s `target_group_id =
    // original.group_id or original.id`). Skipping null-`group_id` rows
    // therefore left that original row un-canonicalized forever: its local
    // `groupId` stayed whatever it was assigned at creation (not
    // `hosted:`-prefixed), which never matched its sibling versions' now
    // -canonicalized `hosted:$id`, so the two versions collapsed on the
    // *originating* device (same local convention throughout) but rendered
    // as two separate, out-of-order bubbles on any *other* device that only
    // ever received them via sync.
    // [kelivo-hosted] Content/status reconciliation for messages already
    // known locally (matched via `hostedServerMessageId` above, so NOT
    // touched by `flushServerUpTo`'s insert path). Without this, a message
    // first pulled in while still generating on another device (or
    // discovered right as it finished, but before this device's own
    // resume/poll ever ran — e.g. `resumeStaleHostedGenerations` was
    // skipped because this device already had some other active generation
    // for the conversation right at that moment) stayed frozen at whatever
    // content/`isStreaming` it had at the moment of that first pull,
    // forever — repeat calls to this same function (the periodic watcher,
    // the manual "sync with server" button, app-resume, or just reopening
    // the conversation) kept re-fetching the authoritative server list but
    // silently discarded it for any message this device had already seen
    // once. Safe to always trust the server's snapshot here: this function
    // is never invoked while this device itself is actively streaming the
    // same conversation (every caller — the periodic watcher, manual
    // refresh, `resumeStaleHostedGenerations`'s own callers — checks
    // `isConversationLoading`/`conversationStreams` first), so there's no
    // fresher local-only content this could ever clobber.
    for (final serverMsg in serverMessagesNonNull) {
      final canonicalTarget = serverMsg.groupId ?? serverMsg.id;
      final localId = localIdByServerId[serverMsg.id];
      if (localId == null) continue;
      final local = _messagesBox.get(localId);
      if (local == null) continue;
      final canonicalGroupId = 'hosted:$canonicalTarget';
      final serverStillStreaming = !serverMsg.isFinished;
      final serverImagesJson = _encodeHostedImagesJson(serverMsg.images);
      final serverFilesJson = _encodeHostedFilesJson(serverMsg.files);
      final serverSearchCitationsJson = _encodeHostedSearchCitationsJson(
        serverMsg.searchCitations,
      );
      final resolvedContent = _contentOrFailureReason(serverMsg);
      final serverIsError = serverMsg.status == 'failed';
      if (local.groupId != canonicalGroupId ||
          local.version != serverMsg.version ||
          local.content != resolvedContent ||
          local.hostedImagesJson != serverImagesJson ||
          local.hostedFilesJson != serverFilesJson ||
          local.hostedSearchCitationsJson != serverSearchCitationsJson ||
          local.isStreaming != serverStillStreaming ||
          local.totalTokens != serverMsg.totalTokens ||
          local.promptTokens != serverMsg.promptTokens ||
          local.completionTokens != serverMsg.completionTokens ||
          local.isError != serverIsError) {
        await _messagesBox.put(
          localId,
          local.copyWith(
            groupId: canonicalGroupId,
            version: serverMsg.version,
            content: resolvedContent,
            hostedImagesJson: serverImagesJson,
            hostedFilesJson: serverFilesJson,
            hostedSearchCitationsJson: serverSearchCitationsJson,
            isStreaming: serverStillStreaming,
            totalTokens: serverMsg.totalTokens,
            promptTokens: serverMsg.promptTokens,
            completionTokens: serverMsg.completionTokens,
            isError: serverIsError,
          ),
        );
        changed = true;
      }
    }

    if (!changed && newOrder.length == convo.messageIds.length) return;

    convo.messageIds
      ..clear()
      ..addAll(newOrder);
    await convo.save();
    _messagesCache.remove(conversationId);
    notifyListeners();
  }

  /// [kelivo-hosted] kelivo-arch.md §5 — conversation-LIST sync, distinct
  /// from [syncMissingHostedMessages] (which pulls messages *within* an
  /// already-open conversation). Discovers conversations created on another
  /// device (never seen locally) and detects conversations deleted on
  /// another device (soft-deleted server-side, so no longer returned here).
  /// Also reconciles the title, last-writer-wins. Called fire-and-forget
  /// right after `ChatService.init()` from `HomePageController.initChat`.
  Future<void> syncConversationList() async {
    if (!_initialized) return;
    final token = ClientBackendSession.token;
    if (token == null) return;

    List<ClientConversationSummary>? serverConversations;
    try {
      final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
      serverConversations = await api.listConversations(token);
    } catch (_) {
      serverConversations = null;
    }
    if (serverConversations == null) return;

    final serverIds = serverConversations.map((c) => c.id).toSet();
    var changed = false;

    // New-on-another-device: create a local shell conversation so it shows
    // up in the list; messages themselves are pulled lazily by
    // `syncMissingHostedMessages` once the conversation is opened.
    for (final serverConvo in serverConversations) {
      if (_conversationsBox.containsKey(serverConvo.id) ||
          _draftConversations.containsKey(serverConvo.id)) {
        continue;
      }
      final conversation = Conversation(
        id: serverConvo.id,
        title: serverConvo.title,
        createdAt: serverConvo.createdAt,
        updatedAt: serverConvo.updatedAt,
        hostedSynced: true,
        assistantId: serverConvo.assistantId,
        // The server only ever knows bare group ids — re-prefix with
        // `hosted:` so this lands in the same key space the pager
        // (`ChatController`/`message_list_view.dart`) reads (see
        // `_localGroupId`'s docstring above `getVersionSelections`).
        versionSelections: serverConvo.versionSelections?.map(
          (k, v) => MapEntry(_localGroupId(k), v),
        ),
      );
      await _conversationsBox.put(conversation.id, conversation);
      changed = true;
    }

    // Deleted-on-another-device: any local hosted conversation no longer
    // returned by the server has been soft-deleted remotely — remove it
    // locally too, reusing the same removal path as a local delete.
    final locallyGoneIds = _conversationsBox.values
        .where((c) => c.hostedSynced && !serverIds.contains(c.id))
        .map((c) => c.id)
        .toList();
    for (final id in locallyGoneIds) {
      if (await _deletePersistedConversation(id)) {
        await _cleanupOrphanUploads();
        changed = true;
      }
    }

    // Present on both sides: last-writer-wins title reconciliation.
    for (final serverConvo in serverConversations) {
      final local = _conversationsBox.get(serverConvo.id);
      if (local == null || !local.hostedSynced) continue;
      // Captured before any mutation below — `title`'s own reconciliation
      // bumps `local.updatedAt` to the server's value, which would make
      // the version-selections check below (run after it, in the same
      // iteration) compare against an already-overwritten timestamp instead
      // of this device's actual last-known state.
      final localUpdatedAt = local.updatedAt;
      var localChanged = false;
      if (local.title != serverConvo.title) {
        local.title = serverConvo.title;
        local.updatedAt = serverConvo.updatedAt;
        localChanged = true;
      }
      // [kelivo-hosted] Backfill for conversations synced down before
      // `ClientConversationOut` exposed `assistant_id` — those landed with
      // `assistantId == null` locally, which the side drawer's conversation
      // list treats as "show under every assistant". Fill-if-null only
      // (never overwrite a non-null local value) since this field isn't
      // pushed to the server on every change the way `title` is.
      if (local.assistantId == null && serverConvo.assistantId != null) {
        local.assistantId = serverConvo.assistantId;
        localChanged = true;
      }
      // Version-pager selections (kelivo-arch.md §6) — unlike `title`,
      // which is safe to always blindly copy from the server (this device
      // also pushes renames immediately, so a stale server value here is
      // rare and self-corrects on the next sync), a version switch made on
      // THIS device is pushed fire-and-forget (`ChatService.setSelectedVersion`)
      // and can still be in flight (or have failed silently, offline) when
      // this sync runs. Blindly copying the server's map in that window
      // would clobber a switch the user just made on this exact device
      // with what the server still thinks is selected. Comparing this
      // conversation's own `updatedAt` (bumped by ANY change, not just a
      // version switch — same coarse "no per-field diffing" convention
      // `title` above already relies on) is the best signal available:
      // only adopt the server's map when it is NOT older than what this
      // device last saw, so an in-flight/failed local push never loses to
      // a snapshot from before it was made.
      if (serverConvo.versionSelections != null) {
        // Re-prefix to the local (`hosted:`-prefixed) key space before
        // comparing/adopting — see `_localGroupId`'s docstring. Comparing
        // the raw server map against `local.versionSelections` here would
        // never match even when nothing actually changed (different key
        // formats), forcing a needless write every single sync.
        final serverAsLocal = serverConvo.versionSelections!.map(
          (k, v) => MapEntry(_localGroupId(k), v),
        );
        if (!serverConvo.updatedAt.isBefore(localUpdatedAt) &&
            !mapEquals(local.versionSelections, serverAsLocal)) {
          local.versionSelections = serverAsLocal;
          localChanged = true;
        }
      }
      if (localChanged) {
        await local.save();
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  /// Called once a message resumed via [messagesNeedingResume] has actually
  /// been picked back up (or given up on) so it doesn't get offered for
  /// resume again on the next cold launch.
  void clearResumeTracking(String messageId) {
    _untrackStreamingId(messageId);
  }

  /// Record a message ID as actively streaming.
  void _trackStreamingId(String messageId) {
    try {
      final raw = _toolEventsBox.get(_activeStreamingKey);
      final ids = raw != null
          ? (raw as List).cast<String>().toList()
          : <String>[];
      if (!ids.contains(messageId)) {
        ids.add(messageId);
        _toolEventsBox.put(_activeStreamingKey, ids);
      }
    } catch (_) {}
  }

  /// Remove a message ID from the active streaming set.
  void _untrackStreamingId(String messageId) {
    try {
      final raw = _toolEventsBox.get(_activeStreamingKey);
      if (raw == null) return;
      final ids = (raw as List).cast<String>().toList();
      if (ids.remove(messageId)) {
        if (ids.isEmpty) {
          _toolEventsBox.delete(_activeStreamingKey);
        } else {
          _toolEventsBox.put(_activeStreamingKey, ids);
        }
      }
    } catch (_) {}
  }

  Future<void> _cleanupOrphanUploads() async {
    try {
      final uploadDir = await AppDirectories.getUploadDirectory();
      if (!await uploadDir.exists()) return;

      // Build the set of all referenced paths across all messages
      String canon(String pth) {
        // Normalize separators and resolve redundant segments to enable
        // reliable equality checks across platforms (esp. Windows).
        final normalized = p.normalize(pth);
        // On Windows, paths are case-insensitive; compare in lowercase.
        return Platform.isWindows ? normalized.toLowerCase() : normalized;
      }

      final referenced = <String>{};
      for (final m in _messagesBox.values) {
        for (final pth in _extractAttachmentPaths(m.content)) {
          referenced.add(canon(pth));
        }
      }

      // Walk upload directory recursively to consider all files
      final entries = uploadDir.listSync(recursive: true, followLinks: false);
      for (final ent in entries) {
        if (ent is File) {
          final filePath = canon(ent.path);
          if (!referenced.contains(filePath)) {
            try {
              await ent.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  Future<void> restoreConversation(
    Conversation conversation,
    List<ChatMessage> messages,
  ) async {
    if (!_initialized) await init();
    // Restore messages first
    for (final m in messages) {
      await _messagesBox.put(m.id, m);
    }
    // Ensure messageIds are in the same order
    final ids = messages.map((m) => m.id).toList();
    final restored = Conversation(
      id: conversation.id,
      title: conversation.title,
      createdAt: conversation.createdAt,
      updatedAt: conversation.updatedAt,
      messageIds: ids,
      isPinned: conversation.isPinned,
      mcpServerIds: List.of(conversation.mcpServerIds),
      truncateIndex: conversation.truncateIndex,
      assistantId: conversation.assistantId,
      versionSelections: Map<String, int>.from(conversation.versionSelections),
      summary: conversation.summary,
      lastSummarizedMessageCount: conversation.lastSummarizedMessageCount,
      chatSuggestions: List<String>.of(conversation.chatSuggestions),
    );
    await _conversationsBox.put(restored.id, restored);

    // Update caches
    _messagesCache[restored.id] = List.of(messages);

    notifyListeners();
  }

  // Add a message directly to an existing conversation (for merge mode)
  Future<void> addMessageDirectly(
    String conversationId,
    ChatMessage message,
  ) async {
    if (!_initialized) await init();

    // Add message to box
    await _messagesBox.put(message.id, message);

    // Update conversation
    final conversation = _conversationsBox.get(conversationId);
    if (conversation != null) {
      if (!conversation.messageIds.contains(message.id)) {
        conversation.messageIds.add(message.id);
        // Keep original updatedAt during restore
        await conversation.save();
      }
    }

    // Update cache
    if (_messagesCache.containsKey(conversationId)) {
      if (!_messagesCache[conversationId]!.any((m) => m.id == message.id)) {
        _messagesCache[conversationId]!.add(message);
      }
    }

    notifyListeners();
  }

  // Conversation-scoped MCP servers selection
  List<String> getConversationMcpServers(String conversationId) {
    if (!_initialized) return const <String>[];
    final c =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    return c?.mcpServerIds ?? const <String>[];
  }

  Future<void> setConversationMcpServers(
    String conversationId,
    List<String> serverIds,
  ) async {
    if (!_initialized) await init();
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.mcpServerIds = List.of(serverIds);
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final c = _conversationsBox.get(conversationId);
    if (c == null) return;
    c.mcpServerIds = List.of(serverIds);
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
  }

  // Conversation-scoped chat model override; null falls back to the
  // assistant's default model, then the global default model.
  (String?, String?)? getConversationChatModel(String conversationId) {
    if (!_initialized) return null;
    final c =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    if (c == null || c.chatModelProvider == null || c.chatModelId == null) {
      return null;
    }
    return (c.chatModelProvider, c.chatModelId);
  }

  Future<void> setConversationChatModel(
    String conversationId,
    String? providerKey,
    String? modelId,
  ) async {
    if (!_initialized) await init();
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.chatModelProvider = providerKey;
      draft.chatModelId = modelId;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final c = _conversationsBox.get(conversationId);
    if (c == null) return;
    c.chatModelProvider = providerKey;
    c.chatModelId = modelId;
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
  }

  Future<void> toggleConversationMcpServer(
    String conversationId,
    String serverId,
    bool enabled,
  ) async {
    final current = getConversationMcpServers(conversationId);
    final set = current.toSet();
    if (enabled) {
      set.add(serverId);
    } else {
      set.remove(serverId);
    }
    await setConversationMcpServers(conversationId, set.toList());
  }

  Future<void> renameConversation(String id, String newTitle) async {
    if (!_initialized) return;

    if (_draftConversations.containsKey(id)) {
      final draft = _draftConversations[id]!;
      draft.title = newTitle;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;

    conversation.title = newTitle;
    conversation.updatedAt = DateTime.now();
    await conversation.save();
    notifyListeners();

    // [kelivo-hosted] kelivo-arch.md §5 — push the new title to the server
    // so it shows up on other devices too, covering both manual rename
    // (side_drawer.dart) and Kelivo's auto-title-after-first-exchange
    // (home_view_model.dart), which both funnel through this method.
    // Fire-and-forget, same tone as `_deleteHostedConversation`.
    if (conversation.hostedSynced) {
      unawaited(_pushHostedConversationTitle(id, newTitle));
    }
  }

  Future<void> _pushHostedConversationTitle(
    String conversationId,
    String title,
  ) async {
    final token = ClientBackendSession.token;
    if (token == null) return;
    try {
      final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
      await api.updateConversationTitle(token, conversationId, title);
    } catch (_) {}
  }

  /// Updates the conversation summary generated by LLM.
  Future<void> updateConversationSummary(
    String id,
    String summary,
    int messageCount,
  ) async {
    if (!_initialized) return;

    if (_draftConversations.containsKey(id)) {
      final draft = _draftConversations[id]!;
      draft.summary = summary;
      draft.lastSummarizedMessageCount = messageCount;
      notifyListeners();
      return;
    }

    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;

    conversation.summary = summary;
    conversation.lastSummarizedMessageCount = messageCount;
    await conversation.save();
    notifyListeners();
  }

  /// Gets all conversations with non-empty summaries for a specific assistant.
  List<Conversation> getConversationsWithSummaryForAssistant(
    String assistantId,
  ) {
    if (!_initialized) return [];
    return getAllConversations()
        .where(
          (c) =>
              c.assistantId == assistantId &&
              c.summary != null &&
              c.summary!.trim().isNotEmpty,
        )
        .toList();
  }

  /// Clears the summary of a specific conversation.
  Future<void> clearConversationSummary(String conversationId) async {
    if (!_initialized) return;

    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.summary = null;
      draft.lastSummarizedMessageCount = 0;
      notifyListeners();
      return;
    }

    final conversation = _conversationsBox.get(conversationId);
    if (conversation == null) return;

    conversation.summary = null;
    conversation.lastSummarizedMessageCount = 0;
    await conversation.save();
    notifyListeners();
  }

  Future<void> updateConversationSuggestions(
    String conversationId,
    List<String> suggestions,
  ) async {
    if (!_initialized) return;

    final clean = suggestions
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList();

    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.chatSuggestions = clean;
      notifyListeners();
      return;
    }

    final conversation = _conversationsBox.get(conversationId);
    if (conversation == null) return;

    conversation.chatSuggestions = clean;
    await conversation.save();
    notifyListeners();
  }

  Future<void> clearConversationSuggestions(String conversationId) async {
    if (!_initialized) return;

    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      if (draft.chatSuggestions.isEmpty) return;
      draft.chatSuggestions = <String>[];
      notifyListeners();
      return;
    }

    final conversation = _conversationsBox.get(conversationId);
    if (conversation == null || conversation.chatSuggestions.isEmpty) return;

    conversation.chatSuggestions = <String>[];
    await conversation.save();
    notifyListeners();
  }

  Future<void> togglePinConversation(String id) async {
    if (!_initialized) return;

    if (_draftConversations.containsKey(id)) {
      final draft = _draftConversations[id]!;
      draft.isPinned = !draft.isPinned;
      notifyListeners();
      return;
    }
    final conversation = _conversationsBox.get(id);
    if (conversation == null) return;

    conversation.isPinned = !conversation.isPinned;
    await conversation.save();
    notifyListeners();
  }

  Future<ChatMessage> addMessage({
    required String conversationId,
    required String role,
    required String content,
    String? modelId,
    String? providerId,
    int? totalTokens,
    bool isStreaming = false,
    String? reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
    String? groupId,
    int? version,
  }) async {
    if (!_initialized) await init();

    var conversation = _conversationsBox.get(conversationId);
    final temporary = _temporaryConversationIds.contains(conversationId);
    // If conversation doesn't exist yet, persist draft (if any)
    if (conversation == null) {
      final draft = temporary
          ? _draftConversations[conversationId]
          : _draftConversations.remove(conversationId);
      if (draft != null) {
        if (!temporary) {
          await _conversationsBox.put(draft.id, draft);
        }
        conversation = draft;
      } else {
        // Create a new one on the fly as a fallback
        conversation = Conversation(
          id: conversationId,
          title: _defaultConversationTitle,
        );
        if (!temporary) {
          await _conversationsBox.put(conversationId, conversation);
        } else {
          _draftConversations[conversationId] = conversation;
        }
      }
    }

    final message = ChatMessage(
      role: role,
      content: content,
      conversationId: conversationId,
      modelId: modelId,
      providerId: providerId,
      totalTokens: totalTokens,
      isStreaming: isStreaming,
      reasoningText: reasoningText,
      reasoningStartAt: reasoningStartAt,
      reasoningFinishedAt: reasoningFinishedAt,
      groupId: groupId,
      version: version,
    );

    if (!temporary) {
      await _messagesBox.put(message.id, message);
    }

    // Track streaming state for crash-recovery cleanup
    if (isStreaming && !temporary) {
      _trackStreamingId(message.id);
    }

    conversation.messageIds.add(message.id);
    conversation.updatedAt = DateTime.now();
    if (temporary) {
      _messagesCache.putIfAbsent(conversationId, () => <ChatMessage>[]);
    } else {
      await conversation.save();
    }

    // Update cache
    if (_messagesCache.containsKey(conversationId)) {
      _messagesCache[conversationId]!.add(message);
    }

    notifyListeners();
    return message;
  }

  ChatMessage? _cachedTemporaryMessage(String messageId) {
    for (final entry in _messagesCache.entries) {
      if (!_temporaryConversationIds.contains(entry.key)) continue;
      for (final message in entry.value) {
        if (message.id == messageId) return message;
      }
    }
    return null;
  }

  bool _isTemporaryMessageId(String messageId) {
    return _cachedTemporaryMessage(messageId) != null;
  }

  void _replaceCachedMessage(ChatMessage updatedMessage) {
    final messages = _messagesCache[updatedMessage.conversationId];
    if (messages == null) return;
    final index = messages.indexWhere((m) => m.id == updatedMessage.id);
    if (index >= 0) {
      messages[index] = updatedMessage;
    }
  }

  /// Reads a single message straight from storage — callers that already
  /// hold their own in-memory copy (e.g. `ChatController._messages`) can use
  /// this to pick up a mutation made elsewhere (`updateMessage`, this
  /// class's own internal writes) that their cached copy wouldn't otherwise
  /// see, since `ChatService` and `ChatController` keep independent object
  /// references rather than one being a live view of the other.
  ChatMessage? getMessageById(String messageId) => _messagesBox.get(messageId);

  Future<void> updateMessage(
    String messageId, {
    String? content,
    int? totalTokens,
    bool? isStreaming,
    String? reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
    String? translation,
    String? reasoningSegmentsJson,
    int? promptTokens,
    int? completionTokens,
    int? cachedTokens,
    int? durationMs,
    String? groupId,
    int? version,
    bool? isError,
  }) async {
    if (!_initialized) return;

    final message =
        _messagesBox.get(messageId) ?? _cachedTemporaryMessage(messageId);
    if (message == null) return;

    final updatedMessage = message.copyWith(
      content: content ?? message.content,
      totalTokens: totalTokens ?? message.totalTokens,
      isStreaming: isStreaming ?? message.isStreaming,
      reasoningText: reasoningText ?? message.reasoningText,
      reasoningStartAt: reasoningStartAt ?? message.reasoningStartAt,
      reasoningFinishedAt: reasoningFinishedAt ?? message.reasoningFinishedAt,
      translation: translation,
      reasoningSegmentsJson:
          reasoningSegmentsJson ?? message.reasoningSegmentsJson,
      promptTokens: promptTokens ?? message.promptTokens,
      completionTokens: completionTokens ?? message.completionTokens,
      cachedTokens: cachedTokens ?? message.cachedTokens,
      durationMs: durationMs ?? message.durationMs,
      groupId: groupId ?? message.groupId,
      version: version ?? message.version,
      isError: isError ?? message.isError,
    );

    if (isTemporaryConversation(message.conversationId)) {
      _replaceCachedMessage(updatedMessage);
      notifyListeners();
      return;
    }

    await _messagesBox.put(messageId, updatedMessage);

    // Update streaming tracking for crash-recovery
    if (isStreaming == false) {
      _untrackStreamingId(messageId);
    }

    // Update cache
    final conversationId = message.conversationId;
    if (_messagesCache.containsKey(conversationId)) {
      final messages = _messagesCache[conversationId]!;
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        messages[index] = updatedMessage;
      }
    }

    notifyListeners();
  }

  /// Update message content during streaming without triggering notifyListeners.
  /// This is used for streaming updates to avoid unnecessary rebuilds of
  /// widgets watching ChatService (e.g., side_drawer).
  Future<void> updateMessageSilent(
    String messageId, {
    String? content,
    int? totalTokens,
    bool? isStreaming,
    String? reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
    String? translation,
    String? reasoningSegmentsJson,
    int? promptTokens,
    int? completionTokens,
    int? cachedTokens,
    int? durationMs,
    // [kelivo-hosted] kelivo-arch.md §5 — see ChatMessage.hostedServerMessageId.
    String? hostedServerMessageId,
  }) async {
    if (!_initialized) return;

    final message =
        _messagesBox.get(messageId) ?? _cachedTemporaryMessage(messageId);
    if (message == null) return;

    final updatedMessage = message.copyWith(
      content: content ?? message.content,
      totalTokens: totalTokens ?? message.totalTokens,
      isStreaming: isStreaming ?? message.isStreaming,
      reasoningText: reasoningText ?? message.reasoningText,
      reasoningStartAt: reasoningStartAt ?? message.reasoningStartAt,
      reasoningFinishedAt: reasoningFinishedAt ?? message.reasoningFinishedAt,
      translation: translation,
      reasoningSegmentsJson:
          reasoningSegmentsJson ?? message.reasoningSegmentsJson,
      promptTokens: promptTokens ?? message.promptTokens,
      completionTokens: completionTokens ?? message.completionTokens,
      cachedTokens: cachedTokens ?? message.cachedTokens,
      durationMs: durationMs ?? message.durationMs,
      hostedServerMessageId:
          hostedServerMessageId ?? message.hostedServerMessageId,
    );

    if (isTemporaryConversation(message.conversationId)) {
      _replaceCachedMessage(updatedMessage);
      return;
    }

    await _messagesBox.put(messageId, updatedMessage);

    // [kelivo-hosted] kelivo-arch.md §5 — the first time any message of a
    // conversation gets tagged with a `hostedServerMessageId`, flip the
    // owning conversation to `hostedSynced` so it becomes eligible for
    // `syncConversationList`'s discovery/deletion/title sync.
    if (hostedServerMessageId != null) {
      final owningConvo = _conversationsBox.get(message.conversationId);
      if (owningConvo != null && !owningConvo.hostedSynced) {
        owningConvo.hostedSynced = true;
        await owningConvo.save();
      }
    }

    // Update streaming tracking for crash-recovery
    if (isStreaming == false) {
      _untrackStreamingId(messageId);
    }

    // Update cache
    final conversationId = message.conversationId;
    if (_messagesCache.containsKey(conversationId)) {
      final messages = _messagesCache[conversationId]!;
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        messages[index] = updatedMessage;
      }
    }
    // NOTE: Do NOT call notifyListeners() here to avoid UI rebuilds during streaming
  }

  // Tool events persistence (per assistant message)
  List<Map<String, dynamic>> getToolEvents(String assistantMessageId) {
    if (!_initialized) return const <Map<String, dynamic>>[];
    final temporary = _temporaryToolEvents[assistantMessageId];
    if (temporary != null) return List<Map<String, dynamic>>.of(temporary);
    final v = _toolEventsBox.get(assistantMessageId);
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<void> setToolEvents(
    String assistantMessageId,
    List<Map<String, dynamic>> events,
  ) async {
    if (!_initialized) await init();
    if (_isTemporaryMessageId(assistantMessageId)) {
      _temporaryToolEvents[assistantMessageId] = List<Map<String, dynamic>>.of(
        events,
      );
      notifyListeners();
      return;
    }
    await _toolEventsBox.put(assistantMessageId, events);
    notifyListeners();
  }

  Future<void> upsertToolEvent(
    String assistantMessageId, {
    required String id,
    required String name,
    required Map<String, dynamic> arguments,
    String? content,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_initialized) await init();
    final list = List<Map<String, dynamic>>.of(
      getToolEvents(assistantMessageId),
    );
    final cleanId = (id).toString();

    int idx = -1;
    // Prefer matching by a non-empty id
    if (cleanId.isNotEmpty) {
      idx = list.indexWhere((e) => (e['id']?.toString() ?? '') == cleanId);
    }
    // If no id or not found, match the first placeholder (no content) with same name
    if (idx < 0) {
      idx = list.indexWhere(
        (e) =>
            (e['name']?.toString() ?? '') == name &&
            (e['content'] == null ||
                (e['content']?.toString().isEmpty ?? true)),
      );
    }

    final record = <String, dynamic>{
      'id': cleanId,
      'name': name,
      'arguments': arguments,
      'content': content,
    };
    final existingMetadata = idx >= 0 ? list[idx]['metadata'] : null;
    if (metadata != null && metadata.isNotEmpty) {
      record['metadata'] = metadata;
    } else if (existingMetadata is Map && existingMetadata.isNotEmpty) {
      record['metadata'] = existingMetadata.cast<String, dynamic>();
    }
    if (idx >= 0) {
      list[idx] = record;
    } else {
      list.add(record);
    }
    if (_isTemporaryMessageId(assistantMessageId)) {
      _temporaryToolEvents[assistantMessageId] = list;
      notifyListeners();
      return;
    }
    await _toolEventsBox.put(assistantMessageId, list);
    notifyListeners();
  }

  // Gemini thought signature persistence (per assistant message)
  String? getGeminiThoughtSignature(String assistantMessageId) {
    if (!_initialized) return null;
    final temporary = _temporaryGeminiThoughtSigs[assistantMessageId];
    if (temporary != null && temporary.trim().isNotEmpty) return temporary;
    final v = _toolEventsBox.get(_sigKey(assistantMessageId));
    if (v is String && v.trim().isNotEmpty) return v;
    return null;
  }

  Future<void> setGeminiThoughtSignature(
    String assistantMessageId,
    String signature,
  ) async {
    if (!_initialized) await init();
    if (_isTemporaryMessageId(assistantMessageId)) {
      _temporaryGeminiThoughtSigs[assistantMessageId] = signature;
      notifyListeners();
      return;
    }
    await _toolEventsBox.put(_sigKey(assistantMessageId), signature);
    notifyListeners();
  }

  Future<void> removeGeminiThoughtSignature(String assistantMessageId) async {
    if (!_initialized) await init();
    if (_isTemporaryMessageId(assistantMessageId)) {
      _temporaryGeminiThoughtSigs.remove(assistantMessageId);
      return;
    }
    try {
      await _toolEventsBox.delete(_sigKey(assistantMessageId));
    } catch (_) {}
  }

  Future<Conversation> forkConversation({
    required String title,
    required String? assistantId,
    required List<ChatMessage> sourceMessages,
  }) async {
    if (!_initialized) await init();
    // Create new conversation first
    final convo = await createConversation(
      title: title,
      assistantId: assistantId,
    );
    final ids = <String>[];
    for (final src in sourceMessages) {
      final clone = ChatMessage(
        role: src.role,
        content: src.content,
        timestamp: src.timestamp,
        modelId: src.modelId,
        providerId: src.providerId,
        totalTokens: src.totalTokens,
        conversationId: convo.id,
        isStreaming: false,
        reasoningText: src.reasoningText,
        reasoningStartAt: src.reasoningStartAt,
        reasoningFinishedAt: src.reasoningFinishedAt,
        translation: src.translation,
        reasoningSegmentsJson: src.reasoningSegmentsJson,
        // [kelivo-hosted] A hosted message's image/video/file attachments
        // live ONLY here, never as `[image:...]`/`[file:...]` markers in
        // `content` (see `hostedImagesJson`'s doc comment) — without
        // copying these two, forking a conversation containing a
        // hosted-generated image/video, or any message synced from another
        // device, silently dropped its attachments in the new conversation.
        hostedImagesJson: src.hostedImagesJson,
        hostedFilesJson: src.hostedFilesJson,
      );
      await _messagesBox.put(clone.id, clone);
      ids.add(clone.id);
    }
    // Attach to conversation in storage
    final c = _conversationsBox.get(convo.id);
    if (c != null) {
      c.messageIds
        ..clear()
        ..addAll(ids);
      c.versionSelections = <String, int>{};
      c.updatedAt = DateTime.now();
      await c.save();
    }
    // Cache
    _messagesCache[convo.id] = [for (final id in ids) _messagesBox.get(id)!];
    notifyListeners();
    return _conversationsBox.get(convo.id)!;
  }

  Future<ChatMessage?> appendMessageVersion({
    required String messageId,
    required String content,
    // [kelivo-hosted] Full desired attachment set for the new version — omit
    // both (leave null) to keep whatever the original message already had
    // untouched (used by the assistant-edit-text-only dialog, which never
    // touches attachments). Passed by `HomePageController._saveEditedUserMessageVersion`
    // for the inline user-message editor, which always knows the edit box's
    // current attachment state (existing hosted attachments the user hasn't
    // removed get re-downloaded into these paths first by
    // `buildEditInputData`) — see `ClientBackendApi.editUserMessage`'s
    // docstring for why this re-uploads rather than referencing existing
    // server-side files by id.
    List<String>? imagePaths,
    List<DocumentAttachment>? documents,
  }) async {
    if (!_initialized) await init();
    final original = _messagesBox.get(messageId);
    if (original == null) return null;

    final cid = original.conversationId;
    final convo = _conversationsBox.get(cid) ?? _draftConversations[cid];
    if (convo == null) return null;

    var gid = (original.groupId ?? original.id);
    String? hostedServerMessageId;
    int? hostedVersion;
    String? hostedImagesJson = original.hostedImagesJson;
    String? hostedFilesJson = original.hostedFilesJson;
    final bool attachmentsProvided = imagePaths != null || documents != null;
    // [kelivo-hosted] Register this edit as a real server-side message
    // version FIRST (same server-then-local ordering `regenerateAtMessage`
    // already uses) — until this existed, an edit was purely a local Hive
    // operation that never reached the server at all: another signed-in
    // device could never see it or page between versions, and the very
    // next hosted regenerate rebuilt its prompt from the stale original
    // text since the server had no idea an edit ever happened. On failure
    // (offline, server error) we fall back to the old local-only grouping
    // below — editing still works on this device, it just won't propagate
    // until a later successful edit/sync reconciles it.
    if (convo.hostedSynced && original.hostedServerMessageId != null) {
      final token = ClientBackendSession.token;
      if (token != null) {
        try {
          final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
          List<String>? uploadImages;
          List<Map<String, dynamic>>? uploadDocs;
          if (attachmentsProvided) {
            uploadImages = <String>[];
            for (final path in imagePaths ?? const <String>[]) {
              try {
                uploadImages.add(
                  await ChatApiService.encodeLocalFileAsDataUrl(path),
                );
              } catch (_) {}
            }
            uploadDocs = <Map<String, dynamic>>[];
            for (final doc in documents ?? const <DocumentAttachment>[]) {
              try {
                final dataUrl = await ChatApiService.encodeLocalFileAsDataUrl(
                  doc.path,
                );
                uploadDocs.add({
                  'filename': doc.fileName,
                  'mimeType': doc.mime,
                  'data': dataUrl,
                });
              } catch (_) {}
            }
          }
          final result = await api.editUserMessage(
            token,
            original.hostedServerMessageId!,
            content,
            images: uploadImages,
            documents: uploadDocs,
            versionSelections: versionSelectionsForNetwork(convo.id),
          );
          if (result.isSuccess) {
            if (attachmentsProvided) {
              hostedImagesJson = _encodeHostedImagesJson(result.images);
              hostedFilesJson = _encodeHostedFilesJson(result.files);
            }
            // Adopt the server's canonical group id/version outright rather
            // than recomputing a local max-version scan against it — this
            // new `hosted:`-prefixed gid has no prior local rows to scan in
            // the first place (the original/earlier versions still carry
            // whatever local-only gid they had before this edit), so a
            // local scan would wrongly restart numbering from 0.
            gid = 'hosted:${result.groupId!}';
            hostedServerMessageId = result.messageId;
            hostedVersion = result.version;
            // [kelivo-hosted] The ORIGINAL message's own local `groupId` is
            // still whatever it was before (usually `null`, i.e. its own
            // local id) — it never gets rewritten to this canonical
            // `hosted:...` value on its own. Without forcing it here too,
            // `ChatController.collapseVersions` (groups by `groupId ?? id`)
            // sees the original and this new version as TWO DIFFERENT
            // groups on THIS SAME editing device, showing up as two
            // separate bubbles instead of one message with a pager — same
            // bug the identical fix in `chat_actions.dart`'s
            // `regenerateAtMessage` (search "Force the ORIGINAL reply's
            // persisted `groupId`") already prevents for assistant replies.
            if (original.groupId != gid) {
              // Reuses the same `updateMessage` the assistant-regenerate path
              // calls for its own identical fix (`chat_actions.dart`'s
              // "Force the ORIGINAL reply's persisted `groupId`") — updates
              // the Hive row and `ChatService`'s own `_messagesCache`, but
              // NOT `ChatController`'s separate in-memory `_messages` copy;
              // the caller (`home_page_controller.dart`) still needs to
              // patch that via `getMessageById` + `updateMessageInList`
              // after this method returns, the same way the caller-side
              // `assistant_message.groupId` fix works.
              await updateMessage(original.id, groupId: gid);
            }
          }
        } catch (_) {}
      }
    }

    int nextVersion;
    if (hostedVersion != null) {
      nextVersion = hostedVersion;
    } else {
      // Find current max version within this group in this conversation
      int maxVersion = -1;
      for (final mid in convo.messageIds) {
        final m = _messagesBox.get(mid);
        if (m == null) continue;
        final mg = (m.groupId ?? m.id);
        if (mg == gid) {
          if (m.version > maxVersion) maxVersion = m.version;
        }
      }
      nextVersion = maxVersion + 1;
    }

    final newMsg = ChatMessage(
      role: original.role,
      content: content,
      conversationId: cid,
      modelId: original.modelId,
      providerId: original.providerId,
      totalTokens: null,
      isStreaming: false,
      groupId: gid,
      version: nextVersion,
      hostedServerMessageId: hostedServerMessageId,
      // [kelivo-hosted] Defaults (set above) to the original's own values —
      // in hosted mode these are the ONLY place an attachment is recorded
      // (`content` has no `[image:...]`/`[file:...]` markers for
      // server-stored attachments), so without that default
      // `_parseUserContentWithHostedImages` (chat_message_widget.dart) would
      // have nothing to fall back to on the new version. Overwritten above
      // with the server's authoritative post-edit set whenever the caller
      // actually declared a new attachment set (`attachmentsProvided`).
      hostedImagesJson: hostedImagesJson,
      hostedFilesJson: hostedFilesJson,
    );
    await _messagesBox.put(newMsg.id, newMsg);
    // Append to conversation order at the end (we'll group when rendering)
    if (_draftConversations.containsKey(cid)) {
      final draft = _draftConversations[cid]!;
      draft.messageIds.add(newMsg.id);
      draft.updatedAt = DateTime.now();
      draft.versionSelections[gid] = nextVersion;
    } else {
      final c = _conversationsBox.get(cid);
      if (c != null) {
        c.messageIds.add(newMsg.id);
        c.updatedAt = DateTime.now();
        // Persist selection of latest version for this group
        c.versionSelections[gid] = nextVersion;
        await c.save();
      }
    }
    // Update caches
    final arr = _messagesCache[cid];
    if (arr != null) arr.add(newMsg);
    notifyListeners();
    return newMsg;
  }

  // [kelivo-hosted] Every hosted message's LOCAL `ChatMessage.groupId` is
  // canonicalized to `hosted:$serverGroupId` (see `_buildHostedSeedMessage`/
  // `appendMessageVersion` below) purely so the pre-existing BYOK-style
  // pager (`ChatController`/`message_list_view.dart`) can collapse/page
  // through hosted and local messages with the exact same `groupId`-keyed
  // logic, with no separate code path. `version_selections` was added
  // later and — this was the bug — never accounted for that prefix: a
  // manual version switch is always recorded under the `hosted:`-prefixed
  // key (since that's the `groupId` the pager itself hands to
  // `setSelectedVersion`), while anything seeded from the SERVER's
  // `Conversation.version_selections` (which only ever knows the bare
  // server-side `group_id` — a raw DB UUID, no such prefix exists there)
  // landed under the unprefixed key instead. The two silently coexisted as
  // separate map entries, so the outgoing network payload for a
  // send/regenerate/edit — sent as this whole map — carried BOTH: the
  // live, correctly-updated switch under one key, and a stale, long-dead
  // value (frozen from whenever it was first seeded) under the other.
  // Since the server only ever recognizes the bare key, it read the stale
  // one and silently ignored the real switch entirely. These two helpers
  // are the only correct way to cross the local/network boundary from here
  // on: strip going OUT, add going IN.
  String _networkGroupId(String localGroupId) =>
      localGroupId.startsWith('hosted:')
      ? localGroupId.substring('hosted:'.length)
      : localGroupId;

  String _localGroupId(String serverGroupId) =>
      serverGroupId.startsWith('hosted:')
      ? serverGroupId
      : 'hosted:$serverGroupId';

  Map<String, int> _toNetworkVersionSelections(Map<String, int> local) =>
      local.map((k, v) => MapEntry(_networkGroupId(k), v));

  /// The LOCAL (`hosted:`-prefixed) view of this conversation's version
  /// selections — what `ChatController`/the pager UI reads. NOT what a
  /// send/regenerate/edit network call should send; use
  /// [versionSelectionsForNetwork] for that.
  Map<String, int> getVersionSelections(String conversationId) {
    final c =
        _conversationsBox.get(conversationId) ??
        _draftConversations[conversationId];
    return Map<String, int>.from(c?.versionSelections ?? const <String, int>{});
  }

  /// The wire form of [getVersionSelections] — bare (unprefixed) group ids,
  /// exactly what the backend's `group_id` column actually stores. Always
  /// use this, never [getVersionSelections] directly, when building a
  /// `versionSelections` field for `ClientBackendApi.sendMessage`/
  /// `regenerateMessage`/`editUserMessage`.
  Map<String, int> versionSelectionsForNetwork(String conversationId) =>
      _toNetworkVersionSelections(getVersionSelections(conversationId));

  Future<void> setSelectedVersion(
    String conversationId,
    String groupId,
    int version,
  ) async {
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.versionSelections[groupId] = version;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final c = _conversationsBox.get(conversationId);
    if (c == null) return;
    c.versionSelections[groupId] = version;
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();

    // [kelivo-hosted] Sync the switch to the server so other devices/webui
    // see it too (kelivo-arch.md §6) — this is the out-of-band path for
    // when the switch isn't immediately followed by a send/regenerate/edit
    // (those already carry the current selections inline, race-free; see
    // `ClientBackendApi.sendMessage`'s `versionSelections` param).
    // Fire-and-forget, same tone as `_pushHostedConversationTitle`.
    if (c.hostedSynced) {
      unawaited(
        _pushHostedVersionSelection(
          conversationId,
          _networkGroupId(groupId),
          version,
        ),
      );
    }
  }

  Future<void> _pushHostedVersionSelection(
    String conversationId,
    String serverGroupId,
    int version,
  ) async {
    final token = ClientBackendSession.token;
    if (token == null) return;
    try {
      final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
      await api.updateVersionSelection(
        token,
        conversationId,
        serverGroupId,
        version,
      );
    } catch (_) {}
  }

  Future<void> clearSelectedVersion(
    String conversationId,
    String groupId,
  ) async {
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.versionSelections.remove(groupId);
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }
    final c = _conversationsBox.get(conversationId);
    if (c == null) return;
    c.versionSelections.remove(groupId);
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
  }

  Future<Conversation?> toggleTruncateAtTail(
    String conversationId, {
    String? defaultTitle,
  }) async {
    if (!_initialized) await init();
    // Draft case
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      final lastIndexPlusOne = draft.messageIds.length; // last index + 1
      final newValue = (draft.truncateIndex == lastIndexPlusOne)
          ? -1
          : lastIndexPlusOne;
      draft.truncateIndex = newValue;
      if ((defaultTitle ?? '').isNotEmpty) draft.title = defaultTitle!;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return draft;
    }
    // Persisted case
    final c = _conversationsBox.get(conversationId);
    if (c == null) return null;
    final lastIndexPlusOne = c.messageIds.length;
    final newValue = (c.truncateIndex == lastIndexPlusOne)
        ? -1
        : lastIndexPlusOne;
    c.truncateIndex = newValue;
    if ((defaultTitle ?? '').isNotEmpty) c.title = defaultTitle!;
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
    return c;
  }

  Future<void> deleteMessage(String messageId) async {
    if (!_initialized) return;

    final message =
        _messagesBox.get(messageId) ?? _cachedTemporaryMessage(messageId);
    if (message == null) return;

    if (isTemporaryConversation(message.conversationId)) {
      final conversation = _draftConversations[message.conversationId];
      conversation?.messageIds.remove(messageId);
      final messages = _messagesCache[message.conversationId];
      messages?.removeWhere((m) => m.id == messageId);
      _temporaryToolEvents.remove(messageId);
      _temporaryGeminiThoughtSigs.remove(messageId);
      notifyListeners();
      return;
    }

    final conversation = _conversationsBox.get(message.conversationId);
    if (conversation != null) {
      final gid = message.groupId ?? message.id;
      final ids = conversation.messageIds;

      // Find the earliest position of this message group before removal so we
      // can keep the group anchored when deleting one of its versions.
      int anchorIndex = -1;
      for (int i = 0; i < ids.length; i++) {
        final mid = ids[i];
        final m = _messagesBox.get(mid);
        if (m == null) continue;
        final mgid = m.groupId ?? m.id;
        if (mgid == gid) {
          anchorIndex = i;
          break;
        }
      }

      ids.remove(messageId);

      // If we removed the earliest version but other versions remain, move the
      // earliest remaining one back to the original anchor index to preserve
      // the group's relative order in the conversation.
      if (anchorIndex >= 0) {
        int? earliestRemaining;
        for (int i = 0; i < ids.length; i++) {
          final mid = ids[i];
          final m = _messagesBox.get(mid);
          if (m == null) continue;
          final mgid = m.groupId ?? m.id;
          if (mgid == gid) {
            earliestRemaining = i;
            break;
          }
        }

        if (earliestRemaining != null && earliestRemaining > anchorIndex) {
          final replacementId = ids.removeAt(earliestRemaining);
          final insertAt = anchorIndex <= ids.length ? anchorIndex : ids.length;
          ids.insert(insertAt, replacementId);
        }
      }

      await conversation.save();
    }

    await _messagesBox.delete(messageId);
    // Remove any tool events linked to this assistant message
    if (message.role == 'assistant') {
      try {
        await _toolEventsBox.delete(message.id);
      } catch (_) {}
      try {
        await _toolEventsBox.delete(_sigKey(message.id));
      } catch (_) {}
    }

    // Update cache: clear this conversation so that next getMessages()
    // reloads messages in the updated order from conversation.messageIds.
    _messagesCache.remove(message.conversationId);

    // Clean up orphaned upload files that are no longer referenced by any message
    await _cleanupOrphanUploads();

    // [kelivo-hosted] Fire-and-forget server-side soft-delete
    // (kelivo-arch.md 5) — only meaningful when this message has a known
    // server id (assistant messages always do; user messages do once sent
    // via the hosted provider, see chat_actions.dart/hosted.dart).
    final hostedId = message.hostedServerMessageId;
    if (hostedId != null) {
      unawaited(_deleteHostedMessage(hostedId));
    }

    notifyListeners();
  }

  Future<void> _deleteHostedMessage(String hostedMessageId) async {
    final token = ClientBackendSession.token;
    if (token == null) return;
    try {
      final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
      await api.deleteMessage(token, hostedMessageId);
    } catch (_) {}
  }

  void setCurrentConversation(String? id) {
    if (id != _currentConversationId) {
      _discardTemporaryConversation(_currentConversationId);
    }
    _currentConversationId = id;
    notifyListeners();
  }

  Future<void> clearAllData() async {
    if (!_initialized) return;

    await _messagesBox.clear();
    await _conversationsBox.clear();
    await _toolEventsBox.clear();
    _messagesCache.clear();
    _draftConversations.clear();
    _temporaryConversationIds.clear();
    _temporaryToolEvents.clear();
    _temporaryGeminiThoughtSigs.clear();
    _currentConversationId = null;
    // Remove uploads directory completely
    try {
      final uploadDir = await AppDirectories.getUploadDirectory();
      if (await uploadDir.exists()) {
        await uploadDir.delete(recursive: true);
      }
    } catch (_) {}
    notifyListeners();
  }

  // Uploads stats: count and total size of files under app documents/upload
  Future<UploadStats> getUploadStats() async {
    try {
      final uploadDir = await AppDirectories.getUploadDirectory();
      if (!await uploadDir.exists()) {
        return const UploadStats(fileCount: 0, totalBytes: 0);
      }
      int count = 0;
      int bytes = 0;
      final entries = uploadDir.listSync(recursive: true, followLinks: false);
      for (final ent in entries) {
        if (ent is File) {
          count += 1;
          try {
            bytes += await ent.length();
          } catch (_) {}
        }
      }
      return UploadStats(fileCount: count, totalBytes: bytes);
    } catch (_) {
      return const UploadStats(fileCount: 0, totalBytes: 0);
    }
  }

  // Move an existing conversation to a different assistant.
  // If the conversation is still a draft, update it in memory;
  // otherwise persist the assistantId change and updatedAt.
  Future<void> moveConversationToAssistant({
    required String conversationId,
    required String assistantId,
  }) async {
    if (!_initialized) await init();

    // Draft conversation case
    if (_draftConversations.containsKey(conversationId)) {
      final draft = _draftConversations[conversationId]!;
      draft.assistantId = assistantId;
      draft.updatedAt = DateTime.now();
      notifyListeners();
      return;
    }

    final c = _conversationsBox.get(conversationId);
    if (c == null) return;
    c.assistantId = assistantId;
    c.updatedAt = DateTime.now();
    await c.save();
    notifyListeners();
  }
}

class UploadStats {
  final int fileCount;
  final int totalBytes;
  const UploadStats({required this.fileCount, required this.totalBytes});
}
