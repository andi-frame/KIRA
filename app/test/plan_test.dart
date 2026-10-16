import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/home/home_screen.dart';
import 'package:kira/features/plan/plan_preferences_screen.dart';
import 'package:kira/features/plan/plan_screen.dart';
import 'package:kira/features/reminders/reminder_plan.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

Finder _in(String listKey) =>
    find.descendant(of: find.byKey(Key(listKey)), matching: find.byType(Scrollable)).first;

void main() {
  testWidgets('rencana hari ini: energi bersumber, usulan dengan alasan, olahraga, tidur, dan penafian', (tester) async {
    await tester.pumpWidget(testApp(const PlanScreen(), api: FakeApi()));
    await tester.pumpAndSettle();

    expect(find.text('Energi hari ini sekitar 2.650 kkal'), findsOneWidget);
    expect(find.textContaining('Permenkes 28/2019'), findsOneWidget);
    expect(find.text('Roti telur'), findsOneWidget);
    expect(find.textContaining('Gula 4 g, masih di bawah anggaran sarapan'), findsOneWidget);
    expect(find.text('Roti tawar 60 g, Telur ceplok 50 g'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('plan_sleep')), 300, scrollable: _in('plan_today_list'));
    expect(find.text('jalan cepat 10 menit'), findsOneWidget);
    expect(find.text('Tidur jam 22.00, bangun 06.00'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('bukan resep'), 300, scrollable: _in('plan_today_list'));
    expect(find.textContaining('bukan resep'), findsOneWidget);
  });

  testWidgets('ganti usulan memperbarui satu bagian', (tester) async {
    final api = FakeApi()..onSwap = (slot) => fakeDayPlan(DateTime(2026, 10, 16), lunch: 'Sate ayam + lontong');
    await tester.pumpWidget(testApp(const PlanScreen(), api: api));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('swap_lunch')), 200, scrollable: _in('plan_today_list'));
    await tester.tap(find.byKey(const Key('swap_lunch')));
    await tester.pumpAndSettle();
    expect(api.swaps, ['lunch']);
    expect(find.text('Sate ayam + lontong'), findsOneWidget);
    expect(find.text('Nasi warteg'), findsNothing);
  });

  testWidgets('yang sudah dimakan bertanda dan tidak bisa diganti', (tester) async {
    final base = fakeDayPlan(DateTime(2026, 10, 16));
    final api = FakeApi()
      ..planToday = DayPlan(
        date: base.date, kcalTarget: base.kcalTarget, energySource: base.energySource, sleep: base.sleep,
        exercise: base.exercise, disclaimer: base.disclaimer,
        adapted: 'Disesuaikan dengan yang sudah kamu makan hari ini: sisa gula 10 g.',
        meals: [
          const PlanMeal(slot: 'breakfast', label: 'sarapan', title: 'Roti telur', done: true),
          ...base.meals.skip(1),
        ],
      );
    await tester.pumpWidget(testApp(const PlanScreen(), api: api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan_adapted')), findsOneWidget);
    expect(find.text('sudah tercatat'), findsOneWidget);
    expect(find.byKey(const Key('swap_breakfast')), findsNothing);
  });

  testWidgets('rencana minggu: tujuh hari dengan hari istirahat ditulis', (tester) async {
    final week = [for (var i = 0; i < 7; i++) fakeDayPlan(DateTime(2026, 10, 16 + i))];
    final api = FakeApi()
      ..planWeek = [
        ...week.take(6),
        DayPlan(date: week[6].date, kcalTarget: 2650, energySource: '', meals: week[6].meals, sleep: week[6].sleep),
      ];
    await tester.pumpWidget(testApp(const PlanScreen(), api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minggu ini'));
    await tester.pumpAndSettle();
    expect(find.text('Jumat, 16 Okt 2026'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('plan_week_2026-10-22')), 300, scrollable: _in('plan_week_list'));
    expect(find.text('Olahraga: hari istirahat'), findsOneWidget);
  });

  testWidgets('preferensi: ubah hari olahraga dan tujuan lalu simpan', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(testApp(const PlanPreferencesScreen(), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pref_day_5')));
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('pref_goal_turun_berat')), 200);
    await tester.ensureVisible(find.byKey(const Key('pref_goal_turun_berat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pref_goal_turun_berat')));
    await tester.pump();
    expect(find.textContaining('bukan diet medis'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('pref_save')), 300);
    await tester.ensureVisible(find.byKey(const Key('pref_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pref_save')));
    await tester.pumpAndSettle();

    final saved = api.savedPlanPrefs.single;
    expect(saved.exerciseDays, [0, 1, 2, 3, 4, 5]);
    expect(saved.goal, 'turun_berat');
  });

  testWidgets('preferensi: tidak bisa memilih tujuh hari olahraga (harus ada hari istirahat)', (tester) async {
    final api = FakeApi()..planPrefs = const PlanPreferences(exerciseDays: [0, 1, 2, 3, 4, 5]);
    await tester.pumpWidget(testApp(const PlanPreferencesScreen(), api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pref_day_6')));
    await tester.pump();
    final chip = tester.widget<FilterChip>(find.byKey(const Key('pref_day_6')));
    expect(chip.selected, isFalse);
  });

  testWidgets('Beranda menampilkan kartu rencana hari ini', (tester) async {
    final api = FakeApi()
      ..dashboard = DashboardData(
        today: const TodayStatus(kcalTarget: 2650),
        nextAction: const NextAction(kind: 'exercise', text: 'Sisa 30 menit bergerak hari ini.'),
        planToday: PlanCard.fromJson({
          'meals': [
            {'label': 'sarapan', 'time': '06:30', 'title': 'Roti telur', 'done': true},
            {'label': 'makan siang', 'time': '12:00', 'title': 'Nasi warteg', 'done': false},
          ],
          'exercise': {'minutes': 30, 'activity': 'jalan cepat', 'done': false, 'blocked': false},
          'sleep': {'bedtime': '22:00'},
        }),
      );
    await tester.pumpWidget(testApp(const HomeScreen(), api: api));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('plan_card')), 200);
    expect(find.text('06.30 sarapan: Roti telur (sudah)'), findsOneWidget);
    expect(find.text('12.00 makan siang: Nasi warteg'), findsOneWidget);
    expect(find.text('Olahraga: jalan cepat 30 menit'), findsOneWidget);
    expect(find.text('Tidur jam 22.00'), findsOneWidget);
    expect(find.text('2.650 kkal'), findsNothing);
    expect(find.textContaining('dari 2.650 kkal'), findsOneWidget);
  });

  group('pengingat rencana lokal', () {
    final now = DateTime(2026, 10, 16, 11, 0); // Jumat
    const input = PlanReminderInput(
      mealTimes: {'breakfast': '06:30', 'lunch': '12:00', 'snack': '15:30', 'dinner': '18:30'},
      exerciseTime: '17:00',
      exerciseDays: [0, 1, 2, 3, 4],
      exerciseLabel: 'jalan cepat',
      bedtime: '22:00',
    );

    List<PlannedReminder> run({ReminderSettings settings = const ReminderSettings(plan: true), PlanReminderInput? plan = input}) =>
        planReminders(now: now, settings: settings, loggedToday: false, checkFollowUpDue: false, plan: plan);

    test('mati secara bawaan', () {
      expect(run(settings: const ReminderSettings()), isEmpty);
      expect(const ReminderSettings().plan, isFalse);
    });

    test('10 menit sebelum tiap waktu, yang sudah lewat dilewati, isi tanpa angka kesehatan', () {
      final today = run().where((r) => r.at.day == 16).toList();
      expect(today.map((r) => (r.body, r.at.hour, r.at.minute)), [
        ('Waktunya makan siang', 11, 50),
        ('Waktunya selingan', 15, 20),
        ('Waktunya makan malam', 18, 20),
        ('Waktunya jalan cepat', 16, 50),
        ('Waktunya bersiap tidur', 21, 50),
      ]);
      for (final r in run()) {
        expect(r.body.codeUnits.any((c) => c >= 0x30 && c <= 0x39), isFalse); // tanpa angka
      }
    });

    test('olahraga hanya di hari pilihan, ID unik per slot per hari', () {
      final all = run();
      final saturdayExercise = all.where((r) => r.at.weekday == DateTime.saturday && r.body.contains('jalan cepat'));
      expect(saturdayExercise, isEmpty);
      expect(all.map((r) => r.id).toSet().length, all.length);
      expect(all.every((r) => r.id >= planIdBase && r.id < planIdBase + 70), isTrue);
    });

    test('makan yang sudah tercatat hari ini dan yang lewat WhatsApp tidak digandakan', () {
      final logged = run(plan: const PlanReminderInput(
        mealTimes: {'lunch': '12:00'}, exerciseTime: '17:00', exerciseDays: [0, 1, 2, 3, 4], bedtime: '22:00',
        loggedSlotsToday: {'lunch'}, viaWhatsapp: {'sleep'},
      ));
      expect(logged.where((r) => r.at.day == 16 && r.body == 'Waktunya makan siang'), isEmpty);
      expect(logged.where((r) => r.body == 'Waktunya bersiap tidur'), isEmpty);
      expect(logged.where((r) => r.at.day == 17 && r.body == 'Waktunya makan siang'), hasLength(1));
    });

    test('pengaturan tersimpan dan terbaca kembali', () {
      final s = ReminderSettings.fromJson(const ReminderSettings(plan: true).toJson());
      expect(s.plan, isTrue);
      expect(s.anyEnabled, isTrue);
    });
  });
}
