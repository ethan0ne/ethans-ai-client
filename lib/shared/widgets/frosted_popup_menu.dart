import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const double _menuInset = 10;
const double _menuInnerCornerRadius = 14;
const double _menuOuterCornerRadius = _menuInnerCornerRadius + _menuInset;

class FrostedPopupMenuItem {
  const FrostedPopupMenuItem({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.dividerAfter = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
  final bool dividerAfter;
}

/// Frosted popup menu positioned relative to a captured anchor rectangle.
class FrostedPopupMenu extends StatefulWidget {
  const FrostedPopupMenu({
    super.key,
    required this.anchorRect,
    required this.title,
    required this.items,
    required this.onDismiss,
  });

  final Rect anchorRect;
  final String title;
  final List<FrostedPopupMenuItem> items;
  final VoidCallback onDismiss;

  @override
  State<FrostedPopupMenu> createState() => _FrostedPopupMenuState();
}

class _FrostedPopupMenuState extends State<FrostedPopupMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _scale = Tween<double>(begin: 0.88, end: 1).animate(curved);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _controller.forward();
  }

  void _dismiss({VoidCallback? afterDismiss}) {
    if (_dismissing) return;
    _dismissing = true;
    _controller.reverse().whenComplete(() {
      if (!mounted) return;
      widget.onDismiss();
      afterDismiss?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final menuWidth = (screenWidth - 24).clamp(0.0, 280.0).toDouble();
    final left = (widget.anchorRect.right - menuWidth).clamp(
      12.0,
      screenWidth - menuWidth - 12,
    );
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassFill = isDark
        ? const Color(0xD91C1C1E)
        : const Color(0xD9FFFFFF);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: left,
          top: widget.anchorRect.bottom + 8,
          child: FadeTransition(
            opacity: _opacity,
            child: ScaleTransition(
              scale: _scale,
              alignment: Alignment.topRight,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_menuOuterCornerRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.24 : 0.12,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_menuOuterCornerRadius),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Material(
                      color: Colors.transparent,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: glassFill),
                        child: SizedBox(
                          width: menuWidth,
                          child: Padding(
                            padding: const EdgeInsets.all(_menuInset),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    0,
                                    14,
                                    6,
                                  ),
                                  child: Text(
                                    widget.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.68,
                                      ),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                for (final item in widget.items) ...[
                                  _FrostedPopupMenuRow(
                                    item: item,
                                    onPressed: () =>
                                        _dismiss(afterDismiss: item.onPressed),
                                  ),
                                  if (item.dividerAfter)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      child: Divider(
                                        height: 1,
                                        thickness: 0.75,
                                        color: colorScheme.outlineVariant
                                            .withValues(alpha: 0.16),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FrostedPopupMenuRow extends StatefulWidget {
  const _FrostedPopupMenuRow({required this.item, required this.onPressed});

  final FrostedPopupMenuItem item;
  final VoidCallback onPressed;

  @override
  State<_FrostedPopupMenuRow> createState() => _FrostedPopupMenuRowState();
}

class _FrostedPopupMenuRowState extends State<_FrostedPopupMenuRow> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = widget.item.destructive
        ? Colors.red.shade600
        : colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: widget.item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          decoration: BoxDecoration(
            color: _pressed
                ? (isDark
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.18))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(_menuInnerCornerRadius),
          ),
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(widget.item.icon, size: 18, color: foreground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foreground, fontSize: 14),
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
