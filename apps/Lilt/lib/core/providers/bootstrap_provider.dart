import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'repository_providers.dart';
import 'retry_policy.dart';

/// Async provider that resolves once the name catalog is loaded into SQLite.
/// Await this in the app shell before allowing navigation to any screen.
final bootstrapProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(namesRepositoryProvider);
  await repo.ensureLoaded();
}, retry: noAutoRetry);
