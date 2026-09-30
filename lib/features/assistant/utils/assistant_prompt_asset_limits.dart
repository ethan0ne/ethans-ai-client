import 'dart:convert';

import '../../../core/models/assistant.dart';

const int _maxInstructionCards = 100;
const int _maxWorldBooks = 100;
const int _maxWorldBookEntries = 500;
const int _maxAssetTextLength = 32000;
const int _maxAssetPayloadBytes = 256 * 1024;
const int _maxAssetJsonNodes = 100000;
const int _maxAssetIdLength = 128;
const int _maxRegexLength = 512;

/// Returns whether [assistant]'s prompt assets fit the hosted API limits.
///
/// BYOK assistants are stored and executed locally, so hosted-only limits do
/// not apply to them.
bool assistantPromptAssetsWithinHostedLimits(Assistant assistant) {
  if (!assistant.cloudHosted) return true;

  final cards = assistant.instructionInjections;
  final books = assistant.worldBooks;
  final activeCardIds = assistant.activeInstructionInjectionIds;
  final activeBookIds = assistant.activeWorldBookIds;
  if (cards.length > _maxInstructionCards ||
      books.length > _maxWorldBooks ||
      activeCardIds.length > _maxWorldBooks ||
      activeBookIds.length > _maxWorldBooks) {
    return false;
  }

  var entryCount = 0;
  var keywordCount = 0;
  for (final book in books) {
    entryCount += book.entries.length;
    for (final entry in book.entries) {
      keywordCount += entry.keywords.length;
    }
  }
  if (entryCount > _maxWorldBookEntries) return false;

  // The server counts JSON values and object keys as nodes. Keep the local
  // estimate conservative so a request cannot pass this check and then fail
  // solely on the server's node cap.
  final estimatedNodeCount =
      1 +
      cards.length * 10 +
      books.length * 12 +
      entryCount * 30 +
      activeCardIds.length +
      activeBookIds.length +
      keywordCount;
  if (estimatedNodeCount > _maxAssetJsonNodes) return false;

  var rawTextBytes = 0;
  bool validText(
    String value, {
    required int maxLength,
    bool nonEmpty = false,
  }) {
    if ((nonEmpty && value.isEmpty) || value.runes.length > maxLength) {
      return false;
    }
    try {
      rawTextBytes += utf8.encode(value).length;
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
    return rawTextBytes <= _maxAssetPayloadBytes;
  }

  for (final card in cards) {
    if (!validText(card.id, maxLength: _maxAssetIdLength, nonEmpty: true) ||
        !validText(card.title, maxLength: _maxAssetTextLength) ||
        !validText(card.group, maxLength: _maxAssetTextLength) ||
        !validText(card.prompt, maxLength: _maxAssetTextLength)) {
      return false;
    }
  }
  for (final id in activeCardIds) {
    if (!validText(id, maxLength: _maxAssetIdLength, nonEmpty: true)) {
      return false;
    }
  }

  for (final book in books) {
    if (!validText(book.id, maxLength: _maxAssetIdLength, nonEmpty: true) ||
        !validText(book.name, maxLength: _maxAssetTextLength) ||
        !validText(book.description, maxLength: _maxAssetTextLength)) {
      return false;
    }
    for (final entry in book.entries) {
      if (!validText(entry.id, maxLength: _maxAssetIdLength, nonEmpty: true) ||
          !validText(entry.name, maxLength: _maxAssetTextLength) ||
          !validText(entry.content, maxLength: _maxAssetTextLength) ||
          entry.priority < -9999 ||
          entry.priority > 9999 ||
          entry.scanDepth < 1 ||
          entry.scanDepth > 200 ||
          entry.injectDepth < 1 ||
          entry.injectDepth > 200) {
        return false;
      }
      for (final keyword in entry.keywords) {
        if (!validText(keyword, maxLength: _maxAssetTextLength) ||
            (entry.useRegex && keyword.runes.length > _maxRegexLength)) {
          return false;
        }
      }
    }
  }
  for (final id in activeBookIds) {
    if (!validText(id, maxLength: _maxAssetIdLength, nonEmpty: true)) {
      return false;
    }
  }

  // Raw UTF-8 text is a lower bound on the final JSON size. Check it before
  // encoding, then measure the exact serialized payload including JSON syntax
  // and escaping.
  if (utf8
          .encode(
            jsonEncode(<String, Object>{
              'instructionInjections': cards
                  .map((item) => item.toJson())
                  .toList(),
              'activeInstructionInjectionIds': activeCardIds,
              'worldBooks': books.map((item) => item.toJson()).toList(),
              'activeWorldBookIds': activeBookIds,
            }),
          )
          .length >
      _maxAssetPayloadBytes) {
    return false;
  }
  return true;
}
