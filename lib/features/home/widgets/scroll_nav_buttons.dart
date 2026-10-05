import 'dart:async';
import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/app_button_island.dart';

const scrollNavHoverRegionKey = ValueKey('scroll-nav-hover-region');

/// Four shared button islands in a fixed screen-edge hit-test container.
class ScrollNavButtonsPanel extends StatefulWidget {
  const ScrollNavButtonsPanel({
    super.key,
    required this.visible,
    required this.onScrollToTop,
    required this.onPreviousMessage,
    required this.onNextMessage,
    required this.onScrollToBottom,
    this.bottomOffset = 80,
    this.iconSize = 16,
    this.buttonPadding = 6,
    this.buttonSpacing = 8,
    this.hoverEnabled = false,
    this.onHoverChanged,
  });

  final bool visible;
  final VoidCallback onScrollToTop;
  final VoidCallback onPreviousMessage;
  final VoidCallback onNextMessage;
  final VoidCallback onScrollToBottom;
  final double bottomOffset;
  final double iconSize;
  final double buttonPadding;
  final double buttonSpacing;
  final bool hoverEnabled;
  final ValueChanged<bool>? onHoverChanged;

  @override
  State<ScrollNavButtonsPanel> createState() => _ScrollNavButtonsPanelState();
}

class _ScrollNavButtonsPanelState extends State<ScrollNavButtonsPanel> {
  static const _buttonExtent = 28.0;
  final Set<String> _feedbackButtons = {};
  Timer? _releaseTimer;
  bool _onScreen = false;
  bool get _visible =>
      widget.visible || _feedbackButtons.isNotEmpty || _releaseTimer != null;

  @override
  void initState() {
    super.initState();
    _onScreen = widget.visible;
  }

  void _feedbackChanged(String name, bool active) {
    final changed = active
        ? _feedbackButtons.add(name)
        : _feedbackButtons.remove(name);
    if (!changed) return;
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (_feedbackButtons.isEmpty) {
      // Match the shared island's return duration, including taps for which
      // down and up arrive before a frame and no scale tween is started.
      _releaseTimer = Timer(const Duration(milliseconds: 600), () {
        setState(() => _releaseTimer = null);
      });
    }
    setState(() {
      if (active) _onScreen = true;
    });
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ScrollNavButtonsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_visible) _onScreen = true;
  }

  Widget _button(String name, IconData icon, VoidCallback action) {
    return AppButtonIsland(
      key: ValueKey('scroll-nav-$name'),
      showBorder: false,
      onPressedChanged: (active) => _feedbackChanged(name, active),
      children: [
        AppButtonIslandButton(
          icon: icon,
          size: widget.iconSize,
          buttonDiameter: _buttonExtent,
          hitTargetSize: _buttonExtent,
          onTap: action,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final inset = widget.buttonPadding * 2;
    final height = _buttonExtent * 4 + widget.buttonSpacing * 3 + 12;
    return Align(
      alignment: Alignment.bottomRight,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.bottomOffset),
          child: MouseRegion(
            key: scrollNavHoverRegionKey,
            opaque: widget.hoverEnabled || _onScreen,
            onEnter: widget.hoverEnabled
                ? (_) => widget.onHoverChanged?.call(true)
                : null,
            onExit: widget.hoverEnabled
                ? (_) => widget.onHoverChanged?.call(false)
                : null,
            child: IgnorePointer(
              // A hiding target is still painted and tappable during exit.
              ignoring: !_onScreen,
              child: SizedBox(
                // This parent includes the screen edge throughout entry.
                // Positioned moves layout and hit testing together; no
                // narrow Align/Padding ancestor clips the moving hit path.
                width: _buttonExtent + inset + 12,
                height: height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 280),
                      curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
                      right: visible ? inset : -_buttonExtent - 12,
                      bottom: 6,
                      width: _buttonExtent,
                      onEnd: () {
                        if (!_visible && _onScreen) {
                          setState(() => _onScreen = false);
                        }
                      },
                      child: AnimatedOpacity(
                        opacity: visible ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _button(
                              'top',
                              Lucide.ArrowUpToLine,
                              widget.onScrollToTop,
                            ),
                            SizedBox(height: widget.buttonSpacing),
                            _button(
                              'previous',
                              Lucide.ChevronUp,
                              widget.onPreviousMessage,
                            ),
                            SizedBox(height: widget.buttonSpacing),
                            _button(
                              'next',
                              Lucide.ChevronDown,
                              widget.onNextMessage,
                            ),
                            SizedBox(height: widget.buttonSpacing),
                            _button(
                              'bottom',
                              Lucide.ArrowDownToLine,
                              widget.onScrollToBottom,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
