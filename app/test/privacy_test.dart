import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/features/privacy/privacy_screen.dart';
import 'package:kira/shared/account_models.dart';

import 'support/fakes.dart';

Future<void> pumpPrivacy(WidgetTester tester, FakeApi api, {FakeShare? share, String? token = 'token'}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(
    const PrivacyScreen(),
    api: api,
    token: token,
    overrides: [if (share != null) shareOverride(share)],
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('riwayat akses kosong menjelaskan kapan akan terisi', (tester) async {
    await pumpPrivacy(tester, FakeApi());
    expect(find.byKey(const Key('access_log_card')), findsOneWidget);
    expect(find.textContaining('Belum ada'), findsOneWidget);
  });

  testWidgets('riwayat akses menampilkan siapa, apa, dan kapan', (tester) async {
    final api = FakeApi()
      ..accessLog = [
        AccessEntry(kind: 'share_link', viewer: 'Penerima tautan', at: DateTime(2026, 10, 12, 14, 5), detail: 'Tautan 10/10'),
        AccessEntry(kind: 'family_status', viewer: 'Bu Sari', at: DateTime(2026, 10, 11, 8, 30)),
      ];
    await pumpPrivacy(tester, api);
    expect(find.text('Penerima tautan'), findsOneWidget);
    expect(find.textContaining('Membuka tautan dokter · 12 Okt 2026, 14.05'), findsOneWidget);
    expect(find.text('Bu Sari'), findsOneWidget);
    expect(find.textContaining('Melihat status check-in · 11 Okt 2026, 08.30'), findsOneWidget);
  });

  testWidgets('persetujuan bisa dibaca ulang kapan saja', (tester) async {
    await pumpPrivacy(tester, FakeApi());
    await tester.tap(find.byKey(const Key('tile_consent')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('consent_sheet')), findsOneWidget);
    expect(find.textContaining('UU PDP'), findsOneWidget);
    expect(find.text('Ke mana data pergi'), findsOneWidget);
  });

  testWidgets('unduh data membagikan satu berkas JSON tanpa PIN', (tester) async {
    final api = FakeApi()..exportData = {'format': 1, 'account': {'username': 'raka'}, 'logs': []};
    final share = FakeShare();
    await pumpPrivacy(tester, api, share: share);
    await tester.tap(find.byKey(const Key('tile_export')));
    await tester.pumpAndSettle();
    expect(api.exports, 1);
    expect(share.files, hasLength(1));
    expect(share.files.single.mime, 'application/json');
    expect(share.files.single.filename, matches(RegExp(r'^kira-data-\d{8}\.json$')));
    expect(share.files.single.content, contains('"username": "raka"'));
    expect(share.files.single.content, isNot(contains('pin')));
  });

  testWidgets('unduh data gagal: pesan ramah, bukan crash', (tester) async {
    final api = FakeApi()..exportError = ApiException('Tidak bisa terhubung ke server.');
    await pumpPrivacy(tester, api, share: FakeShare());
    await tester.tap(find.byKey(const Key('tile_export')));
    await tester.pumpAndSettle();
    expect(find.text('Tidak bisa terhubung ke server.'), findsOneWidget);
  });

  testWidgets('ganti PIN: validasi lokal lalu menyimpan sesi baru', (tester) async {
    final api = FakeApi();
    await pumpPrivacy(tester, api);
    await tester.tap(find.byKey(const Key('tile_change_pin')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pin_save')));
    await tester.pumpAndSettle();
    expect(find.text('Isi PIN yang sekarang.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pin_current')), '123456');
    await tester.enterText(find.byKey(const Key('pin_new')), '654321');
    await tester.enterText(find.byKey(const Key('pin_new2')), '111111');
    await tester.tap(find.byKey(const Key('pin_save')));
    await tester.pumpAndSettle();
    expect(find.text('Kedua PIN baru belum sama.'), findsOneWidget);
    expect(api.pinChanges, isEmpty);

    await tester.enterText(find.byKey(const Key('pin_new2')), '654321');
    await tester.tap(find.byKey(const Key('pin_save')));
    await tester.pumpAndSettle();
    expect(api.pinChanges, [(current: '123456', next: '654321')]);
    expect(find.text('PIN sudah diganti.'), findsOneWidget);
  });

  testWidgets('ganti PIN: PIN lama salah menampilkan pesan server', (tester) async {
    final api = FakeApi()..pinChangeError = ApiException('PIN saat ini salah', status: 403);
    await pumpPrivacy(tester, api);
    await tester.tap(find.byKey(const Key('tile_change_pin')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin_current')), '000000');
    await tester.enterText(find.byKey(const Key('pin_new')), '654321');
    await tester.enterText(find.byKey(const Key('pin_new2')), '654321');
    await tester.tap(find.byKey(const Key('pin_save')));
    await tester.pumpAndSettle();
    expect(find.text('PIN saat ini salah'), findsOneWidget);
  });

  testWidgets('hapus akun butuh PIN, menghapus di server, lalu keluar', (tester) async {
    final api = FakeApi();
    await pumpPrivacy(tester, api, token: 'token');
    await tester.tap(find.byKey(const Key('tile_delete')));
    await tester.pumpAndSettle();
    expect(find.text('Hapus akun?'), findsOneWidget);
    expect(find.textContaining('tidak bisa dipulihkan'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Isi PIN-mu untuk melanjutkan.'), findsOneWidget);
    expect(api.deletedAccounts, isEmpty);

    await tester.enterText(find.byKey(const Key('delete_pin')), '123456');
    await tester.tap(find.byKey(const Key('delete_confirm')));
    await tester.pumpAndSettle();
    expect(api.deletedAccounts, ['123456']);
  });

  testWidgets('hapus akun: PIN salah tidak menutup dialog dan tidak keluar', (tester) async {
    final api = FakeApi()..deleteError = ApiException('PIN salah', status: 403);
    await pumpPrivacy(tester, api);
    await tester.tap(find.byKey(const Key('tile_delete')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('delete_pin')), '000000');
    await tester.tap(find.byKey(const Key('delete_confirm')));
    await tester.pumpAndSettle();
    expect(find.text('PIN salah'), findsOneWidget);
    expect(find.text('Hapus akun?'), findsOneWidget);
    expect(api.deletedAccounts, isEmpty);
  });

  test('AccessEntry dan ShareLinkData membaca JSON server', () {
    final e = AccessEntry.fromJson({'kind': 'share_link', 'viewer': 'Penerima tautan', 'detail': null, 'at': '2026-10-12T07:05:00+00:00'});
    expect(e.isShareLink, isTrue);
    final l = ShareLinkData.fromJson({
      'id': 'a', 'days': 30, 'expires_at': '2026-10-20T00:00:00+00:00', 'revoked': false, 'expired': false,
      'open_count': 2, 'last_opened_at': null,
    });
    expect(l.active, isTrue);
    expect(l.url, isNull);
    expect(ShareLinkData.fromJson({'id': 'b', 'days': 7, 'expires_at': '2026-10-20T00:00:00+00:00', 'revoked': true}).active, isFalse);
  });

  test('penanda sesi tidak berubah saat token akses diperbarui diam-diam', () {
    const before = AuthState(loaded: true, token: 'a1', refreshToken: 'r1');
    const after = AuthState(loaded: true, token: 'a1', access: 'a2', refreshToken: 'r2');
    expect(after.token, before.token);
    expect(after.currentAccess, 'a2');
    expect(before.currentAccess, 'a1');
  });
}
