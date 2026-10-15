import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/doctor/doctor_summary_screen.dart';
import 'package:kira/shared/account_models.dart';
import 'package:kira/shared/family_models.dart';

import 'support/fakes.dart';

Future<void> pumpSummary(WidgetTester tester, FakeApi api, {FakeShare? share}) async {
  tester.view.physicalSize = const Size(900, 5200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const DoctorSummaryScreen(), api: api, overrides: [if (share != null) shareOverride(share)]));
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

  testWidgets('menampilkan penanda triase dan grafik tren di bawah ringkasan teks', (tester) async {
    final api = FakeApi()..trends = sampleTrends();
    await pumpSummary(tester, api);
    expect(find.byKey(const Key('triage_card')), findsOneWidget);
    expect(find.byKey(const Key('chart_blood_pressure')), findsOneWidget);
    expect(find.byKey(const Key('chart_sugar')), findsOneWidget);
    expect(api.trendsDays, [30]);
    await tester.tap(find.byKey(const Key('period_90')));
    await tester.pumpAndSettle();
    expect(api.trendsDays.last, 90);
  });

  testWidgets('bagikan PDF: mengambil PDF periode terpilih lalu membuka menu bagikan dengan nama berkas jelas', (tester) async {
    final api = FakeApi()..trends = sampleTrends();
    final share = FakeShare();
    await pumpSummary(tester, api, share: share);
    await tester.tap(find.byKey(const Key('period_7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share_pdf')));
    await tester.pumpAndSettle();

    expect(api.pdfDays, [7]);
    expect(share.shared, hasLength(1));
    expect(share.shared.single.bytes, 4);
    expect(share.shared.single.filename, matches(RegExp(r'^kira-ringkasan-\d{8}\.pdf$')));
    expect(share.shared.single.message, contains('bukan diagnosis'));
  });

  testWidgets('gagal membuat PDF menampilkan pesan ramah dan tidak membuka menu bagikan', (tester) async {
    final api = FakeApi()
      ..trends = sampleTrends()
      ..pdfError = ApiException('Ada kendala di server. Coba lagi sebentar lagi ya.', status: 500);
    final share = FakeShare();
    await pumpSummary(tester, api, share: share);
    await tester.tap(find.byKey(const Key('share_pdf')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ada kendala di server'), findsOneWidget);
    expect(share.shared, isEmpty);
  });

  testWidgets('gagal membuka menu bagikan juga ditangani tanpa membuat layar rusak', (tester) async {
    final share = FakeShare()..error = StateError('tidak ada aplikasi');
    await pumpSummary(tester, FakeApi()..trends = sampleTrends(), share: share);
    await tester.tap(find.byKey(const Key('share_pdf')));
    await tester.pumpAndSettle();
    expect(find.textContaining('belum bisa dibagikan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  shareLinkTests();
}

void shareLinkTests() {
  testWidgets('membuat tautan untuk dokter: URL tampil sekali, bisa dibagikan, dan masuk daftar aktif', (tester) async {
    final api = FakeApi();
    final share = FakeShare();
    await pumpSummary(tester, api, share: share);
    final card = find.byKey(const Key('share_links_card'));
    await tester.scrollUntilVisible(card, 300, scrollable: find.byType(Scrollable).first);

    await tester.tap(find.byKey(const Key('valid_30')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create_share_link')));
    await tester.pumpAndSettle();
    expect(api.createdLinks, [(days: 30, validDays: 30)]);
    expect(find.byKey(const Key('fresh_link')), findsOneWidget);
    expect(find.textContaining('https://api.kira.example/s/token-rahasia-1'), findsWidgets);
    expect(find.textContaining('hanya ditampilkan sekarang'), findsOneWidget);

    await tester.tap(find.byKey(const Key('share_link_send')));
    await tester.pumpAndSettle();
    expect(share.texts.single, allOf(contains('https://api.kira.example/s/token-rahasia-1'), contains('bukan diagnosis')));

    expect(find.byKey(const Key('link_link-1')), findsOneWidget);
    expect(find.text('Belum dibuka'), findsOneWidget);
  });

  testWidgets('mencabut tautan menghapusnya dari daftar aktif', (tester) async {
    final api = FakeApi()
      ..shareLinks = [ShareLinkData(id: 'a1', days: 30, expiresAt: DateTime.now().add(const Duration(days: 5)), openCount: 3)];
    await pumpSummary(tester, api);
    final row = find.byKey(const Key('link_a1'));
    await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Dibuka 3 kali'), findsOneWidget);
    await tester.tap(find.byKey(const Key('revoke_a1')));
    await tester.pumpAndSettle();
    expect(api.revokedLinks, ['a1']);
    expect(find.byKey(const Key('link_a1')), findsNothing);
    expect(find.textContaining('dicabut'), findsOneWidget);
  });

  testWidgets('tautan kedaluwarsa atau dicabut tidak muncul di daftar aktif', (tester) async {
    final api = FakeApi()
      ..shareLinks = [
        ShareLinkData(id: 'old', days: 30, expiresAt: DateTime.now().subtract(const Duration(days: 1)), expired: true),
        ShareLinkData(id: 'gone', days: 30, expiresAt: DateTime.now().add(const Duration(days: 1)), revoked: true),
      ];
    await pumpSummary(tester, api);
    expect(find.byKey(const Key('link_old')), findsNothing);
    expect(find.byKey(const Key('link_gone')), findsNothing);
    expect(find.text('Tautan aktif'), findsNothing);
  });

  testWidgets('batas tautan aktif tercapai: pesan server ditampilkan', (tester) async {
    final api = FakeApi()..shareLinkError = ApiException('Sudah ada 5 tautan aktif. Cabut salah satu dulu.', status: 409);
    await pumpSummary(tester, api);
    final button = find.byKey(const Key('create_share_link'));
    await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('Cabut salah satu'), findsOneWidget);
    expect(find.byKey(const Key('fresh_link')), findsNothing);
  });
}
