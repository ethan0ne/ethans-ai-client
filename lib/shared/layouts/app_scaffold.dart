import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/window_corner_inset.dart';
import '../widgets/app_button_island.dart';

const double _islandEdgeInset = 16;
const double _islandCompactInset = 8;
const double _windowGeometryTolerance = 12;
const double _islandHeight = 44;
const double _islandTopBreathing = 4;
const double _windowControlsTopMargin = 10;
const double _toolbarWindowOpticalLift = 8;
const double _topDockOpticalLift = 4;

/// App page shell with the floating, centered toolbar used across the app.
class AppScaffold extends StatefulWidget {
  const AppScaffold({
    super.key,
    this.scaffoldKey,
    this.leadingIslands = const [],
    required this.title,
    this.actions = const [],
    this.appBarOverride,
    required this.body,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
    this.extendBodyBehindAppBar = true,
    this.toolbarHeight = 56,
  });

  final GlobalKey<ScaffoldState>? scaffoldKey;
  final List<List<Widget>> leadingIslands;
  final Widget title;
  final List<Widget> actions;
  final PreferredSizeWidget? appBarOverride;
  final Widget body;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;
  final bool extendBodyBehindAppBar;
  final double toolbarHeight;

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  final GlobalKey _leadingKey = GlobalKey();
  final GlobalKey _actionsKey = GlobalKey();
  double _leadingWidth = 0;
  double _actionsWidth = 0;

  @override
  void didUpdateWidget(AppScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leadingIslands.length != widget.leadingIslands.length ||
        oldWidget.actions.length != widget.actions.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureIslands());
    }
  }

  void _measureIslands() {
    if (!mounted) return;
    double widthFor(GlobalKey key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      return box?.hasSize == true ? box!.size.width : 0;
    }

    final leadingWidth = widthFor(_leadingKey);
    final actionsWidth = widthFor(_actionsKey);
    if (leadingWidth != _leadingWidth || actionsWidth != _actionsWidth) {
      setState(() {
        _leadingWidth = leadingWidth;
        _actionsWidth = actionsWidth;
      });
    }
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureIslands());
    final mediaQuery = MediaQuery.of(context);
    final windowInsets = WindowCornerInsetScope.of(context);
    final safeTop = [
      mediaQuery.padding.top,
      mediaQuery.viewPadding.top,
      windowInsets?.top ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    final isPhoneBySize = mediaQuery.size.shortestSide < 600;
    final isPhoneHardware = windowInsets?.hasSnapshot == true
        ? windowInsets!.isPhone
        : isPhoneBySize;
    final isPortrait = mediaQuery.size.height >= mediaQuery.size.width;
    final horizontalSafeArea = [
      mediaQuery.padding.left,
      mediaQuery.padding.right,
      mediaQuery.viewPadding.left,
      mediaQuery.viewPadding.right,
      windowInsets?.leading ?? 0,
      windowInsets?.trailing ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final hasWindowControls = windowInsets?.controlsVisible ?? false;
    final windowControlInset = [
      windowInsets?.leading ?? 0,
      windowInsets?.trailing ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final hasWindowControlGeometry =
        hasWindowControls &&
        !isPhoneHardware &&
        (windowInsets?.top ?? 0) <=
            windowControlInset + _windowGeometryTolerance;
    final usesWindowControlTopLayout = hasWindowControlGeometry && isIos;
    final usesCompactWindowTop =
        usesWindowControlTopLayout && windowInsets?.windowTouchesTop != true;
    final chromeSafeTop = usesCompactWindowTop ? 0.0 : safeTop;
    final isNotched = chromeSafeTop > 24;
    final usesPhoneNotchCompaction =
        isIos &&
        isPhoneBySize &&
        isPortrait &&
        isNotched &&
        !usesWindowControlTopLayout;
    final usesPhoneLandscapeCompaction =
        isIos &&
        isPhoneHardware &&
        !isPortrait &&
        horizontalSafeArea > 24 &&
        !usesWindowControlTopLayout;
    final isPortraitPhone = usesPhoneNotchCompaction;
    final topShift = isPortraitPhone
        ? -14.0
        : isNotched
        ? -10.0
        : 0.0;
    final toolbarCenteringOffset = (widget.toolbarHeight - _islandHeight) / 2;
    final toolbarBandTop = usesWindowControlTopLayout
        ? (windowInsets?.windowTouchesTop == true &&
                  (windowInsets?.top ?? 0) > 0
              ? (windowInsets!.top -
                            (_islandHeight - 4 + toolbarCenteringOffset))
                        .clamp(_islandTopBreathing, double.infinity) -
                    _topDockOpticalLift
              : [
                  _windowControlsTopMargin - toolbarCenteringOffset,
                  _islandTopBreathing -
                      toolbarCenteringOffset -
                      _toolbarWindowOpticalLift +
                      topShift,
                ].reduce((a, b) => a > b ? a : b))
        : usesPhoneLandscapeCompaction
        ? 0.0
        : (chromeSafeTop + topShift).clamp(0.0, double.infinity);
    final leadingInset = hasWindowControlGeometry
        ? [
            _islandCompactInset,
            (windowInsets?.leading ?? 0) + _islandCompactInset,
          ].reduce((a, b) => a > b ? a : b)
        : _islandEdgeInset;
    final trailingInset = hasWindowControlGeometry
        ? _islandCompactInset
        : _islandEdgeInset;
    final leadingChildren = widget.leadingIslands
        .where((island) => island.isNotEmpty)
        .toList();
    final hasActions = widget.actions.isNotEmpty;

    return AppBar(
      clipBehavior: Clip.none,
      automaticallyImplyLeading: false,
      forceMaterialTransparency: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: widget.toolbarHeight,
      systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            ),
      flexibleSpace: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: toolbarBandTop,
            left: 0,
            right: 0,
            height: widget.toolbarHeight,
            child: SafeArea(
              left: true,
              right: true,
              top: false,
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final islandWidth = _leadingWidth > _actionsWidth
                      ? _leadingWidth
                      : _actionsWidth;
                  final titleMaxWidth =
                      (constraints.maxWidth - islandWidth * 2 - 24).clamp(
                        0.0,
                        constraints.maxWidth,
                      );

                  return Stack(
                    children: [
                      if (leadingChildren.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(left: leadingInset),
                            child: Row(
                              key: _leadingKey,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < leadingChildren.length; i++)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      left: i == 0 ? 0 : 8,
                                    ),
                                    child: AppButtonIsland(
                                      children: leadingChildren[i],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: titleMaxWidth),
                          child: widget.title,
                        ),
                      ),
                      if (hasActions)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: EdgeInsets.only(right: trailingInset),
                            child: AppButtonIsland(
                              key: _actionsKey,
                              children: widget.actions,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: widget.scaffoldKey,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
      backgroundColor: widget.backgroundColor,
      appBar: widget.appBarOverride ?? _buildAppBar(context),
      body: widget.body,
    );
  }
}
