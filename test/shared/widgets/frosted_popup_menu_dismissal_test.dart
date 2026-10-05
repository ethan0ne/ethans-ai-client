import 'package:Kelivo/shared/widgets/frosted_popup_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(Future<void>, ValueNotifier<int>)> _open(
  WidgetTester tester, {
  double keyboard = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  final actions = ValueNotifier(0);
  addTearDown(actions.dispose);
  late BuildContext page;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            page = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  final dismissed = showFrostedPopupMenuAt(
    page,
    title: 'Menu',
    globalPosition: const Offset(120, 480),
    items: [
      FrostedPopupMenuItem(
        icon: Icons.folder,
        label: 'First',
        children: [
          FrostedPopupMenuItem(
            icon: Icons.folder,
            label: 'Second',
            children: [
              for (var index = 0; index < (keyboard == 0 ? 2 : 5); index++)
                FrostedPopupMenuItem(
                  icon: Icons.code,
                  label: 'Leaf $index',
                  description: 'Description',
                  onPressed: () => actions.value++,
                ),
            ],
          ),
        ],
      ),
      FrostedPopupMenuItem(
        icon: Icons.delete,
        label: 'Background action',
        onPressed: () => actions.value++,
      ),
    ],
  );
  await tester.pumpAndSettle();
  return (dismissed, actions);
}

List<Rect> _surfaces(WidgetTester tester) => [
  for (final element in find.byType(BackdropFilter).evaluate())
    tester.getRect(find.byElementPredicate((value) => value == element)),
];

void _expectSharedAnchor(List<Rect> before, List<Rect> after, Offset anchor) {
  expect(after.length, before.length);
  final scale = after.first.width / before.first.width;
  expect(scale, greaterThan(0));
  expect(scale, lessThan(1));
  for (var index = 0; index < before.length; index++) {
    final expectedTop = anchor + (before[index].topLeft - anchor) * scale;
    final expectedBottom =
        anchor + (before[index].bottomRight - anchor) * scale;
    expect((after[index].topLeft - expectedTop).distance, lessThan(0.001));
    expect(
      (after[index].bottomRight - expectedBottom).distance,
      lessThan(0.001),
    );
  }
}

void main() {
  for (final keyboard in [0.0, 320.0]) {
    testWidgets('all three levels dismiss toward the root anchor ($keyboard)', (
      tester,
    ) async {
      final (dismissed, actions) = await _open(tester, keyboard: keyboard);
      final root = _surfaces(tester).single;
      final anchor = Offset(120, keyboard == 0 ? root.top : root.bottom);
      await tester.tap(find.text('First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second').last);
      await tester.pumpAndSettle();
      final before = _surfaces(tester);
      expect(before.length, 3);
      await tester.tapAt(const Offset(5, 820));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 67));
      _expectSharedAnchor(before, _surfaces(tester), anchor);
      await tester.pumpAndSettle();
      await dismissed;
      expect(find.byType(FrostedPopupMenu), findsNothing);
      expect(actions.value, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('blank dismissal freezes an unfinished submenu transition', (
    tester,
  ) async {
    final (dismissed, actions) = await _open(tester);
    final root = _surfaces(tester).single;
    await tester.tap(find.text('First'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 84));
    final before = _surfaces(tester);
    await tester.tapAt(const Offset(5, 820));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 67));
    _expectSharedAnchor(before, _surfaces(tester), Offset(120, root.top));
    await tester.pumpAndSettle();
    await dismissed;
    expect(actions.value, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposed background rows return without executing actions', (
    tester,
  ) async {
    final (dismissed, actions) = await _open(tester, keyboard: 320);
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second').last);
    await tester.pumpAndSettle();
    final surfaces = _surfaces(tester);
    final row = tester.getRect(
      find
          .ancestor(
            of: find.text('Background action'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(row.bottom, greaterThan(surfaces.last.bottom));
    final point = Offset(
      row.center.dx,
      (row.bottom + surfaces.last.bottom) / 2,
    );
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(actions.value, 0);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('Leaf 0'), findsNothing);
    await tester.tapAt(const Offset(5, 820));
    await tester.pumpAndSettle();
    await dismissed;
    expect(actions.value, 0);
    expect(tester.takeException(), isNull);
  });
}
