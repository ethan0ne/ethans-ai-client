import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildHarness({required Widget child}) {
  SharedPreferences.setMockInitialValues(const {});
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider(create: (_) => TtsProvider()),
      ChangeNotifierProvider(create: (_) => ToolApprovalService()),
      ChangeNotifierProvider(create: (_) => AskUserInteractionService()),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('还没收到任何内容时显示"正在与服务器通讯"提示', (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        child: ChatMessageWidget(
          message: ChatMessage(
            id: 'waiting-empty',
            role: 'assistant',
            content: '',
            conversationId: 'conversation-1',
            isStreaming: true,
          ),
          showModelIcon: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LoadingIndicator), findsOneWidget);
    expect(find.text('正在与服务器通讯，请不要关闭'), findsOneWidget);
  });

  testWidgets('已经收到正文内容后不再显示"正在与服务器通讯"提示', (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        child: ChatMessageWidget(
          message: ChatMessage(
            id: 'waiting-with-content',
            role: 'assistant',
            content: '已经开始回复了',
            conversationId: 'conversation-1',
            isStreaming: true,
          ),
          showModelIcon: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('正在与服务器通讯，请不要关闭'), findsNothing);
  });

  testWidgets('hideStreamingIndicator 为 true 时不显示提示文字（沿用原有占位行为）', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildHarness(
        child: ChatMessageWidget(
          message: ChatMessage(
            id: 'waiting-hidden',
            role: 'assistant',
            content: '',
            conversationId: 'conversation-1',
            isStreaming: true,
          ),
          showModelIcon: false,
          hideStreamingIndicator: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LoadingIndicator), findsNothing);
    expect(find.text('正在与服务器通讯，请不要关闭'), findsNothing);
  });

  testWidgets('服务器已开始响应但仍无正文时，三个点保留但提示文字消失', (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        child: ChatMessageWidget(
          message: ChatMessage(
            id: 'waiting-response-started',
            role: 'assistant',
            content: '',
            conversationId: 'conversation-1',
            isStreaming: true,
          ),
          showModelIcon: false,
          responseStarted: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LoadingIndicator), findsOneWidget);
    expect(find.text('正在与服务器通讯，请不要关闭'), findsNothing);
  });

  testWidgets('非流式消息不显示"正在与服务器通讯"提示', (tester) async {
    await tester.pumpWidget(
      _buildHarness(
        child: ChatMessageWidget(
          message: ChatMessage(
            id: 'not-streaming',
            role: 'assistant',
            content: '',
            conversationId: 'conversation-1',
            isStreaming: false,
          ),
          showModelIcon: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('正在与服务器通讯，请不要关闭'), findsNothing);
  });
}
