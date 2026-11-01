import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sundial/core/providers/core_providers.dart';
import 'package:sundial/core/storage/app_database.dart' hide UserPrefs;
import 'package:sundial/features/profiles/domain/profiles_repository.dart';
import 'package:sundial/features/settings/domain/settings_repository.dart';
import 'package:sundial/features/settings/domain/user_prefs.dart';

/// Every read of the local database fails the way a broken disk does: with
/// an Exception (riverpod 3 retries Exceptions, not Errors).
class _BrokenSettingsRepo implements SettingsRepository {
  int appModeReads = 0;
  int prefsReads = 0;

  @override
  Stream<AppMode> watchAppMode() {
    appModeReads++;
    return Stream.error(Exception('disk read failed'));
  }

  @override
  Stream<UserPrefs> watchUserPrefs() {
    prefsReads++;
    return Stream.error(Exception('disk read failed'));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _BrokenProfilesRepo implements ProfilesRepository {
  int reads = 0;

  @override
  Stream<List<Profile>> watchAll() {
    reads++;
    return Stream.error(Exception('disk read failed'));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Shows "failed" once each provider is in error, so the test can see the
/// error is still what the screen holds after the wait.
class _Probe extends ConsumerWidget {
  const _Probe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = [
      ref.watch(appModeProvider),
      ref.watch(userPrefsProvider),
      ref.watch(profilesListProvider),
    ];
    return Column(
      children: [
        for (final s in states) Text(s.hasError ? 'failed' : 'waiting'),
      ],
    );
  }
}

/// A failed read of the device's own database is read once and stays failed.
/// Riverpod 3 would otherwise read it again up to 10 times on its own, from
/// 200 ms apart: a loop against a broken disk that nobody asked for. Sundial
/// keeps riverpod 2's behaviour here (no automatic retry) on the providers
/// themselves, so this holds in any scope, not only the app's root scope.
void main() {
  testWidgets('a failed disk read is not retried on its own', (tester) async {
    final settings = _BrokenSettingsRepo();
    final profiles = _BrokenProfilesRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        profilesRepositoryProvider.overrideWithValue(profiles),
      ],
      child: const MaterialApp(home: Scaffold(body: _Probe())),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('failed'), findsNWidgets(3));

    // Long enough for several of riverpod 3's default retries.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(settings.appModeReads, 1, reason: 'app mode is read once');
    expect(settings.prefsReads, 1, reason: 'settings are read once');
    expect(profiles.reads, 1, reason: 'the profile list is read once');
    expect(find.text('failed'), findsNWidgets(3),
        reason: 'the error stays, not a spinner');
  });
}
