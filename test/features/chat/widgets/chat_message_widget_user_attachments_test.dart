import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('用户消息附件显示在文本气泡上方且不在气泡内部', (tester) async {
    const messageId = 'user-with-attachments';

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatMessageWidget(
              showUserAvatar: false,
              message: ChatMessage(
                id: messageId,
                role: 'user',
                content:
                    '请看这个\n[image:missing-user-image.png]\n[file:/tmp/spec.pdf|spec.pdf|application/pdf]',
                conversationId: 'conversation-user-attachments',
              ),
            ),
          ),
        ),
      ),
    );

    final bubbleFinder = find.byKey(
      const ValueKey('user-message-text-bubble:$messageId'),
    );
    final attachmentsFinder = find.byKey(
      const ValueKey('user-message-attachments:$messageId'),
    );
    final imagesFinder = find.byKey(
      const ValueKey('user-message-images:$messageId'),
    );
    final docsFinder = find.byKey(
      const ValueKey('user-message-docs:$messageId'),
    );

    expect(bubbleFinder, findsOneWidget);
    expect(attachmentsFinder, findsOneWidget);
    expect(imagesFinder, findsOneWidget);
    expect(docsFinder, findsOneWidget);
    expect(
      find.descendant(of: bubbleFinder, matching: find.text('请看这个')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bubbleFinder, matching: find.text('spec.pdf')),
      findsNothing,
    );
    expect(
      find.descendant(of: bubbleFinder, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(of: attachmentsFinder, matching: find.text('spec.pdf')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: attachmentsFinder, matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: attachmentsFinder, matching: find.byType(InkWell)),
      findsNothing,
    );

    final attachmentsRect = tester.getRect(attachmentsFinder);
    final imagesRect = tester.getRect(imagesFinder);
    final docsRect = tester.getRect(docsFinder);
    final bubbleRect = tester.getRect(bubbleFinder);
    expect(imagesRect.bottom, lessThanOrEqualTo(docsRect.top));
    expect(attachmentsRect.bottom, lessThanOrEqualTo(bubbleRect.top));
  });

  testWidgets('同步到其他设备的托管消息用 hostedImagesJson 渲染附件缩略图', (tester) async {
    // [kelivo-hosted] Regresses the bug where a hosted message synced onto a
    // different device (or re-synced after a restart) showed no attachment
    // at all — its `content` no longer carries the sending device's local
    // `[image:<path>]` marker (server strips it, see
    // `strip_local_image_markers` on the backend), so the thumbnail has to
    // come from the structured `hostedImagesJson` fallback instead
    // (`_parseUserContentWithHostedImages`).
    const messageId = 'user-hosted-synced';

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatMessageWidget(
              showUserAvatar: false,
              message: ChatMessage(
                id: messageId,
                role: 'user',
                content: '你能把这张图片换成黑天吗',
                conversationId: 'conversation-user-hosted-synced',
                hostedServerMessageId: 'server-msg-1',
                hostedImagesJson:
                    '[{"id":"img-1","url":"https://backend.example/__client/message-images/img-1/file","mimeType":"image/jpeg"}]',
              ),
            ),
          ),
        ),
      ),
    );

    final imagesFinder = find.byKey(
      const ValueKey('user-message-images:$messageId'),
    );

    expect(imagesFinder, findsOneWidget);
    expect(
      find.descendant(of: imagesFinder, matching: find.byType(Image)),
      findsOneWidget,
    );
  });

  testWidgets('已发送消息中的附件引用仍显示为可读标签', (tester) async {
    const messageId = 'user-hosted-reference';

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatMessageWidget(
              showUserAvatar: false,
              message: ChatMessage(
                id: messageId,
                role: 'user',
                content:
                    '请比较 @Image: Image 2 和 @Image: Image 1，还有 @File: file-1',
                conversationId: 'conversation-user-hosted-reference',
                hostedImagesJson:
                    '[{"id":"img-1","url":"https://backend.example/__client/message-images/img-1/file","mimeType":"image/jpeg"},{"id":"img-2","url":"https://backend.example/__client/message-images/img-2/file","mimeType":"image/jpeg"}]',
                hostedFilesJson:
                    '[{"id":"file-1","filename":"需求说明.pdf","mimeType":"application/pdf"}]',
                attachmentReferencesJson:
                    '[{"type":"text","text":"请比较 "},{"type":"attachment","token":"@Image: Image 2","attachment_id":"img-2"},{"type":"text","text":" 和 "},{"type":"attachment","token":"@Image: Image 1","attachment_id":"img-1"},{"type":"text","text":"，还有 "},{"type":"attachment","token":"@File: file-1","attachment_id":"file-1"}]',
              ),
            ),
          ),
        ),
      ),
    );

    final bubbleFinder = find.byKey(
      const ValueKey('user-message-text-bubble:$messageId'),
    );
    expect(
      find.descendant(of: bubbleFinder, matching: find.text('图片 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bubbleFinder, matching: find.text('图片 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bubbleFinder, matching: find.text('需求说明.pdf')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bubbleFinder, matching: find.text('img-1')),
      findsNothing,
    );
    expect(
      find.descendant(of: bubbleFinder, matching: find.text('img-2')),
      findsNothing,
    );
    expect(
      find.descendant(of: bubbleFinder, matching: find.text('file-1')),
      findsNothing,
    );
  });

  testWidgets('引用历史消息附件时也能在气泡中恢复标签', (tester) async {
    const messageId = 'user-history-reference';

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChatMessageWidget(
              showUserAvatar: false,
              attachmentReferenceCandidates: const [
                ChatImageReferenceCandidate(
                  id: 'history:img-2',
                  fileId: 'img-2',
                  label: 'Image 2',
                  mimeType: 'image/jpeg',
                ),
              ],
              message: ChatMessage(
                id: messageId,
                role: 'user',
                content: '请修改 @Image: Image 2',
                conversationId: 'conversation-history-reference',
                attachmentReferencesJson:
                    '[{"type":"text","text":"请修改 "},{"type":"attachment","token":"@Image: Image 2","attachment_id":"img-2"}]',
              ),
            ),
          ),
        ),
      ),
    );

    final bubbleFinder = find.byKey(
      const ValueKey('user-message-text-bubble:$messageId'),
    );
    expect(
      find.descendant(of: bubbleFinder, matching: find.text('Image 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bubbleFinder, matching: find.text('@Image: Image 2')),
      findsNothing,
    );
  });
}
