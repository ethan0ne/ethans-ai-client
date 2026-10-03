import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/world_book.dart';
import 'package:Kelivo/core/models/instruction_injection.dart';
import 'package:Kelivo/features/world_book/pages/world_book_page.dart';
import 'package:Kelivo/features/instruction_injection/pages/instruction_injection_page.dart';
import 'package:Kelivo/shared/layouts/app_scaffold.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/instruction_injection_group_provider.dart';
import 'package:Kelivo/core/providers/memory_provider.dart';
import 'package:Kelivo/core/providers/quick_phrase_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/assistant/pages/assistant_settings_edit_page.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

const _assistantId = 'assistant-mcp-test';

void _seedPreferences() {
  SharedPreferences.setMockInitialValues({
    'assistants_v1': Assistant.encodeList(const [
      Assistant(id: _assistantId, name: 'Test Assistant', temperature: 0.6),
    ]),
  });
}

Future<AssistantProvider> _createAssistantProvider(WidgetTester tester) async {
  final provider = AssistantProvider();
  for (var i = 0; i < 25; i++) {
    if (provider.getById(_assistantId) != null) return provider;
    await tester.pump(const Duration(milliseconds: 10));
  }
  return provider;
}

Widget _buildHarness({
  required AssistantProvider assistantProvider,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider(
        create: (_) => InstructionInjectionGroupProvider(),
      ),
      ChangeNotifierProvider.value(value: assistantProvider),
      ChangeNotifierProvider(create: (_) => MemoryProvider()),
      ChangeNotifierProvider(create: (_) => QuickPhraseProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('assistant edit page shows MCP tab on mobile', (tester) async {
    _seedPreferences();
    final assistantProvider = await _createAssistantProvider(tester);

    await tester.pumpWidget(
      _buildHarness(
        assistantProvider: assistantProvider,
        child: const AssistantSettingsEditPage(assistantId: _assistantId),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('MCP'), findsOneWidget);
  });

  testWidgets('assistant local tools page uses clock icon for time info', (
    tester,
  ) async {
    _seedPreferences();
    final assistantProvider = await _createAssistantProvider(tester);

    await tester.pumpWidget(
      _buildHarness(
        assistantProvider: assistantProvider,
        child: const AssistantSettingsEditPage(assistantId: _assistantId),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await Scrollable.ensureVisible(
      tester.element(find.text('Local Tools')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local Tools'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Time Info'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Icon && widget.icon == Lucide.clock,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Icon && widget.icon == Lucide.Calendar,
      ),
      findsNothing,
    );
  });

  testWidgets('assistant desktop dialog shows MCP menu item', (tester) async {
    _seedPreferences();
    final assistantProvider = await _createAssistantProvider(tester);

    await tester.pumpWidget(
      _buildHarness(
        assistantProvider: assistantProvider,
        child: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showAssistantDesktopDialog(
                  context,
                  assistantId: _assistantId,
                ),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('MCP'), findsOneWidget);
  });
  for (final populated in [false, true]) {
    for (final books in [false, true]) {
      testWidgets(
        'embedded prompt assets use the page viewport (books $books, populated $populated)',
        (tester) async {
          tester.view.physicalSize = const Size(375, 664);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(top: 47);
          tester.view.viewPadding = const FakeViewPadding(top: 47);
          addTearDown(tester.view.reset);
          SharedPreferences.setMockInitialValues({
            'assistants_v1': Assistant.encodeList([
              Assistant(
                id: _assistantId,
                name: 'Test',
                worldBooks: populated
                    ? List.generate(
                        20,
                        (i) => WorldBook(id: 'book-$i', name: 'Book $i'),
                      )
                    : [],
                instructionInjections: populated
                    ? List.generate(
                        20,
                        (i) => InstructionInjection(
                          id: 'item-$i',
                          title: 'Item $i',
                          prompt: 'Prompt',
                        ),
                      )
                    : [],
              ),
            ]),
          });
          final assistant = await _createAssistantProvider(tester);
          await tester.pumpWidget(
            _buildHarness(
              assistantProvider: assistant,
              child: AppScaffold(
                title: const Text('Assets'),
                appBarBottom: const PreferredSize(
                  preferredSize: Size.fromHeight(52),
                  child: SizedBox(height: 52),
                ),
                body: books
                    ? const WorldBookPage(
                        assistantId: _assistantId,
                        embedded: true,
                      )
                    : const InstructionInjectionPage(
                        assistantId: _assistantId,
                        embedded: true,
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final view = populated
              ? (books
                    ? find.byType(ReorderableListView)
                    : find.byType(ListView))
              : find.byType(CustomScrollView);
          expect(tester.getTopLeft(view.first).dy, 0);
          if (populated) {
            final scroll = tester
                .stateList<ScrollableState>(find.byType(Scrollable))
                .firstWhere(
                  (s) =>
                      axisDirectionToAxis(s.position.axisDirection) ==
                      Axis.vertical,
                );
            scroll.position.jumpTo(200);
            await tester.pumpAndSettle();
            expect(tester.getTopLeft(view.first).dy, 0);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
