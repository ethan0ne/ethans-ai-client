import 'package:Kelivo/features/home/widgets/chat_input_overlay_layout.dart';
import 'package:flutter/material.dart';
import 'package:Kelivo/shared/widgets/top_scroll_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('内容铺满可用区域，底部覆盖层贴住底部', (tester) async {
    const rootKey = Key('root');
    const contentKey = Key('content');
    const overlayKey = Key('overlay');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: rootKey,
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: ColoredBox(key: contentKey, color: Colors.blue),
              bottomOverlay: SizedBox(key: overlayKey, width: 200, height: 50),
            ),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(contentKey)).dy, 0);
    expect(tester.getBottomLeft(find.byKey(contentKey)).dy, 600);
    expect(tester.getTopLeft(find.byKey(overlayKey)).dy, 550);
  });

  testWidgets('底部覆盖层内的居中包装不会把输入框推到中间', (tester) async {
    const overlayKey = Key('overlay');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: ColoredBox(color: Colors.blue),
              bottomOverlay: Center(
                child: SizedBox(key: overlayKey, width: 200, height: 50),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(overlayKey)).dy, 550);
  });

  testWidgets('输入框层位于前景遮罩上方', (tester) async {
    var inputTaps = 0;
    var foregroundTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: const ColoredBox(color: Colors.blue),
              foreground: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => foregroundTaps++,
              ),
              bottomOverlay: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => inputTaps++,
                child: const SizedBox(width: 400, height: 88),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(200, 560));
    await tester.pump();

    expect(inputTaps, 1);
    expect(foregroundTaps, 0);
  });

  testWidgets('底部覆盖层后方有渐变遮罩隔开消息内容', (tester) async {
    const fadeKey = Key('chat-input-overlay-bottom-fade');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: ColoredBox(color: Colors.blue),
              bottomOverlay: SizedBox(width: 200, height: 50),
            ),
          ),
        ),
      ),
    );

    final fadeFinder = find.byKey(fadeKey);
    expect(fadeFinder, findsOneWidget);
    expect(tester.getTopLeft(fadeFinder).dy, 420);
    expect(tester.getBottomLeft(fadeFinder).dy, 600);

    final decoration = tester.widget<DecoratedBox>(
      find.descendant(of: fadeFinder, matching: find.byType(DecoratedBox)),
    );
    final boxDecoration = decoration.decoration as BoxDecoration;
    final gradient = boxDecoration.gradient as LinearGradient;
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
    expect(gradient.colors.first.a, 0);
    expect(gradient.colors[1].a, greaterThan(0.80));
    expect(gradient.colors.last.a, greaterThan(0.95));
  });

  testWidgets('顶部导航栏后方有渐变遮罩隔开消息内容', (tester) async {
    const fadeKey = Key('chat-input-overlay-top-fade');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              content: ColoredBox(color: Colors.blue),
              bottomOverlay: SizedBox(width: 200, height: 50),
            ),
          ),
        ),
      ),
    );

    final fadeFinder = find.byKey(fadeKey);
    expect(fadeFinder, findsOneWidget);
    expect(tester.getTopLeft(fadeFinder).dy, 0);
    expect(tester.getBottomLeft(fadeFinder).dy, 132);

    final decoration = tester.widget<DecoratedBox>(
      find.descendant(of: fadeFinder, matching: find.byType(DecoratedBox)),
    );
    final boxDecoration = decoration.decoration as BoxDecoration;
    final gradient = boxDecoration.gradient as LinearGradient;
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
    expect(gradient.colors.first.a, closeTo(0.9, 0.01));
    expect(gradient.colors, hasLength(2));
    expect(gradient.colors.last.a, 0);
  });

  testWidgets('背景图模式顶部仍使用共享主题渐变', (tester) async {
    const bottomFadeKey = Key('chat-input-overlay-bottom-fade');
    const bottomBackgroundKey = Key('chat-input-overlay-bottom-background');
    const topFadeKey = Key('chat-input-overlay-top-fade');
    const backgroundKey = Key('background');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatInputOverlayLayout(
              topInset: 100,
              backgroundImageActive: true,
              background: ColoredBox(key: backgroundKey, color: Colors.green),
              backgroundFade: ColoredBox(
                key: backgroundKey,
                color: Colors.green,
              ),
              content: ColoredBox(color: Colors.blue),
              bottomOverlay: SizedBox(width: 200, height: 50),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(bottomFadeKey), findsNothing);
    expect(find.byKey(bottomBackgroundKey), findsOneWidget);
    expect(find.byKey(topFadeKey), findsOneWidget);
    expect(find.byType(TopScrollOverlay), findsOneWidget);
    expect(find.byKey(backgroundKey), findsNWidgets(2));

    final topOverlay = find.byType(TopScrollOverlay);
    expect(tester.getTopLeft(topOverlay).dy, 0);
    expect(tester.getBottomLeft(topOverlay).dy, 132);

    final bottomClipRect = tester.widget<ClipRect>(
      find.ancestor(
        of: find.byKey(bottomBackgroundKey),
        matching: find.byType(ClipRect),
      ),
    );
    final bottomClip = bottomClipRect.clipper!.getClip(const Size(400, 600));
    expect(bottomClip.top, 420);
    expect(bottomClip.height, 180);
  });
  testWidgets(
    'chat content uses the settings screen-top fade after scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(375, 664);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 47);
      tester.view.viewPadding = const FakeViewPadding(top: 47);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputOverlayLayout(
              topInset: 103,
              content: ListView.builder(
                padding: const EdgeInsets.only(top: 113),
                itemCount: 30,
                itemExtent: 50,
                itemBuilder: (_, i) => Text('Row $i'),
              ),
              bottomOverlay: const SizedBox(height: 60),
            ),
          ),
        ),
      );
      final overlay = find.byType(TopScrollOverlay);
      final opacity = find.ancestor(
        of: overlay,
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.getTopLeft(find.byType(ListView)).dy, 0);
      expect(tester.getTopLeft(overlay).dy, 0);
      expect(tester.widget<TopScrollOverlay>(overlay).topBandHeight, 47);
      expect(tester.widget<TopScrollOverlay>(overlay).gradientHeight, 56);
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
      expect(tester.getTopLeft(overlay).dy, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
