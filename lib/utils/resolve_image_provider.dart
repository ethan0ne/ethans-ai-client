import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/services/api/client_backend_config.dart';
import '../core/services/api/client_backend_session.dart';
import 'hosted_image_cache.dart';
import 'sandbox_path_resolver.dart';

/// Resolves a `data:`/`http(s)://`/local-file-path image `src` string to an
/// [ImageProvider]. Shared by every place that turns a raw image URL/path
/// into something paintable — `markdown_with_highlight.dart`'s inline
/// message rendering AND `image_viewer_page.dart`'s full-size viewer, which
/// used to have its own separate, un-authenticated `NetworkImage(src)`
/// fallback that 401'd on hosted image URLs (kelivo-arch.md 5) since it
/// never attached the session JWT or checked `HostedImageCache` the way
/// this logic does. Kept as one function so the two never drift apart
/// again.
ImageProvider? resolveImageProvider(String src) {
  if (src.startsWith('http://') || src.startsWith('https://')) {
    // [kelivo-hosted] kelivo-arch.md §5 image support — the hosted backend's
    // `![image](url)` markdown (client_message_images.py's
    // `build_display_content`) points at an auth-gated endpoint, unlike
    // every other image URL a model might return (those are just public
    // links). Attach the session JWT only when the URL is actually ours —
    // sending it to an arbitrary third-party image host would leak it.
    if (src.startsWith(clientBackendBaseUrl) &&
        ClientBackendSession.token != null) {
      // Prefer an already-cached local copy so this image keeps rendering
      // even if the server later garbage-collects the underlying file
      // (retention policy) — see `HostedImageCache`. Not cached yet: fall
      // back to a live authenticated fetch for this render, and kick off
      // caching it in the background (fire-and-forget; `getPath` itself
      // checks the disk cache before re-downloading, so this is cheap once
      // cached) so the NEXT render/app-restart hits the cache instead.
      final cachedPath = HostedImageCache.peek(src);
      if (cachedPath != null) {
        return FileImage(File(cachedPath));
      }
      final headers = {'Authorization': 'Bearer ${ClientBackendSession.token}'};
      unawaited(HostedImageCache.getPath(src, headers: headers));
      return NetworkImage(src, headers: headers);
    }
    return NetworkImage(src);
  }
  if (src.startsWith('data:')) {
    try {
      final base64Marker = 'base64,';
      final idx = src.indexOf(base64Marker);
      if (idx != -1) {
        final b64 = src.substring(idx + base64Marker.length);
        return MemoryImage(base64Decode(b64));
      }
    } catch (_) {}
    return null;
  }
  final fixed = SandboxPathResolver.fix(src);
  final f = File(fixed);
  if (f.existsSync()) {
    return FileImage(f);
  }
  // Missing local file or unsupported scheme
  return null;
}
