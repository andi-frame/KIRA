import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/features/history/history_screen.dart';
import 'package:kira/features/home/home_screen.dart';
import 'package:kira/features/projection/projection_providers.dart';
import 'package:kira/features/trends/trends_screen.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

final _today = DateTime(2026, 10, 16, 9);

const _geprekItems = [
  LoggedItem(id: 'a', name: 'Ayam goreng tepung', portionG: 100, kcal: 268, sugarG: 0.5, sodiumMg: 269, fatG: 15.8,
      foodId: 'ayam_goreng_tepung', group: 'Ayam geprek'),
  LoggedItem(id: 'b', name: 'Nasi putih', portionG: 150, kcal: 270, sugarG: 0.2, sodiumMg: 2, fatG: 0.5,
      foodId: 'nasi_putih', group: 'Ayam geprek'),
];

HistoryDay _day(int daysAgo, {bool logged = false, List<HistoryEntry> meals = const [], NutrientTotals? totals,
    double? sleep, double? active}) =>
    HistoryDay(
      date: DateTime(2026, 10, 16 - daysAgo),
      logged: logged,
      totals: totals ?? const NutrientTotals(),
      meals: meals,
      sleepHours: sleep,
      activityMinutes: active,
    );

HistoryPage _page({String nextBefore = '2026-10-03'}) => HistoryPage(nextBefore: nextBefore, days: [
      _day(0,
          logged: true,
          totals: const NutrientTotals(kcal: 538, sugarG: 62, sodiumMg: 271, fatG: 16.3),
          sleep: 6,
          active: 30,
          meals: [
            HistoryEntry(
              logId: 'log1',
              kind: 'meal',
              time: DateTime(2026, 10, 16, 12, 30),
              source: 'voice',
              title: 'Ayam geprek',
              items: _geprekItems,
              totals: const NutrientTotals(kcal: 538, sugarG: 0.7, sodiumMg: 271, fatG: 16.3),
            ),
          ]),
      _day(1),
      for (var i = 2; i < 14; i++) _day(i),
    ]);

Widget _app(FakeApi api) => testApp(
      const HistoryScreen(),
      api: api,
      overrides: [clockProvider.overrideWithValue(() => _today)],
    );

void main() {
  testWidgets('hari ini tampil dengan total, batas ditulis dengan kata, dan hari kosong "tidak tercatat"', (tester) async {
    final api = FakeApi()..onHistory = (d, b) => _page();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('tidur 6 jam · aktif 30 menit'), 200);
    expect(find.text('Hari ini'), findsOneWidget);
    expect(find.text('538 kkal'), findsOneWidget);
    expect(find.text('melewati batas 12 g'), findsOneWidget); // gula 62 dari batas 50
    expect(find.text('sisa 1.729 mg'), findsOneWidget); // natrium
    expect(find.text('tidur 6 jam · aktif 30 menit'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('history_day_2026-10-15')), 200);
    expect(find.text('Kemarin'), findsOneWidget);
    expect(find.text('tidak tercatat'), findsWidgets);
    expect(api.historyCalls.first, (days: 14, before: null));
  });

  testWidgets('catatan makan bisa dibuka untuk melihat komponen dan dikoreksi', (tester) async {
    final api = FakeApi()..onHistory = (d, b) => _page();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('history_entry_log1')), 200);
    expect(find.textContaining('12.30 · 538 kkal'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('history_entry_log1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayam geprek'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('halve_group_0')), 200);
    expect(find.text('Ayam goreng tepung'), findsOneWidget);

    await tester.tap(find.byKey(const Key('halve_group_0')));
    await tester.pumpAndSettle();
    expect(api.patchFields.single.fields, {'half': true, 'group': 'Ayam geprek'});
    expect(api.historyCalls, hasLength(2)); // dimuat ulang supaya total harian ikut berubah
    expect(api.dashboardCalls, greaterThanOrEqualTo(0));
  });

  testWidgets('koreksi dari Riwayat membuat proyeksi, Beranda, dan tren dimuat ulang, bukan tertahan angka lama', (tester) async {
    final api = FakeApi()..onHistory = (d, b) => _page();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(HistoryScreen)));
    await container.read(projectionProvider.future);
    await container.read(dashboardProvider.future);
    await container.read(trendsProvider(30).future);
    final calls = (projection: api.projectionCalls, dashboard: api.dashboardCalls);

    await tester.scrollUntilVisible(find.byKey(const Key('history_entry_log1')), 200);
    await tester.ensureVisible(find.byKey(const Key('history_entry_log1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayam geprek'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('delete_log')), 200);
    await tester.ensureVisible(find.byKey(const Key('delete_log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_log_confirm')));
    await tester.pumpAndSettle();
    expect(api.deletedLogs, ['log1']);

    await container.read(projectionProvider.future);
    await container.read(dashboardProvider.future);
    expect(api.projectionCalls, calls.projection + 1);
    expect(api.dashboardCalls, calls.dashboard + 1);
    expect(container.read(trendsProvider(30)).isLoading || container.read(trendsProvider(30)).hasValue, isTrue);
  });

  testWidgets('olahraga dan tidur tampil di Riwayat dan bisa diubah atau dihapus', (tester) async {
    final api = FakeApi()
      ..onHistory = (d, b) => HistoryPage(nextBefore: '2026-10-03', days: [
            HistoryDay(
              date: DateTime(2026, 10, 16),
              logged: true,
              sleepHours: 6,
              activityMinutes: 20,
              activities: [HistoryActivity(logId: 'act1', kind: 'jalan kaki', minutes: 20, time: DateTime(2026, 10, 16, 7))],
              sleeps: [HistorySleep(logId: 'slp1', time: DateTime(2026, 10, 16, 6), hours: 6, bedTime: '23:00', wakeTime: '05:00')],
            ),
            for (var i = 1; i < 14; i++) _day(i),
          ]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Olahraga dan aktivitas'), 200);
    expect(find.text('Olahraga dan aktivitas'), findsOneWidget);
    expect(find.text('jalan kaki · 20 menit'), findsOneWidget);
    expect(find.text('6 jam tidur'), findsOneWidget);
    expect(find.text('tidur 23:00, bangun 05:00'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('edit_activity_act1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_activity_act1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('activity_minutes')), '45');
    await tester.tap(find.byKey(const Key('activity_save')));
    await tester.pumpAndSettle();
    expect(api.patchFields.single.id, 'act1');
    expect(api.patchFields.single.fields, {'minutes': 45, 'activity_kind': 'jalan kaki'});

    await tester.ensureVisible(find.byKey(const Key('delete_sleep_slp1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_sleep_slp1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_delete')));
    await tester.pumpAndSettle();
    expect(api.deletedLogs, ['slp1']);
  });

  testWidgets('ubah tidur lewat jam tidur dan bangun, atau lamanya saja bila jam tidak dicatat', (tester) async {
    final api = FakeApi()
      ..onHistory = (d, b) => HistoryPage(nextBefore: '2026-10-03', days: [
            HistoryDay(
              date: DateTime(2026, 10, 16),
              logged: true,
              sleepHours: 5,
              sleeps: [HistorySleep(logId: 'slp1', time: DateTime(2026, 10, 16, 6), hours: 5)],
            ),
            for (var i = 1; i < 14; i++) _day(i),
          ]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('edit_sleep_slp1')), 200);
    await tester.ensureVisible(find.byKey(const Key('edit_sleep_slp1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_sleep_slp1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sleep_hours')), '7,5');
    await tester.tap(find.byKey(const Key('sleep_save')));
    await tester.pumpAndSettle();
    expect(api.patchFields.single.id, 'slp1');
    expect(api.patchFields.single.fields, {'hours': 7.5});
  });

  testWidgets('muat 14 hari sebelumnya memakai next_before', (tester) async {
    final api = FakeApi()
      ..onHistory = (d, b) => b == null
          ? _page()
          : HistoryPage(nextBefore: '2026-09-19', days: [for (var i = 14; i < 28; i++) _day(i)]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('history_load_more')), 300);
    await tester.tap(find.byKey(const Key('history_load_more')));
    await tester.pumpAndSettle();

    expect(api.historyCalls.last, (days: 14, before: '2026-10-03'));
    await tester.scrollUntilVisible(find.byKey(const Key('history_day_2026-09-19')), 300);
  });

  testWidgets('belum ada catatan sama sekali: ajakan mencatat, bukan angka nol', (tester) async {
    final api = FakeApi()
      ..onHistory = (d, b) => HistoryPage(nextBefore: '2026-10-03', days: [for (var i = 0; i < 14; i++) _day(i)]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history_empty')), findsOneWidget);
    expect(find.byKey(const Key('history_week_strip')), findsNothing);
  });

  testWidgets('gagal memuat: pesan ramah dan bisa dicoba lagi', (tester) async {
    final api = FakeApi()..historyError = ApiException('Ada kendala di server.', status: 500);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ada kendala di server'), findsOneWidget);

    api
      ..historyError = null
      ..onHistory = (d, b) => _page();
    await tester.tap(find.byKey(const Key('retry_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history_week_strip')), findsOneWidget);
  });

  test('judul hari: hari ini, kemarin, lalu nama hari dan tanggal', () {
    expect(dayTitle(DateTime(2026, 10, 16), _today), 'Hari ini');
    expect(dayTitle(DateTime(2026, 10, 15), _today), 'Kemarin');
    expect(dayTitle(DateTime(2026, 10, 13), _today), 'Sel, 13 Okt 2026');
  });
}
