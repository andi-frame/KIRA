import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/health/health_source.dart';
import 'package:kira/shared/insight_models.dart';

RawStep step(String src, int day, int hour, int minutes, int count) => RawStep(
      sourceId: src,
      start: DateTime(2026, 10, day, hour),
      end: DateTime(2026, 10, day, hour).add(Duration(minutes: minutes)),
      count: count,
    );

void main() {
  test('langkah ganda dari beberapa aplikasi tidak dihitung dua kali: hanya sumber terbanyak dipakai', () {
    final batch = buildBatch([
      step('ponsel', 14, 7, 10, 1100),
      step('ponsel', 14, 18, 10, 900),
      step('jam', 14, 7, 10, 1000), // merekam jalan yang sama
    ], const []);
    expect(batch.steps.map((s) => s.count), [1100, 900]);
  });

  test('catatan kosong, nol langkah, atau durasi terbalik dibuang', () {
    final batch = buildBatch([
      step('a', 14, 7, 10, 0),
      RawStep(sourceId: 'a', start: DateTime(2026, 10, 14, 9), end: DateTime(2026, 10, 14, 8), count: 50),
      step('a', 14, 10, 5, 400),
    ], const []);
    expect(batch.steps.map((s) => s.count), [400]);
  });

  test('tidur: sumber dengan durasi terpanjang dipakai', () {
    final batch = buildBatch(const [], [
      RawSleep(sourceId: 'jam', start: DateTime(2026, 10, 13, 23), end: DateTime(2026, 10, 14, 6)),
      RawSleep(sourceId: 'ponsel', start: DateTime(2026, 10, 14, 0), end: DateTime(2026, 10, 14, 1)),
    ]);
    expect(batch.sleep, hasLength(1));
    expect(batch.sleep.single.end, DateTime(2026, 10, 14, 6));
  });

  test('pemecahan per beberapa hari berurutan dari yang terlama', () {
    final steps = [for (var d = 1; d <= 7; d++) StepSegmentData(start: DateTime(2026, 10, d, 8), end: DateTime(2026, 10, d, 8, 10), count: 1100)];
    final chunks = chunkByDays(PassiveBatch(steps: steps), daysPerChunk: 3);
    expect(chunks.map((c) => c.steps.length), [3, 3, 1]);
    expect(chunks.first.steps.first.start.day, 1);
    expect(chunks.last.steps.single.start.day, 7);
  });

  test('pemecahan juga dibatasi jumlah segmen dan tidak membuat potongan kosong', () {
    final dense = [for (var i = 0; i < 6; i++) StepSegmentData(start: DateTime(2026, 10, 1 + (i ~/ 3), 8, i), end: DateTime(2026, 10, 1 + (i ~/ 3), 8, i + 1), count: 120)];
    final chunks = chunkByDays(PassiveBatch(steps: dense), maxSegments: 3);
    expect(chunks.map((c) => c.steps.length), [3, 3]);
    expect(chunkByDays(const PassiveBatch()), isEmpty);
  });

  test('tidur dikelompokkan menurut hari bangun', () {
    final batch = PassiveBatch(sleep: [SleepSessionData(start: DateTime(2026, 10, 1, 23), end: DateTime(2026, 10, 2, 6))]);
    final chunks = chunkByDays(batch);
    expect(chunks, hasLength(1));
    expect(chunks.single.sleep, hasLength(1));
  });
}
