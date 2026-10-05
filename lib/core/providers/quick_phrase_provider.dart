import 'package:flutter/foundation.dart';
import '../models/quick_phrase.dart';
import '../services/api/client_backend_api.dart';
import '../services/api/client_backend_config.dart';
import '../services/api/client_backend_session.dart';
import '../services/quick_phrase_store.dart';

class QuickPhraseProvider with ChangeNotifier {
  List<QuickPhrase> _phrases = [];
  bool _initialized = false;
  String? _lastSyncedToken;
  Future<void>? _syncInFlight;

  List<QuickPhrase> get phrases => List.unmodifiable(_phrases);

  List<QuickPhrase> get globalPhrases =>
      _phrases.where((p) => p.isGlobal).toList();

  List<QuickPhrase> getForAssistant(String assistantId) => _phrases
      .where((p) => !p.isGlobal && p.assistantId == assistantId)
      .toList();

  Future<void> initialize() async {
    if (!_initialized) {
      await loadAll();
      _initialized = true;
    }
    await syncFromCloud();
  }

  /// Synchronizes this user's hosted quick phrases. If the account has no
  /// cloud copy yet, migrate the existing device list once; afterward the
  /// cloud copy is authoritative and replaces the local cache.
  Future<void> syncFromCloud() async {
    final token = ClientBackendSession.token;
    if (token == null) {
      _lastSyncedToken = null;
      return;
    }
    if (token == _lastSyncedToken) return;
    final active = _syncInFlight;
    if (active != null) {
      await active;
      if (token == _lastSyncedToken) return;
    }

    final operation = _syncFromCloud(token);
    _syncInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_syncInFlight, operation)) _syncInFlight = null;
    }
  }

  Future<void> _syncFromCloud(String token) async {
    final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
    final result = await api.fetchQuickPhrases(token);
    if (!result.isSuccess || ClientBackendSession.token != token) return;

    if (!result.initialized) {
      final saved = await api.updateQuickPhrases(
        token,
        _phrases.map((phrase) => phrase.toJson()).toList(),
      );
      if (saved && ClientBackendSession.token == token) {
        _lastSyncedToken = token;
      }
      return;
    }

    try {
      _phrases = result.phrases.map(QuickPhrase.fromJson).toList();
      await QuickPhraseStore.save(_phrases);
      _lastSyncedToken = token;
      notifyListeners();
    } catch (error) {
      debugPrint('Failed to apply hosted quick phrases: $error');
    }
  }

  Future<void> _save() async {
    await QuickPhraseStore.save(_phrases);
    final token = ClientBackendSession.token;
    if (token == null) return;
    final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
    if (await api.updateQuickPhrases(
          token,
          _phrases.map((phrase) => phrase.toJson()).toList(),
        ) &&
        ClientBackendSession.token == token) {
      _lastSyncedToken = token;
    }
  }

  Future<void> loadAll() async {
    try {
      _phrases = await QuickPhraseStore.getAll();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load quick phrases: $e');
      _phrases = [];
      notifyListeners();
    }
  }

  Future<void> add(QuickPhrase phrase) async {
    await QuickPhraseStore.add(phrase);
    await loadAll();
    await _save();
  }

  Future<void> update(QuickPhrase phrase) async {
    await QuickPhraseStore.update(phrase);
    await loadAll();
    await _save();
  }

  Future<void> delete(String id) async {
    await QuickPhraseStore.delete(id);
    await loadAll();
    await _save();
  }

  Future<void> clear() async {
    _phrases = [];
    notifyListeners();
    await _save();
  }

  void _reorderInMemory({
    required int oldIndex,
    required int newIndex,
    String? assistantId,
  }) {
    final bool isGlobal = assistantId == null;

    // Determine indices in the subset (global or specific assistant)
    final List<int> subsetIndices = [];
    for (int i = 0; i < _phrases.length; i++) {
      final p = _phrases[i];
      final matches = isGlobal
          ? p.isGlobal
          : (!p.isGlobal && p.assistantId == assistantId);
      if (matches) subsetIndices.add(i);
    }

    if (subsetIndices.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= subsetIndices.length) return;
    if (newIndex < 0 || newIndex >= subsetIndices.length) return;

    // Extract the subset in current order
    final List<QuickPhrase> subset = subsetIndices
        .map((i) => _phrases[i])
        .toList(growable: true);

    final item = subset.removeAt(oldIndex);
    subset.insert(newIndex, item);

    // Merge reordered subset back into original list
    final List<QuickPhrase> merged = [];
    int take = 0;
    for (int i = 0; i < _phrases.length; i++) {
      final p = _phrases[i];
      final matches = isGlobal
          ? p.isGlobal
          : (!p.isGlobal && p.assistantId == assistantId);
      if (matches) {
        merged.add(subset[take++]);
      } else {
        merged.add(p);
      }
    }
    _phrases = merged;
  }

  Future<void> reorder({
    required int oldIndex,
    required int newIndex,
    String? assistantId,
  }) async {
    _reorderInMemory(
      oldIndex: oldIndex,
      newIndex: newIndex,
      assistantId: assistantId,
    );
    notifyListeners();
    await _save();
  }

  // Backward/alternate API name for clarity
  Future<void> reorderPhrases({
    required int oldIndex,
    required int newIndex,
    String? assistantId,
  }) async {
    // Immediate UI update, then persist
    _reorderInMemory(
      oldIndex: oldIndex,
      newIndex: newIndex,
      assistantId: assistantId,
    );
    notifyListeners();
    await _save();
  }
}
