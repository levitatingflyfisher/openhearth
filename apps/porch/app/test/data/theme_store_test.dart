// The theme choice persists behind SecretStore, like the relay URL, so it
// is readable before onboarding (no PorchState exists yet) and before
// runApp (no flash of the wrong theme).
import 'package:test/test.dart';

import 'package:porch_app/data/key_store.dart' show InMemorySecretStore;
import 'package:porch_app/data/theme_store.dart';

void main() {
  test(
    'nothing stored reads as null (the caller defaults to follow phone)',
    () async {
      expect(await ThemePreferenceStore(InMemorySecretStore()).read(), isNull);
    },
  );

  test('a written value round-trips', () async {
    final store = ThemePreferenceStore(InMemorySecretStore());
    await store.write('dark');
    expect(await store.read(), 'dark');
  });

  test('it lives under its own versioned key', () async {
    final secrets = InMemorySecretStore();
    await ThemePreferenceStore(secrets).write('light');
    expect(await secrets.read(ThemePreferenceStore.key), 'light');
    expect(ThemePreferenceStore.key, 'porch.theme.v1');
  });
}
