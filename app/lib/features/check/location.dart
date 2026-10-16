import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Keadaan lokasi untuk mencari tempat cek. Selain `found`, layar Cek menampilkan ajakan yang sesuai penyebabnya.
enum LocationStatus {
  found,

  /// Layanan lokasi (GPS) ponsel mati.
  serviceOff,

  /// Izin belum pernah diberikan; dialog izin masih bisa dimunculkan.
  needsPermission,

  /// Izin ditolak permanen; hanya bisa dibuka dari pengaturan aplikasi.
  blocked,

  /// Izin ada tetapi posisi belum terbaca (tanpa sinyal GPS, waktu habis).
  unavailable,
}

typedef LocationFix = ({LocationStatus status, double? lat, double? lng});

const LocationFix _unavailable = (status: LocationStatus.unavailable, lat: null, lng: null);

abstract class LocationService {
  /// Posisi saat ini tanpa memunculkan dialog izin: dialog hanya muncul setelah pengguna menekan "Izinkan lokasi".
  Future<LocationFix> current();

  /// Munculkan dialog izin lokasi, lalu baca posisi.
  Future<LocationFix> requestAndLocate();

  Future<void> openLocationSettings();
  Future<void> openAppSettings();
}

class DeviceLocationService implements LocationService {
  @override
  Future<LocationFix> current() => _lookup(ask: false);

  @override
  Future<LocationFix> requestAndLocate() => _lookup(ask: true);

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<LocationFix> _lookup({required bool ask}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return (status: LocationStatus.serviceOff, lat: null, lng: null);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && ask) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) return (status: LocationStatus.blocked, lat: null, lng: null);
      if (permission == LocationPermission.denied) return (status: LocationStatus.needsPermission, lat: null, lng: null);
      Position? position;
      try {
        // Akurasi tinggi supaya GPS ikut dipakai: mode hemat daya hanya memakai lokasi jaringan (Wi-Fi/BTS) dan bisa
        // tidak pernah mendapat posisi. Batas waktu: posisi yang menggantung tidak boleh menahan layar Cek.
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        // Di dalam gedung GPS sering belum dapat posisi baru: posisi terakhir yang diketahui cukup untuk mencari faskes.
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) return _unavailable;
      return (status: LocationStatus.found, lat: position.latitude, lng: position.longitude);
    } catch (_) {
      return _unavailable;
    }
  }
}

final locationProvider = Provider<LocationService>((ref) => DeviceLocationService());
