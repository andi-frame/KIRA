import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/goals/goals_screen.dart';
import 'package:kira/shared/goal_models.dart';

import 'support/fakes.dart';

Future<void> pumpGoals(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const GoalsScreen(), api: api));
  await tester.pumpAndSettle();
}

GoalsData withGoals(List<Goal> goals) => GoalsData(goals: goals, kinds: sampleGoalKinds, daysLeft: 3);

void main() {
  testWidgets('tanpa target: ajakan lembut dan tombol tambah', (tester) async {
    await pumpGoals(tester, FakeApi());
    expect(find.byKey(const Key('goals_empty')), findsOneWidget);
    expect(find.byKey(const Key('goal_add')), findsOneWidget);
    expect(find.textContaining('tidak dihitung sebagai gagal'), findsOneWidget);
  });

  testWidgets('kemajuan ditulis dengan kata, bukan hanya bilah', (tester) async {
    final api = FakeApi()..goalsData = withGoals([sampleGoal(current: 70, target: 150)]);
    await pumpGoals(tester, api);
    expect(find.text('70 dari 150 menit'), findsOneWidget);
    expect(find.byKey(const Key('goal_bar_active_minutes_week')), findsOneWidget);
  });

  testWidgets('target tercapai ditandai "Tercapai"; batas yang dilewati ditulis "melewati batas"', (tester) async {
    final api = FakeApi()
      ..goalsData = withGoals([
        sampleGoal(current: 160, target: 150),
        sampleGoal(kind: 'sweet_drinks_week', label: 'Minuman manis minggu ini', unit: 'gelas', current: 9, target: 7, isMax: true),
      ]);
    await pumpGoals(tester, api);
    expect(find.text('Tercapai: 160 dari 150 menit'), findsOneWidget);
    expect(find.text('9 gelas, melewati batas 7'), findsOneWidget);
  });

  testWidgets('batas minuman manis yang masih sesuai ditulis "dari batas"', (tester) async {
    final api = FakeApi()
      ..goalsData = withGoals([sampleGoal(kind: 'sweet_drinks_week', label: 'Minuman manis minggu ini', unit: 'gelas', current: 3, target: 7, isMax: true)]);
    await pumpGoals(tester, api);
    expect(find.text('3 dari batas 7 gelas'), findsOneWidget);
  });

  testWidgets('riwayat: hanya minggu yang punya catatan dihitung', (tester) async {
    final api = FakeApi()..goalsData = withGoals([sampleGoal(metWeeks: 2, weeksWithData: 3)]);
    await pumpGoals(tester, api);
    expect(find.text('2 dari 3 minggu terakhir tercapai'), findsOneWidget);
  });

  testWidgets('belum ada minggu dengan catatan: tidak ada kalimat riwayat', (tester) async {
    await pumpGoals(tester, FakeApi()..goalsData = withGoals([sampleGoal()]));
    expect(find.byKey(const Key('goal_history_active_minutes_week')), findsNothing);
  });

  testWidgets('tambah target: pilih jenis, atur angka (divalidasi), simpan', (tester) async {
    final api = FakeApi();
    await pumpGoals(tester, api);
    await tester.tap(find.byKey(const Key('goal_add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_active_minutes_week')));
    await tester.pumpAndSettle();
    expect(find.text('150'), findsOneWidget); // angka bawaan

    await tester.enterText(find.byKey(const Key('goal_target_input')), '5');
    await tester.tap(find.byKey(const Key('goal_target_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Isi angka 30 sampai 600 menit'), findsOneWidget);
    expect(api.createdGoals, isEmpty);

    await tester.enterText(find.byKey(const Key('goal_target_input')), '120');
    await tester.tap(find.byKey(const Key('goal_target_save')));
    await tester.pumpAndSettle();
    expect(api.createdGoals, [(kind: 'active_minutes_week', target: 120.0)]);
    expect(find.byKey(const Key('goal_active_minutes_week')), findsOneWidget);
  });

  testWidgets('jenis yang sudah dipasang tidak muncul lagi di daftar tambah', (tester) async {
    final api = FakeApi()..goalsData = withGoals([sampleGoal()]);
    await pumpGoals(tester, api);
    await tester.tap(find.byKey(const Key('goal_add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add_active_minutes_week')), findsNothing);
    expect(find.byKey(const Key('add_sweet_drinks_week')), findsOneWidget);
  });

  testWidgets('semua jenis terpasang: tombol tambah hilang', (tester) async {
    final api = FakeApi()
      ..goalsData = withGoals([
        sampleGoal(),
        sampleGoal(kind: 'sweet_drinks_week', isMax: true, target: 7),
        sampleGoal(kind: 'sleep_nights', target: 5),
      ]);
    await pumpGoals(tester, api);
    expect(find.byKey(const Key('goal_add')), findsNothing);
  });

  testWidgets('ubah angka dan hapus', (tester) async {
    final api = FakeApi()..goalsData = withGoals([sampleGoal()]);
    await pumpGoals(tester, api);
    await tester.tap(find.byKey(const Key('edit_active_minutes_week')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('goal_target_input')), '200');
    await tester.tap(find.byKey(const Key('goal_target_save')));
    await tester.pumpAndSettle();
    expect(api.updatedGoals, [(id: 'g-active_minutes_week', target: 200.0)]);

    await tester.tap(find.byKey(const Key('delete_active_minutes_week')));
    await tester.pumpAndSettle();
    expect(api.deletedGoals, ['g-active_minutes_week']);
    expect(find.byKey(const Key('goals_empty')), findsOneWidget);
  });

  testWidgets('kegagalan server ditampilkan ramah', (tester) async {
    final api = FakeApi()..goalError = ApiException('Target jenis ini sudah ada. Ubah saja angkanya.', status: 409);
    await pumpGoals(tester, api);
    await tester.tap(find.byKey(const Key('goal_add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_sleep_nights')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal_target_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('sudah ada'), findsOneWidget);
  });

  test('model membaca JSON server', () {
    final data = GoalsData.fromJson({
      'goals': [
        {
          'id': 'a', 'kind': 'sleep_nights', 'label': 'Malam tidur', 'unit': 'malam', 'met_weeks': 1, 'weeks_with_data': 2,
          'progress': {'current': 3, 'target': 5, 'direction': 'min', 'met': false, 'remaining': 2, 'fraction': 0.6, 'status': 'in_progress'},
          'history': [{'week_start': '2026-10-05', 'met': null, 'current': null}],
        },
      ],
      'kinds': [
        {'kind': 'sleep_nights', 'label': 'Malam tidur', 'unit': 'malam', 'direction': 'min', 'default': 5, 'min': 1, 'max': 7},
        {'kind': 'logging_days', 'label': 'Hari mencatat', 'unit': 'hari', 'direction': 'min', 'default': 5, 'min': 1, 'max': 7},
      ],
      'week': {'start': '2026-10-12', 'end': '2026-10-18', 'days_left': 3},
    });
    expect(data.goals.single.history.single.met, isNull);
    expect(data.available.map((k) => k.kind), ['logging_days']);
    expect(data.daysLeft, 3);
  });
}
