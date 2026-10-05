import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_button_island.dart';
import 'popup_content_frame.dart';

/// Standard confirmation action for the top-right popup toolbar island.
Widget appPopupDoneAction({
  required String semanticLabel,
  required VoidCallback onTap,
}) => AppButtonIslandButton(
  icon: Icons.check_rounded,
  semanticLabel: semanticLabel,
  onTap: onTap,
);

/// Compatibility entry point for existing sheet call sites while their
/// contents are migrated to explicit [PopupContentFrame] layouts.
///
/// The route, adaptive sheet/dialog surface, and toolbar islands are provided
/// by `PopupContentFrame`. Scrollable bodies set [extendBodyBehindHeader] and
/// use [PopupContentFrame.scrollPadding] inside their scroll view; fixed bodies
/// retain the default outer header inset. Existing builders retain their result
/// values and local state during the migration.
/// Both sheet presentations consume the keyboard inset outside the body
/// viewport, so descendants receive a zero bottom viewInset. Fitting sheets
/// move above the keyboard; stretching sheets reduce the body viewport.
Future<T?> showAppPopupSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required String title,
  bool showCloseButton = true,
  List<Widget> actions = const [],
  String? closeSemanticLabel,
  VoidCallback? onClose,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool extendBodyBehindHeader = false,
  double scrollControlDisabledMaxHeightRatio = 9 / 16,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
}) {
  // These options belonged to the old Material bottom-sheet route. The shared
  // frame owns surface, clipping, navigation and drag styling now.
  final screenHeight = MediaQuery.sizeOf(context).height;
  final requestedHeight = constraints?.maxHeight.isFinite == true
      ? constraints!.maxHeight
      : isScrollControlled
      ? screenHeight * 0.92
      : screenHeight * scrollControlDisabledMaxHeightRatio;

  return showPopupContentFrame<T>(
    context,
    maxWidth: 620,
    maxHeight: math.min(requestedHeight, 820),
    fitContent: !isScrollControlled,
    largeSheet: true,
    isDismissible: isDismissible,
    builder: (frameContext, isDialog) => PopupContentFrame(
      title: title,
      showCloseButton: showCloseButton,
      actions: actions,
      closeSemanticLabel: closeSemanticLabel,
      onClose: onClose,
      isDialog: isDialog,
      child: extendBodyBehindHeader
          ? Builder(builder: builder)
          : Padding(
              padding: EdgeInsets.only(
                top: PopupContentFrame.contentTopPadding(
                  frameContext,
                  isDialog,
                ),
              ),
              child: Builder(builder: builder),
            ),
    ),
  );
}
