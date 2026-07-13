import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/conversation.dart';

void main() {
  group('Conversation chat suggestions compatibility', () {
    test('fromJson defaults missing suggestions to empty list', () {
      final conversation = Conversation.fromJson({
        'id': 'conversation-1',
        'title': 'Chat',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 1, 2).toIso8601String(),
        'messageIds': <String>[],
      });

      expect(conversation.chatSuggestions, isEmpty);
    });

    test('toJson includes chat suggestions', () {
      final conversation = Conversation(
        id: 'conversation-2',
        title: 'Chat',
        chatSuggestions: const ['继续', '举例'],
      );

      expect(conversation.toJson()['chatSuggestions'], ['继续', '举例']);
    });
  });

  group('Conversation chat model override', () {
    test('defaults to no override for new conversations', () {
      final conversation = Conversation(id: 'conversation-3', title: 'Chat');
      expect(conversation.chatModelProvider, isNull);
      expect(conversation.chatModelId, isNull);
    });

    test('copyWith sets a conversation-scoped model override', () {
      final conversation = Conversation(id: 'conversation-4', title: 'Chat');
      final updated = conversation.copyWith(
        chatModelProvider: 'openai',
        chatModelId: 'gpt-5',
      );

      expect(updated.chatModelProvider, 'openai');
      expect(updated.chatModelId, 'gpt-5');
    });

    test('copyWith clearChatModel removes the override', () {
      final conversation = Conversation(
        id: 'conversation-5',
        title: 'Chat',
        chatModelProvider: 'openai',
        chatModelId: 'gpt-5',
      );
      final cleared = conversation.copyWith(clearChatModel: true);

      expect(cleared.chatModelProvider, isNull);
      expect(cleared.chatModelId, isNull);
    });

    test('round-trips through toJson/fromJson', () {
      final conversation = Conversation(
        id: 'conversation-6',
        title: 'Chat',
        chatModelProvider: 'anthropic',
        chatModelId: 'claude-sonnet-5',
      );
      final restored = Conversation.fromJson(conversation.toJson());

      expect(restored.chatModelProvider, 'anthropic');
      expect(restored.chatModelId, 'claude-sonnet-5');
    });
  });
}
