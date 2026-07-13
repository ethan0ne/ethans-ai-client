import 'dart:io';
import 'package:http/http.dart' as http;
import './app_directories.dart';

/// [kelivo-hosted] Persists hosted-chat images (kelivo-arch.md 5) to a
/// local file the first time they're successfully fetched, so a message's
/// image keeps rendering even if the server later garbage-collects the
/// underlying file (e.g. retention policy) — without this, a client that
/// never re-fetches after the file is gone would show a permanently broken
/// image for something the user already saw once. Mirrors `AvatarCache`'s
/// shape (same URL-hash-keyed cache-file convention), but downloads with a
/// caller-supplied `Authorization` header, since these URLs are gated
/// behind the account's own JWT (`/__client/message-images/{id}/file`) —
/// unlike avatars, which are always unauthenticated.
class HostedImageCache {
  HostedImageCache._();

  static final Map<String, String?> _memo = <String, String?>{};

  static void clearMemory() {
    _memo.clear();
  }

  static Future<Directory> _cacheDir() async {
    return await AppDirectories.getHostedImageCacheDirectory();
  }

  static String _safeName(String url) {
    // Same 64-bit FNV-1a scheme as AvatarCache — avoids collisions from
    // common URL prefixes without needing a real hashing package.
    int h = 0xcbf29ce484222325;
    const int prime = 0x100000001b3;
    for (final c in url.codeUnits) {
      h ^= c;
      h = (h * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    final hex = h.toRadixString(16).padLeft(16, '0');
    return 'hi_$hex.img';
  }

  /// Synchronous cache peek: returns the locally cached file path for [url]
  /// only if already memoized and still present on disk. Returns null
  /// otherwise (caller should fall back to [getPath]).
  static String? peek(String url) {
    if (url.isEmpty) return null;
    final cached = _memo[url];
    if (cached == null) return null;
    try {
      if (File(cached).existsSync()) return cached;
    } catch (_) {}
    return null;
  }

  /// Ensures the image at [url] is cached locally and returns the file
  /// path. [headers] is sent with the download request only — never
  /// persisted, so nothing about the auth token ends up on disk. Returns
  /// null on failure (caller falls back to a live authenticated
  /// `NetworkImage` fetch, per kelivo-arch.md 5's existing behavior).
  static Future<String?> getPath(
    String url, {
    Map<String, String>? headers,
  }) async {
    if (url.isEmpty) return null;
    if (_memo.containsKey(url)) {
      final cached = _memo[url];
      if (cached == null) return null;
      try {
        final f = File(cached);
        if (await f.exists()) return cached;
      } catch (_) {}
      _memo.remove(url);
    }
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final name = _safeName(url);
      final file = File('${dir.path}/$name');
      if (await file.exists()) {
        _memo[url] = file.path;
        return file.path;
      }
      final res = await http.get(Uri.parse(url), headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await file.writeAsBytes(res.bodyBytes, flush: true);
        _memo[url] = file.path;
        return file.path;
      }
    } catch (_) {}
    _memo[url] = null;
    return null;
  }

  static Future<void> evict(String url) async {
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) return;
      final name = _safeName(url);
      final file = File('${dir.path}/$name');
      if (await file.exists()) await file.delete();
    } catch (_) {}
    _memo.remove(url);
  }
}
