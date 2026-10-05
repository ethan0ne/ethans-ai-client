import 'package:Kelivo/shared/widgets/app_dialog.dart';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

import '../../theme/design_tokens.dart';
import 'app_button_island.dart';

/// Tracks the number of currently active popup content routes.
final popupContentFrameDepthNotifier = ValueNotifier<int>(0);

/// Top corner radius for popup sheets and embedded popup-style panels.
const double kPopupContentFrameCornerRadius = 37.0;

const double _popupToolbarHeight = 44.0;
const double _popupDragHandleHeight = 5.0;
const double _popupMaxExpandedViewportFraction = 0.9;
const _popupSheetPhysics = BouncingSheetPhysics(
  bounceExtent: 96,
  resistance: 6,
);
const _popupScrollConfiguration = SheetScrollConfiguration(
  scrollSyncMode: SheetScrollHandlingBehavior.always,
);

Color popupContentBackground(BuildContext context) =>
    Theme.of(context).colorScheme.surface;

Color _popupContentBarrierColor(BuildContext context) =>
    Theme.of(context).colorScheme.scrim.withValues(alpha: 0.32);

double _popupKeyboardInset(BuildContext context) {
  final rawInset = MediaQuery.viewInsetsOf(context).bottom;
  if (!rawInset.isFinite || rawInset <= 0) return 0;

  // The sheet keeps 10% of the viewport above its expanded surface. Clamp
  // transient invalid platform insets so the remaining content viewport can
  // never receive a negative height constraint.
  final maxInset = MediaQuery.sizeOf(context).height * 0.89;
  return rawInset.clamp(0.0, math.max(0.0, maxInset)).toDouble();
}

/// Identifies the current presentation of a popup surface to descendants
/// that need dialog-specific chrome without depending on the concrete route
/// type. This matters for the adaptive route, whose route remains the same
/// while its surface changes between sheet and dialog.
class PopupContentSurfaceScope extends InheritedWidget {
  const PopupContentSurfaceScope({
    required this.isDialog,
    required this.bottomSafeInset,
    required super.child,
    super.key,
  });

  final bool isDialog;
  final double bottomSafeInset;

  static bool isDialogOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PopupContentSurfaceScope>()
          ?.isDialog ??
      false;

  @override
  bool updateShouldNotify(PopupContentSurfaceScope oldWidget) =>
      isDialog != oldWidget.isDialog ||
      bottomSafeInset != oldWidget.bottomSafeInset;
}

/// Sheet 拖柄纵向偏移（绝对定位，不占布局高度）。
const double _popupDragHandleTopInset = AppSpacing.sm;

Widget _popupDragHandle(BuildContext context) {
  final theme = Theme.of(context);
  return Center(
    child: Container(
      width: 36,
      height: _popupDragHandleHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2.5),
      ),
    ),
  );
}

Widget _popupDragHandleOverlay(BuildContext context) {
  return Positioned(
    top: _popupDragHandleTopInset,
    left: 0,
    right: 0,
    child: IgnorePointer(child: _popupDragHandle(context)),
  );
}

/// Keeps the sheet centered when landscape safe areas are asymmetric (for
/// example, a phone with a sensor housing on only one side). The same inset
/// is applied to both sides so the sheet content does not need to know about
/// the system safe area.
double _popupSheetHorizontalSafeInset(BuildContext context) {
  final viewPadding = MediaQuery.viewPaddingOf(context);
  return math.max(viewPadding.left, viewPadding.right);
}

/// Lets a modal remain on its Navigator route while temporarily hiding its
/// surface and barrier. This is useful for gestures that must keep
/// receiving the same pointer sequence: popping a route makes Navigator cancel
/// every active pointer.
class PopupContentPresentationController extends ChangeNotifier {
  bool _isRetreated = false;

  bool get isRetreated => _isRetreated;

  void retreat() {
    if (_isRetreated) return;
    _isRetreated = true;
    notifyListeners();
  }

  void restore() {
    if (!_isRetreated) return;
    _isRetreated = false;
    notifyListeners();
  }
}

Future<T?> showPopupContentFrame<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, bool isDialog) builder,
  double maxWidth = 500,
  double maxHeight = 700,
  bool fitContent = false,
  bool alwaysDialog = false,
  bool isDismissible = true,
  bool largeSheet = false,
  PopupContentPresentationController? presentationController,
}) async {
  final presentsAsDialog =
      alwaysDialog || MediaQuery.sizeOf(context).width >= 600;
  final barrierColor = presentsAsDialog
      ? appDialogBarrierColor(context)
      : _popupContentBarrierColor(context);
  final navigator = Navigator.of(context, rootNavigator: true);

  if (alwaysDialog) {
    return navigator.push<T>(
      _PopupRetreatableDialogRoute<T>(
        context: context,
        barrierColor: barrierColor,
        barrierDismissible: isDismissible,
        presentationController: presentationController,
        builder: (context) => _PopupRetreatableDialog(
          presentationController: presentationController,
          child: AppDialogFrame(
            clipBehavior: Clip.hardEdge,
            backgroundColor: popupContentBackground(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                kPopupContentFrameCornerRadius,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              ),
              child: builder(context, true),
            ),
          ),
        ),
      ),
    );
  }

  // Keep one route alive while the window crosses the sheet/dialog breakpoint.
  // The route's content switches presentation in place, so form state is not
  // lost during iPad split-view or desktop window resizing.
  popupContentFrameDepthNotifier.value++;
  try {
    return await navigator.push<T>(
      _AdaptivePopupContentRoute<T>(
        builder: builder,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        fitContent: fitContent,
        largeSheet: largeSheet,
        barrierDismissible: isDismissible,
        barrierColor: barrierColor,
        presentationController: presentationController,
      ),
    );
  } finally {
    popupContentFrameDepthNotifier.value--;
  }
}

class _PopupRetreatableDialogRoute<T> extends DialogRoute<T> {
  _PopupRetreatableDialogRoute({
    required super.context,
    required super.builder,
    required super.barrierColor,
    required super.barrierDismissible,
    required this.presentationController,
  });

  final PopupContentPresentationController? presentationController;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      appDialogTransitionBuilder(context, animation, secondaryAnimation, child);

  @override
  Widget buildModalBarrier() => _PopupRetreatableModalBarrier(
    presentationController: presentationController,
    child: super.buildModalBarrier(),
  );
}

/// A popup route whose surface follows the current window width while it is
/// already open. The breakpoint is intentionally kept here, beside the
/// surface selection, so individual callers do not need to
/// implement resize handling themselves.
class _AdaptivePopupContentRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T> {
  _AdaptivePopupContentRoute({
    required this.builder,
    required this.maxWidth,
    required this.maxHeight,
    required this.fitContent,
    required this.largeSheet,
    required this.barrierDismissible,
    required this.barrierColor,
    required this.presentationController,
    super.settings,
  });

  final Widget Function(BuildContext context, bool isDialog) builder;
  final double maxWidth;
  final double maxHeight;
  final bool fitContent;
  final bool largeSheet;
  @override
  final bool barrierDismissible;
  @override
  final Color barrierColor;
  final PopupContentPresentationController? presentationController;

  @override
  String? get barrierLabel => null;

  // A popup is an overlay on top of the current page, even when its compact
  // presentation slides up from the bottom. Marking it as a fullscreen dialog
  // makes CupertinoRouteTransitionMixin.canTransitionFrom() suppress the
  // covered route's horizontal parallax. Without this, opening a popup from
  // the transaction form moves the form left while the sheet enters.
  @override
  bool get fullscreenDialog => true;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  String get title => '';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildContent(BuildContext context) {
    return _AdaptivePopupContentSurface(
      builder: builder,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      fitContent: fitContent,
      largeSheet: largeSheet,
      isDismissible: barrierDismissible,
      presentationController: presentationController,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return buildContent(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final isDialog = MediaQuery.sizeOf(context).width >= 600;
    if (isDialog) {
      return appDialogTransitionBuilder(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }

    final position = animation.drive(
      Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.fastEaseInToSlowEaseOut)),
    );
    return SlideTransition(position: position, child: child);
  }

  @override
  Widget buildModalBarrier() {
    return _PopupRetreatableModalBarrier(
      presentationController: presentationController,
      child: super.buildModalBarrier(),
    );
  }
}

class _AdaptivePopupContentSurface extends StatefulWidget {
  const _AdaptivePopupContentSurface({
    required this.builder,
    required this.maxWidth,
    required this.maxHeight,
    required this.fitContent,
    required this.largeSheet,
    required this.isDismissible,
    required this.presentationController,
  });

  final Widget Function(BuildContext context, bool isDialog) builder;
  final double maxWidth;
  final double maxHeight;
  final bool fitContent;
  final bool largeSheet;
  final bool isDismissible;
  final PopupContentPresentationController? presentationController;

  @override
  State<_AdaptivePopupContentSurface> createState() =>
      _AdaptivePopupContentSurfaceState();
}

class _AdaptivePopupContentSurfaceState
    extends State<_AdaptivePopupContentSurface> {
  // Reparenting this subtree across the sheet/dialog branches keeps stateful
  // content (most importantly an in-progress transaction form) alive while
  // the window crosses the breakpoint.
  final _contentKey = GlobalKey();
  SheetController? _fitContentController;

  SheetController get _sheetController =>
      _fitContentController ??= SheetController();

  @override
  void dispose() {
    _fitContentController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDialog = MediaQuery.sizeOf(context).width >= 600;
    final sheetHorizontalSafeInset = _popupSheetHorizontalSafeInset(context);
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = _popupKeyboardInset(context);
    final sheetViewportPadding = EdgeInsets.fromLTRB(
      sheetHorizontalSafeInset,
      widget.fitContent
          ? 0
          : viewportHeight * (1 - _popupMaxExpandedViewportFraction),
      sheetHorizontalSafeInset,
      // Fitting sheets move their content baseline above the keyboard. The
      // SheetMediaQuery consumes this inset before it reaches form padding.
      widget.fitContent ? keyboardHeight : 0,
    );
    final content = KeyedSubtree(
      key: _contentKey,
      child: widget.builder(context, isDialog),
    );
    final surfaceContent = PopupContentSurfaceScope(
      isDialog: isDialog,
      // Dialogs already constrain their surface away from screen edges. Sheets
      // extend to the bottom edge, so scrollable content needs the safe inset
      // as trailing scroll extent instead of losing viewport height to a
      // SafeArea wrapper.
      bottomSafeInset: isDialog ? 0 : MediaQuery.paddingOf(context).bottom,
      child: isDialog
          ? MediaQuery(
              data: MediaQuery.of(context)
                  .removeViewInsets(removeBottom: true)
                  .copyWith(
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                  ),
              child: content,
            )
          : content,
    );

    if (isDialog) {
      return _PopupRetreatableSurface(
        presentationController: widget.presentationController,
        child: Center(
          child: AppDialogFrame(
            clipBehavior: Clip.hardEdge,
            backgroundColor: popupContentBackground(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                kPopupContentFrameCornerRadius,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: widget.maxWidth,
                maxHeight: widget.maxHeight,
              ),
              child: surfaceContent,
            ),
          ),
        ),
      );
    }

    final sheet = widget.fitContent
        ? PopupFitContentModalSheet(
            controller: _sheetController,
            isDismissible: widget.isDismissible,
            disposeController: false,
            child: surfaceContent,
          )
        : PopupContentModalSheet(
            isDismissible: widget.isDismissible,
            largeSheet: widget.largeSheet,
            child: content,
          );

    final sheetViewport = widget.fitContent
        ? _PopupFitContentViewport(
            controller: _sheetController,
            padding: sheetViewportPadding,
            child: sheet,
          )
        : SheetViewport(padding: sheetViewportPadding, child: sheet);

    final outerMediaQuery = MediaQuery.of(context);
    final sheetMediaQuery = outerMediaQuery.copyWith(
      viewInsets: EdgeInsets.fromLTRB(
        outerMediaQuery.viewInsets.left,
        outerMediaQuery.viewInsets.top,
        outerMediaQuery.viewInsets.right,
        keyboardHeight,
      ),
    );
    return _PopupRetreatableSurface(
      presentationController: widget.presentationController,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (keyboardHeight > 0)
            Positioned(
              left: sheetHorizontalSafeInset,
              right: sheetHorizontalSafeInset,
              bottom: 0,
              height: keyboardHeight,
              child: IgnorePointer(
                child: ColoredBox(color: popupContentBackground(context)),
              ),
            ),
          Positioned.fill(
            child: MediaQuery(data: sheetMediaQuery, child: sheetViewport),
          ),
        ],
      ),
    );
  }
}

class _PopupRetreatableModalBarrier extends StatelessWidget {
  const _PopupRetreatableModalBarrier({
    required this.presentationController,
    required this.child,
  });

  final PopupContentPresentationController? presentationController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = presentationController;
    if (controller == null) return child;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => IgnorePointer(
        ignoring: controller.isRetreated,
        child: AnimatedOpacity(
          opacity: controller.isRetreated ? 0 : 1,
          duration: const Duration(milliseconds: 120),
          child: child,
        ),
      ),
    );
  }
}

class _PopupRetreatableSurface extends StatelessWidget {
  const _PopupRetreatableSurface({
    required this.presentationController,
    required this.child,
  });

  final PopupContentPresentationController? presentationController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = presentationController;
    if (controller == null) return child;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => IgnorePointer(
        ignoring: controller.isRetreated,
        child: AnimatedOpacity(
          opacity: controller.isRetreated ? 0 : 1,
          duration: const Duration(milliseconds: 120),
          child: child,
        ),
      ),
    );
  }
}

class _PopupRetreatableDialog extends StatelessWidget {
  const _PopupRetreatableDialog({
    required this.presentationController,
    required this.child,
  });

  final PopupContentPresentationController? presentationController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = presentationController;
    if (controller == null) return child;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => IgnorePointer(
        ignoring: controller.isRetreated,
        child: AnimatedOpacity(
          opacity: controller.isRetreated ? 0 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: child,
        ),
      ),
    );
  }
}

class PopupFitContentModalSheet extends StatefulWidget {
  const PopupFitContentModalSheet({
    super.key,
    required this.controller,
    required this.child,
    this.isDismissible = true,
    this.disposeController = true,
  });

  final SheetController controller;
  final Widget child;
  final bool isDismissible;
  final bool disposeController;

  @override
  State<PopupFitContentModalSheet> createState() =>
      _PopupFitContentModalSheetState();
}

class _PopupFitContentModalSheetState extends State<PopupFitContentModalSheet> {
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    if (widget.isDismissible) {
      widget.controller.addListener(_onOffsetChanged);
    }
  }

  @override
  void dispose() {
    if (widget.isDismissible) {
      widget.controller.removeListener(_onOffsetChanged);
    }
    if (widget.disposeController) {
      widget.controller.dispose();
    }
    super.dispose();
  }

  void _onOffsetChanged() {
    if (_popped) return;
    final offset = widget.controller.value;
    if (offset == null || offset >= 5.0) return;
    _popped = true;
    // maybePop (not pop): lets a PopScope guard on the sheet's content
    // (e.g. an unsaved-changes confirm) intercept via
    // onPopInvokedWithResult instead of being force-closed. No effect on
    // routes without such a guard — they pop immediately either way.
    // Deliberately not resetting _popped afterwards — maybePop()'s Future
    // resolves almost immediately regardless of whether the pop actually
    // went through yet, so resetting it here let this listener fire a
    // second time (offset kept changing during the same drag) and call
    // maybePop() again — landing on whatever route is now current, i.e.
    // the *parent* page, once this sheet had already been popped.
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = math.max(
      0.0,
      MediaQuery.sizeOf(context).height * 0.9 - _popupKeyboardInset(context),
    );

    return Sheet(
      controller: widget.controller,
      initialOffset: const SheetOffset(1),
      snapGrid: SheetSnapGrid(
        snaps: [
          if (widget.isDismissible) const SheetOffset.proportionalToViewport(0),
          const SheetOffset(1),
        ],
      ),
      physics: _popupSheetPhysics,
      scrollConfiguration: _popupScrollConfiguration,
      decoration: MaterialSheetDecoration(
        size: SheetSize.fit,
        color: popupContentBackground(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(kPopupContentFrameCornerRadius),
        ),
        // Isolate descendant backdrop filters within the rounded surface.
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          child: Stack(
            children: [widget.child, _popupDragHandleOverlay(context)],
          ),
        ),
      ),
    );
  }
}

class _PopupFitContentViewport extends StatelessWidget {
  const _PopupFitContentViewport({
    required this.controller,
    required this.padding,
    required this.child,
  });

  final SheetController controller;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = popupContentBackground(context);

    return Stack(
      children: [
        SheetViewport(padding: padding, child: child),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final metrics = controller.metrics;
            final overdrag = metrics == null
                ? 0.0
                : math.max(0.0, metrics.offset - metrics.maxOffset);

            return Positioned(
              left: padding.left,
              right: padding.right,
              bottom: padding.bottom,
              height: overdrag + 2,
              child: IgnorePointer(child: ColoredBox(color: backgroundColor)),
            );
          },
        ),
      ],
    );
  }
}

class PopupContentModalSheet extends StatefulWidget {
  const PopupContentModalSheet({
    super.key,
    required this.child,
    this.isDismissible = true,
    this.largeSheet = false,
  });

  final Widget child;
  final bool isDismissible;
  final bool largeSheet;

  @override
  State<PopupContentModalSheet> createState() => _PopupContentModalSheetState();
}

class _PopupContentModalSheetState extends State<PopupContentModalSheet>
    with WidgetsBindingObserver {
  final _controller = SheetController();
  bool _popped = false;
  double _keyboardHeight = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.isDismissible) {
      _controller.addListener(_onOffsetChanged);
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload does not rerun initState or undo a previous addObserver.
    // Detach instances registered by the former keyboard implementation.
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeMetrics() {
    // Also clean up a retained observer that is no longer in the live tree.
    // Keyboard layout is driven solely by MediaQuery in didChangeDependencies.
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This State is outside SheetMediaQuery, so use its unconsumed keyboard
    // inset from the current view, including when the popup opens with an
    // already visible keyboard. Do not read a global implicitView instead.
    final height = _popupKeyboardInset(context);
    final wasZero = _keyboardHeight == 0;
    _keyboardHeight = height;
    if (wasZero && height > 0 && _controller.hasClient) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _keyboardHeight == 0 || !_controller.hasClient) return;
        _controller.animateTo(
          const SheetOffset.proportionalToViewport(0.9),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.isDismissible) {
      _controller.removeListener(_onOffsetChanged);
    }
    _controller.dispose();
    super.dispose();
  }

  void _onOffsetChanged() {
    if (_popped) return;
    final offset = _controller.value;
    if (offset == null || offset >= 5.0) return;
    _popped = true;
    // maybePop (not pop): see the other _onOffsetChanged in this file
    // (including why _popped is deliberately never reset afterwards).
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = _keyboardHeight;
    return Sheet(
      controller: _controller,
      initialOffset: widget.largeSheet || _keyboardHeight > 0
          ? const SheetOffset.proportionalToViewport(
              _popupMaxExpandedViewportFraction,
            )
          : const SheetOffset.proportionalToViewport(0.5),
      snapGrid: SheetSnapGrid(
        snaps: [
          if (widget.isDismissible) const SheetOffset.proportionalToViewport(0),
          if (!widget.largeSheet) const SheetOffset.proportionalToViewport(0.5),
          const SheetOffset.proportionalToViewport(
            _popupMaxExpandedViewportFraction,
          ),
        ],
      ),
      physics: _popupSheetPhysics,
      // Use the sheet's own content margin so layout constraints and the
      // descendant MediaQuery both exclude the keyboard exactly once.
      padding: EdgeInsets.only(bottom: keyboardHeight),
      // Let the package's scroll activity coordinate the scroll position,
      // sheet offset, overscroll and release as one continuous gesture.
      scrollConfiguration: _popupScrollConfiguration,
      decoration: MaterialSheetDecoration(
        size: SheetSize.stretch,
        color: popupContentBackground(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(kPopupContentFrameCornerRadius),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              // Header islands use backdrop blur. A composited clip prevents
              // their filter output escaping the rounded sheet surface.
              clipBehavior: Clip.antiAliasWithSaveLayer,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(kPopupContentFrameCornerRadius),
              ),
              child: widget.child,
            ),
          ),
          _popupDragHandleOverlay(context),
        ],
      ),
    );
  }
}

class _PopupContentScrollInsets extends InheritedWidget {
  const _PopupContentScrollInsets({required this.top, required super.child});

  final double top;

  @override
  bool updateShouldNotify(_PopupContentScrollInsets oldWidget) =>
      top != oldWidget.top;
}

class PopupContentFrame extends StatefulWidget {
  const PopupContentFrame({
    super.key,
    required this.title,
    required this.child,
    this.leading = const [],
    this.actions = const [],
    this.headerExtension,
    this.isDialog = false,
    this.largeTitle = false,
    this.showCloseButton = false,
    this.closeSemanticLabel,
    this.onClose,
  });

  final String title;
  final Widget child;
  final List<Widget> leading;
  final List<Widget> actions;
  final Widget? headerExtension;
  final bool isDialog;
  final bool largeTitle;

  /// Top-left close control that pops with `null` (discard). Use when a
  /// confirmation action applies a working set, so cancel is explicit.
  final bool showCloseButton;
  final String? closeSemanticLabel;
  final VoidCallback? onClose;

  static const double headerExtensionHeight = 44.0;
  static const double contentTopGap = 12.0;

  /// Sheet 水平边距 [AppSpacing.md]；Dialog 为 [AppSpacing.sm]。
  static double _chromeInset(bool isDialog) =>
      isDialog ? AppSpacing.sm : AppSpacing.md;

  static double _toolbarTopOffset(bool isDialog) => _chromeInset(isDialog);

  static double contentTopPadding(
    BuildContext context,
    bool isDialog, {
    bool hasHeaderExtension = false,
  }) {
    final base = isDialog ? 80.0 : 64.0 + _chromeInset(isDialog);
    final headerOffset = hasHeaderExtension
        ? headerExtensionHeight - contentTopGap
        : 0.0;
    return base + headerOffset;
  }

  static Widget bottomSafeSpacer() =>
      const SafeArea(top: false, child: SizedBox(height: 48));

  /// Put the header space inside the scrollable so its viewport starts at the
  /// popup top and content can pass underneath the fixed header gradient.
  /// On sheets, append the bottom screen safe inset to the scroll extent so it
  /// remains reachable after the content without shrinking the viewport.
  static EdgeInsets scrollPadding(BuildContext context, EdgeInsets padding) {
    final insets = context
        .dependOnInheritedWidgetOfExactType<_PopupContentScrollInsets>();
    final surface = context
        .dependOnInheritedWidgetOfExactType<PopupContentSurfaceScope>();
    // Stretch sheets keep the keyed content subtree directly under the sheet
    // to avoid reparenting InkResponse descendants. Fitting sheets already
    // carry the pre-SafeArea inset in their surface scope.
    final bottomSafeInset =
        surface?.bottomSafeInset ?? MediaQuery.paddingOf(context).bottom;
    return padding.copyWith(
      top: padding.top + (insets?.top ?? 0),
      bottom: padding.bottom + bottomSafeInset,
    );
  }

  static ValueNotifier<bool>? showSmallTitleNotifierOf(BuildContext context) {
    return context
        .findAncestorStateOfType<_PopupContentFrameState>()
        ?._showSmallTitle;
  }

  @override
  State<PopupContentFrame> createState() => _PopupContentFrameState();
}

class _PopupContentFrameState extends State<PopupContentFrame> {
  final ValueNotifier<bool> _showSmallTitle = ValueNotifier(true);

  @override
  void initState() {
    super.initState();
    if (widget.largeTitle) {
      _showSmallTitle.value = false;
    }
  }

  @override
  void dispose() {
    _showSmallTitle.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollUpdateNotification notification) {
    if (!widget.largeTitle) return false;
    if (notification.metrics.axis != Axis.vertical) return false;
    // Show small title when user scrolls past 30 pixels
    final show = notification.metrics.pixels > 30.0;
    if (_showSmallTitle.value != show) {
      _showSmallTitle.value = show;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = widget.isDialog
        ? Colors.transparent
        : popupContentBackground(context);
    final headerBackground = popupContentBackground(context);
    final titleGradientHeight = widget.isDialog
        ? 88.0
        : 72.0 + PopupContentFrame._chromeInset(widget.isDialog);
    final gradientHeight =
        titleGradientHeight +
        (widget.headerExtension == null
            ? 0.0
            : PopupContentFrame.headerExtensionHeight);
    final leading = <Widget>[
      if (widget.showCloseButton)
        AppButtonIslandButton(
          icon: Icons.close_rounded,
          semanticLabel:
              widget.closeSemanticLabel ??
              MaterialLocalizations.of(context).closeButtonTooltip,
          onTap: widget.onClose ?? () => Navigator.of(context).pop(),
        ),
      ...widget.leading,
    ];

    return Material(
      color: bg,
      child: Stack(
        children: [
          NotificationListener<ScrollUpdateNotification>(
            onNotification: _onScroll,
            child: _PopupContentScrollInsets(
              top: PopupContentFrame.contentTopPadding(
                context,
                widget.isDialog,
                hasHeaderExtension: widget.headerExtension != null,
              ),
              child: widget.child,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: gradientHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.4, 1.0],
                    colors: [
                      headerBackground,
                      headerBackground.withValues(alpha: 0.9),
                      headerBackground.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: PopupContentFrame._toolbarTopOffset(widget.isDialog),
            height: _popupToolbarHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _showSmallTitle,
                    builder: (context, show, child) => AnimatedOpacity(
                      opacity: show ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: child,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 60.0),
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ),
                  if (leading.isNotEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: PopupContentFrame._chromeInset(
                            widget.isDialog,
                          ),
                        ),
                        child: AppButtonIsland(children: leading),
                      ),
                    ),
                  if (widget.actions.isNotEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: PopupContentFrame._chromeInset(widget.isDialog),
                        ),
                        child: AppButtonIsland(children: widget.actions),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (widget.headerExtension != null)
            Positioned(
              left: 0,
              right: 0,
              top: widget.isDialog
                  ? 56.0
                  : 48.0 + PopupContentFrame._chromeInset(widget.isDialog),
              height: PopupContentFrame.headerExtensionHeight,
              child: widget.headerExtension!,
            ),
        ],
      ),
    );
  }
}
