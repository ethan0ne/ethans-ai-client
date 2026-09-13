class DocumentAttachment {
  final String path; // absolute file path
  final String fileName;
  final String mime; // e.g. application/pdf, text/plain

  const DocumentAttachment({
    required this.path,
    required this.fileName,
    required this.mime,
  });
}

/// An attachment the user explicitly selected with the inline reference
/// button. The historic class name is retained because it is part of the
/// existing client-side API; the wire payload now supports every attachment
/// type.
class ChatInputImageReference {
  final String token;
  final String? fileId;
  final int? draftImageIndex;
  final int? draftDocumentIndex;
  final int? start;
  final int? end;
  final String? label;
  final String? mimeType;

  const ChatInputImageReference({
    required this.token,
    this.fileId,
    this.draftImageIndex,
    this.draftDocumentIndex,
    this.start,
    this.end,
    this.label,
    this.mimeType,
  });

  ChatInputImageReference copyWith({int? start, int? end}) {
    return ChatInputImageReference(
      token: token,
      fileId: fileId,
      draftImageIndex: draftImageIndex,
      draftDocumentIndex: draftDocumentIndex,
      start: start ?? this.start,
      end: end ?? this.end,
      label: label,
      mimeType: mimeType,
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    if (fileId != null) 'file_id': fileId,
    if (draftImageIndex != null) 'draft_image_index': draftImageIndex,
    if (draftDocumentIndex != null) 'draft_document_index': draftDocumentIndex,
    if (start != null) 'start': start,
    if (end != null) 'end': end,
    if (label != null) 'label': label,
    if (mimeType != null) 'mime_type': mimeType,
  };
}

/// Exact inline structure of the composer. Text segments are preserved as
/// text; attachment segments are created only by the reference picker. This
/// is the authoritative protocol sent to the hosted backend, so a manually
/// typed `@...` remains a normal text segment.
class ChatAttachmentSegment {
  final String type; // "text" | "attachment"
  final String? text;
  final ChatInputImageReference? reference;

  const ChatAttachmentSegment.text(this.text) : type = 'text', reference = null;

  const ChatAttachmentSegment.attachment(this.reference)
    : type = 'attachment',
      text = null;

  Map<String, dynamic> toJson() => {
    'type': type,
    if (type == 'text') 'text': text ?? '',
    if (type == 'attachment') ...?reference?.toJson(),
  };
}

/// Attachment candidates shown by the self-hosted normal-chat reference
/// picker.
class ChatImageReferenceCandidate {
  final String id;
  final String label;
  final String? fileId;
  final String? localPath;
  final String? previewSource;
  final int? draftImageIndex;
  final int? draftDocumentIndex;
  final String? fileName;
  final String? mimeType;

  const ChatImageReferenceCandidate({
    required this.id,
    required this.label,
    this.fileId,
    this.localPath,
    this.previewSource,
    this.draftImageIndex,
    this.draftDocumentIndex,
    this.fileName,
    this.mimeType,
  });

  bool get isImage => mimeType?.startsWith('image/') ?? localPath != null;
}

class ChatInputData {
  final String text;
  final List<String> imagePaths; // absolute file paths or data URLs
  final List<DocumentAttachment> documents; // selected files
  final List<ChatInputImageReference> imageReferences;
  final List<ChatAttachmentSegment> attachmentSegments;
  final bool allowImagesApiRouting;
  // Optional size/count overrides for models routed through the OpenAI
  // images/generations API (e.g. gpt-image-*, dall-e-*). Only relevant when
  // the selected model is marked as an image-output model.
  final String? imageGenSize;
  final int? imageGenCount;
  // Optional duration/aspect-ratio/resolution/extend-mode overrides for
  // models routed through the xAI videos API (`/v1/videos/generations`/
  // `/edits`/`/extensions`). Only relevant when the selected model is
  // marked as a video-output model.
  final int? videoDuration;
  final String? videoAspectRatio;
  final String? videoResolution;
  final bool? videoExtendMode;

  const ChatInputData({
    required this.text,
    this.imagePaths = const [],
    this.documents = const [],
    this.imageReferences = const [],
    this.attachmentSegments = const [],
    this.allowImagesApiRouting = true,
    this.imageGenSize,
    this.imageGenCount,
    this.videoDuration,
    this.videoAspectRatio,
    this.videoResolution,
    this.videoExtendMode,
  });
}

enum ChatInputSubmissionResult { sent, queued, rejected }

class QueuedChatInput {
  final String conversationId;
  final ChatInputData input;

  const QueuedChatInput({required this.conversationId, required this.input});
}
