import 'dart:async';

import 'package:flutter/material.dart';

import '../../icons/lucide_adapter.dart';
import '../../theme/design_tokens.dart';
import 'app_dialog_controls.dart';

class AppListDividerInsets {
  const AppListDividerInsets({required this.indent, required this.endIndent});

  final double indent;
  final double endIndent;
}

abstract interface class AppListTileDividerMetrics {
  AppListDividerInsets dividerInsets(
    BuildContext context, {
    bool? dialogHasDesignedBackground,
  });
}

AppListDividerInsets _listTileDividerInsets({
  required BuildContext context,
  required bool hasLeading,
  required EdgeInsetsGeometry? contentPadding,
  required double minLeadingWidth,
  required double horizontalTitleGap,
  double? leadingWidth,
  bool? dialogHasDesignedBackground,
}) {
  final noDialogPadding =
      AppDialogControlScope.of(context) &&
      !(dialogHasDesignedBackground ??
          AppDialogControlScope.hasBackgroundOf(context));
  final padding = noDialogPadding
      ? EdgeInsets.zero
      : (contentPadding ?? const EdgeInsets.symmetric(horizontal: 16));
  final direction = Directionality.of(context);
  final resolvedPadding = padding.resolve(direction);
  final startPadding = direction == TextDirection.ltr
      ? resolvedPadding.left
      : resolvedPadding.right;
  final endPadding = direction == TextDirection.ltr
      ? resolvedPadding.right
      : resolvedPadding.left;
  final leadingSlotWidth =
      leadingWidth != null && leadingWidth > minLeadingWidth
      ? leadingWidth
      : minLeadingWidth;
  final titleStart =
      startPadding + (hasLeading ? leadingSlotWidth + horizontalTitleGap : 0);

  return AppListDividerInsets(indent: titleStart, endIndent: endPadding);
}

/// List row with immediate neutral selection feedback and route-aware release.
class AppListTile extends StatefulWidget implements AppListTileDividerMetrics {
  const AppListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.contentPadding,
    this.minLeadingWidth = 24,
    this.horizontalTitleGap = 16,
    this.dividerLeadingWidth,
    this.minVerticalPadding = 4,
    this.dense = false,
    this.enabled = true,
    this.selected = false,
    this.showSelectedBackground = true,
    this.showPressFeedback = true,
    this.holdHighlightThroughNavigation = true,
    this.onTapFeedback,
    this.onLongPressFeedback,
    this.pressColor,
    this.selectedColor,
    this.borderRadius,
    this.onTap,
    this.onLongPress,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? contentPadding;
  final double minLeadingWidth;
  final double horizontalTitleGap;

  /// Optional actual leading slot width when it can exceed [minLeadingWidth].
  final double? dividerLeadingWidth;
  final double minVerticalPadding;
  final bool dense;
  final bool enabled;
  final bool selected;
  final bool showSelectedBackground;
  final bool showPressFeedback;
  final bool holdHighlightThroughNavigation;
  final VoidCallback? onTapFeedback;
  final VoidCallback? onLongPressFeedback;
  final Color? pressColor;
  final Color? selectedColor;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  AppListDividerInsets dividerInsets(
    BuildContext context, {
    bool? dialogHasDesignedBackground,
  }) {
    var leadingWidth = dividerLeadingWidth;
    final leading = this.leading;
    if (leadingWidth == null) {
      if (leading is SizedBox) leadingWidth = leading.width;
      if (leading is Container) {
        final constraints = leading.constraints;
        if (constraints != null && constraints.hasTightWidth) {
          leadingWidth ??= constraints.maxWidth;
        }
      }
      if (leading is Icon) leadingWidth ??= leading.size;
    }
    return _listTileDividerInsets(
      context: context,
      hasLeading: leading != null,
      contentPadding: contentPadding,
      minLeadingWidth: minLeadingWidth,
      horizontalTitleGap: horizontalTitleGap,
      leadingWidth: leadingWidth,
      dialogHasDesignedBackground: dialogHasDesignedBackground,
    );
  }

  @override
  State<AppListTile> createState() => _AppListTileState();
}

class _AppListTileState extends State<AppListTile> {
  bool _pressed = false;
  Timer? _releaseTimer;
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _routeAnimationListener;
  Animation<double>? _secondaryBeforeTap;

  bool get _canTap => widget.enabled && widget.onTap != null;
  bool get _canLongPress => widget.enabled && widget.onLongPress != null;
  bool get _interactive => _canTap || _canLongPress;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _cancelPendingRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (_routeAnimation != null && _routeAnimationListener != null) {
      _routeAnimation!.removeStatusListener(_routeAnimationListener!);
    }
    _routeAnimation = null;
    _routeAnimationListener = null;
  }

  void _handleTap() {
    _secondaryBeforeTap = ModalRoute.of(context)?.secondaryAnimation;
    widget.onTapFeedback?.call();
    widget.onTap?.call();
    if (widget.holdHighlightThroughNavigation) {
      _scheduleReleaseAfterRouteTransition();
    }
  }

  void _handleLongPress() {
    _cancelPendingRelease();
    widget.onLongPressFeedback?.call();
    widget.onLongPress?.call();
  }

  void _scheduleReleaseAfterRouteTransition() {
    _cancelPendingRelease();
    void tryRelease() {
      if (!mounted) return;
      if (_maybeWaitForRoutePush()) return;
      _setPressed(false);
      _secondaryBeforeTap = null;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      tryRelease();
      scheduleMicrotask(tryRelease);
    });
  }

  bool _maybeWaitForRoutePush() {
    final secondary = ModalRoute.of(context)?.secondaryAnimation;
    if (secondary != null &&
        _didRoutePushStart(_secondaryBeforeTap, secondary)) {
      _waitForRouteTransition(secondary);
      return true;
    }
    return false;
  }

  bool _didRoutePushStart(Animation<double>? before, Animation<double> after) {
    if (after.status == AnimationStatus.forward) return true;
    final beforeValue = before?.value ?? 0.0;
    return after.status == AnimationStatus.completed &&
        after.value > beforeValue + 0.001;
  }

  void _waitForRouteTransition(Animation<double> animation) {
    _cancelPendingRelease();
    if (animation.status == AnimationStatus.completed ||
        animation.status == AnimationStatus.dismissed) {
      _setPressed(false);
      _secondaryBeforeTap = null;
      return;
    }

    void listener(AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      animation.removeStatusListener(listener);
      _releaseTimer?.cancel();
      _routeAnimation = null;
      _routeAnimationListener = null;
      if (mounted) {
        _setPressed(false);
        _secondaryBeforeTap = null;
      }
    }

    _routeAnimation = animation;
    _routeAnimationListener = listener;
    animation.addStatusListener(listener);
    _releaseTimer = Timer(const Duration(milliseconds: 500), () {
      animation.removeStatusListener(listener);
      _routeAnimation = null;
      _routeAnimationListener = null;
      if (mounted) {
        _setPressed(false);
        _secondaryBeforeTap = null;
      }
    });
  }

  @override
  void dispose() {
    _cancelPendingRelease();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (AppDialogControlScope.of(context)) {
      return AppDialogControlTile(
        leading: widget.leading,
        title: widget.title,
        subtitle: widget.subtitle,
        trailing: widget.trailing,
        enabled: widget.enabled,
        selected: widget.selected,
        selectedColor: widget.selectedColor,
        showPressFeedback: widget.showPressFeedback,
        contentPadding: AppDialogControlScope.hasBackgroundOf(context)
            ? widget.contentPadding ??
                  const EdgeInsets.symmetric(horizontal: 16)
            : EdgeInsets.zero,
        minLeadingWidth: widget.minLeadingWidth,
        horizontalTitleGap: widget.horizontalTitleGap,
        minVerticalPadding: widget.minVerticalPadding,
        dense: widget.dense,
        onTap: _canTap
            ? () {
                widget.onTapFeedback?.call();
                widget.onTap?.call();
              }
            : null,
        onLongPress: _canLongPress
            ? () {
                widget.onLongPressFeedback?.call();
                widget.onLongPress?.call();
              }
            : null,
      );
    }
    final brightness = theme.brightness;
    final isPressed = widget.showPressFeedback && _pressed;
    final showSelectionHighlight =
        widget.selected && widget.showSelectedBackground;
    final highlighted = showSelectionHighlight || isPressed;
    final highlightColor =
        widget.pressColor ??
        (showSelectionHighlight
            ? AppColors.listPressed(brightness)
            : AppColors.listPressedFor(theme));
    final highlightRadius =
        widget.borderRadius ??
        (showSelectionHighlight
            ? const BorderRadius.all(Radius.circular(AppRadius.md))
            : null);
    final tile = ListTile(
      leading: widget.leading,
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: widget.trailing,
      contentPadding:
          widget.contentPadding ?? const EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: widget.minLeadingWidth,
      horizontalTitleGap: widget.horizontalTitleGap,
      minVerticalPadding: widget.minVerticalPadding,
      dense: widget.dense,
      enabled: widget.enabled,
      selected: widget.selected,
      selectedColor: widget.selectedColor,
      onTap: null,
      tileColor: Colors.transparent,
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _interactive
          ? (_) {
              _cancelPendingRelease();
              if (widget.showPressFeedback) _setPressed(true);
            }
          : null,
      onTapUp: _interactive
          ? (_) {
              if (widget.showPressFeedback &&
                  !widget.holdHighlightThroughNavigation) {
                _setPressed(false);
              }
            }
          : null,
      onTapCancel: _interactive
          ? () {
              _cancelPendingRelease();
              if (widget.showPressFeedback) _setPressed(false);
            }
          : null,
      onTap: _canTap ? _handleTap : null,
      onLongPress: _canLongPress ? _handleLongPress : null,
      onLongPressUp: _canLongPress && widget.showPressFeedback
          ? () => _setPressed(false)
          : null,
      onLongPressCancel: _canLongPress && widget.showPressFeedback
          ? () => _setPressed(false)
          : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highlighted
              ? highlightColor
              : AppColors.listTileBackgroundFor(theme),
          // Grouped rows let the parent clip both idle and pressed surfaces.
          borderRadius: highlighted ? highlightRadius : null,
        ),
        child: tile,
      ),
    );
  }
}

/// Settings-style navigation row with a right detail that stacks when needed.
class AppSettingsNavTile extends StatelessWidget
    implements AppListTileDividerMetrics {
  const AppSettingsNavTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.onTapFeedback,
    this.detailText,
    this.detailBuilder,
  }) : assert(detailText == null || detailBuilder == null);

  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onTapFeedback;
  final String? detailText;
  final Widget Function(BuildContext context)? detailBuilder;

  @override
  AppListDividerInsets dividerInsets(
    BuildContext context, {
    bool? dialogHasDesignedBackground,
  }) => _listTileDividerInsets(
    context: context,
    hasLeading: icon != null,
    contentPadding: null,
    minLeadingWidth: 24,
    horizontalTitleGap: 16,
    leadingWidth: 24,
    dialogHasDesignedBackground: dialogHasDesignedBackground,
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final titleStyle = TextStyle(
      fontSize: 16,
      color: colors.onSurface,
      fontWeight: FontWeight.w400,
    );
    final detailStyle = TextStyle(
      fontSize: 13,
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w400,
    );
    final detail = detailBuilder != null
        ? DefaultTextStyle.merge(
            style: detailStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: detailBuilder!(context),
          )
        : detailText == null
        ? null
        : Text(
            detailText!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: detailStyle,
          );
    final arrow = onTap == null
        ? null
        : Icon(Lucide.ChevronRight, size: 18, color: colors.onSurfaceVariant);
    final trailing = detail == null
        ? arrow
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: detail,
              ),
              if (arrow != null) ...[const SizedBox(width: 4), arrow],
            ],
          );

    AppListTile buildTile({
      required Widget? subtitle,
      required Widget? trailing,
      int titleMaxLines = 2,
    }) => AppListTile(
      onTap: onTap,
      onTapFeedback: onTapFeedback,
      leading: icon == null
          ? null
          : Icon(icon, size: 24, color: AppColors.secondaryLabel(brightness)),
      title: Text(
        label,
        maxLines: titleMaxLines,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      ),
      subtitle: subtitle,
      trailing: trailing,
    );

    if (detail == null) return buildTile(subtitle: null, trailing: arrow);

    return LayoutBuilder(
      builder: (context, constraints) {
        var shouldStack = detailBuilder != null || !constraints.hasBoundedWidth;
        if (!shouldStack) {
          final textDirection = Directionality.of(context);
          final textScaler = MediaQuery.textScalerOf(context);
          final titlePainter = TextPainter(
            text: TextSpan(text: label, style: titleStyle),
            textDirection: textDirection,
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          final titleWidth = titlePainter.width;
          titlePainter.dispose();

          final detailPainter = TextPainter(
            text: TextSpan(text: detailText!, style: detailStyle),
            textDirection: textDirection,
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          final detailWidth = detailPainter.width;
          detailPainter.dispose();

          final trailingWidth = detailWidth + (arrow == null ? 0 : 22);
          final leadingWidth = icon == null ? 0 : 24 + 16;
          final titleAvailableWidth =
              constraints.maxWidth - 32 - leadingWidth - trailingWidth - 16;
          shouldStack = titleWidth > titleAvailableWidth;
        }

        if (shouldStack) {
          return buildTile(subtitle: detail, trailing: arrow);
        }
        return buildTile(subtitle: null, trailing: trailing, titleMaxLines: 1);
      },
    );
  }
}
