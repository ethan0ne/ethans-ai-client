import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../../../theme/design_tokens.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/widgets/local_video_thumbnail.dart';
import '../../../utils/file_import_helper.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../shared/responsive/breakpoints.dart';
import 'dart:async';
import 'dart:io';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/instruction_injection.dart';
import '../../../core/models/quick_phrase.dart';
import '../../../utils/clipboard_images.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/api/builtin_tools.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/search/search_service.dart';
import '../../../core/utils/multimodal_input_utils.dart';
import '../../../core/utils/video_duration_options.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/app_switch.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/frosted_popup_menu.dart';
import '../../../utils/app_directories.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:video_player/video_player.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import '../../../utils/sandbox_path_resolver.dart';
import '../../../utils/resolve_image_provider.dart';
import 'mini_map_sheet.dart' show showImageReferenceSheet;

const double _composerButtonIslandHeight = 44;

/// Picks whichever `"W:H"` option in [options] is closest to [size]'s actual
/// ratio, comparing on a log scale so e.g. a 3:4 source and a 4:3 option are
/// judged symmetrically instead of the comparison being skewed by landscape
/// ratios having a larger raw numeric range than portrait ones. Returns null
/// if [size] or every option is degenerate/unparseable.
///
/// Top-level (not a `_ChatInputBarState` method) so it's unit-testable
/// without needing the whole widget/video-mode machinery — see
/// `_maybeAutoRecommendVideoAspectRatio` for where the real attachment path
/// calls it.
String? nearestAspectRatioOption(Size size, List<String> options) {
  if (size.width <= 0 || size.height <= 0 || options.isEmpty) return null;
  final actualRatio = size.width / size.height;
  String? best;
  double bestDelta = double.infinity;
  for (final option in options) {
    final parts = option.split(':');
    if (parts.length != 2) continue;
    final w = double.tryParse(parts[0]);
    final h = double.tryParse(parts[1]);
    if (w == null || h == null || w <= 0 || h <= 0) continue;
    final delta = (math.log(actualRatio) - math.log(w / h)).abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      best = option;
    }
  }
  return best;
}

class _SerializedComposerReference {
  const _SerializedComposerReference({
    required this.start,
    required this.end,
    required this.reference,
  });

  final int start;
  final int end;
  final ChatInputImageReference reference;
}

class _SerializedComposer {
  const _SerializedComposer({required this.text, required this.references});

  final String text;
  final List<_SerializedComposerReference> references;
}

class _AttachmentReferenceChip extends StatelessWidget {
  const _AttachmentReferenceChip({
    required this.reference,
    required this.candidate,
    required this.textStyle,
  });

  final ChatInputImageReference reference;
  final ChatImageReferenceCandidate? candidate;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = candidate?.localPath ?? candidate?.previewSource;
    final imageProvider = source == null ? null : resolveImageProvider(source);
    final tokenLabel = reference.token
        .substring(reference.token.indexOf(':') + 1)
        .trim()
        .replaceFirst(RegExp(r' #\d+$'), '');
    final label = candidate?.label ?? reference.label ?? tokenLabel;
    return Container(
      constraints: const BoxConstraints(maxWidth: 110, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageProvider != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Image(
                image: imageProvider,
                width: 14,
                height: 14,
                fit: BoxFit.cover,
              ),
            )
          else
            Icon(
              candidate?.isImage == true ? Lucide.Image : Lucide.FileText,
              size: 14,
              color: colorScheme.primary,
            ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Material TextField-compatible controller backed by shadcn's atomic chip
/// storage. The package controller keeps each chip as one private-use code
/// point; this renderer only controls how that code point is painted.
class AttachmentChipEditingController extends TextEditingController {
  AttachmentChipEditingController({super.text})
    : _chipController = shadcn.ChipEditingController<ChatInputImageReference>(
        text: text,
      );

  final shadcn.ChipEditingController<ChatInputImageReference> _chipController;

  ChatImageReferenceCandidate? Function(String token)? candidateResolver;

  @override
  set value(TextEditingValue newValue) {
    _chipController.value = newValue;
    super.value = newValue;
  }

  @override
  set text(String newText) {
    _chipController.text = newText;
    super.text = newText;
  }

  List<InlineSpan> getSelectionSpans(TextSelection selection) {
    return _chipController.getSelectionSpans(selection);
  }

  void replaceSelectionWithSpans(List<InlineSpan> spans) {
    _chipController.value = value;
    _chipController.replaceSelectionWithSpans(spans);
    super.value = _chipController.value;
  }

  void removeAllChips() {
    _chipController.value = value;
    _chipController.removeAllChips();
    super.value = _chipController.value;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    final spans = _chipController.getSelectionSpans(selection);
    final children = <InlineSpan>[];
    var sourceOffset = 0;

    void addPlainText(String plainText) {
      if (plainText.isEmpty) return;
      final composing = value.composing;
      final composingStart = composing.isValid && withComposing
          ? (composing.start - sourceOffset).clamp(0, plainText.length)
          : 0;
      final composingEnd = composing.isValid && withComposing
          ? (composing.end - sourceOffset).clamp(0, plainText.length)
          : 0;
      if (composingStart >= composingEnd) {
        children.add(TextSpan(text: plainText, style: style));
      } else {
        if (composingStart > 0) {
          children.add(
            TextSpan(
              text: plainText.substring(0, composingStart),
              style: style,
            ),
          );
        }
        children.add(
          TextSpan(
            text: plainText.substring(composingStart, composingEnd),
            style: style?.merge(
              const TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        );
        if (composingEnd < plainText.length) {
          children.add(
            TextSpan(text: plainText.substring(composingEnd), style: style),
          );
        }
      }
      sourceOffset += plainText.length;
    }

    for (final span in spans) {
      if (span is shadcn.ChipSpan<ChatInputImageReference>) {
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _AttachmentReferenceChip(
              reference: span.value,
              candidate: candidateResolver?.call(span.value.token),
              textStyle: style ?? const TextStyle(),
            ),
          ),
        );
        sourceOffset++;
      } else if (span is TextSpan) {
        addPlainText(span.text ?? '');
      }
    }
    return TextSpan(style: style, children: children);
  }

  @override
  void dispose() {
    _chipController.dispose();
    super.dispose();
  }
}

class ChatInputBarController {
  _ChatInputBarState? _state;
  void _bind(_ChatInputBarState s) => _state = s;
  void _unbind(_ChatInputBarState s) {
    if (identical(_state, s)) _state = null;
  }

  bool get allowImagesApiRouting => true;
  bool get hasDraftMedia => _state?._hasDraftMedia ?? false;

  void addImages(List<String> paths) => _state?._addImages(paths);
  void clearImages() => _state?._clearImages();
  void addFiles(List<DocumentAttachment> docs) => _state?._addFiles(docs);
  void clearFiles() => _state?._clearFiles();
  void restoreInput(ChatInputData input) => _state?._restoreInput(input);
  ChatInputData snapshotInput(String text) =>
      _state?._snapshotInput(text) ?? ChatInputData(text: text.trim());
  void clearDraft() => _state?._clearDraft();

  // [kelivo-hosted] Set by `HomePageController._enterUserMessageEdit` while
  // a hosted-origin message's attachments are still being re-downloaded for
  // the inline editor — rendered as loading placeholder tiles in the
  // attachment preview strip (`_buildInlineAttachmentPreviews`) instead of
  // showing an empty strip, which would read as "this message has no
  // attachments" rather than "they're on the way". Reset to 0 once
  // `addImages`/`addFiles` above actually merges the real ones in.
  final ValueNotifier<int> pendingAttachmentCount = ValueNotifier(0);
}

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    this.onSend,
    this.onStop,
    this.onSelectModel,
    this.onOpenMcp,
    this.onLongPressMcp,
    this.onSetSearchEnabled,
    this.onSelectBuiltInSearch,
    this.onSelectSearchService,
    this.onOpenSearchServices,
    this.onConfigureReasoning,
    this.focusNode,
    this.modelIcon,
    this.controller,
    this.mediaController,
    this.loading = false,
    this.hasQueuedInput = false,
    this.queuedPreviewText,
    this.onCancelQueuedInput,
    this.reasoningActive = false,
    this.supportsReasoning = true,
    this.showMcpButton = false,
    this.mcpActive = false,
    this.showMiniMapButton = false,
    this.onOpenMiniMap,
    this.onPickCamera,
    this.onPickPhotos,
    this.onPickPhotosOrVideo,
    this.referenceMode = AttachmentReferenceMode.disabled,
    this.maxReferenceImages = 0,
    this.maxReferenceVideos = 0,
    this.supportsImageInput = true,
    this.isEmbeddingModel = false,
    this.isImageGenerationModel = false,
    this.isVideoGenerationModel = false,
    this.imageReferenceCandidates = const [],
    this.onRefreshImageReferenceCandidates,
    this.onUploadFiles,
    this.onSetInstructionInjectionActive,
    this.activeInstructionInjectionIds,
    this.onOpenWorldBook,
    this.onClearContext,
    this.onCompressContext,
    this.onLongPressLearning,
    this.quickPhrases = const [],
    this.onSelectQuickPhrase,
    this.showOcrButton = false,
    this.onToggleOcr,
    this.conversationId,
    this.sendButtonTooltip,
    this.hasVideoInHistory = false,
  });

  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;
  final VoidCallback? onStop;
  final VoidCallback? onSelectModel;
  final VoidCallback? onOpenMcp;
  final VoidCallback? onLongPressMcp;
  final Future<void> Function(bool)? onSetSearchEnabled;

  /// Selects model built-in search, with the boolean enabling Claude's
  /// dynamic web search variant when supported.
  final Future<void> Function(bool)? onSelectBuiltInSearch;

  /// A null index selects hosted server search; otherwise selects a configured
  /// device search service by its current index.
  final Future<void> Function(int?)? onSelectSearchService;
  final VoidCallback? onOpenSearchServices;
  final VoidCallback? onConfigureReasoning;
  final FocusNode? focusNode;
  final Widget? modelIcon;
  final TextEditingController? controller;
  final ChatInputBarController? mediaController;
  final bool loading;
  final bool hasQueuedInput;
  final String? queuedPreviewText;
  final VoidCallback? onCancelQueuedInput;
  final bool reasoningActive;
  final bool supportsReasoning;
  final bool showMcpButton;
  final bool mcpActive;
  final bool showMiniMapButton;
  final VoidCallback? onOpenMiniMap;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickPhotos;
  // [kelivo-hosted] Merged image/video picker used instead of [onPickPhotos]
  // while video mode is active — see `FileUploadService.onPickPhotosOrVideo`.
  final VoidCallback? onPickPhotosOrVideo;
  final AttachmentReferenceMode referenceMode;
  final int maxReferenceImages;
  final int maxReferenceVideos;
  final bool supportsImageInput;
  final bool isEmbeddingModel;
  final bool isImageGenerationModel;
  final bool isVideoGenerationModel;
  final List<ChatImageReferenceCandidate> imageReferenceCandidates;
  final Future<List<ChatImageReferenceCandidate>> Function()?
  onRefreshImageReferenceCandidates;
  final VoidCallback? onUploadFiles;
  final Future<void> Function(String id, bool active)?
  onSetInstructionInjectionActive;
  final List<String>? activeInstructionInjectionIds;
  final VoidCallback? onOpenWorldBook;
  final VoidCallback? onClearContext;
  final VoidCallback? onCompressContext;
  final VoidCallback? onLongPressLearning;
  final List<QuickPhrase> quickPhrases;
  final ValueChanged<QuickPhrase>? onSelectQuickPhrase;
  final bool showOcrButton;
  final VoidCallback? onToggleOcr;
  final String? conversationId;
  final String? sendButtonTooltip;
  // [kelivo-hosted] Whether the current conversation already has a
  // generated video message (`ChatMessage.hasHostedVideoFile`) the backend
  // could extend/edit even though nothing is staged in this turn's draft
  // (`_docs`) — see `_hasAttachedVideo`'s docstring. Computed by the caller
  // (home_page.dart) from `HomePageController.messages` since this widget
  // has no direct access to the conversation's message list.
  final bool hasVideoInHistory;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with WidgetsBindingObserver {
  late AttachmentChipEditingController _controller;
  TextEditingController? _legacyController;
  bool _ownsChipController = false;
  bool _syncingLegacyController = false;
  bool _isExpanded = false; // Track expand/collapse state for input field
  final List<String> _images = <String>[]; // local file paths
  final List<DocumentAttachment> _docs =
      <DocumentAttachment>[]; // files to upload
  final List<ChatInputImageReference> _imageReferences =
      <ChatInputImageReference>[];
  final Map<String, ChatImageReferenceCandidate> _referenceCandidatesByToken =
      <String, ChatImageReferenceCandidate>{};
  final Map<LogicalKeyboardKey, Timer?> _repeatTimers = {};
  static const Duration _repeatInitialDelay = Duration(milliseconds: 300);
  static const Duration _repeatPeriod = Duration(milliseconds: 35);
  final GlobalKey _collapsedComposerActionsAnchorKey = GlobalKey(
    debugLabel: 'collapsed-composer-actions-anchor',
  );
  final GlobalKey _expandedComposerActionsAnchorKey = GlobalKey(
    debugLabel: 'expanded-composer-actions-anchor',
  );
  final GlobalKey _generationOptionsAnchorKey = GlobalKey(
    debugLabel: 'generation-options-anchor',
  );
  FocusNode? _listenedFocusNode;
  bool _inputFocused = false;
  bool _focusUpdateScheduled = false;
  bool _pendingFocusState = false;
  static const double _documentPreviewHeight = 48;
  static const double _imagePreviewHeight = 64;
  static const double _imageRemoveButtonSize = 18;
  // Suppress context menu briefly after app resume to avoid flickering
  bool _suppressContextMenu = false;
  bool _isCleaningDraftAttachments = false;
  bool _isSubmitting = false;
  String? _imageModeModelKey;
  // Sentinel sent to the backend when the user wants the provider to pick
  // the size itself, instead of a fixed WxH — the backend omits `size`
  // from the upstream request entirely when it sees this value (see
  // `_stream_image_generation` in client_chat_task.py).
  static const String _imageGenSizeAuto = 'auto';
  // Used when the selected model's catalog entry has no admin-configured
  // `image_sizes` preset (see `ChatApiService.imageGenerationSizes`).
  static const List<String> _defaultImageGenSizeOptions = <String>[
    _imageGenSizeAuto,
    '1024x1024',
    '1024x1792',
    '1792x1024',
  ];
  List<String> _imageGenSizeOptions = _defaultImageGenSizeOptions;
  String _imageGenSize = _defaultImageGenSizeOptions.first;
  int _imageGenCount = 1;

  String? _videoModeModelKey;
  // xAI's global fixed enums — used when the selected model's catalog entry
  // has no admin-configured video option preset (mirrors
  // `_defaultImageGenSizeOptions`'s fallback role for `_imageGenSizeOptions`).
  static const List<String> _defaultVideoAspectRatioOptions = <String>[
    '1:1',
    '16:9',
    '9:16',
    '4:3',
    '3:4',
    '3:2',
    '2:3',
  ];
  static const List<String> _defaultVideoResolutionOptions = <String>[
    '480p',
    '720p',
    '1080p',
  ];
  static final List<int> _defaultVideoDurationOptions = <int>[
    for (int v = 1; v <= 15; v++) v,
  ];
  // [kelivo-hosted] Built-in fallback for `/v1/videos/extensions`' own
  // `duration` range (2-10s, default 6) — used when the admin catalog has
  // no `video_extend_durations` preset configured for this model, same
  // "empty means fall back to built-in default" contract every other
  // video/image-gen option list already follows (see
  // `ChatApiService.videoGenerationExtendDurations`).
  static final List<int> _defaultVideoExtendDurationOptions = <int>[
    for (int v = 2; v <= 10; v++) v,
  ];
  static const int _defaultVideoExtendDuration = 6;
  List<String> _videoAspectRatioOptions = _defaultVideoAspectRatioOptions;
  List<String> _videoResolutionOptions = _defaultVideoResolutionOptions;
  List<int> _videoDurationOptions = _defaultVideoDurationOptions;
  int _videoDuration = 5;
  String _videoAspectRatio = '16:9';
  String _videoResolution = '480p';
  bool _videoExtendMode = false;
  // Whether the user has manually picked an aspect ratio for this draft —
  // once true, `_maybeAutoRecommendVideoAspectRatio` stops overwriting
  // `_videoAspectRatio`, so a later attachment swap never clobbers a choice
  // the user actually made. Reset alongside the rest of the draft (see
  // `_clearDraft`/`_clearImages`/`_clearFiles`).
  bool _videoAspectRatioUserSet = false;
  // Tracks video-mode entry/exit across builds so switching models INTO a
  // video model (with media already attached from before the switch) also
  // triggers the auto-recommend — see `_maybeAutoRecommendVideoAspectRatio`.
  bool _wasVideoModeActive = false;

  bool get _composerLocked => widget.hasQueuedInput;

  /// Current model, preferring this conversation's own override, then the
  /// assistant's default, then the global default.
  ({String? providerKey, String? modelId}) _currentModelIds(
    BuildContext context, {
    bool listen = true,
  }) {
    final settings = listen
        ? context.watch<SettingsProvider>()
        : context.read<SettingsProvider>();
    final ap = listen
        ? context.watch<AssistantProvider>()
        : context.read<AssistantProvider>();
    final a = ap.currentAssistant;
    final override = widget.conversationId != null
        ? (listen ? context.watch<ChatService>() : context.read<ChatService>())
              .getConversationChatModel(widget.conversationId!)
        : null;
    return (
      providerKey:
          override?.$1 ?? a?.chatModelProvider ?? settings.currentModelProvider,
      modelId: override?.$2 ?? a?.chatModelId ?? settings.currentModelId,
    );
  }

  bool _supportsImagesApiRouting(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final modelIds = _currentModelIds(context);
    final providerKey = modelIds.providerKey;
    final modelId = modelIds.modelId;
    if (providerKey == null || modelId == null) {
      _imageModeModelKey = null;
      return false;
    }
    final cfg = settings.getProviderConfig(providerKey);
    // [kelivo-hosted] Not `supportsOpenAIImagesApiRouting` — that only
    // answers "should the client itself call images/generations directly"
    // (true only for a direct OpenAI-compatible provider). The size/count
    // options bar must show for any provider kind whose selected model is
    // an image model, including `ProviderKind.hosted` where the hosted
    // backend does the images/generations routing server-side instead.
    final supported = ChatApiService.isImageGenerationModel(cfg, modelId);
    _imageModeModelKey = supported
        ? '${widget.conversationId ?? ''}::$providerKey::$modelId'
        : null;
    if (supported) {
      final catalogSizes = ChatApiService.imageGenerationSizes(cfg, modelId);
      _imageGenSizeOptions = catalogSizes.isNotEmpty
          ? [
              if (!catalogSizes.contains(_imageGenSizeAuto)) _imageGenSizeAuto,
              ...catalogSizes,
            ]
          : _defaultImageGenSizeOptions;
      if (!_imageGenSizeOptions.contains(_imageGenSize)) {
        _imageGenSize = _imageGenSizeOptions.first;
      }
    }
    return supported;
  }

  bool get _imageModeActive => _imageModeModelKey != null;

  bool _supportsVideoApiRouting(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final modelIds = _currentModelIds(context);
    final providerKey = modelIds.providerKey;
    final modelId = modelIds.modelId;
    if (providerKey == null || modelId == null) {
      _videoModeModelKey = null;
      return false;
    }
    final cfg = settings.getProviderConfig(providerKey);
    // Mirrors `_supportsImagesApiRouting` above: the options bar must show
    // for any provider kind whose selected model is a video model, even
    // though only `ProviderKind.hosted` actually routes to the xAI videos
    // endpoints (server-side).
    final supported = ChatApiService.isVideoGenerationModel(cfg, modelId);
    _videoModeModelKey = supported
        ? '${widget.conversationId ?? ''}::$providerKey::$modelId'
        : null;
    if (supported) {
      final catalogAspectRatios = ChatApiService.videoGenerationAspectRatios(
        cfg,
        modelId,
      );
      _videoAspectRatioOptions = catalogAspectRatios.isNotEmpty
          ? catalogAspectRatios
          : _defaultVideoAspectRatioOptions;
      if (!_videoAspectRatioOptions.contains(_videoAspectRatio)) {
        _videoAspectRatio = _videoAspectRatioOptions.first;
      }

      final catalogResolutions = ChatApiService.videoGenerationResolutions(
        cfg,
        modelId,
      );
      _videoResolutionOptions = catalogResolutions.isNotEmpty
          ? catalogResolutions
          : _defaultVideoResolutionOptions;
      if (!_videoResolutionOptions.contains(_videoResolution)) {
        _videoResolution = _videoResolutionOptions.first;
      }

      // [kelivo-hosted] While extend mode is active, this same duration
      // control switches to governing the continuation length sent to
      // `/v1/videos/extensions` instead of the admin-curated total-video-
      // length range sent to `/v1/videos/generations` — its own admin-
      // curated preset (`video_extend_durations`), same
      // fall-back-to-built-in-default contract as the generation-time one.
      if (_videoExtendMode && _hasAttachedVideo) {
        final catalogExtendDurations = VideoDurationOptions.parse(
          ChatApiService.videoGenerationExtendDurations(cfg, modelId),
        );
        _videoDurationOptions = catalogExtendDurations.isNotEmpty
            ? catalogExtendDurations
            : _defaultVideoExtendDurationOptions;
        if (!_videoDurationOptions.contains(_videoDuration)) {
          _videoDuration =
              _videoDurationOptions.contains(_defaultVideoExtendDuration)
              ? _defaultVideoExtendDuration
              : _videoDurationOptions.first;
        }
      } else {
        final catalogDurations = VideoDurationOptions.parse(
          ChatApiService.videoGenerationDurations(cfg, modelId),
        );
        _videoDurationOptions = catalogDurations.isNotEmpty
            ? catalogDurations
            : _defaultVideoDurationOptions;
        if (!_videoDurationOptions.contains(_videoDuration)) {
          _videoDuration = _videoDurationOptions.first;
        }
      }
    }
    return supported;
  }

  bool get _videoModeActive => _videoModeModelKey != null;

  bool get _hasDraftMedia => _images.isNotEmpty || _docs.isNotEmpty;

  /// [kelivo-hosted] Whether "Extend mode" can apply — the backend treats a
  /// turn as an edit/extension (`/v1/videos/edits`/`/extensions`) when
  /// either this turn's draft has a picked video attached
  /// (`onPickPhotosOrVideo`/`_docs`) or the conversation history already has
  /// a generated video
  /// message (`widget.hasVideoInHistory`, scanned by
  /// `_last_message_video_data_url` server-side). With neither, there's no
  /// video to extend, so the toggle should read as off and be
  /// non-interactive rather than silently doing nothing when the turn is
  /// actually sent.
  bool get _hasAttachedVideo =>
      _docs.any((d) => d.mime.startsWith('video/')) || widget.hasVideoInHistory;

  /// Probes the first attached image/video's actual pixel size and, if the
  /// user hasn't manually touched the aspect-ratio option yet, selects
  /// whichever preset in `_videoAspectRatioOptions` is closest to it. No-op
  /// while video mode isn't active — called both right after attaching new
  /// media (`_addImages`/`_addFiles`) and right after switching INTO video
  /// mode with media already attached from before the switch (the
  /// `_wasVideoModeActive` transition check in `build`), so either order
  /// (attach-then-switch or switch-then-attach) ends up recommending.
  Future<void> _maybeAutoRecommendVideoAspectRatio() async {
    if (_videoAspectRatioUserSet || !_videoModeActive) return;
    DocumentAttachment? videoDoc;
    for (final d in _docs) {
      if (d.mime.startsWith('video/')) {
        videoDoc = d;
        break;
      }
    }
    final Size? size = videoDoc != null
        ? await _probeVideoSize(videoDoc.path)
        : (_images.isNotEmpty ? await _probeImageSize(_images.first) : null);
    if (size == null || !mounted) return;
    // Re-check after the await: the user may have picked a ratio manually,
    // or switched out of video mode, while the probe was in flight.
    if (_videoAspectRatioUserSet || !_videoModeActive) return;
    final best = nearestAspectRatioOption(size, _videoAspectRatioOptions);
    if (best != null && best != _videoAspectRatio) {
      setState(() => _videoAspectRatio = best);
    }
  }

  Future<Size?> _probeImageSize(String path) async {
    try {
      if (path.startsWith('http')) return null;
      final file = File(SandboxPathResolver.fix(path));
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final img = await decodeImageFromList(bytes);
      return Size(img.width.toDouble(), img.height.toDouble());
    } catch (_) {
      return null;
    }
  }

  Future<Size?> _probeVideoSize(String path) async {
    VideoPlayerController? controller;
    try {
      final file = File(SandboxPathResolver.fix(path));
      if (!await file.exists()) return null;
      controller = VideoPlayerController.file(file);
      await controller.initialize();
      final s = controller.value.size;
      if (s.width <= 0 || s.height <= 0) return null;
      return s;
    } catch (_) {
      return null;
    } finally {
      await controller?.dispose();
    }
  }

  // ChipInput keeps references as atomic inline objects, so ordinary text and
  // IME composition never edit the visible label inside a reference.
  void _onTextChanged(String _) {
    _syncReferencesFromController();
    _syncLegacyController();
    if (mounted) setState(() {});
  }

  void _syncLegacyController() {
    final legacyController = _legacyController;
    if (legacyController == null) return;
    final serialized = _serializeComposer().text;
    if (legacyController.text == serialized) return;
    _syncingLegacyController = true;
    legacyController.value = TextEditingValue(
      text: serialized,
      selection: TextSelection.collapsed(offset: serialized.length),
      composing: TextRange.empty,
    );
    _syncingLegacyController = false;
  }

  void _onLegacyControllerChanged() {
    if (_syncingLegacyController ||
        _controller.text == _legacyController?.text) {
      return;
    }
    _controller.value = TextEditingValue(
      text: _legacyController?.text ?? '',
      selection: TextSelection.collapsed(
        offset: (_legacyController?.text.length ?? 0),
      ),
      composing: TextRange.empty,
    );
    _syncReferencesFromController();
    if (mounted) setState(() {});
  }

  void _syncReferencesFromController() {
    final spans = _controller.getSelectionSpans(
      TextSelection(baseOffset: 0, extentOffset: _controller.text.length),
    );
    _imageReferences
      ..clear()
      ..addAll(
        spans.whereType<shadcn.ChipSpan<ChatInputImageReference>>().map(
          (span) => span.value,
        ),
      );
    _referenceCandidatesByToken.clear();
    for (final reference in _imageReferences) {
      final candidate = _referenceCandidateByToken(reference.token);
      if (candidate != null) {
        _referenceCandidatesByToken[reference.token] = candidate;
      }
    }
  }

  _SerializedComposer _serializeComposer() {
    final spans = _controller.getSelectionSpans(
      TextSelection(baseOffset: 0, extentOffset: _controller.text.length),
    );
    final text = StringBuffer();
    final references = <_SerializedComposerReference>[];
    for (final span in spans) {
      if (span is shadcn.ChipSpan<ChatInputImageReference>) {
        final start = text.length;
        text.write(span.value.token);
        references.add(
          _SerializedComposerReference(
            start: start,
            end: text.length,
            reference: span.value,
          ),
        );
      } else if (span is TextSpan) {
        text.write(span.text ?? '');
      }
    }
    return _SerializedComposer(text: text.toString(), references: references);
  }

  String _serializeSelection(TextSelection selection) {
    final buffer = StringBuffer();
    for (final span in _controller.getSelectionSpans(selection)) {
      if (span is shadcn.ChipSpan<ChatInputImageReference>) {
        buffer.write(span.value.token);
      } else if (span is TextSpan) {
        buffer.write(span.text ?? '');
      }
    }
    return buffer.toString();
  }

  void _rebuildComposerFromSerialized(_SerializedComposer serialized) {
    _controller.value = TextEditingValue(
      text: serialized.text,
      selection: TextSelection.collapsed(offset: serialized.text.length),
      composing: TextRange.empty,
    );
    for (final item in serialized.references.reversed) {
      _controller.selection = TextSelection(
        baseOffset: item.start,
        extentOffset: item.end,
      );
      _controller.replaceSelectionWithSpans([
        shadcn.ChipSpan<ChatInputImageReference>(
          value: item.reference,
          child: const SizedBox.shrink(),
        ),
      ]);
    }
    _syncReferencesFromController();
    _syncLegacyController();
  }

  ChatImageReferenceCandidate? _referenceCandidateByToken(String token) {
    final separator = token.indexOf(':');
    if (separator < 2) return null;
    final rawLabel = token.substring(separator + 1).trimLeft();
    final label = rawLabel.replaceFirst(RegExp(r' #\d+$'), '');
    for (final candidate in _referenceCandidates()) {
      if (candidate.fileId == rawLabel ||
          candidate.label == rawLabel ||
          candidate.fileName == rawLabel ||
          candidate.fileName == label ||
          candidate.label == label) {
        return candidate;
      }
    }
    return null;
  }

  void _transformComposerReferences(
    ChatInputImageReference? Function(ChatInputImageReference reference)
    transform,
  ) {
    final current = _serializeComposer();
    final text = StringBuffer();
    final references = <_SerializedComposerReference>[];
    var cursor = 0;
    for (final item in current.references) {
      text.write(current.text.substring(cursor, item.start));
      final replacement = transform(item.reference);
      if (replacement != null) {
        final start = text.length;
        text.write(replacement.token);
        references.add(
          _SerializedComposerReference(
            start: start,
            end: text.length,
            reference: replacement,
          ),
        );
      }
      cursor = item.end;
    }
    text.write(current.text.substring(cursor));
    _rebuildComposerFromSerialized(
      _SerializedComposer(text: text.toString(), references: references),
    );
  }

  bool _isDraftReferenceSupported(ChatInputImageReference reference) {
    final isVideo = reference.mimeType?.startsWith('video/') ?? false;
    final isImage =
        reference.draftImageIndex != null ||
        (reference.mimeType?.startsWith('image/') ?? false);
    switch (widget.referenceMode) {
      case AttachmentReferenceMode.disabled:
        return false;
      case AttachmentReferenceMode.chat:
        if (isVideo) return false;
        return !isImage || widget.supportsImageInput;
      case AttachmentReferenceMode.imageGeneration:
        return isImage && widget.maxReferenceImages > 0;
      case AttachmentReferenceMode.videoGeneration:
        return (isImage && widget.maxReferenceImages > 0) ||
            (isVideo && widget.maxReferenceVideos > 0);
    }
  }

  Future<void> _removeUnsupportedDraftReferences() async {
    if (_isCleaningDraftAttachments || !mounted) return;
    _isCleaningDraftAttachments = true;
    try {
      final oldImages = List<String>.of(_images);
      final oldDocs = List<DocumentAttachment>.of(_docs);
      final references = _serializeComposer().references
          .map((item) => item.reference)
          .toList(growable: false);
      final videos = <int>[];
      for (var i = 0; i < oldDocs.length; i++) {
        if (oldDocs[i].mime.startsWith('video/')) videos.add(i);
      }

      final keepImages = <int>{};
      final keepDocs = <int>{};
      final keepReferenceIdentities = <String>{};
      final keptMediaIdentities = <String>{};
      final generationMode =
          widget.isImageGenerationModel || widget.isVideoGenerationModel;
      final generationReferenceChipsEnabled =
          widget.referenceMode == AttachmentReferenceMode.imageGeneration ||
          widget.referenceMode == AttachmentReferenceMode.videoGeneration;
      final chatLike = !widget.isEmbeddingModel && !generationMode;

      String identityOf(ChatInputImageReference reference) {
        if (reference.draftImageIndex != null) {
          return 'image:${reference.draftImageIndex}';
        }
        if (reference.draftDocumentIndex != null) {
          return 'document:${reference.draftDocumentIndex}';
        }
        if (reference.fileId != null) return 'file:${reference.fileId}';
        return 'token:${reference.token}';
      }

      void retainReferences({required bool images, required int limit}) {
        for (final reference in references) {
          final matches = images
              ? _referenceIsImage(reference)
              : _referenceIsVideo(reference);
          if (!matches) continue;
          final identity = identityOf(reference);
          if (keptMediaIdentities.contains(identity)) {
            keepReferenceIdentities.add(identity);
          } else if (keptMediaIdentities.length < limit) {
            keptMediaIdentities.add(identity);
            keepReferenceIdentities.add(identity);
          }
        }
      }

      if (widget.isEmbeddingModel) {
        // Embedding models do not accept chat attachments.
      } else if (chatLike) {
        if (widget.supportsImageInput) {
          keepImages.addAll(Iterable<int>.generate(oldImages.length));
        }
        // Ordinary files remain available to chat models; staged videos are
        // generation inputs and are not valid chat attachments.
        for (var i = 0; i < oldDocs.length; i++) {
          final mime = oldDocs[i].mime;
          if (!mime.startsWith('video/') &&
              (!mime.startsWith('image/') || widget.supportsImageInput)) {
            keepDocs.add(i);
          }
        }
      } else if (widget.isImageGenerationModel) {
        if (generationReferenceChipsEnabled) {
          retainReferences(images: true, limit: widget.maxReferenceImages);
        }
        for (var i = 0; i < oldImages.length; i++) {
          final identity = 'image:$i';
          if (keptMediaIdentities.contains(identity) ||
              keptMediaIdentities.length < widget.maxReferenceImages) {
            keptMediaIdentities.add(identity);
            keepImages.add(i);
          }
        }
      } else if (widget.isVideoGenerationModel) {
        // Video generation accepts one media mode at a time. Existing image
        // references and draft images take precedence over video inputs.
        final hasImageInput =
            oldImages.isNotEmpty ||
            (generationReferenceChipsEnabled &&
                references.any(_referenceIsImage));
        final keepImageMode = hasImageInput && widget.maxReferenceImages > 0;
        if (keepImageMode) {
          if (generationReferenceChipsEnabled) {
            retainReferences(images: true, limit: widget.maxReferenceImages);
          }
          for (var i = 0; i < oldImages.length; i++) {
            final identity = 'image:$i';
            if (keptMediaIdentities.contains(identity) ||
                keptMediaIdentities.length < widget.maxReferenceImages) {
              keptMediaIdentities.add(identity);
              keepImages.add(i);
            }
          }
        } else if (widget.maxReferenceVideos > 0) {
          if (generationReferenceChipsEnabled) {
            retainReferences(images: false, limit: widget.maxReferenceVideos);
          }
          for (final index in videos) {
            final identity = 'document:$index';
            if (keptMediaIdentities.contains(identity) ||
                keptMediaIdentities.length < widget.maxReferenceVideos) {
              keptMediaIdentities.add(identity);
              keepDocs.add(index);
            }
          }
        }
      }

      final imageRemap = <int, int>{};
      final docRemap = <int, int>{};
      var nextImage = 0;
      for (final index in Iterable<int>.generate(oldImages.length)) {
        if (keepImages.contains(index)) imageRemap[index] = nextImage++;
      }
      var nextDoc = 0;
      for (final index in Iterable<int>.generate(oldDocs.length)) {
        if (keepDocs.contains(index)) docRemap[index] = nextDoc++;
      }

      final removedCount =
          oldImages.length -
          keepImages.length +
          oldDocs.length -
          keepDocs.length;
      final referencesNeedCleanup = references.any((reference) {
        if (generationMode) {
          if (!keepReferenceIdentities.contains(identityOf(reference))) {
            return true;
          }
        } else if (!_isDraftReferenceSupported(reference)) {
          return true;
        }
        final imageIndex = reference.draftImageIndex;
        if (imageIndex != null && imageRemap[imageIndex] != imageIndex) {
          return true;
        }
        final documentIndex = reference.draftDocumentIndex;
        if (documentIndex != null && docRemap[documentIndex] != documentIndex) {
          return true;
        }
        return false;
      });
      if (removedCount == 0 && !referencesNeedCleanup) return;
      var keptReferenceCount = 0;
      if (referencesNeedCleanup) {
        _transformComposerReferences((reference) {
          if (generationMode) {
            final identity = identityOf(reference);
            if (!keepReferenceIdentities.contains(identity)) return null;
          } else if (!_isDraftReferenceSupported(reference)) {
            return null;
          }
          final oldImageIndex = reference.draftImageIndex;
          if (oldImageIndex != null) {
            final newIndex = imageRemap[oldImageIndex];
            if (newIndex == null) return null;
            keptReferenceCount++;
            return _copyDraftReference(reference, draftImageIndex: newIndex);
          }
          final oldDocIndex = reference.draftDocumentIndex;
          if (oldDocIndex != null) {
            final newIndex = docRemap[oldDocIndex];
            if (newIndex == null) return null;
            keptReferenceCount++;
            return _copyDraftReference(reference, draftDocumentIndex: newIndex);
          }
          keptReferenceCount++;
          return reference;
        });
      } else {
        keptReferenceCount = references.length;
      }

      final removedReferenceCount = references.length - keptReferenceCount;
      if (removedCount == 0 && removedReferenceCount == 0) return;
      if (!mounted) return;
      if (removedCount > 0) {
        setState(() {
          _images
            ..clear()
            ..addAll([
              for (final i in Iterable<int>.generate(oldImages.length))
                if (keepImages.contains(i)) oldImages[i],
            ]);
          _docs
            ..clear()
            ..addAll([
              for (final i in Iterable<int>.generate(oldDocs.length))
                if (keepDocs.contains(i)) oldDocs[i],
            ]);
          if (!_hasAttachedVideo) _videoExtendMode = false;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            )!.chatInputBarUnsupportedDraftMediaRemoved,
          ),
        ),
      );
    } finally {
      _isCleaningDraftAttachments = false;
    }
  }

  ChatInputImageReference _copyDraftReference(
    ChatInputImageReference reference, {
    int? draftImageIndex,
    int? draftDocumentIndex,
  }) => ChatInputImageReference(
    token: reference.token,
    fileId: reference.fileId,
    draftImageIndex: draftImageIndex ?? reference.draftImageIndex,
    draftDocumentIndex: draftDocumentIndex ?? reference.draftDocumentIndex,
    label: reference.label,
    mimeType: reference.mimeType,
  );

  bool _referenceIsImage(ChatInputImageReference reference) =>
      reference.draftImageIndex != null ||
      (reference.mimeType?.startsWith('image/') ?? false);

  bool _referenceIsVideo(ChatInputImageReference reference) =>
      reference.mimeType?.startsWith('video/') ?? false;

  void _addImages(List<String> paths) {
    if ((!widget.supportsImageInput &&
            !_imageModeActive &&
            !_videoModeActive) ||
        paths.isEmpty) {
      return;
    }
    var acceptedPaths = paths;
    if (_imageModeActive || _videoModeActive) {
      final limit = widget.maxReferenceImages;
      final referencedHistoryImages =
          widget.referenceMode == AttachmentReferenceMode.disabled
          ? 0
          : _serializeComposer().references
                .map((item) => item.reference)
                .where(_referenceIsImage)
                .where((reference) => reference.draftImageIndex == null)
                .map((reference) => reference.fileId ?? reference.token)
                .toSet()
                .length;
      final remaining = math.max(
        0,
        limit - _images.length - referencedHistoryImages,
      );
      acceptedPaths = paths.take(remaining).toList(growable: false);
      if (acceptedPaths.length < paths.length && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.chatInputBarImageReferenceLimit(limit),
            ),
          ),
        );
      }
    }
    if (acceptedPaths.isEmpty) return;
    setState(() => _images.addAll(acceptedPaths));
    _syncReferencesFromController();
    unawaited(_maybeAutoRecommendVideoAspectRatio());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_removeUnsupportedDraftReferences());
    });
  }

  void _clearImages() {
    setState(() {
      _images.clear();
      _transformComposerReferences(
        (reference) =>
            reference.draftImageIndex != null ||
                reference.draftDocumentIndex != null
            ? null
            : reference,
      );
      _videoAspectRatioUserSet = false;
    });
  }

  void _addFiles(List<DocumentAttachment> docs) {
    if (docs.isEmpty) return;
    var acceptedDocs = docs;
    if (_videoModeActive) {
      final videos = docs
          .where((doc) => doc.mime.startsWith('video/'))
          .toList();
      final existingVideos = _docs
          .where((doc) => doc.mime.startsWith('video/'))
          .length;
      final referencedHistoryVideos =
          widget.referenceMode == AttachmentReferenceMode.disabled
          ? 0
          : _serializeComposer().references
                .map((item) => item.reference)
                .where(_referenceIsVideo)
                .where((reference) => reference.draftDocumentIndex == null)
                .map((reference) => reference.fileId ?? reference.token)
                .toSet()
                .length;
      final remaining = math.max(
        0,
        widget.maxReferenceVideos - existingVideos - referencedHistoryVideos,
      );
      final allowedVideos = videos.take(remaining).toSet();
      acceptedDocs = docs
          .where(
            (doc) =>
                !doc.mime.startsWith('video/') || allowedVideos.contains(doc),
          )
          .toList(growable: false);
      if (allowedVideos.length < videos.length && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.chatInputBarVideoReferenceLimit(widget.maxReferenceVideos),
            ),
          ),
        );
      }
    }
    if (acceptedDocs.isEmpty) return;
    setState(() => _docs.addAll(acceptedDocs));
    _syncReferencesFromController();
    unawaited(_maybeAutoRecommendVideoAspectRatio());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_removeUnsupportedDraftReferences());
    });
  }

  void _clearFiles() {
    setState(() {
      _docs.clear();
      _transformComposerReferences(
        (reference) => reference.draftDocumentIndex != null ? null : reference,
      );
      _videoExtendMode = false;
      _videoAspectRatioUserSet = false;
    });
  }

  void _restoreInput(ChatInputData input) {
    final references = <_SerializedComposerReference>[];
    var searchOffset = 0;
    for (final reference in input.imageReferences) {
      final start = input.text.indexOf(reference.token, searchOffset);
      if (start < 0) continue;
      references.add(
        _SerializedComposerReference(
          start: start,
          end: start + reference.token.length,
          reference: reference,
        ),
      );
      searchOffset = start + reference.token.length;
    }
    setState(() {
      _images
        ..clear()
        ..addAll(input.imagePaths);
      _docs
        ..clear()
        ..addAll(input.documents);
      _imageReferences
        ..clear()
        ..addAll(input.imageReferences);
      _rebuildComposerFromSerialized(
        _SerializedComposer(text: input.text, references: references),
      );
      if (!_hasAttachedVideo) _videoExtendMode = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_removeUnsupportedDraftReferences());
    });
  }

  ChatInputData _snapshotInput(String _) {
    final serialized = _serializeComposer();
    final segments = <ChatAttachmentSegment>[];
    // Rebuild the wire segments from the already-serialized chip ranges.
    // Calling getSelectionSpans() a second time here used to be lossy: the
    // editor could still render a chip, while its runtime span type was not
    // recognized by this generic type check, so the outgoing payload kept
    // only surrounding text and the backend quite correctly had no
    // attachment reference to resolve.
    var cursor = 0;
    for (final item in serialized.references) {
      if (item.start > cursor) {
        segments.add(
          ChatAttachmentSegment.text(
            serialized.text.substring(cursor, item.start),
          ),
        );
      }
      segments.add(ChatAttachmentSegment.attachment(item.reference));
      cursor = item.end;
    }
    if (cursor < serialized.text.length) {
      segments.add(
        ChatAttachmentSegment.text(serialized.text.substring(cursor)),
      );
    }
    while (segments.isNotEmpty && segments.first.type == 'text') {
      final text = segments.first.text!.trimLeft();
      if (text.isEmpty) {
        segments.removeAt(0);
      } else {
        segments[0] = ChatAttachmentSegment.text(text);
        break;
      }
    }
    while (segments.isNotEmpty && segments.last.type == 'text') {
      final text = segments.last.text!.trimRight();
      if (text.isEmpty) {
        segments.removeLast();
      } else {
        segments[segments.length - 1] = ChatAttachmentSegment.text(text);
        break;
      }
    }
    if (serialized.references.isEmpty) segments.clear();
    return ChatInputData(
      text: serialized.text.trim(),
      imagePaths: List<String>.of(_images),
      documents: List<DocumentAttachment>.of(_docs),
      imageReferences: serialized.references
          .map((item) => item.reference)
          .toList(growable: false),
      attachmentSegments: segments,
      allowImagesApiRouting: true,
      imageGenSize: _imageModeActive ? _imageGenSize : null,
      imageGenCount: _imageModeActive ? _imageGenCount : null,
      videoDuration: _videoModeActive ? _videoDuration : null,
      videoAspectRatio: _videoModeActive ? _videoAspectRatio : null,
      videoResolution: _videoModeActive ? _videoResolution : null,
      videoExtendMode: _videoModeActive
          ? (_videoExtendMode && _hasAttachedVideo)
          : null,
    );
  }

  void _clearDraft() {
    setState(() {
      _controller.clear();
      _images.clear();
      _docs.clear();
      _imageReferences.clear();
      _controller.removeAllChips();
      _referenceCandidatesByToken.clear();
      _videoAspectRatioUserSet = false;
    });
  }

  void _removeImageAt(int index) {
    setState(() {
      _images.removeAt(index);
      _transformComposerReferences((reference) {
        final draftIndex = reference.draftImageIndex;
        if (draftIndex == index) return null;
        if (draftIndex != null && draftIndex > index) {
          return ChatInputImageReference(
            token: reference.token,
            fileId: reference.fileId,
            draftImageIndex: draftIndex - 1,
            draftDocumentIndex: reference.draftDocumentIndex,
            label: reference.label,
            mimeType: reference.mimeType,
          );
        }
        return reference;
      });
    });
  }

  void _removeDocumentAt(int index) {
    setState(() {
      _docs.removeAt(index);
      _transformComposerReferences((reference) {
        final draftIndex = reference.draftDocumentIndex;
        if (draftIndex == index) return null;
        if (draftIndex != null && draftIndex > index) {
          return ChatInputImageReference(
            token: reference.token,
            fileId: reference.fileId,
            draftImageIndex: reference.draftImageIndex,
            draftDocumentIndex: draftIndex - 1,
            label: reference.label,
            mimeType: reference.mimeType,
          );
        }
        return reference;
      });
      if (!_hasAttachedVideo) _videoExtendMode = false;
    });
  }

  List<ChatImageReferenceCandidate> _referenceCandidates({
    List<ChatImageReferenceCandidate>? historyCandidates,
  }) {
    if (widget.referenceMode == AttachmentReferenceMode.disabled) {
      return const [];
    }
    final current = <ChatImageReferenceCandidate>[
      for (var i = 0; i < _images.length; i++)
        ChatImageReferenceCandidate(
          id: 'draft:$i',
          label: p.basename(_images[i]),
          fileName: p.basename(_images[i]),
          mimeType: 'image/*',
          localPath: _images[i],
          draftImageIndex: i,
        ),
      for (var i = 0; i < _docs.length; i++)
        ChatImageReferenceCandidate(
          id: 'draft-document:$i',
          label: _docs[i].fileName,
          fileName: _docs[i].fileName,
          mimeType: _docs[i].mime,
          localPath: _docs[i].path,
          draftDocumentIndex: i,
        ),
    ];
    final candidates =
        [...current, ...(historyCandidates ?? widget.imageReferenceCandidates)]
            .where((candidate) {
              switch (widget.referenceMode) {
                case AttachmentReferenceMode.disabled:
                  return false;
                case AttachmentReferenceMode.chat:
                  if (candidate.isVideo) return false;
                  return !candidate.isImage || widget.supportsImageInput;
                case AttachmentReferenceMode.imageGeneration:
                  return candidate.isImage && widget.maxReferenceImages > 0;
                case AttachmentReferenceMode.videoGeneration:
                  return (candidate.isImage && widget.maxReferenceImages > 0) ||
                      (candidate.isVideo && widget.maxReferenceVideos > 0);
              }
            })
            .toList(growable: false);
    final seenLabels = <String, int>{};
    return candidates
        .map((candidate) {
          final base = candidate.label.trim().isEmpty
              ? candidate.label
              : candidate.label.trim();
          final key = '${candidate.isImage ? 'image' : 'file'}:$base';
          final occurrence = (seenLabels[key] ?? 0) + 1;
          seenLabels[key] = occurrence;
          final label = occurrence == 1 ? base : '$base #$occurrence';
          if (label == candidate.label) return candidate;
          return ChatImageReferenceCandidate(
            id: candidate.id,
            label: label,
            fileId: candidate.fileId,
            localPath: candidate.localPath,
            previewSource: candidate.previewSource,
            draftImageIndex: candidate.draftImageIndex,
            draftDocumentIndex: candidate.draftDocumentIndex,
            fileName: candidate.fileName,
            mimeType: candidate.mimeType,
          );
        })
        .toList(growable: false);
  }

  Future<void> _openImageReferencePicker() async {
    if (_composerLocked ||
        widget.referenceMode == AttachmentReferenceMode.disabled) {
      return;
    }
    if (!mounted) return;
    final candidate = await showImageReferenceSheet(
      context,
      _referenceCandidates(),
      refreshCandidates: widget.onRefreshImageReferenceCandidates == null
          ? null
          : () async {
              final historyCandidates = await widget
                  .onRefreshImageReferenceCandidates!
                  .call();
              return _referenceCandidates(historyCandidates: historyCandidates);
            },
    );
    if (mounted && candidate != null) _insertImageReference(candidate);
  }

  void _insertImageReference(ChatImageReferenceCandidate candidate) {
    final l10n = AppLocalizations.of(context)!;
    final kind = candidate.isImage
        ? l10n.chatInputBarReferenceImageTag
        : l10n.chatInputBarReferenceFileTag;
    final label = candidate.label;
    final reference = ChatInputImageReference(
      token: '@$kind: $label',
      fileId: candidate.fileId,
      draftImageIndex: candidate.draftImageIndex,
      draftDocumentIndex: candidate.draftDocumentIndex,
      label: candidate.label,
      mimeType: candidate.mimeType,
    );
    final selection = _controller.selection.isValid
        ? _controller.selection
        : TextSelection.collapsed(offset: _controller.text.length);
    _controller.selection = selection;
    _controller.replaceSelectionWithSpans([
      shadcn.ChipSpan<ChatInputImageReference>(
        value: reference,
        child: const SizedBox.shrink(),
      ),
    ]);
    setState(() {
      _syncReferencesFromController();
    });
    unawaited(_removeUnsupportedDraftReferences());
    widget.focusNode?.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _setListenedFocusNode(widget.focusNode);
    final suppliedController = widget.controller;
    if (suppliedController is AttachmentChipEditingController) {
      _controller = suppliedController;
    } else {
      _controller = AttachmentChipEditingController(
        text: suppliedController?.text,
      );
      _legacyController = suppliedController;
      _ownsChipController = true;
      _legacyController?.addListener(_onLegacyControllerChanged);
    }
    _controller.candidateResolver = _referenceCandidateByToken;
    _syncReferencesFromController();
    _syncLegacyController();
    widget.mediaController?._bind(this);
    widget.mediaController?.pendingAttachmentCount.addListener(
      _onPendingAttachmentCountChanged,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_removeUnsupportedDraftReferences());
    });
  }

  void _onPendingAttachmentCountChanged() {
    if (mounted) setState(() {});
  }

  void _setListenedFocusNode(FocusNode? focusNode) {
    _listenedFocusNode?.removeListener(_onInputFocusChanged);
    _listenedFocusNode = focusNode;
    _inputFocused = focusNode?.hasFocus ?? false;
    _listenedFocusNode?.addListener(_onInputFocusChanged);
  }

  void _onInputFocusChanged() {
    final focused = _listenedFocusNode?.hasFocus ?? false;
    _scheduleInputFocusUpdate(focused);
  }

  void _scheduleInputFocusUpdate(bool focused) {
    _pendingFocusState = focused;
    if (_focusUpdateScheduled) return;
    _focusUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusUpdateScheduled = false;
      if (!mounted) return;
      _setInputFocused(_listenedFocusNode?.hasFocus ?? _pendingFocusState);
    });
  }

  void _setInputFocused(bool focused) {
    if (_inputFocused == focused || !mounted) return;
    setState(() => _inputFocused = focused);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app resumes from background, suppress context menu briefly to avoid flickering
    if (state == AppLifecycleState.resumed) {
      _suppressContextMenu = true;
      // Also unfocus to reset any stuck toolbar state
      widget.focusNode?.unfocus();
      // Re-enable context menu after a short delay
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _suppressContextMenu = false);
        }
      });
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // When going to background, hide any open toolbar
      _suppressContextMenu = true;
      widget.focusNode?.unfocus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _listenedFocusNode?.removeListener(_onInputFocusChanged);
    for (final timer in _repeatTimers.values) {
      try {
        timer?.cancel();
      } catch (_) {}
    }
    _repeatTimers.clear();
    widget.mediaController?.pendingAttachmentCount.removeListener(
      _onPendingAttachmentCountChanged,
    );
    widget.mediaController?._unbind(this);
    _legacyController?.removeListener(_onLegacyControllerChanged);
    if (_ownsChipController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _setListenedFocusNode(widget.focusNode);
    }
    if (oldWidget.referenceMode != widget.referenceMode ||
        oldWidget.maxReferenceImages != widget.maxReferenceImages ||
        oldWidget.maxReferenceVideos != widget.maxReferenceVideos ||
        oldWidget.supportsImageInput != widget.supportsImageInput ||
        oldWidget.isEmbeddingModel != widget.isEmbeddingModel ||
        oldWidget.isImageGenerationModel != widget.isImageGenerationModel ||
        oldWidget.isVideoGenerationModel != widget.isVideoGenerationModel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_removeUnsupportedDraftReferences());
      });
    }
  }

  String _hint(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return l10n.chatInputBarHint;
  }

  /// Returns the number of lines in the input text (minimum 1).
  int get _lineCount {
    final text = _controller.text;
    if (text.isEmpty) return 1;
    return text.split('\n').length;
  }

  /// Whether to show the expand/collapse button (when text has 3+ lines).
  bool get _showExpandButton => _lineCount >= 3;

  Future<void> _handleSend() async {
    if (_isSubmitting) return;
    _isSubmitting = true;
    try {
      await _removeUnsupportedDraftReferences();
      if (!mounted) return;
      final text = _controller.text.trim();
      if (text.isEmpty && _images.isEmpty && _docs.isEmpty) return;
      final result =
          await widget.onSend?.call(_snapshotInput(text)) ??
          ChatInputSubmissionResult.rejected;
      if (!mounted) return;
      if (result == ChatInputSubmissionResult.sent ||
          result == ChatInputSubmissionResult.queued) {
        _controller.clear();
        _images.clear();
        _docs.clear();
        _imageReferences.clear();
        _referenceCandidatesByToken.clear();
        _syncLegacyController();
        setState(() {});
        // Keep focus on desktop so user can continue typing
        try {
          if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
            widget.focusNode?.requestFocus();
          }
        } catch (_) {}
      }
    } finally {
      _isSubmitting = false;
    }
  }

  void _insertNewlineAtCursor() {
    final value = _controller.value;
    final selection = value.selection;
    final text = value.text;
    if (!selection.isValid) {
      _controller.text = '$text\n';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    } else {
      final start = selection.start;
      final end = selection.end;
      final newText = text.replaceRange(start, end, '\n');
      _controller.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + 1),
        composing: TextRange.empty,
      );
    }
    setState(() {});
    _ensureCaretVisible();
  }

  // Keep the caret visible after programmatic edits (e.g., Shift+Enter insert)
  void _ensureCaretVisible() {
    try {
      final selection = _controller.selection;
      if (!selection.isValid) return;
      final focusNode = widget.focusNode ?? Focus.maybeOf(context);
      final focusContext = focusNode?.context;
      if (focusContext == null) return;
      final editable = focusContext
          .findAncestorStateOfType<EditableTextState>();
      if (editable == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          editable.bringIntoView(selection.extent);
        } catch (_) {}
      });
    } catch (_) {}
  }

  // Instance method for contextMenuBuilder to avoid flickering caused by recreating
  // the callback on every build. See: https://github.com/flutter/flutter/issues/150551
  Widget _buildContextMenu(BuildContext context, EditableTextState state) {
    // Suppress context menu during app lifecycle transitions to avoid flickering
    if (_suppressContextMenu) {
      return const SizedBox.shrink();
    }
    if (Platform.isIOS) {
      final items = <ContextMenuButtonItem>[];
      try {
        final appL10n = AppLocalizations.of(context)!;
        final materialL10n = MaterialLocalizations.of(context);
        final value = _controller.value;
        final selection = value.selection;
        final hasSelection = selection.isValid && !selection.isCollapsed;
        final hasText = value.text.isNotEmpty;

        // Cut
        if (hasSelection) {
          items.add(
            ContextMenuButtonItem(
              onPressed: () async {
                try {
                  final start = selection.start;
                  final end = selection.end;
                  final text = _serializeSelection(selection);
                  await Clipboard.setData(ClipboardData(text: text));
                  final newText = value.text.replaceRange(start, end, '');
                  _controller.value = value.copyWith(
                    text: newText,
                    selection: TextSelection.collapsed(offset: start),
                  );
                } catch (_) {}
                state.hideToolbar();
              },
              label: materialL10n.cutButtonLabel,
            ),
          );
        }

        // Copy
        if (hasSelection) {
          items.add(
            ContextMenuButtonItem(
              onPressed: () async {
                try {
                  final text = _serializeSelection(selection);
                  await Clipboard.setData(ClipboardData(text: text));
                } catch (_) {}
                state.hideToolbar();
              },
              label: materialL10n.copyButtonLabel,
            ),
          );
        }

        // Paste (text or image via _handlePasteFromClipboard)
        items.add(
          ContextMenuButtonItem(
            onPressed: () {
              _handlePasteFromClipboard();
              state.hideToolbar();
            },
            label: materialL10n.pasteButtonLabel,
          ),
        );

        // Insert newline
        items.add(
          ContextMenuButtonItem(
            onPressed: () {
              _insertNewlineAtCursor();
              state.hideToolbar();
            },
            label: appL10n.chatInputBarInsertNewline,
          ),
        );

        // Select all
        if (hasText) {
          items.add(
            ContextMenuButtonItem(
              onPressed: () {
                try {
                  _controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: value.text.length,
                  );
                } catch (_) {}
                state.hideToolbar();
              },
              label: materialL10n.selectAllButtonLabel,
            ),
          );
        }
      } catch (_) {}
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: state.contextMenuAnchors,
        buttonItems: items,
      );
    }

    // Other platforms: keep default behavior.
    final items = <ContextMenuButtonItem>[...state.contextMenuButtonItems];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Enhance hardware keyboard behavior
    final w = MediaQuery.sizeOf(node.context!).width;
    final isTabletOrDesktop = w >= AppBreakpoints.tablet;
    final isIosTablet = Platform.isIOS && isTabletOrDesktop;

    final isDown = event is KeyDownEvent;
    final key = event.logicalKey;
    final isEnter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    final isArrow =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    final isPasteV = key == LogicalKeyboardKey.keyV;

    // Enter handling on tablet/desktop: configurable shortcut
    if (isEnter && isTabletOrDesktop) {
      if (!isDown) return KeyEventResult.handled; // ignore key up
      // Respect IME composition (e.g., Chinese Pinyin). If composing, let IME handle Enter.
      final composing = _controller.value.composing;
      final composingActive = composing.isValid && !composing.isCollapsed;
      if (composingActive) return KeyEventResult.ignored;
      final keys = HardwareKeyboard.instance.logicalKeysPressed;
      final shift =
          keys.contains(LogicalKeyboardKey.shiftLeft) ||
          keys.contains(LogicalKeyboardKey.shiftRight);
      final ctrl =
          keys.contains(LogicalKeyboardKey.controlLeft) ||
          keys.contains(LogicalKeyboardKey.controlRight);
      final meta =
          keys.contains(LogicalKeyboardKey.metaLeft) ||
          keys.contains(LogicalKeyboardKey.metaRight);
      final ctrlOrMeta = ctrl || meta;
      // Get send shortcut setting
      final sendShortcut = Provider.of<SettingsProvider>(
        node.context!,
        listen: false,
      ).desktopSendShortcut;
      if (sendShortcut == DesktopSendShortcut.ctrlEnter) {
        // Ctrl/Cmd+Enter to send, Enter to newline
        if (ctrlOrMeta) {
          unawaited(_handleSend());
        } else if (!shift) {
          _insertNewlineAtCursor();
        } else {
          // Shift+Enter also newline
          _insertNewlineAtCursor();
        }
      } else {
        // Enter to send, Shift+Enter or Ctrl/Cmd+Enter to newline (default)
        if (shift || ctrlOrMeta) {
          _insertNewlineAtCursor();
        } else {
          unawaited(_handleSend());
        }
      }
      return KeyEventResult.handled;
    }

    // Paste handling for images on iOS/macOS (tablet/desktop)
    if (isDown && isPasteV) {
      final keys = HardwareKeyboard.instance.logicalKeysPressed;
      final meta =
          keys.contains(LogicalKeyboardKey.metaLeft) ||
          keys.contains(LogicalKeyboardKey.metaRight);
      final ctrl =
          keys.contains(LogicalKeyboardKey.controlLeft) ||
          keys.contains(LogicalKeyboardKey.controlRight);
      if (meta || ctrl) {
        _handlePasteFromClipboard();
        return KeyEventResult.handled;
      }
    }

    // Arrow repeat fix only needed on iOS tablets
    if (!isIosTablet || !isArrow) return KeyEventResult.ignored;

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final shift =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final alt =
        keys.contains(LogicalKeyboardKey.altLeft) ||
        keys.contains(LogicalKeyboardKey.altRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);

    void moveOnce() {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _moveCaret(-1, extend: shift, byWord: alt);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _moveCaret(1, extend: shift, byWord: alt);
      }
    }

    if (event is KeyDownEvent) {
      // Initial move
      moveOnce();
      // Start repeat timer if not already
      if (!_repeatTimers.containsKey(key)) {
        Timer? periodic;
        final starter = Timer(_repeatInitialDelay, () {
          periodic = Timer.periodic(_repeatPeriod, (_) => moveOnce());
          _repeatTimers[key] = periodic!;
        });
        // Store starter temporarily; replace when periodic begins
        _repeatTimers[key] = starter;
      }
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      // Key up -> cancel repeat
      final t = _repeatTimers.remove(key);
      try {
        t?.cancel();
      } catch (_) {}
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  Future<void> _handlePasteFromClipboard() async {
    // 1) Prefer reading via super_clipboard for better Windows support
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final reader = await clipboard.read();

        // Helper: read bytes for a given file format from DataReader (ClipboardReader or item)
        Future<Uint8List?> readFileBytes(
          DataReader dataReader,
          FileFormat format,
        ) async {
          try {
            final completer = Completer<Uint8List?>();
            final progress = dataReader.getFile(
              format,
              (file) async {
                try {
                  final bytes = await file.readAll();
                  if (!completer.isCompleted) completer.complete(bytes);
                } catch (e) {
                  if (!completer.isCompleted) completer.completeError(e);
                }
              },
              onError: (e) {
                if (!completer.isCompleted) completer.completeError(e);
              },
            );
            if (progress == null) {
              if (!completer.isCompleted) completer.complete(null);
            }
            return await completer.future;
          } catch (_) {
            return null;
          }
        }

        // Helper: persist bytes as a file under upload directory
        Future<String?> saveImageBytes(String format, Uint8List bytes) async {
          try {
            final dir = await AppDirectories.getUploadDirectory();
            if (!await dir.exists()) {
              await dir.create(recursive: true);
            }
            final ts = DateTime.now().millisecondsSinceEpoch;
            final ext = format.toLowerCase();
            final fileExt = ext == 'jpeg' ? 'jpg' : ext;
            String name = 'paste_$ts.$fileExt';
            String destPath = p.join(dir.path, name);
            if (await File(destPath).exists()) {
              name =
                  'paste_${ts}_${DateTime.now().microsecondsSinceEpoch}.$fileExt';
              destPath = p.join(dir.path, name);
            }
            await File(destPath).writeAsBytes(bytes, flush: true);
            return destPath;
          } catch (_) {
            return null;
          }
        }

        // Try aggregated formats in priority: png > jpeg > gif > webp
        Uint8List? bytes;
        String? fmt;
        if (reader.canProvide(Formats.png)) {
          bytes = await readFileBytes(reader, Formats.png);
          fmt = 'png';
        }
        bytes ??= reader.canProvide(Formats.jpeg)
            ? await readFileBytes(reader, Formats.jpeg)
            : null;
        fmt = (bytes != null && fmt == null) ? 'jpeg' : fmt;
        if (bytes == null && reader.canProvide(Formats.gif)) {
          bytes = await readFileBytes(reader, Formats.gif);
          fmt = 'gif';
        }
        if (bytes == null && reader.canProvide(Formats.webp)) {
          bytes = await readFileBytes(reader, Formats.webp);
          fmt = 'webp';
        }

        if (bytes == null) {
          // Try per-item formats
          for (final item in reader.items) {
            if (bytes == null && item.canProvide(Formats.png)) {
              bytes = await readFileBytes(item, Formats.png);
              fmt = 'png';
            }
            if (bytes == null && item.canProvide(Formats.jpeg)) {
              bytes = await readFileBytes(item, Formats.jpeg);
              fmt = 'jpeg';
            }
            if (bytes == null && item.canProvide(Formats.gif)) {
              bytes = await readFileBytes(item, Formats.gif);
              fmt = 'gif';
            }
            if (bytes == null && item.canProvide(Formats.webp)) {
              bytes = await readFileBytes(item, Formats.webp);
              fmt = 'webp';
            }
            if (bytes != null) break;
          }
        }

        if (bytes != null && bytes.isNotEmpty && fmt != null) {
          final savedPath = await saveImageBytes(fmt, bytes);
          if (savedPath != null) {
            _addImages([savedPath]);
            return;
          }
        }

        // If clipboard has plain text via super_clipboard, paste it
        if (reader.canProvide(Formats.plainText)) {
          try {
            final String? text = await reader.readValue(Formats.plainText);
            if (text != null && text.isNotEmpty) {
              final value = _controller.value;
              final sel = value.selection;
              if (!sel.isValid) {
                _controller.text = value.text + text;
                _controller.selection = TextSelection.collapsed(
                  offset: _controller.text.length,
                );
              } else {
                final start = sel.start;
                final end = sel.end;
                final newText = value.text.replaceRange(start, end, text);
                _controller.value = value.copyWith(
                  text: newText,
                  selection: TextSelection.collapsed(
                    offset: start + text.length,
                  ),
                  composing: TextRange.empty,
                );
              }
              setState(() {});
              return;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 2) Fallback: legacy platform channel image handling
    final imageTempPaths = await ClipboardImages.getImagePaths();
    if (imageTempPaths.isNotEmpty) {
      final persisted = await _persistClipboardImages(imageTempPaths);
      if (persisted.isNotEmpty) {
        _addImages(persisted);
      }
      return;
    }

    // 3) Try files via platform channel on desktop (Finder/Explorer copies)
    bool handledFiles = false;
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final filePaths = await ClipboardImages.getFilePaths();
        if (filePaths.isNotEmpty) {
          final saved = await _copyFilesToUpload(filePaths);
          if (saved.images.isNotEmpty) _addImages(saved.images);
          if (saved.docs.isNotEmpty) _addFiles(saved.docs);
          handledFiles = saved.images.isNotEmpty || saved.docs.isNotEmpty;
        }
      }
    } catch (_) {}
    if (handledFiles) return;

    // 4) Last resort: paste text via Flutter Clipboard API
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.isEmpty) return;
      final value = _controller.value;
      final sel = value.selection;
      if (!sel.isValid) {
        _controller.text = value.text + text;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      } else {
        final start = sel.start;
        final end = sel.end;
        final newText = value.text.replaceRange(start, end, text);
        _controller.value = value.copyWith(
          text: newText,
          selection: TextSelection.collapsed(offset: start + text.length),
          composing: TextRange.empty,
        );
      }
      setState(() {});
    } catch (_) {}
  }

  // Copy arbitrary files to upload directory (without deleting the source),
  // split into images and document attachments.
  Future<({List<String> images, List<DocumentAttachment> docs})>
  _copyFilesToUpload(List<String> srcPaths) async {
    final images = <String>[];
    final docs = <DocumentAttachment>[];
    try {
      final dir = await AppDirectories.getUploadDirectory();
      for (final raw in srcPaths) {
        if (!mounted) {
          return (images: images, docs: docs);
        }
        final src = raw.startsWith('file://') ? raw.substring(7) : raw;
        final savedPath = await FileImportHelper.copyXFile(
          XFile(src),
          dir,
          context,
        );
        if (savedPath != null) {
          final savedName = p.basename(savedPath);
          if (_isImageExtension(savedName)) {
            images.add(savedPath);
          } else {
            final mime = _inferMimeByExtension(savedName);
            docs.add(
              DocumentAttachment(
                path: savedPath,
                fileName: savedName,
                mime: mime,
              ),
            );
          }
        }
      }
    } catch (_) {}
    return (images: images, docs: docs);
  }

  List<FrostedPopupMenuItem> _buildComposerActionItems(
    BuildContext context, {
    bool listen = true,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final settings = listen
        ? context.watch<SettingsProvider>()
        : context.read<SettingsProvider>();
    final assistantProvider = listen
        ? context.watch<AssistantProvider>()
        : context.read<AssistantProvider>();
    final assistant = assistantProvider.currentAssistant;
    final currentModelIds = _currentModelIds(context, listen: listen);
    final providerKey = currentModelIds.providerKey;
    final modelId = currentModelIds.modelId;
    final config = providerKey == null
        ? null
        : settings.getProviderConfig(providerKey);
    final builtInSearchActive = BuiltInToolsHelper.getActiveTools(
      cfg: config,
      modelId: modelId,
    ).searchActive;
    final supportsBuiltInSearch =
        BuiltInToolsHelper.supportsBuiltInSearchForModel(
          cfg: config,
          modelId: modelId,
        );
    final supportsClaudeDynamicWebSearch =
        BuiltInToolsHelper.supportsClaudeDynamicWebSearchForModel(
          cfg: config,
          modelId: modelId,
        );
    final claudeDynamicSearchActive =
        BuiltInToolsHelper.isClaudeDynamicWebSearchEnabled(
          cfg: config,
          modelId: modelId,
        );
    final serverSearchActive =
        assistant?.cloudHosted == true &&
        assistant?.searchProviderMode != 'client';
    final searchServices = settings.searchServices;
    final selectedSearchService = settings.searchServiceSelected;
    final searchEnabled =
        assistantProvider.currentSearchEnabled || builtInSearchActive;

    FrostedPopupMenuItem? actionItem({
      required IconData icon,
      required String label,
      VoidCallback? onPressed,
      VoidCallback? onLongPress,
      bool isOption = false,
      bool selected = false,
    }) {
      if (onPressed == null) return null;
      return FrostedPopupMenuItem(
        icon: icon,
        label: label,
        onPressed: onPressed,
        onLongPress: onLongPress,
        isOption: isOption,
        selected: selected,
      );
    }

    final attachments = <FrostedPopupMenuItem>[
      if (actionItem(
            icon: Lucide.Camera,
            label: l10n.bottomToolsSheetCamera,
            onPressed: widget.onPickCamera,
          )
          case final item?)
        item,
    ];
    final photoPicker = _videoModeActive
        ? widget.onPickPhotosOrVideo ?? widget.onPickPhotos
        : widget.onPickPhotos;
    if (photoPicker != null) {
      attachments.add(
        FrostedPopupMenuItem(
          icon: Lucide.Image,
          label: _videoModeActive
              ? l10n.chatInputBarPickMedia
              : l10n.bottomToolsSheetPhotos,
          onPressed: photoPicker,
        ),
      );
    }
    if (widget.onUploadFiles != null) {
      attachments.add(
        FrostedPopupMenuItem(
          icon: Lucide.Paperclip,
          label: l10n.bottomToolsSheetUpload,
          onPressed: widget.onUploadFiles,
        ),
      );
    }

    final contextItems = <FrostedPopupMenuItem>[
      if (widget.onOpenWorldBook != null)
        FrostedPopupMenuItem(
          icon: Lucide.BookOpen,
          label: l10n.worldBookTitle,
          onPressed: widget.onOpenWorldBook!,
        ),
      if (widget.onCompressContext != null)
        FrostedPopupMenuItem(
          icon: Lucide.Boxes,
          label: l10n.compressContext,
          onPressed: widget.onCompressContext!,
        ),
      if (widget.onClearContext != null)
        FrostedPopupMenuItem(
          icon: Lucide.Eraser,
          label: l10n.bottomToolsSheetClearContext,
          destructive: true,
          onPressed: widget.onClearContext!,
        ),
    ];
    final quickPhraseItems = <FrostedPopupMenuItem>[];
    void appendQuickPhrases(
      List<QuickPhrase> phrases, {
      required bool dividerAfter,
    }) {
      for (var index = 0; index < phrases.length; index++) {
        final phrase = phrases[index];
        final description = phrase.content
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        quickPhraseItems.add(
          FrostedPopupMenuItem(
            icon: phrase.isGlobal ? Lucide.Zap : Lucide.botMessageSquare,
            label: phrase.title.trim().isEmpty
                ? l10n.quickPhraseTitleLabel
                : phrase.title.trim(),
            description: description.isEmpty ? null : description,
            onPressed: () => widget.onSelectQuickPhrase!(phrase),
            dividerAfter: dividerAfter && index == phrases.length - 1,
            compact: true,
          ),
        );
      }
    }

    final globalQuickPhrases = widget.quickPhrases
        .where((phrase) => phrase.isGlobal)
        .toList(growable: false);
    final assistantQuickPhrases = widget.quickPhrases
        .where((phrase) => !phrase.isGlobal)
        .toList(growable: false);
    appendQuickPhrases(
      globalQuickPhrases,
      dividerAfter: assistantQuickPhrases.isNotEmpty,
    );
    appendQuickPhrases(assistantQuickPhrases, dividerAfter: false);

    final instructionInjections =
        assistant?.instructionInjections ?? const <InstructionInjection>[];
    final activeInjectionIds =
        (widget.activeInstructionInjectionIds ??
                assistant?.activeInstructionInjectionIds ??
                const <String>[])
            .toSet();
    final activeInstructionInjectionCount = instructionInjections
        .where((injection) => activeInjectionIds.contains(injection.id))
        .length;
    final groupedInjections = <String, List<InstructionInjection>>{};
    for (final injection in instructionInjections) {
      (groupedInjections[injection.group.trim()] ??= <InstructionInjection>[])
          .add(injection);
    }
    final injectionGroupNames = groupedInjections.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty && b.isNotEmpty) return -1;
        if (a.isNotEmpty && b.isEmpty) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final instructionInjectionItems = <FrostedPopupMenuItem>[];
    if (instructionInjections.isEmpty) {
      instructionInjectionItems.add(
        FrostedPopupMenuItem.info(label: l10n.instructionInjectionEmptyMessage),
      );
    } else {
      for (
        var groupIndex = 0;
        groupIndex < injectionGroupNames.length;
        groupIndex++
      ) {
        final groupName = injectionGroupNames[groupIndex];
        final groupItems = groupedInjections[groupName]!;
        instructionInjectionItems.add(
          FrostedPopupMenuItem.info(
            label: groupName.isEmpty
                ? l10n.instructionInjectionUngroupedGroup
                : groupName,
            emphasized: true,
          ),
        );
        for (var itemIndex = 0; itemIndex < groupItems.length; itemIndex++) {
          final injection = groupItems[itemIndex];
          final title = injection.title.trim().isEmpty
              ? l10n.instructionInjectionDefaultTitle
              : injection.title.trim();
          final description = injection.prompt
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          instructionInjectionItems.add(
            FrostedPopupMenuItem(
              icon: null,
              label: title,
              description: description.isEmpty ? null : description,
              onPressedAsync: () => widget.onSetInstructionInjectionActive!(
                injection.id,
                !activeInjectionIds.contains(injection.id),
              ),
              isOption: true,
              selected: activeInjectionIds.contains(injection.id),
              dismissOnSelect: false,
              compact: true,
              dividerAfter:
                  groupIndex < injectionGroupNames.length - 1 &&
                  itemIndex == groupItems.length - 1,
            ),
          );
        }
      }
    }
    final searchItems = <FrostedPopupMenuItem>[
      if (widget.onSetSearchEnabled != null)
        FrostedPopupMenuItem(
          icon: null,
          label: l10n.searchSettingsSheetEnableLabel,
          onPressedAsync: () => widget.onSetSearchEnabled!(!searchEnabled),
          dividerAfter: true,
          isOption: true,
          selected: searchEnabled,
          dismissOnSelect: false,
        ),
      if (searchEnabled) ...[
        if (supportsBuiltInSearch && widget.onSelectBuiltInSearch != null)
          FrostedPopupMenuItem(
            icon: Lucide.Search,
            label: l10n.searchSettingsSheetBuiltinSearchTitle,
            onPressedAsync: () => widget.onSelectBuiltInSearch!(false),
            isOption: true,
            selected: builtInSearchActive && !claudeDynamicSearchActive,
            dismissOnSelect: false,
          ),
        if (supportsClaudeDynamicWebSearch &&
            widget.onSelectBuiltInSearch != null)
          FrostedPopupMenuItem(
            icon: Lucide.Search,
            label: l10n.searchSettingsSheetClaudeDynamicSearchTitle,
            onPressedAsync: () => widget.onSelectBuiltInSearch!(true),
            isOption: true,
            selected: builtInSearchActive && claudeDynamicSearchActive,
            dismissOnSelect: false,
          ),
        if (assistant?.cloudHosted == true &&
            widget.onSelectSearchService != null)
          FrostedPopupMenuItem(
            icon: Lucide.Network,
            label: l10n.searchServiceNameServerSearch,
            onPressedAsync: widget.onSelectSearchService == null
                ? null
                : () => widget.onSelectSearchService!(null),
            isOption: true,
            selected:
                assistantProvider.currentSearchEnabled &&
                !builtInSearchActive &&
                serverSearchActive,
            dividerAfter: searchServices.isEmpty,
            dismissOnSelect: false,
          ),
        for (
          var index = 0;
          index < searchServices.length && widget.onSelectSearchService != null;
          index++
        )
          FrostedPopupMenuItem(
            icon: Lucide.Search,
            label: SearchService.getService(searchServices[index]).name,
            onPressedAsync: widget.onSelectSearchService == null
                ? null
                : () => widget.onSelectSearchService!(index),
            isOption: true,
            selected:
                assistantProvider.currentSearchEnabled &&
                !builtInSearchActive &&
                !serverSearchActive &&
                index == selectedSearchService,
            dividerAfter:
                index == searchServices.length - 1 &&
                widget.onOpenSearchServices != null,
            dismissOnSelect: false,
          ),
        if (searchServices.isEmpty &&
            assistant?.cloudHosted != true &&
            widget.onSelectSearchService != null &&
            !(supportsBuiltInSearch && widget.onSelectBuiltInSearch != null))
          FrostedPopupMenuItem.info(
            label: l10n.searchSettingsSheetNoServicesMessage,
          ),
      ],
      if (widget.onOpenSearchServices != null)
        FrostedPopupMenuItem(
          icon: Lucide.Settings,
          label: l10n.searchSettingsSheetOpenSearchServicesTooltip,
          onPressed: widget.onOpenSearchServices!,
        ),
    ];
    final mainItems = <FrostedPopupMenuItem>[
      if (widget.onSetSearchEnabled != null ||
          widget.onSelectBuiltInSearch != null ||
          widget.onSelectSearchService != null)
        FrostedPopupMenuItem(
          icon: Lucide.Globe,
          label: l10n.chatInputBarOnlineSearchTooltip,
          trailingLabel: searchEnabled
              ? l10n.searchSettingsSheetEnableLabel
              : l10n.reasoningBudgetSheetOff,
          children: searchItems,
        ),
      if (quickPhraseItems.isNotEmpty && widget.onSelectQuickPhrase != null)
        FrostedPopupMenuItem(
          icon: Lucide.Zap,
          label: l10n.chatInputBarQuickPhraseTooltip,
          children: quickPhraseItems,
        ),
      if (widget.onSetInstructionInjectionActive != null)
        FrostedPopupMenuItem(
          icon: Lucide.Layers,
          label: l10n.instructionInjectionTitle,
          trailingLabel: activeInstructionInjectionCount > 0
              ? l10n.instructionInjectionEnabledCount(
                  activeInstructionInjectionCount,
                )
              : null,
          children: instructionInjectionItems,
        ),
      if (contextItems.isNotEmpty)
        FrostedPopupMenuItem(
          icon: Lucide.Eraser,
          label: l10n.contextManagement,
          children: contextItems,
        ),
    ];
    final ocrItem = widget.showOcrButton
        ? actionItem(
            icon: Lucide.Eye,
            label: l10n.chatInputBarOcrTooltip,
            onPressed: widget.onToggleOcr,
          )
        : null;

    final items = <FrostedPopupMenuItem>[];
    void appendGroup(
      List<FrostedPopupMenuItem> group, {
      required bool dividerAfter,
    }) {
      for (var index = 0; index < group.length; index++) {
        final item = group[index];
        items.add(
          FrostedPopupMenuItem(
            icon: item.icon!,
            label: item.label,
            onPressed: item.onPressed,
            onPressedAsync: item.onPressedAsync,
            onLongPress: item.onLongPress,
            children: item.children,
            description: item.description,
            trailingLabel: item.trailingLabel,
            destructive: item.destructive,
            dividerAfter: dividerAfter && index == group.length - 1,
            isOption: item.isOption,
            selected: item.selected,
            dismissOnSelect: item.dismissOnSelect,
          ),
        );
      }
    }

    appendGroup(
      attachments,
      dividerAfter: mainItems.isNotEmpty || ocrItem != null,
    );
    appendGroup(mainItems, dividerAfter: ocrItem != null);
    if (ocrItem != null) items.add(ocrItem);
    return items;
  }

  Widget _buildComposerAddButton(
    BuildContext context,
    List<FrostedPopupMenuItem> menuItems,
    GlobalKey anchorKey,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      key: anchorKey,
      child: _CompactIconButton(
        tooltip: l10n.chatInputBarMoreTooltip,
        icon: Lucide.Plus,
        onTap: _composerLocked || menuItems.isEmpty
            ? null
            : () {
                final anchorBox =
                    anchorKey.currentContext?.findRenderObject() as RenderBox?;
                if (anchorBox == null || !anchorBox.hasSize) return;
                final topLeft = anchorBox.localToGlobal(Offset.zero);
                unawaited(
                  showFrostedPopupMenuAt(
                    context,
                    globalAnchorRect: topLeft & anchorBox.size,
                    items: menuItems,
                    itemsBuilder: () =>
                        _buildComposerActionItems(context, listen: false),
                  ),
                );
              },
      ),
    );
  }

  Widget _buildImageReferenceButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _CompactIconButton(
      tooltip: l10n.chatInputBarReferenceAttachmentTooltip,
      icon: Lucide.AtSign,
      onTap: _composerLocked ? null : _openImageReferencePicker,
    );
  }

  List<FrostedPopupMenuItem> _buildGenerationOptionsMenuItems(
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context)!;
    if (_imageModeActive) {
      return [
        FrostedPopupMenuItem(
          icon: Lucide.Image,
          label: l10n.chatInputBarImageGenSizeLabel,
          children: [
            for (final size in _imageGenSizeOptions)
              FrostedPopupMenuItem(
                icon: Lucide.Image,
                label: size == _imageGenSizeAuto
                    ? l10n.chatInputBarImageGenSizeAuto
                    : size,
                onPressed: () => setState(() => _imageGenSize = size),
                isOption: true,
                selected: size == _imageGenSize,
              ),
          ],
        ),
        FrostedPopupMenuItem.custom(
          label: l10n.chatInputBarImageGenCountLabel,
          height: 48,
          content: _PopupMenuStepper(
            label: l10n.chatInputBarImageGenCountLabel,
            values: const [1, 2, 3, 4],
            value: _imageGenCount,
            onChanged: _composerLocked
                ? null
                : (value) => setState(() => _imageGenCount = value),
          ),
        ),
      ];
    }
    if (_videoModeActive) {
      return [
        FrostedPopupMenuItem(
          icon: Lucide.Timer,
          label: l10n.chatInputBarVideoGenDurationLabel,
          children: [
            for (final duration in _videoDurationOptions)
              FrostedPopupMenuItem(
                icon: Lucide.Timer,
                label: '${duration}s',
                onPressed: () => setState(() => _videoDuration = duration),
                isOption: true,
                selected: duration == _videoDuration,
              ),
          ],
        ),
        FrostedPopupMenuItem(
          icon: Lucide.Crop,
          label: l10n.chatInputBarVideoGenAspectRatioLabel,
          children: [
            for (final ratio in _videoAspectRatioOptions)
              FrostedPopupMenuItem(
                icon: Lucide.Crop,
                label: ratio,
                onPressed: () => setState(() {
                  _videoAspectRatio = ratio;
                  _videoAspectRatioUserSet = true;
                }),
                isOption: true,
                selected: ratio == _videoAspectRatio,
              ),
          ],
        ),
        FrostedPopupMenuItem(
          icon: Lucide.Layers,
          label: l10n.chatInputBarVideoGenResolutionLabel,
          children: [
            for (final resolution in _videoResolutionOptions)
              FrostedPopupMenuItem(
                icon: Lucide.Layers,
                label: resolution,
                onPressed: () => setState(() => _videoResolution = resolution),
                isOption: true,
                selected: resolution == _videoResolution,
              ),
          ],
        ),
        FrostedPopupMenuItem.custom(
          label: l10n.chatInputBarVideoExtendModeLabel,
          height: 72,
          content: _PopupMenuSwitch(
            label: l10n.chatInputBarVideoExtendModeLabel,
            description: l10n.chatInputBarVideoExtendModeHint,
            value: _videoExtendMode && _hasAttachedVideo,
            onChanged: _composerLocked || !_hasAttachedVideo
                ? null
                : (value) => setState(() => _videoExtendMode = value),
          ),
        ),
      ];
    }
    return const [];
  }

  Widget _buildGenerationOptionsButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = _imageModeActive
        ? l10n.chatInputBarImageMode
        : l10n.chatInputBarVideoMode;
    return Container(
      key: _generationOptionsAnchorKey,
      child: _CompactIconButton(
        tooltip: title,
        icon: Lucide.Brush,
        onTap: _composerLocked
            ? null
            : () {
                final anchorBox =
                    _generationOptionsAnchorKey.currentContext
                            ?.findRenderObject()
                        as RenderBox?;
                if (anchorBox == null || !anchorBox.hasSize) return;
                final topLeft = anchorBox.localToGlobal(Offset.zero);
                unawaited(
                  showFrostedPopupMenuAt(
                    context,
                    globalAnchorRect: topLeft & anchorBox.size,
                    title: title,
                    items: _buildGenerationOptionsMenuItems(context),
                  ),
                );
              },
      ),
    );
  }

  String _inferMimeByExtension(String name) {
    final mediaMime = inferMediaMimeFromSource(name);
    if (mediaMime.isNotEmpty) return mediaMime;
    final lower = name.toLowerCase();
    // Documents / text
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.js')) return 'application/javascript';
    if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.markdown') ||
        lower.endsWith('.mdx')) {
      return 'text/plain';
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.xml')) return 'application/xml';
    if (lower.endsWith('.yml') || lower.endsWith('.yaml')) {
      return 'application/x-yaml';
    }
    if (lower.endsWith('.py')) return 'text/x-python';
    if (lower.endsWith('.java')) return 'text/x-java-source';
    if (lower.endsWith('.kt') || lower.endsWith('.kts')) return 'text/x-kotlin';
    if (lower.endsWith('.dart')) return 'text/x-dart';
    if (lower.endsWith('.ts')) return 'text/typescript';
    if (lower.endsWith('.tsx')) return 'text/tsx';
    return 'application/octet-stream';
  }

  bool _isImageExtension(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  Future<List<String>> _persistClipboardImages(List<String> srcPaths) async {
    try {
      final dir = await AppDirectories.getUploadDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final out = <String>[];
      int i = 0;
      for (var raw in srcPaths) {
        try {
          // Normalize path (strip file:// if present)
          final src = raw.startsWith('file://') ? raw.substring(7) : raw;
          // If already under upload directory, just keep it
          if (src.contains('/upload/') || src.contains('\\upload\\')) {
            out.add(src);
            continue;
          }
          final ext = p.extension(src).isNotEmpty ? p.extension(src) : '.png';
          final name =
              'paste_${DateTime.now().millisecondsSinceEpoch}_${i++}$ext';
          final destPath = p.join(dir.path, name);
          final from = File(src);
          if (await from.exists()) {
            await File(destPath).writeAsBytes(await from.readAsBytes());
            // Best-effort cleanup of the temporary source
            try {
              await from.delete();
            } catch (_) {}
            out.add(destPath);
          }
        } catch (_) {
          // skip single file errors
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  void _moveCaret(int dir, {bool extend = false, bool byWord = false}) {
    final text = _controller.text;
    if (text.isEmpty) return;
    TextSelection sel = _controller.selection;
    if (!sel.isValid) {
      final off = dir < 0 ? text.length : 0;
      _controller.selection = TextSelection.collapsed(offset: off);
      return;
    }

    int nextOffset(int from, int direction) {
      if (!byWord) return (from + direction).clamp(0, text.length);
      // Move by simple word boundary: skip whitespace; then skip non-whitespace
      int i = from;
      if (direction < 0) {
        // Move left
        while (i > 0 && text[i - 1].trim().isEmpty) {
          i--;
        }
        while (i > 0 && text[i - 1].trim().isNotEmpty) {
          i--;
        }
      } else {
        // Move right
        while (i < text.length && text[i].trim().isEmpty) {
          i++;
        }
        while (i < text.length && text[i].trim().isNotEmpty) {
          i++;
        }
      }
      return i.clamp(0, text.length);
    }

    if (extend) {
      final newExtent = nextOffset(sel.extentOffset, dir);
      _controller.selection = sel.copyWith(extentOffset: newExtent);
    } else {
      final base = dir < 0 ? sel.start : sel.end;
      final collapsed = nextOffset(base, dir);
      _controller.selection = TextSelection.collapsed(offset: collapsed);
    }
    setState(() {});
  }

  /// Shared 64x64 thumbnail chrome (rounded border + top-right remove
  /// button) for both an image draft (`_images`) and a video draft (a
  /// `_docs` row whose `mime` starts with `video/`) — the two need to look
  /// the same (both are "an image the model will see/edit"-shaped things,
  /// image-to-video reference frame vs. an image-to-generate-from), unlike
  /// a genuine document attachment (PDF/etc, kept as the separate
  /// filename-chip row below).
  Widget _mediaThumbnail({
    required Widget content,
    required VoidCallback onRemove,
    required bool isDark,
    required Color previewBorder,
    required Key removeKey,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: previewBorder, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(width: 64, height: 64, child: content),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: IosCardPress(
            key: removeKey,
            haptics: false,
            baseColor: isDark
                ? Colors.black.withValues(alpha: 0.50)
                : Colors.black.withValues(alpha: 0.46),
            pressedScale: 0.94,
            borderRadius: BorderRadius.circular(_imageRemoveButtonSize / 2),
            padding: EdgeInsets.zero,
            duration: const Duration(milliseconds: 140),
            onTap: onRemove,
            child: const SizedBox(
              width: _imageRemoveButtonSize,
              height: _imageRemoveButtonSize,
              child: Icon(Icons.close, size: 11, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  // [kelivo-hosted] Placeholder tile for a hosted attachment still being
  // re-downloaded for the inline editor (`ChatInputBarController.
  // pendingAttachmentCount`) — same size/shape as a real thumbnail
  // (`_mediaThumbnail`) but no remove button, since there's nothing to
  // remove yet.
  Widget _loadingAttachmentPlaceholder({
    required bool isDark,
    required Color previewFill,
    required Color previewBorder,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: previewBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 64,
          height: 64,
          child: ColoredBox(
            color: previewFill,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark
                        ? Colors.white.withValues(alpha: 0.55)
                        : Colors.black.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoImageIgnoredWarning(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    const warningColor = Color(0xFFFF9500);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.xxs,
      ),
      child: Row(
        children: [
          const Icon(Lucide.CircleAlert, size: 14, color: warningColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.chatInputBarVideoImageIgnoredWarning,
              style: theme.textTheme.labelSmall?.copyWith(color: warningColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineAttachmentPreviews(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final previewFill = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : theme.colorScheme.onSurface.withValues(alpha: 0.045);
    final previewBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : theme.colorScheme.outline.withValues(alpha: 0.13);

    // Video drafts render as a thumbnail alongside images (both above), not
    // as a filename chip (below, reserved for genuine documents) — see
    // `_mediaThumbnail`'s docstring.
    final docEntries = _docs.asMap().entries.toList();
    final videoDocs = docEntries
        .where((e) => e.value.mime.startsWith('video/'))
        .toList();
    final fileDocs = docEntries
        .where((e) => !e.value.mime.startsWith('video/'))
        .toList();
    // [kelivo-hosted] Extra trailing slots for hosted attachments still
    // being re-downloaded for the inline editor (`ChatInputBarController.
    // pendingAttachmentCount`) — rendered as loading placeholders so an
    // edit that hasn't finished restoring its attachments yet doesn't read
    // as "this message has no attachments".
    final pendingAttachmentCount =
        widget.mediaController?.pendingAttachmentCount.value ?? 0;
    final realMediaCount = _images.length + videoDocs.length;
    final mediaCount = realMediaCount + pendingAttachmentCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xxs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mediaCount > 0)
            SizedBox(
              key: const ValueKey('chat-input-image-previews'),
              height: _imagePreviewHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: mediaCount,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  if (idx >= realMediaCount) {
                    return _loadingAttachmentPlaceholder(
                      isDark: isDark,
                      previewFill: previewFill,
                      previewBorder: previewBorder,
                    );
                  }
                  if (idx < _images.length) {
                    final path = _images[idx];
                    return _mediaThumbnail(
                      isDark: isDark,
                      previewBorder: previewBorder,
                      removeKey: ValueKey('chat-input-image-remove:$idx'),
                      onRemove: () => _removeImageAt(idx),
                      content: Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: previewFill,
                          child: Icon(
                            Icons.broken_image,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  final docEntry = videoDocs[idx - _images.length];
                  return _mediaThumbnail(
                    isDark: isDark,
                    previewBorder: previewBorder,
                    removeKey: ValueKey(
                      'chat-input-document-remove:${docEntry.key}',
                    ),
                    onRemove: () => _removeDocumentAt(docEntry.key),
                    content: LocalVideoThumbnail(
                      path: docEntry.value.path,
                      errorFill: previewFill,
                    ),
                  );
                },
              ),
            ),
          if (mediaCount > 0 && fileDocs.isNotEmpty)
            const SizedBox(height: AppSpacing.xs),
          if (fileDocs.isNotEmpty)
            SizedBox(
              key: const ValueKey('chat-input-document-previews'),
              height: _documentPreviewHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: fileDocs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final docEntry = fileDocs[idx];
                  final d = docEntry.value;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: previewFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: previewBorder, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.insert_drive_file,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.72,
                          ),
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            d.fileName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        IosIconButton(
                          key: ValueKey(
                            'chat-input-document-remove:${docEntry.key}',
                          ),
                          icon: Icons.close,
                          size: 16,
                          padding: const EdgeInsets.all(3),
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.58,
                          ),
                          circularFeedback: true,
                          onTap: () => _removeDocumentAt(docEntry.key),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inputRadius = BorderRadius.circular(AppRadius.chat);
    final hasText = _controller.text.trim().isNotEmpty;
    // Mirrors `_buildInlineAttachmentPreviews`'s split: a video draft
    // renders (and sizes) as part of the image-style thumbnail row, not the
    // document-chip row, so these two flags follow the same split.
    final pendingAttachmentCount =
        widget.mediaController?.pendingAttachmentCount.value ?? 0;
    final hasImages =
        _images.isNotEmpty ||
        _docs.any((d) => d.mime.startsWith('video/')) ||
        pendingAttachmentCount > 0;
    final hasDocs = _docs.any((d) => !d.mime.startsWith('video/'));
    final showActionsRow =
        _inputFocused ||
        (widget.focusNode?.hasFocus ?? false) ||
        _controller.text.isNotEmpty ||
        hasImages ||
        hasDocs;
    final compactSingleLine = !showActionsRow && _lineCount <= 1;
    final actionMenuItems = _buildComposerActionItems(context);
    _supportsImagesApiRouting(context);
    _supportsVideoApiRouting(context);
    if (_videoModeActive && !_wasVideoModeActive) {
      // Just switched into video mode — media attached before the switch
      // never went through `_addImages`/`_addFiles`'s trigger, so check now.
      unawaited(_maybeAutoRecommendVideoAspectRatio());
    }
    _wasVideoModeActive = _videoModeActive;
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final bool isMobileLayout = size.width < AppBreakpoints.tablet;
    final double visibleHeight = size.height - viewInsets.bottom;
    final double attachmentPreviewHeight = (hasDocs || hasImages)
        ? AppSpacing.sm +
              (hasImages ? _imagePreviewHeight : 0) +
              (hasImages && hasDocs ? AppSpacing.xs : 0) +
              (hasDocs ? _documentPreviewHeight : 0) +
              AppSpacing.xxs
        : 0;
    const double baseChromeHeight = 120; // padding + action row + chrome buffer
    double maxInputHeight = double.infinity;
    if (isMobileLayout) {
      final double available =
          visibleHeight - attachmentPreviewHeight - baseChromeHeight;
      final double softCap = visibleHeight * 0.45;
      if (available > 0) {
        maxInputHeight = math.min(softCap, available);
        maxInputHeight = math.min(available, math.max(80.0, maxInputHeight));
      } else {
        maxInputHeight = math.max(80.0, softCap);
      }
    }
    // Cap text field height on mobile so expanded input stays above the keyboard.
    final BoxConstraints textFieldConstraints =
        (isMobileLayout && maxInputHeight.isFinite && maxInputHeight > 0)
        ? BoxConstraints(maxHeight: maxInputHeight)
        : const BoxConstraints();

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xxs,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.hasQueuedInput) ...[
              _QueuedInputBanner(
                label: AppLocalizations.of(context)!.chatInputBarQueuedPending,
                previewText: widget.queuedPreviewText,
                cancelLabel: AppLocalizations.of(
                  context,
                )!.chatInputBarQueuedCancel,
                onCancel: widget.onCancelQueuedInput,
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Use the same glass fill, blur, border, and shadow as the
                // shared toolbar button islands.
                Container(
                  decoration: BoxDecoration(
                    borderRadius: inputRadius,
                    boxShadow: [AppButtonIslandStyle.shadow(theme.brightness)],
                  ),
                  child: ClipRRect(
                    borderRadius: inputRadius,
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: AppButtonIslandStyle.blurSigma,
                        sigmaY: AppButtonIslandStyle.blurSigma,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppButtonIslandStyle.fill(theme.brightness),
                          borderRadius: inputRadius,
                          border: Border.all(
                            color: AppButtonIslandStyle.border(
                              theme.brightness,
                            ),
                            width: AppButtonIslandStyle.borderWidth,
                          ),
                        ),
                        child: Column(
                          children: [
                            if (hasDocs || hasImages)
                              _buildInlineAttachmentPreviews(context, isDark),
                            // [kelivo-hosted] xAI's `/v1/videos/edits`/`/extensions`
                            // (the endpoints used whenever there's already a
                            // video to continue — `_hasAttachedVideo`) only
                            // accept a `video` field, no `image`/`reference_images`
                            // — confirmed against xAI's own REST API reference.
                            // Any image attached alongside a video-continuation
                            // turn is silently dropped server-side
                            // (client_chat_task.py's `_stream_video_generation`),
                            // so tell the user up front rather than let them
                            // find out only after the model doesn't react to it.
                            if (_videoModeActive &&
                                _hasAttachedVideo &&
                                _images.isNotEmpty)
                              _buildVideoImageIgnoredWarning(context),
                            // Input field with expand/collapse button
                            Row(
                              children: [
                                if (!showActionsRow)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      start: 6,
                                      end: AppSpacing.xxs,
                                    ),
                                    child: _buildComposerAddButton(
                                      context,
                                      actionMenuItems,
                                      _collapsedComposerActionsAnchorKey,
                                    ),
                                  ),
                                Expanded(
                                  key: const ValueKey<String>(
                                    'chat-input-field-slot',
                                  ),
                                  child: Stack(
                                    children: [
                                      Padding(
                                        padding: EdgeInsetsDirectional.fromSTEB(
                                          showActionsRow
                                              ? AppSpacing.md
                                              : AppSpacing.xs,
                                          compactSingleLine
                                              ? 0
                                              : AppSpacing.xxs,
                                          AppSpacing.md,
                                          compactSingleLine ? 0 : AppSpacing.xs,
                                        ),
                                        child: ConstrainedBox(
                                          constraints: textFieldConstraints,
                                          child: Focus(
                                            onFocusChange:
                                                _scheduleInputFocusUpdate,
                                            onKeyEvent: _handleKeyEvent,
                                            child: Builder(
                                              builder: (ctx) {
                                                // Desktop: show a right-click context menu with paste/cut/copy/select all
                                                // Future<void> _showDesktopContextMenu(Offset globalPos) async {
                                                //   bool isDesktop = false;
                                                //   try { isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux; } catch (_) {}
                                                //   if (!isDesktop) return;
                                                //   // Ensure input has focus so operations apply correctly
                                                //   try { widget.focusNode?.requestFocus(); } catch (_) {}
                                                //
                                                //   final sel = _controller.selection;
                                                //   final hasSelection = sel.isValid && !sel.isCollapsed;
                                                //   final hasText = _controller.text.isNotEmpty;
                                                //
                                                //   final l10n = MaterialLocalizations.of(ctx);
                                                //   await showDesktopContextMenuAt(
                                                //     ctx,
                                                //     globalPosition: globalPos,
                                                //     items: [
                                                //       DesktopContextMenuItem(
                                                //         icon: Lucide.Clipboard,
                                                //         label: l10n.pasteButtonLabel,
                                                //         onTap: () async {
                                                //           await _handlePasteFromClipboard();
                                                //         },
                                                //       ),
                                                //       DesktopContextMenuItem(
                                                //         icon: Lucide.Cut,
                                                //         label: l10n.cutButtonLabel,
                                                //         onTap: () async {
                                                //           final s = _controller.selection;
                                                //           if (s.isValid && !s.isCollapsed) {
                                                //             final text = _controller.text.substring(s.start, s.end);
                                                //             try { await Clipboard.setData(ClipboardData(text: text)); } catch (_) {}
                                                //             final newText = _controller.text.replaceRange(s.start, s.end, '');
                                                //             _controller.value = TextEditingValue(
                                                //               text: newText,
                                                //               selection: TextSelection.collapsed(offset: s.start),
                                                //             );
                                                //             setState(() {});
                                                //           }
                                                //         },
                                                //       ),
                                                //       DesktopContextMenuItem(
                                                //         icon: Lucide.Copy,
                                                //         label: l10n.copyButtonLabel,
                                                //         onTap: () async {
                                                //           final s2 = _controller.selection;
                                                //           if (s2.isValid && !s2.isCollapsed) {
                                                //             final text = _controller.text.substring(s2.start, s2.end);
                                                //             try { await Clipboard.setData(ClipboardData(text: text)); } catch (_) {}
                                                //           }
                                                //         },
                                                //       ),
                                                //       // DesktopContextMenuItem(
                                                //       //   // icon: Lucide.TextSelect,
                                                //       //   label: l10n.selectAllButtonLabel,
                                                //       //   onTap: () {
                                                //       //     if (hasText) {
                                                //       //       _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
                                                //       //       setState(() {});
                                                //       //     }
                                                //       //   },
                                                //       // ),
                                                //     ],
                                                //   );
                                                // }

                                                final enterToSend = context
                                                    .watch<SettingsProvider>()
                                                    .enterToSendOnMobile;
                                                return GestureDetector(
                                                  behavior: HitTestBehavior
                                                      .deferToChild,
                                                  // onSecondaryTapDown: (details) {
                                                  //   // _showDesktopContextMenu(details.globalPosition);
                                                  // },
                                                  child: AppTextField(
                                                    controller: _controller,
                                                    focusNode: widget.focusNode,
                                                    onTap: () {
                                                      widget.focusNode
                                                          ?.requestFocus();
                                                    },
                                                    onChanged: _onTextChanged,
                                                    readOnly: _composerLocked,
                                                    minLines: 1,
                                                    maxLines: compactSingleLine
                                                        ? 1
                                                        : _isExpanded
                                                        ? 25
                                                        : 5,
                                                    textAlignVertical:
                                                        compactSingleLine
                                                        ? TextAlignVertical
                                                              .center
                                                        : null,
                                                    // On mobile, optionally show "Send" on the return key and submit on tap.
                                                    // Still keep multiline so pasted text preserves line breaks.
                                                    keyboardType:
                                                        TextInputType.multiline,
                                                    textInputAction: enterToSend
                                                        ? TextInputAction.send
                                                        : TextInputAction
                                                              .newline,
                                                    onSubmitted: enterToSend
                                                        ? (_) => unawaited(
                                                            _handleSend(),
                                                          )
                                                        : null,
                                                    // Custom context menu: use instance method to avoid flickering
                                                    // caused by recreating the callback on every build.
                                                    // See: https://github.com/flutter/flutter/issues/150551
                                                    contextMenuBuilder:
                                                        _buildContextMenu,
                                                    autofocus: false,
                                                    decoration: InputDecoration(
                                                      isDense:
                                                          compactSingleLine,
                                                      constraints:
                                                          compactSingleLine
                                                          ? const BoxConstraints.tightFor(
                                                              height:
                                                                  _composerButtonIslandHeight,
                                                            )
                                                          : null,
                                                      hintText: _hint(context),
                                                      hintStyle: TextStyle(
                                                        color: theme
                                                            .colorScheme
                                                            .onSurface
                                                            .withValues(
                                                              alpha: 0.45,
                                                            ),
                                                      ),
                                                      border: InputBorder.none,
                                                      // Keep the line centered inside the fixed-height island.
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            vertical:
                                                                compactSingleLine
                                                                ? 12
                                                                : 2,
                                                          ),
                                                    ),
                                                    style: TextStyle(
                                                      color: theme
                                                          .colorScheme
                                                          .onSurface,
                                                      fontSize:
                                                          (Platform.isWindows ||
                                                              Platform
                                                                  .isLinux ||
                                                              Platform.isMacOS)
                                                          ? 14
                                                          : 15,
                                                    ),
                                                    cursorColor: theme
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Expand/Collapse icon button (only shown when 3+ lines)
                                      if (_showExpandButton)
                                        Positioned(
                                          top: 10,
                                          right: 12,
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(
                                                () =>
                                                    _isExpanded = !_isExpanded,
                                              );
                                              _ensureCaretVisible();
                                            },
                                            child: Icon(
                                              _isExpanded
                                                  ? Lucide.ChevronsDownUp
                                                  : Lucide.ChevronsUpDown,
                                              size: 16,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.45),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (compactSingleLine)
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 6,
                                    ),
                                    child: _CompactSendButton(
                                      enabled:
                                          (hasText || hasImages || hasDocs) &&
                                          !widget.loading,
                                      loading: widget.loading,
                                      onSend: _handleSend,
                                      onStop: widget.loading
                                          ? widget.onStop
                                          : null,
                                      color: theme.colorScheme.primary,
                                      icon: Lucide.ArrowUp,
                                      tooltip: widget.sendButtonTooltip,
                                    ),
                                  ),
                              ],
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: showActionsRow
                                  ? Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.xs,
                                        0,
                                        AppSpacing.xs,
                                        AppSpacing.xs,
                                      ),
                                      child: Row(
                                        children: [
                                          _buildComposerAddButton(
                                            context,
                                            actionMenuItems,
                                            _expandedComposerActionsAnchorKey,
                                          ),
                                          if (widget.referenceMode !=
                                              AttachmentReferenceMode
                                                  .disabled) ...[
                                            const SizedBox(
                                              width: AppSpacing.xxs,
                                            ),
                                            _buildImageReferenceButton(context),
                                          ],
                                          const Spacer(),
                                          if (_imageModeActive ||
                                              _videoModeActive) ...[
                                            _buildGenerationOptionsButton(
                                              context,
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.xs,
                                            ),
                                          ],
                                          _CompactIconButton(
                                            tooltip: AppLocalizations.of(
                                              context,
                                            )!.chatInputBarSelectModelTooltip,
                                            icon: Lucide.Boxes,
                                            modelIcon: true,
                                            onTap: _composerLocked
                                                ? null
                                                : widget.onSelectModel,
                                            child: widget.modelIcon,
                                          ),
                                          const SizedBox(width: AppSpacing.xs),
                                          _CompactSendButton(
                                            enabled:
                                                (hasText ||
                                                    hasImages ||
                                                    hasDocs) &&
                                                !widget.loading,
                                            loading: widget.loading,
                                            onSend: _handleSend,
                                            onStop: widget.loading
                                                ? widget.onStop
                                                : null,
                                            color: theme.colorScheme.primary,
                                            icon: Lucide.ArrowUp,
                                            tooltip: widget.sendButtonTooltip,
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QueuedInputBanner extends StatelessWidget {
  const _QueuedInputBanner({
    required this.label,
    required this.cancelLabel,
    this.previewText,
    this.onCancel,
  });

  final String label;
  final String cancelLabel;
  final String? previewText;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final preview = previewText?.trim();
    final hasPreview = preview != null && preview.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.16),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.schedule_rounded,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                if (hasPreview) ...[
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.72,
                      ),
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IosCardPress(
            onTap: onCancel,
            borderRadius: BorderRadius.circular(10),
            baseColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              cancelLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: AppFontWeights.semibold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopupMenuStepper extends StatefulWidget {
  const _PopupMenuStepper({
    required this.label,
    required this.values,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<int> values;
  final int value;
  final ValueChanged<int>? onChanged;

  @override
  State<_PopupMenuStepper> createState() => _PopupMenuStepperState();
}

class _PopupMenuStepperState extends State<_PopupMenuStepper> {
  late int _value = widget.value;

  @override
  void didUpdateWidget(covariant _PopupMenuStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  void _changeBy(int delta) {
    final currentIndex = widget.values.indexOf(_value);
    final nextIndex = currentIndex + delta;
    if (widget.onChanged == null ||
        currentIndex < 0 ||
        nextIndex < 0 ||
        nextIndex >= widget.values.length) {
      return;
    }
    final nextValue = widget.values[nextIndex];
    setState(() => _value = nextValue);
    widget.onChanged!(nextValue);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIndex = widget.values.indexOf(_value);
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        IosIconButton(
          icon: Lucide.Minus,
          size: 16,
          padding: const EdgeInsets.all(4),
          minSize: 32,
          onTap: currentIndex > 0 ? () => _changeBy(-1) : null,
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$_value',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: AppFontWeights.semibold,
            ),
          ),
        ),
        IosIconButton(
          icon: Lucide.Plus,
          size: 16,
          padding: const EdgeInsets.all(4),
          minSize: 32,
          onTap: currentIndex >= 0 && currentIndex < widget.values.length - 1
              ? () => _changeBy(1)
              : null,
        ),
      ],
    );
  }
}

class _PopupMenuSwitch extends StatefulWidget {
  const _PopupMenuSwitch({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<_PopupMenuSwitch> createState() => _PopupMenuSwitchState();
}

class _PopupMenuSwitchState extends State<_PopupMenuSwitch> {
  late bool _value = widget.value;

  @override
  void didUpdateWidget(covariant _PopupMenuSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                widget.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        AppSwitch(
          value: _value,
          onChanged: widget.onChanged == null
              ? null
              : (value) {
                  setState(() => _value = value);
                  widget.onChanged!(value);
                },
          semanticLabel: widget.label,
        ),
      ],
    );
  }
}

// New compact button for the integrated input bar
class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    this.onTap,
    this.tooltip,
    this.child,
    this.modelIcon = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Widget? child;
  final bool modelIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fgColor = isDark ? Colors.white70 : Colors.black54;
    // Keep overall button size constant. For model icon with child, enlarge child slightly
    // and reduce padding so (2*padding + childSize) stays unchanged.
    final bool isModelChild = modelIcon && child != null;
    final double iconSize = 20.0; // default glyph size
    final double childSize = isModelChild
        ? 28.0
        : iconSize; // enlarge circle a bit more
    final double padding = isModelChild
        ? 1.0
        : 6.0; // keep total ~30px (2*1 + 28)

    final button = IosIconButton(
      size: isModelChild ? childSize : 20,
      padding: EdgeInsets.all(padding),
      onTap: onTap,
      color: fgColor,
      circularFeedback: true,
      builder: child == null
          ? null
          : (_) => SizedBox(width: childSize, height: childSize, child: child),
      icon: child == null ? icon : null,
    );

    if (tooltip == null) {
      return button;
    }

    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(tooltip: tooltip!, child: button),
    );
  }
}

// New compact send button for the integrated input bar
class _CompactSendButton extends StatelessWidget {
  const _CompactSendButton({
    required this.enabled,
    required this.onSend,
    required this.color,
    required this.icon,
    this.loading = false,
    this.onStop,
    this.tooltip,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final Color color;
  final IconData icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = (enabled || loading)
        ? color
        : (isDark
              ? Colors.white12
              : Colors.grey.shade300.withValues(alpha: 0.84));
    final fg = (enabled || loading)
        ? (isDark ? Colors.black : Colors.white)
        : (isDark ? Colors.white70 : Colors.grey.shade600);

    final button = Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: loading ? onStop : (enabled ? onSend : null),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: loading
                ? SvgPicture.asset(
                    key: const ValueKey('stop'),
                    'assets/icons/stop.svg',
                    width: 18,
                    height: 18,
                    colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                  )
                : Icon(icon, key: const ValueKey('send'), size: 18, color: fg),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(tooltip: tooltip!, child: button),
    );
  }
}
