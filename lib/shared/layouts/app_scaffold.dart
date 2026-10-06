import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/window_corner_inset.dart';
import '../../theme/design_tokens.dart';
import '../widgets/app_button_island.dart';
import '../widgets/top_scroll_overlay.dart';

const double _islandEdgeInset = 16;
const double _islandCompactInset = 8;
const double _windowGeometryTolerance = 12;
const double _islandHeight = 44;
const double _islandTopBreathing = 4;
const double _windowControlsTopMargin = 10;
const double _toolbarWindowOpticalLift = 8;
const double _topDockOpticalLift = 4;

/// Standard compact navigation title used by pages built with [AppScaffold].
class AppScaffoldTitle extends StatelessWidget {
  const AppScaffoldTitle(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: color ?? Theme.of(context).colorScheme.onSurface,
        letterSpacing: 0,
      ),
    );
  }
}

/// App page shell with the floating toolbar used across the app.
class AppScaffold extends StatefulWidget {
  static const double defaultToolbarHeight = 56;
  static const double defaultAppBarContentGap = 10;

  /// Settings has 16 px list padding plus 32 px of trailing breathing room.
  static const double defaultScrollContentBottomSpacing =
      AppSpacing.md + AppSpacing.xl;

  /// Put this space inside the scroll view, so content can scroll beneath the
  /// transparent navigation bar while the viewport starts at the screen top.
  static double scrollContentTop(BuildContext context) {
    final scoped = context
        .dependOnInheritedWidgetOfExactType<_PageScrollInsets>();
    if (scoped != null) return scoped.top;
    final mediaQuery = MediaQuery.of(context);
    final windowInset = WindowCornerInsetScope.of(context)?.top ?? 0.0;
    final safeTop = [
      mediaQuery.padding.top,
      mediaQuery.viewPadding.top,
      windowInset,
    ].reduce((a, b) => a > b ? a : b);
    return safeTop + defaultToolbarHeight + defaultAppBarContentGap;
  }

  /// Appends the device's remaining bottom safe inset after page content.
  /// Keep this inside the scroll view's padding so it scrolls with the list.
  static double scrollContentBottom(
    BuildContext context, {
    double spacing = defaultScrollContentBottomSpacing,
  }) => MediaQuery.paddingOf(context).bottom + spacing;

  /// Shared tab/pane content keeps its original spacing outside a page shell.
  static EdgeInsets scrollPadding(BuildContext context, EdgeInsets padding) {
    final scoped = context
        .dependOnInheritedWidgetOfExactType<_PageScrollInsets>();
    if (scoped == null) return padding;
    return padding.copyWith(
      top: scoped.top,
      bottom: scrollContentBottom(
        context,
        spacing: padding.bottom < defaultScrollContentBottomSpacing
            ? defaultScrollContentBottomSpacing
            : padding.bottom,
      ),
    );
  }

  const AppScaffold({
    super.key,
    this.scaffoldKey,
    this.leadingIslands = const [],
    required this.title,
    this.centerTitle = true,
    this.actions = const [],
    this.appBarBottom,
    this.appBarOverride,
    required this.body,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
    this.extendBodyBehindAppBar = true,
    this.showTopScrollOverlay = true,
    this.alwaysShowTopScrollOverlay = false,
    this.processingGlow = false,
    this.topOverlayHeight,
    this.topScrollOffset,
    this.toolbarHeight = defaultToolbarHeight,
  }) : assert(!showTopScrollOverlay || extendBodyBehindAppBar);

  final GlobalKey<ScaffoldState>? scaffoldKey;
  final List<List<Widget>> leadingIslands;
  final Widget title;

  /// When false, the title starts 12 px after the left button islands and uses
  /// the remaining width before the right actions. Defaults to screen-centered.
  final bool centerTitle;
  final List<Widget> actions;
  final PreferredSizeWidget? appBarBottom;
  final PreferredSizeWidget? appBarOverride;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;
  final bool extendBodyBehindAppBar;

  /// Fades scrolled content from the screen top after the first 16 px.
  /// Enabled by default for pages using [AppScaffold].
  final bool showTopScrollOverlay;

  /// Camera pages keep navigation readable even without a scroll source.
  final bool alwaysShowTopScrollOverlay;

  /// Keeps the top fade visible while the current page is processing work.
  final bool processingGlow;

  /// Optional extra fade distance beneath the toolbar. Defaults to zero when
  /// the page has no navigation extension area.
  final double? topOverlayHeight;

  /// Scroll source for platform views, which do not emit Flutter notifications.
  final ValueNotifier<double>? topScrollOffset;
  final double toolbarHeight;

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _PageScrollInsets extends InheritedWidget {
  const _PageScrollInsets({required this.top, required super.child});
  final double top;

  @override
  bool updateShouldNotify(_PageScrollInsets oldWidget) => top != oldWidget.top;
}

class _AppScaffoldState extends State<AppScaffold> {
  final GlobalKey _leadingKey = GlobalKey();
  final GlobalKey _actionsKey = GlobalKey();
  final GlobalKey _bodyKey = GlobalKey();
  final ValueNotifier<bool> _showTopScrollOverlay = ValueNotifier(false);
  double _leadingWidth = 0;
  double _actionsWidth = 0;

  @override
  void initState() {
    super.initState();
    widget.topScrollOffset?.addListener(_handleExternalScroll);
  }

  void _handleExternalScroll() {
    _showTopScrollOverlay.value = (widget.topScrollOffset?.value ?? 0) > 16;
  }

  @override
  void dispose() {
    widget.topScrollOffset?.removeListener(_handleExternalScroll);
    _showTopScrollOverlay.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AppScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topScrollOffset != widget.topScrollOffset) {
      oldWidget.topScrollOffset?.removeListener(_handleExternalScroll);
      widget.topScrollOffset?.addListener(_handleExternalScroll);
      _handleExternalScroll();
    }
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

  bool _handleBodyScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      if (notification is ScrollEndNotification) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _syncVisibleScroll(),
        );
      }
      return false;
    }
    // Scroll notifications can also arrive while a viewport is being laid out.
    // Read global geometry after layout, when route transforms have valid sizes.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVisibleScroll());
    return false;
  }

  void _syncVisibleScroll() {
    if (!mounted) return;
    final context = _bodyKey.currentContext;
    final box = context?.findRenderObject();
    if (context == null || box is! RenderBox || !box.hasSize) return;
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    ScrollableState? visibleScroll;
    void visit(Element element) {
      if (visibleScroll != null) return;
      if (element.widget case Offstage(offstage: true)) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        final render = element.findRenderObject();
        if (axisDirectionToAxis(state.position.axisDirection) ==
                Axis.vertical &&
            state.position.hasPixels &&
            render is RenderBox &&
            render.hasSize &&
            bounds.contains(
              render.localToGlobal(render.size.center(Offset.zero)),
            )) {
          visibleScroll = state;
          return;
        }
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    final shouldShow =
        (visibleScroll?.position.pixels ?? widget.topScrollOffset?.value ?? 0) >
        16;
    if (_showTopScrollOverlay.value != shouldShow) {
      _showTopScrollOverlay.value = shouldShow;
    }
  }

  Widget _buildBody(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final windowInsets = WindowCornerInsetScope.of(context);
    final topInset = [
      mediaQuery.padding.top,
      mediaQuery.viewPadding.top,
      windowInsets?.top ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final hasTopInset = topInset > 0;
    final appBarExtent =
        widget.appBarOverride?.preferredSize.height ??
        widget.toolbarHeight +
            (widget.appBarBottom?.preferredSize.height ?? 0.0);
    final topBandHeight = hasTopInset ? topInset : 32.0;
    final gradientHeight = appBarExtent + (widget.topOverlayHeight ?? 0.0);
    final overlayBackground =
        widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;
    final body = _PageScrollInsets(
      top: widget.extendBodyBehindAppBar
          ? topInset + appBarExtent + AppScaffold.defaultAppBarContentGap
          : 0,
      child: KeyedSubtree(key: _bodyKey, child: widget.body),
    );
    if (!widget.showTopScrollOverlay) return body;

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _syncVisibleScroll(),
        );
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleBodyScroll,
        child: Stack(
          fit: StackFit.expand,
          children: [
            body,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topBandHeight + gradientHeight,
              child: IgnorePointer(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _showTopScrollOverlay,
                  builder: (context, visible, child) => AnimatedOpacity(
                    opacity:
                        visible ||
                            widget.alwaysShowTopScrollOverlay ||
                            widget.processingGlow
                        ? 1
                        : 0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeInOut,
                    child: child,
                  ),
                  child: TopScrollOverlay(
                    backgroundColor: overlayBackground,
                    topBandHeight: topBandHeight,
                    gradientHeight: gradientHeight,
                    notched: hasTopInset,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      bottom: widget.appBarBottom,
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
                  if (!widget.centerTitle) {
                    return Padding(
                      padding: EdgeInsets.only(
                        left: leadingInset,
                        right: trailingInset,
                      ),
                      child: Row(
                        children: [
                          if (leadingChildren.isNotEmpty) ...[
                            Row(
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
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: widget.title,
                            ),
                          ),
                          if (hasActions) ...[
                            const SizedBox(width: 12),
                            AppButtonIsland(
                              key: _actionsKey,
                              children: widget.actions,
                            ),
                          ],
                        ],
                      ),
                    );
                  }
                  final leadingTitleClearance = leadingChildren.isEmpty
                      ? 0.0
                      : leadingInset + _leadingWidth + 12;
                  final actionsTitleClearance = hasActions
                      ? trailingInset + _actionsWidth + 12
                      : 0.0;
                  final titleSideClearance =
                      leadingTitleClearance > actionsTitleClearance
                      ? leadingTitleClearance
                      : actionsTitleClearance;
                  final titleMaxWidth =
                      (constraints.maxWidth - titleSideClearance * 2).clamp(
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
      body: _buildBody(context),
      bottomNavigationBar: widget.bottomNavigationBar,
    );
  }
}
