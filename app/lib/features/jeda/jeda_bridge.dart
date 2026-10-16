import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'jeda_models.dart';

class JedaPermissions {
  const JedaPermissions({this.usageAccess = false, this.overlay = false});

  /// "Akses penggunaan": agar KIRA tahu aplikasi mana yang sedang dibuka (tidak membaca isinya).
  final bool usageAccess;

  /// "Tampil di atas aplikasi lain": agar kartu bisa muncul sebelum aplikasi sosmed.
  final bool overlay;

  bool get ready => usageAccess && overlay;
}

class JedaApp {
  const JedaApp(this.package, this.label);
  final String package, label;
}

/// Jembatan ke bagian Android (layanan yang memantau aplikasi di depan). Dipisah agar logika dan layar bisa diuji
/// tanpa perangkat; di web dan iOS tidak tersedia.
abstract class JedaBridge {
  bool get supported;
  Future<JedaPermissions> permissions();
  Future<void> openUsageAccess();
  Future<void> openOverlay();
  Future<List<JedaApp>> installedApps();

  /// Menyimpan pengaturan + isi kartu di perangkat dan menyalakan atau mematikan layanan sesuai `enabled`.
  Future<void> apply(JedaSettings settings, JedaPayload? payload);
  Future<void> stop();

  /// Menampilkan kartu [kind] (morning | evening | night | other) sekarang, sebagai contoh. Tidak dicatat sebagai tampil.
  Future<void> preview(String kind);

  /// Rute yang diminta tombol kartu (mis. /chat), sekali ambil.
  Future<String?> takeLaunchRoute();
}

class MethodChannelJedaBridge implements JedaBridge {
  static const _channel = MethodChannel('id.kira.kira/jeda');

  @override
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<T> _call<T>(String method, T fallback, [Object? args]) async {
    if (!supported) return fallback;
    try {
      return (await _channel.invokeMethod<T>(method, args)) ?? fallback;
    } on PlatformException {
      return fallback;
    } on MissingPluginException {
      return fallback;
    }
  }

  @override
  Future<JedaPermissions> permissions() async {
    final m = await _call<Map<Object?, Object?>>('permissions', const {});
    return JedaPermissions(usageAccess: m['usage_access'] == true, overlay: m['overlay'] == true);
  }

  @override
  Future<void> openUsageAccess() => _call<bool>('openUsageAccess', false);

  @override
  Future<void> openOverlay() => _call<bool>('openOverlay', false);

  @override
  Future<List<JedaApp>> installedApps() async {
    final raw = await _call<List<Object?>>('installedApps', const []);
    return [
      for (final e in raw)
        if (e is Map) JedaApp(e['package'] as String, e['label'] as String),
    ];
  }

  @override
  Future<void> apply(JedaSettings settings, JedaPayload? payload) => _call<bool>('apply', false, {
        'settings': jsonEncode(settings.toMap()),
        'payload': payload == null ? null : jsonEncode(payload.toMap()),
      });

  @override
  Future<void> stop() => _call<bool>('stop', false);

  @override
  Future<void> preview(String kind) => _call<bool>('preview', false, {'kind': kind});

  @override
  Future<String?> takeLaunchRoute() async {
    final r = await _call<String>('takeLaunchRoute', '');
    return r.isEmpty ? null : r;
  }
}

final jedaBridgeProvider = Provider<JedaBridge>((ref) => MethodChannelJedaBridge());
