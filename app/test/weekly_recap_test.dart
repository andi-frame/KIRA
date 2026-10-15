import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/projection/projection_screen.dart';
import 'package:kira/shared/insight_models.dart';

import 'support/fakes.dart';

Future<void> pumpProjection(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const ProjectionScreen(), api: api));
  await tester.pumpAndSettle();
}

WeeklyRecap recap({Map<String, MetricChange>? changes}) => WeeklyRecap(
      start: '2026-10-05',
      end: '2026-10-11',
      text: 'Minggu 5 Okt sampai 11 Okt: tercatat 6 hari',
      daysLogged: 6,
      sweetDrinksPerDay: 1.2,
      sugarGPerDay: 41.5,
      activeMinutesPerDay: 25,
      sleepHoursAvg: 5.5,
      changes: changes,
    );

void main() {
  testWidgets('rekap minggu lalu menampilkan angka dan arah perubahan dengan kata, bukan warna saja', (tester) async {
    final api = FakeApi()
      ..weeklyRecap = recap(changes: {
        'sweet_drinks_per_day': const MetricChange(delta: -0.8, trend: 'better'),
        'sugar_g_per_day': const MetricChange(delta: 6.0, trend: 'worse'),
        'active_minutes_per_day': const MetricChange(delta: 0.5, trend: 'same'),
        'sleep_hours_avg': const MetricChange(delta: 1.0),
      });
    await pumpProjection(tester, api);

    expect(find.byKey(const Key('weekly_recap_card')), findsOneWidget);
    expect(find.text('Rekap minggu lalu'), findsOneWidget);
    expect(find.textContaining('5 Okt'), findsWidgets);
    expect(find.textContaining('1,2'), findsWidgets); // desimal koma
    expect(find.textContaining('turun 0,8'), findsOneWidget);
    expect(find.textContaining('naik 6'), findsOneWidget);
    expect(find.textContaining('hampir sama'), findsOneWidget);
    expect(find.textContaining('menakutkan'), findsNothing);
  });

  testWidgets('tanpa minggu pembanding, rekap tetap tampil tanpa perubahan', (tester) async {
    await pumpProjection(tester, FakeApi()..weeklyRecap = recap());
    expect(find.byKey(const Key('weekly_recap_card')), findsOneWidget);
    expect(find.textContaining('Belum ada minggu pembanding'), findsOneWidget);
  });

  testWidgets('belum ada rekap: kartu tidak muncul dan proyeksi tetap utuh', (tester) async {
    await pumpProjection(tester, FakeApi());
    expect(find.byKey(const Key('weekly_recap_card')), findsNothing);
    expect(find.byKey(const Key('risk_chart')), findsOneWidget);
  });

  testWidgets('gagal memuat rekap tidak merusak layar proyeksi', (tester) async {
    await pumpProjection(tester, FakeApi()..weeklyError = ApiException('gagal'));
    expect(find.byKey(const Key('weekly_recap_card')), findsNothing);
    expect(find.byKey(const Key('risk_chart')), findsOneWidget);
  });
}
