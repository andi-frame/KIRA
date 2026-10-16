import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/features/home/home_screen.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

const _data = DashboardData(
  today: TodayStatus(
    nutrition: NutrientTotals(kcal: 1240, sugarG: 58, sodiumMg: 1400, fatG: 40),
    activityMinutes: 20,
    sleepHours: 5.5,
    mealsLogged: 2,
  ),
  nextAction: NextAction(kind: 'exercise', text: 'Sisa 10 menit bergerak hari ini. Jalan cepat sore ini sudah cukup.'),
  dataQuality: 'cukup',
  loggedDays: 5,
  signals: [
    HabitSignal(key: 'sleep', level: 'perhatian', title: 'Sering tidur kurang dari 6 jam',
        detail: '3 dari 5 malam tidur kurang dari 6 jam.', source: 'AASM/SRS (Watson dkk. 2015)'),
    HabitSignal(key: 'sodium_mg', level: 'baik', title: 'Natrium (garam) masih sesuai batas',
        detail: 'Natrium berada di bawah 2.000 mg.', source: 'Permenkes 30/2013'),
  ],
);

Future<FakeApi> _pump(WidgetTester tester, {DashboardData data = _data, DateTime? now}) async {
  final api = FakeApi()..dashboard = data;
  await tester.pumpWidget(testApp(
    const HomeScreen(),
    api: api,
    overrides: [clockProvider.overrideWithValue(() => now ?? DateTime(2026, 10, 16, 15))],
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('Beranda: langkah berikutnya, kondisi hari ini dengan kata, lalu proyeksi tetap ada', (tester) async {
    await _pump(tester);

    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Selamat sore'), findsOneWidget);
    expect(find.text('Sisa 10 menit bergerak hari ini. Jalan cepat sore ini sudah cukup.'), findsOneWidget);
    expect(find.byKey(const Key('next_action_button')), findsNothing); // olahraga: tidak ada layar tujuan
    expect(find.text('1.240 kkal'), findsOneWidget);
    expect(find.text('melewati batas 8 g'), findsOneWidget); // gula 58 dari 50
    expect(find.text('20 dari 30 menit, sisa 10 menit'), findsOneWidget);
    expect(find.text('5,5 jam, kurang 1,5 jam dari target'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('risk_headline')), 300);
    expect(find.byKey(const Key('risk_headline')), findsOneWidget); // isi tab "10 Tahun" pindah ke sini
  });

  testWidgets('sinyal urut dengan tingkat ditulis dan sumber saat dibuka', (tester) async {
    await _pump(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('signal_sleep')), 200);
    expect(find.text('Perhatian'), findsOneWidget);
    expect(find.text('Baik'), findsOneWidget);
    expect(find.textContaining('5 hari tercatat'), findsOneWidget);

    await tester.tap(find.text('Sering tidur kurang dari 6 jam'));
    await tester.pumpAndSettle();
    expect(find.text('Sumber: AASM/SRS (Watson dkk. 2015)'), findsOneWidget);
  });

  testWidgets('data kurang: tidak menyimpulkan kebiasaan', (tester) async {
    await _pump(tester, data: const DashboardData(
      today: TodayStatus(),
      nextAction: NextAction(kind: 'log_meal', text: 'Belum ada catatan sarapan. Ceritakan di Ngobrol, satu kalimat cukup.'),
      dataQuality: 'kurang',
      signals: [HabitSignal(key: 'data', level: 'info', title: 'Catatan minggu ini masih sedikit', detail: '-', source: '-')],
    ), now: DateTime(2026, 10, 16, 8));
    expect(find.text('Selamat pagi'), findsOneWidget);
    expect(find.byKey(const Key('next_action_button')), findsOneWidget); // catat makan -> Ngobrol
    expect(find.text('Belum ada catatan makan hari ini.'), findsOneWidget);
    expect(find.textContaining('belum tercatat (target 7 jam)'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('signals_card')), 200);
    expect(find.textContaining('belum menyimpulkan'), findsOneWidget);
  });

  testWidgets('Beranda gagal dimuat: proyeksi tetap tampil dan bisa dicoba lagi', (tester) async {
    final api = FakeApi()..dashboardError = ApiException('Ada kendala di server.', status: 500);
    await tester.pumpWidget(testApp(const HomeScreen(), api: api));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kondisi hari ini belum termuat'), findsOneWidget);
    expect(find.byKey(const Key('risk_headline')), findsOneWidget);

    api.dashboardError = null;
    await tester.tap(find.byKey(const Key('dashboard_retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today_card')), findsOneWidget);
    expect(api.dashboardCalls, greaterThanOrEqualTo(2)); // Riverpod 3 juga mencoba ulang otomatis
  });

  test('sapaan menurut jam', () {
    expect(greeting(DateTime(2026, 1, 1, 6)), 'Selamat pagi');
    expect(greeting(DateTime(2026, 1, 1, 12)), 'Selamat siang');
    expect(greeting(DateTime(2026, 1, 1, 16)), 'Selamat sore');
    expect(greeting(DateTime(2026, 1, 1, 20)), 'Selamat malam');
  });
}
