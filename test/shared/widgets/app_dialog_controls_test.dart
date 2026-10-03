import 'package:Kelivo/shared/widgets/app_dialog.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:Kelivo/shared/widgets/app_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget reminder({
    required ValueChanged<bool>? onChanged,
    TextDirection direction = TextDirection.ltr,
    String label = 'Do not remind me again',
    double textScale = 1,
  }) => MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      listTileTheme: const ListTileThemeData(tileColor: Colors.green),
    ),
    home: Scaffold(
      body: Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: AppDialog(
            title: 'Title',
            actions: const [],
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dialog body'),
                AppDialogCheckboxTile(
                  value: false,
                  label: label,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('visible checkbox edge aligns to body in both directions', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        reminder(onChanged: (_) {}, direction: direction),
      );
      final body = tester.getRect(find.text('Dialog body'));
      final center = tester.getCenter(find.byType(Checkbox));
      final edge =
          center.dx +
          (direction == TextDirection.ltr
              ? -Checkbox.width / 2
              : Checkbox.width / 2);
      expect(
        edge,
        closeTo(direction == TextDirection.ltr ? body.left : body.right, 0.01),
      );
      final labelStyle = tester
          .widget<ListTile>(find.byType(ListTile))
          .titleTextStyle!;
      final bodyStyle = DefaultTextStyle.of(
        tester.element(find.text('Dialog body')),
      ).style;
      expect(labelStyle.fontSize, bodyStyle.fontSize);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('label press highlights only the checkbox and toggles once', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(reminder(onChanged: changes.add));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Do not remind me again')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    final halo = find.byType(AnimatedOpacity);
    expect(tester.widget<AnimatedOpacity>(halo).opacity, 1);
    expect(tester.getSize(halo).width, lessThan(48));
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.tileColor, Colors.transparent);
    expect(tile.selectedTileColor, Colors.transparent);
    final ink = tester.widget<InkWell>(find.byType(InkWell).first);
    expect(ink.splashFactory, NoSplash.splashFactory);
    expect(
      ink.overlayColor!.resolve({WidgetState.pressed}),
      Colors.transparent,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(tester.widget<AnimatedOpacity>(halo).opacity, 0);
  });

  testWidgets(
    'disabled checkbox ignores taps; keyboard can toggle enabled one',
    (tester) async {
      await tester.pumpWidget(reminder(onChanged: null));
      await tester.tap(find.text('Do not remind me again'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      final changes = <bool>[];
      await tester.pumpWidget(reminder(onChanged: changes.add));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(changes, [true]);
    },
  );

  testWidgets('long localized labels wrap with enlarged text', (tester) async {
    for (final label in [
      'Do not remind me again when deleting summarized conversation contents',
      '下次不再提醒删除已压缩的对话内容',
      '下次不再提醒刪除已壓縮的對話內容',
    ]) {
      await tester.pumpWidget(
        reminder(onChanged: (_) {}, label: label, textScale: 1.8),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.text(label)).height, greaterThan(30));
    }
  });

  testWidgets('dialog scope removes inherited row and group backgrounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          listTileTheme: const ListTileThemeData(tileColor: Colors.green),
        ),
        home: Scaffold(
          body: Column(
            children: [
              AppListTile(title: const Text('Page row'), onTap: () {}),
              AppDialogSurface(
                child: AppListGroup(
                  child: AppListTile(
                    title: const Text('Dialog row'),
                    onTap: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(AppDialogControlTile), findsOneWidget);
    final rowContext = tester.element(find.text('Dialog row'));
    expect(Theme.of(rowContext).listTileTheme.tileColor, Colors.transparent);
    expect(AppDialogControlScope.of(rowContext), isTrue);
    expect(
      AppDialogControlScope.of(tester.element(find.text('Page row'))),
      isFalse,
    );
    final groupContainer = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AppListGroup),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (groupContainer.decoration! as BoxDecoration).color,
      Colors.transparent,
    );
  });
}
