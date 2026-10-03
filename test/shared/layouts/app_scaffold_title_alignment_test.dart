import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/shared/layouts/app_scaffold.dart';
import 'package:Kelivo/shared/widgets/app_button_island.dart';
import 'package:Kelivo/shared/widgets/top_scroll_overlay.dart';

void main() {
  for (final width in [320.0, 375.0]) {
    for (final multiple in [false, true]) {
      testWidgets('left title follows islands at $width, multiple=$multiple', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 812),
                padding: const EdgeInsets.only(top: 47, left: 8, right: 8),
                viewPadding: const EdgeInsets.only(top: 47, left: 8, right: 8),
              ),
              child: AppScaffold(
                centerTitle: false,
                extendBodyBehindAppBar: false,
                showTopScrollOverlay: false,
                leadingIslands: [
                  [AppButtonIslandButton(icon: Icons.arrow_back, onTap: () {})],
                  if (multiple)
                    [AppButtonIslandButton(icon: Icons.close, onTap: () {})],
                ],
                title: const AppScaffoldTitle(
                  '一个很长的网页标题 Long webpage title with more text',
                ),
                actions: [
                  AppButtonIslandButton(icon: Icons.refresh, onTap: () {}),
                ],
                body: const SizedBox.expand(key: ValueKey('web-content')),
              ),
            ),
          ),
        );
        // The first frame already uses the actual island widths.
        final islands = find.byType(AppButtonIsland);
        final title = find.byType(AppScaffoldTitle);
        final lastLeading = islands.at(multiple ? 1 : 0);
        expect(
          tester.getTopLeft(title).dx,
          closeTo(tester.getTopRight(lastLeading).dx + 12, 0.01),
        );
        expect(
          tester.getTopRight(title).dx,
          lessThanOrEqualTo(tester.getTopLeft(islands.last).dx - 12),
        );
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('web-content'))).dy,
          47 + 56,
        );
        expect(find.byType(TopScrollOverlay), findsNothing);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('left title without islands uses the page edge', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppScaffold(
          centerTitle: false,
          title: AppScaffoldTitle('Web'),
          body: SizedBox(),
        ),
      ),
    );
    expect(tester.getTopLeft(find.byType(AppScaffoldTitle)).dx, 16);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('default title remains screen centered', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppScaffold(
          leadingIslands: [
            [AppButtonIslandButton(icon: Icons.arrow_back, onTap: () {})],
          ],
          title: const AppScaffoldTitle('Settings'),
          body: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.byType(AppScaffoldTitle)).dx, 400);
    expect(tester.takeException(), isNull);
  });
}
