import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _methodChannel = MethodChannel('financial_memory/window_corner_inset');
const _eventChannel = EventChannel(
  'financial_memory/window_corner_inset/events',
);

/// UIKit geometry for iPadOS floating-window controls. Other platforms use
/// MediaQuery safe-area values as the fallback.
class WindowCornerInsetController extends ChangeNotifier {
  double leading = 0;
  double trailing = 0;
  double top = 0;
  bool isPhone = false;
  bool windowTouchesTop = false;
  bool controlsVisible = false;
  bool hasSnapshot = false;
  StreamSubscription<dynamic>? _subscription;
  bool _initialized = false;
  bool _receivedEvent = false;

  Future<void> initialize() async {
    if (_initialized || defaultTargetPlatform != TargetPlatform.iOS) return;
    _initialized = true;
    _subscription = _eventChannel.receiveBroadcastStream().listen((value) {
      _receivedEvent = true;
      _update(value);
    }, onError: (_) {});
    try {
      final value = await _methodChannel.invokeMethod<dynamic>('current');
      if (!_receivedEvent) _update(value);
    } on MissingPluginException {
      // Older iOS builds have no UIKit geometry bridge.
    } on PlatformException {
      // Keep the MediaQuery fallback when UIKit cannot provide geometry.
    }
  }

  void _update(dynamic value) {
    if (value is! Map) return;
    double number(String key) {
      final raw = value[key];
      final next = raw is num ? raw.toDouble() : 0.0;
      return next.isFinite && next > 0 ? next : 0.0;
    }

    final nextLeading = number('leading');
    final nextTrailing = number('trailing');
    final nextTop = number('top');
    final nextIsPhone = (value['isPhone'] as num?)?.toDouble() == 1;
    final nextTouchesTop = (value['windowTouchesTop'] as num?)?.toDouble() == 1;
    final nextControlsVisible =
        (value['controlsVisible'] as num?)?.toDouble() == 1;
    if (leading == nextLeading &&
        trailing == nextTrailing &&
        top == nextTop &&
        isPhone == nextIsPhone &&
        windowTouchesTop == nextTouchesTop &&
        controlsVisible == nextControlsVisible) {
      return;
    }
    leading = nextLeading;
    trailing = nextTrailing;
    top = nextTop;
    isPhone = nextIsPhone;
    windowTouchesTop = nextTouchesTop;
    controlsVisible = nextControlsVisible;
    hasSnapshot = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final windowCornerInsetController = WindowCornerInsetController();

class WindowCornerInsetScope
    extends InheritedNotifier<WindowCornerInsetController> {
  const WindowCornerInsetScope({
    required WindowCornerInsetController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static WindowCornerInsetController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WindowCornerInsetScope>()
      ?.notifier;
}
