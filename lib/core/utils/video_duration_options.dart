/// [kelivo-hosted] Parses an admin-curated video-duration expression
/// (`ModelInfo.videoDurations`, e.g. "6-15,30,40") into a sorted,
/// deduplicated list of allowed whole-second values — the composer's
/// duration stepper (chat_input_bar.dart) steps through this list instead of
/// a plain min/max range, since the admin field mixes continuous ranges and
/// discrete points in one expression.
abstract final class VideoDurationOptions {
  VideoDurationOptions._();

  // Guards a typo'd huge range (e.g. "1-100000") from expanding into an
  // unusably long list — video durations are always small integers in
  // practice, so this is generous headroom, not a real limit.
  static const int _maxExpandedValues = 200;

  static final RegExp _rangeToken = RegExp(r'^(\d+)-(\d+)$');
  static final RegExp _pointToken = RegExp(r'^\d+$');

  /// Malformed tokens are skipped rather than failing the whole parse,
  /// matching `image_sizes`'/`ClientModelInfo`'s "advisory, not validated
  /// server-side" contract — a stray typo degrades gracefully instead of
  /// breaking the composer.
  static List<int> parse(String expr) {
    final values = <int>{};
    for (final raw in expr.split(',')) {
      final token = raw.trim();
      if (token.isEmpty) continue;
      final range = _rangeToken.firstMatch(token);
      if (range != null) {
        final lo = int.parse(range.group(1)!);
        final hi = int.parse(range.group(2)!);
        if (lo > hi) continue;
        for (int v = lo; v <= hi && values.length < _maxExpandedValues; v++) {
          values.add(v);
        }
        continue;
      }
      if (_pointToken.hasMatch(token)) {
        values.add(int.parse(token));
      }
    }
    final list = values.toList()..sort();
    return list;
  }
}
