/// Satu titik riwayat skor FINDRISC (rentang karena data profil/hasil cek bisa belum lengkap).
class RiskPoint {
  const RiskPoint({required this.date, required this.low, required this.high});
  final DateTime date;
  final int low, high;

  factory RiskPoint.fromJson(Map<String, dynamic> j) => RiskPoint(
        date: DateTime.parse(j['date'] as String),
        low: (j['score_low'] as num).toInt(),
        high: (j['score_high'] as num).toInt(),
      );
}

class RiskHistory {
  const RiskHistory({this.points = const [], this.boundaries = const []});
  final List<RiskPoint> points;

  /// Skor awal tiap kategori di atas yang terendah (7, 12, 15, 21), untuk garis batas di grafik.
  final List<int> boundaries;

  factory RiskHistory.fromJson(Map<String, dynamic> j) => RiskHistory(
        points: (j['points'] as List).map((e) => RiskPoint.fromJson(e as Map<String, dynamic>)).toList(),
        boundaries: [
          for (final c in (j['categories'] as List).skip(1)) ((c as Map<String, dynamic>)['min'] as num).toInt(),
        ],
      );
}

class PatternComparison {
  const PatternComparison({
    required this.key,
    required this.label,
    required this.unit,
    required this.shortAvg,
    required this.otherAvg,
    required this.diff,
    required this.nShort,
    required this.nOther,
  });
  final String key, label, unit;
  final double shortAvg, otherAvg, diff;
  final int nShort, nOther;

  factory PatternComparison.fromJson(Map<String, dynamic> j) => PatternComparison(
        key: j['key'] as String,
        label: j['label'] as String,
        unit: j['unit'] as String,
        shortAvg: (j['short_avg'] as num).toDouble(),
        otherAvg: (j['other_avg'] as num).toDouble(),
        diff: (j['diff'] as num).toDouble(),
        nShort: (j['n_short'] as num).toInt(),
        nOther: (j['n_other'] as num).toInt(),
      );
}

/// Pola tidur pendek vs hari lain dari catatan sendiri. Deskriptif, bukan sebab-akibat.
class SleepPatterns {
  const SleepPatterns({
    this.thresholdHours = 6,
    this.shortDays = 0,
    this.otherDays = 0,
    this.minPerGroup = 3,
    this.needsMoreData = true,
    this.comparisons = const [],
    this.disclaimer = '',
  });
  final double thresholdHours;
  final int shortDays, otherDays, minPerGroup;
  final bool needsMoreData;
  final List<PatternComparison> comparisons;
  final String disclaimer;

  factory SleepPatterns.fromJson(Map<String, dynamic> j) {
    final s = j['sleep'] as Map<String, dynamic>;
    return SleepPatterns(
      thresholdHours: (s['threshold_hours'] as num).toDouble(),
      shortDays: (s['short_days'] as num).toInt(),
      otherDays: (s['other_days'] as num).toInt(),
      minPerGroup: (s['min_per_group'] as num).toInt(),
      needsMoreData: s['needs_more_data'] as bool? ?? true,
      comparisons: (s['comparisons'] as List).map((e) => PatternComparison.fromJson(e as Map<String, dynamic>)).toList(),
      disclaimer: j['disclaimer'] as String? ?? '',
    );
  }
}

class ScoreSpan {
  const ScoreSpan(this.low, this.high);
  final int low, high;

  factory ScoreSpan.fromJson(Map<String, dynamic> j) => ScoreSpan((j['low'] as num).toInt(), (j['high'] as num).toInt());

  String get text => low == high ? '$low' : '$low-$high';
}

/// Skenario "bagaimana kalau" yang disimpan: hasil saat disimpan vs dihitung ulang dengan data terkini.
class SavedScenario {
  const SavedScenario({
    required this.id,
    required this.name,
    required this.params,
    required this.savedBefore,
    required this.savedAfter,
    required this.nowBefore,
    required this.nowAfter,
  });
  final String id, name;
  final Map<String, dynamic> params;
  final ScoreSpan savedBefore, savedAfter, nowBefore, nowAfter;

  /// Berubah sejak disimpan: data barumu menggeser hasilnya.
  bool get changed => savedAfter.text != nowAfter.text || savedBefore.text != nowBefore.text;

  /// Ringkasan kebiasaan di skenario, dalam bahasa sehari-hari.
  String get habits {
    final parts = <String>[
      if (params['active_30min'] == true) 'jalan 30 menit sehari',
      if (params['daily_veg_fruit'] == true) 'sayur/buah tiap hari',
      if ((params['weight_delta_kg'] as num?) != null && (params['weight_delta_kg'] as num) != 0)
        '${(params['weight_delta_kg'] as num) < 0 ? 'turun' : 'naik'} ${(params['weight_delta_kg'] as num).abs().toStringAsFixed(1).replaceAll('.', ',')} kg',
      if ((params['sweet_drinks_delta_per_day'] as num?) != null && (params['sweet_drinks_delta_per_day'] as num) != 0)
        '${(params['sweet_drinks_delta_per_day'] as num) < 0 ? 'kurangi' : 'tambah'} ${(params['sweet_drinks_delta_per_day'] as num).abs().toStringAsFixed(0)} minuman manis/hari',
    ];
    return parts.join(', ');
  }

  factory SavedScenario.fromJson(Map<String, dynamic> j) {
    final saved = j['saved'] as Map<String, dynamic>;
    final now = j['now'] as Map<String, dynamic>;
    return SavedScenario(
      id: j['id'] as String,
      name: j['name'] as String,
      params: Map<String, dynamic>.from(j['params'] as Map),
      savedBefore: ScoreSpan.fromJson(saved['before'] as Map<String, dynamic>),
      savedAfter: ScoreSpan.fromJson(saved['after'] as Map<String, dynamic>),
      nowBefore: ScoreSpan.fromJson(now['before'] as Map<String, dynamic>),
      nowAfter: ScoreSpan.fromJson(now['after'] as Map<String, dynamic>),
    );
  }
}
