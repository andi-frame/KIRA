/// Rencana harian/mingguan dan preferensinya (GET/PUT /plan/...). Usulan dari server; aplikasi hanya menampilkan.
library;

import 'meal_models.dart';

double? _d(Object? v) => v is num ? v.toDouble() : null;

class PlanComponent {
  const PlanComponent({required this.name, this.grams, this.kcal});
  final String name;
  final double? grams;
  final double? kcal;

  factory PlanComponent.fromJson(Map<String, dynamic> j) =>
      PlanComponent(name: j['name'] as String, grams: _d(j['grams']), kcal: _d(j['kcal']));
}

class PlanMeal {
  const PlanMeal({
    required this.slot,
    required this.label,
    this.time,
    this.title,
    this.why,
    this.done = false,
    this.overBudget = false,
    this.components = const [],
    this.totals = const NutrientTotals(),
  });

  final String slot; // breakfast | lunch | snack | dinner
  final String label;
  final String? time;
  final String? title;
  final String? why;
  final bool done;
  final bool overBudget;
  final List<PlanComponent> components;
  final NutrientTotals totals;

  factory PlanMeal.fromJson(Map<String, dynamic> j) => PlanMeal(
        slot: j['slot'] as String,
        label: j['label'] as String,
        time: j['time'] as String?,
        title: j['title'] as String?,
        why: j['why'] as String?,
        done: (j['done'] as bool?) ?? false,
        overBudget: (j['over_budget'] as bool?) ?? false,
        components:
            (j['components'] as List? ?? const []).map((e) => PlanComponent.fromJson(e as Map<String, dynamic>)).toList(),
        totals: j['totals'] == null ? const NutrientTotals() : NutrientTotals.fromJson(j['totals'] as Map<String, dynamic>),
      );
}

class PlanExercise {
  const PlanExercise({
    this.minutes = 0,
    this.activity,
    this.time,
    this.why = '',
    this.strength = false,
    this.blocked = false,
    this.done = false,
    this.doneMinutes = 0,
  });

  final int minutes;
  final String? activity;
  final String? time;
  final String why;
  final bool strength;
  final bool blocked;
  final bool done;
  final double doneMinutes;

  factory PlanExercise.fromJson(Map<String, dynamic> j) => PlanExercise(
        minutes: (j['minutes'] as num?)?.toInt() ?? 0,
        activity: j['activity'] as String?,
        time: j['time'] as String?,
        why: (j['why'] as String?) ?? '',
        strength: (j['strength'] as bool?) ?? false,
        blocked: (j['blocked'] as bool?) ?? false,
        done: (j['done'] as bool?) ?? false,
        doneMinutes: _d(j['done_minutes']) ?? 0,
      );
}

class PlanSleep {
  const PlanSleep({required this.hours, required this.bedtime, required this.wakeTime, this.why = ''});
  final double hours;
  final String bedtime;
  final String wakeTime;
  final String why;

  factory PlanSleep.fromJson(Map<String, dynamic> j) => PlanSleep(
        hours: _d(j['hours']) ?? 8,
        bedtime: j['bedtime'] as String,
        wakeTime: j['wake_time'] as String,
        why: (j['why'] as String?) ?? '',
      );
}

class DayPlan {
  const DayPlan({
    required this.date,
    required this.kcalTarget,
    required this.energySource,
    required this.meals,
    required this.sleep,
    this.exercise,
    this.adapted,
    this.disclaimer = '',
  });

  final DateTime date;
  final double kcalTarget;
  final String energySource;
  final List<PlanMeal> meals;
  final PlanExercise? exercise;
  final PlanSleep sleep;
  final String? adapted;
  final String disclaimer;

  factory DayPlan.fromJson(Map<String, dynamic> j) {
    final energy = j['energy'] as Map<String, dynamic>;
    return DayPlan(
      date: DateTime.parse(j['date'] as String),
      kcalTarget: _d(energy['kcal']) ?? 0,
      energySource: (energy['source'] as String?) ?? '',
      meals: (j['meals'] as List).map((e) => PlanMeal.fromJson(e as Map<String, dynamic>)).toList(),
      exercise: j['exercise'] == null ? null : PlanExercise.fromJson(j['exercise'] as Map<String, dynamic>),
      sleep: PlanSleep.fromJson(j['sleep'] as Map<String, dynamic>),
      adapted: j['adapted'] as String?,
      disclaimer: (j['disclaimer'] as String?) ?? '',
    );
  }
}

class PlanPreferences {
  const PlanPreferences({
    this.wakeTime = '06:00',
    this.mealTimes = const {'breakfast': '06:30', 'lunch': '12:00', 'snack': '15:30', 'dinner': '18:30'},
    this.exerciseTime = '17:00',
    this.exerciseDays = const [0, 1, 2, 3, 4],
    this.exerciseKinds = const ['jalan cepat'],
    this.strengthDays = 0,
    this.goal = 'jaga',
    this.whatsapp = false,
    this.reminders = const {'meals': true, 'exercise': true, 'sleep': true, 'weekly_plan': true},
    this.quietStart = '21:30',
    this.quietEnd = '06:00',
  });

  final String wakeTime;
  final Map<String, String> mealTimes;
  final String exerciseTime;
  final List<int> exerciseDays; // 0 = Senin
  final List<String> exerciseKinds;
  final int strengthDays;
  final String goal; // jaga | turun_berat | aktif
  final bool whatsapp;
  final Map<String, bool> reminders;
  final String quietStart, quietEnd;

  PlanPreferences copyWith({
    String? wakeTime,
    Map<String, String>? mealTimes,
    String? exerciseTime,
    List<int>? exerciseDays,
    List<String>? exerciseKinds,
    int? strengthDays,
    String? goal,
    bool? whatsapp,
    Map<String, bool>? reminders,
  }) =>
      PlanPreferences(
        wakeTime: wakeTime ?? this.wakeTime,
        mealTimes: mealTimes ?? this.mealTimes,
        exerciseTime: exerciseTime ?? this.exerciseTime,
        exerciseDays: exerciseDays ?? this.exerciseDays,
        exerciseKinds: exerciseKinds ?? this.exerciseKinds,
        strengthDays: strengthDays ?? this.strengthDays,
        goal: goal ?? this.goal,
        whatsapp: whatsapp ?? this.whatsapp,
        reminders: reminders ?? this.reminders,
        quietStart: quietStart,
        quietEnd: quietEnd,
      );

  factory PlanPreferences.fromJson(Map<String, dynamic> j) {
    final quiet = j['quiet_hours'] as Map<String, dynamic>? ?? const {};
    return PlanPreferences(
      wakeTime: j['wake_time'] as String,
      mealTimes: Map<String, String>.from(j['meal_times'] as Map),
      exerciseTime: j['exercise_time'] as String,
      exerciseDays: (j['exercise_days'] as List).map((e) => (e as num).toInt()).toList(),
      exerciseKinds: (j['exercise_kinds'] as List).cast<String>(),
      strengthDays: (j['strength_days'] as num).toInt(),
      goal: j['goal'] as String,
      whatsapp: ((j['channels'] as Map?)?['whatsapp'] as bool?) ?? false,
      reminders: Map<String, bool>.from(j['reminders'] as Map),
      quietStart: (quiet['start'] as String?) ?? '21:30',
      quietEnd: (quiet['end'] as String?) ?? '06:00',
    );
  }

  Map<String, dynamic> toJson() => {
        'wake_time': wakeTime,
        'meal_times': mealTimes,
        'exercise_time': exerciseTime,
        'exercise_days': exerciseDays,
        'exercise_kinds': exerciseKinds,
        'strength_days': strengthDays,
        'goal': goal,
        'channels': {'app': true, 'whatsapp': whatsapp},
        'reminders': reminders,
        'quiet_hours': {'start': quietStart, 'end': quietEnd},
      };
}
