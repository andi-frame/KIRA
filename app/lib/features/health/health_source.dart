import '../../shared/insight_models.dart';

enum HealthAvailability { available, notInstalled, unsupported }

/// Sumber data pasif perangkat (Health Connect di Android). Dipisah dari plugin agar logika bisa diuji tanpa perangkat.
abstract class HealthSource {
  Future<HealthAvailability> availability();

  /// Minta izin baca langkah dan tidur. false bila pengguna menolak.
  Future<bool> requestAccess();

  Future<({List<RawStep> steps, List<RawSleep> sleep})> read({int days = 14});
}

class RawStep {
  const RawStep({required this.sourceId, required this.start, required this.end, required this.count});
  final String sourceId;
  final DateTime start, end;
  final int count;
}

class RawSleep {
  const RawSleep({required this.sourceId, required this.start, required this.end});
  final String sourceId;
  final DateTime start, end;
}

/// Beberapa aplikasi (ponsel dan jam tangan) bisa menulis langkah yang sama ke Health Connect. Agar tidak terhitung dua
/// kali, hanya sumber dengan catatan terbanyak yang dipakai.
String? _dominant(Map<String, num> totals) {
  if (totals.isEmpty) return null;
  final ids = totals.keys.toList()..sort();
  return ids.reduce((a, b) => totals[b]! > totals[a]! ? b : a);
}

PassiveBatch buildBatch(List<RawStep> steps, List<RawSleep> sleep) {
  final stepTotals = <String, num>{};
  for (final s in steps) {
    stepTotals[s.sourceId] = (stepTotals[s.sourceId] ?? 0) + s.count;
  }
  final sleepTotals = <String, num>{};
  for (final s in sleep) {
    sleepTotals[s.sourceId] = (sleepTotals[s.sourceId] ?? 0) + s.end.difference(s.start).inMinutes;
  }
  final stepSource = _dominant(stepTotals), sleepSource = _dominant(sleepTotals);
  return PassiveBatch(
    steps: [
      for (final s in steps)
        if (s.sourceId == stepSource && s.count > 0 && s.end.isAfter(s.start))
          StepSegmentData(start: s.start, end: s.end, count: s.count),
    ],
    sleep: [
      for (final s in sleep)
        if (s.sourceId == sleepSource && s.end.isAfter(s.start)) SleepSessionData(start: s.start, end: s.end),
    ],
  );
}

DateTime _day(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Memecah kiriman menjadi potongan beberapa hari (dari yang terlama), supaya tiap permintaan tidak terlalu besar.
/// Server hanya mengganti hari yang ada di kiriman, jadi urutan dan pemotongan aman.
List<PassiveBatch> chunkByDays(PassiveBatch batch, {int daysPerChunk = 3, int maxSegments = 15000}) {
  final stepsByDay = <DateTime, List<StepSegmentData>>{};
  for (final s in batch.steps) {
    stepsByDay.putIfAbsent(_day(s.start), () => []).add(s);
  }
  final sleepByDay = <DateTime, List<SleepSessionData>>{};
  for (final s in batch.sleep) {
    sleepByDay.putIfAbsent(_day(s.end), () => []).add(s);
  }
  final days = {...stepsByDay.keys, ...sleepByDay.keys}.toList()..sort();
  final chunks = <PassiveBatch>[];
  var steps = <StepSegmentData>[], sleep = <SleepSessionData>[];
  var daysInChunk = 0;
  void flush() {
    if (steps.isNotEmpty || sleep.isNotEmpty) chunks.add(PassiveBatch(steps: steps, sleep: sleep));
    steps = [];
    sleep = [];
    daysInChunk = 0;
  }

  for (final d in days) {
    final daySteps = stepsByDay[d] ?? const <StepSegmentData>[];
    if (daysInChunk >= daysPerChunk || steps.length + daySteps.length > maxSegments) flush();
    steps.addAll(daySteps);
    sleep.addAll(sleepByDay[d] ?? const []);
    daysInChunk++;
  }
  flush();
  return chunks;
}
