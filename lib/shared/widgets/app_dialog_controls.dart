import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// Marks modal content so shared rows can use local control feedback.
class AppDialogControlScope extends InheritedWidget {
  const AppDialogControlScope({
    super.key,
    required super.child,
    this.hasDesignedBackground = false,
  });

  final bool hasDesignedBackground;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDialogControlScope>() !=
      null;

  @override
  bool updateShouldNotify(AppDialogControlScope oldWidget) =>
      hasDesignedBackground != oldWidget.hasDesignedBackground;

  static bool hasBackgroundOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppDialogControlScope>()
          ?.hasDesignedBackground ??
      false;
}

/// Prevents page list backgrounds and ink effects from leaking into dialogs.
class AppDialogContentTheme extends StatelessWidget {
  const AppDialogContentTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppDialogControlScope.of(context)) return child;
    final theme = Theme.of(context);
    final overlay = WidgetStateProperty.resolveWith<Color?>((states) {
      return states.any(
            (state) => const {
              WidgetState.pressed,
              WidgetState.hovered,
              WidgetState.focused,
            }.contains(state),
          )
          ? AppColors.dialogPressOverlay(theme.brightness)
          : Colors.transparent;
    });
    return AppDialogControlScope(
      child: Theme(
        data: theme.copyWith(
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          listTileTheme: theme.listTileTheme.copyWith(
            tileColor: Colors.transparent,
            selectedTileColor: Colors.transparent,
            contentPadding: EdgeInsets.zero,
          ),
          checkboxTheme: theme.checkboxTheme.copyWith(overlayColor: overlay),
          radioTheme: theme.radioTheme.copyWith(overlayColor: overlay),
          switchTheme: theme.switchTheme.copyWith(overlayColor: overlay),
          sliderTheme: theme.sliderTheme.copyWith(
            overlayColor: AppColors.dialogPressOverlay(theme.brightness),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: (theme.iconButtonTheme.style ?? const ButtonStyle())
                .copyWith(overlayColor: overlay),
          ),
          textButtonTheme: TextButtonThemeData(
            style: (theme.textButtonTheme.style ?? const ButtonStyle())
                .copyWith(overlayColor: overlay),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Transparent, start-aligned modal row with feedback around one control only.
class AppDialogControlTile extends StatefulWidget {
  const AppDialogControlTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.selected = false,
    this.selectedColor,
    this.showPressFeedback = true,
    this.contentPadding = EdgeInsets.zero,
    this.minLeadingWidth = 24,
    this.horizontalTitleGap = 12,
    this.minVerticalPadding = 8,
    this.dense = false,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final bool selected;
  final Color? selectedColor;
  final bool showPressFeedback;
  final EdgeInsetsGeometry contentPadding;
  final double minLeadingWidth;
  final double horizontalTitleGap;
  final double minVerticalPadding;
  final bool dense;

  @override
  State<AppDialogControlTile> createState() => _AppDialogControlTileState();
}

class _AppDialogControlTileState extends State<AppDialogControlTile> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  Widget? _feedback(Widget? child, {bool circular = false}) {
    if (child == null) return null;
    final active =
        widget.enabled &&
        widget.showPressFeedback &&
        (_pressed || _hovered || _focused);
    return Stack(
      alignment: AlignmentDirectional.centerStart,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          left: -8,
          right: -8,
          top: -8,
          bottom: -8,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 80),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.dialogPressOverlay(
                    Theme.of(context).brightness,
                  ),
                  shape: circular ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: circular ? null : BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLeading = widget.leading != null;
    return InkWell(
      onTap: widget.enabled ? widget.onTap : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      onHighlightChanged: (value) => setState(() => _pressed = value),
      onHover: (value) => setState(() => _hovered = value),
      onFocusChange: (value) => setState(() => _focused = value),
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      child: ListTile(
        leading: hasLeading ? _feedback(widget.leading, circular: true) : null,
        title: widget.title,
        subtitle: widget.subtitle,
        trailing: hasLeading ? widget.trailing : _feedback(widget.trailing),
        enabled: widget.enabled,
        selected: widget.selected,
        selectedColor: widget.selectedColor,
        contentPadding: widget.contentPadding,
        minLeadingWidth: widget.minLeadingWidth,
        horizontalTitleGap: widget.horizontalTitleGap,
        minVerticalPadding: widget.minVerticalPadding,
        minTileHeight: 48,
        dense: widget.dense,
        titleTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.dialogTitle(theme.brightness),
        ),
        tileColor: Colors.transparent,
        selectedTileColor: Colors.transparent,
      ),
    );
  }
}

/// Checkbox whose visible edge aligns to the modal body's start.
class AppDialogCheckboxTile extends StatelessWidget {
  const AppDialogCheckboxTile({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      checked: value,
      enabled: onChanged != null,
      child: AppDialogControlTile(
        enabled: onChanged != null,
        leading: SizedBox(
          width: Checkbox.width,
          height: Checkbox.width,
          child: OverflowBox(
            minWidth: 48,
            maxWidth: 48,
            minHeight: 48,
            maxHeight: 48,
            child: ExcludeFocus(
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: Checkbox(
                    value: value,
                    onChanged: onChanged == null
                        ? null
                        : (value) => onChanged!(value ?? false),
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        minLeadingWidth: Checkbox.width,
        title: Text(label),
        onTap: onChanged == null ? null : () => onChanged!(!value),
      ),
    ),
  );
}
