import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

const double _menuInset = 8;
const double _menuItemHeight = 40;
const double _menuInfoItemHeight = 26;
const double _menuInnerCornerRadius = 14;
const double _menuOuterCornerRadius = _menuInnerCornerRadius + _menuInset;
const double _parentMenuScale = 0.96;
const Duration _menuResizeDuration = Duration(milliseconds: 280);
// Retain the opening timing with only a slight overshoot at the end.
const Curve _menuOpeningCurve = Cubic(0.175, 0.885, 0.32, 1.04);

class FrostedPopupMenuItem {
  const FrostedPopupMenuItem({
    required this.icon,
    required this.label,
    this.onPressed,
    this.onPressedAsync,
    this.onLongPress,
    this.children = const [],
    this.description,
    this.trailingLabel,
    this.destructive = false,
    this.dividerAfter = false,
    this.isStatic = false,
    this.isOption = false,
    this.selected = false,
    this.dismissOnSelect = true,
    this.compact = false,
    this.emphasized = false,
    this.customContent,
    this.customHeight,
  }) : assert(
         customContent != null
             ? onPressed == null &&
                   onPressedAsync == null &&
                   onLongPress == null &&
                   children.length == 0 &&
                   customHeight != null
             : isStatic
             ? onPressed == null &&
                   onPressedAsync == null &&
                   children.length == 0 &&
                   customHeight == null
             : (onPressed != null ||
                       onPressedAsync != null ||
                       children.length > 0) &&
                   customHeight == null,
       );

  const FrostedPopupMenuItem.info({
    required this.label,
    this.dividerAfter = false,
    this.emphasized = false,
  }) : icon = null,
       onPressed = null,
       onPressedAsync = null,
       onLongPress = null,
       children = const [],
       description = null,
       trailingLabel = null,
       destructive = false,
       isStatic = true,
       isOption = false,
       selected = false,
       dismissOnSelect = true,
       compact = false,
       customContent = null,
       customHeight = null;

  /// Embeds directly interactive content (for example, a switch or text field)
  /// in a menu row. The embedded controls keep the menu open while they work.
  const FrostedPopupMenuItem.custom({
    required this.label,
    required Widget content,
    required double height,
    this.dividerAfter = false,
  }) : icon = null,
       onPressed = null,
       onPressedAsync = null,
       onLongPress = null,
       children = const [],
       description = null,
       trailingLabel = null,
       destructive = false,
       isStatic = false,
       isOption = false,
       selected = false,
       dismissOnSelect = true,
       compact = false,
       emphasized = false,
       customContent = content,
       customHeight = height;

  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final Future<void> Function()? onPressedAsync;
  final VoidCallback? onLongPress;

  /// Child actions open within this menu and retain this item as the header.
  final List<FrostedPopupMenuItem> children;
  final String? description;

  /// Secondary neutral status text shown before the submenu chevron.
  final String? trailingLabel;
  final bool destructive;
  final bool dividerAfter;

  /// Informational row that is visible but cannot be selected.
  final bool isStatic;

  /// Marks this row as a radio/checkbox option and reserves a check column.
  final bool isOption;

  /// Whether this option is currently selected.
  final bool selected;

  /// Whether selecting this item closes the menu. Defaults to true.
  final bool dismissOnSelect;

  /// Reduces a standard row's vertical space while preserving its content.
  final bool compact;

  /// Gives an informational row stronger text weight for group headings.
  final bool emphasized;

  /// Interactive content rendered directly inside a menu row.
  final Widget? customContent;

  /// Height reserved for [customContent].
  final double? customHeight;
}

double _menuRowHeight(FrostedPopupMenuItem item, {String? description}) {
  if (item.customContent != null) return item.customHeight!;
  if (item.isStatic) return _menuInfoItemHeight;
  final height = _menuItemHeight + (description == null ? 0 : 24);
  final compactReduction = description == null ? 4 : 8;
  return item.compact
      ? math.max(_menuItemHeight - 4, height - compactReduction)
      : height;
}

/// Resolves an on-screen point for a popup menu when a caller does not have a
/// gesture position. Prefer passing the original pointer position when one is
/// available.
Offset popupMenuAnchorForContext(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize) {
    return box.localToGlobal(box.size.center(Offset.zero));
  }
  final size = MediaQuery.sizeOf(context);
  return Offset(size.width / 2, size.height / 2);
}

Future<void> showFrostedPopupMenuAt(
  BuildContext context, {
  Offset? globalPosition,
  Rect? globalAnchorRect,
  String title = '',
  required List<FrostedPopupMenuItem> items,
  List<FrostedPopupMenuItem> Function()? itemsBuilder,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
  if (overlay == null || overlayBox == null) return Future<void>.value();

  if (globalAnchorRect == null && globalPosition == null) {
    throw ArgumentError('Provide either globalAnchorRect or globalPosition.');
  }
  final Rect anchorRect;
  if (globalAnchorRect == null) {
    final anchorPosition = overlayBox.globalToLocal(globalPosition!);
    anchorRect = Rect.fromLTWH(anchorPosition.dx, anchorPosition.dy, 0, 0);
  } else {
    anchorRect = Rect.fromPoints(
      overlayBox.globalToLocal(globalAnchorRect.topLeft),
      overlayBox.globalToLocal(globalAnchorRect.bottomRight),
    );
  }
  final dismissed = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => FrostedPopupMenu(
      anchorRect: anchorRect,
      title: title,
      items: items,
      itemsBuilder: itemsBuilder,
      parentRoute: ModalRoute.of(context),
      onDismiss: () {
        entry.remove();
        if (!dismissed.isCompleted) dismissed.complete();
      },
      onActionSelected: (action) {
        try {
          action();
        } finally {
          if (!dismissed.isCompleted) dismissed.complete();
        }
      },
      onAsyncActionSelected: (action) {
        try {
          unawaited(action());
        } finally {
          if (!dismissed.isCompleted) dismissed.complete();
        }
      },
    ),
  );
  overlay.insert(entry);
  return dismissed.future;
}

/// Frosted popup menu positioned relative to a captured anchor rectangle.
class FrostedPopupMenu extends StatefulWidget {
  const FrostedPopupMenu({
    super.key,
    required this.anchorRect,
    required this.title,
    required this.items,
    this.itemsBuilder,
    required this.onDismiss,
    required this.onActionSelected,
    this.onAsyncActionSelected,
    this.parentRoute,
  });

  final Rect anchorRect;
  final String title;
  final List<FrostedPopupMenuItem> items;
  final List<FrostedPopupMenuItem> Function()? itemsBuilder;
  final VoidCallback onDismiss;
  final ValueChanged<VoidCallback> onActionSelected;
  final ValueChanged<Future<void> Function()>? onAsyncActionSelected;
  final ModalRoute<dynamic>? parentRoute;

  @override
  State<FrostedPopupMenu> createState() => _FrostedPopupMenuState();
}

class _FrostedMenuLevel {
  _FrostedMenuLevel({
    required this.items,
    this.title = '',
    this.parentItem,
    this.parentIndex,
    this.sourceRect,
    this.parentRect,
  }) : rowKeys = List.generate(items.length, (_) => GlobalKey());

  List<FrostedPopupMenuItem> items;
  final String title;
  FrostedPopupMenuItem? parentItem;
  final int? parentIndex;
  final Rect? sourceRect;
  final Rect? parentRect;
  List<GlobalKey> rowKeys;
  final ScrollController scrollController = ScrollController();

  void updateItems(List<FrostedPopupMenuItem> newItems) {
    items = newItems;
    rowKeys = List.generate(newItems.length, (_) => GlobalKey());
  }
}

class _FrostedMenuLayout {
  const _FrostedMenuLayout(this.rect, this.alignment);
  final Rect rect;
  final Alignment alignment;
}

class _FrostedPopupMenuState extends State<FrostedPopupMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final GlobalKey _overlayKey = GlobalKey();
  final List<_FrostedMenuLevel> _levels = [];
  final List<_FrostedMenuLevel> _createdLevels = [];
  LocalHistoryEntry? _historyEntry;
  bool _dismissing = false;
  bool _navigating = false;
  bool _returning = false;
  bool _backPending = false;
  int _navigation = 0;
  Rect? _currentRect;
  Rect? _outgoingRect;
  Rect? _outgoingTargetRect;
  int _returnDepth = 1;
  _FrostedMenuLevel? _outgoing;
  Offset? _rootAnchor;
  Offset? _dismissAnchor;
  double _navigationProgress = 1;
  double _dismissNavigationProgress = 1;

  @override
  void initState() {
    super.initState();
    final root = _FrostedMenuLevel(items: widget.items, title: widget.title);
    _levels.add(root);
    _createdLevels.add(root);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 335),
      reverseDuration: const Duration(milliseconds: 335),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerBack());
  }

  void _registerBack() {
    if (!mounted || _dismissing || _historyEntry != null) return;
    final route = widget.parentRoute;
    if (route == null) return;
    _historyEntry = LocalHistoryEntry(
      impliesAppBarDismissal: false,
      onRemove: () {
        _historyEntry = null;
        if (!mounted || _dismissing) return;
        if (_navigating) {
          _backPending = true;
        } else if (_levels.length > 1) {
          _goBack();
        } else {
          _dismiss();
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _registerBack());
      },
    );
    route.addLocalHistoryEntry(_historyEntry!);
  }

  void _dismiss() {
    if (_dismissing) return;
    setState(() {
      _dismissAnchor = _rootAnchor;
      _dismissNavigationProgress = _navigationProgress;
      _dismissing = true;
    });
    _historyEntry?.remove();
    _historyEntry = null;
    _controller.reverse().whenComplete(() {
      if (!mounted) return;
      widget.onDismiss();
    });
  }

  void _invokeActionAndDismiss(VoidCallback action) {
    // Dispatch the selected work before starting the exit animation so route,
    // picker, and provider responses begin on the tap itself.
    try {
      widget.onActionSelected(action);
    } finally {
      _dismiss();
    }
  }

  void _invokeAsyncActionAndDismiss(Future<void> Function() action) {
    // Start async work on the tap before the menu's exit animation.
    try {
      final dispatch = widget.onAsyncActionSelected;
      if (dispatch == null) {
        unawaited(action());
      } else {
        dispatch(action);
      }
    } finally {
      _dismiss();
    }
  }

  Future<void> _invokePersistentAsyncAction(
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } finally {
      if (mounted && !_dismissing) _refreshItems();
    }
  }

  void _refreshItems() {
    final itemsBuilder = widget.itemsBuilder;
    if (itemsBuilder == null) {
      setState(() {});
      return;
    }

    final rootItems = itemsBuilder();
    setState(() {
      _levels.first.updateItems(rootItems);
      for (var depth = 1; depth < _levels.length; depth++) {
        final level = _levels[depth];
        final parentIndex = level.parentIndex;
        if (parentIndex == null ||
            parentIndex >= _levels[depth - 1].items.length) {
          break;
        }
        final parent = _levels[depth - 1].items[parentIndex];
        if (parent.children.isEmpty) break;
        level.parentItem = parent;
        level.updateItems(parent.children);
      }
    });
  }

  void _select(_FrostedMenuLevel level, int index) {
    if (_navigating || _dismissing) return;
    final item = level.items[index];
    if (item.isStatic || item.customContent != null) return;
    if (item.children.isEmpty) {
      final action = item.onPressed;
      final asyncAction = item.onPressedAsync;
      if (action == null && asyncAction == null) return;
      if (!item.dismissOnSelect) {
        if (asyncAction != null) {
          unawaited(_invokePersistentAsyncAction(asyncAction));
        } else {
          action!();
          _refreshItems();
        }
      } else if (asyncAction != null) {
        _invokeAsyncActionAndDismiss(asyncAction);
      } else {
        _invokeActionAndDismiss(action!);
      }
      return;
    }
    final rowBox =
        level.rowKeys[index].currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (rowBox == null || overlayBox == null || _currentRect == null) return;
    final rowRect = Rect.fromPoints(
      rowBox.localToGlobal(Offset.zero, ancestor: overlayBox),
      rowBox.localToGlobal(
        rowBox.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );
    // The child header starts at the actual selected row, including after scroll.
    final sourceRect = Rect.fromLTWH(
      _currentRect!.left,
      rowRect.top - _menuInset,
      _currentRect!.width,
      rowRect.height + _menuInset * 2,
    );
    final child = _FrostedMenuLevel(
      items: item.children,
      parentItem: item,
      parentIndex: index,
      sourceRect: sourceRect,
      parentRect: _currentRect,
    );
    setState(() {
      _outgoing = null;
      _outgoingRect = null;
      _levels.add(child);
      _createdLevels.add(child);
      _navigating = true;
      _returning = false;
      _navigation++;
    });
  }

  void _selectLongPress(_FrostedMenuLevel level, int index) {
    if (_navigating || _dismissing) return;
    final item = level.items[index];
    final action = item.onLongPress;
    if (item.isStatic || item.customContent != null || action == null) return;
    _invokeActionAndDismiss(action);
  }

  void _goBack() {
    if (_navigating || _dismissing || _levels.length < 2) return;
    _returnToLevel(_levels.length - 2, targetRect: _levels.last.sourceRect);
  }

  void _returnToLevel(int index, {Rect? targetRect}) {
    if (_navigating ||
        _dismissing ||
        index < 0 ||
        index >= _levels.length - 1) {
      return;
    }
    setState(() {
      _outgoing = _levels.last;
      _outgoingRect = _currentRect;
      _outgoingTargetRect =
          targetRect ??
          _levels[index + 1].sourceRect ??
          _levels[index + 1].parentRect;
      _returnDepth = _levels.length - index - 1;
      _levels.removeRange(index + 1, _levels.length);
      _navigating = true;
      _returning = true;
      _navigation++;
    });
  }

  void _finishNavigation() {
    if (!mounted || _dismissing) return;
    setState(() {
      _navigating = false;
      _outgoing = null;
      _outgoingRect = null;
      _outgoingTargetRect = null;
    });
    if (_backPending) {
      _backPending = false;
      if (_levels.length > 1) {
        _goBack();
      } else {
        _dismiss();
      }
    }
  }

  @override
  void dispose() {
    _dismissing = true;
    _historyEntry?.remove();
    for (final level in _createdLevels) {
      level.scrollController.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  double _desiredHeight(_FrostedMenuLevel level) =>
      _menuInset * 2 +
      level.items.fold<double>(
        0,
        (height, item) =>
            height + _menuRowHeight(item, description: item.description),
      ) +
      level.items
              .take(math.max(0, level.items.length - 1))
              .where((item) => item.dividerAfter)
              .length *
          13 +
      (level.parentItem != null
          ? _menuItemHeight + 13
          : level.title.isEmpty
          ? 0
          : 40);

  _FrostedMenuLayout _layout(
    MediaQueryData mediaQuery,
    _FrostedMenuLevel level,
  ) {
    final screenWidth = mediaQuery.size.width;
    final leftInset = math.max(12.0, mediaQuery.padding.left + 8);
    final rightInset = math.max(12.0, mediaQuery.padding.right + 8);
    final menuWidth = (screenWidth - leftInset - rightInset)
        .clamp(0.0, 280.0)
        .toDouble();
    final visibleBottom =
        mediaQuery.size.height -
        math.max(mediaQuery.padding.bottom, mediaQuery.viewInsets.bottom);
    final desiredHeight = _desiredHeight(level);
    if (level.sourceRect != null) {
      final source = level.sourceRect!;
      final topInset = mediaQuery.padding.top + 8;
      final bottom = visibleBottom - 8;
      final height = math.min(desiredHeight, math.max(0.0, bottom - topInset));
      // With room below, align the submenu header to the selected row.
      // Otherwise expand upward from that row, within the available bounds.
      final parentTop = level.parentRect!.top;
      final preferredTop =
          parentTop + (source.top - parentTop) * _parentMenuScale;
      final fitsBelow = preferredTop + desiredHeight <= bottom;
      final top =
          (fitsBelow
                  ? preferredTop
                  : math.min(source.bottom - height, bottom - height))
              .clamp(topInset, math.max(topInset, bottom - height))
              .toDouble();
      final left = source.left
          .clamp(leftInset, screenWidth - rightInset - menuWidth)
          .toDouble();
      return _FrostedMenuLayout(
        Rect.fromLTWH(left, top, menuWidth, height),
        fitsBelow ? Alignment.topCenter : Alignment.bottomCenter,
      );
    }
    final rightRoom = screenWidth - rightInset - widget.anchorRect.left;
    final leftRoom = widget.anchorRect.right - leftInset;
    final requestedLeft = rightRoom >= menuWidth || rightRoom >= leftRoom
        ? widget.anchorRect.left
        : widget.anchorRect.right - menuWidth;
    final left = requestedLeft
        .clamp(leftInset, screenWidth - menuWidth - rightInset)
        .toDouble();
    final anchorX = widget.anchorRect.center.dx
        .clamp(left, left + menuWidth)
        .toDouble();
    final alignmentX = menuWidth == 0
        ? 0.0
        : ((anchorX - left) / menuWidth * 2 - 1).clamp(-1.0, 1.0).toDouble();
    final placementAnchorTop = math.min(
      widget.anchorRect.top,
      visibleBottom - 8,
    );
    final below = math.max(0.0, visibleBottom - widget.anchorRect.bottom - 8);
    final above = math.max(
      0.0,
      placementAnchorTop - mediaQuery.padding.top - 8,
    );
    final placeAbove = below < desiredHeight && above > below;
    final height = math.min(desiredHeight, placeAbove ? above : below);
    final top = placeAbove
        ? placementAnchorTop - height - 8
        : widget.anchorRect.bottom + 8;
    return _FrostedMenuLayout(
      Rect.fromLTWH(left, top, menuWidth, height),
      Alignment(alignmentX, placeAbove ? 1 : -1),
    );
  }

  Widget _divider(ColorScheme colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Divider(
      height: 1,
      thickness: 0.75,
      color: colors.outlineVariant.withValues(alpha: 0.16),
    ),
  );

  double _ancestorScale(int depth, double progress) => math
      .pow(_parentMenuScale, depth + (_returning ? 1 - progress : progress - 1))
      .toDouble();

  Widget _content(_FrostedMenuLevel level, ColorScheme colors, double reveal) =>
      Padding(
        padding: const EdgeInsets.all(_menuInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (level.parentItem != null) ...[
              _FrostedPopupMenuRow(
                item: level.parentItem!,
                isSubmenuHeader: true,
                onPressed: _goBack,
              ),
              _divider(colors),
            ] else if (level.title.isNotEmpty)
              SizedBox(
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      level.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.68),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Opacity(
                opacity: reveal,
                child: ListView(
                  controller: level.scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    for (
                      var index = 0;
                      index < level.items.length;
                      index++
                    ) ...[
                      _FrostedPopupMenuRow(
                        key: level.rowKeys[index],
                        item: level.items[index],
                        hasOptionRows: level.items.any((item) => item.isOption),
                        onPressed: () => _select(level, index),
                        onLongPress: () => _selectLongPress(level, index),
                      ),
                      if (index < level.items.length - 1 &&
                          level.items[index].dividerAfter)
                        _divider(colors),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Matrix4 _surfaceTransform(Rect rect, Alignment alignment, double localScale) {
    if (!_dismissing) {
      return Matrix4.diagonal3Values(localScale, localScale, 1);
    }
    // Keep each parent's depth scale, then shrink every surface around the
    // same root anchor in overlay coordinates.
    final groupScale = Curves.easeInCubic.transform(_controller.value);
    final anchor = _dismissAnchor! - rect.topLeft;
    final localAnchor = alignment.alongSize(rect.size);
    final translation =
        anchor * (1 - groupScale) +
        localAnchor * (groupScale * (1 - localScale));
    return Matrix4.diagonal3Values(
      groupScale * localScale,
      groupScale * localScale,
      1,
    )..setTranslationRaw(translation.dx, translation.dy, 0);
  }

  Widget _surface({
    required _FrostedMenuLevel level,
    required Rect rect,
    required Size contentSize,
    required Alignment alignment,
    required double scale,
    required Color fill,
    required ColorScheme colors,
    VoidCallback? onBackgroundTap,
    double opacity = 1,
    double reveal = 1,
    bool outgoing = false,
  }) => Positioned.fromRect(
    key: ObjectKey(level),
    rect: rect,
    child: ExcludeSemantics(
      excluding: outgoing,
      child: Opacity(
        opacity: opacity,
        child: Transform(
          transform: _surfaceTransform(rect, alignment, scale),
          alignment: _dismissing ? null : alignment,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_menuOuterCornerRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha:
                        (colors.brightness == Brightness.dark ? 0.24 : 0.12) *
                        _controller.value,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_menuOuterCornerRadius),
              child: GestureDetector(
                // Only the visible background surface returns to its level.
                // Its rows stay inert inside IgnorePointer.
                behavior: onBackgroundTap == null
                    ? HitTestBehavior.deferToChild
                    : HitTestBehavior.opaque,
                onTap: onBackgroundTap,
                child: IgnorePointer(
                  ignoring: _navigating || _dismissing || outgoing,
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: 24 * _controller.value,
                      sigmaY: 24 * _controller.value,
                    ),
                    child: FadeTransition(
                      opacity: _controller,
                      child: ColoredBox(
                        color: fill,
                        // Keep final content dimensions while the surface reveals it.
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: contentSize.width,
                          maxWidth: contentSize.width,
                          minHeight: contentSize.height,
                          maxHeight: contentSize.height,
                          child: SizedBox.fromSize(
                            size: contentSize,
                            // Root Overlay entries need their own themed text style.
                            child: DefaultTextStyle(
                              style: Theme.of(context).textTheme.bodyMedium!
                                  .copyWith(decoration: TextDecoration.none),
                              child: _content(level, colors, reveal),
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
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xD91C1C1E) : const Color(0xD9FFFFFF);
    final level = _levels.last;
    final layout = _layout(mediaQuery, level);
    final outgoingLayout = _outgoing == null
        ? null
        : _layout(mediaQuery, _outgoing!);
    if (_levels.length == 1 && !_dismissing && _rootAnchor == null) {
      _rootAnchor =
          layout.rect.topLeft + layout.alignment.alongSize(layout.rect.size);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final scale = _dismissing
            ? 1.0
            : (_controller.status == AnimationStatus.reverse
                      ? Curves.easeInCubic
                      : _menuOpeningCurve)
                  .transform(_controller.value);
        return SizedBox.expand(
          key: _overlayKey,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_navigation),
            tween: Tween(begin: _navigation == 0 ? 1 : 0, end: 1),
            duration: _navigation == 0
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            onEnd: _navigation == 0 ? null : _finishNavigation,
            builder: (context, animatedProgress, _) {
              final progress = _dismissing
                  ? _dismissNavigationProgress
                  : animatedProgress;
              final activeRect = !_returning && level.sourceRect != null
                  ? Rect.lerp(level.sourceRect, layout.rect, progress)!
                  : layout.rect;
              if (!_dismissing) _navigationProgress = progress;
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
                  // Keep the real parent surfaces at their original positions.
                  // Scale them down instead of inventing contours above the child.
                  for (
                    var index = math.max(0, _levels.length - 3);
                    index < _levels.length - 1;
                    index++
                  )
                    _surface(
                      level: _levels[index],
                      rect: _levels[index + 1].parentRect!,
                      contentSize: _levels[index + 1].parentRect!.size,
                      alignment: Alignment.topCenter,
                      scale:
                          scale *
                          _ancestorScale(_levels.length - 1 - index, progress),
                      fill: fill,
                      colors: colors,
                      outgoing: true,
                      onBackgroundTap: _navigating || _dismissing
                          ? null
                          : () => _returnToLevel(index),
                    ),
                  TweenAnimationBuilder<Rect?>(
                    tween: RectTween(begin: activeRect, end: activeRect),
                    duration: _navigating ? Duration.zero : _menuResizeDuration,
                    curve: Curves.easeOutCubic,
                    builder: (context, animatedRect, _) {
                      final rect = animatedRect ?? activeRect;
                      _currentRect = rect;
                      return _surface(
                        level: level,
                        rect: rect,
                        contentSize: rect.size,
                        alignment: _returning
                            ? Alignment.topCenter
                            : layout.alignment,
                        scale:
                            scale *
                            (_returning
                                ? math
                                      .pow(
                                        _parentMenuScale,
                                        _returnDepth * (1 - progress),
                                      )
                                      .toDouble()
                                : 1),
                        fill: fill,
                        colors: colors,
                        opacity: !_returning && level.parentItem != null
                            ? progress
                            : 1,
                      );
                    },
                  ),
                  if (_outgoing != null && _outgoingRect != null)
                    _surface(
                      level: _outgoing!,
                      rect: Rect.lerp(
                        _outgoingRect,
                        _outgoingTargetRect,
                        progress,
                      )!,
                      contentSize: _outgoingRect!.size,
                      alignment: outgoingLayout!.alignment,
                      scale: scale,
                      fill: fill,
                      colors: colors,
                      opacity: 1 - progress,
                      outgoing: true,
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _FrostedPopupMenuRow extends StatefulWidget {
  const _FrostedPopupMenuRow({
    super.key,
    required this.item,
    required this.onPressed,
    this.onLongPress,
    this.hasOptionRows = false,
    this.isSubmenuHeader = false,
  });

  final FrostedPopupMenuItem item;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final bool hasOptionRows;
  final bool isSubmenuHeader;

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
    if (widget.item.customContent case final content?) {
      return Semantics(
        container: true,
        label: widget.item.label,
        child: SizedBox(
          height: widget.item.customHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: content,
          ),
        ),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    final description = widget.isSubmenuHeader ? null : widget.item.description;
    final trailingLabel = widget.item.trailingLabel;
    final isStatic = widget.item.isStatic;
    final menuIcon = isStatic ? null : widget.item.icon;
    final foreground = widget.item.destructive
        ? AppColors.destructiveRed
        : isStatic
        ? colorScheme.onSurface.withValues(alpha: 0.58)
        : colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: !isStatic,
      selected: widget.item.isOption && widget.item.selected,
      label: description == null
          ? widget.item.label
          : '${widget.item.label}. $description',
      hint: widget.isSubmenuHeader
          ? MaterialLocalizations.of(context).backButtonTooltip
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: isStatic ? null : (_) => _setPressed(true),
        onTapUp: isStatic ? null : (_) => _setPressed(false),
        onTapCancel: isStatic ? null : () => _setPressed(false),
        onTap: isStatic ? () {} : widget.onPressed,
        onLongPress:
            isStatic ||
                widget.item.onLongPress == null ||
                widget.onLongPress == null
            ? null
            : () {
                _setPressed(false);
                widget.onLongPress!();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          decoration: BoxDecoration(
            color: _pressed
                ? (isDark
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.black.withValues(alpha: 0.08))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(_menuInnerCornerRadius),
          ),
          child: SizedBox(
            height: _menuRowHeight(widget.item, description: description),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (widget.hasOptionRows) ...[
                    SizedBox(
                      width: 18,
                      child: widget.item.isOption && widget.item.selected
                          ? Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: foreground,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (menuIcon case final icon?) ...[
                    Icon(icon, size: 18, color: foreground),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: description == null
                        ? Text(
                            widget.item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontSize: isStatic ? 13 : 14,
                              fontWeight:
                                  widget.item.emphasized ||
                                      widget.isSubmenuHeader
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: foreground,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: foreground.withValues(alpha: 0.65),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (trailingLabel case final label?) ...[
                    const SizedBox(width: 8),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (widget.isSubmenuHeader ||
                      widget.item.children.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Icon(
                      widget.isSubmenuHeader
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chevron_right_rounded,
                      size: 18,
                      color: foreground,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
