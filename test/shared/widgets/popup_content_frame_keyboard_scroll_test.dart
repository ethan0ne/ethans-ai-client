import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/popup_content_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scroll end keeps the final field visible above the keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);

    const listKey = ValueKey('form-scroll');
    const lastFieldKey = ValueKey('last-field');
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
    final closed = showAppPopupSheet<void>(
      context: pageContext,
      title: 'Form',
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
        key: listKey,
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: const Column(
          children: [
            SizedBox(height: 96, child: Text('Name')),
            SizedBox(height: 240, child: Text('Description')),
            SizedBox(height: 64, key: lastFieldKey, child: Text('Enabled')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final keyboardHeight in [320.0, 360.0, 0.0, 320.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
      tester.view.padding = FakeViewPadding(
        bottom: keyboardHeight == 0 ? 34 : 0,
      );
      await tester.pumpAndSettle();

      final list = find.byKey(listKey);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(list);
      final lastField = tester.getRect(find.byKey(lastFieldKey));
      expect(viewport.bottom, lessThanOrEqualTo(844 - keyboardHeight + 0.1));
      expect(lastField.top, greaterThanOrEqualTo(viewport.top));
      expect(lastField.bottom, lessThanOrEqualTo(viewport.bottom));
      // Content shorter than the viewport has no scroll range. Otherwise,
      // only the form's ordinary 16 px trailing padding remains at scroll end.
      if (scrollable.position.maxScrollExtent > 0) {
        expect(viewport.bottom - lastField.bottom, closeTo(16, 0.1));
      }
      expect(tester.takeException(), isNull);
    }

    Navigator.of(tester.element(find.byType(PopupContentFrame))).pop();
    await tester.pumpAndSettle();
    await closed;
  });
}
