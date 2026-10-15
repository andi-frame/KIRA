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
