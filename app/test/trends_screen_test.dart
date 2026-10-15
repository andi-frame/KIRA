import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/trends/trends_screen.dart';
import 'package:kira/shared/insight_models.dart';

import 'support/fakes.dart';

Future<void> pumpTrends(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 4200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const TrendsScreen(), api: api));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menampilkan penanda triase dengan tingkatnya dalam kata, urut dari yang perlu perhatian', (tester) async {
    await pumpTrends(tester, FakeApi()..trends = sampleTrends());
    expect(find.byKey(const Key('triage_card')), findsOneWidget);
    expect(find.text('Perlu perhatian'), findsOneWidget);
    expect(find.text('Pantau'), findsOneWidget);
    expect(find.textContaining('146/94'), findsWidgets);
    expect(find.textContaining('bukan diagnosis'), findsWidgets);
    final first = tester.getTopLeft(find.text('Perlu perhatian')).dy;
    final second = tester.getTopLeft(find.text('Pantau')).dy;
    expect(first, lessThan(second));
  });

  testWidgets('grafik tren tensi dan gula puasa tampil dengan nilai terakhir, kata tren, dan alternatif teks', (tester) async {
    await pumpTrends(tester, FakeApi()..trends = sampleTrends());
    expect(find.byKey(const Key('chart_blood_pressure')), findsOneWidget);
    expect(find.byKey(const Key('chart_fasting_glucose')), findsOneWidget);
    expect(find.textContaining('146/94 mmHg'), findsWidgets);
    expect(find.textContaining('128 mg/dL'), findsWidgets);
    expect(find.text('naik'), findsNWidgets(2));
    // grafik tidak boleh hanya visual: ada ringkasan teks untuk pembaca layar
    final labels = tester.widgetList<Semantics>(find.byType(Semantics)).map((s) => s.properties.label ?? '').join(' | ');
    expect(labels, contains('Tekanan darah'));
    expect(labels, contains('146/94'));
  });

  testWidgets('jenis pemeriksaan yang belum pernah diukur tidak punya grafik kosong', (tester) async {
    await pumpTrends(tester, FakeApi()..trends = sampleTrends());
    expect(find.byKey(const Key('chart_hba1c')), findsNothing);
    expect(find.byKey(const Key('chart_random_glucose')), findsNothing);
  });

  testWidgets('satu pengukuran saja: nilai tampil dengan catatan belum ada tren', (tester) async {
    final data = TrendsData(
      clinical: {
        'hba1c': const ClinicalSeries(
          points: [ClinicalPoint(date: '2026-10-10', source: 'lab', value: 5.9, band: 'prediabetes')],
          references: [RefLine('Prediabetes mulai', 5.7), RefLine('Rentang diabetes mulai', 6.5)],
        ),
      },
      triage: const [],
    );
    await pumpTrends(tester, FakeApi()..trends = data);
    expect(find.textContaining('5,9 %'), findsWidgets);
    expect(find.textContaining('baru satu pengukuran'), findsOneWidget);
  });

  testWidgets('tanpa hasil pemeriksaan: ajakan untuk mengukur, bukan grafik kosong', (tester) async {
    await pumpTrends(tester, FakeApi()..trends = sampleTrends(withClinical: false, triage: const []));
    expect(find.byKey(const Key('clinical_empty')), findsOneWidget);
    expect(find.textContaining('Belum ada hasil pemeriksaan'), findsOneWidget);
    expect(find.byKey(const Key('chart_blood_pressure')), findsNothing);
  });

  testWidgets('grafik kebiasaan harian: gula, tidur, dan aktivitas, dengan jumlah hari tercatat', (tester) async {
    await pumpTrends(tester, FakeApi()..trends = sampleTrends());
    expect(find.byKey(const Key('chart_sugar')), findsOneWidget);
    expect(find.byKey(const Key('chart_sleep')), findsOneWidget);
    expect(find.byKey(const Key('chart_active')), findsOneWidget);
    expect(find.textContaining('2 dari 3 hari tercatat'), findsOneWidget);
    expect(find.textContaining('batas 50 g'), findsWidgets);
  });

  testWidgets('berganti periode memuat ulang data dari server', (tester) async {
    final api = FakeApi()..trends = sampleTrends();
    await pumpTrends(tester, api);
    expect(api.trendsDays, [30]);
    await tester.tap(find.byKey(const Key('period_7')));
    await tester.pumpAndSettle();
    expect(api.trendsDays.last, 7);
  });

  testWidgets('gagal memuat menampilkan pesan ramah dengan tombol coba lagi', (tester) async {
    final api = FakeApi()..trendsError = ApiException('Tidak bisa terhubung ke server.');
    await pumpTrends(tester, api);
    expect(find.textContaining('Tidak bisa terhubung'), findsOneWidget);
    api.trendsError = null;
    api.trends = sampleTrends();
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('triage_card')), findsOneWidget);
  });
}
