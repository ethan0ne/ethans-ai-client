import 'package:Kelivo/shared/widgets/frosted_popup_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectNormalText(WidgetTester tester, String label) {
  // A retained background menu may contain the same label as the pinned header.
  final text = find.text(label).last;
  expect(text, findsOneWidget);
  final richText = tester.widget<RichText>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  final style = richText.text.style!;
  expect(style.decoration, anyOf(isNull, TextDecoration.none));
  expect(style.decorationStyle, isNot(TextDecorationStyle.double));
}

void main() {
  for (final keyboardHeight in [0.0, 320.0]) {
    for (final childCount in [2, 12]) {
      testWidgets(
        'overlay text and submenu geometry ($keyboardHeight, $childCount)',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
          addTearDown(tester.view.reset);
          late BuildContext pageContext;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    pageContext = context;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          );
          var calls = 0;
          final dismissed = showFrostedPopupMenuAt(
            pageContext,
            globalPosition: const Offset(120, 480),
            title: '插入变量',
            items: [
              FrostedPopupMenuItem(
                icon: Icons.folder_open,
                label: '设备与环境',
                children: [
                  for (var index = 0; index < childCount; index++)
                    FrostedPopupMenuItem(
                      icon: Icons.code,
                      label: '变量 $index',
                      description: '{{variable_$index}}',
                      onPressed: () => calls++,
                    ),
                ],
              ),
            ],
          );
          await tester.pumpAndSettle();
          _expectNormalText(tester, '插入变量');
          _expectNormalText(tester, '设备与环境');
          expect(tester.takeException(), isNull);
          final parent = tester.getRect(find.byType(BackdropFilter));
          await tester.tap(find.text('设备与环境'));
          await tester.pumpAndSettle();
          _expectNormalText(tester, '设备与环境');
          _expectNormalText(tester, '变量 0');
          _expectNormalText(tester, '{{variable_0}}');
          expect(find.byType(BackdropFilter), findsNWidgets(2));
          final background = tester.getRect(find.byType(BackdropFilter).first);
          final surface = tester.getRect(find.byType(BackdropFilter).last);
          expect(background.top, closeTo(parent.top, 0.001));
          expect(background.width, closeTo(parent.width * 0.96, 0.001));
          expect(background.height, closeTo(parent.height * 0.96, 0.001));
          final fitsBelow =
              parent.top + 8 + 69 + childCount * 64 <= 844 - keyboardHeight - 8;
          if (fitsBelow) {
            expect(surface.top, closeTo(background.top + 8, 0.001));
          } else {
            expect(surface.top, lessThan(background.top));
          }
          expect(surface.top, greaterThanOrEqualTo(8));
          expect(surface.bottom, lessThanOrEqualTo(844 - keyboardHeight - 8));
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('设备与环境').last);
          await tester.pumpAndSettle();
          expect(find.byType(BackdropFilter), findsOneWidget);
          expect(tester.getRect(find.byType(BackdropFilter)), parent);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('设备与环境'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('变量 0'));
          await tester.pumpAndSettle();
          await dismissed;
          expect(calls, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
