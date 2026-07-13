import 'client_backend_api.dart';
import 'client_backend_config.dart';

/// Sentinel provider key for the Kelivo-hosted-client backend (kelivo-arch.md
/// §5/§8). Deliberately never persisted into `SettingsProvider.providerConfigs`
/// (that map backs the user-facing Provider management page, and this
/// provider's "apiKey" is actually a live JWT — showing/editing/sharing it
/// there would leak the session, see kelivo-arch.md §8's "Plan A vs B"
/// note). Instead, `SettingsProvider.getProviderConfig` special-cases this
/// key and synthesizes a `ProviderConfig` on the fly from this holder.
const String kHostedProviderKey = 'kelivo_hosted';

/// In-memory mirror of the current hosted-client session, kept in sync by
/// `AuthProvider` (the source of truth — JWT persisted via
/// `flutter_secure_storage`, see `core/providers/auth_provider.dart`).
/// Exists so `SettingsProvider.getProviderConfig` (a synchronous method
/// called from many places, see kelivo-arch.md §8) can produce a hosted
/// `ProviderConfig` without `SettingsProvider` holding a reference to
/// `AuthProvider`.
class ClientBackendSession {
  ClientBackendSession._();

  static String? token;
  static List<ClientModelInfo> models = [];
  // [kelivo-hosted] `role -> model_id` — see `ClientBackendApi.fetchDefaultModels`.
  // Consulted by `SettingsProvider`'s hosted-mode model resolution for
  // every model slot except the chat model itself (OCR/suggestion/
  // translation/context-compression) — see kelivo-arch.md 1.1 and
  // `SettingsProvider.hostedDefaultModelFor`.
  static Map<String, String> defaultModels = {};

  /// Re-fetches the hosted model catalog from `/__client/models` and the
  /// role→model default assignments from `/__client/models/defaults`. Fire
  /// this before reading `models`/`defaultModels` synchronously elsewhere
  /// (e.g. right after login, or when the model-select sheet opens) —
  /// there's no push notification for catalog/default changes, just a
  /// manual refresh.
  static Future<void> refresh() async {
    final t = token;
    if (t == null) {
      models = [];
      defaultModels = {};
      return;
    }
    final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
    final result = await api.fetchModels(t);
    if (result.isSuccess) models = result.models!;
    defaultModels = await api.fetchDefaultModels(t);
  }

  static void clear() {
    token = null;
    models = [];
    defaultModels = {};
  }

  /// [kelivo-hosted] Pushes (or, with `modelId: null`, clears) the account's
  /// title-generation model preference — called from
  /// `SettingsProvider.setTitleModel`/`resetTitleModel` whenever the title
  /// model is (or was) the hosted provider. Fire-and-forget: the setting is
  /// still saved locally regardless of whether this network call succeeds.
  static Future<void> pushTitleModel(String? modelId) async {
    final t = token;
    if (t == null) return;
    final api = ClientBackendApi(baseUrl: clientBackendBaseUrl);
    await api.updateTitleModel(t, modelId);
  }
}
