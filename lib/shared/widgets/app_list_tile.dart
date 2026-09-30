import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// List row with immediate neutral selection feedback and route-aware release.
class AppListTile extends StatefulWidget {
  const AppListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.minLeadingWidth = 24,
    this.horizontalTitleGap = 16,
    this.enabled = true,
    this.selected = false,
    this.showPressFeedback = true,
    this.holdHighlightThroughNavigation = true,
    this.onTapFeedback,
    this.pressColor,
    this.selectedColor,
    this.borderRadius,
    this.onTap,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry contentPadding;
  final double minLeadingWidth;
  final double horizontalTitleGap;
  final bool enabled;
  final bool selected;
  final bool showPressFeedback;
  final bool holdHighlightThroughNavigation;
  final VoidCallback? onTapFeedback;
  final Color? pressColor;
  final Color? selectedColor;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  State<AppListTile> createState() => _AppListTileState();
}

class _AppListTileState extends State<AppListTile> {
  bool _pressed = false;
  Timer? _releaseTimer;
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _routeAnimationListener;
  Animation<double>? _secondaryBeforeTap;

  bool get _interactive => widget.enabled && widget.onTap != null;

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
    final brightness = Theme.of(context).brightness;
    final tile = ListTile(
      leading: widget.leading,
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: widget.trailing,
      contentPadding: widget.contentPadding,
      minLeadingWidth: widget.minLeadingWidth,
      horizontalTitleGap: widget.horizontalTitleGap,
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
      onTap: _interactive ? _handleTap : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.selected || (widget.showPressFeedback && _pressed)
              ? (widget.pressColor ?? AppColors.listPressed(brightness))
              : Colors.transparent,
          borderRadius: widget.borderRadius,
        ),
        child: tile,
      ),
    );
  }
}
