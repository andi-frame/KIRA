import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/projection/projection_screen.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

Future<void> pumpProjection(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const ProjectionScreen(), api: api));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menampilkan rentang kategori, persentase perkiraan, dan grafik dua kurva', (tester) async {
    await pumpProjection(tester, FakeApi());

    expect(find.byKey(const Key('risk_headline')), findsOneWidget);
    expect(find.textContaining('sedikit meningkat'), findsWidgets);
    expect(find.textContaining('tinggi'), findsWidgets);
    expect(find.textContaining('4'), findsWidgets);
    expect(find.byKey(const Key('risk_chart')), findsOneWidget);
    expect(find.text('Kebiasaan sekarang'), findsOneWidget);
    expect(find.text('Kalau kebiasaan diperbaiki'), findsOneWidget);
  });

  testWidgets('profil belum lengkap menampilkan ajakan, bukan grafik kosong', (tester) async {
    await pumpProjection(tester, FakeApi()..projection = sampleProjection(needsProfile: true, low: 0, high: 26));
    expect(find.byKey(const Key('needs_profile_note')), findsOneWidget);
    expect(find.byKey(const Key('risk_chart')), findsOneWidget);
  });

  testWidgets('rentang lebar mengarahkan ke tab Cek', (tester) async {
    await pumpProjection(tester, FakeApi()); // 9..18 -> selisih 9
    expect(find.byKey(const Key('check_hint')), findsOneWidget);
  });

  testWidgets('rentang sempit tidak menampilkan ajakan cek', (tester) async {
    await pumpProjection(tester, FakeApi()..projection = sampleProjection(low: 13, high: 15));
    expect(find.byKey(const Key('check_hint')), findsNothing);
  });

  testWidgets('menggeser slider beruntun hanya memanggil API sekali setelah 300 ms', (tester) async {
    final api = FakeApi();
    await pumpProjection(tester, api);

    final slider = find.byKey(const Key('sweet_slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.drag(slider, const Offset(150, 0));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(api.whatIfRequests, isEmpty); // masih menunggu jeda
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(api.whatIfRequests, hasLength(1));
    expect(api.whatIfRequests.single.sweetDrinksDeltaPerDay, lessThan(0));
  });

  testWidgets('mengaktifkan bergerak 30 menit mengirim perubahan dan menampilkan dampaknya', (tester) async {
    final api = FakeApi()
      ..onWhatIf = (c) => sampleWhatIf(afterLow: 9, afterHigh: 16);
    await pumpProjection(tester, api);

    final toggle = find.byKey(const Key('active_switch'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(api.whatIfRequests.single.active30min, true);
    expect(find.byKey(const Key('impact_card')), findsOneWidget);
    expect(find.textContaining('Bergerak'), findsWidgets);
  });

  testWidgets('teks tidak pernah memakai "aman" atau "menderita"', (tester) async {
    await pumpProjection(tester, FakeApi());
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => (t.data ?? '').toLowerCase());
    for (final t in texts) {
      expect(t.contains('menderita'), isFalse, reason: t);
      expect(RegExp(r'\baman\b').hasMatch(t), isFalse, reason: t);
    }
  });

  testWidgets('gagal memuat menampilkan pesan ramah dengan tombol coba lagi', (tester) async {
    final api = FakeApi()..projectionError = ApiException('Tidak bisa terhubung ke server. Cek koneksimu lalu coba lagi.');
    await pumpProjection(tester, api);
    expect(find.textContaining('Tidak bisa terhubung'), findsOneWidget);

    api.projectionError = null;
    await tester.tap(find.byKey(const Key('retry_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('risk_chart')), findsOneWidget);
  });

  testWidgets('penjelasan perhitungan menyebut skor yang dipakai dan bukan diagnosis', (tester) async {
    await pumpProjection(tester, FakeApi());
    final link = find.byKey(const Key('how_calculated'));
    await tester.scrollUntilVisible(link, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.textContaining('FINDRISC'), findsOneWidget);
    expect(find.textContaining('bukan diagnosis'), findsOneWidget);
  });

  test('model WhatIfChange hanya mengirim yang diubah', () {
    expect(const WhatIfChange().isEmpty, isTrue);
    expect(const WhatIfChange(active30min: true).toJson()['active_30min'], true);
    expect(const WhatIfChange(sweetDrinksDeltaPerDay: -2).toJson()['sweet_drinks_delta_per_day'], -2);
  });

  testWidgets('penjelasan menyebut sumber angka dan batasannya dengan jujur', (tester) async {
    await pumpProjection(tester, FakeApi());
    final link = find.byKey(const Key('how_calculated'));
    await tester.scrollUntilVisible(link, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.textContaining('Norwegia'), findsOneWidget);
    expect(find.textContaining('interpolasi'), findsOneWidget);
    expect(find.textContaining('TKPI'), findsOneWidget);
    expect(find.textContaining('Permenkes 30/2013'), findsOneWidget);
  });
}
