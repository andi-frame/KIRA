/// Isi Beranda dari GET /dashboard (angka dari server; aplikasi hanya menampilkan).
library;

import 'meal_models.dart';

double? _d(Object? v) => v is num ? v.toDouble() : null;

class TodayStatus {
  const TodayStatus({
    this.nutrition = const NutrientTotals(),
    this.limits = const DailyLimits(),
    this.kcalTarget,
    this.activityMinutes = 0,
    this.activityTarget = 30,
    this.sleepHours,
    this.sleepTargetHours = 7,
    this.sleepBedtime,
    this.mealsLogged = 0,
  });

  final NutrientTotals nutrition;
  final DailyLimits limits;
  final double? kcalTarget;
  final double activityMinutes;
  final double activityTarget;
  final double? sleepHours;
  final double sleepTargetHours;
  final String? sleepBedtime;
  final int mealsLogged;

  factory TodayStatus.fromJson(Map<String, dynamic> j) {
    final n = j['nutrition'] as Map<String, dynamic>;
    final sleep = j['sleep_target'] as Map<String, dynamic>? ?? const {};
    return TodayStatus(
      nutrition: NutrientTotals.fromJson(n),
      limits: DailyLimits.fromJson(n['limits'] as Map<String, dynamic>),
      kcalTarget: _d(n['kcal_target']),
      activityMinutes: _d(j['activity_minutes']) ?? 0,
      activityTarget: _d(j['activity_target_today']) ?? 30,
      sleepHours: _d(j['sleep_hours_last_night']),
      sleepTargetHours: _d(sleep['hours']) ?? 7,
      sleepBedtime: sleep['bedtime'] as String?,
      mealsLogged: (j['meals_logged'] as int?) ?? 0,
    );
  }
}

/// Penanda kebiasaan/hasil cek. level: perhatian | pantau | baik | info.
class HabitSignal {
  const HabitSignal({required this.key, required this.level, required this.title, required this.detail, required this.source});
  final String key;
  final String level;
  final String title;
  final String detail;
  final String source;

  factory HabitSignal.fromJson(Map<String, dynamic> j) => HabitSignal(
        key: j['key'] as String,
        level: j['level'] as String,
        title: j['title'] as String,
        detail: j['detail'] as String,
        source: j['source'] as String,
      );
}

/// Satu langkah paling berguna sekarang. kind: log_meal | measure_bp | check | exercise | sleep.
class NextAction {
  const NextAction({required this.kind, required this.text});
  final String kind;
  final String text;

  factory NextAction.fromJson(Map<String, dynamic> j) => NextAction(kind: j['kind'] as String, text: j['text'] as String);
}

class DashboardData {
  const DashboardData({
    required this.today,
    required this.nextAction,
    this.signals = const [],
    this.dataQuality = 'cukup',
    this.loggedDays = 0,
    this.planToday,
  });

  final TodayStatus today;
  final NextAction nextAction;
  final List<HabitSignal> signals;
  final String dataQuality; // cukup | kurang
  final int loggedDays;
  final Map<String, dynamic>? planToday; // Fase 4

  bool get enoughData => dataQuality == 'cukup';

  factory DashboardData.fromJson(Map<String, dynamic> j) => DashboardData(
        today: TodayStatus.fromJson(j['today'] as Map<String, dynamic>),
        nextAction: NextAction.fromJson(j['next_best_action'] as Map<String, dynamic>),
        signals: (j['signals'] as List? ?? const []).map((e) => HabitSignal.fromJson(e as Map<String, dynamic>)).toList(),
        dataQuality: (j['data_quality'] as String?) ?? 'cukup',
        loggedDays: (j['logged_days'] as int?) ?? 0,
        planToday: j['plan_today'] as Map<String, dynamic>?,
      );
}
