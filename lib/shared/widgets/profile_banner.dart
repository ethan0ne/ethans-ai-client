import 'package:flutter/material.dart';

import '../../icons/lucide_adapter.dart';
import '../../theme/app_font_weights.dart';
import 'ios_tactile.dart';

/// Centered profile identity header with optional avatar and name actions.
///
/// The avatar widget is clipped to a circle and constrained to [avatarSize].
/// Callbacks are optional so the same layout can be used as a display-only
/// profile header.
class ProfileBanner extends StatelessWidget {
  const ProfileBanner({
    super.key,
    required this.avatar,
    required this.name,
    this.subtitle,
    this.onAvatarTap,
    this.onEditTap,
    this.avatarSemanticLabel,
    this.editSemanticLabel,
    this.avatarSize = 80,
    this.avatarNameSpacing = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.nameStyle,
  });

  final Widget avatar;
  final String name;
  final String? subtitle;
  final ValueChanged<BuildContext>? onAvatarTap;
  final VoidCallback? onEditTap;
  final String? avatarSemanticLabel;
  final String? editSemanticLabel;
  final double avatarSize;
  final double avatarNameSpacing;
  final EdgeInsetsGeometry padding;
  final TextStyle? nameStyle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolvedSubtitle = subtitle?.trim();
    final avatarTap = onAvatarTap;
    final avatarView = avatarTap == null
        ? SizedBox.square(
            dimension: avatarSize,
            child: ClipOval(child: avatar),
          )
        : _ProfileBannerAvatarAction(
            avatar: avatar,
            size: avatarSize,
            semanticLabel: avatarSemanticLabel,
            onTap: avatarTap,
          );

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          avatarView,
          SizedBox(height: avatarNameSpacing),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style:
                      nameStyle ??
                      Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: cs.onSurface,
                        fontWeight: AppFontWeights.medium,
                      ),
                ),
              ),
              if (onEditTap != null) ...[
                const SizedBox(width: 6),
                IosIconButton(
                  icon: Lucide.Pencil,
                  size: 19,
                  padding: const EdgeInsets.all(4),
                  minSize: 40,
                  color: cs.onSurface.withValues(alpha: 0.62),
                  semanticLabel: editSemanticLabel,
                  onTap: onEditTap,
                ),
              ],
            ],
          ),
          if (resolvedSubtitle != null && resolvedSubtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              resolvedSubtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileBannerAvatarAction extends StatefulWidget {
  const _ProfileBannerAvatarAction({
    required this.avatar,
    required this.size,
    required this.onTap,
    this.semanticLabel,
  });

  final Widget avatar;
  final double size;
  final ValueChanged<BuildContext> onTap;
  final String? semanticLabel;

  @override
  State<_ProfileBannerAvatarAction> createState() =>
      _ProfileBannerAvatarActionState();
}

class _ProfileBannerAvatarActionState
    extends State<_ProfileBannerAvatarAction> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (avatarContext) => Semantics(
        button: true,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: () => widget.onTap(avatarContext),
          child: SizedBox.square(
            dimension: widget.size,
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.avatar,
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _pressed ? 0.18 : 0,
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      child: const ColoredBox(color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
