import 'dart:ui' show PointerDeviceKind;

import 'package:Kelivo/features/home/widgets/scroll_nav_buttons.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/shared/widgets/app_button_island.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _icons = [
  Lucide.ArrowUpToLine,
  Lucide.ChevronUp,
  Lucide.ChevronDown,
  Lucide.ArrowDownToLine,
];
const _names = ['top', 'previous', 'next', 'bottom'];

class _Harness {
  bool visible = false;
  int backgroundDowns = 0;
  final taps = <String>[];
  final scrollController = ScrollController();
  late StateSetter update;

  Future<void> mount(WidgetTester tester, {bool hover = false}) async {
    addTearDown(scrollController.dispose);
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => backgroundDowns++,
                      child: ListView(
                        controller: scrollController,
                        children: const [SizedBox(height: 4000)],
                      ),
                    ),
                  ),
                  ScrollNavButtonsPanel(
                    visible: visible,
                    hoverEnabled: hover,
                    onHoverChanged: (value) => update(() => visible = value),
                    onScrollToTop: () => taps.add('top'),
                    onPreviousMessage: () => taps.add('previous'),
                    onNextMessage: () => taps.add('next'),
                    onScrollToBottom: () => taps.add('bottom'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void show(bool value) => update(() => visible = value);
}

Finder _island(int index) =>
    find.byKey(ValueKey('scroll-nav-${_names[index]}'));
Finder _scale(int index) =>
    find.descendant(of: _island(index), matching: find.byType(AnimatedScale));
double _paintedScale(WidgetTester tester, int index) {
  final render = tester.renderObject<RenderTransform>(
    find.descendant(of: _scale(index), matching: find.byType(Transform)).first,
  );
  return render.child!.getTransformTo(render).storage[0];
}

void main() {
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    for (var index = 0; index < 4; index++) {
      testWidgets(
        'shared island first press during entry: ${_names[index]} $kind',
        (tester) async {
          final h = _Harness();
          await h.mount(tester);
          h.show(true);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          final entry = tester.getCenter(find.byIcon(_icons[index]));
          expect(entry.dx, lessThan(375));
          final gesture = await tester.startGesture(entry, kind: kind);
          await tester.pump();
          expect(tester.widget<AnimatedScale>(_scale(index)).scale, 1.15);
          await tester.pump(const Duration(milliseconds: 220));
          expect(_paintedScale(tester, index), closeTo(1.15, 0.001));
          expect(h.backgroundDowns, 0);
          expect(
            tester.getCenter(find.byIcon(_icons[index])).dx,
            lessThan(entry.dx),
          );
          await gesture.up();
          await tester.pumpAndSettle();
          expect(h.taps, [_names[index]]);
          expect(_paintedScale(tester, index), closeTo(1, 0.001));
          expect(
            tester.widget<AppButtonIsland>(_island(index)).showBorder,
            isFalse,
          );
        },
      );
    }
  }

  testWidgets(
    'long hold pins visibility through shared island return, then hidden area passes touches',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      h.show(true);
      await tester.pumpAndSettle();
      final position = tester.getCenter(find.byIcon(Lucide.ChevronDown));
      final gesture = await tester.startGesture(position);
      await tester.pump();
      h.show(false);
      await tester.pump(const Duration(seconds: 5));
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        1,
      );
      expect(_paintedScale(tester, 2), closeTo(1.15, 0.001));
      expect(h.taps, isEmpty);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.taps, ['next']);
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        1,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        0,
      );
      await tester.tapAt(position);
      expect(h.backgroundDowns, 1);
      h.show(true);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Lucide.ChevronDown));
      await tester.pumpAndSettle();
      expect(h.taps, ['next', 'next']);
    },
  );

  testWidgets(
    'repress and change buttons during return; cancel does not navigate',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      h.show(true);
      await tester.pumpAndSettle();
      for (final index in [2, 2, 1, 2]) {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(_icons[index])),
        );
        await tester.pump();
        expect(tester.widget<AnimatedScale>(_scale(index)).scale, 1.15);
        await tester.pump(const Duration(milliseconds: 220));
        expect(_paintedScale(tester, index), closeTo(1.15, 0.001));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(h.taps, ['next', 'next', 'previous', 'next']);
      expect(h.backgroundDowns, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Lucide.ChevronDown)),
      );
      await tester.pump();
      h.show(false);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(h.taps, ['next', 'next', 'previous', 'next']);
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        0,
      );
    },
  );

  testWidgets('all four 28px targets receive edge presses and block the list', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    h.show(true);
    await tester.pumpAndSettle();
    expect(find.byType(AppButtonIslandButton), findsNWidgets(4));
    for (var index = 0; index < 4; index++) {
      final rect = tester.getRect(_island(index));
      expect(rect.size, const Size(28, 28));
      await tester.tapAt(rect.topLeft + const Offset(2, 2));
      await tester.pumpAndSettle();
    }
    expect(h.taps, _names);
    expect(h.backgroundDowns, 0);
    h.show(false);
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
          .opacity,
      0,
    );
  });

  for (final exitMs in [40, 120, 200]) {
    testWidgets('a painted button remains tappable ${exitMs}ms into exit', (
      tester,
    ) async {
      final h = _Harness();
      await h.mount(tester);
      h.show(true);
      await tester.pumpAndSettle();
      h.show(false);
      await tester.pump();
      await tester.pump(Duration(milliseconds: exitMs));
      final position = tester.getCenter(find.byIcon(Lucide.ChevronDown));
      expect(position.dx, lessThan(375));
      final gesture = await tester.startGesture(position);
      await tester.pump();
      expect(tester.widget<AnimatedScale>(_scale(2)).scale, 1.15);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_paintedScale(tester, 2), closeTo(1.15, 0.001));
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        1,
      );
      expect(h.backgroundDowns, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(h.taps, ['next']);
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        0,
      );
    });
  }

  testWidgets(
    'shared press paints while background is flinging and after it stops',
    (tester) async {
      final h = _Harness();
      await h.mount(tester);
      h.show(true);
      await tester.pumpAndSettle();
      await tester.fling(find.byType(ListView), const Offset(0, -500), 2000);
      await tester.pump(const Duration(milliseconds: 40));
      expect(h.scrollController.position.isScrollingNotifier.value, isTrue);
      for (final moving in [true, false]) {
        if (!moving) await tester.pumpAndSettle();
        final before = h.scrollController.offset;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Lucide.ChevronDown)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(_paintedScale(tester, 2), closeTo(1.15, 0.001));
        if (moving) expect(h.scrollController.offset, greaterThan(before));
        await tester.pump(const Duration(seconds: 1));
        expect(_paintedScale(tester, 2), closeTo(1.15, 0.001));
        await gesture.up();
        await tester.pumpAndSettle();
      }
      expect(h.taps, ['next', 'next']);
      // Only the actual list fling reached the background.
      expect(h.backgroundDowns, 1);
    },
  );

  testWidgets('desktop hover reveals hidden panel', (tester) async {
    final h = _Harness();
    await h.mount(tester, hover: true);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byKey(scrollNavHoverRegionKey)));
    await tester.pumpAndSettle();
    expect(h.visible, isTrue);
    expect(
      tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
          .opacity,
      1,
    );
  });
}
