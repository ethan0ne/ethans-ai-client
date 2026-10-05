import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/services/haptics.dart';

/// Pull-to-refresh indicator styled to match the frosted refresh control in
/// Financial-Memory. The circle is painted above [child] and reveals from its
/// top edge as the user pulls.
class AppRefreshIndicator extends StatefulWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.enabled = true,
    this.headerExtent = 0,
    this.triggerDistance = 72,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final bool enabled;

  /// Distance from the top of this widget to the header covering the scroll
  /// content. The side drawer begins below its fixed header, so it uses zero.
  final double headerExtent;

  /// Finger travel in logical pixels required to arm a refresh.
  final double triggerDistance;

  @override
  State<AppRefreshIndicator> createState() => _AppRefreshIndicatorState();
}

enum _RefreshStatus { idle, drag, armed, snap, refresh, dismissing }

class _AppRefreshIndicatorState extends State<AppRefreshIndicator>
    with SingleTickerProviderStateMixin {
  static const _indicatorSize = 20.0;
  static const _glassSize = 36.0;
  static const _restReveal = 34.0;
  static const _overshootReveal = 16.0;
  static const _maxFactor = 1.5;
  static const _snapDuration = Duration(milliseconds: 160);
  static const _dismissDuration = Duration(milliseconds: 220);

  late final AnimationController _controller;
  _RefreshStatus _status = _RefreshStatus.idle;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _dismissDuration,
      upperBound: _maxFactor,
    );
  }

  @override
  void didUpdateWidget(covariant AppRefreshIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled &&
        !widget.enabled &&
        (_status == _RefreshStatus.drag || _status == _RefreshStatus.armed)) {
      _dragOffset = 0;
      _status = _RefreshStatus.idle;
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.enabled ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        notification.metrics.axisDirection != AxisDirection.down) {
      return false;
    }
    if (_status == _RefreshStatus.snap ||
        _status == _RefreshStatus.refresh ||
        _status == _RefreshStatus.dismissing) {
      return false;
    }

    final minExtent = notification.metrics.minScrollExtent;
    final pixels = notification.metrics.pixels;
    final atTop = notification.metrics.extentBefore <= 0 || pixels <= minExtent;

    if (_status == _RefreshStatus.idle) {
      final pullingDown =
          (notification is ScrollUpdateNotification &&
              notification.dragDetails != null &&
              (notification.scrollDelta ?? 0) < 0) ||
          (notification is OverscrollNotification &&
              notification.overscroll < 0);
      if (pullingDown && atTop) {
        _status = _RefreshStatus.drag;
        _dragOffset = math.max(0.0, minExtent - pixels).toDouble();
        if (notification is OverscrollNotification) {
          _dragOffset = math
              .max(0.0, _dragOffset - notification.overscroll)
              .toDouble();
        }
        _applyDrag(holding: true);
      }
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final holding = notification.dragDetails != null;
      if (holding && pixels > minExtent + 8) {
        _status = _RefreshStatus.idle;
        _dragOffset = 0;
        _controller.value = 0;
        return false;
      }
      if (!holding && _status == _RefreshStatus.armed) {
        unawaited(_startRefresh());
        return false;
      }
      if (pixels < minExtent) {
        _dragOffset = minExtent - pixels;
      } else {
        _dragOffset = math
            .max(0.0, _dragOffset - (notification.scrollDelta ?? 0))
            .toDouble();
        if (pixels > minExtent + 1 && !holding) {
          _dragOffset = 0;
        }
      }
      _applyDrag(holding: holding);
    } else if (notification is OverscrollNotification) {
      _dragOffset = math
          .max(0.0, _dragOffset - notification.overscroll)
          .toDouble();
      _applyDrag(holding: true);
    } else if (notification is ScrollEndNotification) {
      if (_status == _RefreshStatus.armed) {
        unawaited(_startRefresh());
      } else if (_status == _RefreshStatus.drag) {
        unawaited(_dismiss());
      }
    }
    return false;
  }

  bool _handleGlowNotification(OverscrollIndicatorNotification notification) {
    if (!widget.enabled || notification.depth != 0 || !notification.leading) {
      return false;
    }
    if (_status == _RefreshStatus.drag || _status == _RefreshStatus.armed) {
      notification.disallowIndicator();
      return true;
    }
    return false;
  }

  void _applyDrag({required bool holding}) {
    final t = (_dragOffset / widget.triggerDistance)
        .clamp(0.0, _maxFactor)
        .toDouble();
    _controller.value = t;
    if (t >= 1) {
      if (_status != _RefreshStatus.armed) Haptics.light();
      _status = _RefreshStatus.armed;
    } else if (holding && _status == _RefreshStatus.armed) {
      _status = _RefreshStatus.drag;
    }
  }

  Future<void> _startRefresh() async {
    if (_status == _RefreshStatus.refresh || _status == _RefreshStatus.snap) {
      return;
    }
    _status = _RefreshStatus.snap;
    await _controller.animateTo(1, duration: _snapDuration);
    if (!mounted || _status != _RefreshStatus.snap) return;
    setState(() => _status = _RefreshStatus.refresh);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) await _dismiss();
    }
  }

  Future<void> _dismiss() async {
    if (_status == _RefreshStatus.dismissing ||
        _status == _RefreshStatus.idle) {
      return;
    }
    _status = _RefreshStatus.dismissing;
    await _controller.animateTo(0, duration: _dismissDuration);
    if (!mounted) return;
    _dragOffset = 0;
    setState(() => _status = _RefreshStatus.idle);
  }

  double _revealFor(double t) {
    if (t <= 1) return t * _restReveal;
    return _restReveal + (t - 1) / (_maxFactor - 1) * _overshootReveal;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: _handleGlowNotification,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value;
            final showIndicator = t > 0 || _status != _RefreshStatus.idle;
            final top = widget.headerExtent - _glassSize + _revealFor(t);
            final refreshing = _status == _RefreshStatus.refresh;
            return Stack(
              children: [
                child!,
                if (widget.enabled && showIndicator)
                  Positioned(
                    top: top,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Opacity(
                          opacity: t.clamp(0.0, 1.0).toDouble(),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [glassShadow],
                            ),
                            child: ClipOval(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 24,
                                  sigmaY: 24,
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: glassFill,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: glassBorder,
                                      width: 0.75,
                                    ),
                                  ),
                                  child: SizedBox(
                                    width: _glassSize,
                                    height: _glassSize,
                                    child: Center(
                                      child: SizedBox(
                                        width: _indicatorSize,
                                        height: _indicatorSize,
                                        child: CircularProgressIndicator(
                                          value: refreshing
                                              ? null
                                              : t.clamp(0.08, 1.0).toDouble(),
                                          strokeWidth: 2.2,
                                          color: theme.colorScheme.primary,
                                          strokeCap: StrokeCap.round,
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
              ],
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
