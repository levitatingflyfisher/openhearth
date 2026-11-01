import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/result.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/providers/retry_policy.dart';
import 'export_service.dart';

final rawExportProvider =
    FutureProvider.family<String, String>((ref, babyId) async {
  final feedingRepo = ref.watch(feedingRepositoryProvider);
  final sleepRepo = ref.watch(sleepRepositoryProvider);
  final diaperRepo = ref.watch(diaperRepositoryProvider);
  final growthRepo = ref.watch(growthRepositoryProvider);
  final medicineRepo = ref.watch(medicineRepositoryProvider);
  final vaccineRepo = ref.watch(vaccineRepositoryProvider);

  final feedingResult = await feedingRepo.getAllForBaby(babyId);
  final sleepResult = await sleepRepo.getAllForBaby(babyId);
  final diaperResult = await diaperRepo.getAllForBaby(babyId);
  final growthResult = await growthRepo.getAllForBaby(babyId);
  final medicineResult = await medicineRepo.getAllForBaby(babyId);
  final vaccineResult = await vaccineRepo.getAllForBaby(babyId);

  // Any failed read fails the export: a CSV missing the feeds, or with
  // nothing in it, reads as "the log is gone". The screen says the read
  // failed and writes no file.
  return const ExportService().generateRawCsv(
    feedings: feedingResult.orThrow(),
    sleeps: sleepResult.orThrow(),
    diapers: diaperResult.orThrow(),
    growthRecords: growthResult.orThrow(),
    medicines: medicineResult.orThrow(),
    vaccines: vaccineResult.orThrow(),
  );
}, name: 'rawExportProvider',
  retry: noAutoRetry,
);
