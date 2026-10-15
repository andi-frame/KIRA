import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/features/reminders/reminder_plan.dart';
import 'package:kira/features/reminders/reminders_controller.dart';
import 'package:kira/features/reminders/reminders_screen.dart';
import 'package:kira/shared/account_models.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

// Rabu 14 Oktober 2026, 10.30.
final wed = DateTime(2026, 10, 14, 10, 30);
const daily = ReminderSettings(daily: true, hour: 19, minute: 0);

List<PlannedReminder> plan(ReminderSettings s, {DateTime? now, bool logged = false, bool due = false}) =>
    planReminders(now: now ?? wed, settings: s, loggedToday: logged, checkFollowUpDue: due);

void main() {
  group('perencana pengingat (fungsi murni)', () {
    test('semua mati secara bawaan: tidak ada yang dijadwalkan', () {
      expect(plan(const ReminderSettings(), due: true), isEmpty);
      expect(const ReminderSettings().anyEnabled, isFalse);
    });

    test('harian: tujuh hari ke depan pada jam pilihan, mulai hari ini bila jamnya belum lewat', () {
      final r = plan(daily);
      expect(r, hasLength(7));
      expect(r.first.at, DateTime(2026, 10, 14, 19, 0));
      expect(r.last.at, DateTime(2026, 10, 20, 19, 0));
      expect(r.map((e) => e.id).toSet(), hasLength(7));
    });

    test('jam hari ini sudah lewat: mulai besok', () {
      final r = plan(daily, now: DateTime(2026, 10, 14, 20, 0));
      expect(r, hasLength(6));
      expect(r.first.at, DateTime(2026, 10, 15, 19, 0));
    });

    test('sudah mencatat hari ini: pengingat hari ini dilewati, besok tetap', () {
      final r = plan(daily, logged: true);
      expect(r, hasLength(6));
      expect(r.first.at.day, 15);
    });

    test('rekap mingguan: tiap Senin 08.00, empat minggu ke depan', () {
      final r = plan(const ReminderSettings(weekly: true));
      expect(r, hasLength(4));
      expect(r.first.at, DateTime(2026, 10, 19, 8, 0)); // Senin berikutnya
      expect(r.every((e) => e.at.weekday == DateTime.monday), isTrue);
    });

    test('hari ini Senin sebelum 08.00: rekap hari ini; sesudahnya: minggu depan', () {
      final early = plan(const ReminderSettings(weekly: true), now: DateTime(2026, 10, 19, 6, 0));
      expect(early.first.at, DateTime(2026, 10, 19, 8, 0));
      final late = plan(const ReminderSettings(weekly: true), now: DateTime(2026, 10, 19, 9, 0));
      expect(late.first.at, DateTime(2026, 10, 26, 8, 0));
    });

    test('tindak lanjut cek: hanya bila diaktifkan DAN memang saatnya, sekali saja', () {
      const s = ReminderSettings(checkFollowUp: true);
      expect(plan(s, due: false), isEmpty);
      final r = plan(s, due: true);
      expect(r, hasLength(1));
      expect(r.single.at, DateTime(2026, 10, 15, 9, 0)); // 09.00 hari ini sudah lewat: besok
      expect(plan(const ReminderSettings(), due: true), isEmpty);
    });

    test('isi notifikasi tidak memuat data kesehatan apa pun', () {
      const all = ReminderSettings(daily: true, weekly: true, checkFollowUp: true);
      final text = plan(all, due: true).map((e) => '${e.title} ${e.body}'.toLowerCase()).join(' ');
      for (final forbidden in ['mg/dl', 'mmhg', 'diabetes', 'hipertensi', 'tensi', 'gula darah', 'risiko', 'skor']) {
        expect(text, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('pengaturan disimpan dan dibaca kembali, rusak jatuh ke bawaan', () {
      const s = ReminderSettings(daily: true, hour: 6, minute: 45, weekly: true);
      final back = ReminderSettings.fromJson(s.toJson());
      expect((back.daily, back.hour, back.minute, back.weekly, back.checkFollowUp), (true, 6, 45, true, false));
      expect(ReminderSettings.fromJson('bukan json').anyEnabled, isFalse);
      expect(ReminderSettings.fromJson(null).hour, 19);
      expect(ReminderSettings.fromJson('{"hour": 99, "minute": -5}').hour, 23); // dijepit ke rentang jam
    });
  });

  group('layar dan pengendali pengingat', () {
    Future<(FakeApi, FakeNotifications, MemoryPrefsStore)> pump(WidgetTester tester,
        {bool grant = true, bool logged = false}) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final api = FakeApi()..loggedToday = logged;
      final notif = FakeNotifications(grant: grant);
      final prefs = MemoryPrefsStore();
      await tester.pumpWidget(testApp(const RemindersScreen(), api: api, prefs: prefs, overrides: [notificationsOverride(notif)]));
      await tester.pumpAndSettle();
      return (api, notif, prefs);
    }

    testWidgets('semua saklar mati, penjelasan privasi tampil', (tester) async {
      await pump(tester);
      expect(find.textContaining('tidak memuat data kesehatan'), findsOneWidget);
      for (final k in ['reminder_daily', 'reminder_weekly', 'reminder_check']) {
        expect(tester.widget<SwitchListTile>(find.byKey(Key(k))).value, isFalse, reason: k);
      }
      expect(find.byKey(const Key('reminder_time')), findsNothing);
    });

    testWidgets('menyalakan check-in harian meminta izin, menjadwalkan, dan menyimpan', (tester) async {
      final (_, notif, prefs) = await pump(tester);
      await tester.tap(find.byKey(const Key('reminder_daily')));
      await tester.pumpAndSettle();
      expect(notif.permissionRequests, 1);
      expect(notif.scheduled, isNotEmpty);
      expect(notif.scheduled.every((r) => r.title == 'Check-in KIRA'), isTrue);
      expect(await prefs.read('reminders_v1'), contains('"daily":true'));
      expect(find.byKey(const Key('reminder_time')), findsOneWidget);
    });

    testWidgets('izin ditolak: tetap mati dan dijelaskan, tidak ada jadwal', (tester) async {
      final (_, notif, prefs) = await pump(tester, grant: false);
      await tester.tap(find.byKey(const Key('reminder_weekly')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reminder_denied')), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('reminder_weekly'))).value, isFalse);
      expect(notif.scheduled, isEmpty);
      expect(await prefs.read('reminders_v1'), isNull);
    });

    testWidgets('mematikan semua membatalkan jadwal', (tester) async {
      final (_, notif, prefs) = await pump(tester);
      await tester.tap(find.byKey(const Key('reminder_weekly')));
      await tester.pumpAndSettle();
      expect(notif.scheduled, hasLength(4));
      await tester.tap(find.byKey(const Key('reminder_weekly')));
      await tester.pumpAndSettle();
      expect(notif.scheduled, isEmpty);
      expect(await prefs.read('reminders_v1'), isNull);
    });

    testWidgets('sudah mencatat hari ini: jadwal hari ini dilewati (dipantau dari server)', (tester) async {
      final (_, notif, _) = await pump(tester, logged: true);
      await tester.tap(find.byKey(const Key('reminder_daily')));
      await tester.pumpAndSettle();
      final today = DateTime.now();
      expect(notif.scheduled.where((r) => r.at.day == today.day && r.at.month == today.month), isEmpty);
    });

    testWidgets('tindak lanjut cek hanya dijadwalkan bila server bilang saatnya', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final api = FakeApi()
        ..recommendation = const CheckRecommendation(id: 'r', testKind: 'fasting_glucose', reason: 'x', followUp: true, ageDays: 4);
      final notif = FakeNotifications();
      await tester.pumpWidget(testApp(const RemindersScreen(), api: api, overrides: [notificationsOverride(notif)]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reminder_check')));
      await tester.pumpAndSettle();
      expect(notif.scheduled.single.title, 'Sudah sempat cek?');
    });

    testWidgets('pengaturan tersimpan dimuat saat dibuka kembali', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final prefs = MemoryPrefsStore();
      await prefs.write('reminders_v1', const ReminderSettings(daily: true, hour: 6, minute: 5).toJson());
      final notif = FakeNotifications();
      await tester.pumpWidget(testApp(const RemindersScreen(), prefs: prefs, overrides: [notificationsOverride(notif)]));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('reminder_daily'))).value, isTrue);
      expect(find.text('06.05'), findsOneWidget);
      expect(notif.scheduled.first.at.hour, 6);
    });

    test('keluar dari akun membatalkan semua pengingat dan menghapus pengaturan', () async {
      final notif = FakeNotifications();
      final prefs = MemoryPrefsStore();
      final c = ProviderContainer(overrides: [
        apiProvider.overrideWithValue(FakeApi()),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore('a')),
        prefsStoreProvider.overrideWithValue(prefs),
        notificationsOverride(notif),
      ]);
      addTearDown(c.dispose);
      await c.read(authProvider.notifier).setTokens(const AuthTokens('akun-a', 'r'));
      await c.read(remindersProvider.notifier).update(daily);
      expect(notif.scheduled, isNotEmpty);
      await c.read(authProvider.notifier).setTokens(const AuthTokens('akun-b', 'r'));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(remindersProvider).anyEnabled, isFalse);
      expect(notif.scheduled, isEmpty);
      expect(await prefs.read('reminders_v1'), isNull);
    });
  });
}
