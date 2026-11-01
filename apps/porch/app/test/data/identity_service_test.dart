// W3-data: identity_service — first-launch keygen persists entropy to the
// secure-storage abstraction; every later load derives the SAME identity.
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:porch_app/data/identity_service.dart';
import 'package:porch_app/data/key_store.dart';

import '../domain/support/test_sodium.dart';

void main() {
  test('fresh install: load() is null; create() persists; load() rederives',
      () async {
    final sodium = await loadTestSodium();
    final keys = PorchKeyStore(InMemorySecretStore());
    final svc = IdentityService(sodium, keys);

    expect(await svc.load(), isNull);
    final created = await svc.create();
    final loaded = await svc.load();
    expect(loaded, isNotNull);
    expect(loaded!.mailboxId, created.mailboxId);
    expect(loaded.sign.publicKey, created.sign.publicKey);
    expect(await keys.readEntropy(), created.entropy);
  });

  test('create() with explicit entropy is deterministic (restore path)',
      () async {
    final sodium = await loadTestSodium();
    final entropy = Uint8List.fromList(List.filled(16, 42));
    final a = await IdentityService(sodium, PorchKeyStore(InMemorySecretStore()))
        .create(entropy: entropy);
    final b = await IdentityService(sodium, PorchKeyStore(InMemorySecretStore()))
        .create(entropy: entropy);
    expect(a.mailboxId, b.mailboxId);
    expect(a.box.publicKey, b.box.publicKey);
  });

  test('create() over an existing identity refuses — identity is forever',
      () async {
    final sodium = await loadTestSodium();
    final svc = IdentityService(sodium, PorchKeyStore(InMemorySecretStore()));
    await svc.create();
    await expectLater(svc.create(), throwsA(isA<StateError>()));
  });
}
