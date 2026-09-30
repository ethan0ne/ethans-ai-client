import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/instruction_injection.dart';
import 'package:Kelivo/core/models/world_book.dart';

void main() {
  group('Assistant prompt assets', () {
    test(
      'round trips instruction cards, activation, world books, and entries',
      () {
        const assistant = Assistant(
          id: 'assistant-1',
          name: 'Test assistant',
          instructionInjections: [
            InstructionInjection(
              id: 'card-1',
              title: 'Card',
              prompt: 'Be concise.',
              group: 'Style',
            ),
          ],
          activeInstructionInjectionIds: ['card-1'],
          worldBooks: [
            WorldBook(
              id: 'book-1',
              name: 'World',
              entries: [
                WorldBookEntry(
                  id: 'entry-1',
                  keywords: ['dragon'],
                  content: 'Ancient lore',
                  position: WorldBookInjectionPosition.atDepth,
                  injectDepth: 2,
                ),
              ],
            ),
          ],
          activeWorldBookIds: ['book-1'],
        );

        final decoded = Assistant.fromJson(assistant.toJson());

        expect(decoded.instructionInjections.single.prompt, 'Be concise.');
        expect(decoded.activeInstructionInjectionIds, ['card-1']);
        expect(
          decoded.worldBooks.single.entries.single.content,
          'Ancient lore',
        );
        expect(
          decoded.worldBooks.single.entries.single.position,
          WorldBookInjectionPosition.atDepth,
        );
        expect(decoded.activeWorldBookIds, ['book-1']);
      },
    );

    test('older assistant JSON defaults to empty prompt assets', () {
      final assistant = Assistant.fromJson(const {
        'id': 'legacy',
        'name': 'Legacy',
      });

      expect(assistant.instructionInjections, isEmpty);
      expect(assistant.activeInstructionInjectionIds, isEmpty);
      expect(assistant.worldBooks, isEmpty);
      expect(assistant.activeWorldBookIds, isEmpty);
    });

    test('normalizes imported world-book priority and depths', () {
      final book = WorldBook.fromJson(const {
        'id': 'book',
        'entries': [
          {
            'id': 'entry',
            'priority': 20000,
            'scanDepth': 0,
            'injectDepth': 999,
          },
        ],
      });

      expect(book.entries.single.priority, 9999);
      expect(book.entries.single.scanDepth, 1);
      expect(book.entries.single.injectDepth, 200);
    });
  });
}
