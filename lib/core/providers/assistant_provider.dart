import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../utils/sandbox_path_resolver.dart';
import '../models/assistant.dart';
import '../models/assistant_regex.dart';
import '../models/preset_message.dart';
import '../services/api/client_backend_api.dart';
import '../services/api/client_backend_config.dart';
import '../services/api/client_backend_session.dart';
import '../services/chat/chat_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/avatar_cache.dart';
import '../../utils/app_directories.dart';

class AssistantProvider extends ChangeNotifier {
  static const String _assistantsKey = 'assistants_v1';
  static const String _currentAssistantKey = 'current_assistant_id_v1';
  static const String _legacySearchEnabledKey = 'search_enabled_v1';

  final List<Assistant> _assistants = <Assistant>[];
  String? _currentAssistantId;
  final ChatService? chatService;
  // [kelivo-hosted] Assistant cloud sync — a signed-in `ClientUser`'s
  // assistants (system prompt/temperature/enableMemory/etc.) are synced
  // across their devices via `/__client/assistants`, following the same
  // `ClientBackendSession.token` synchronous-mirror idiom as
  // `SettingsProvider.getProviderConfig` so this provider doesn't need a
  // direct `AuthProvider` reference.
  final ClientBackendApi _cloudApi = ClientBackendApi(
    baseUrl: clientBackendBaseUrl,
  );

  List<Assistant> get assistants => List.unmodifiable(_assistants);
  String? get currentAssistantId => _currentAssistantId;
  Assistant? get currentAssistant {
    final idx = _assistants.indexWhere((a) => a.id == _currentAssistantId);
    if (idx != -1) return _assistants[idx];
    if (_assistants.isNotEmpty) return _assistants.first;
    return null;
  }

  bool get currentSearchEnabled => currentAssistant?.searchEnabled ?? false;

  AssistantProvider({this.chatService}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_assistantsKey);
    if (raw != null && raw.isNotEmpty) {
      final legacySearchEnabled = prefs.getBool(_legacySearchEnabledKey);
      final migrated = _decodeAssistantsWithLegacySearch(
        raw,
        legacySearchEnabled: legacySearchEnabled,
      );
      bool migratedSearchEnabled = false;
      _assistants
        ..clear()
        ..addAll(migrated.assistants);
      migratedSearchEnabled = migrated.didApplyLegacySearch;
      // Fix any sandboxed local paths (avatars/backgrounds) imported from other platforms
      bool changed = migratedSearchEnabled;
      for (int i = 0; i < _assistants.length; i++) {
        final a = _assistants[i];
        String? av = a.avatar;
        String? bg = a.background;
        if (av != null &&
            av.isNotEmpty &&
            (av.startsWith('/') || av.contains(':')) &&
            !av.startsWith('http')) {
          final fixed = SandboxPathResolver.fix(av);
          if (fixed != av) {
            av = fixed;
            changed = true;
          }
        }
        if (bg != null &&
            bg.isNotEmpty &&
            (bg.startsWith('/') || bg.contains(':')) &&
            !bg.startsWith('http')) {
          final fixedBg = SandboxPathResolver.fix(bg);
          if (fixedBg != bg) {
            bg = fixedBg;
            changed = true;
          }
        }
        if (changed) {
          _assistants[i] = a.copyWith(avatar: av, background: bg);
        }
      }
      if (changed) {
        try {
          await _persist();
        } catch (_) {}
      }
    }
    // [kelivo-hosted] If this device is signed in to a hosted account and
    // that account already has assistants synced from elsewhere (another
    // device, or a prior local->cloud push), adopt the cloud copy —
    // otherwise fall through to whatever was loaded locally above. Once the
    // authenticated state is known, `ensureDefaults` makes the authoritative
    // cloud-first decision.
    await _pullFromCloud();

    // Do not create defaults here because localization is not available.
    // Defaults will be ensured later via ensureDefaults(context).
    // Restore current assistant if present
    final savedId = prefs.getString(_currentAssistantKey);
    if (savedId != null && _assistants.any((a) => a.id == savedId)) {
      _currentAssistantId = savedId;
    } else {
      _currentAssistantId = null;
    }
    notifyListeners();
  }

  /// Pulls the account's cloud assistants into this provider.
  ///
  /// The result distinguishes an explicitly empty cloud list from a failed
  /// request. That distinction is required before creating a first hosted
  /// assistant: a network failure must never be mistaken for an empty account.
  ///
  /// Only ever replaces this account's own `cloudHosted` assistants —
  /// purely local ones (created signed-out, `cloudHosted == false`) are
  /// preserved verbatim so a device that had offline-only assistants before
  /// ever signing in doesn't lose them the moment login pulls the cloud
  /// copy.
  /// [kelivo-hosted] Public re-sync entry point — called from
  /// `HomeViewModel.resyncCurrentHostedConversation` on the same
  /// foreground/window-focus-regain trigger (and shared 12s throttle) as
  /// the hosted message resync, so an assistant edited on another device
  /// shows up here on the same cadence a message would, instead of only
  /// ever refreshing once at app launch (`_load`).
  Future<void> refreshFromCloud() async {
    if (await _pullFromCloud() == _AssistantCloudPullResult.adopted) {
      notifyListeners();
    }
  }

  Future<_AssistantCloudPullResult> _pullFromCloud() async {
    final token = ClientBackendSession.token;
    if (token == null) return _AssistantCloudPullResult.unavailable;
    final cloud = await _cloudApi.listAssistants(token);
    if (cloud == null) return _AssistantCloudPullResult.unavailable;
    if (cloud.isEmpty) return _AssistantCloudPullResult.empty;
    try {
      final decoded = [
        for (final row in cloud)
          Assistant.fromJson(row.data).copyWith(cloudHosted: true),
      ];
      final localOnly = _assistants.where((a) => !a.cloudHosted).toList();
      _assistants
        ..clear()
        ..addAll(decoded)
        ..addAll(localOnly);
      await _persist();
      return _AssistantCloudPullResult.adopted;
    } catch (_) {
      // A malformed cloud row shouldn't wipe out a perfectly good local
      // list — keep whatever was already loaded from SharedPreferences.
      return _AssistantCloudPullResult.unavailable;
    }
  }

  /// Fire-and-forget push of one assistant's full config to the cloud —
  /// no-ops silently when signed out or when [a] isn't `cloudHosted` (a
  /// purely local assistant is never synced, even if the user happens to
  /// be signed in at the time it's edited). Failures are left for the next
  /// sync pass to reconcile (same tolerance as conversation title pushes).
  void _pushToCloud(Assistant a) {
    if (!a.cloudHosted) return;
    final token = ClientBackendSession.token;
    if (token == null) return;
    unawaited(
      _cloudApi.upsertAssistant(
        token,
        a.id,
        data: a.toJson(),
        enableMemory: a.enableMemory,
        localToolIds: a.localToolIds,
      ),
    );
  }

  void _deleteFromCloud(String id) {
    final token = ClientBackendSession.token;
    if (token == null) return;
    unawaited(_cloudApi.deleteAssistant(token, id));
  }

  /// [kelivo-hosted] Logout cleanup (called from `AuthProvider.logout`) —
  /// removes every `cloudHosted` assistant from local storage (they belong
  /// to the account that just signed out, not this device), leaving any
  /// purely local ones untouched. If nothing is left, the caller should
  /// follow up with `ensureDefaults(context)` to reseed a local default —
  /// not done here since localization isn't available at this layer.
  Future<void> clearCloudHostedAssistants() async {
    if (_assistants.every((a) => !a.cloudHosted)) return;
    final removingCurrent = _assistants
        .firstWhere(
          (a) => a.id == _currentAssistantId,
          orElse: () => const Assistant(id: '', name: ''),
        )
        .cloudHosted;
    _assistants.removeWhere((a) => a.cloudHosted);
    await _persist();
    final prefs = await SharedPreferences.getInstance();
    if (removingCurrent) {
      _currentAssistantId = _assistants.isNotEmpty
          ? _assistants.first.id
          : null;
      if (_currentAssistantId != null) {
        await prefs.setString(_currentAssistantKey, _currentAssistantId!);
      } else {
        await prefs.remove(_currentAssistantKey);
      }
    }
    notifyListeners();
  }

  _AssistantDecodeResult _decodeAssistantsWithLegacySearch(
    String raw, {
    required bool? legacySearchEnabled,
  }) {
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      bool didApplyLegacySearch = false;
      final assistants = [
        for (final e in decoded)
          if (e is Map)
            (() {
              final json = e.cast<String, dynamic>();
              if (legacySearchEnabled != null &&
                  !json.containsKey('searchEnabled')) {
                json['searchEnabled'] = legacySearchEnabled;
                didApplyLegacySearch = true;
              }
              return Assistant.fromJson(json);
            })(),
      ];
      return _AssistantDecodeResult(
        assistants: assistants,
        didApplyLegacySearch: didApplyLegacySearch,
      );
    } catch (_) {
      return const _AssistantDecodeResult(
        assistants: <Assistant>[],
        didApplyLegacySearch: false,
      );
    }
  }

  Assistant _defaultAssistant(AppLocalizations l10n) => Assistant(
    id: const Uuid().v4(),
    name: l10n.assistantProviderDefaultAssistantName,
    systemPrompt: '',
    thinkingBudget: null,
    temperature: 0.6,
    topP: null,
  );

  // Ensure a default assistant exists; call this after localization is ready.
  Future<void> ensureDefaults(dynamic context) async {
    final l10n = AppLocalizations.of(context)!;
    final token = ClientBackendSession.token;
    if (token != null) {
      // A login (including restored login after a reinstall) must resolve
      // the cloud state before considering a default. `_load` can run before
      // the JWT is restored, so its earlier pull is not authoritative here.
      final cloudResult = await _pullFromCloud();
      if (cloudResult == _AssistantCloudPullResult.adopted ||
          cloudResult == _AssistantCloudPullResult.unavailable) {
        return;
      }

      // The server explicitly confirmed that this account has no assistants.
      // Seed exactly one hosted default, and only retain it locally after the
      // cloud write succeeds. Do not silently turn it into a local assistant.
      final a = _defaultAssistant(l10n).copyWith(cloudHosted: true);
      final ok = await _cloudApi.upsertAssistant(
        token,
        a.id,
        data: a.toJson(),
        enableMemory: a.enableMemory,
        localToolIds: a.localToolIds,
      );
      if (!ok) return;
      _assistants.add(a);
    } else {
      if (_assistants.isNotEmpty) return;
      _assistants.add(_defaultAssistant(l10n));
    }
    await _persist();
    // Set current assistant if not set
    if (_currentAssistantId == null && _assistants.isNotEmpty) {
      _currentAssistantId = _assistants.first.id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentAssistantKey, _currentAssistantId!);
    }
    notifyListeners();
  }

  String _buildCopyName(Assistant source, AppLocalizations? l10n) {
    final suffix = (l10n?.assistantSettingsCopySuffix ?? 'Copy').trim();
    final baseName = source.name.trim().isEmpty
        ? (l10n?.assistantProviderNewAssistantName ?? 'Assistant')
        : source.name.trim();
    final existingNames = _assistants.map((a) => a.name).toSet();

    String candidate = suffix.isEmpty ? baseName : '$baseName $suffix';
    int counter = 2;
    while (existingNames.contains(candidate)) {
      final counterSuffix = suffix.isEmpty ? '$counter' : '$suffix $counter';
      candidate = '$baseName $counterSuffix';
      counter++;
    }
    return candidate;
  }

  Future<String?> _duplicateLocalFile(
    String? rawPath, {
    required bool isAvatar,
    required String newId,
  }) async {
    final raw = (rawPath ?? '').trim();
    if (raw.isEmpty) return rawPath;
    if (raw.startsWith('http') || raw.startsWith('data:')) return rawPath;
    final fixed = SandboxPathResolver.fix(raw);
    final src = File(fixed);
    if (!await src.exists()) return rawPath;

    try {
      final dir = isAvatar
          ? await AppDirectories.getAvatarsDirectory()
          : await AppDirectories.getImagesDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      String ext = '';
      final dot = fixed.lastIndexOf('.');
      if (dot != -1 && dot < fixed.length - 1) {
        ext = fixed.substring(dot + 1).toLowerCase();
        if (ext.length > 6) ext = 'jpg';
      } else {
        ext = 'jpg';
      }
      final prefix = isAvatar ? 'assistant' : 'background';
      final dest = File(
        '${dir.path}/${prefix}_${newId}_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await src.copy(dest.path);
      return dest.path;
    } catch (_) {
      return rawPath;
    }
  }

  Future<String?> _copyLocalAssetToManagedDirectory(
    String? rawPath, {
    required Future<Directory> Function() directoryAsync,
    required String filenamePrefix,
    required String id,
  }) async {
    final raw = (rawPath ?? '').trim();
    if (raw.isEmpty || raw.startsWith('http') || raw.startsWith('data:')) {
      return rawPath;
    }
    if (!(raw.startsWith('/') || raw.contains(':'))) return rawPath;

    final fixed = SandboxPathResolver.fix(raw);
    final src = File(fixed);
    if (!await src.exists()) return rawPath;

    final managedDir = await directoryAsync();
    final managedRoot = p.normalize(managedDir.absolute.path);
    final sourcePath = p.normalize(src.absolute.path);
    if (p.isWithin(managedRoot, sourcePath)) return fixed;

    if (!await managedDir.exists()) {
      await managedDir.create(recursive: true);
    }

    var ext = p.extension(fixed).toLowerCase();
    if (ext.isEmpty || ext.length > 7) ext = '.jpg';
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final dest = File(
      p.join(
        managedDir.path,
        '${filenamePrefix}_${safeId}_${DateTime.now().millisecondsSinceEpoch}$ext',
      ),
    );
    await src.copy(dest.path);
    return dest.path;
  }

  Future<void> _deleteManagedFileIfOwned(
    String? rawPath, {
    required Future<Directory> Function() directoryAsync,
    required String? replacementPath,
  }) async {
    final raw = (rawPath ?? '').trim();
    if (raw.isEmpty) return;
    try {
      final dir = await directoryAsync();
      final root = p.normalize(dir.absolute.path);
      final targetFile = File(raw);
      final target = p.normalize(targetFile.absolute.path);
      if (!p.isWithin(root, target)) return;
      if (replacementPath != null &&
          p.equals(target, p.normalize(File(replacementPath).absolute.path))) {
        return;
      }
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_assistantsKey, Assistant.encodeList(_assistants));
  }

  Future<void> setCurrentAssistant(String id) async {
    if (_currentAssistantId == id) return;
    _currentAssistantId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentAssistantKey, id);
  }

  Assistant? getById(String id) {
    final idx = _assistants.indexWhere((a) => a.id == id);
    if (idx == -1) return null;
    return _assistants[idx];
  }

  // Lightweight accessor so callers don't depend on Assistant.presetMessages symbol
  List<Map<String, String>> getPresetMessagesForAssistant(String? assistantId) {
    Assistant? a;
    if (assistantId != null) {
      a = getById(assistantId);
    } else {
      a = currentAssistant;
    }
    if (a == null) return const <Map<String, String>>[];
    return [
      for (final m in a.presetMessages) {'role': m.role, 'content': m.content},
    ];
  }

  /// [kelivo-hosted] When signed in, a new assistant is a cloud-hosted one
  /// by definition — created via a *blocking* cloud upsert (caller shows a
  /// progress indicator while this awaits) so the assistant only ever
  /// exists locally once the server has actually confirmed it, rather than
  /// optimistically storing it and hoping a background push reconciles
  /// later. Throws [AssistantSyncException] on failure (e.g. offline) so
  /// the caller can surface an error instead of silently ending up with an
  /// assistant that looks hosted but isn't. Signed-out creation is
  /// unaffected — purely local, as before.
  Future<String> addAssistant({String? name, dynamic context}) async {
    final hosted = ClientBackendSession.token != null;
    final a = Assistant(
      id: const Uuid().v4(),
      name:
          (name ??
          (context != null
              ? AppLocalizations.of(context)!.assistantProviderNewAssistantName
              : 'New Assistant')),
      temperature: 0.6,
      topP: null,
      cloudHosted: hosted,
    );
    if (hosted) {
      final ok = await _cloudApi.upsertAssistant(
        ClientBackendSession.token!,
        a.id,
        data: a.toJson(),
        enableMemory: a.enableMemory,
        localToolIds: a.localToolIds,
      );
      if (!ok) {
        throw AssistantSyncException('Failed to create assistant in the cloud');
      }
    }
    _assistants.add(a);
    await _persist();
    notifyListeners();
    return a.id;
  }

  /// Same blocking-cloud-create rule as [addAssistant] — a duplicate made
  /// while signed in is itself a new cloud-hosted assistant (regardless of
  /// whether the source was), confirmed server-side before it's stored
  /// locally.
  Future<String?> duplicateAssistant(
    String id, {
    AppLocalizations? l10n,
  }) async {
    final idx = _assistants.indexWhere((a) => a.id == id);
    if (idx == -1) return null;
    final source = _assistants[idx];
    final newId = const Uuid().v4();

    final avatarCopy = await _duplicateLocalFile(
      source.avatar,
      isAvatar: true,
      newId: newId,
    );
    final backgroundCopy = await _duplicateLocalFile(
      source.background,
      isAvatar: false,
      newId: newId,
    );

    final hosted = ClientBackendSession.token != null;
    final copy = source.copyWith(
      id: newId,
      name: _buildCopyName(source, l10n),
      avatar: avatarCopy,
      background: backgroundCopy,
      mcpServerIds: List<String>.of(source.mcpServerIds),
      localToolIds: List<String>.of(source.localToolIds),
      customHeaders: source.customHeaders
          .map((e) => Map<String, String>.from(e))
          .toList(),
      customBody: source.customBody
          .map((e) => Map<String, String>.from(e))
          .toList(),
      presetMessages: source.presetMessages
          .map((m) => PresetMessage(role: m.role, content: m.content))
          .toList(),
      regexRules: source.regexRules
          .map(
            (r) => AssistantRegex(
              id: const Uuid().v4(),
              name: r.name,
              pattern: r.pattern,
              replacement: r.replacement,
              scopes: List<AssistantRegexScope>.of(r.scopes),
              visualOnly: r.visualOnly,
              replaceOnly: r.replaceOnly,
              enabled: r.enabled,
            ),
          )
          .toList(),
      cloudHosted: hosted,
    );

    if (hosted) {
      final ok = await _cloudApi.upsertAssistant(
        ClientBackendSession.token!,
        copy.id,
        data: copy.toJson(),
        enableMemory: copy.enableMemory,
        localToolIds: copy.localToolIds,
      );
      if (!ok) {
        throw AssistantSyncException('Failed to create assistant in the cloud');
      }
    }

    _assistants.insert(idx + 1, copy);
    await _persist();
    notifyListeners();
    return copy.id;
  }

  Future<void> updateAssistant(Assistant updated) async {
    final idx = _assistants.indexWhere((a) => a.id == updated.id);
    if (idx == -1) return;

    var next = updated;

    try {
      final prev = _assistants[idx];
      final raw = (updated.avatar ?? '').trim();
      final prevRaw = (prev.avatar ?? '').trim();
      final changed = raw != prevRaw;

      if (changed) {
        final avatarPath = await _copyLocalAssetToManagedDirectory(
          raw,
          directoryAsync: AppDirectories.getAvatarsDirectory,
          filenamePrefix: 'assistant',
          id: updated.id,
        );
        if (avatarPath != updated.avatar) {
          await _deleteManagedFileIfOwned(
            prevRaw,
            directoryAsync: AppDirectories.getAvatarsDirectory,
            replacementPath: avatarPath,
          );
          next = updated.copyWith(avatar: avatarPath);
        } else if (raw.isEmpty) {
          await _deleteManagedFileIfOwned(
            prevRaw,
            directoryAsync: AppDirectories.getAvatarsDirectory,
            replacementPath: null,
          );
        }
      }

      // Prefetch URL avatar to allow offline display later
      if (changed && raw.startsWith('http')) {
        try {
          await AvatarCache.getPath(raw);
        } catch (_) {}
      }

      // Handle background persistence similar to avatar, but under images/
      final bgRaw = (updated.background ?? '').trim();
      final prevBgRaw = (prev.background ?? '').trim();
      final bgChanged = bgRaw != prevBgRaw;
      if (bgChanged) {
        final backgroundPath = await _copyLocalAssetToManagedDirectory(
          bgRaw,
          directoryAsync: AppDirectories.getImagesDirectory,
          filenamePrefix: 'background',
          id: updated.id,
        );
        if (backgroundPath != updated.background) {
          await _deleteManagedFileIfOwned(
            prevBgRaw,
            directoryAsync: AppDirectories.getImagesDirectory,
            replacementPath: backgroundPath,
          );
          next = next.copyWith(background: backgroundPath);
        } else if (bgRaw.isEmpty) {
          await _deleteManagedFileIfOwned(
            prevBgRaw,
            directoryAsync: AppDirectories.getImagesDirectory,
            replacementPath: null,
          );
        }
      }
    } catch (_) {
      // On any failure, fall back to the provided value unchanged.
    }

    _assistants[idx] = next;
    await _persist();
    _pushToCloud(next);
    notifyListeners();
  }

  Future<void> setSearchEnabledForCurrentAssistant(bool enabled) async {
    final a = currentAssistant;
    if (a == null || a.searchEnabled == enabled) return;
    await updateAssistant(a.copyWith(searchEnabled: enabled));
  }

  Future<void> reorderAssistantRegex({
    required String assistantId,
    required int oldIndex,
    required int newIndex,
  }) async {
    final idx = _assistants.indexWhere((a) => a.id == assistantId);
    if (idx == -1) return;
    final list = List<AssistantRegex>.of(_assistants[idx].regexRules);
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex < 0 || newIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _assistants[idx] = _assistants[idx].copyWith(regexRules: list);
    notifyListeners();
    await _persist();
  }

  Future<bool> deleteAssistant(String id) async {
    final idx = _assistants.indexWhere((a) => a.id == id);
    if (idx == -1) return false;
    // Do not allow deleting the last remaining assistant
    if (_assistants.length <= 1) return false;

    await chatService?.deleteConversationsForAssistant(id);

    final wasCloudHosted = _assistants[idx].cloudHosted;
    final removingCurrent = _assistants[idx].id == _currentAssistantId;
    _assistants.removeAt(idx);
    if (wasCloudHosted) _deleteFromCloud(id);
    if (removingCurrent) {
      _currentAssistantId = _assistants.isNotEmpty
          ? _assistants.first.id
          : null;
    }
    await _persist();
    final prefs = await SharedPreferences.getInstance();
    if (_currentAssistantId != null) {
      await prefs.setString(_currentAssistantKey, _currentAssistantId!);
    } else {
      await prefs.remove(_currentAssistantKey);
    }
    notifyListeners();
    return true;
  }

  Future<void> reorderAssistants(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _assistants.length) return;
    if (newIndex < 0 || newIndex >= _assistants.length) return;

    final assistant = _assistants.removeAt(oldIndex);
    _assistants.insert(newIndex, assistant);

    // Notify listeners immediately for smooth UI update
    notifyListeners();

    // Then persist the changes
    await _persist();
  }

  // Reorder only within a subset (e.g., assistants belonging to a tag group or ungrouped).
  // subsetIds defines the set and order boundary; other assistants remain in place.
  Future<void> reorderAssistantsWithin({
    required List<String> subsetIds,
    required int oldIndex,
    required int newIndex,
  }) async {
    if (oldIndex == newIndex) return;
    if (subsetIds.isEmpty) return;

    // Build subset indices in the master list preserving current order
    final idSet = subsetIds.toSet();
    final subsetIndices = <int>[];
    for (int i = 0; i < _assistants.length; i++) {
      if (idSet.contains(_assistants[i].id)) subsetIndices.add(i);
    }
    if (subsetIndices.isEmpty) return;
    if (oldIndex < 0 || oldIndex >= subsetIndices.length) return;
    if (newIndex < 0 || newIndex >= subsetIndices.length) return;

    // Extract subset in current order
    final subset = subsetIndices
        .map((i) => _assistants[i])
        .toList(growable: true);
    final moved = subset.removeAt(oldIndex);
    subset.insert(newIndex, moved);

    // Merge back into master list
    final merged = <Assistant>[];
    int take = 0;
    for (int i = 0; i < _assistants.length; i++) {
      final a = _assistants[i];
      if (idSet.contains(a.id)) {
        merged.add(subset[take++]);
      } else {
        merged.add(a);
      }
    }
    _assistants
      ..clear()
      ..addAll(merged);

    notifyListeners();
    await _persist();
  }
}

/// [kelivo-hosted] Thrown by `addAssistant`/`duplicateAssistant` when the
/// blocking cloud-create call fails (offline, server error, etc.) — the
/// assistant is deliberately never stored locally in that case (see
/// `AssistantProvider.addAssistant`'s doc comment), so callers must catch
/// this and surface it rather than assuming creation always succeeds.
class AssistantSyncException implements Exception {
  AssistantSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _AssistantDecodeResult {
  const _AssistantDecodeResult({
    required this.assistants,
    required this.didApplyLegacySearch,
  });

  final List<Assistant> assistants;
  final bool didApplyLegacySearch;
}

enum _AssistantCloudPullResult { adopted, empty, unavailable }
