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

/// Keadaan penjagaan dari sisi Android, untuk layar status. Tidak ada isi layar atau data kesehatan di sini.
class JedaDiagnostics {
  const JedaDiagnostics({
    this.serviceAlive = false,
    this.lastTickAt,
    this.lastFrontLabel,
    this.lastFrontAt,
    this.lastGuardedLabel,
    this.lastGuardedAt,
    this.lastReason = '',
    this.lastError = '',
    this.shownTotal = 0,
    this.nowCode = 'off',
    this.nowKinds = const [],
    this.graceUntil,
    this.batteryIgnored = true,
    this.manufacturer = '',
    this.sdk = 0,
  });

  final bool serviceAlive;
  final DateTime? lastTickAt, lastFrontAt, lastGuardedAt, graceUntil;
  final String? lastFrontLabel, lastGuardedLabel;

  /// Alasan terakhir untuk aplikasi pilihan yang dibuka: shown | outside_window | grace | ... (lihat layar status).
  final String lastReason, lastError;
  final int shownTotal;

  /// Seandainya aplikasi pilihan dibuka sekarang: ready | off | no_apps | skip_day | grace | no_content | outside_window |
  /// cap_reached | already_logged.
  final String nowCode;
  final List<String> nowKinds;
  final bool batteryIgnored;
  final String manufacturer;
  final int sdk;

  static DateTime? _ms(Object? v) => v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  factory JedaDiagnostics.fromMap(Map<Object?, Object?> m) => JedaDiagnostics(
        serviceAlive: m['service_alive'] == true,
        lastTickAt: _ms(m['last_tick_at']),
        lastFrontLabel: m['last_front_label'] as String?,
        lastFrontAt: _ms(m['last_front_at']),
        lastGuardedLabel: m['last_guarded_label'] as String?,
        lastGuardedAt: _ms(m['last_guarded_at']),
        lastReason: (m['last_reason'] as String?) ?? '',
        lastError: (m['last_error'] as String?) ?? '',
        shownTotal: (m['shown_total'] as num?)?.toInt() ?? 0,
        nowCode: (m['now_code'] as String?) ?? 'off',
        nowKinds: [for (final k in (m['now_kinds'] as List? ?? const [])) '$k'],
        graceUntil: _ms(m['grace_until']),
        batteryIgnored: m['battery_ignored'] != false,
        manufacturer: ((m['manufacturer'] as String?) ?? '').toLowerCase(),
        sdk: (m['sdk'] as num?)?.toInt() ?? 0,
      );
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

  /// Halaman "Info aplikasi" KIRA di pengaturan Android. Di sana ada menu ⋮ > "Izinkan setelan terbatas" yang dibutuhkan
  /// aplikasi hasil pasang manual (bukan dari toko) sebelum izin akses penggunaan dan tampil di atas aplikasi lain bisa diberikan.
  Future<void> openAppInfo();

  /// Daftar penghemat baterai di pengaturan Android, untuk mengecualikan KIRA.
  Future<void> openBatterySettings();

  /// Status penjagaan (layanan hidup, aplikasi terakhir terdeteksi, mengapa kartu tampil atau tidak). null di platform tanpa dukungan.
  Future<JedaDiagnostics?> diagnostics();
  Future<List<JedaApp>> installedApps();

  /// Menyimpan pengaturan + isi kartu di perangkat dan menyalakan atau mematikan layanan sesuai `enabled`.
  Future<void> apply(JedaSettings settings, JedaPayload? payload);
  Future<void> stop();

  /// Menampilkan kartu [kind] (morning | evening | night | other | fact) sekarang, sebagai contoh. Tidak dicatat sebagai tampil.
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
  Future<void> openAppInfo() => _call<bool>('openAppInfo', false);

  @override
  Future<void> openBatterySettings() => _call<bool>('openBatterySettings', false);

  @override
  Future<JedaDiagnostics?> diagnostics() async {
    final m = await _call<Map<Object?, Object?>>('diagnostics', const {});
    return m.isEmpty ? null : JedaDiagnostics.fromMap(m);
  }

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
        'settings': jsonEncode(settings.toBridgeMap()),
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
