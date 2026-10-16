import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/record_models.dart';

/// Rekam medis pribadi pengguna (terbaru dulu).
final recordsProvider = FutureProvider<List<MedicalRecord>>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).listRecords();
});
