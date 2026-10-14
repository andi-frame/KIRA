import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/doctor/doctor_summary_screen.dart';
import 'package:kira/shared/family_models.dart';

import 'support/fakes.dart';

Future<void> pumpSummary(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const DoctorSummaryScreen(), api: api));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menampilkan ringkasan 30 hari dan bisa berganti periode', (tester) async {
    final api = FakeApi();
    await pumpSummary(tester, api);
    expect(find.byKey(const Key('summary_text')), findsOneWidget);
    expect(find.textContaining('30 hari'), findsWidgets);
    expect(api.doctorSummaryDays, [30]);

    await tester.tap(find.byKey(const Key('period_7')));
    await tester.pumpAndSettle();
    expect(api.doctorSummaryDays.last, 7);
    expect(find.textContaining('7 hari'), findsWidgets);
  });

  testWidgets('tombol salin menaruh ringkasan di papan klip', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpSummary(tester, FakeApi());
    await tester.tap(find.byKey(const Key('copy_summary')));
    await tester.pumpAndSettle();
    expect(copied, contains('Ringkasan KIRA 30 hari untuk Raka'));
    expect(find.textContaining('disalin'), findsOneWidget);
  });

  testWidgets('tanpa catatan: ajakan untuk mulai check-in', (tester) async {
    final api = FakeApi()
      ..onDoctorSummary = (d) => DoctorSummary(text: 'Belum ada catatan.', periodDays: d, daysLogged: 0);
    await pumpSummary(tester, api);
    expect(find.byKey(const Key('summary_empty_hint')), findsOneWidget);
  });

  testWidgets('korelasi makanan dan gula darah: butuh data lebih banyak', (tester) async {
    await pumpSummary(tester, FakeApi());
    final card = find.byKey(const Key('food_glucose_card'));
    await tester.scrollUntilVisible(card, 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('minimal 3'), findsOneWidget);
  });

  testWidgets('korelasi makanan dan gula darah: daftar dengan peringatan bukan sebab pasti', (tester) async {
    final api = FakeApi()
      ..foodGlucose = const FoodGlucose(
        foods: [FoodGlucoseEntry(name: 'nasi goreng', samples: 3, avgMgDl: 160)],
        needsMoreData: false,
        totalReadings: 4,
        disclaimer: 'Ini pola dari catatanmu sendiri, bukan sebab pasti.',
      );
    await pumpSummary(tester, api);
    final card = find.byKey(const Key('food_glucose_card'));
    await tester.scrollUntilVisible(card, 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('nasi goreng'), findsOneWidget);
    expect(find.textContaining('160'), findsOneWidget);
    expect(find.textContaining('bukan sebab pasti'), findsOneWidget);
  });
}
