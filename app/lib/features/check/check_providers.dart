import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/models.dart';
import 'location.dart';

final checkProvider = FutureProvider<CheckRecommendation?>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getCheck();
});

class NearbyFaskes {
  const NearbyFaskes(this.faskes, {required this.approximate, this.lat = defaultLat, this.lng = defaultLng});
  final List<Faskes> faskes;

  /// Titik yang dipakai mencari; untuk tautan "cari di Google Maps".
  final double lat, lng;

  /// true bila lokasi pengguna tidak tersedia dan titik acuan dipakai.
  final bool approximate;
}

final faskesProvider = FutureProvider<NearbyFaskes>((ref) async {
  ref.watch(authProvider.select((s) => s.token));
  final position = await ref.read(locationProvider).current();
  final lat = position?.lat ?? defaultLat, lng = position?.lng ?? defaultLng;
  final list = await ref.read(apiProvider).nearbyFaskes(lat, lng);
  return NearbyFaskes(list, approximate: position == null, lat: lat, lng: lng);
});
