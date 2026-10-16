import '../../shared/models.dart';
import 'jeda_models.dart';

/// Menyusun isi kartu dari rencana harian. Fungsi murni: angka gizi dan jam tidur datang dari server, tidak dibuat di sini.
/// Kalimatnya tidak mendiagnosis dan tidak menyebut obat.

String _hhmm(String? t) => (t ?? '').replaceFirst(':', '.');

String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _list(List<String> items) {
  if (items.length <= 1) return items.join();
  return '${items.sublist(0, items.length - 1).join(', ')} dan ${items.last}';
}

String _mealBody(PlanMeal m) {
  final parts = m.components.map((c) => c.name.toLowerCase()).toList();
  final what = parts.isEmpty ? m.title! : '${m.title} (${_list(parts)})';
  return (m.why ?? '').isEmpty ? what : '$what. ${m.why}';
}

/// Kartu pagi untuk satu hari: apa yang dimakan (dengan contoh), olahraga, dan tidur.
JedaCard morningCard(DayPlan plan) {
  final sections = <JedaSection>[];
  final ex = plan.exercise;
  if (ex == null || (ex.minutes == 0 && !ex.blocked)) {
    sections.add(const JedaSection('Olahraga', 'Hari ini tidak ada usulan olahraga. Bergerak ringan tetap baik.'));
  } else if (ex.blocked) {
    sections.add(JedaSection('Olahraga', ex.why));
  } else {
    final at = (ex.time ?? '').isEmpty ? '' : ', sekitar ${_hhmm(ex.time)}';
    sections.add(JedaSection('Olahraga', '${_capital(ex.activity ?? 'bergerak')} ${ex.minutes} menit$at.'));
  }
  for (final m in plan.meals) {
    if (m.done || (m.title ?? '').isEmpty) continue;
    sections.add(JedaSection(_capital(m.label), _mealBody(m)));
  }
  sections.add(JedaSection(
    'Tidur',
    'Target ${plan.sleep.hours.toStringAsFixed(plan.sleep.hours % 1 == 0 ? 0 : 1)} jam: tidur sekitar '
        '${_hhmm(plan.sleep.bedtime)}, bangun ${_hhmm(plan.sleep.wakeTime)}.',
  ));
  return JedaCard(
    kind: 'morning',
    title: 'Rencana hari ini',
    sections: sections,
    actionLabel: 'Buka rencana',
    route: '/plan',
    footnote: 'Usulan untuk membantu kebiasaan harian, bukan resep atau terapi gizi.',
  );
}

const morningGenericCard = JedaCard(
  kind: 'morning',
  title: 'Selamat pagi',
  sections: [
    JedaSection('Hari ini', 'Lihat usulan makan, olahraga, dan jam tidur hari ini di Rencana.'),
  ],
  actionLabel: 'Buka rencana',
  route: '/plan',
);

const eveningGenericCard = JedaCard(
  kind: 'evening',
  title: 'Catat hari ini dulu?',
  sections: [
    JedaSection('Sebelum lanjut', 'Sudah mencatat makan dan olahraga hari ini? Satu kalimat di chat cukup, '
        'misalnya "tadi siang makan nasi padang, sore jalan 20 menit".'),
  ],
  actionLabel: 'Catat sekarang',
  route: '/chat',
);

/// null bila makan dan olahraga hari ini sudah tercatat (tidak ada alasan menahan pengguna).
JedaCard? eveningCard(DayPlan plan, DateTime checkedAt) {
  final missingMeals = [
    for (final m in plan.meals)
      if (!m.done && m.slot != 'snack' && (m.title ?? '').isNotEmpty) m.label,
  ];
  final ex = plan.exercise;
  final exerciseMissing = ex != null && !ex.blocked && ex.minutes > 0 && !ex.done;
  if (missingMeals.isEmpty && !exerciseMissing) return null;
  final sections = <JedaSection>[
    if (missingMeals.isNotEmpty) JedaSection('Makan', 'Belum ada catatan ${_list(missingMeals)}.'),
    if (exerciseMissing) JedaSection('Olahraga', 'Belum ada catatan olahraga hari ini.'),
    const JedaSection('Caranya', 'Satu kalimat di chat cukup, misalnya "tadi siang makan nasi padang, sore jalan 20 menit".'),
  ];
  return JedaCard(
    kind: 'evening',
    title: 'Catat hari ini dulu?',
    sections: sections,
    actionLabel: 'Catat sekarang',
    route: '/chat',
    footnote: 'Diperiksa pukul ${clock(checkedAt.hour * 60 + checkedAt.minute)}. Kalau sudah dicatat lewat WhatsApp, abaikan.',
  );
}

JedaCard nightCard(DayPlan plan) => JedaCard(
      kind: 'night',
      title: 'Waktunya bersiap tidur',
      sections: [
        JedaSection(
          'Tidur',
          'Rencanamu tidur sekitar ${_hhmm(plan.sleep.bedtime)} dan bangun ${_hhmm(plan.sleep.wakeTime)}. '
              'Menyimpan ponsel sekarang membantu tidurmu tidak mundur.',
        ),
      ],
      actionLabel: 'Buka rencana',
      route: '/plan',
    );

JedaCard? otherCard(CheckRecommendation? check) {
  if (check == null || !check.followUp) return null;
  return JedaCard(
    kind: 'other',
    title: 'Sudah sempat cek?',
    sections: [
      JedaSection(check.label, 'Beberapa hari lalu KIRA menyarankan pemeriksaan ini. Kalau belum, pertimbangkan '
          'menjadwalkannya ke puskesmas atau dokter.'),
    ],
    actionLabel: 'Lihat saran cek',
    route: '/check',
  );
}

/// [week] berisi usulan hari-hari berikutnya (urutan tanggal); kartu pagi dibuat untuk semuanya, hari ini dari [today].
JedaPayload buildJedaPayload({
  required DayPlan today,
  List<DayPlan> week = const [],
  CheckRecommendation? check,
  required DateTime now,
}) {
  final morning = <String, JedaCard>{
    for (final p in week) dateKey(p.date): morningCard(p),
    dateKey(today.date): morningCard(today),
  };
  return JedaPayload(
    generatedAt: now,
    morningByDate: morning,
    morningGeneric: morningGenericCard,
    evening: eveningCard(today, now),
    eveningGeneric: eveningGenericCard,
    night: nightCard(today),
    other: otherCard(check),
  );
}
