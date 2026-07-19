import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/services/api/client_backend_session.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_directories.dart';
import '../../icons/lucide_adapter.dart';
import 'snackbar.dart';

/// [kelivo-hosted] Renders an AI-generated video message file
/// (`ClientMessageFileOut` with `mime_type` starting with `video/`,
/// kelivo-arch.md video generation support) as a tap-to-play card.
///
/// Deliberately simple: no real thumbnail is generated (would need
/// decoding a frame before the file is even downloaded), just a static
/// placeholder with a play glyph — matching the "keep it simple" scope
/// this widget was asked for. The video itself is fetched on first tap
/// (authenticated with the session JWT, same as `resolveImageProvider`'s
/// hosted image fetches) into `AppDirectories.getHostedVideoCacheDirectory()`
/// and played with `video_player`; that directory is a persistent,
/// content-addressed cache (same FNV-1a naming `HostedImageCache` uses) —
/// see that getter's docstring for why it's deliberately NOT under `cache/`.
class HostedVideoPlayer extends StatefulWidget {
  const HostedVideoPlayer({
    super.key,
    required this.url,
    required this.filename,
    this.width = 240,
    this.height = 240,
  });

  final String url;
  final String filename;
  final double width;
  final double height;

  @override
  State<HostedVideoPlayer> createState() => _HostedVideoPlayerState();
}

enum _VideoLoadState { idle, loading, ready, error }

class _HostedVideoPlayerState extends State<HostedVideoPlayer> {
  _VideoLoadState _state = _VideoLoadState.idle;
  VideoPlayerController? _controller;
  File? _localFile;
  bool _saving = false;
  // Determinate download progress (0..1), null while the server hasn't sent
  // a Content-Length yet or the file is already cached locally — falls back
  // to an indeterminate spinner in that case, same as before this was added.
  double? _downloadProgress;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _safeName(String url) {
    // Same FNV-1a scheme `HostedImageCache` uses, kept local since this
    // cache is intentionally scratch-only (not shared with the image
    // cache's retention/eviction lifecycle).
    int h = 0xcbf29ce484222325;
    const int prime = 0x100000001b3;
    for (final c in url.codeUnits) {
      h ^= c;
      h = (h * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return 'hv_${h.toRadixString(16).padLeft(16, '0')}.mp4';
  }

  Future<void> _startPlayback() async {
    if (_state == _VideoLoadState.loading) return;
    setState(() {
      _state = _VideoLoadState.loading;
      _downloadProgress = null;
    });
    try {
      final dir = await AppDirectories.getHostedVideoCacheDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/${_safeName(widget.url)}');
      if (!await file.exists()) {
        final token = ClientBackendSession.token;
        final headers = token != null
            ? {'Authorization': 'Bearer $token'}
            : null;
        final request = http.Request('GET', Uri.parse(widget.url));
        if (headers != null) request.headers.addAll(headers);
        final streamed = await http.Client().send(request);
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          throw HttpException('HTTP ${streamed.statusCode}');
        }
        final total = streamed.contentLength;
        final sink = file.openWrite();
        var received = 0;
        await for (final chunk in streamed.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        }
        await sink.close();
      }
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.addListener(() {
        if (mounted) setState(() {});
      });
      setState(() {
        _controller = controller;
        _localFile = file;
        _state = _VideoLoadState.ready;
      });
      await controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _VideoLoadState.error);
    }
  }

  Future<void> _saveToGallery() async {
    final file = _localFile;
    if (file == null || _saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await ImageGallerySaverPlus.saveFile(
        file.path,
        name: 'kelivo-${DateTime.now().millisecondsSinceEpoch}',
      );
      bool success = false;
      if (result is Map) {
        final isSuccess =
            result['isSuccess'] == true || result['isSuccess'] == 1;
        final filePath = result['filePath'] ?? result['file_path'];
        success = isSuccess || (filePath is String && filePath.isNotEmpty);
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: success
            ? l10n.hostedVideoPlayerDownloadSuccess
            : l10n.hostedVideoPlayerDownloadFailed('unknown'),
        type: success ? NotificationType.success : NotificationType.error,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.hostedVideoPlayerDownloadFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget content;
    switch (_state) {
      case _VideoLoadState.ready:
        final controller = _controller!;
        content = AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 16 / 9
              : controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              _PlaybackControls(controller: controller),
              PositionedDirectional(
                top: 8,
                end: 8,
                child: _DownloadButton(
                  saving: _saving,
                  onTap: _saveToGallery,
                  tooltip: l10n.hostedVideoPlayerDownload,
                ),
              ),
            ],
          ),
        );
        break;
      case _VideoLoadState.loading:
        content = SizedBox(
          width: widget.width,
          height: widget.height,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  strokeWidth: 2.5,
                  value: _downloadProgress,
                ),
                const SizedBox(height: 8),
                Text(
                  _downloadProgress != null
                      ? l10n.hostedVideoPlayerLoadingProgress(
                          (_downloadProgress! * 100).round(),
                        )
                      : l10n.hostedVideoPlayerLoading,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
        break;
      case _VideoLoadState.error:
        content = SizedBox(
          width: widget.width,
          height: widget.height,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Lucide.CircleAlert, color: cs.error, size: 28),
                const SizedBox(height: 8),
                Text(
                  l10n.hostedVideoPlayerError,
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.error),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _startPlayback,
                  child: Text(l10n.hostedVideoPlayerRetry),
                ),
              ],
            ),
          ),
        );
        break;
      case _VideoLoadState.idle:
        content = SizedBox(
          width: widget.width,
          height: widget.height,
          child: Center(
            child: Semantics(
              button: true,
              label: l10n.hostedVideoPlayerPlay,
              child: Icon(Lucide.Play, size: 40, color: cs.onSurfaceVariant),
            ),
          ),
        );
        break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: GestureDetector(
          onTap: _state == _VideoLoadState.idle ? _startPlayback : null,
          child: content,
        ),
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final isPlaying = controller.value.isPlaying;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (isPlaying) {
                controller.pause();
              } else {
                controller.play();
              }
            },
            child: AnimatedOpacity(
              opacity: isPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.25),
                child: Center(
                  child: Icon(
                    isPlaying ? Lucide.Pause : Lucide.Play,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          start: 0,
          end: 0,
          bottom: 0,
          child: VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            padding: const EdgeInsets.all(6),
          ),
        ),
      ],
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    required this.saving,
    required this.onTap,
    required this.tooltip,
  });

  final bool saving;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: saving ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Lucide.Download, color: Colors.white, size: 16),
          ),
        ),
      ),
    );
  }
}
