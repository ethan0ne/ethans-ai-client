import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/assistant/pages/assistant_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/layouts/app_scaffold.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:Kelivo/shared/widgets/app_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AssistantProvider> pumpAssistantPage(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'assistants_v1': Assistant.encodeList(const [
      Assistant(id: 'first', name: 'First assistant'),
      Assistant(id: 'second', name: 'Second assistant'),
      Assistant(id: 'third', name: 'Third assistant'),
    ]),
  });
  final assistants = AssistantProvider();
  final settings = SettingsProvider();
  addTearDown(assistants.dispose);
  addTearDown(settings.dispose);
  for (var i = 0; i < 20 && assistants.assistants.length != 3; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AssistantProvider>.value(value: assistants),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const AssistantSettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return assistants;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('assistant page uses one continuous grouped list and title', (
    tester,
  ) async {
    await pumpAssistantPage(tester);

    expect(find.text('First assistant'), findsOneWidget);
    expect(find.text('Second assistant'), findsOneWidget);
    expect(find.text('Third assistant'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppScaffold), matching: find.text('助手')),
      findsOneWidget,
    );
    expect(find.byType(AppListGroup), findsNWidgets(3));
    expect(find.byType(AppListDivider), findsNWidgets(2));

    final rows = find.byType(AppListTile);
    final dividers = find.byType(AppListDivider);
    for (var index = 0; index < 2; index++) {
      expect(
        tester.getBottomLeft(rows.at(index)).dy,
        closeTo(tester.getTopLeft(dividers.at(index)).dy, 0.01),
      );
      expect(
        tester.getBottomLeft(dividers.at(index)).dy,
        closeTo(tester.getTopLeft(rows.at(index + 1)).dy, 0.01),
      );
    }
    expect(tester.takeException(), isNull);
  });
  for (final dragged in [
    'First assistant',
    'Second assistant',
    'Third assistant',
  ]) {
    testWidgets('dragging $dragged updates group edges and proxy', (
      tester,
    ) async {
      await pumpAssistantPage(tester);
      Finder group(String name) => find.ancestor(
        of: find.text(name),
        matching: find.byType(AppListGroup),
      );
      BorderRadius radius(String name) =>
          tester.widget<AppListGroup>(group(name)).borderRadius as BorderRadius;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(dragged)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 300));
      expect(radius(dragged), const BorderRadius.all(Radius.circular(20)));
      expect(
        find.descendant(
          of: group(dragged),
          matching: find.byType(AppListDivider),
        ),
        findsNothing,
      );
      final remaining = [
        'First assistant',
        'Second assistant',
        'Third assistant',
      ].where((name) => name != dragged).toList();
      expect(radius(remaining.first).topLeft, const Radius.circular(20));
      expect(radius(remaining.first).bottomLeft, Radius.zero);
      expect(radius(remaining.last).topLeft, Radius.zero);
      expect(radius(remaining.last).bottomLeft, const Radius.circular(20));
      await gesture.up();
      await tester.pumpAndSettle();
      // Dropping in the original position must restore the full group, too.
      expect(radius('First assistant').topLeft, const Radius.circular(20));
      expect(radius('First assistant').bottomLeft, Radius.zero);
      expect(radius('Second assistant'), BorderRadius.zero);
      expect(radius('Third assistant').bottomLeft, const Radius.circular(20));
      expect(find.byType(AppListDivider), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('dropping the first assistant last follows the new order', (
    tester,
  ) async {
    final assistants = await pumpAssistantPage(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('First assistant')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveTo(
      tester.getBottomLeft(find.text('Third assistant')) + const Offset(80, 65),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(assistants.assistants.map((item) => item.id), [
      'second',
      'third',
      'first',
    ]);
    final lastGroup = find.ancestor(
      of: find.text('First assistant'),
      matching: find.byType(AppListGroup),
    );
    expect(
      (tester.widget<AppListGroup>(lastGroup).borderRadius as BorderRadius)
          .bottomLeft,
      const Radius.circular(20),
    );
    expect(
      find.descendant(of: lastGroup, matching: find.byType(AppListDivider)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
