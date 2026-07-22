import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../../../theme/design_tokens.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../icons/reasoning_icons.dart';
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
import '../../../utils/clipboard_images.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/search/search_service.dart';
import '../../../core/services/api/builtin_tools.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/utils/multimodal_input_utils.dart';
import '../../../core/utils/video_duration_options.dart';
import '../../../utils/brand_assets.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../utils/app_directories.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../../../desktop/desktop_context_menu.dart';
import 'package:Kelivo/theme/app_font_weights.dart';
import 'package:video_player/video_player.dart';
import '../../../utils/sandbox_path_resolver.dart';

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
    this.onLongPressSelectModel,
    this.onOpenMcp,
    this.onLongPressMcp,
    this.onOpenSearch,
    this.onMore,
    this.onConfigureReasoning,
    this.moreOpen = false,
    this.focusNode,
    this.modelIcon,
    this.controller,
    this.mediaController,
    this.loading = false,
    this.hasQueuedInput = false,
    this.queuedPreviewText,
    this.onCancelQueuedInput,
    this.reasoningActive = false,
    this.reasoningBudget,
    this.supportsReasoning = true,
    this.showMcpButton = false,
    this.mcpActive = false,
    this.showMiniMapButton = false,
    this.onOpenMiniMap,
    this.onPickCamera,
    this.onPickPhotos,
    this.onPickPhotosOrVideo,
    this.onUploadFiles,
    this.onToggleLearningMode,
    this.onOpenWorldBook,
    this.onClearContext,
    this.onCompressContext,
    this.onLongPressLearning,
    this.learningModeActive = false,
    this.worldBookActive = false,
    this.showMoreButton = true,
    this.showQuickPhraseButton = false,
    this.onQuickPhrase,
    this.onLongPressQuickPhrase,
    this.showOcrButton = false,
    this.ocrActive = false,
    this.onToggleOcr,
    this.conversationId,
    this.sendButtonTooltip,
    this.backgroundImageActive = false,
    this.inputBackgroundOpacityLight =
        SettingsProvider.defaultChatInputBackgroundOpacityLight,
    this.inputBackgroundOpacityDark =
        SettingsProvider.defaultChatInputBackgroundOpacityDark,
    this.hasVideoInHistory = false,
  });

  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;
  final VoidCallback? onStop;
  final VoidCallback? onSelectModel;
  final VoidCallback? onLongPressSelectModel;
  final VoidCallback? onOpenMcp;
  final VoidCallback? onLongPressMcp;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onMore;
  final VoidCallback? onConfigureReasoning;
  final bool moreOpen;
  final FocusNode? focusNode;
  final Widget? modelIcon;
  final TextEditingController? controller;
  final ChatInputBarController? mediaController;
  final bool loading;
  final bool hasQueuedInput;
  final String? queuedPreviewText;
  final VoidCallback? onCancelQueuedInput;
  final bool reasoningActive;
  final int? reasoningBudget;
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
  final VoidCallback? onUploadFiles;
  final VoidCallback? onToggleLearningMode;
  final VoidCallback? onOpenWorldBook;
  final VoidCallback? onClearContext;
  final VoidCallback? onCompressContext;
  final VoidCallback? onLongPressLearning;
  final bool learningModeActive;
  final bool worldBookActive;
  final bool showMoreButton;
  final bool showQuickPhraseButton;
  final VoidCallback? onQuickPhrase;
  final VoidCallback? onLongPressQuickPhrase;
  final bool showOcrButton;
  final bool ocrActive;
  final VoidCallback? onToggleOcr;
  final String? conversationId;
  final String? sendButtonTooltip;
  final bool backgroundImageActive;
  final double inputBackgroundOpacityLight;
  final double inputBackgroundOpacityDark;
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
  late TextEditingController _controller;
  bool _isExpanded = false; // Track expand/collapse state for input field
  final List<String> _images = <String>[]; // local file paths
  final List<DocumentAttachment> _docs =
      <DocumentAttachment>[]; // files to upload
  final Map<LogicalKeyboardKey, Timer?> _repeatTimers = {};
  static const Duration _repeatInitialDelay = Duration(milliseconds: 300);
  static const Duration _repeatPeriod = Duration(milliseconds: 35);
  // Anchor for the responsive overflow menu on the left action bar
  final GlobalKey _leftOverflowAnchorKey = GlobalKey(
    debugLabel: 'left-overflow-anchor',
  );
  final GlobalKey _contextMgmtAnchorKey = GlobalKey(
    debugLabel: 'context-mgmt-anchor',
  );
  static const double _documentPreviewHeight = 48;
  static const double _imagePreviewHeight = 64;
  static const double _imageRemoveButtonSize = 18;
  // Suppress context menu briefly after app resume to avoid flickering
  bool _suppressContextMenu = false;
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

  Color _inputFillColor({
    required ThemeData theme,
    required bool backgroundImageActive,
    required double lightOpacity,
    required double darkOpacity,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final configuredOpacity = (isDark ? darkOpacity : lightOpacity)
        .clamp(0.0, 1.0)
        .toDouble();
    final backgroundRatio = isDark
        ? 0.545 / SettingsProvider.defaultChatInputBackgroundOpacityDark
        : 0.5296 / SettingsProvider.defaultChatInputBackgroundOpacityLight;
    final targetOpacity = backgroundImageActive
        ? configuredOpacity * backgroundRatio
        : configuredOpacity;
    final overlayAlpha = isDark ? (backgroundImageActive ? 0.09 : 0.07) : 0.02;
    final overlayTint = isDark
        ? Colors.white.withValues(alpha: overlayAlpha)
        : theme.colorScheme.primary.withValues(alpha: overlayAlpha);
    final baseAlpha = ((targetOpacity - overlayAlpha) / (1.0 - overlayAlpha))
        .clamp(0.0, 1.0)
        .toDouble();
    final base = theme.colorScheme.surface.withValues(alpha: baseAlpha);
    return Color.alphaBlend(overlayTint, base).withValues(alpha: targetOpacity);
  }

  /// Current model, preferring this conversation's own override, then the
  /// assistant's default, then the global default.
  ({String? providerKey, String? modelId}) _currentModelIds(
    BuildContext context,
  ) {
    final settings = context.watch<SettingsProvider>();
    final ap = context.watch<AssistantProvider>();
    final a = ap.currentAssistant;
    final override = widget.conversationId != null
        ? context.watch<ChatService>().getConversationChatModel(
            widget.conversationId!,
          )
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

  // Instance method for onChanged to avoid recreating the callback on every build
  void _onTextChanged(String _) => setState(() {});

  void _addImages(List<String> paths) {
    if (paths.isEmpty) return;
    setState(() => _images.addAll(paths));
    unawaited(_maybeAutoRecommendVideoAspectRatio());
  }

  void _clearImages() {
    setState(() {
      _images.clear();
      _videoAspectRatioUserSet = false;
    });
  }

  void _addFiles(List<DocumentAttachment> docs) {
    if (docs.isEmpty) return;
    setState(() => _docs.addAll(docs));
    unawaited(_maybeAutoRecommendVideoAspectRatio());
  }

  void _clearFiles() {
    setState(() {
      _docs.clear();
      _videoExtendMode = false;
      _videoAspectRatioUserSet = false;
    });
  }

  void _restoreInput(ChatInputData input) {
    setState(() {
      _images
        ..clear()
        ..addAll(input.imagePaths);
      _docs
        ..clear()
        ..addAll(input.documents);
      if (!_hasAttachedVideo) _videoExtendMode = false;
    });
  }

  ChatInputData _snapshotInput(String text) {
    return ChatInputData(
      text: text.trim(),
      imagePaths: List<String>.of(_images),
      documents: List<DocumentAttachment>.of(_docs),
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
      _videoAspectRatioUserSet = false;
    });
  }

  void _removeImageAt(int index) {
    setState(() => _images.removeAt(index));
  }

  void _removeDocumentAt(int index) {
    setState(() {
      _docs.removeAt(index);
      if (!_hasAttachedVideo) _videoExtendMode = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    widget.mediaController?._bind(this);
    widget.mediaController?.pendingAttachmentCount.addListener(
      _onPendingAttachmentCountChanged,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  void _onPendingAttachmentCountChanged() {
    if (mounted) setState(() {});
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
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    final text = _controller.text.trim();
    if (text.isEmpty && _images.isEmpty && _docs.isEmpty) return;
    _isSubmitting = true;
    try {
      final result =
          await widget.onSend?.call(_snapshotInput(text)) ??
          ChatInputSubmissionResult.rejected;
      if (!mounted) return;
      if (result == ChatInputSubmissionResult.sent ||
          result == ChatInputSubmissionResult.queued) {
        _controller.clear();
        _images.clear();
        _docs.clear();
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
                  final text = value.text.substring(start, end);
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
                  final start = selection.start;
                  final end = selection.end;
                  final text = value.text.substring(start, end);
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

  // Build a responsive left action bar that hides overflowing actions
  // into an anchored "+" menu using DesktopContextMenu style.
  Widget _buildResponsiveLeftActions(BuildContext context) {
    const double spacing = 8;
    const double normalButtonW = 32; // 20 + padding(6*2)
    const double modelButtonW = 30; // 28 + padding(1*2)
    const double plusButtonW = 32;

    final l10n = AppLocalizations.of(context)!;
    VoidCallback? lockTap(VoidCallback? callback) {
      if (_composerLocked) return null;
      return callback;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final List<_OverflowAction> actions = [];

        // Model select (always present; can be hidden if overflow)
        actions.add(
          _OverflowAction(
            width: (widget.modelIcon != null) ? modelButtonW : normalButtonW,
            builder: () => _CompactIconButton(
              tooltip: l10n.chatInputBarSelectModelTooltip,
              icon: Lucide.Boxes,
              modelIcon: true,
              onTap: lockTap(widget.onSelectModel),
              onLongPress: lockTap(widget.onLongPressSelectModel),
              child: widget.modelIcon,
            ),
            menu: DesktopContextMenuItem(
              icon: Lucide.Boxes,
              label: l10n.chatInputBarSelectModelTooltip,
              onTap: lockTap(widget.onSelectModel),
            ),
          ),
        );

        // Search button (stateful icon depending on provider config)
        final settings = context.watch<SettingsProvider>();
        final ap = context.watch<AssistantProvider>();
        final currentModelIds = _currentModelIds(context);
        final currentProviderKey = currentModelIds.providerKey;
        final currentModelId = currentModelIds.modelId;
        final cfg = (currentProviderKey != null)
            ? settings.getProviderConfig(currentProviderKey)
            : null;
        // Check built-in tools state using helper
        final toolsState = BuiltInToolsHelper.getActiveTools(
          cfg: cfg,
          modelId: currentModelId,
        );
        final builtinSearchActive = toolsState.searchActive;
        final appSearchEnabled = ap.currentSearchEnabled;
        // [kelivo-hosted] "服务器搜索" isn't a member of `settings.searchServices`
        // at all (see search_settings_sheet.dart/search_provider_popover.dart)
        // — same tri-state default as there: unset/null defaults to server
        // for a hosted assistant, only explicit 'client' falls back to the
        // device-local provider this toolbar icon would otherwise show.
        final serverSearchActive =
            ap.currentAssistant?.cloudHosted == true &&
            ap.currentAssistant?.searchProviderMode != 'client';
        final brandAsset = (() {
          if (!appSearchEnabled || builtinSearchActive || serverSearchActive) {
            return null;
          }
          final services = settings.searchServices;
          final sel = settings.searchServiceSelected.clamp(
            0,
            services.isNotEmpty ? services.length - 1 : 0,
          );
          final options = services.isNotEmpty
              ? services[sel]
              : SearchServiceOptions.defaultOption;
          final svc = SearchService.getService(options);
          return BrandAssets.assetForName(svc.name);
        })();

        // Search button
        actions.add(
          _OverflowAction(
            width: normalButtonW,
            builder: () {
              // Not enabled at all -> default globe
              if (!appSearchEnabled && !builtinSearchActive) {
                return _CompactIconButton(
                  tooltip: l10n.chatInputBarOnlineSearchTooltip,
                  icon: Lucide.Globe,
                  active: false,
                  onTap: lockTap(widget.onOpenSearch),
                );
              }
              // Built-in search -> magnifier icon in theme color
              if (builtinSearchActive) {
                return _CompactIconButton(
                  tooltip: l10n.chatInputBarOnlineSearchTooltip,
                  icon: Lucide.Search,
                  active: true,
                  onTap: lockTap(widget.onOpenSearch),
                );
              }
              // External provider search -> brand icon
              return _CompactIconButton(
                tooltip: l10n.chatInputBarOnlineSearchTooltip,
                icon: Lucide.Globe,
                active: true,
                onTap: lockTap(widget.onOpenSearch),
                childBuilder: (c) {
                  if (serverSearchActive) {
                    return Icon(Lucide.Network, size: 20, color: c);
                  }
                  final asset = brandAsset;
                  if (asset != null) {
                    if (asset.endsWith('.svg')) {
                      return SvgPicture.asset(
                        asset,
                        width: 20,
                        height: 20,
                        colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
                      );
                    } else {
                      return Image.asset(
                        asset,
                        width: 20,
                        height: 20,
                        color: c,
                        colorBlendMode: BlendMode.srcIn,
                      );
                    }
                  } else {
                    return Icon(Lucide.Globe, size: 20, color: c);
                  }
                },
              );
            },
            menu: () {
              // Prefer vector icon if brandAsset is svg, otherwise pick reasonable default
              if (!appSearchEnabled && !builtinSearchActive) {
                return DesktopContextMenuItem(
                  icon: Lucide.Globe,
                  label: l10n.chatInputBarOnlineSearchTooltip,
                  onTap: lockTap(widget.onOpenSearch),
                );
              }
              if (builtinSearchActive) {
                return DesktopContextMenuItem(
                  icon: Lucide.Search,
                  label: l10n.chatInputBarOnlineSearchTooltip,
                  onTap: lockTap(widget.onOpenSearch),
                );
              }
              if (serverSearchActive) {
                return DesktopContextMenuItem(
                  icon: Lucide.Network,
                  label: l10n.chatInputBarOnlineSearchTooltip,
                  onTap: lockTap(widget.onOpenSearch),
                );
              }
              if (brandAsset != null && brandAsset.endsWith('.svg')) {
                return DesktopContextMenuItem(
                  svgAsset: brandAsset,
                  label: l10n.chatInputBarOnlineSearchTooltip,
                  onTap: lockTap(widget.onOpenSearch),
                );
              }
              return DesktopContextMenuItem(
                icon: Lucide.Globe,
                label: l10n.chatInputBarOnlineSearchTooltip,
                onTap: lockTap(widget.onOpenSearch),
              );
            }(),
          ),
        );

        if (widget.supportsReasoning) {
          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => _CompactIconButton(
                tooltip: l10n.chatInputBarReasoningStrengthTooltip,
                icon: Lucide.Brain,
                active: widget.reasoningActive,
                onTap: lockTap(widget.onConfigureReasoning),
                childBuilder: (c) => ReasoningIcons.budgetIcon(
                  widget.reasoningBudget,
                  size: 20,
                  color: c,
                ),
              ),
              menu: DesktopContextMenuItem(
                svgAsset: ReasoningIcons.assetForBudget(widget.reasoningBudget),
                label: l10n.chatInputBarReasoningStrengthTooltip,
                onTap: lockTap(widget.onConfigureReasoning),
              ),
            ),
          );
        }

        // MCP button
        if (widget.showMcpButton) {
          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => _CompactIconButton(
                tooltip: l10n.chatInputBarMcpServersTooltip,
                icon: Lucide.Hammer,
                active: widget.mcpActive,
                onTap: lockTap(widget.onOpenMcp),
                onLongPress: lockTap(widget.onLongPressMcp),
              ),
              menu: DesktopContextMenuItem(
                icon: Lucide.Hammer,
                label: l10n.chatInputBarMcpServersTooltip,
                onTap: lockTap(widget.onOpenMcp),
              ),
            ),
          );
        }

        if (widget.showQuickPhraseButton && widget.onQuickPhrase != null) {
          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => _CompactIconButton(
                tooltip: l10n.chatInputBarQuickPhraseTooltip,
                icon: Lucide.Zap,
                onTap: lockTap(widget.onQuickPhrase),
                onLongPress: lockTap(widget.onLongPressQuickPhrase),
              ),
              menu: DesktopContextMenuItem(
                icon: Lucide.Zap,
                label: l10n.chatInputBarQuickPhraseTooltip,
                onTap: lockTap(widget.onQuickPhrase),
              ),
            ),
          );
        }

        if (widget.onPickCamera != null) {
          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => _CompactIconButton(
                tooltip: l10n.bottomToolsSheetCamera,
                icon: Lucide.Camera,
                onTap: lockTap(widget.onPickCamera),
              ),
              menu: DesktopContextMenuItem(
                icon: Lucide.Camera,
                label: l10n.bottomToolsSheetCamera,
                onTap: lockTap(widget.onPickCamera),
              ),
            ),
          );
        }

        final pickMediaForVideoMode =
            widget.onPickPhotosOrVideo ?? widget.onPickPhotos;
        if (_videoModeActive && pickMediaForVideoMode != null) {
          // One merged picker for video mode (image-to-video reference
          // frame OR a video to edit/extend) instead of a separate
          // image-only "Photos" button next to a video-only one. Gated on
          // `pickMediaForVideoMode != null` same as the plain "Photos"
          // action below (tablet/desktop only) — this used to be
          // unconditional, which meant it ignored the "everything not
          // directly reachable stays behind the '+' button on phones" rule
          // every other attachment action follows, and showed up inline
          // even on narrow phones while its non-video counterpart stayed
          // tucked away.
          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => _CompactIconButton(
                tooltip: l10n.chatInputBarPickMedia,
                icon: Lucide.Image,
                onTap: lockTap(pickMediaForVideoMode),
              ),
              menu: DesktopContextMenuItem(
                icon: Lucide.Image,
                label: l10n.chatInputBarPickMedia,
                onTap: lockTap(pickMediaForVideoMode),
              ),
            ),
          );
        } else if (!_videoModeActive && widget.onPickPhotos != null) {
          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => _CompactIconButton(
                tooltip: l10n.bottomToolsSheetPhotos,
                icon: Lucide.Image,
                onTap: lockTap(widget.onPickPhotos),
              ),
              menu: DesktopContextMenuItem(
                icon: Lucide.Image,
                label: l10n.bottomToolsSheetPhotos,
                onTap: lockTap(widget.onPickPhotos),
              ),
            ),
          );
        }

        if (widget.onUploadFiles != null) {
          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => _CompactIconButton(
                tooltip: l10n.bottomToolsSheetUpload,
                icon: Lucide.Paperclip,
                onTap: lockTap(widget.onUploadFiles),
              ),
              menu: DesktopContextMenuItem(
                icon: Lucide.Paperclip,
                label: l10n.bottomToolsSheetUpload,
                onTap: lockTap(widget.onUploadFiles),
              ),
            ),
          );
        }

        if (widget.onToggleLearningMode != null) {
          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => _CompactIconButton(
                tooltip: l10n.instructionInjectionTitle,
                icon: Lucide.Layers,
                active: widget.learningModeActive,
                onTap: lockTap(widget.onToggleLearningMode),
                onLongPress: lockTap(widget.onLongPressLearning),
              ),
              menu: DesktopContextMenuItem(
                icon: Lucide.Layers,
                label: l10n.instructionInjectionTitle,
                onTap: lockTap(widget.onToggleLearningMode),
              ),
            ),
          );
        }

        if (widget.onOpenWorldBook != null) {
          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => _CompactIconButton(
                tooltip: l10n.worldBookTitle,
                icon: Lucide.BookOpen,
                active: widget.worldBookActive,
                onTap: lockTap(widget.onOpenWorldBook),
              ),
              menu: DesktopContextMenuItem(
                icon: Lucide.BookOpen,
                label: l10n.worldBookTitle,
                onTap: lockTap(widget.onOpenWorldBook),
              ),
            ),
          );
        }

        if (widget.onClearContext != null) {
          void showContextMenu() {
            showDesktopAnchoredMenu(
              context,
              anchorKey: _contextMgmtAnchorKey,
              items: [
                if (widget.onCompressContext != null)
                  DesktopContextMenuItem(
                    icon: Lucide.package2,
                    label: l10n.compressContext,
                    onTap: lockTap(widget.onCompressContext),
                  ),
                DesktopContextMenuItem(
                  icon: Lucide.Eraser,
                  label: l10n.bottomToolsSheetClearContext,
                  onTap: lockTap(widget.onClearContext),
                ),
              ],
            );
          }

          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => Container(
                key: _contextMgmtAnchorKey,
                child: _CompactIconButton(
                  tooltip: l10n.contextManagement,
                  icon: Lucide.Eraser,
                  onTap: _composerLocked ? null : showContextMenu,
                ),
              ),
              menu: DesktopContextMenuItem(
                icon: Lucide.Eraser,
                label: l10n.contextManagement,
                onTap: _composerLocked ? null : showContextMenu,
              ),
            ),
          );
        }

        if (widget.showMiniMapButton) {
          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => _CompactIconButton(
                tooltip: l10n.miniMapTooltip,
                icon: Lucide.Map,
                onTap: lockTap(widget.onOpenMiniMap),
              ),
              menu: DesktopContextMenuItem(
                icon: Lucide.Map,
                label: l10n.miniMapTooltip,
                onTap: lockTap(widget.onOpenMiniMap),
              ),
            ),
          );
        }

        if (widget.showOcrButton && widget.onToggleOcr != null) {
          actions.add(
            _OverflowAction(
              width: normalButtonW,
              builder: () => _CompactIconButton(
                tooltip: l10n.chatInputBarOcrTooltip,
                icon: Lucide.Eye,
                active: widget.ocrActive,
                onTap: lockTap(widget.onToggleOcr),
              ),
              menu: DesktopContextMenuItem(
                icon: Lucide.Eye,
                label: l10n.chatInputBarOcrTooltip,
                onTap: lockTap(widget.onToggleOcr),
              ),
            ),
          );
        }

        // Compute total width with spacing to see if overflow is needed
        double full = 0;
        for (var i = 0; i < actions.length; i++) {
          if (i > 0) full += spacing;
          full += actions[i].width;
        }

        final maxW = constraints.maxWidth;
        int visibleCount = actions.length;
        if (full > maxW) {
          // First pass: include as many as possible ignoring the +
          double used = 0;
          visibleCount = 0;
          for (var i = 0; i < actions.length; i++) {
            final add = (visibleCount > 0 ? spacing : 0) + actions[i].width;
            if (used + add <= maxW) {
              used += add;
              visibleCount++;
            } else {
              break;
            }
          }
          // Ensure + button fits; remove items until it does
          while (visibleCount > 0 && used + spacing + plusButtonW > maxW) {
            // remove last
            used -= actions[visibleCount - 1].width;
            if (visibleCount - 1 > 0) used -= spacing;
            visibleCount--;
          }
        }

        final overflowItems = actions.sublist(visibleCount);

        final children = <Widget>[];
        for (var i = 0; i < visibleCount; i++) {
          if (i > 0) children.add(const SizedBox(width: spacing));
          children.add(actions[i].builder());
        }

        if (overflowItems.isNotEmpty) {
          if (children.isNotEmpty) children.add(const SizedBox(width: spacing));
          final menuItems = overflowItems
              .map((e) => e.menu)
              .toList(growable: false);
          children.add(
            Container(
              key: _leftOverflowAnchorKey,
              child: _CompactIconButton(
                tooltip: l10n.chatInputBarMoreTooltip,
                icon: Lucide.Plus,
                onTap: () {
                  showDesktopAnchoredMenu(
                    context,
                    anchorKey: _leftOverflowAnchorKey,
                    items: menuItems,
                  );
                },
              ),
            ),
          );
        }

        return Row(children: children);
      },
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
    final inputFillColor = _inputFillColor(
      theme: theme,
      backgroundImageActive: widget.backgroundImageActive,
      lightOpacity: widget.inputBackgroundOpacityLight,
      darkOpacity: widget.inputBackgroundOpacityDark,
    );
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
                // Main input container with iOS-like frosted glass effect
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        // Translucent background over blurred content
                        color: inputFillColor,
                        borderRadius: BorderRadius.circular(20),
                        // Use previous gray border for better contrast on white
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.10)
                              : theme.colorScheme.outline.withValues(
                                  alpha: 0.20,
                                ),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          if (_imageModeActive)
                            _ImageGenOptionsRow(
                              sizeOptions: _imageGenSizeOptions,
                              selectedSize: _imageGenSize,
                              count: _imageGenCount,
                              onSizeChanged: _composerLocked
                                  ? null
                                  : (v) => setState(() => _imageGenSize = v),
                              onCountChanged: _composerLocked
                                  ? null
                                  : (v) => setState(() => _imageGenCount = v),
                            )
                          else if (_videoModeActive)
                            _VideoGenOptionsRow(
                              durationOptions: _videoDurationOptions,
                              duration: _videoDuration,
                              aspectRatioOptions: _videoAspectRatioOptions,
                              aspectRatio: _videoAspectRatio,
                              resolutionOptions: _videoResolutionOptions,
                              resolution: _videoResolution,
                              extendMode: _videoExtendMode && _hasAttachedVideo,
                              onDurationChanged: _composerLocked
                                  ? null
                                  : (v) => setState(() => _videoDuration = v),
                              onAspectRatioChanged: _composerLocked
                                  ? null
                                  : (v) => setState(() {
                                      _videoAspectRatio = v;
                                      _videoAspectRatioUserSet = true;
                                    }),
                              onResolutionChanged: _composerLocked
                                  ? null
                                  : (v) => setState(() => _videoResolution = v),
                              onExtendModeChanged:
                                  (_composerLocked || !_hasAttachedVideo)
                                  ? null
                                  : (v) => setState(() => _videoExtendMode = v),
                            ),
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
                          Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  AppSpacing.xxs,
                                  AppSpacing.md,
                                  AppSpacing.xs,
                                ),
                                child: ConstrainedBox(
                                  constraints: textFieldConstraints,
                                  child: Focus(
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
                                          behavior:
                                              HitTestBehavior.deferToChild,
                                          // onSecondaryTapDown: (details) {
                                          //   // _showDesktopContextMenu(details.globalPosition);
                                          // },
                                          child: TextField(
                                            controller: _controller,
                                            focusNode: widget.focusNode,
                                            onChanged: _onTextChanged,
                                            readOnly: _composerLocked,
                                            minLines: 1,
                                            maxLines: _isExpanded ? 25 : 5,
                                            // On mobile, optionally show "Send" on the return key and submit on tap.
                                            // Still keep multiline so pasted text preserves line breaks.
                                            keyboardType:
                                                TextInputType.multiline,
                                            textInputAction: enterToSend
                                                ? TextInputAction.send
                                                : TextInputAction.newline,
                                            onSubmitted: enterToSend
                                                ? (_) =>
                                                      unawaited(_handleSend())
                                                : null,
                                            // Custom context menu: use instance method to avoid flickering
                                            // caused by recreating the callback on every build.
                                            // See: https://github.com/flutter/flutter/issues/150551
                                            contextMenuBuilder:
                                                _buildContextMenu,
                                            autofocus: false,
                                            decoration: InputDecoration(
                                              hintText: _hint(context),
                                              hintStyle: TextStyle(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.45),
                                              ),
                                              border: InputBorder.none,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 2,
                                                  ),
                                            ),
                                            style: TextStyle(
                                              color:
                                                  theme.colorScheme.onSurface,
                                              fontSize:
                                                  (Platform.isWindows ||
                                                      Platform.isLinux ||
                                                      Platform.isMacOS)
                                                  ? 14
                                                  : 15,
                                            ),
                                            cursorColor:
                                                theme.colorScheme.primary,
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
                                        () => _isExpanded = !_isExpanded,
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
                          // Bottom buttons row (no divider)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.xs,
                              0,
                              AppSpacing.xs,
                              AppSpacing.xs,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Responsive left action bar that overflows into a + menu on desktop
                                Expanded(
                                  child: _buildResponsiveLeftActions(context),
                                ),
                                Row(
                                  children: [
                                    if (widget.showMoreButton) ...[
                                      _CompactIconButton(
                                        tooltip: AppLocalizations.of(
                                          context,
                                        )!.chatInputBarMoreTooltip,
                                        icon: Lucide.Plus,
                                        active: widget.moreOpen,
                                        onTap: _composerLocked
                                            ? null
                                            : widget.onMore,
                                        childBuilder: (c) => AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          transitionBuilder: (child, anim) =>
                                              RotationTransition(
                                                turns: Tween<double>(
                                                  begin: 0.85,
                                                  end: 1,
                                                ).animate(anim),
                                                child: FadeTransition(
                                                  opacity: anim,
                                                  child: child,
                                                ),
                                              ),
                                          child: Icon(
                                            widget.moreOpen
                                                ? Lucide.X
                                                : Lucide.Plus,
                                            key: ValueKey(
                                              widget.moreOpen ? 'close' : 'add',
                                            ),
                                            size: 20,
                                            color: c,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    _CompactSendButton(
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
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_imageModeActive)
                  PositionedDirectional(
                    top: -12,
                    start: AppSpacing.sm,
                    child: _ImageModePill(
                      label: AppLocalizations.of(
                        context,
                      )!.chatInputBarImageMode,
                    ),
                  )
                else if (_videoModeActive)
                  PositionedDirectional(
                    top: -12,
                    start: AppSpacing.sm,
                    child: _ImageModePill(
                      label: AppLocalizations.of(
                        context,
                      )!.chatInputBarVideoMode,
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

class _ImageGenOptionsRow extends StatelessWidget {
  const _ImageGenOptionsRow({
    required this.sizeOptions,
    required this.selectedSize,
    required this.count,
    required this.onSizeChanged,
    required this.onCountChanged,
  });

  final List<String> sizeOptions;
  final String selectedSize;
  final int count;
  final ValueChanged<String>? onSizeChanged;
  final ValueChanged<int>? onCountChanged;

  // Every other option is shown verbatim (e.g. "1024x1024") — only the
  // `_ChatInputBarState._imageGenSizeAuto` sentinel needs a localized
  // display label instead of its raw wire value ("auto").
  static String _sizeLabel(AppLocalizations l10n, String value) {
    return value == _ChatInputBarState._imageGenSizeAuto
        ? l10n.chatInputBarImageGenSizeAuto
        : value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.08,
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(l10n.chatInputBarImageGenSizeLabel, style: labelStyle),
          const SizedBox(width: AppSpacing.xs),
          PopupMenuButton<String>(
            enabled: onSizeChanged != null,
            initialValue: selectedSize,
            onSelected: onSizeChanged,
            padding: EdgeInsets.zero,
            itemBuilder: (context) => [
              for (final s in sizeOptions)
                PopupMenuItem<String>(
                  value: s,
                  child: Text(_sizeLabel(l10n, s)),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _sizeLabel(l10n, selectedSize),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Lucide.ChevronDown,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(l10n.chatInputBarImageGenCountLabel, style: labelStyle),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            icon: const Icon(Lucide.Minus, size: 16),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: (onCountChanged == null || count <= 1)
                ? null
                : () => onCountChanged!(count - 1),
          ),
          Text('$count', style: theme.textTheme.labelMedium),
          IconButton(
            icon: const Icon(Lucide.Plus, size: 16),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: (onCountChanged == null || count >= 4)
                ? null
                : () => onCountChanged!(count + 1),
          ),
        ],
      ),
    );
  }
}

class _VideoGenOptionsRow extends StatelessWidget {
  const _VideoGenOptionsRow({
    required this.durationOptions,
    required this.duration,
    required this.aspectRatioOptions,
    required this.aspectRatio,
    required this.resolutionOptions,
    required this.resolution,
    required this.extendMode,
    required this.onDurationChanged,
    required this.onAspectRatioChanged,
    required this.onResolutionChanged,
    required this.onExtendModeChanged,
  });

  // [kelivo-hosted] Admin-curated per-model allowed values (see
  // `VideoDurationOptions.parse`), already expanded/sorted — this widget
  // just steps to the previous/next entry, it doesn't know or care whether
  // the admin expression was a continuous range or discrete points.
  final List<int> durationOptions;
  final int duration;
  final List<String> aspectRatioOptions;
  final String aspectRatio;
  final List<String> resolutionOptions;
  final String resolution;
  final bool extendMode;
  final ValueChanged<int>? onDurationChanged;
  final ValueChanged<String>? onAspectRatioChanged;
  final ValueChanged<String>? onResolutionChanged;
  final ValueChanged<bool>? onExtendModeChanged;

  Widget _dropdown({
    required BuildContext context,
    required String value,
    required List<String> options,
    required ValueChanged<String>? onChanged,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupMenuButton<String>(
      enabled: onChanged != null,
      initialValue: value,
      onSelected: onChanged,
      padding: EdgeInsets.zero,
      itemBuilder: (context) => [
        for (final s in options)
          PopupMenuItem<String>(value: s, child: Text(s)),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: AppFontWeights.semibold,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Lucide.ChevronDown, size: 14, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final durationIndex = durationOptions.indexOf(duration);
    final hasPrevDuration = durationIndex > 0;
    final hasNextDuration =
        durationIndex >= 0 && durationIndex < durationOptions.length - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.08,
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.chatInputBarVideoGenDurationLabel,
                    style: labelStyle,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    icon: const Icon(Lucide.Minus, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: (onDurationChanged == null || !hasPrevDuration)
                        ? null
                        : () => onDurationChanged!(
                            durationOptions[durationIndex - 1],
                          ),
                  ),
                  Text('${duration}s', style: theme.textTheme.labelMedium),
                  IconButton(
                    icon: const Icon(Lucide.Plus, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: (onDurationChanged == null || !hasNextDuration)
                        ? null
                        : () => onDurationChanged!(
                            durationOptions[durationIndex + 1],
                          ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.chatInputBarVideoGenAspectRatioLabel,
                    style: labelStyle,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _dropdown(
                    context: context,
                    value: aspectRatio,
                    options: aspectRatioOptions,
                    onChanged: onAspectRatioChanged,
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.chatInputBarVideoGenResolutionLabel,
                    style: labelStyle,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _dropdown(
                    context: context,
                    value: resolution,
                    options: resolutionOptions,
                    onChanged: onResolutionChanged,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(l10n.chatInputBarVideoExtendModeLabel, style: labelStyle),
              const SizedBox(width: AppSpacing.xs),
              IosSwitch(
                value: extendMode,
                onChanged: onExtendModeChanged,
                width: 36,
                height: 20,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.chatInputBarVideoExtendModeHint,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImageModePill extends StatelessWidget {
  const _ImageModePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = (isDark ? Colors.black : Colors.white).withValues(
      alpha: isDark ? 0.34 : 0.58,
    );
    final border = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : scheme.primary.withValues(alpha: 0.36);
    final fg = isDark ? scheme.onSurface : scheme.primary;
    final iconColor = isDark ? scheme.primaryContainer : scheme.primary;
    final radius = BorderRadius.circular(999);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: Border.all(color: border),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 172),
              child: SizedBox(
                height: 24,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 9, end: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Brush, size: 14, color: iconColor),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: fg,
                            fontWeight: AppFontWeights.semibold,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Internal data model for responsive overflow actions on desktop
class _OverflowAction {
  final double width;
  final Widget Function() builder;
  final DesktopContextMenuItem menu;
  const _OverflowAction({
    required this.width,
    required this.builder,
    required this.menu,
  });
}

// New compact button for the integrated input bar
class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    this.onTap,
    this.onLongPress,
    this.tooltip,
    this.active = false,
    this.child,
    this.childBuilder,
    this.modelIcon = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final bool active;
  final Widget? child;
  final Widget Function(Color color)? childBuilder;
  final bool modelIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fgColor = active
        ? theme.colorScheme.primary
        : (isDark ? Colors.white70 : Colors.black54);
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

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
      // Disable long press on desktop platforms
      onLongPress: isDesktop ? null : onLongPress,
      color: fgColor,
      builder: childBuilder != null
          ? (c) => SizedBox(
              width: childSize,
              height: childSize,
              child: childBuilder!(c),
            )
          : (child != null
                ? (_) => SizedBox(
                    width: childSize,
                    height: childSize,
                    child: child,
                  )
                : null),
      icon: child == null && childBuilder == null ? icon : null,
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
