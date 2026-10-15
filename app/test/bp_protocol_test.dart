import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/bp/bp_protocol_screen.dart';
import 'package:kira/shared/engagement_models.dart';

import 'support/fakes.dart';

Future<void> pumpBp(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const BpProtocolScreen(), api: api));
  await tester.pumpAndSettle();
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('bp_add')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('belum ada putaran: alasan, empat langkah, dan sumber panduan', (tester) async {
    await pumpBp(tester, FakeApi());
    expect(find.textContaining('lebih bisa dipegang'), findsOneWidget);
    expect(find.text('Dua kali tiap sesi'), findsOneWidget);
    expect(find.text('Duduk tenang dulu'), findsOneWidget);
    expect(find.textContaining('ESH 2021'), findsOneWidget);
    expect(find.textContaining('bukan diagnosis'), findsOneWidget);
  });

  testWidgets('mulai membuat putaran dan menampilkan tujuh hari', (tester) async {
    final api = FakeApi();
    await pumpBp(tester, api);
    await tester.tap(find.byKey(const Key('bp_start')));
    await tester.pumpAndSettle();
    expect(api.bpStarts, 1);
    expect(find.text('Hari ke-1 dari 7'), findsOneWidget);
    expect(find.byKey(const Key('bp_days')), findsOneWidget);
    expect(find.textContaining('butuh 3 hari lagi'), findsOneWidget);
  });

  testWidgets('selesai tidak bisa ditekan sebelum cukup, dan penjelasannya tertulis', (tester) async {
    final api = FakeApi()..bpView = BpProtocolView(protocol: sampleBpState(morning: 2));
    await pumpBp(tester, api);
    final finish = tester.widget<OutlinedButton>(find.byKey(const Key('bp_finish')));
    expect(finish.onPressed, isNull);
    expect(find.text('dibuang'), findsOneWidget); // hari pertama ditandai
  });

  testWidgets('cukup untuk dihitung: pratinjau rata-rata dan tombol selesai aktif', (tester) async {
    final summary = const BpSummary(valid: true, readingsUsed: 12, daysUsed: 3, avgSys: 126.4, avgDia: 81.0, range: 'below_threshold');
    final api = FakeApi()..bpView = BpProtocolView(protocol: sampleBpState(dayIndex: 5, canFinish: true, summary: summary));
    await pumpBp(tester, api);
    expect(find.textContaining('126,4/81 mmHg dari 12 bacaan di 3 hari'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bp_finish')));
    await tester.pumpAndSettle();
    expect(api.bpFinishes, 1);
  });

  testWidgets('catat bacaan: sesi mengikuti jam, angka divalidasi sebelum dikirim', (tester) async {
    final api = FakeApi()..bpView = BpProtocolView(protocol: sampleBpState());
    await pumpBp(tester, api);
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('bp_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bp_error')), findsOneWidget);
    expect(api.bpReadings, isEmpty);

    await tester.enterText(find.byKey(const Key('bp_sys')), '110');
    await tester.enterText(find.byKey(const Key('bp_dia')), '120');
    await tester.tap(find.byKey(const Key('bp_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('lebih kecil'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('bp_sys')), '128');
    await tester.enterText(find.byKey(const Key('bp_dia')), '82');
    await tester.tap(find.text('Malam'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bp_save')));
    await tester.pumpAndSettle();
    expect(api.bpReadings, [(sys: 128, dia: 82, session: 'evening')]);
    expect(find.byKey(const Key('bp_sys')), findsNothing); // lembar tertutup
  });

  testWidgets('bacaan berbahaya tidak disimpan: kartu darurat tampil di halaman', (tester) async {
    final api = FakeApi()
      ..bpView = BpProtocolView(protocol: sampleBpState())
      ..onBpReading = (_, _, _) => BpProtocolView(
            protocol: sampleBpState(), saved: false,
            redFlag: 'Tekanan darahmu sangat tinggi. Segera ke IGD atau Puskesmas terdekat.',
          );
    await pumpBp(tester, api);
    await openSheet(tester);
    await tester.enterText(find.byKey(const Key('bp_sys')), '190');
    await tester.enterText(find.byKey(const Key('bp_dia')), '120');
    await tester.tap(find.byKey(const Key('bp_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('emergency_card')), findsOneWidget);
    expect(find.textContaining('Segera ke IGD'), findsOneWidget);
  });

  testWidgets('tanpa sinyal: pesan jelas bahwa bacaan protokol butuh sinyal, tidak diam-diam hilang', (tester) async {
    final api = FakeApi()..bpView = BpProtocolView(protocol: sampleBpState());
    await pumpBp(tester, api);
    await openSheet(tester);
    api.bpError = ApiException('Tidak bisa terhubung ke server.');
    await tester.enterText(find.byKey(const Key('bp_sys')), '120');
    await tester.enterText(find.byKey(const Key('bp_dia')), '80');
    await tester.tap(find.byKey(const Key('bp_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Butuh sinyal'), findsOneWidget);
  });

  testWidgets('batal meminta konfirmasi dulu', (tester) async {
    final api = FakeApi()..bpView = BpProtocolView(protocol: sampleBpState());
    await pumpBp(tester, api);
    await tester.tap(find.byKey(const Key('bp_cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Batalkan putaran ini?'), findsOneWidget);
    expect(api.bpCancels, 0);
    await tester.tap(find.byKey(const Key('bp_cancel_confirm')));
    await tester.pumpAndSettle();
    expect(api.bpCancels, 1);
    expect(find.byKey(const Key('bp_start')), findsOneWidget); // kembali ke awal
  });

  testWidgets('hasil di atas ambang rumah: kata "di atas" tertulis, bukan hanya warna, tanpa kata diagnosis pasti', (tester) async {
    final done = BpProtocolState(
      id: 'p1', status: 'completed', dayIndex: 7, days: sampleBpState().days, summary: sampleBpState().summary,
      canFinish: false, over: true, resultSys: 138.5, resultDia: 86, resultReadings: 12, resultRange: 'hypertension_range',
    );
    await pumpBp(tester, FakeApi()..bpView = BpProtocolView(protocol: done));
    expect(find.text('138,5/86 mmHg'), findsOneWidget);
    expect(find.textContaining('di atas ambang tensi rumah (135/85 mmHg)'), findsOneWidget);
    expect(find.textContaining('bukan diagnosis'), findsOneWidget);
    expect(find.textContaining('menderita'), findsNothing);
  });

  testWidgets('hasil di bawah ambang dan mulai putaran baru', (tester) async {
    final api = FakeApi();
    api.bpView = BpProtocolView(
      protocol: BpProtocolState(
        id: 'p1', status: 'completed', dayIndex: 7, days: sampleBpState().days, summary: sampleBpState().summary,
        canFinish: false, over: true, resultSys: 121, resultDia: 78, resultReadings: 14, resultRange: 'below_threshold',
      ),
    );
    await pumpBp(tester, api);
    expect(find.textContaining('di bawah ambang tensi rumah'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bp_again')));
    await tester.pumpAndSettle();
    expect(api.bpStarts, 1);
  });

  testWidgets('gagal memuat: pesan ramah dengan tombol coba lagi', (tester) async {
    final api = FakeApi()..bpError = ApiException('Ada kendala di server.', status: 500);
    await pumpBp(tester, api);
    expect(find.text('Ada kendala di server.'), findsOneWidget);
  });
}
