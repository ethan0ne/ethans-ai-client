import 'package:Kelivo/shared/widgets/frosted_popup_menu.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Frame {
  const _Frame(this.scale, this.opacity);
  final double scale;
  final double opacity;
}

_Frame _frame(WidgetTester tester, {required bool native}) {
  final action = find.text('Action');
  final transform = tester.widget<Transform>(
    // The app's scroll body also contains a Transform; measure its surface.
    find
        .ancestor(
          of: native ? action : find.byType(BackdropFilter),
          matching: find.byType(Transform),
        )
        .first,
  );
  final fade = tester.widget<FadeTransition>(
    find.ancestor(of: action, matching: find.byType(FadeTransition)).first,
  );
  return _Frame(transform.transform.entry(0, 0), fade.opacity.value);
}

Future<List<_Frame>> _capture(
  WidgetTester tester, {
  required bool native,
  required Size screen,
  required Rect anchor,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.binding.setSurfaceSize(screen);
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            pageContext = context;
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: anchor,
                  child: native
                      ? CupertinoContextMenu(
                          actions: [
                            CupertinoContextMenuAction(
                              child: const Text('Action'),
                            ),
                          ],
                          child: const ColoredBox(
                            key: ValueKey('preview'),
                            color: Colors.blue,
                          ),
                        )
                      : const ColoredBox(color: Colors.blue),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  if (native) {
    final gesture = await tester.startGesture(anchor.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.up();
  } else {
    showFrostedPopupMenuAt(
      pageContext,
      globalAnchorRect: anchor,
      items: [
        FrostedPopupMenuItem(
          icon: Icons.copy,
          label: 'Action',
          onPressed: () {},
        ),
      ],
    );
    await tester.pump();
  }
  // Give each animation its initial frame before advancing its clock.
  await tester.pump();
  final frames = <_Frame>[];
  for (final elapsed in [16, 17, 34, 67, 101, 67]) {
    await tester.pump(Duration(milliseconds: elapsed));
    frames.add(_frame(tester, native: native));
  }
  await tester.pump(const Duration(milliseconds: 33));
  if (native) {
    ModalRoute.of(tester.element(find.text('Action')))!.navigator!.pop();
  } else {
    // The app keeps its transparent outside-tap target and local blur.
    // MaterialApp's base route already has a transparent barrier.
    for (final barrier in tester.widgetList<ModalBarrier>(
      find.byType(ModalBarrier),
    )) {
      expect(barrier.color?.a ?? 0, 0);
    }
    expect(find.byType(AnimatedModalBarrier), findsNothing);
    expect(tester.getSize(find.byType(BackdropFilter)).width, 280);
    await tester.tapAt(Offset(screen.width / 2, screen.height - 20));
  }
  await tester.pump();
  for (final elapsed in [16, 17, 34, 67, 101, 67]) {
    await tester.pump(Duration(milliseconds: elapsed));
    frames.add(_frame(tester, native: native));
  }
  await tester.pumpAndSettle();
  expect(find.text('Action'), findsNothing);
  expect(tester.takeException(), isNull);
  return frames;
}

void main() {
  for (final screen in [const Size(390, 844), const Size(844, 390)]) {
    for (final horizontal in [0.15, 0.5, 0.85]) {
      testWidgets(
        'subtle opening and monotonic closing ($screen, $horizontal)',
        (tester) async {
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final anchor = Rect.fromCenter(
            center: Offset(screen.width * horizontal, 140),
            width: 40,
            height: 40,
          );
          final reference = await _capture(
            tester,
            native: true,
            screen: screen,
            anchor: anchor,
          );
          final actual = await _capture(
            tester,
            native: false,
            screen: screen,
            anchor: anchor,
          );
          expect(actual.length, reference.length);
          for (var i = 0; i < reference.length; i++) {
            if (i < reference.length ~/ 2) {
              expect(
                actual[i].scale,
                closeTo(
                  const Cubic(
                    0.175,
                    0.885,
                    0.32,
                    1.04,
                  ).transform(actual[i].opacity),
                  1e-8,
                ),
                reason: 'frame $i opening scale',
              );
            } else {
              expect(actual[i].scale, inInclusiveRange(0.0, 1.0));
              final previous = i == reference.length ~/ 2
                  ? 1.0
                  : actual[i - 1].scale;
              expect(actual[i].scale, lessThanOrEqualTo(previous));
              expect(
                actual[i].scale,
                closeTo(Curves.easeInCubic.transform(actual[i].opacity), 1e-8),
                reason: 'frame $i closing scale',
              );
            }
            expect(
              actual[i].opacity,
              closeTo(reference[i].opacity, 1e-8),
              reason: 'frame $i opacity',
            );
          }
        },
      );
    }
  }

  testWidgets('action waits for the closing animation', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    var calls = 0;
    final dismissed = showFrostedPopupMenuAt(
      context,
      globalPosition: const Offset(120, 120),
      items: [
        FrostedPopupMenuItem(
          icon: Icons.copy,
          label: 'Action',
          onPressed: () {
            calls++;
          },
        ),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pump();
    expect(calls, 0);
    await tester.pumpAndSettle();
    await dismissed;
    expect(calls, 1);
    expect(find.text('Action'), findsNothing);
  });
}
