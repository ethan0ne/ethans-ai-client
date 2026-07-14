import 'package:flutter/foundation.dart';

enum ModelType { chat, image, video, embedding }

enum Modality { text, image }

enum ModelAbility { tool, reasoning }

@immutable
class ModelInfo {
  final String id;
  final String displayName;
  final ModelType type;
  final List<Modality> input;
  final List<Modality> output;
  final List<ModelAbility> abilities;
  // Admin-curated `/v1/images/generations` `size` values this model
  // accepts (only meaningful when `type == ModelType.image`) — empty means
  // no server-side preset, callers fall back to a built-in default list.
  final List<String> imageSizes;
  // [kelivo-hosted] Admin-curated video generation option presets (only
  // meaningful when `type == ModelType.video`), same "empty means fall back
  // to a built-in default" contract as `imageSizes`. `videoDurations` is a
  // raw comma-separated expression mixing continuous ranges ("6-15") and
  // discrete points ("30") — see `VideoDurationOptions.parse`, the only
  // place that interprets this string; every other caller should treat it
  // as an opaque value straight from the admin catalog.
  final String videoDurations;
  final List<String> videoResolutions;
  final List<String> videoAspectRatios;
  // [kelivo-hosted] Admin-curated duration preset for `/v1/videos/extensions`
  // specifically (continuing an existing video) — a separate range from
  // `videoDurations` (which governs `/v1/videos/generations`), since the two
  // endpoints have different default/allowed ranges. Same opaque
  // raw-expression contract as `videoDurations`.
  final String videoExtendDurations;

  static List<Modality> _normalizeModalities(Iterable<Modality> mods) {
    final set = <Modality>{...mods};
    final list = set.toList()..sort((a, b) => a.index.compareTo(b.index));
    return List.unmodifiable(list);
  }

  static List<ModelAbility> _normalizeAbilities(Iterable<ModelAbility> abs) {
    final set = <ModelAbility>{...abs};
    final list = set.toList()..sort((a, b) => a.index.compareTo(b.index));
    return List.unmodifiable(list);
  }

  ModelInfo({
    required this.id,
    required this.displayName,
    this.type = ModelType.chat,
    List<Modality> input = const [Modality.text],
    List<Modality> output = const [Modality.text],
    List<ModelAbility> abilities = const [],
    this.imageSizes = const [],
    this.videoDurations = '',
    this.videoResolutions = const [],
    this.videoAspectRatios = const [],
    this.videoExtendDurations = '',
  }) : input = _normalizeModalities(input),
       output = _normalizeModalities(output),
       abilities = _normalizeAbilities(abilities);

  ModelInfo copyWith({
    String? id,
    String? displayName,
    ModelType? type,
    List<Modality>? input,
    List<Modality>? output,
    List<ModelAbility>? abilities,
    List<String>? imageSizes,
    String? videoDurations,
    List<String>? videoResolutions,
    List<String>? videoAspectRatios,
    String? videoExtendDurations,
  }) {
    return ModelInfo(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      type: type ?? this.type,
      input: input ?? this.input,
      output: output ?? this.output,
      abilities: abilities ?? this.abilities,
      imageSizes: imageSizes ?? this.imageSizes,
      videoDurations: videoDurations ?? this.videoDurations,
      videoResolutions: videoResolutions ?? this.videoResolutions,
      videoAspectRatios: videoAspectRatios ?? this.videoAspectRatios,
      videoExtendDurations: videoExtendDurations ?? this.videoExtendDurations,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ModelInfo &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            displayName == other.displayName &&
            type == other.type &&
            listEquals(input, other.input) &&
            listEquals(output, other.output) &&
            listEquals(abilities, other.abilities) &&
            listEquals(imageSizes, other.imageSizes) &&
            videoDurations == other.videoDurations &&
            listEquals(videoResolutions, other.videoResolutions) &&
            listEquals(videoAspectRatios, other.videoAspectRatios) &&
            videoExtendDurations == other.videoExtendDurations);
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    type,
    Object.hashAll(imageSizes),
    videoDurations,
    Object.hashAll(videoResolutions),
    Object.hashAll(videoAspectRatios),
    videoExtendDurations,
    Object.hashAll(input),
    Object.hashAll(output),
    Object.hashAll(abilities),
  );
}
