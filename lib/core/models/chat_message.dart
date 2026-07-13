import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'chat_message.g.dart';

@HiveType(typeId: 0)
class ChatMessage extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String role; // 'user' or 'assistant'

  @HiveField(2)
  final String content;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  final String? modelId;

  @HiveField(5)
  final String? providerId;

  @HiveField(6)
  final int? totalTokens;

  @HiveField(7)
  final String conversationId;

  @HiveField(8)
  final bool isStreaming;

  // Optional reasoning fields for assistant messages
  @HiveField(9)
  final String? reasoningText;

  @HiveField(10)
  final DateTime? reasoningStartAt;

  @HiveField(11)
  final DateTime? reasoningFinishedAt;

  // Translation field for translated content
  @HiveField(12)
  final String? translation;

  // JSON encoded reasoning segments for multiple reasoning blocks
  @HiveField(13)
  final String? reasoningSegmentsJson;

  // Versioning: group messages sharing the same semantic position
  // groupId identifies a message thread; version starts from 0 and increments
  @HiveField(14)
  final String? groupId;

  @HiveField(15)
  final int version;

  @HiveField(16)
  final int? promptTokens;

  @HiveField(17)
  final int? completionTokens;

  @HiveField(18)
  final int? cachedTokens;

  @HiveField(19)
  final int? durationMs;

  // [kelivo-hosted] kelivo-arch.md §5 — the hosted backend's own id for this
  // message's assistant reply (`SendMessageResponse.assistant_message_id`),
  // set once when a hosted generation starts. Lets `ChatService.init()`
  // reconcile against the server's authoritative state after a force-quit
  // instead of just discarding whatever partial text happened to be
  // persisted at the moment the app died — see `_resetStaleStreamingFlags`.
  // Null for every non-hosted message.
  @HiveField(20)
  final String? hostedServerMessageId;

  // [kelivo-hosted] JSON-encoded list of `{id, url, mimeType}` for images
  // attached to this message, straight from the server's structured
  // `ClientMessageOut.images` (see `ClientChatMessage.images` in
  // client_backend_api.dart). Hosted messages no longer embed image
  // markdown/markers in `content` (server strips the sending device's own
  // `[image:<local path>]` marker before returning it — that path is
  // meaningless on any other device), so this is the only place a
  // synced/other-device view of a hosted message's images lives. Null for
  // every non-hosted message and for hosted messages with no images.
  @HiveField(21)
  final String? hostedImagesJson;

  // [kelivo-hosted] JSON-encoded list of `{id, filename, mimeType,
  // extractedText}` for non-image file attachments (PDF/txt/etc) on this
  // message — the server's structured `ClientMessageOut.files` (see
  // `ClientChatMessage.files` in client_backend_api.dart). Same reasoning as
  // `hostedImagesJson`: `content` no longer carries the sending device's
  // `## user sent a file: ...` template (that's now injected server-side
  // only for the upstream model call, not stored/synced), so this is the
  // only place a synced/other-device view of a hosted message's file
  // attachments lives.
  @HiveField(22)
  final String? hostedFilesJson;

  // Set when `content` holds a generation-failure message rather than a
  // real assistant reply (see `ChatActions._handleStreamError` and
  // `ChatService._contentOrFailureReason`), so the UI can style it
  // distinctly instead of rendering it as a normal completed reply.
  @HiveField(23, defaultValue: false)
  final bool isError;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.modelId,
    this.providerId,
    this.totalTokens,
    required this.conversationId,
    this.isStreaming = false,
    this.reasoningText,
    this.reasoningStartAt,
    this.reasoningFinishedAt,
    this.translation,
    this.reasoningSegmentsJson,
    String? groupId,
    int? version,
    this.promptTokens,
    this.completionTokens,
    this.cachedTokens,
    this.durationMs,
    this.hostedServerMessageId,
    this.hostedImagesJson,
    this.hostedFilesJson,
    this.isError = false,
  }) : id = id ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now(),
       groupId = groupId ?? id,
       version = version ?? 0;

  ChatMessage copyWith({
    String? id,
    String? role,
    String? content,
    DateTime? timestamp,
    String? modelId,
    String? providerId,
    int? totalTokens,
    String? conversationId,
    bool? isStreaming,
    String? reasoningText,
    DateTime? reasoningStartAt,
    DateTime? reasoningFinishedAt,
    String? translation,
    String? reasoningSegmentsJson,
    String? groupId,
    int? version,
    int? promptTokens,
    int? completionTokens,
    int? cachedTokens,
    int? durationMs,
    String? hostedServerMessageId,
    String? hostedImagesJson,
    String? hostedFilesJson,
    bool? isError,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      modelId: modelId ?? this.modelId,
      providerId: providerId ?? this.providerId,
      totalTokens: totalTokens ?? this.totalTokens,
      conversationId: conversationId ?? this.conversationId,
      isStreaming: isStreaming ?? this.isStreaming,
      reasoningText: reasoningText ?? this.reasoningText,
      reasoningStartAt: reasoningStartAt ?? this.reasoningStartAt,
      reasoningFinishedAt: reasoningFinishedAt ?? this.reasoningFinishedAt,
      translation: translation ?? this.translation,
      reasoningSegmentsJson:
          reasoningSegmentsJson ?? this.reasoningSegmentsJson,
      groupId: groupId ?? this.groupId,
      version: version ?? this.version,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      cachedTokens: cachedTokens ?? this.cachedTokens,
      durationMs: durationMs ?? this.durationMs,
      hostedServerMessageId:
          hostedServerMessageId ?? this.hostedServerMessageId,
      hostedImagesJson: hostedImagesJson ?? this.hostedImagesJson,
      hostedFilesJson: hostedFilesJson ?? this.hostedFilesJson,
      isError: isError ?? this.isError,
    );
  }

  // [kelivo-hosted] Whether `hostedFilesJson` carries a generated video
  // (`mimeType`/`mime_type` starting with `video/`) — same decoding
  // `ChatMessageWidget._hostedGeneratedVideos` does to render
  // `HostedVideoPlayer`, but as a cheap presence check for callers (e.g.
  // "Extend mode" in chat_input_bar.dart) that only need to know whether
  // this conversation has a video to extend, not the video itself.
  bool get hasHostedVideoFile {
    final json = hostedFilesJson;
    if (json == null || json.isEmpty) return false;
    try {
      final decoded = jsonDecode(json) as List;
      return decoded.any((e) {
        final m = e as Map<String, dynamic>;
        final mime = (m['mimeType'] ?? m['mime_type']) as String?;
        return mime != null && mime.toLowerCase().startsWith('video/');
      });
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'modelId': modelId,
      'providerId': providerId,
      'totalTokens': totalTokens,
      'conversationId': conversationId,
      'isStreaming': isStreaming,
      'reasoningText': reasoningText,
      'reasoningStartAt': reasoningStartAt?.toIso8601String(),
      'reasoningFinishedAt': reasoningFinishedAt?.toIso8601String(),
      'translation': translation,
      'reasoningSegmentsJson': reasoningSegmentsJson,
      'groupId': groupId,
      'version': version,
      'promptTokens': promptTokens,
      'completionTokens': completionTokens,
      'cachedTokens': cachedTokens,
      'durationMs': durationMs,
      'hostedServerMessageId': hostedServerMessageId,
      'hostedImagesJson': hostedImagesJson,
      'hostedFilesJson': hostedFilesJson,
      'isError': isError,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      modelId: json['modelId'] as String?,
      providerId: json['providerId'] as String?,
      totalTokens: json['totalTokens'] as int?,
      conversationId: json['conversationId'] as String,
      isStreaming: json['isStreaming'] as bool? ?? false,
      reasoningText: json['reasoningText'] as String?,
      reasoningStartAt: json['reasoningStartAt'] != null
          ? DateTime.parse(json['reasoningStartAt'] as String)
          : null,
      reasoningFinishedAt: json['reasoningFinishedAt'] != null
          ? DateTime.parse(json['reasoningFinishedAt'] as String)
          : null,
      translation: json['translation'] as String?,
      reasoningSegmentsJson: json['reasoningSegmentsJson'] as String?,
      groupId: json['groupId'] as String?,
      version: (json['version'] as int?) ?? 0,
      promptTokens: json['promptTokens'] as int?,
      completionTokens: json['completionTokens'] as int?,
      cachedTokens: json['cachedTokens'] as int?,
      durationMs: json['durationMs'] as int?,
      hostedServerMessageId: json['hostedServerMessageId'] as String?,
      hostedImagesJson: json['hostedImagesJson'] as String?,
      hostedFilesJson: json['hostedFilesJson'] as String?,
      isError: json['isError'] as bool? ?? false,
    );
  }
}
