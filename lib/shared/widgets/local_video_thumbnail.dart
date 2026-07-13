import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// First-frame thumbnail for a local video file (chat composer draft
/// previews, sent-message attachment previews) — decodes the actual file
/// with `video_player` (already a dependency, used for playing
/// hosted-generated videos via `HostedVideoPlayer`) rather than showing a
/// generic file icon, so a video attachment looks like a real preview
/// instead of a filename chip. Deliberately static (no playback controls);
/// wrap it in your own tap handler if you want one (e.g. `HostedVideoPlayer`
/// for the hosted/network case, or `OpenFilex.open` for a local file).
class LocalVideoThumbnail extends StatefulWidget {
  const LocalVideoThumbnail({
    super.key,
    required this.path,
    required this.errorFill,
  });

  final String path;
  final Color errorFill;

  @override
  State<LocalVideoThumbnail> createState() => _LocalVideoThumbnailState();
}

class _LocalVideoThumbnailState extends State<LocalVideoThumbnail> {
  VideoPlayerController? _controller;
  bool _errored = false;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.file(File(widget.path));
    controller
        .initialize()
        .then((_) {
          if (!mounted) {
            controller.dispose();
            return;
          }
          setState(() => _controller = controller);
        })
        .catchError((_) {
          controller.dispose();
          if (mounted) setState(() => _errored = true);
        });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return ColoredBox(
        color: widget.errorFill,
        child: _errored
            ? const Icon(Icons.videocam_off, color: Colors.white70, size: 22)
            : const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
        const ColoredBox(color: Color(0x33000000)),
        const Center(
          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
        ),
      ],
    );
  }
}
