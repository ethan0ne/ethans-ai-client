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

class ChatInputData {
  final String text;
  final List<String> imagePaths; // absolute file paths or data URLs
  final List<DocumentAttachment> documents; // selected files
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
