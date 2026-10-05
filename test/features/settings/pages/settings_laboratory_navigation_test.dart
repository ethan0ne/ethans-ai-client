import 'package:Kelivo/core/providers/auth_provider.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/backup_reminder_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/backup/pages/backup_page.dart';
import 'package:Kelivo/features/settings/pages/laboratory_page.dart';
import 'package:Kelivo/features/settings/pages/debug_development_page.dart';
import 'package:Kelivo/features/settings/pages/display_settings_page.dart';
import 'package:Kelivo/features/mcp/pages/mcp_page.dart';
import 'package:Kelivo/features/search/pages/search_services_page.dart';
import 'package:Kelivo/features/settings/pages/network_proxy_page.dart';
import 'package:Kelivo/features/settings/pages/settings_page.dart';
import 'package:Kelivo/features/stats/pages/stats_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/app_dialog.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedOutAuth extends ChangeNotifier implements AuthProvider {
  @override
  Null get user => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final locale in [
    const Locale('en'),
    const Locale('zh'),
    const Locale('zh', 'Hant'),
  ]) {
    testWidgets('laboratory groups and settings navigation ($locale)', (
      tester,
    ) async {
      final settings = SettingsProvider();
      final auth = _SignedOutAuth();
      final chat = ChatService();
      final reminder = BackupReminderProvider(autoLoad: false);
      await reminder.load(startTimer: false);
      addTearDown(settings.dispose);
      addTearDown(auth.dispose);
      addTearDown(chat.dispose);
      addTearDown(reminder.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<ChatService>.value(value: chat),
            ChangeNotifierProvider<AssistantProvider>(
              create: (_) => AssistantProvider(chatService: chat),
            ),
            ChangeNotifierProvider<McpProvider>(create: (_) => McpProvider()),
            ChangeNotifierProvider<BackupReminderProvider>.value(
              value: reminder,
            ),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(SettingsPage)),
      )!;
      await tester.scrollUntilVisible(
        find.text(l10n.settingsPageModelsServicesSection),
        180,
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsPageModelsServicesSection), findsOneWidget);
      final servicesCard = find
          .ancestor(
            of: find.text(l10n.settingsPageAssistant),
            matching: find.byType(AppListGroup),
          )
          .first;
      for (final label in [
        l10n.settingsPageSearch,
        l10n.settingsPageMcp,
        l10n.settingsPageNetworkProxy,
      ]) {
        expect(
          find.descendant(of: servicesCard, matching: find.text(label)),
          findsNothing,
        );
      }

      await tester.scrollUntilVisible(
        find.text(l10n.displaySettingsPageLanguageTitle),
        180,
      );
      await tester.pumpAndSettle();
      final generalCard = find
          .ancestor(
            of: find.text(l10n.displaySettingsPageLanguageTitle),
            matching: find.byType(AppListGroup),
          )
          .first;
      expect(generalCard, findsOneWidget);
      expect(
        find.descendant(
          of: generalCard,
          matching: find.text(l10n.settingsPageAppearanceAndTheme),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: generalCard,
          matching: find.text(l10n.settingsPageDisplay),
        ),
        findsNothing,
      );
      expect(
        tester.getTopLeft(find.text(l10n.displaySettingsPageLanguageTitle)).dy,
        lessThan(
          tester.getTopLeft(find.text(l10n.settingsPageAppearanceAndTheme)).dy,
        ),
      );
      expect(
        find.descendant(
          of: generalCard,
          matching: find.text(l10n.settingsPageChatStorage),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: generalCard,
          matching: find.text(l10n.settingsPageLaboratory),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: generalCard,
          matching: find.text(l10n.settingsPageAbout),
        ),
        findsOneWidget,
      );
      final labEntry = find.text(l10n.settingsPageLaboratory);
      await tester.scrollUntilVisible(labEntry, 180);
      expect(find.text(l10n.settingsPageBackup), findsNothing);
      await tester.tap(labEntry);
      await tester.pumpAndSettle();
      expect(find.byType(LaboratoryPage), findsOneWidget);

      final labGroups = find.byType(AppListGroup);
      expect(labGroups, findsNWidgets(6));
      final secondGroup = labGroups.at(1);
      final thirdGroup = labGroups.at(2);
      final fourthGroup = labGroups.at(3);
      final fifthGroup = labGroups.at(4);
      final sixthGroup = labGroups.at(5);
      for (final label in [
        l10n.settingsPageMcp,
        l10n.settingsPageSearch,
        l10n.settingsPageNetworkProxy,
      ]) {
        expect(
          find.descendant(of: secondGroup, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: thirdGroup,
          matching: find.text(l10n.settingsPageDisplay),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: fourthGroup,
          matching: find.text(l10n.settingsPageBackup),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: fifthGroup,
          matching: find.text(l10n.settingsPageStatistics),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sixthGroup,
          matching: find.text(l10n.settingsPageDebugAndDevelopment),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text(l10n.settingsPageMcp)).dy,
        lessThan(tester.getTopLeft(find.text(l10n.settingsPageSearch)).dy),
      );
      expect(
        tester.getTopLeft(find.text(l10n.settingsPageSearch)).dy,
        lessThan(
          tester.getTopLeft(find.text(l10n.settingsPageNetworkProxy)).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text(l10n.settingsPageNetworkProxy)).dy,
        lessThan(tester.getTopLeft(find.text(l10n.settingsPageDisplay)).dy),
      );
      expect(
        tester.getTopLeft(find.text(l10n.settingsPageDisplay)).dy,
        lessThan(tester.getTopLeft(find.text(l10n.settingsPageBackup)).dy),
      );
      expect(
        tester.getTopLeft(find.text(l10n.settingsPageBackup)).dy,
        lessThan(tester.getTopLeft(find.text(l10n.settingsPageStatistics)).dy),
      );
      expect(
        tester.getTopLeft(find.text(l10n.settingsPageStatistics)).dy,
        lessThan(
          tester.getTopLeft(find.text(l10n.settingsPageDebugAndDevelopment)).dy,
        ),
      );

      final statsEntry = find.text(l10n.settingsPageStatistics);
      expect(statsEntry, findsOneWidget);
      final preferencesEntry = find.text(l10n.settingsPageDisplay);
      await tester.tap(preferencesEntry);
      await tester.pumpAndSettle();
      expect(find.byType(DisplaySettingsPage), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      await tester.tap(statsEntry);
      await tester.pumpAndSettle();
      expect(find.byType(StatsPage), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      for (final (label, pageType) in [
        (l10n.settingsPageSearch, SearchServicesPage),
        (l10n.settingsPageMcp, McpPage),
        (l10n.settingsPageNetworkProxy, NetworkProxyPage),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(pageType), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text(l10n.settingsPageDebugAndDevelopment));
      await tester.pumpAndSettle();
      expect(find.byType(DebugDevelopmentPage), findsOneWidget);
      expect(find.text(l10n.settingsServerAddress), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(l10n.settingsServerAddress));
      await tester.pumpAndSettle();
      expect(find.byType(AppAlertDialog), findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      final backupEntry = find.text(l10n.settingsPageBackup);
      await tester.tap(backupEntry);
      await tester.pumpAndSettle();
      expect(find.byType(BackupPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
