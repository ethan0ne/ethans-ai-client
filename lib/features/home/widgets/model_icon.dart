import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../utils/brand_assets.dart';
import '../../../theme/app_font_weights.dart';

/// Widget that displays the current model's icon.
///
/// Shows either:
/// - A brand SVG/PNG icon if available for the model/provider
/// - A circular placeholder with the first letter of the model name
class CurrentModelIcon extends StatelessWidget {
  const CurrentModelIcon({
    super.key,
    required this.providerKey,
    required this.modelId,
    this.size = 28,
    this.withBackground = true,
    this.backgroundColor,
  });

  final String? providerKey;
  final String? modelId;
  final double size; // outer diameter
  final bool withBackground; // whether to draw circular background
  final Color? backgroundColor; // override background color if provided

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // [kelivo-hosted] `providerKey` is a purely BYOK-local concept (which of
    // the user's configured providers sent this) — hosted messages synced
    // in from another device (or a device that never itself sent anything
    // in the conversation) have no such value, only `modelId`
    // (backend/app/schemas/client_chat.py has no provider field to sync
    // down at all). `modelId` alone is usually enough to resolve the brand
    // icon anyway (tried first below), so only bail if that's missing too.
    if (modelId == null) return const SizedBox.shrink();

    String? asset = BrandAssets.assetForName(modelId!);
    if (asset == null && providerKey != null) {
      asset = BrandAssets.assetForName(providerKey!);
    }

    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final ColorFilter? tint =
            (Theme.of(context).brightness == Brightness.dark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.5,
          height: size * 0.5,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(
          asset,
          width: size * 0.5,
          height: size * 0.5,
          fit: BoxFit.contain,
        );
      }
    } else {
      inner = Text(
        modelId!.isNotEmpty ? modelId!.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: AppFontWeights.emphasis,
          fontSize: size * 0.43,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: withBackground
            ? (backgroundColor ??
                  (isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.1)))
            : Colors.transparent,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: size * 0.64,
        height: size * 0.64,
        child: Center(
          child: inner is SvgPicture || inner is Image
              ? inner
              : FittedBox(child: inner),
        ),
      ),
    );
  }
}
