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

  testWidgets('layar Cek menyediakan jalan ke tren hasil cek dan penanda', (tester) async {
    await pumpCheck(tester, FakeApi());
    expect(find.byKey(const Key('trends_button')), findsOneWidget);
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

  testWidgets('gula darah setelah makan disimpan sebagai gula sewaktu, bukan gula puasa', (tester) async {
    final api = FakeApi();
    await pumpCheck(tester, api);
    await openForm(tester);

    await tester.tap(find.byKey(const Key('glucose_random_chip')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('glucose_input')), '160');
    await tester.tap(find.byKey(const Key('result_save')));
    await tester.pumpAndSettle();

    expect(api.results.single.kind, 'random_glucose');
    expect(api.results.single.value, {'mg_dl': 160});
  });

  followUpTests();
  mapTests();
}

const agedRec = CheckRecommendation(
  id: 'r1',
  testKind: 'fasting_glucose',
  reason: 'Proyeksimu masih punya rentang lebar karena gula darahmu belum pernah diukur.',
  followUp: true,
  ageDays: 4,
);

void followUpTests() {
  testWidgets('rekomendasi baru tidak menanyakan "sudah dicek?"', (tester) async {
    await pumpCheck(tester, FakeApi()..recommendation = glucoseRec);
    expect(find.byKey(const Key('followup_question')), findsNothing);
  });

  testWidgets('setelah beberapa hari KIRA bertanya dengan tiga jawaban yang sama-sama sopan', (tester) async {
    await pumpCheck(tester, FakeApi()..recommendation = agedRec);
    expect(find.textContaining('Sudah sempat cek? Saran ini muncul 4 hari lalu.'), findsOneWidget);
    expect(find.byKey(const Key('followup_done')), findsOneWidget);
    expect(find.byKey(const Key('followup_snooze')), findsOneWidget);
    expect(find.byKey(const Key('followup_dismiss')), findsOneWidget);
  });

  testWidgets('"Sudah" membuka isian hasil supaya proyeksi terbarui', (tester) async {
    final api = FakeApi()..recommendation = agedRec;
    await pumpCheck(tester, api);
    await tester.tap(find.byKey(const Key('followup_done')));
    await tester.pumpAndSettle();
    expect(api.checkResponses, [(id: 'r1', action: 'done')]);
    expect(find.text('Gula darah puasa'), findsWidgets); // lembar isian hasil terbuka
    expect(find.byKey(const Key('result_save')), findsOneWidget);
  });

  testWidgets('"Nanti" menunda tanpa membuka apa pun dan memberi tahu kapan ditanya lagi', (tester) async {
    final api = FakeApi()..recommendation = agedRec;
    await pumpCheck(tester, api);
    await tester.tap(find.byKey(const Key('followup_snooze')));
    await tester.pumpAndSettle();
    expect(api.checkResponses, [(id: 'r1', action: 'snooze')]);
    expect(find.textContaining('tanya lagi dalam 3 hari'), findsOneWidget);
    expect(find.byKey(const Key('result_save')), findsNothing);
  });

  testWidgets('"Tidak perlu" dihormati dan dijelaskan', (tester) async {
    final api = FakeApi()..recommendation = agedRec;
    await pumpCheck(tester, api);
    await tester.tap(find.byKey(const Key('followup_dismiss')));
    await tester.pumpAndSettle();
    expect(api.checkResponses, [(id: 'r1', action: 'dismiss')]);
    expect(find.textContaining('tidak menyarankan ini lagi'), findsOneWidget);
  });

  testWidgets('gagal menjawab: pesan ramah, tidak crash', (tester) async {
    final api = FakeApi()
      ..recommendation = agedRec
      ..onRespondCheck = (_, _) => throw ApiException('Tidak bisa terhubung ke server.');
    await pumpCheck(tester, api);
    await tester.tap(find.byKey(const Key('followup_snooze')));
    await tester.pumpAndSettle();
    expect(find.text('Tidak bisa terhubung ke server.'), findsOneWidget);
  });
}

void mapTests() {
  testWidgets('tempat cek terdekat bisa dibuka di peta dengan koordinatnya', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final links = FakeLinks();
    await tester.pumpWidget(testApp(const CheckScreen(),
        api: FakeApi()..recommendation = glucoseRec, overrides: [locationOverride((lat: -6.893, lng: 107.613)), linksOverride(links)]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('map_Puskesmas Coblong')));
    await tester.pumpAndSettle();
    // Rute di Google Maps ke koordinat tempat itu (bukan sekadar titik), bisa dibuka tanpa kunci apa pun.
    expect(links.opened.single.host, 'www.google.com');
    expect(links.opened.single.path, '/maps/dir/');
    expect(links.opened.single.queryParameters['destination'], '-6.893,107.613');
    expect(find.byKey(const Key('map_Posyandu Melati')), findsNothing); // tanpa koordinat: tidak ada tombol
  });

  testWidgets('tidak ada aplikasi peta: pesan ramah', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(const CheckScreen(),
        api: FakeApi()..recommendation = glucoseRec, overrides: [locationOverride(), linksOverride(FakeLinks(canOpen: false))]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('map_Puskesmas Coblong')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aplikasi peta belum bisa dibuka'), findsOneWidget);
  });
}
