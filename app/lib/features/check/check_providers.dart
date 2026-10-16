import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/models.dart';
import 'location.dart';

final checkProvider = FutureProvider<CheckRecommendation?>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getCheck();
});

class NearbyFaskes {
  const NearbyFaskes(this.faskes, {required this.location, this.lat, this.lng, this.mapDataMissing = false});

  /// Lokasi belum tersedia: tidak ada daftar, layar menampilkan ajakan mengaktifkan lokasi.
  const NearbyFaskes.needsLocation(LocationStatus status) : this(const [], location: status);

  final List<Faskes> faskes;
  final LocationStatus location;

  /// Titik pengguna; untuk tautan "cari di Google Maps".
  final double? lat, lng;

  /// Server hanya punya daftar contoh (data peta gagal dimuat). Daftar contoh tidak ditampilkan.
  final bool mapDataMissing;
}

final faskesProvider = FutureProvider<NearbyFaskes>((ref) async {
  ref.watch(authProvider.select((s) => s.token));
  final fix = await ref.read(locationProvider).current();
  if (fix.status != LocationStatus.found) return NearbyFaskes.needsLocation(fix.status);
  final list = await ref.read(apiProvider).nearbyFaskes(fix.lat!, fix.lng!);
  final real = [for (final f in list) if (f.source != 'seed') f];
  return NearbyFaskes(real, location: LocationStatus.found, lat: fix.lat, lng: fix.lng, mapDataMissing: real.isEmpty);
});
