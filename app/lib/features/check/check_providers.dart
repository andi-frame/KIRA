import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/models.dart';
import 'location.dart';

final checkProvider = FutureProvider<CheckRecommendation?>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getCheck();
});

class NearbyFaskes {
  const NearbyFaskes(this.faskes, {required this.approximate});
  final List<Faskes> faskes;

  /// true bila lokasi pengguna tidak tersedia dan titik acuan dipakai.
  final bool approximate;
}

final faskesProvider = FutureProvider<NearbyFaskes>((ref) async {
  ref.watch(authProvider.select((s) => s.token));
  final position = await ref.read(locationProvider).current();
  final list = await ref.read(apiProvider).nearbyFaskes(position?.lat ?? defaultLat, position?.lng ?? defaultLng);
  return NearbyFaskes(list, approximate: position == null);
});
