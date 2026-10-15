import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Membuka tautan di luar aplikasi (peta, peramban). Dipisah dari plugin agar mudah diuji.
abstract class LinkOpener {
  /// false bila tidak ada aplikasi yang bisa membukanya.
  Future<bool> open(Uri uri);
}

class UrlLauncherOpener implements LinkOpener {
  const UrlLauncherOpener();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

final linkOpenerProvider = Provider<LinkOpener>((ref) => const UrlLauncherOpener());

/// Tautan peta Google Maps untuk koordinat (terbuka di aplikasi Maps bila terpasang, selain itu di peramban).
Uri mapsUri(double lat, double lng, {String? label}) => Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': label == null ? '$lat,$lng' : '$label @$lat,$lng',
    });
