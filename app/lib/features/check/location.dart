import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Titik acuan bila lokasi tidak tersedia (sekitar Bandung, sesuai data faskes contoh).
const defaultLat = -6.8915;
const defaultLng = 107.6107;

abstract class LocationService {
  /// null bila layanan lokasi mati, izin ditolak, atau gagal; pemanggil memakai titik acuan.
  Future<({double lat, double lng})?> current();
}

class DeviceLocationService implements LocationService {
  @override
  Future<({double lat, double lng})?> current() async {
    // Batas total: izin lokasi yang menggantung tidak boleh menahan daftar faskes.
    return _lookup().timeout(const Duration(seconds: 6), onTimeout: () => null);
  }

  Future<({double lat, double lng})?> _lookup() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
      );
      return (lat: position.latitude, lng: position.longitude);
    } catch (_) {
      return null;
    }
  }
}

final locationProvider = Provider<LocationService>((ref) => DeviceLocationService());
