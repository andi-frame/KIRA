class GoalKind {
  const GoalKind({
    required this.kind,
    required this.label,
    required this.unit,
    required this.isMax,
    required this.defaultTarget,
    required this.min,
    required this.max,
  });
  final String kind, label, unit;
  final bool isMax; // batas atas (jangan lewati) vs capaian minimum
  final double defaultTarget, min, max;

  factory GoalKind.fromJson(Map<String, dynamic> j) => GoalKind(
        kind: j['kind'] as String,
        label: j['label'] as String,
        unit: j['unit'] as String,
        isMax: j['direction'] == 'max',
        defaultTarget: (j['default'] as num).toDouble(),
        min: (j['min'] as num).toDouble(),
        max: (j['max'] as num).toDouble(),
      );
}

class WeekResult {
  const WeekResult({required this.weekStart, this.met, this.current});
  final DateTime weekStart;
  final bool? met; // null = minggu itu tidak ada catatan (bukan gagal)
  final double? current;

  factory WeekResult.fromJson(Map<String, dynamic> j) => WeekResult(
        weekStart: DateTime.parse(j['week_start'] as String),
        met: j['met'] as bool?,
        current: (j['current'] as num?)?.toDouble(),
      );
}

class Goal {
  const Goal({
    required this.id,
    required this.kind,
    required this.label,
    required this.unit,
    required this.current,
    required this.target,
    required this.isMax,
    required this.met,
    required this.fraction,
    required this.remaining,
    required this.history,
    required this.metWeeks,
    required this.weeksWithData,
  });
  final String id, kind, label, unit;
  final double current, target, fraction, remaining;
  final bool isMax, met;
  final List<WeekResult> history;
  final int metWeeks, weeksWithData;

  /// Satu kalimat kemajuan, dengan kata (bukan hanya bilah/warna): "70 dari 150 menit" atau "melewati batas".
  String get progressText {
    String n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
    if (isMax) {
      return met ? '${n(current)} dari batas ${n(target)} $unit' : '${n(current)} $unit, melewati batas ${n(target)}';
    }
    return met ? 'Tercapai: ${n(current)} dari ${n(target)} $unit' : '${n(current)} dari ${n(target)} $unit';
  }

  factory Goal.fromJson(Map<String, dynamic> j) {
    final p = j['progress'] as Map<String, dynamic>;
    return Goal(
      id: j['id'] as String,
      kind: j['kind'] as String,
      label: j['label'] as String,
      unit: j['unit'] as String,
      current: (p['current'] as num).toDouble(),
      target: (p['target'] as num).toDouble(),
      isMax: p['direction'] == 'max',
      met: p['met'] as bool,
      fraction: (p['fraction'] as num).toDouble(),
      remaining: (p['remaining'] as num).toDouble(),
      history: (j['history'] as List).map((e) => WeekResult.fromJson(e as Map<String, dynamic>)).toList(),
      metWeeks: (j['met_weeks'] as num).toInt(),
      weeksWithData: (j['weeks_with_data'] as num).toInt(),
    );
  }
}

class GoalsData {
  const GoalsData({this.goals = const [], this.kinds = const [], this.daysLeft = 0});
  final List<Goal> goals;
  final List<GoalKind> kinds;
  final int daysLeft;

  /// Jenis yang belum punya target (satu target per jenis).
  List<GoalKind> get available => [for (final k in kinds) if (!goals.any((g) => g.kind == k.kind)) k];

  factory GoalsData.fromJson(Map<String, dynamic> j) => GoalsData(
        goals: (j['goals'] as List).map((e) => Goal.fromJson(e as Map<String, dynamic>)).toList(),
        kinds: (j['kinds'] as List).map((e) => GoalKind.fromJson(e as Map<String, dynamic>)).toList(),
        daysLeft: ((j['week'] as Map<String, dynamic>)['days_left'] as num).toInt(),
      );
}
