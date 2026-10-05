import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'frosted_popup_menu.dart';

export 'frosted_popup_menu.dart' show FrostedPopupMenuItem;

/// Frosted capsule used to group related toolbar buttons.
class AppButtonIsland extends StatefulWidget {
  const AppButtonIsland({super.key, required this.children});

  final List<Widget> children;

  @override
  State<AppButtonIsland> createState() => _AppButtonIslandState();
}

/// Circular hit target inset into an [AppButtonIsland].
class AppButtonIslandButton extends StatefulWidget {
  const AppButtonIslandButton({
    super.key,
    this.icon,
    this.builder,
    this.label,
    this.labelColor,
    this.onTap,
    this.onLongPress,
    this.menuTitle,
    this.menuItems,
    this.semanticLabel,
    this.size = 24,
    this.hitPadding = const EdgeInsets.fromLTRB(2, 3, 2, 3),
  }) : assert(icon != null || builder != null || label != null);

  const AppButtonIslandButton._({
    super.key,
    required this.icon,
    required this.builder,
    required this.label,
    required this.labelColor,
    required this.onTap,
    required this.onLongPress,
    required this.menuTitle,
    required this.menuItems,
    required this.semanticLabel,
    required this.size,
    required this.hitPadding,
  });

  final IconData? icon;
  final Widget Function(Color color)? builder;
  final String? label;
  final Color? labelColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? menuTitle;
  final List<FrostedPopupMenuItem>? menuItems;
  final String? semanticLabel;
  final double size;
  final EdgeInsets hitPadding;

  AppButtonIslandButton _withHitPadding(EdgeInsets hitPadding) =>
      AppButtonIslandButton._(
        key: key,
        icon: icon,
        builder: builder,
        label: label,
        labelColor: labelColor,
        onTap: onTap,
        onLongPress: onLongPress,
        menuTitle: menuTitle,
        menuItems: menuItems,
        semanticLabel: semanticLabel,
        size: size,
        hitPadding: hitPadding,
      );

  @override
  State<AppButtonIslandButton> createState() => _AppButtonIslandButtonState();
}

class _AppButtonIslandButtonState extends State<AppButtonIslandButton> {
  final GlobalKey _menuAnchorKey = GlobalKey();
  OverlayEntry? _menuEntry;
  bool _pressed = false;
  bool _hovered = false;

  void _setPressed(bool pressed) {
    if (!mounted || _pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  void _setHovered(bool hovered) {
    if (!mounted || _hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  void _toggleMenu() {
    if (_menuEntry != null) {
      _closeMenu();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final anchorBox =
        _menuAnchorKey.currentContext!.findRenderObject()! as RenderBox;
    final anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final anchorBottomRight = anchorBox.localToGlobal(
      anchorBox.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    );
    final anchorRect = Rect.fromPoints(anchorTopLeft, anchorBottomRight);
    _menuEntry = OverlayEntry(
      builder: (_) => FrostedPopupMenu(
        anchorRect: anchorRect,
        title: widget.menuTitle ?? '',
        items: widget.menuItems ?? const <FrostedPopupMenuItem>[],
        parentRoute: ModalRoute.of(context),
        onDismiss: _closeMenu,
      ),
    );
    overlay.insert(_menuEntry!);
  }

  void _closeMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
  }

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasMenu = widget.menuItems?.isNotEmpty ?? false;
    final enabled =
        widget.onTap != null || widget.onLongPress != null || hasMenu;
    final background = !enabled
        ? Colors.transparent
        : _pressed
        ? colorScheme.onSurface.withValues(alpha: 0.15)
        : _hovered
        ? colorScheme.onSurface.withValues(alpha: 0.08)
        : Colors.transparent;
    final iconColor = colorScheme.onSurface.withValues(
      alpha: enabled ? 1 : 0.38,
    );
    final labelColor = widget.labelColor ?? colorScheme.primary;
    final labelTextColor = labelColor.withValues(alpha: enabled ? 1 : 0.38);
    final content =
        widget.builder?.call(iconColor) ??
        (widget.label == null
            ? Icon(widget.icon, size: widget.size, color: iconColor)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: widget.size, color: iconColor),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    widget.label!,
                    style: TextStyle(
                      color: labelTextColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ));

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      child: KeyedSubtree(
        key: _menuAnchorKey,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => _setPressed(true) : null,
            onTapUp: enabled
                ? (_) {
                    _setPressed(false);
                    if (hasMenu) {
                      _toggleMenu();
                    } else {
                      widget.onTap?.call();
                    }
                  }
                : null,
            onTapCancel: enabled ? () => _setPressed(false) : null,
            onLongPress: widget.onLongPress,
            child: Padding(
              padding: widget.hitPadding,
              child: AnimatedContainer(
                // Reset a previously circular container on hot reload. A
                // circle-to-rounded-rectangle decoration tween is invalid.
                key: const ValueKey('app-button-island-pill'),
                duration: const Duration(milliseconds: 150),
                width: widget.label == null ? 38 : null,
                height: 38,
                padding: widget.label == null
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppButtonIslandState extends State<AppButtonIsland> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (!mounted || _pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassFill = isDark
        ? const Color(0xCC1C1C1E)
        : const Color(0xE0FFFFFF);
    final glassBorder = isDark
        ? const Color(0x14FFFFFF)
        : const Color(0x14000000);
    final glassShadow = isDark
        ? const BoxShadow(
            color: Color(0x26000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          )
        : const BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          );
    final buttonChildren = List<Widget>.generate(widget.children.length, (
      index,
    ) {
      final child = widget.children[index];
      if (child is! AppButtonIslandButton) return child;
      return child._withHitPadding(
        EdgeInsets.fromLTRB(
          index == 0 ? 3 : 2,
          3,
          index == widget.children.length - 1 ? 3 : 2,
          3,
        ),
      );
    });
    final animationKey =
        '${widget.children.where((child) => child.key != null).map((child) => child.key).join(',')}_${widget.children.length}';
    final row = Row(mainAxisSize: MainAxisSize.min, children: buttonChildren);
    final animatedRow = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerRight,
        clipBehavior: Clip.none,
        children: [
          ...previousChildren.map(
            (previousChild) => Positioned(
              right: 0,
              top: 0,
              height: 44,
              width: 500,
              child: Align(
                alignment: Alignment.centerRight,
                child: previousChild,
              ),
            ),
          ),
          if (currentChild != null) currentChild,
        ],
      ),
      child: Semantics(
        container: true,
        child: KeyedSubtree(key: ValueKey(animationKey), child: row),
      ),
    );

    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 1.15 : 1,
        duration: Duration(milliseconds: _pressed ? 200 : 600),
        curve: _pressed ? Curves.easeOutCubic : Curves.elasticOut,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [glassShadow],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: glassFill,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: glassBorder, width: 0.75),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerRight,
                  child: animatedRow,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
