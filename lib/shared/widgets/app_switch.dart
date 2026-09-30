import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/haptics.dart';
import '../../theme/design_tokens.dart';

const double _trackWidth = 51;
const double _trackHeight = 31;
const double _thumbInset = 2;
const double _thumbDiameter = _trackHeight - _thumbInset * 2;
const double _thumbTravel = _trackWidth - _thumbDiameter - _thumbInset * 2;
const double _pressedThumbStretch = 5;

/// iOS-style switch with a resistant, side-snapping drag and selection haptics.
class AppSwitch extends StatefulWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeTrackColor,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeTrackColor;
  final String? semanticLabel;

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch> {
  bool _isDragging = false;
  bool _isPressed = false;
  double _dragDelta = 0;
  bool? _dragStartSide;
  bool? _previewSide;
  bool? _pendingValue;

  bool get _enabled => widget.onChanged != null;
  bool get _effectiveSide => _previewSide ?? _pendingValue ?? widget.value;

  @override
  void didUpdateWidget(covariant AppSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pendingValue != null && widget.value == _pendingValue) {
      _pendingValue = null;
      _previewSide = null;
    }
  }

  void _selectionHaptic() {
    if (context.read<SettingsProvider>().hapticsIosSwitch) Haptics.soft();
  }

  void _setPreviewSide(bool side) {
    final current = _previewSide ?? widget.value;
    if (current != side) _selectionHaptic();
    _previewSide = side;
  }

  void _beginDrag() {
    if (_isDragging) return;
    setState(() {
      _isDragging = true;
      _isPressed = true;
      _dragDelta = 0;
      _dragStartSide = _previewSide ?? widget.value;
    });
  }

  void _updateDrag(double delta) {
    if (!_enabled) return;
    final startSide = _dragStartSide ?? widget.value;
    setState(() {
      _isDragging = true;
      _dragDelta += delta;
      final startOffset = startSide ? _thumbTravel : 0.0;
      final currentOffset = startOffset + _dragDelta;
      final newSide = (currentOffset / _thumbTravel).round().clamp(0, 1) == 1;
      _setPreviewSide(newSide);
    });
  }

  void _endInteraction() {
    if (!_isDragging && !_isPressed) return;
    setState(() {
      _isDragging = false;
      _isPressed = false;
      _dragDelta = 0;
      _dragStartSide = null;
      _previewSide = null;
      _pendingValue = null;
    });
  }

  void _commitDrag() {
    final targetValue = _previewSide ?? _dragStartSide ?? widget.value;
    if (targetValue != widget.value) {
      widget.onChanged!(targetValue);
      setState(() {
        _isDragging = false;
        _isPressed = false;
        _dragDelta = 0;
        _dragStartSide = null;
        _pendingValue = targetValue;
      });
      _revertIfRejected(targetValue);
    } else {
      setState(() {
        _isDragging = false;
        _isPressed = false;
        _dragDelta = 0;
        _dragStartSide = null;
        _previewSide = null;
      });
    }
  }

  void _revertIfRejected(bool expected) {
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      if (_pendingValue == expected && widget.value != expected) {
        setState(() {
          _pendingValue = null;
          _previewSide = null;
        });
      }
    });
  }

  void _handleTapDown(TapDownDetails details) {
    if (!_enabled) return;
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails details) {
    if (!_enabled) return;
    setState(() => _isPressed = false);
    _activate();
  }

  void _activate() {
    if (!_enabled) return;
    _selectionHaptic();
    widget.onChanged!(!widget.value);
  }

  void _handleTapCancel() {
    if (!_enabled) return;
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final progress = _effectiveSide ? 1.0 : 0.0;
    final trackColor = Color.lerp(
      AppColors.switchOffTrack(brightness),
      widget.activeTrackColor ?? theme.colorScheme.primary,
      progress,
    )!;
    final thumbColor = Color.lerp(
      AppColors.switchOffThumb(brightness),
      AppColors.switchOffThumbLight,
      progress,
    )!;

    final restingLeft = _thumbInset + progress * _thumbTravel;
    final thumbWidth = _isPressed
        ? _thumbDiameter + _pressedThumbStretch
        : _thumbDiameter;
    final thumbLeft = (restingLeft + _thumbDiameter / 2 - thumbWidth / 2).clamp(
      _thumbInset,
      _trackWidth - _thumbInset - thumbWidth,
    );
    final duration = _isDragging
        ? const Duration(milliseconds: 120)
        : const Duration(milliseconds: 200);

    return Opacity(
      opacity: _enabled ? 1 : 0.5,
      child: Semantics(
        label: widget.semanticLabel,
        checked: _effectiveSide,
        enabled: _enabled,
        onTap: _enabled ? _activate : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? _handleTapDown : null,
          onTapUp: _enabled ? _handleTapUp : null,
          onTapCancel: _enabled ? _handleTapCancel : null,
          onHorizontalDragStart: _enabled ? (_) => _beginDrag() : null,
          onHorizontalDragUpdate: _enabled
              ? (details) => _updateDrag(details.primaryDelta ?? 0)
              : null,
          onHorizontalDragEnd: _enabled ? (_) => _commitDrag() : null,
          onHorizontalDragCancel: _enabled ? _endInteraction : null,
          child: SizedBox(
            width: _trackWidth,
            height: _trackHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: _trackWidth,
                  height: _trackHeight,
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(_trackHeight / 2),
                  ),
                ),
                AnimatedPositioned(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  left: thumbLeft,
                  top: _thumbInset,
                  width: thumbWidth,
                  height: _thumbDiameter,
                  child: AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: _enabled
                          ? thumbColor
                          : thumbColor.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(_thumbDiameter / 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 1,
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
    );
  }
}
