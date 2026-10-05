import 'package:flutter/material.dart';

/// Observes page-route animations so the app can ignore pointer input while a
/// route is entering or leaving. This prevents taps on a still-visible page
/// from starting another route transition before the current one has settled.
class NavigationTransitionObserver extends RouteObserver<ModalRoute<dynamic>> {
  final ValueNotifier<bool> isTransitioning = ValueNotifier(false);

  final Map<ModalRoute<dynamic>, _RouteAnimationWatch> _watches = {};
  final Set<ModalRoute<dynamic>> _activeTransitions = {};
  final Set<ModalRoute<dynamic>> _poppingRoutes = {};

  bool _userGestureInProgress = false;

  void _watch(Route<dynamic>? route) {
    if (route is! ModalRoute<dynamic> || _watches.containsKey(route)) return;
    final animation = route.animation;
    if (animation == null) return;

    final watch = _RouteAnimationWatch(animation);
    watch.listener = (status) => _handleAnimationStatus(route, status);
    _watches[route] = watch;
    animation.addStatusListener(watch.listener);
    _handleAnimationStatus(route, animation.status);
  }

  void _handleAnimationStatus(
    ModalRoute<dynamic> route,
    AnimationStatus status,
  ) {
    if (status == AnimationStatus.forward ||
        status == AnimationStatus.reverse) {
      _activeTransitions.add(route);
    } else {
      _activeTransitions.remove(route);
      if (status == AnimationStatus.dismissed && _poppingRoutes.remove(route)) {
        _stopWatching(route, publish: false);
      }
    }
    _publishTransitionState();
  }

  void _stopWatching(ModalRoute<dynamic> route, {bool publish = true}) {
    final watch = _watches.remove(route);
    if (watch != null) {
      watch.animation.removeStatusListener(watch.listener);
    }
    _activeTransitions.remove(route);
    _poppingRoutes.remove(route);
    if (publish) _publishTransitionState();
  }

  void _publishTransitionState() {
    final next = !_userGestureInProgress && _activeTransitions.isNotEmpty;
    if (isTransitioning.value != next) isTransitioning.value = next;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _watch(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute<dynamic>) _poppingRoutes.add(route);
    super.didPop(route, previousRoute);
    _watch(route);
    _watch(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute<dynamic>) _stopWatching(route);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is ModalRoute<dynamic>) _stopWatching(oldRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _watch(newRoute);
  }

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    _userGestureInProgress = true;
    _publishTransitionState();
    super.didStartUserGesture(route, previousRoute);
  }

  @override
  void didStopUserGesture() {
    super.didStopUserGesture();
    _userGestureInProgress = false;
    _publishTransitionState();
  }
}

class _RouteAnimationWatch {
  _RouteAnimationWatch(this.animation);

  final Animation<double> animation;
  late final AnimationStatusListener listener;
}
