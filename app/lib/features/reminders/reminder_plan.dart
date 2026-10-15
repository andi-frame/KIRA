import 'dart:convert';

/// Pengaturan pengingat. Semuanya mati secara bawaan: pengguna yang memilih, bukan KIRA yang mengganggu.
class ReminderSettings {
  const ReminderSettings({
    this.daily = false,
    this.hour = 19,
    this.minute = 0,
    this.weekly = false,
    this.checkFollowUp = false,
  });

  final bool daily; // ajakan check-in harian (dilewati bila hari ini sudah mencatat)
  final int hour, minute;
  final bool weekly; // rekap minggu lalu, tiap Senin pagi
  final bool checkFollowUp; // tanya "sudah dicek?" saat saran cek sudah beberapa hari

  bool get anyEnabled => daily || weekly || checkFollowUp;

  ReminderSettings copyWith({bool? daily, int? hour, int? minute, bool? weekly, bool? checkFollowUp}) =>
      ReminderSettings(
        daily: daily ?? this.daily,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        weekly: weekly ?? this.weekly,
        checkFollowUp: checkFollowUp ?? this.checkFollowUp,
      );

  String toJson() => jsonEncode({'daily': daily, 'hour': hour, 'minute': minute, 'weekly': weekly, 'check': checkFollowUp});

  factory ReminderSettings.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const ReminderSettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return ReminderSettings(
        daily: j['daily'] as bool? ?? false,
        hour: ((j['hour'] as num?)?.toInt() ?? 19).clamp(0, 23),
        minute: ((j['minute'] as num?)?.toInt() ?? 0).clamp(0, 59),
        weekly: j['weekly'] as bool? ?? false,
        checkFollowUp: j['check'] as bool? ?? false,
      );
    } catch (_) {
      return const ReminderSettings();
    }
  }
}

class PlannedReminder {
  const PlannedReminder({required this.id, required this.at, required this.title, required this.body});
  final int id;
  final DateTime at;
  final String title, body;
}

const dailyIdBase = 1000, weeklyIdBase = 2000, checkId = 3000;
const dailyHorizonDays = 7, weeklyHorizonWeeks = 4;
const weeklyHour = 8, checkHour = 9;

/// Menyusun pengingat yang perlu dijadwalkan. Fungsi murni supaya mudah diuji.
///
/// Isi notifikasi sengaja tidak memuat data kesehatan apa pun: layar kunci bisa dilihat orang lain.
/// Pengingat harian hanya dijadwalkan beberapa hari ke depan dan disusun ulang tiap aplikasi dibuka atau pengguna
/// mencatat, sehingga hari yang sudah ada catatannya tidak diingatkan lagi.
List<PlannedReminder> planReminders({
  required DateTime now,
  required ReminderSettings settings,
  required bool loggedToday,
  required bool checkFollowUpDue,
}) {
  final out = <PlannedReminder>[];
  final today = DateTime(now.year, now.month, now.day);

  if (settings.daily) {
    for (var d = 0; d < dailyHorizonDays; d++) {
      final at = today.add(Duration(days: d)).copyWith(hour: settings.hour, minute: settings.minute);
      if (!at.isAfter(now)) continue;
      if (d == 0 && loggedToday) continue;
      out.add(PlannedReminder(
        id: dailyIdBase + d,
        at: at,
        title: 'Check-in KIRA',
        body: 'Satu menit saja: ceritakan makan, minum, dan tidurmu hari ini.',
      ));
    }
  }

  if (settings.weekly) {
    final daysToMonday = (DateTime.monday - today.weekday + 7) % 7;
    for (var w = 0; w < weeklyHorizonWeeks; w++) {
      final at = today.add(Duration(days: daysToMonday + 7 * w)).copyWith(hour: weeklyHour, minute: 0);
      if (!at.isAfter(now)) continue;
      out.add(PlannedReminder(
        id: weeklyIdBase + w,
        at: at,
        title: 'Rekap minggumu siap',
        body: 'Lihat apa yang berubah dari kebiasaanmu minggu lalu.',
      ));
    }
  }

  if (settings.checkFollowUp && checkFollowUpDue) {
    var at = today.copyWith(hour: checkHour, minute: 0);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    out.add(PlannedReminder(
      id: checkId,
      at: at,
      title: 'Sudah sempat cek?',
      body: 'KIRA ingin tahu kabar saran cek beberapa hari lalu. Tidak mendesak, buka kapan saja.',
    ));
  }
  return out;
}
