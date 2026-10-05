import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

// ============================================================================
// Auto-follow ScrollController / ScrollPosition
// ============================================================================

/// ScrollController whose positions auto-pin to maxScrollExtent during layout.
///
/// When [shouldAutoFollow] returns true, the created [ScrollPosition] corrects
/// its pixel value to maxScrollExtent inside [applyContentDimensions] — i.e.
/// BEFORE paint — so there is zero visual lag between content growth and scroll
/// position update. This eliminates the 1-frame flicker that post-frame
/// `jumpTo(max)` cannot avoid.
class ChatAutoFollowScrollController extends ScrollController {
  /// Callback checked during layout to decide whether to auto-follow bottom.
  bool Function() shouldAutoFollow = () => false;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _AutoFollowScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      controller: this,
    );
  }
}

class _AutoFollowScrollPosition extends ScrollPositionWithSingleContext {
  _AutoFollowScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.controller,
  });

  final ChatAutoFollowScrollController controller;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final result = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    // Also guard on userScrollDirection here in the layout phase, because it
    // updates immediately via the scroll activity — earlier than the scroll-
    // controller listener that sets _isUserScrolling.  Without this check,
    // correctPixels would override the user's drag for one frame, causing a
    // "stuck / can't scroll up" feeling.
    if (controller.shouldAutoFollow() &&
        userScrollDirection == ScrollDirection.idle) {
      final gap = this.maxScrollExtent - pixels;
      if (gap > 0.5) {
        correctPixels(this.maxScrollExtent);
        return false; // Force viewport re-layout with corrected position
      }
    }
    return result;
  }
}

// ============================================================================
// ChatScrollController
// ============================================================================

/// Controller for managing scroll behavior in the chat home page.
///
/// This controller handles:
/// - Auto-scroll to bottom during streaming (zero-lag via custom ScrollPosition)
/// - Previous/next message navigation
/// - Scroll to specific message by ID (via ListObserverController)
/// - Scroll state monitoring (user scrolling detection)
/// - Visibility state for navigation buttons
class ChatScrollController {
  ChatScrollController({
    required this._scrollController,
    required this._onStateChanged,
    required this._getAutoScrollEnabled,
    required this._getAutoScrollIdleSeconds,
  }) {
    final scrollController = _scrollController;
    _scrollController.addListener(_onScrollControllerChanged);
    _observerController = ListObserverController(controller: scrollController)
      ..cacheJumpIndexOffset = false;

    // Wire auto-follow callback for zero-lag bottom pinning
    if (scrollController is ChatAutoFollowScrollController) {
      scrollController.shouldAutoFollow = () =>
          _getAutoScrollEnabled() &&
          _autoStickToBottom &&
          !_isUserScrolling &&
          _messageNavigationDepth == 0;
    }
  }

  final ScrollController _scrollController;
  final VoidCallback _onStateChanged;
  final bool Function() _getAutoScrollEnabled;
  final int Function() _getAutoScrollIdleSeconds;

  /// Observer controller for precise index-based scroll navigation.
  late final ListObserverController _observerController;

  // ============================================================================
  // State Fields
  // ============================================================================

  /// Whether to show the jump-to-bottom button.
  bool _showJumpToBottom = false;
  bool get showJumpToBottom => _showJumpToBottom;

  /// Whether the navigation buttons should be visible (based on scroll activity).
  bool _showNavButtons = false;
  bool get showNavButtons => _showNavButtons;

  /// Timer for auto-hiding navigation buttons.
  Timer? _navButtonsHideTimer;
  static const int _navButtonsHideDelayMs = 2000;

  /// Whether the user is actively scrolling.
  bool _isUserScrolling = false;
  bool get isUserScrolling => _isUserScrolling;

  /// Whether auto-scroll should stick to bottom.
  bool _autoStickToBottom = true;
  bool get autoStickToBottom => _autoStickToBottom;

  /// Timer for detecting end of user scroll.
  Timer? _userScrollTimer;

  /// Scheduling state for batched auto-scroll (used by explicit scroll-to-bottom).
  bool _autoScrollScheduled = false;

  /// Anchor for chained previous/next message navigation.
  String? _lastJumpMessageId;
  String? get lastJumpMessageId => _lastJumpMessageId;

  // Keep the same placement when switching direction within a navigation
  // sequence. Changing from bottom to top would move a previous message down.
  bool _navigationAlignToTop = true;

  /// Serializes button taps so overlapping animations cannot cancel each other.
  Future<void> _messageNavigationQueue = Future<void>.value();

  /// Suppresses bottom pinning during explicit message navigation.
  int _messageNavigationDepth = 0;
  int _navigationGeneration = 0;
  bool _disposed = false;

  /// Tolerance for "near bottom" detection.
  static const double _autoScrollSnapTolerance = 56.0;

  // ============================================================================
  // Public Getters
  // ============================================================================

  /// Get the underlying scroll controller.
  ScrollController get scrollController => _scrollController;

  /// Get the observer controller for wrapping ListView.
  ListObserverController get observerController => _observerController;

  /// Check if scroll controller has clients attached.
  bool get hasClients => _scrollController.hasClients;

  // ============================================================================
  // Scroll State Detection
  // ============================================================================

  /// Check if the scroll position is near the bottom.
  bool isNearBottom([double tolerance = _autoScrollSnapTolerance]) {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return (pos.maxScrollExtent - pos.pixels) <= tolerance;
  }

  /// Check if the scroll view has enough content to scroll.
  ///
  /// [minExtent] - Minimum scroll extent to consider scrollable (default: 56.0).
  bool hasEnoughContentToScroll([double minExtent = 56.0]) {
    if (!_scrollController.hasClients) return false;
    return _scrollController.position.maxScrollExtent >= minExtent;
  }

  /// Refresh auto-stick-to-bottom state based on current position.
  void refreshAutoStickToBottom() {
    try {
      final nearBottom = isNearBottom();
      if (!nearBottom) {
        _autoStickToBottom = false;
      } else if (!_isUserScrolling) {
        final enabled = _getAutoScrollEnabled();
        if (enabled || _autoStickToBottom) {
          _autoStickToBottom = true;
        }
      }
    } catch (_) {}
  }

  /// Handle scroll controller changes (called from scroll listener).
  void _onScrollControllerChanged() {
    try {
      if (!_scrollController.hasClients) return;
      final autoScrollEnabled = _getAutoScrollEnabled();

      // Do not interpret a stale userScrollDirection as a new user gesture
      // while a programmatic message navigation animation is running.
      if (_messageNavigationDepth == 0 &&
          _scrollController.position.userScrollDirection !=
              ScrollDirection.idle) {
        _recordUserScrollActivity();
      }

      // Only show when not near bottom
      final atBottom = isNearBottom(24);
      if (!atBottom) {
        _autoStickToBottom = false;
      } else if (_isUserScrolling && _messageNavigationDepth == 0) {
        // User actively scrolled back to bottom → re-engage auto-follow
        // immediately so streaming content keeps pinning without waiting
        // for the idle timer.
        _isUserScrolling = false;
        _userScrollTimer?.cancel();
        _autoStickToBottom = true;
      } else if (_messageNavigationDepth == 0 &&
          (autoScrollEnabled || _autoStickToBottom)) {
        _autoStickToBottom = true;
      }
      final shouldShow = !atBottom;
      if (_showJumpToBottom != shouldShow) {
        _showJumpToBottom = shouldShow;
        _onStateChanged();
      }
    } catch (_) {}
  }

  /// Called directly by the message list for drag and pointer-scroll input.
  /// This also cancels a queued navigation anchor when the user takes over.
  void handleUserScrollActivity() {
    _recordUserScrollActivity();
  }

  void _recordUserScrollActivity() {
    _isUserScrolling = true;
    _autoStickToBottom = false;
    resetLastJumpMessageId();

    if (!_showNavButtons) {
      _showNavButtons = true;
      _onStateChanged();
    }
    _resetNavButtonsHideTimer();

    _userScrollTimer?.cancel();
    final secs = _getAutoScrollIdleSeconds();
    _userScrollTimer = Timer(Duration(seconds: secs), () {
      _isUserScrolling = false;
      refreshAutoStickToBottom();
      _onStateChanged();
    });
  }

  /// Reset the auto-hide timer for navigation buttons.
  void _resetNavButtonsHideTimer() {
    _navButtonsHideTimer?.cancel();
    _navButtonsHideTimer = Timer(
      const Duration(milliseconds: _navButtonsHideDelayMs),
      () {
        if (_showNavButtons) {
          _showNavButtons = false;
          _onStateChanged();
        }
      },
    );
  }

  /// Show navigation buttons manually (e.g., when user taps a button).
  void revealNavButtons() {
    if (!_showNavButtons) {
      _showNavButtons = true;
      _onStateChanged();
    }
    _resetNavButtonsHideTimer();
  }

  /// Hide navigation buttons immediately.
  void hideNavButtons() {
    _navButtonsHideTimer?.cancel();
    if (_showNavButtons) {
      _showNavButtons = false;
      _onStateChanged();
    }
  }

  // ============================================================================
  // Scroll To Bottom Methods
  // ============================================================================

  /// Scroll to the bottom of the list.
  ///
  /// [animate] - Whether to animate the scroll (default: true).
  void scrollToBottom({bool animate = true}) {
    _autoStickToBottom = true;
    _scheduleExplicitScrollToBottom(animate: animate);
  }

  /// Force scroll to bottom (used when user explicitly clicks the button).
  void forceScrollToBottom() {
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
    resetLastJumpMessageId();
    revealNavButtons();
    scrollToBottom();
  }

  /// Force scroll after rebuilds when switching topics/conversations.
  void forceScrollToBottomSoon({
    bool animate = true,
    Duration postSwitchDelay = const Duration(milliseconds: 220),
  }) {
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scrollToBottom(animate: animate),
    );
    Future.delayed(postSwitchDelay, () => scrollToBottom(animate: animate));
  }

  /// Ensure scroll reaches bottom even after widget tree transitions.
  void scrollToBottomSoon({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scrollToBottom(animate: animate),
    );
    Future.delayed(
      const Duration(milliseconds: 120),
      () => scrollToBottom(animate: animate),
    );
  }

  /// Auto-scroll to bottom if conditions are met (called from onStreamTick).
  ///
  /// With [ChatAutoFollowScrollController], the custom [ScrollPosition] handles
  /// bottom-pinning during layout automatically. This method is kept as a
  /// lightweight safety-net for edge cases (e.g. plain ScrollController).
  void autoScrollToBottomIfNeeded() {
    final enabled = _getAutoScrollEnabled();
    if (!enabled || !_autoStickToBottom) return;
    // With the custom ScrollPosition, bottom-pinning happens inside
    // applyContentDimensions (during layout, before paint). No post-frame
    // callback needed for the streaming path.
    // Only schedule an explicit jump as fallback for plain ScrollControllers.
    if (_scrollController is! ChatAutoFollowScrollController) {
      _scheduleExplicitScrollToBottom(animate: false);
    }
  }

  /// Schedule an explicit scroll to bottom (batched via post-frame callback).
  ///
  /// Used for user-triggered "go to bottom" and as fallback for streaming
  /// auto-scroll when the custom [ScrollPosition] is not available.
  void _scheduleExplicitScrollToBottom({bool animate = true}) {
    if (_autoScrollScheduled) return;
    _autoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _autoScrollScheduled = false;
      await _animateToBottom(animate: animate);
    });
  }

  /// Animate or jump to the bottom of the scroll view.
  ///
  /// Used for explicit scroll-to-bottom requests (user-triggered button,
  /// conversation switch, etc.). Streaming auto-scroll is handled by the
  /// custom [ScrollPosition] instead.
  Future<void> _animateToBottom({bool animate = true}) async {
    try {
      if (!_scrollController.hasClients) return;

      // Prevent using controller while it is still attached to old/new list
      if (_scrollController.positions.length != 1) {
        Future.microtask(() => _animateToBottom(animate: animate));
        return;
      }
      final pos = _scrollController.position;
      final max = pos.maxScrollExtent;
      final distance = (max - pos.pixels).abs();
      if (distance < 0.5) {
        _updateJumpToBottomVisibility(false);
        return;
      }

      if (animate) {
        final durationMs = distance < 500
            ? 250
            : distance < 2000
            ? 350
            : 450;
        await pos.animateTo(
          max,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        );
      } else {
        pos.jumpTo(max);
      }

      _updateJumpToBottomVisibility(false);
      _autoStickToBottom = true;
    } catch (_) {}
  }

  void _updateJumpToBottomVisibility(bool show) {
    if (_showJumpToBottom != show) {
      _showJumpToBottom = show;
      _onStateChanged();
    }
  }

  // ============================================================================
  // Navigation Methods
  // ============================================================================

  /// Scroll to the top of the list.
  void scrollToTop({bool animate = true}) {
    try {
      if (!_scrollController.hasClients) return;
      resetLastJumpMessageId();
      _autoStickToBottom = false;
      revealNavButtons();

      if (animate) {
        final pos = _scrollController.position;
        final distance = pos.pixels;
        final durationMs = distance < 200
            ? 150
            : distance < 800
            ? 220
            : 300;
        pos.animateTo(
          0.0,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(0.0);
      }
    } catch (_) {}
  }

  /// Jump to the message immediately before the current viewport/anchor.
  Future<void> jumpToPreviousMessage({
    required List<dynamic> messages,
    required int Function(String id) indexOfId,
  }) async {
    return _enqueueMessageNavigation(
      () => _navigateToAdjacentMessage(
        messages: messages,
        indexOfId: indexOfId,
        towardStart: true,
      ),
    );
  }

  /// Jump to the message immediately after the current viewport/anchor.
  Future<void> jumpToNextMessage({
    required List<dynamic> messages,
    required int Function(String id) indexOfId,
  }) async {
    return _enqueueMessageNavigation(
      () => _navigateToAdjacentMessage(
        messages: messages,
        indexOfId: indexOfId,
        towardStart: false,
      ),
    );
  }

  Future<void> _enqueueMessageNavigation(Future<void> Function() navigation) {
    final generation = _navigationGeneration;
    final next = _messageNavigationQueue.then((_) async {
      if (_disposed || generation != _navigationGeneration) return;
      await navigation();
    });
    _messageNavigationQueue = next;
    return next;
  }

  Future<void> _navigateToAdjacentMessage({
    required List<dynamic> messages,
    required int Function(String id) indexOfId,
    required bool towardStart,
  }) async {
    var registeredNavigation = false;
    try {
      if (!_scrollController.hasClients) return;
      if (messages.isEmpty) return;

      _beginMessageNavigation();
      registeredNavigation = true;
      revealNavButtons();
      _autoStickToBottom = false;

      // Repeated taps continue from the last target. After a manual scroll the
      // anchor is cleared and the current viewport edge becomes the boundary.
      var anchor = -1;
      final lastJumpMessageId = _lastJumpMessageId;
      if (lastJumpMessageId != null) {
        final index = indexOfId(lastJumpMessageId);
        if (index >= 0 && index < messages.length) anchor = index;
      }
      if (anchor < 0) {
        _navigationAlignToTop = towardStart;
        final visible = await _observeVisibleMessageIndexes(messages.length);
        if (visible == null || visible.isEmpty) return;
        anchor = towardStart ? visible.first : visible.last;
      }

      final target = anchor + (towardStart ? -1 : 1);
      if (target < 0 || target >= messages.length) {
        _lastJumpMessageId = null;
        if (towardStart) {
          await _scrollController.position.animateTo(
            _scrollController.position.minScrollExtent,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          );
        } else {
          await _animateToBottom();
        }
        return;
      }

      final targetId = messages[target].id as String;
      _lastJumpMessageId = targetId;
      final reachedTarget = await _animateToMessagePosition(
        messageId: targetId,
        indexOfId: indexOfId,
        messageCount: messages.length,
        towardStart: towardStart,
      );
      // Do not advance the sequence when observation/animation failed.
      if (!reachedTarget && _lastJumpMessageId == targetId) {
        _lastJumpMessageId = lastJumpMessageId;
      }
    } catch (error, stack) {
      _lastJumpMessageId = null;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'chat message navigation',
        ),
      );
    } finally {
      if (registeredNavigation) _finishMessageNavigation();
    }
  }

  void _beginMessageNavigation() {
    _messageNavigationDepth++;
  }

  void _finishMessageNavigation() {
    if (_messageNavigationDepth > 0) _messageNavigationDepth--;
    if (_messageNavigationDepth == 0 &&
        _scrollController.hasClients &&
        !_isUserScrolling &&
        isNearBottom()) {
      _autoStickToBottom = _getAutoScrollEnabled();
    }
  }

  Future<List<int>?> _observeVisibleMessageIndexes(int messageCount) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      // A detached observer cannot complete its notification future. Avoid
      // blocking every subsequent tap on the serialized navigation queue.
      final context = _observerController.sliverContexts.firstOrNull;
      if (context == null || !context.mounted) return null;
      final result = await _observerController.dispatchOnceObserve(
        // Navigation needs the current viewport even when it has not changed
        // since the preceding observation; the default only reports changes.
        isForce: true,
        isDependObserveCallback: false,
      );
      final visible =
          result.observeResult?.displayingChildIndexList
              .where((index) => index >= 0 && index < messageCount)
              .toList()
            ?..sort();
      if (visible != null && visible.isNotEmpty) return visible;
      if (attempt == 0) await WidgetsBinding.instance.endOfFrame;
    }
    return null;
  }

  /// Scrolls toward a message, using its measured render position for the final
  /// placement instead of the observer's estimate-and-correct index animation.
  Future<bool> _animateToMessagePosition({
    required String messageId,
    required int Function(String id) indexOfId,
    required int messageCount,
    required bool towardStart,
  }) async {
    var iterations = 0;
    while (_scrollController.hasClients && iterations++ < 256) {
      if (_lastJumpMessageId != messageId) return false;
      final targetIndex = indexOfId(messageId);
      if (targetIndex < 0) return false;

      final visible = await _observeVisibleMessageIndexes(messageCount);
      if (visible == null || visible.isEmpty) return false;
      if (_lastJumpMessageId != messageId) return false;

      final firstVisible = visible.first;
      final lastVisible = visible.last;
      final position = _scrollController.position;
      final currentOffset = position.pixels;
      final viewportExtent = position.viewportDimension;
      if (!viewportExtent.isFinite || viewportExtent <= 0) return false;

      final targetModel = _observerController.observeItem(index: targetIndex);
      if (targetModel != null) {
        final targetLeadingMargin = targetModel.leadingMarginToViewport;
        final targetExtent = targetModel.mainAxisSize;
        final edgeMargin = viewportExtent * 0.2;
        final desiredLeadingMargin = _navigationAlignToTop
            ? edgeMargin
            : targetExtent <= viewportExtent - edgeMargin * 2
            ? viewportExtent - targetExtent - edgeMargin
            : edgeMargin;
        final destination =
            (currentOffset + targetLeadingMargin - desiredLeadingMargin)
                .clamp(position.minScrollExtent, position.maxScrollExtent)
                .toDouble();
        final delta = destination - currentOffset;
        if (delta.abs() < 0.5) return true;

        // If a very uneven row caused a coarse step to pass the desired edge,
        // the target is already in view. Keep the motion one-way instead of
        // visibly reversing to correct an estimate.
        if ((towardStart && delta > 0) || (!towardStart && delta < 0)) {
          return false;
        }

        await position.animateTo(
          destination,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
        return _lastJumpMessageId == messageId &&
            _scrollController.hasClients &&
            (_scrollController.position.pixels - destination).abs() < 0.5;
      }

      final itemDistance = towardStart
          ? firstVisible - targetIndex
          : targetIndex - lastVisible;
      if (itemDistance <= 0) return false;
      // Move by less than one viewport so an offscreen row cannot be skipped
      // completely, even when adjacent messages have very different heights.
      final step = viewportExtent * 0.75;
      final requestedOffset = (currentOffset + (towardStart ? -step : step))
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((requestedOffset - currentOffset).abs() < 0.5) return false;

      await position.animateTo(
        requestedOffset,
        duration: const Duration(milliseconds: 120),
        curve: Curves.linear,
      );

      if (_lastJumpMessageId != messageId) return false;
      if (!_scrollController.hasClients) return false;
      final nextOffset = _scrollController.position.pixels;
      final movedTowardTarget = towardStart
          ? nextOffset < currentOffset - 0.5
          : nextOffset > currentOffset + 0.5;
      if (!movedTowardTarget) return false;
    }
    return false;
  }

  /// Scroll to a specific message by index (from mini map or search).
  ///
  /// Uses ListObserverController for precise index-based scrolling,
  /// replacing the old linear-ratio + paging-loop approach.
  Future<void> scrollToMessageId({
    required String targetId,
    required int targetIndex,
  }) async {
    try {
      if (!_scrollController.hasClients) return;
      if (targetIndex < 0) return;

      await _observerController.animateTo(
        index: targetIndex,
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
      _lastJumpMessageId = targetId;
    } catch (_) {}
  }

  // ============================================================================
  // Observer Cache Management
  // ============================================================================

  /// Clear observer's cached offset data (call on conversation switch).
  void clearObserverCache() {
    resetLastJumpMessageId();
    _observerController.clearScrollIndexCache();
  }

  // ============================================================================
  // State Modifiers
  // ============================================================================

  /// Reset the last jump message ID (e.g., when starting new navigation).
  void resetLastJumpMessageId() {
    _navigationGeneration++;
    _lastJumpMessageId = null;
  }

  /// Set auto-stick-to-bottom state.
  void setAutoStickToBottom(bool value) {
    _autoStickToBottom = value;
  }

  /// Reset user scrolling state (e.g., when force scrolling).
  void resetUserScrolling() {
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Dispose of resources.
  void dispose() {
    _disposed = true;
    resetLastJumpMessageId();
    _scrollController.removeListener(_onScrollControllerChanged);
    _userScrollTimer?.cancel();
    _navButtonsHideTimer?.cancel();
  }
}
