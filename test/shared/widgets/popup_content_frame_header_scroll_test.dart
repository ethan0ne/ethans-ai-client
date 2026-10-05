import 'dart:ui' as ui;

import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/popup_content_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (width, scrollControlled) in [
    (390.0, true),
    (390.0, false),
    (840.0, true),
  ]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
        'content scrolls under opaque popup header ($width, $scrollControlled, $brightness)',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 844);
          addTearDown(tester.view.reset);

          const captureKey = ValueKey('screen');
          const listKey = ValueKey('popup-list');
          const firstRowKey = ValueKey('first-row');
          final surface = brightness == Brightness.light
              ? const Color(0xFFE8E8F2)
              : const Color(0xFF181820);
          late BuildContext pageContext;
          await tester.pumpWidget(
            RepaintBoundary(
              key: captureKey,
              child: MaterialApp(
                theme: ThemeData(
                  brightness: brightness,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.blue,
                    brightness: brightness,
                  ).copyWith(surface: surface),
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) {
                      pageContext = context;
                      return const SizedBox.expand();
                    },
                  ),
                ),
              ),
            ),
          );
          final closed = showAppPopupSheet<void>(
            context: pageContext,
            title: 'Form',
            showCloseButton: false,
            isScrollControlled: scrollControlled,
            extendBodyBehindHeader: true,
            builder: (context) => SingleChildScrollView(
              key: listKey,
              padding: PopupContentFrame.scrollPadding(
                context,
                const EdgeInsets.only(top: 12, bottom: 16),
              ),
              child: const Column(
                children: [
                  ColoredBox(
                    key: firstRowKey,
                    color: Color(0xFFFF0000),
                    child: SizedBox(height: 220, width: double.infinity),
                  ),
                  SizedBox(height: 800),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();
          final frame = tester.getRect(find.byType(PopupContentFrame));
          final viewport = tester.getRect(find.byKey(listKey));
          expect(viewport.top, closeTo(frame.top, 0.1));
          expect(
            tester.getTopLeft(find.byKey(firstRowKey)).dy,
            closeTo(frame.top + 80 + 12, 0.1),
          );
          final scrollable = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(listKey),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          scrollable.position.jumpTo(100);
          await tester.pumpAndSettle();
          expect(
            tester.getTopLeft(find.byKey(firstRowKey)).dy,
            lessThan(frame.top),
          );

          // Sample rendered pixels away from the title and drag handle: the row
          // remains painted below the gradient and is covered near the top edge.
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(captureKey),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final x = (frame.center.dx + 70).round();
            List<int> pixel(double localY) {
              final index =
                  ((frame.top + localY).round() * image.width + x) * 4;
              return [
                for (var channel = 0; channel < 3; channel++)
                  bytes.getUint8(index + channel),
              ];
            }

            final top = pixel(4);
            final middle = pixel(70);
            final below = pixel(120);
            final expected = [
              (surface.r * 255).round(),
              (surface.g * 255).round(),
              (surface.b * 255).round(),
            ];
            for (var channel = 0; channel < 3; channel++) {
              expect(top[channel], closeTo(expected[channel], 8));
            }
            expect(middle[1], greaterThan(below[1]));
            expect(middle[1], lessThan(top[1]));
            expect(below, [255, 0, 0]);
            image.dispose();
          });
          expect(tester.takeException(), isNull);
          Navigator.of(tester.element(find.byType(PopupContentFrame))).pop();
          await tester.pumpAndSettle();
          await closed;
        },
      );
    }
  }
}
