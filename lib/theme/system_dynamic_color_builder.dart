import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Re-reads Android's system palette when the app returns from system settings.
class SystemDynamicColorBuilder extends StatefulWidget {
  const SystemDynamicColorBuilder({super.key, required this.builder});

  final Widget Function(ColorScheme? light, ColorScheme? dark) builder;

  @override
  State<SystemDynamicColorBuilder> createState() =>
      _SystemDynamicColorBuilderState();
}

class _SystemDynamicColorBuilderState extends State<SystemDynamicColorBuilder>
    with WidgetsBindingObserver {
  final _dynamicColorKey = GlobalKey<DynamicColorBuilderState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      final dynamicColorState = _dynamicColorKey.currentState;
      if (dynamicColorState != null) {
        unawaited(dynamicColorState.initPlatformState());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      DynamicColorBuilder(key: _dynamicColorKey, builder: widget.builder);
}
