// Rekap mingguan dan data pasif perangkat (langkah, tidur).

class MetricChange {
  const MetricChange({required this.delta, this.trend});
  final double delta;

  /// better | worse | same, atau null bila tidak dinilai (mis. jam tidur).
  final String? trend;
}

class WeeklyRecap {
  const WeeklyRecap({
    required this.start,
    required this.end,
    required this.text,
    required this.daysLogged,
    this.sweetDrinksPerDay,
    this.sugarGPerDay,
    this.activeMinutesPerDay,
    this.sleepHoursAvg,
    this.changes,
  });

  final String start, end, text;
  final int daysLogged;
  final double? sweetDrinksPerDay, sugarGPerDay, activeMinutesPerDay, sleepHoursAvg;

  /// null bila tidak ada minggu pembanding.
  final Map<String, MetricChange>? changes;

  factory WeeklyRecap.fromJson(Map<String, dynamic> j) {
    final m = j['metrics'] as Map<String, dynamic>;
    double? d(String k) => (m[k] as num?)?.toDouble();
    final raw = j['changes'] as Map<String, dynamic>?;
    return WeeklyRecap(
      start: j['start'] as String,
      end: j['end'] as String,
      text: j['text'] as String,
      daysLogged: (m['days_logged'] as num).toInt(),
      sweetDrinksPerDay: d('sweet_drinks_per_day'),
      sugarGPerDay: d('sugar_g_per_day'),
      activeMinutesPerDay: d('active_minutes_per_day'),
      sleepHoursAvg: d('sleep_hours_avg'),
      changes: raw == null
          ? null
          : {
              for (final e in raw.entries)
                if (e.value != null)
                  e.key: MetricChange(
                    delta: ((e.value as Map)['delta'] as num).toDouble(),
                    trend: (e.value as Map)['trend'] as String?,
                  ),
            },
    );
  }
}

/// Segmen langkah dari perangkat (mis. Health Connect).
class StepSegmentData {
  const StepSegmentData({required this.start, required this.end, required this.count});
  final DateTime start, end;
  final int count;

  Map<String, dynamic> toJson() => {'start': start.toIso8601String(), 'end': end.toIso8601String(), 'count': count};
}

class SleepSessionData {
  const SleepSessionData({required this.start, required this.end});
  final DateTime start, end;

  Map<String, dynamic> toJson() => {'start': start.toIso8601String(), 'end': end.toIso8601String()};
}

class PassiveBatch {
  const PassiveBatch({this.steps = const [], this.sleep = const []});
  final List<StepSegmentData> steps;
  final List<SleepSessionData> sleep;

  bool get isEmpty => steps.isEmpty && sleep.isEmpty;

  Map<String, dynamic> toJson() => {
        'steps': steps.map((e) => e.toJson()).toList(),
        'sleep': sleep.map((e) => e.toJson()).toList(),
      };
}

class PassiveSyncResult {
  const PassiveSyncResult({required this.activityDays, required this.sleepNights});
  final int activityDays, sleepNights;

  factory PassiveSyncResult.fromJson(Map<String, dynamic> j) => PassiveSyncResult(
        activityDays: (j['activity_days'] as num).toInt(),
        sleepNights: (j['sleep_nights'] as num).toInt(),
      );
}

// ---- Tren dan penanda triase ----

class TriageFlag {
  const TriageFlag({required this.level, required this.kind, required this.text});

  /// perhatian | pantau | info
  final String level, kind, text;

  factory TriageFlag.fromJson(Map<String, dynamic> j) =>
      TriageFlag(level: j['level'] as String, kind: j['kind'] as String, text: j['text'] as String);
}

class ClinicalPoint {
  const ClinicalPoint({required this.date, required this.source, this.sys, this.dia, this.value, this.band});

  final String date, source;
  final int? sys, dia;
  final double? value;

  /// Kategori tekanan darah (normal | prehypertension | hypertension) atau rentang gula (normal | prediabetes | diabetes_range).
  final String? band;

  DateTime get day => DateTime.parse(date);

  factory ClinicalPoint.fromJson(Map<String, dynamic> j) => ClinicalPoint(
        date: j['date'] as String,
        source: j['source'] as String? ?? '',
        sys: (j['sys'] as num?)?.toInt(),
        dia: (j['dia'] as num?)?.toInt(),
        value: (j['value'] as num?)?.toDouble(),
        band: (j['category'] ?? j['range']) as String?,
      );
}

class RefLine {
  const RefLine(this.label, this.value);
  final String label;
  final double value;
}

class ClinicalSeries {
  const ClinicalSeries({this.points = const [], this.trend, this.references = const []});
  final List<ClinicalPoint> points;

  /// naik | turun | stabil; null bila kurang dari dua pengukuran.
  final String? trend;
  final List<RefLine> references;

  ClinicalPoint? get latest => points.isEmpty ? null : points.last;

  factory ClinicalSeries.fromJson(Map<String, dynamic> j) => ClinicalSeries(
        points: (j['points'] as List).map((e) => ClinicalPoint.fromJson(e as Map<String, dynamic>)).toList(),
        trend: j['trend'] as String?,
        references: (j['references'] as List)
            .map((e) => RefLine(e['label'] as String, (e['value'] as num).toDouble()))
            .toList(),
      );
}

class DailyPoint {
  const DailyPoint({required this.date, required this.logged, this.sugarG, this.sleepHours, this.activeMinutes, this.kcal});
  final String date;
  final bool logged;
  final double? sugarG, sleepHours, activeMinutes, kcal;

  factory DailyPoint.fromJson(Map<String, dynamic> j) => DailyPoint(
        date: j['date'] as String,
        logged: j['logged'] as bool,
        sugarG: (j['sugar_g'] as num?)?.toDouble(),
        sleepHours: (j['sleep_hours'] as num?)?.toDouble(),
        activeMinutes: (j['active_minutes'] as num?)?.toDouble(),
      );
}

class TrendsData {
  const TrendsData({
    this.periodDays = 30,
    this.clinical = const {},
    this.daily = const [],
    this.sugarLimitG = 50,
    this.activeTargetMin = 30,
    this.triage = const [],
  });

  final int periodDays;
  final Map<String, ClinicalSeries> clinical;
  final List<DailyPoint> daily;
  final double sugarLimitG, activeTargetMin;
  final List<TriageFlag> triage;

  ClinicalSeries series(String kind) => clinical[kind] ?? const ClinicalSeries();
  bool get hasAnyClinical => clinical.values.any((s) => s.points.isNotEmpty);
  int get daysLogged => daily.where((d) => d.logged).length;

  factory TrendsData.fromJson(Map<String, dynamic> j) => TrendsData(
        periodDays: (j['period_days'] as num).toInt(),
        clinical: {
          for (final e in (j['clinical'] as Map<String, dynamic>).entries)
            e.key: ClinicalSeries.fromJson(e.value as Map<String, dynamic>),
        },
        daily: (j['daily'] as List).map((e) => DailyPoint.fromJson(e as Map<String, dynamic>)).toList(),
        sugarLimitG: ((j['references'] as Map)['sugar_g'] as num).toDouble(),
        activeTargetMin: ((j['references'] as Map)['active_minutes'] as num).toDouble(),
        triage: (j['triage'] as List).map((e) => TriageFlag.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
