import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/projection/projection_screen.dart';
import 'package:kira/features/trends/trends_screen.dart';
import 'package:kira/shared/clinical_extras_models.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

Future<void> pumpTrends(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 7000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const TrendsScreen(), api: api));
  await tester.pumpAndSettle();
}

Future<void> pumpProjection(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 5200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const ProjectionScreen(), api: api));
  await tester.pumpAndSettle();
}

RiskPoint pt(int day, int low, int high) => RiskPoint(date: DateTime(2026, 9, day), low: low, high: high);

void main() {
  group('riwayat skor risiko', () {
    testWidgets('tanpa riwayat: penjelasan kapan mulai tercatat', (tester) async {
      await pumpTrends(tester, FakeApi());
      expect(find.byKey(const Key('risk_history_empty')), findsOneWidget);
      expect(find.textContaining('Belum ada riwayat'), findsOneWidget);
    });

    testWidgets('satu hari saja: belum digambar sebagai grafik', (tester) async {
      await pumpTrends(tester, FakeApi()..riskHistory = RiskHistory(points: [pt(1, 9, 18)], boundaries: const [7, 12, 15, 21]));
      expect(find.textContaining('Baru satu hari'), findsOneWidget);
      expect(find.byKey(const Key('chart_risk_history')), findsNothing);
    });

    testWidgets('dua hari atau lebih: grafik pita dan ringkasan kata-kata yang menyebut penyempitan', (tester) async {
      final api = FakeApi()..riskHistory = RiskHistory(points: [pt(1, 6, 20), pt(10, 9, 15)], boundaries: const [7, 12, 15, 21]);
      await pumpTrends(tester, api);
      expect(find.byKey(const Key('chart_risk_history')), findsOneWidget);
      expect(find.textContaining('6-20 → 9-15'), findsOneWidget);
      expect(find.textContaining('menyempit'), findsWidgets);
    });

    testWidgets('rentang tidak menyempit: tidak mengklaim menyempit', (tester) async {
      final api = FakeApi()..riskHistory = RiskHistory(points: [pt(1, 9, 15), pt(10, 8, 18)], boundaries: const [7, 12, 15, 21]);
      await pumpTrends(tester, api);
      expect(find.textContaining('menyempit karena data nyata masuk'), findsNothing);
    });
  });

  group('pola tidur', () {
    testWidgets('data kurang: menjelaskan berapa yang dibutuhkan, tanpa angka perbandingan', (tester) async {
      await pumpTrends(tester, FakeApi()..patterns = const SleepPatterns(shortDays: 2, otherDays: 5));
      expect(find.byKey(const Key('patterns_need_more')), findsOneWidget);
      expect(find.textContaining('Butuh minimal 3 hari'), findsOneWidget);
      expect(find.textContaining('2 hari tidur pendek dan 5 hari lainnya'), findsOneWidget);
    });

    testWidgets('perbandingan tampil dengan selisih bertanda dan catatan bukan sebab pasti', (tester) async {
      final api = FakeApi()
        ..patterns = const SleepPatterns(
          shortDays: 4,
          otherDays: 9,
          needsMoreData: false,
          disclaimer: 'Ini pola dari catatanmu sendiri, bukan sebab pasti.',
          comparisons: [
            PatternComparison(key: 'sugar_g', label: 'Gula dari makan dan minum', unit: 'g', shortAvg: 70, otherAvg: 30, diff: 40, nShort: 4, nOther: 9),
            PatternComparison(key: 'active_minutes', label: 'Menit aktif', unit: 'menit', shortAvg: 10, otherAvg: 25.5, diff: -15.5, nShort: 4, nOther: 9),
          ],
        );
      await pumpTrends(tester, api);
      expect(find.textContaining('kurang dari 6 jam (4 hari) dibanding hari lain (9 hari)'), findsOneWidget);
      expect(find.textContaining('70 vs 30 g  (+40)'), findsOneWidget);
      expect(find.textContaining('10 vs 25,5 menit  (-15,5)'), findsOneWidget);
      expect(find.textContaining('bukan sebab pasti'), findsOneWidget);
      expect(find.textContaining('menyebabkan'), findsNothing);
    });
  });

  group('skenario tersimpan', () {
    Future<void> openProjection(WidgetTester tester, FakeApi api) async {
      await pumpProjection(tester, api);
    }

    testWidgets('simpan hanya aktif setelah ada perubahan dan hasilnya dihitung', (tester) async {
      final api = FakeApi();
      await openProjection(tester, api);
      expect(find.byKey(const Key('save_scenario')), findsNothing); // belum ada skenario dan belum ada perubahan
      await tester.tap(find.byKey(const Key('active_switch')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(find.byKey(const Key('save_scenario')));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('memberi nama lalu menyimpan: kebiasaan dikirim ke server dan muncul di daftar', (tester) async {
      final api = FakeApi();
      await openProjection(tester, api);
      await tester.tap(find.byKey(const Key('active_switch')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save_scenario')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scenario_save_confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Beri nama dulu'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('scenario_name')), 'Jalan pagi');
      await tester.tap(find.byKey(const Key('scenario_save_confirm')));
      await tester.pumpAndSettle();
      expect(api.savedScenarios.single.name, 'Jalan pagi');
      expect(api.savedScenarios.single.change.active30min, isTrue);
      expect(find.text('Jalan pagi'), findsOneWidget);
      expect(find.textContaining('jalan 30 menit sehari'), findsOneWidget);
    });

    testWidgets('skenario yang hasilnya bergeser menyebut nilai saat disimpan dan bahwa datamu berubah', (tester) async {
      final api = FakeApi()
        ..scenarios = [
          const SavedScenario(
            id: 's1', name: 'Kurangi teh', params: {'sweet_drinks_delta_per_day': -1},
            savedBefore: ScoreSpan(9, 18), savedAfter: ScoreSpan(8, 16),
            nowBefore: ScoreSpan(10, 14), nowAfter: ScoreSpan(9, 12),
          ),
        ];
      await openProjection(tester, api);
      expect(find.textContaining('Sekarang: skor 10-14 → 9-12'), findsOneWidget);
      expect(find.textContaining('saat disimpan 9-18 → 8-16; datamu sudah berubah'), findsOneWidget);
      expect(find.textContaining('kurangi 1 minuman manis/hari'), findsOneWidget);
    });

    testWidgets('skenario yang hasilnya tetap tidak menambahkan keterangan berubah', (tester) async {
      final api = FakeApi()
        ..scenarios = [
          const SavedScenario(
            id: 's1', name: 'Sama', params: {'active_30min': true},
            savedBefore: ScoreSpan(9, 18), savedAfter: ScoreSpan(9, 16), nowBefore: ScoreSpan(9, 18), nowAfter: ScoreSpan(9, 16),
          ),
        ];
      await openProjection(tester, api);
      expect(find.textContaining('datamu sudah berubah'), findsNothing);
    });

    testWidgets('ketuk memuat skenario ke pengaturan, ikon sampah menghapus', (tester) async {
      final api = FakeApi()
        ..scenarios = [
          const SavedScenario(
            id: 's1', name: 'Aktif', params: {'active_30min': true, 'sweet_drinks_delta_per_day': 0},
            savedBefore: ScoreSpan(9, 18), savedAfter: ScoreSpan(9, 16), nowBefore: ScoreSpan(9, 18), nowAfter: ScoreSpan(9, 16),
          ),
        ];
      await openProjection(tester, api);
      await tester.tap(find.byKey(const Key('scenario_s1')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('active_switch'))).value, isTrue);
      expect(api.whatIfRequests.single.active30min, isTrue);

      await tester.tap(find.byKey(const Key('delete_scenario_s1')));
      await tester.pumpAndSettle();
      expect(api.deletedScenarios, ['s1']);
      expect(find.byKey(const Key('scenario_s1')), findsNothing);
    });
  });

  test('WhatIfChange dari parameter server', () {
    final c = WhatIfChange(active30min: true, sweetDrinksDeltaPerDay: -2);
    expect(c.toJson()['sweet_drinks_delta_per_day'], -2);
    const s = SavedScenario(
      id: 'x', name: 'n', params: {'weight_delta_kg': -3.5, 'daily_veg_fruit': true},
      savedBefore: ScoreSpan(1, 2), savedAfter: ScoreSpan(1, 2), nowBefore: ScoreSpan(1, 2), nowAfter: ScoreSpan(1, 2),
    );
    expect(s.habits, 'sayur/buah tiap hari, turun 3,5 kg');
    expect(const ScoreSpan(7, 7).text, '7');
  });
}
