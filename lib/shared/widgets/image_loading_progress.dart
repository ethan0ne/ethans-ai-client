import 'package:flutter/material.dart';

/// Shared `Image.loadingBuilder` for every hosted/network image thumbnail
/// in the chat surface (chat bubble attachments, inline markdown images).
/// Kept as one function so they don't drift into slightly different
/// "loading" looks — see `chat_message_widget.dart` and
/// `markdown_with_highlight.dart` for the two call sites.
///
/// [ImageChunkEvent.expectedTotalBytes] is only populated when the
/// underlying `ImageProvider` is a `NetworkImage` (or something else that
/// reports chunk events) AND the server sent a `Content-Length` header —
/// `FileImage`/`MemoryImage` (already-local/decoded images) skip this
/// builder's "loading" frame entirely, so this only ever shows for an
/// actual in-flight network fetch.
Widget imageLoadingBuilder(
  BuildContext context,
  Widget child,
  ImageChunkEvent? loadingProgress, {
  double size = 22,
  double strokeWidth = 2,
  // When set, fills the whole loading frame with this color so the
  // indicator reads as "a placeholder the size of the final image", not a
  // bare spinner floating over nothing — see chat_message_widget.dart's
  // attachment thumbnail call site, which passes the same color it uses for
  // its errorBuilder placeholder so loading/error states look consistent.
  Color? placeholderColor,
}) {
  if (loadingProgress == null) return child;
  final total = loadingProgress.expectedTotalBytes;
  final value = total != null && total > 0
      ? loadingProgress.cumulativeBytesLoaded / total
      : null;
  final indicator = Center(
    child: SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: strokeWidth, value: value),
    ),
  );
  if (placeholderColor == null) return indicator;
  return ColoredBox(color: placeholderColor, child: indicator);
}
