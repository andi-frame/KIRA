import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/check/check_screen.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

const glucoseRec = CheckRecommendation(
  id: 'r1',
  testKind: 'fasting_glucose',
  reason: 'Proyeksimu masih punya rentang lebar karena gula darahmu belum pernah diukur.',
);

Future<void> pumpCheck(WidgetTester tester, FakeApi api, {bool located = true}) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(
    const CheckScreen(),
    api: api,
    overrides: [locationOverride(located ? (lat: -6.893, lng: 107.613) : null)],
  ));
  await tester.pumpAndSettle();
}

Future<void> openForm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('enter_result_button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tanpa rekomendasi: keadaan kosong yang menenangkan, input hasil tetap tersedia', (tester) async {
    await pumpCheck(tester, FakeApi());
    expect(find.byKey(const Key('check_empty')), findsOneWidget);
    expect(find.textContaining('Belum ada yang perlu dicek'), findsOneWidget);
    expect(find.byKey(const Key('enter_result_button')), findsOneWidget);
  });

  testWidgets('rekomendasi menyebut jenis cek, alasan, dan faskes terdekat', (tester) async {
    await pumpCheck(tester, FakeApi()..recommendation = glucoseRec);
    expect(find.text('Cek gula darah puasa'), findsOneWidget);
    expect(find.textContaining('belum pernah diukur'), findsOneWidget);
    expect(find.text('Puskesmas Coblong'), findsOneWidget);
    expect(find.text('Posyandu Melati'), findsOneWidget);
    expect(find.textContaining('0,4 km'), findsOneWidget);
  });

  testWidgets('izin lokasi ditolak: daftar faskes tetap tampil dengan catatan', (tester) async {
    await pumpCheck(tester, FakeApi()..recommendation = glucoseRec, located: false);
    expect(find.text('Puskesmas Coblong'), findsOneWidget);
    expect(find.byKey(const Key('location_note')), findsOneWidget);
  });

  testWidgets('gula darah mustahil ditolak di form sebelum dikirim', (tester) async {
    final api = FakeApi()..recommendation = glucoseRec;
    await pumpCheck(tester, api);
    await openForm(tester);

    await tester.enterText(find.byKey(const Key('glucose_input')), '5000');
    await tester.tap(find.byKey(const Key('result_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('result_error')), findsOneWidget);
    expect(api.results, isEmpty);
  });

  testWidgets('gula darah valid disimpan dan menampilkan rentang yang menyempit', (tester) async {
    final api = FakeApi()
      ..recommendation = glucoseRec
      ..onResult = (k, v) async => ResultOutcome(
            saved: true,
            projection: sampleProjection(low: 13, high: 17, p10Low: 0.17, p10High: 0.33),
          );
    await pumpCheck(tester, api);
    await openForm(tester);

    await tester.enterText(find.byKey(const Key('glucose_input')), '108');
    await tester.tap(find.byKey(const Key('result_save')));
    await tester.pumpAndSettle();

    expect(api.results.single.kind, 'fasting_glucose');
    expect(api.results.single.value, {'mg_dl': 108});
    expect(find.byKey(const Key('outcome_saved')), findsOneWidget);
    expect(find.textContaining('4-33%'), findsOneWidget);
    expect(find.textContaining('17-33%'), findsOneWidget);
  });

  testWidgets('tensi: diastolik tidak boleh lebih besar dari sistolik; nilai valid tersimpan', (tester) async {
    final api = FakeApi()..onResult = (k, v) async => ResultOutcome(saved: true, bpCategory: 'prehypertension', projection: sampleProjection());
    await pumpCheck(tester, api);
    await openForm(tester);
    await tester.tap(find.byKey(const Key('result_kind_bp')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('sys_input')), '120');
    await tester.enterText(find.byKey(const Key('dia_input')), '130');
    await tester.tap(find.byKey(const Key('result_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('result_error')), findsOneWidget);
    expect(api.results, isEmpty);

    await tester.enterText(find.byKey(const Key('dia_input')), '85');
    await tester.tap(find.byKey(const Key('result_save')));
    await tester.pumpAndSettle();
    expect(api.results.single.value, {'sys': 120, 'dia': 85});
    expect(find.textContaining('prehipertensi'), findsOneWidget);
  });

  testWidgets('hasil berbahaya menampilkan kartu darurat dan bukan "tersimpan"', (tester) async {
    final api = FakeApi()
      ..onResult = (k, v) async => const ResultOutcome(saved: false, redFlagMessage: 'Gula darah 45 mg/dL sangat rendah. Segera ke IGD.');
    await pumpCheck(tester, api);
    await openForm(tester);
    await tester.enterText(find.byKey(const Key('glucose_input')), '45');
    await tester.tap(find.byKey(const Key('result_save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emergency_card')), findsOneWidget);
    expect(find.byKey(const Key('outcome_saved')), findsNothing);
  });

  testWidgets('menandai diagnosis dokter memanggil API dan menutup dialog', (tester) async {
    final api = FakeApi();
    await pumpCheck(tester, api);
    await tester.tap(find.byKey(const Key('diagnosis_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dx_prediabetes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dx_confirm')));
    await tester.pumpAndSettle();
    expect(api.diagnoses, ['prediabetes']);
  });

  testWidgets('gagal memuat rekomendasi menampilkan pesan ramah dan bisa dicoba lagi', (tester) async {
    final api = FakeApi()..checkError = ApiException('Tidak bisa terhubung ke server. Cek koneksimu lalu coba lagi.');
    await pumpCheck(tester, api);
    expect(find.textContaining('Tidak bisa terhubung'), findsOneWidget);
    api.checkError = null;
    await tester.tap(find.byKey(const Key('retry_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('check_empty')), findsOneWidget);
  });
}
