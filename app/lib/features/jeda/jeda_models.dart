import 'dart:convert';

import 'jeda_facts.dart';

/// Jeda Sosmed: sebelum membuka aplikasi media sosial yang dipilih, KIRA menampilkan satu kartu singkat
/// (rencana pagi, catat hari ini, atau waktunya tidur). Semua mati sampai pengguna menyalakannya sendiri.

/// Aplikasi yang biasa dipakai berlama-lama. Pengguna memilih sendiri; hanya yang terpasang yang ditawarkan.
/// WhatsApp sengaja tidak ada: KIRA sendiri bicara lewat WhatsApp.
const knownSocialApps = <String, String>{
  'com.instagram.android': 'Instagram',
  'com.twitter.android': 'X',
  'com.facebook.katana': 'Facebook',
  'com.zhiliaoapp.musically': 'TikTok',
  'com.ss.android.ugc.trill': 'TikTok',
  'com.instagram.barcelona': 'Threads',
  'com.snapchat.android': 'Snapchat',
  'com.reddit.frontpage': 'Reddit',
  'com.pinterest': 'Pinterest',
  'com.linkedin.android': 'LinkedIn',
  'com.google.android.youtube': 'YouTube',
};

/// Aplikasi yang dipilih otomatis saat pertama kali dinyalakan (YouTube dan LinkedIn bisa dipakai untuk bekerja).
const defaultSocialApps = <String>{
  'com.instagram.android',
  'com.twitter.android',
  'com.facebook.katana',
  'com.zhiliaoapp.musically',
  'com.ss.android.ugc.trill',
  'com.instagram.barcelona',
  'com.snapchat.android',
};

int _clamp(Object? v, int fallback, int lo, int hi) => ((v as num?)?.toInt() ?? fallback).clamp(lo, hi);

class JedaSettings {
  const JedaSettings({
    this.enabled = false,
    this.apps = const [],
    this.morningStart = 5 * 60,
    this.eveningStart = 19 * 60,
    this.nightStart = 21 * 60 + 30,
    this.graceMinutes = 30,
    this.showOther = true,
    this.funFact = false,
    this.useGrace = true,
  });

  final bool enabled;

  /// Nama paket Android yang dijaga.
  final List<String> apps;

  /// Menit sejak tengah malam (waktu ponsel). Pagi berlangsung 6 jam, catat malam sampai tengah malam, tidur sampai 04.00.
  final int morningStart, eveningStart, nightStart;

  /// Setelah kartu ditutup, aplikasi apa pun bebas dibuka selama sekian menit.
  final int graceMinutes;

  /// Kartu "sudah sempat cek?" (saran cek ke dokter), bila ada yang tertunda.
  final bool showOther;

  /// Tiap kali aplikasi pilihan dibuka (di luar jeda bebas), tampilkan satu fun fact kesehatan bersumber.
  final bool funFact;

  /// Setelah kartu ditutup, aplikasi apa pun bebas dibuka selama [graceMinutes]. Mati = kartu muncul lagi tiap kali dibuka.
  final bool useGrace;

  static const graceChoices = [15, 30, 60];

  JedaSettings copyWith({
    bool? enabled,
    List<String>? apps,
    int? morningStart,
    int? eveningStart,
    int? nightStart,
    int? graceMinutes,
    bool? showOther,
    bool? funFact,
    bool? useGrace,
  }) =>
      JedaSettings(
        enabled: enabled ?? this.enabled,
        apps: apps ?? this.apps,
        morningStart: morningStart ?? this.morningStart,
        eveningStart: eveningStart ?? this.eveningStart,
        nightStart: nightStart ?? this.nightStart,
        graceMinutes: graceMinutes ?? this.graceMinutes,
        showOther: showOther ?? this.showOther,
        funFact: funFact ?? this.funFact,
        useGrace: useGrace ?? this.useGrace,
      );

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'apps': apps,
        'morning_start': morningStart,
        'evening_start': eveningStart,
        'night_start': nightStart,
        'grace_minutes': graceMinutes,
        'show_other': showOther,
        'fun_fact': funFact,
        'use_grace': useGrace,
      };

  /// Yang dikirim ke Android: pengaturan + daftar fun fact (konstanta aplikasi, tidak disimpan di preferensi lokal).
  /// Fakta ikut di pengaturan, bukan di isi kartu, supaya tetap ada walau rencana tidak bisa dimuat (tanpa sinyal).
  Map<String, dynamic> toBridgeMap() => {
        ...toMap(),
        if (funFact) 'facts': [for (final f in jedaFacts) f.toMap()],
      };

  String toJson() => jsonEncode(toMap());

  factory JedaSettings.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const JedaSettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return JedaSettings(
        enabled: j['enabled'] as bool? ?? false,
        apps: [for (final a in (j['apps'] as List? ?? const [])) a as String],
        morningStart: _clamp(j['morning_start'], 5 * 60, 0, 1439),
        eveningStart: _clamp(j['evening_start'], 19 * 60, 0, 1439),
        nightStart: _clamp(j['night_start'], 21 * 60 + 30, 0, 1439),
        graceMinutes: _clamp(j['grace_minutes'], 30, 5, 240),
        showOther: j['show_other'] as bool? ?? true,
        funFact: j['fun_fact'] as bool? ?? false,
        useGrace: j['use_grace'] as bool? ?? true,
      );
    } catch (_) {
      return const JedaSettings();
    }
  }
}

class JedaSection {
  const JedaSection(this.heading, this.body);
  final String heading, body;

  Map<String, dynamic> toMap() => {'heading': heading, 'body': body};
}

/// Satu kartu: judul, beberapa bagian pendek, dan satu tombol yang membuka KIRA di [route].
class JedaCard {
  const JedaCard({
    required this.kind,
    required this.title,
    required this.sections,
    required this.actionLabel,
    required this.route,
    this.footnote = '',
  });

  /// morning | evening | night | other | fact
  final String kind;
  final String title;
  final List<JedaSection> sections;
  final String actionLabel, route, footnote;

  Map<String, dynamic> toMap() => {
        'kind': kind,
        'title': title,
        'sections': [for (final s in sections) s.toMap()],
        'action_label': actionLabel,
        'route': route,
        'footnote': footnote,
      };
}

/// Isi kartu yang dikirim ke bagian Android. Disusun di sini (bukan di sana) karena hanya Dart yang punya akses ke
/// rencana; Android hanya memilih kartu mana yang tampil sekarang.
class JedaPayload {
  const JedaPayload({
    required this.generatedAt,
    required this.morningByDate,
    required this.morningGeneric,
    required this.evening,
    required this.eveningGeneric,
    required this.night,
    this.other,
  });

  final DateTime generatedAt;

  /// Kartu pagi per tanggal (yyyy-MM-dd), hari ini sampai beberapa hari ke depan, supaya tetap benar walau KIRA
  /// tidak dibuka beberapa hari.
  final Map<String, JedaCard> morningByDate;
  final JedaCard morningGeneric;

  /// Kartu catat malam berdasarkan catatan saat [generatedAt]; null = semua sudah tercatat. Bila terlalu lama,
  /// bagian Android memakai [eveningGeneric].
  final JedaCard? evening;
  final JedaCard eveningGeneric;
  final JedaCard night;
  final JedaCard? other;

  Map<String, dynamic> toMap() => {
        'generated_at': generatedAt.millisecondsSinceEpoch,
        'morning_by_date': {for (final e in morningByDate.entries) e.key: e.value.toMap()},
        'morning_generic': morningGeneric.toMap(),
        'evening': evening?.toMap(),
        'evening_generic': eveningGeneric.toMap(),
        'night': night.toMap(),
        'other': other?.toMap(),
      };
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}.${(minutes % 60).toString().padLeft(2, '0')}';
