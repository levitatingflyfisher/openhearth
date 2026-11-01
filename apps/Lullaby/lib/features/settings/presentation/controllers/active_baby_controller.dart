import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../babies/domain/entities/baby.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/retry_policy.dart';

final activeBabyProvider = StreamProvider<BabyEntity?>((ref) {
  final repo = ref.watch(babyRepositoryProvider);
  return repo.watchActiveBaby();
},
  retry: noAutoRetry,
);
