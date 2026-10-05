import 'package:Kelivo/core/providers/auth_provider.dart';
import 'package:Kelivo/core/providers/backup_reminder_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/backup/pages/backup_page.dart';
import 'package:Kelivo/features/settings/pages/settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
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

  for (final bottomInset in [0.0, 34.0]) {
    testWidgets(
      'settings and backup last cards align at scroll end ($bottomInset)',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(top: 47, bottom: bottomInset);
        tester.view.viewPadding = FakeViewPadding(top: 47, bottom: bottomInset);
        addTearDown(tester.view.reset);

        final settings = SettingsProvider();
        final auth = _SignedOutAuth();
        final chat = ChatService();
        final reminder = BackupReminderProvider(autoLoad: false);
        await reminder.load(startTimer: false);
        addTearDown(settings.dispose);
        addTearDown(auth.dispose);
        addTearDown(chat.dispose);
        addTearDown(reminder.dispose);

        Future<double> lastCardBottom(Widget page) async {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<SettingsProvider>.value(value: settings),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<ChatService>.value(value: chat),
                ChangeNotifierProvider<BackupReminderProvider>.value(
                  value: reminder,
                ),
              ],
              child: MaterialApp(
                locale: const Locale('en'),
                theme: ThemeData(platform: TargetPlatform.iOS),
                scrollBehavior: const MaterialScrollBehavior().copyWith(
                  physics: const ClampingScrollPhysics(),
                ),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: page,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final list = find.byType(ListView).first;
          final scrollable = tester.state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          );
          // Lazy slivers can refine maxScrollExtent when their final cards mount.
          for (var i = 0; i < 4; i++) {
            scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
            await tester.pumpAndSettle();
          }
          expect(tester.getBottomRight(list).dy, 812);
          final bottom = tester
              .getBottomRight(find.byType(AppListGroup).last)
              .dy;
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          return bottom;
        }

        final settingsBottom = await lastCardBottom(const SettingsPage());
        final backupBottom = await lastCardBottom(const BackupPage());
        // Preserve the settings page's existing 16 + 32 px trailing space.
        expect(settingsBottom, closeTo(812 - bottomInset - 48, 0.01));
        expect(backupBottom, closeTo(settingsBottom, 0.01));
      },
    );
  }
}
