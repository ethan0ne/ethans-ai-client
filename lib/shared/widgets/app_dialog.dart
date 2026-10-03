import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:Kelivo/theme/design_tokens.dart';
import 'app_dialog_controls.dart';

export 'app_dialog_controls.dart';

const Duration _kAppDialogTransitionDuration = Duration(milliseconds: 220);
const Duration _kAppDialogResultSettleDelay = Duration(milliseconds: 250);
const double _kAppDialogPadding = AppSpacing.md;
const double _kAppDialogButtonHeight = 44;
const double _kAppDialogButtonRadius = AppRadius.dialogButton;
const double kAppDialogRadius = AppRadius.dialogSurface;

/// Shared modal dim level used by confirmation, information, and custom dialogs.
Color appDialogBarrierColor(BuildContext context) =>
    AppColors.modalBarrierColor(Theme.of(context).brightness);

/// Action shown in [AppDialog].
class AppDialogAction {
  const AppDialogAction({
    required this.label,
    this.child,
    this.onPressed,
    this.isPrimary = false,
    this.color,
    this.labelListenable,
    this.enabledListenable,
  });

  final String label;
  final Widget? child;
  final void Function(BuildContext context)? onPressed;
  final bool isPrimary;
  final Color? color;
  final ValueListenable<String>? labelListenable;
  final ValueListenable<bool>? enabledListenable;
}

/// The common glass surface used by every dialog in the Flutter client.
///
/// This deliberately accepts the familiar [Dialog] styling arguments so
/// existing custom dialog bodies can move to the shared surface without
/// changing their content or sizing behavior. The app owns the surface shape,
/// material, and elevation; content-specific width and height constraints stay
/// with the child.
class AppDialogFrame extends StatelessWidget {
  const AppDialogFrame({
    super.key,
    this.backgroundColor,
    this.elevation,
    this.insetAnimationCurve = Curves.decelerate,
    this.insetAnimationDuration = const Duration(milliseconds: 100),
    this.insetPadding,
    this.shadowColor,
    this.surfaceTintColor,
    this.shape,
    this.clipBehavior = Clip.none,
    required this.child,
  });

  // Kept for source compatibility with Dialog call sites. App dialog chrome
  // intentionally resolves these from the current app theme instead.
  final Color? backgroundColor;
  final double? elevation;
  final Curve insetAnimationCurve;
  final Duration insetAnimationDuration;
  final EdgeInsets? insetPadding;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final ShapeBorder? shape;
  final Clip clipBehavior;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetAnimationCurve: insetAnimationCurve,
      insetAnimationDuration: insetAnimationDuration,
      insetPadding:
          insetPadding ??
          const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAppDialogRadius),
      ),
      clipBehavior: Clip.none,
      child: AppDialogSurface(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Frosted, rounded material surface for custom modal content.
class AppDialogSurface extends StatelessWidget {
  const AppDialogSurface({
    super.key,
    required this.child,
    this.borderRadius = kAppDialogRadius,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final glassColor = AppColors.dialogSurface(brightness);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: glassColor,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: AppDialogContentTheme(
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared title/content/actions dialog, aligned with the reference project.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.content,
    required this.actions,
    this.maxWidth = 400,
    this.insetPadding,
  });

  final String title;
  final Widget? content;
  final List<AppDialogAction> actions;
  final double maxWidth;
  final EdgeInsets? insetPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleColor = AppColors.dialogTitle(theme.brightness);
    final bodyColor = AppColors.dialogBody(theme.brightness);

    Widget stackedActions() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _buildButton(context, actions[i]),
          ),
        ],
      ],
    );

    Widget actionRow() => LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final buttonWidth = (constraints.maxWidth - gap) / 2;
        final fits = actions.every(
          (action) => _labelWidth(action.label) <= buttonWidth - 24,
        );
        if (!fits) return stackedActions();
        return Row(
          children: [
            Expanded(child: _buildButton(context, actions[0])),
            const SizedBox(width: gap),
            Expanded(child: _buildButton(context, actions[1])),
          ],
        );
      },
    );

    final Widget actionWidget = actions.isEmpty
        ? const SizedBox.shrink()
        : actions.length == 1
        ? SizedBox(
            width: double.infinity,
            child: _buildButton(context, actions.single),
          )
        : actions.length == 2
        ? actionRow()
        : stackedActions();

    return AppDialogFrame(
      insetPadding: insetPadding,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(_kAppDialogPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      textHeightBehavior: const TextHeightBehavior(
                        applyHeightToFirstAscent: false,
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    if (content != null) ...[
                      const SizedBox(height: 8),
                      DefaultTextStyle(
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: bodyColor,
                        ),
                        child: content!,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              actionWidget,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context, AppDialogAction action) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = action.isPrimary
        ? action.color ?? scheme.primary
        : AppColors.dialogSecondaryFill(theme.brightness);
    final foreground = action.isPrimary
        ? action.color == null
              ? scheme.onPrimary
              : color.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white
        : AppColors.dialogSecondaryForeground(theme.brightness);

    Widget button(bool enabled, String label) => _AppDialogButton(
      color: color,
      foregroundColor: foreground,
      enabled: enabled && action.onPressed != null,
      onPressed: action.onPressed == null
          ? null
          : () => action.onPressed!(context),
      child: action.child ?? Text(label),
    );

    Widget withLabel(bool enabled) {
      final listenable = action.labelListenable;
      if (listenable == null) return button(enabled, action.label);
      return ValueListenableBuilder<String>(
        valueListenable: listenable,
        builder: (context, label, _) => button(enabled, label),
      );
    }

    final enabledListenable = action.enabledListenable;
    if (enabledListenable == null) return withLabel(true);
    return ValueListenableBuilder<bool>(
      valueListenable: enabledListenable,
      builder: (context, enabled, _) => withLabel(enabled),
    );
  }

  double _labelWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }
}

class _AppDialogButton extends StatefulWidget {
  const _AppDialogButton({
    required this.color,
    required this.foregroundColor,
    required this.enabled,
    required this.child,
    this.onPressed,
  });

  final Color color;
  final Color foregroundColor;
  final bool enabled;
  final Widget child;
  final VoidCallback? onPressed;

  @override
  State<_AppDialogButton> createState() => _AppDialogButtonState();
}

class _AppDialogButtonState extends State<_AppDialogButton> {
  bool _pressed = false;

  Color get _currentColor {
    if (!_pressed || !widget.enabled) return widget.color;
    final brightness = Theme.of(context).brightness;
    final alphaLift = AppColors.dialogPressedAlphaLift(brightness);
    final blended = Color.alphaBlend(
      AppColors.dialogPressOverlay(brightness),
      widget.color,
    );
    return widget.color.a < 1
        ? blended.withValues(
            alpha: (widget.color.a + alphaLift).clamp(0.0, 1.0).toDouble(),
          )
        : blended;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled,
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled
              ? (_) => setState(() => _pressed = true)
              : null,
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            height: _kAppDialogButtonHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _currentColor,
              borderRadius: BorderRadius.circular(_kAppDialogButtonRadius),
            ),
            alignment: Alignment.center,
            child: Opacity(
              opacity: widget.enabled ? 1 : 0.4,
              child: DefaultTextStyle(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.foregroundColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                child: IconTheme(
                  data: IconThemeData(color: widget.foregroundColor, size: 18),
                  child: Center(child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// AlertDialog-compatible wrapper that renders actions as app capsule buttons.
class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.actionsAlignment,
    this.backgroundColor,
    this.insetPadding,
    this.scrollable = false,
    this.shape,
    this.maxWidth = 400,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final MainAxisAlignment? actionsAlignment;
  final Color? backgroundColor;
  final EdgeInsets? insetPadding;
  final bool scrollable;
  final ShapeBorder? shape;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final actionWidgets = _flattenActions(actions ?? const []);
    final appActions = <AppDialogAction>[];
    for (var i = 0; i < actionWidgets.length; i++) {
      appActions.add(
        _toAppAction(actionWidgets[i], i == actionWidgets.length - 1),
      );
    }

    final body = scrollable && content != null
        ? ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(child: content),
          )
        : content;

    return AppDialog(
      title: _widgetText(title),
      content: body,
      actions: appActions,
      maxWidth: maxWidth,
      insetPadding: insetPadding,
    );
  }

  static List<Widget> _flattenActions(List<Widget> actions) => [
    for (final action in actions)
      if (action is Row) ..._flattenActions(action.children) else action,
  ];

  static AppDialogAction _toAppAction(Widget action, bool isPrimary) {
    if (action is TextButton) {
      return AppDialogAction(
        label: _widgetText(action.child),
        child: _normalizeActionChild(action.child),
        onPressed: action.onPressed == null
            ? null
            : (_) => action.onPressed!.call(),
        isPrimary: isPrimary,
      );
    }
    if (action is FilledButton) {
      return AppDialogAction(
        label: _widgetText(action.child),
        child: _normalizeActionChild(action.child),
        onPressed: action.onPressed == null
            ? null
            : (_) => action.onPressed!.call(),
        isPrimary: isPrimary,
      );
    }
    if (action is OutlinedButton) {
      return AppDialogAction(
        label: _widgetText(action.child),
        child: _normalizeActionChild(action.child),
        onPressed: action.onPressed == null
            ? null
            : (_) => action.onPressed!.call(),
        isPrimary: isPrimary,
      );
    }
    if (action is ElevatedButton) {
      return AppDialogAction(
        label: _widgetText(action.child),
        child: _normalizeActionChild(action.child),
        onPressed: action.onPressed == null
            ? null
            : (_) => action.onPressed!.call(),
        isPrimary: isPrimary,
      );
    }
    return AppDialogAction(
      label: _widgetText(action),
      child: _normalizeActionChild(action),
      isPrimary: isPrimary,
    );
  }

  static Widget? _normalizeActionChild(Widget? child) => child == null
      ? null
      : child is Text
      ? Text(_widgetText(child), semanticsLabel: child.semanticsLabel)
      : child;

  static String _widgetText(Widget? widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText() ?? '';
    }
    if (widget is Icon) return '';
    if (widget is Row) {
      return widget.children
          .map(_widgetText)
          .where((s) => s.isNotEmpty)
          .join(' ');
    }
    return '';
  }
}

/// showDialog-compatible route using the shared scale + fade transition.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = false,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  bool? requestFocus,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final resolvedBarrier = barrierColor ?? appDialogBarrierColor(context);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel ?? '',
    barrierColor: resolvedBarrier,
    transitionDuration: _kAppDialogTransitionDuration,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    requestFocus: requestFocus,
    pageBuilder: (dialogContext, _, _) {
      Widget child = AppDialogContentTheme(child: Builder(builder: builder));
      if (useSafeArea) child = SafeArea(child: child);
      return themes.wrap(child);
    },
    transitionBuilder: appDialogTransitionBuilder,
  );
}

/// The reference dialog transition: a short scale from 1.1 to 1 with fade.
Widget appDialogTransitionBuilder(
  BuildContext _,
  Animation<double> animation,
  Animation<double> _,
  Widget child,
) {
  const curve = Cubic(0.25, 0.46, 0.45, 0.94);
  final curved = CurvedAnimation(
    parent: animation,
    curve: curve,
    reverseCurve: Curves.easeIn,
  );
  return ScaleTransition(
    scale: Tween<double>(begin: 1.1, end: 1).animate(curved),
    child: FadeTransition(opacity: curved, child: child),
  );
}

Future<T?> showAppConfirmActionsDialog<T>({
  required BuildContext context,
  required String title,
  Widget? content,
  required List<AppDialogAction> actions,
  double maxWidth = 400,
  bool barrierDismissible = true,
  bool canPop = true,
}) async {
  final result = await showAppDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) {
      final dialog = AppDialog(
        title: title,
        content: content,
        actions: actions,
        maxWidth: maxWidth,
      );
      return canPop ? dialog : PopScope(canPop: false, child: dialog);
    },
  );
  await Future<void>.delayed(_kAppDialogResultSettleDelay);
  return result;
}

/// Convenience API for a standard cancel/confirm decision.
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  String? content,
  Widget? contentWidget,
  required String confirmLabel,
  String? cancelLabel,
  bool showCancel = true,
  bool isDestructive = false,
  Color? confirmColor,
  double maxWidth = 400,
  ValueListenable<bool>? cancelEnabled,
  ValueListenable<String>? cancelLabelListenable,
  ValueListenable<bool>? confirmEnabled,
  ValueListenable<String>? confirmLabelListenable,
  FutureOr<void> Function(BuildContext context)? onConfirm,
  bool barrierDismissible = true,
  bool canPop = true,
}) {
  final theme = Theme.of(context);
  final resolvedColor =
      confirmColor ??
      (isDestructive ? theme.colorScheme.error : theme.colorScheme.primary);
  final resolvedContent =
      contentWidget ?? (content == null ? null : Text(content));

  return showAppConfirmActionsDialog<bool>(
    context: context,
    title: title,
    content: resolvedContent,
    maxWidth: maxWidth,
    barrierDismissible: barrierDismissible,
    canPop: canPop,
    actions: [
      if (showCancel)
        AppDialogAction(
          label:
              cancelLabel ??
              MaterialLocalizations.of(context).cancelButtonLabel,
          enabledListenable: cancelEnabled,
          labelListenable: cancelLabelListenable,
          onPressed: (context) => Navigator.pop(context, false),
        ),
      AppDialogAction(
        label: confirmLabel,
        isPrimary: true,
        color: resolvedColor,
        enabledListenable: confirmEnabled,
        labelListenable: confirmLabelListenable,
        onPressed: onConfirm == null
            ? (context) => Navigator.pop(context, true)
            : (context) async => await onConfirm(context),
      ),
    ],
  ).then((value) => value ?? false);
}
