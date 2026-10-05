import 'package:Kelivo/features/home/controllers/scroll_controller.dart';
import 'package:Kelivo/features/home/widgets/scroll_nav_buttons.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

void main() {
  group('ChatScrollController streaming auto-follow', () {
    testWidgets('does not follow new content when auto-scroll is disabled', (
      tester,
    ) async {
      var autoScrollEnabled = false;
      var itemCount = 20;
      final scrollController = ChatAutoFollowScrollController();
      final chatScrollController = ChatScrollController(
        scrollController: scrollController,
        onStateChanged: () {},
        getAutoScrollEnabled: () => autoScrollEnabled,
        getAutoScrollIdleSeconds: () => 8,
      );

      await tester.pumpWidget(
        _ScrollHarness(
          scrollController: scrollController,
          itemCount: itemCount,
        ),
      );
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      final oldMax = scrollController.position.maxScrollExtent;

      itemCount += 1;
      await tester.pumpWidget(
        _ScrollHarness(
          scrollController: scrollController,
          itemCount: itemCount,
        ),
      );

      expect(scrollController.offset, oldMax);
      expect(
        scrollController.offset,
        lessThan(scrollController.position.maxScrollExtent),
      );

      chatScrollController.dispose();
      scrollController.dispose();
    });

    testWidgets('follows new content when auto-scroll is enabled', (
      tester,
    ) async {
      var autoScrollEnabled = true;
      var itemCount = 20;
      final scrollController = ChatAutoFollowScrollController();
      final chatScrollController = ChatScrollController(
        scrollController: scrollController,
        onStateChanged: () {},
        getAutoScrollEnabled: () => autoScrollEnabled,
        getAutoScrollIdleSeconds: () => 8,
      );

      await tester.pumpWidget(
        _ScrollHarness(
          scrollController: scrollController,
          itemCount: itemCount,
        ),
      );
      scrollController.jumpTo(scrollController.position.maxScrollExtent);

      itemCount += 1;
      await tester.pumpWidget(
        _ScrollHarness(
          scrollController: scrollController,
          itemCount: itemCount,
        ),
      );

      expect(
        scrollController.offset,
        scrollController.position.maxScrollExtent,
      );

      chatScrollController.dispose();
      scrollController.dispose();
    });
  });

  group('ChatScrollController message navigation', () {
    testWidgets('上一条消息从当前视口顶部选择目标', (tester) async {
      final messages = <_NavMessage>[
        for (var i = 0; i < 40; i++)
          _NavMessage(
            id: 'message-$i',
            role: i % 5 == 0 ? 'user' : 'assistant',
          ),
      ];
      final scrollController = ChatAutoFollowScrollController();
      final chatScrollController = ChatScrollController(
        scrollController: scrollController,
        onStateChanged: () {},
        getAutoScrollEnabled: () => false,
        getAutoScrollIdleSeconds: () => 8,
      );

      await tester.pumpWidget(
        _ObservedScrollHarness(
          scrollController: scrollController,
          observerController: chatScrollController.observerController,
          messages: messages,
        ),
      );
      scrollController.jumpTo(900);
      await tester.pump();

      final navigation = chatScrollController.jumpToPreviousMessage(
        messages: messages,
        indexOfId: (id) => messages.indexWhere((message) => message.id == id),
      );
      await tester.pumpAndSettle();
      await navigation;

      expect(chatScrollController.lastJumpMessageId, 'message-10');
      expect(scrollController.offset, lessThan(900));
      expect(find.text('user message-10').hitTestable(), findsOneWidget);
      final beforeRepeat = scrollController.offset;
      final repeated = chatScrollController.jumpToPreviousMessage(
        messages: messages,
        indexOfId: (id) => messages.indexWhere((message) => message.id == id),
      );
      await tester.pumpAndSettle();
      await repeated;
      expect(chatScrollController.lastJumpMessageId, 'message-9');
      expect(scrollController.offset, lessThan(beforeRepeat));

      final reverse = chatScrollController.jumpToNextMessage(
        messages: messages,
        indexOfId: (id) => messages.indexWhere((message) => message.id == id),
      );
      await tester.pumpAndSettle();
      await reverse;
      expect(chatScrollController.lastJumpMessageId, 'message-10');
      expect(scrollController.offset, closeTo(beforeRepeat, 0.5));

      chatScrollController.dispose();
      scrollController.dispose();
    });

    testWidgets('下一条消息从当前视口底部选择目标', (tester) async {
      final messages = <_NavMessage>[
        for (var i = 0; i < 40; i++)
          _NavMessage(
            id: 'message-$i',
            role: i % 5 == 0 ? 'user' : 'assistant',
          ),
      ];
      final scrollController = ChatAutoFollowScrollController();
      final chatScrollController = ChatScrollController(
        scrollController: scrollController,
        onStateChanged: () {},
        getAutoScrollEnabled: () => false,
        getAutoScrollIdleSeconds: () => 8,
      );

      await tester.pumpWidget(
        _ObservedScrollHarness(
          scrollController: scrollController,
          observerController: chatScrollController.observerController,
          messages: messages,
        ),
      );
      scrollController.jumpTo(900);
      await tester.pump();

      final navigation = chatScrollController.jumpToNextMessage(
        messages: messages,
        indexOfId: (id) => messages.indexWhere((message) => message.id == id),
      );
      await tester.pumpAndSettle();
      await navigation;

      expect(chatScrollController.lastJumpMessageId, 'message-19');
      expect(scrollController.offset, greaterThan(900));
      expect(find.text('assistant message-19').hitTestable(), findsOneWidget);
      final beforeRepeat = scrollController.offset;
      final repeated = chatScrollController.jumpToNextMessage(
        messages: messages,
        indexOfId: (id) => messages.indexWhere((message) => message.id == id),
      );
      await tester.pumpAndSettle();
      await repeated;
      expect(chatScrollController.lastJumpMessageId, 'message-20');
      expect(scrollController.offset, greaterThan(beforeRepeat));

      final reverse = chatScrollController.jumpToPreviousMessage(
        messages: messages,
        indexOfId: (id) => messages.indexWhere((message) => message.id == id),
      );
      await tester.pumpAndSettle();
      await reverse;
      expect(chatScrollController.lastJumpMessageId, 'message-19');
      expect(scrollController.offset, closeTo(beforeRepeat, 0.5));

      chatScrollController.dispose();
      scrollController.dispose();
    });
    testWidgets('真实按钮连续点击和切换方向都改变消息位置', (tester) async {
      final messages = [
        for (var i = 0; i < 40; i++)
          _NavMessage(id: 'message-$i', role: 'assistant'),
      ];
      final scroll = ChatAutoFollowScrollController();
      final chat = ChatScrollController(
        scrollController: scroll,
        onStateChanged: () {},
        getAutoScrollEnabled: () => true,
        getAutoScrollIdleSeconds: () => 8,
      );
      await tester.pumpWidget(
        _ObservedScrollHarness(
          scrollController: scroll,
          observerController: chat.observerController,
          messages: messages,
          chatController: chat,
        ),
      );
      chat.setAutoStickToBottom(false);
      scroll.jumpTo(900);
      await tester.pump();
      // Deliberately tap before either navigation animation finishes.
      await tester.tap(find.byIcon(Lucide.ChevronUp));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(find.byIcon(Lucide.ChevronUp));
      await tester.pumpAndSettle();
      expect(chat.lastJumpMessageId, 'message-9');
      expect(scroll.offset, closeTo(600, 0.5));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('message-9'))).dy,
        closeTo(120, 0.5),
      );
      await tester.tap(find.byIcon(Lucide.ChevronDown));
      await tester.pumpAndSettle();
      expect(chat.lastJumpMessageId, 'message-10');
      expect(scroll.offset, closeTo(680, 0.5));
      chat.dispose();
      scroll.dispose();
    });

    testWidgets('长短消息混排时跳到真实位置且上一条全程向上', (tester) async {
      final messages = [
        for (var i = 0; i < 12; i++)
          _NavMessage(
            id: 'message-$i',
            role: 'assistant',
            height: i == 4 || i == 8 ? 1800 : 80,
          ),
      ];
      final scroll = ChatAutoFollowScrollController();
      final chat = ChatScrollController(
        scrollController: scroll,
        onStateChanged: () {},
        getAutoScrollEnabled: () => false,
        getAutoScrollIdleSeconds: () => 8,
      );
      await tester.pumpWidget(
        _ObservedScrollHarness(
          scrollController: scroll,
          observerController: chat.observerController,
          messages: messages,
        ),
      );
      // Start in the middle of message 8, outside the preceding row's cache.
      scroll.jumpTo(3600);
      await tester.pumpAndSettle();
      final offsets = <double>[];
      scroll.addListener(() => offsets.add(scroll.offset));
      final previous = chat.jumpToPreviousMessage(
        messages: messages,
        indexOfId: (id) => messages.indexWhere((m) => m.id == id),
      );
      await tester.pumpAndSettle();
      await previous;
      expect(chat.lastJumpMessageId, 'message-7');
      expect(scroll.offset, closeTo(2160, 0.5));
      for (var i = 1; i < offsets.length; i++) {
        expect(offsets[i], lessThanOrEqualTo(offsets[i - 1] + 0.5));
      }
      final next = chat.jumpToNextMessage(
        messages: messages,
        indexOfId: (id) => messages.indexWhere((m) => m.id == id),
      );
      await tester.pumpAndSettle();
      await next;
      expect(chat.lastJumpMessageId, 'message-8');
      expect(scroll.offset, closeTo(2240, 0.5));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('message-8'))).dy,
        closeTo(120, 0.5),
      );
      chat.dispose();
      scroll.dispose();
    });

    testWidgets('手动滚动取消正在执行及排队的导航并重新定位', (tester) async {
      final messages = [
        for (var i = 0; i < 40; i++)
          _NavMessage(id: 'message-$i', role: 'assistant'),
      ];
      final scroll = ChatAutoFollowScrollController();
      final chat = ChatScrollController(
        scrollController: scroll,
        onStateChanged: () {},
        getAutoScrollEnabled: () => false,
        getAutoScrollIdleSeconds: () => 8,
      );
      await tester.pumpWidget(
        _ObservedScrollHarness(
          scrollController: scroll,
          observerController: chat.observerController,
          messages: messages,
        ),
      );
      scroll.jumpTo(900);
      await tester.pump();
      Future<void> previous() => chat.jumpToPreviousMessage(
        messages: messages,
        indexOfId: (id) => messages.indexWhere((m) => m.id == id),
      );
      final first = previous();
      final queued = previous();
      await tester.pump(const Duration(milliseconds: 40));
      chat.handleUserScrollActivity();
      scroll.jumpTo(1400);
      await tester.pumpAndSettle();
      await Future.wait([first, queued]);
      expect(chat.lastJumpMessageId, isNull);
      expect(scroll.offset, closeTo(1400, 0.5));
      final resumed = previous();
      await tester.pumpAndSettle();
      await resumed;
      expect(chat.lastJumpMessageId, 'message-16');
      expect(scroll.offset, closeTo(1160, 0.5));
      chat.dispose();
      scroll.dispose();
    });

    testWidgets('观察器尚未挂载不阻塞后续点击', (tester) async {
      final messages = [
        for (var i = 0; i < 40; i++)
          _NavMessage(id: 'message-$i', role: 'assistant'),
      ];
      final scroll = ChatAutoFollowScrollController();
      final chat = ChatScrollController(
        scrollController: scroll,
        onStateChanged: () {},
        getAutoScrollEnabled: () => false,
        getAutoScrollIdleSeconds: () => 8,
      );
      await tester.pumpWidget(
        _ScrollHarness(scrollController: scroll, itemCount: 40),
      );
      await chat.jumpToPreviousMessage(
        messages: messages,
        indexOfId: (id) => messages.indexWhere((m) => m.id == id),
      );
      expect(chat.lastJumpMessageId, isNull);
      await tester.pumpWidget(
        _ObservedScrollHarness(
          scrollController: scroll,
          observerController: chat.observerController,
          messages: messages,
        ),
      );
      scroll.jumpTo(900);
      await tester.pump();
      final previous = chat.jumpToPreviousMessage(
        messages: messages,
        indexOfId: (id) => messages.indexWhere((m) => m.id == id),
      );
      await tester.pumpAndSettle();
      await previous;
      expect(scroll.offset, closeTo(680, 0.5));
      chat.dispose();
      scroll.dispose();
    });
  });
}

class _ScrollHarness extends StatelessWidget {
  const _ScrollHarness({
    required this.scrollController,
    required this.itemCount,
  });

  final ScrollController scrollController;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SizedBox(
        height: 600,
        child: ListView.builder(
          controller: scrollController,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            return SizedBox(height: 60, child: Text('Message $index'));
          },
        ),
      ),
    );
  }
}

class _ObservedScrollHarness extends StatelessWidget {
  const _ObservedScrollHarness({
    required this.scrollController,
    required this.observerController,
    required this.messages,
    this.chatController,
  });

  final ScrollController scrollController;
  final ListObserverController observerController;
  final List<_NavMessage> messages;
  final ChatScrollController? chatController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SizedBox(
        height: 600,
        child: Stack(
          children: [
            ListViewObserver(
              controller: observerController,
              child: ListView.builder(
                controller: scrollController,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  return SizedBox(
                    key: ValueKey(message.id),
                    height: message.height,
                    child: Text('${message.role} ${message.id}'),
                  );
                },
              ),
            ),
            if (chatController != null)
              ScrollNavButtonsPanel(
                visible: true,
                onScrollToTop: () => chatController!.scrollToTop(),
                onScrollToBottom: chatController!.forceScrollToBottom,
                onPreviousMessage: () => chatController!.jumpToPreviousMessage(
                  messages: messages,
                  indexOfId: (id) => messages.indexWhere((m) => m.id == id),
                ),
                onNextMessage: () => chatController!.jumpToNextMessage(
                  messages: messages,
                  indexOfId: (id) => messages.indexWhere((m) => m.id == id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavMessage {
  const _NavMessage({required this.id, required this.role, this.height = 80});

  final String id;
  final String role;
  final double height;
}
