import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_plan.dart';

/// Notifikasi lokal terjadwal. Dipisah dari plugin agar logika pengingat bisa diuji tanpa perangkat.
abstract class NotificationService {
  /// Minta izin bila perlu. false bila ditolak atau platform tidak mendukung.
  Future<bool> ensurePermission();

  /// Mengganti semua jadwal dengan [reminders].
  Future<void> apply(List<PlannedReminder> reminders);

  Future<void> cancelAll();
}

class LocalNotificationService implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'kira_reminders',
    'Pengingat KIRA',
    channelDescription: 'Pengingat check-in, rekap mingguan, dan tindak lanjut saran cek. Tanpa data kesehatan di isinya.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  /// Notifikasi tidak boleh merusak aplikasi: kegagalan plugin (platform tak didukung, dll.) dianggap "tidak tersedia".
  Future<T> _guard<T>(T fallback, Future<T> Function() body) async {
    try {
      return await body();
    } catch (_) {
      return fallback;
    }
  }

  Future<bool> _init() async {
    if (kIsWeb) return false;
    if (_ready) return true;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    _ready = true;
    return true;
  }

  @override
  Future<bool> ensurePermission() => _guard(false, () async {
        if (!await _init()) return false;
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (android == null) return false;
        return (await android.areNotificationsEnabled() ?? false) ||
            (await android.requestNotificationsPermission() ?? false);
      });

  @override
  Future<void> apply(List<PlannedReminder> reminders) => _guard(null, () async {
        if (!await _init()) return;
        await _plugin.cancelAllPendingNotifications();
        for (final r in reminders) {
          await _plugin.zonedSchedule(
            id: r.id,
            title: r.title,
            body: r.body,
            scheduledDate: tz.TZDateTime.from(r.at, tz.local),
            notificationDetails: const NotificationDetails(android: _channel),
            // Tidak butuh izin alarm tepat waktu; telat beberapa menit tidak masalah untuk pengingat.
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      });

  @override
  Future<void> cancelAll() => _guard(null, () async {
        if (!await _init()) return;
        await _plugin.cancelAllPendingNotifications();
      });
}

final notificationServiceProvider = Provider<NotificationService>((ref) => LocalNotificationService());
