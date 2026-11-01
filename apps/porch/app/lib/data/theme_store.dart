// theme_store — the person's light / dark / follow-the-phone choice.
//
// Stored as a plain string behind SecretStore, the same abstraction the
// relay URL rides (relay_config.dart): it persists identically on device
// and on web, it exists before onboarding (no PorchState yet), and it can
// be read before runApp so the first frame is already in the right theme.
// Flutter-free like the rest of lib/data: the mapping to the fleet's
// OhThemeModePreference happens in the presentation layer.
import 'key_store.dart' show SecretStore;

class ThemePreferenceStore {
  static const key = 'porch.theme.v1';

  final SecretStore _store;
  const ThemePreferenceStore(this._store);

  /// The stored choice, or null if the person never picked one.
  Future<String?> read() => _store.read(key);

  Future<void> write(String value) => _store.write(key, value);
}
