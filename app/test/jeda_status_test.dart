import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/features/jeda/jeda_bridge.dart';
import 'package:kira/features/jeda/jeda_models.dart';
import 'package:kira/features/jeda/jeda_screen.dart';
import 'package:kira/features/jeda/jeda_status.dart';

import 'jeda_test.dart' show FakeJedaBridge, allowed;
import 'support/fakes.dart';

JedaDiagnostics diag({
  bool alive = true,
  String code = 'ready',
  List<String> kinds = const ['night'],
  String reason = '',
  String error = '',
  bool battery = true,
  String maker = 'samsung',
  String? front = 'Instagram',
  String? guarded,
}) =>
    JedaDiagnostics(
      serviceAlive: alive,
      lastTickAt: DateTime.now().subtract(const Duration(seconds: 2)),
      lastFrontLabel: front,
      lastFrontAt: front == null ? null : DateTime.now().subtract(const Duration(minutes: 3)),
      lastGuardedLabel: guarded,
      lastGuardedAt: guarded == null ? null : DateTime.now().subtract(const Duration(minutes: 3)),
      lastReason: reason,
      lastError: error,
      nowCode: code,
      nowKinds: kinds,
      batteryIgnored: battery,
      manufacturer: maker,
    );

Future<FakeJedaBridge> pump(WidgetTester tester, JedaDiagnostics? d, {bool perms = true}) async {
  tester.view.physicalSize = const Size(900, 6000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final prefs = MemoryPrefsStore();
  await prefs.write('jeda_v1', const JedaSettings(enabled: true, apps: ['com.instagram.android']).toJson());
  final bridge = FakeJedaBridge(perms: perms ? allowed : const JedaPermissions())..diag = d;
  await tester.pumpWidget(testApp(const JedaScreen(), prefs: prefs, overrides: [jedaBridgeProvider.overrideWithValue(bridge)]));
  await tester.pumpAndSettle();
  return bridge;
}

String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  const s = JedaSettings(enabled: true, apps: ['com.instagram.android']);

  group('kata-kata status (fungsi murni)', () {
    test('tiap kode "sekarang" punya penjelasan yang menyebut sebabnya', () {
      expect(nowExplanation(diag(code: 'ready', kinds: ['night', 'fact']), s), allOf(contains('waktunya tidur'), contains('fun fact')));
      expect(nowExplanation(diag(code: 'off'), s), contains('mati'));
      expect(nowExplanation(diag(code: 'no_apps'), s), contains('dicentang'));
      expect(nowExplanation(diag(code: 'skip_day'), s), contains('04.00'));
      expect(nowExplanation(diag(code: 'no_content'), s), contains('sinyal'));
      expect(nowExplanation(diag(code: 'cap_reached'), s), contains('tiga kali'));
      expect(nowExplanation(diag(code: 'already_logged'), s), contains('sudah tercatat'));
    });

    test('masa bebas menyebut jamnya dan jalan keluarnya', () {
      final d = JedaDiagnostics(nowCode: 'grace', graceUntil: DateTime(2026, 10, 16, 21, 45));
      final t = nowExplanation(d, s);
      expect(t, allOf(contains('21.45'), contains('bebas buka sosmed selama')));
    });

    test('di luar jam kartu: menyebut jam-jam kartu dan menawarkan fun fact bila belum dinyalakan', () {
      final off = nowExplanation(diag(code: 'outside_window'), s);
      expect(off, allOf(contains('05.00'), contains('19.00'), contains('21.30'), contains('Fun fact')));
      expect(nowExplanation(diag(code: 'outside_window'), s.copyWith(funFact: true)), isNot(contains('Nyalakan')));
    });

    test('alasan terakhir: kartu gagal dipasang menyebut galatnya, kode tak dikenal tidak disembunyikan', () {
      expect(lastReasonText(diag(reason: 'overlay_failed', error: 'BadTokenException')), allOf(contains('gagal'), contains('BadTokenException')));
      expect(lastReasonText(diag(reason: 'no_overlay_permission')), contains('Tampil di atas aplikasi lain'));
      expect(lastReasonText(diag(reason: 'shown')), 'Kartu tampil.');
      expect(lastReasonText(diag(reason: 'kode_baru')), 'kode_baru');
      expect(lastReasonText(diag(reason: '')), '');
    });

    test('petunjuk baterai hanya bila KIRA belum dikecualikan, dan sesuai merek', () {
      expect(batteryHint(diag(battery: true)), isNull);
      expect(batteryHint(diag(battery: false, maker: 'xiaomi')), contains('Mulai otomatis'));
      expect(batteryHint(diag(battery: false, maker: 'samsung')), contains('Aplikasi tidur'));
      expect(batteryHint(diag(battery: false, maker: 'vivo')), contains('Konsumsi daya latar'));
      expect(batteryHint(diag(battery: false, maker: 'lainnya')), isNot(contains(' Di ')));
    });

    test('"berapa lama lalu" ditulis dengan kata', () {
      final now = DateTime(2026, 10, 16, 12);
      expect(ago(null, now), 'belum pernah');
      expect(ago(now.subtract(const Duration(seconds: 2)), now), 'baru saja');
      expect(ago(now.subtract(const Duration(seconds: 30)), now), '30 detik lalu');
      expect(ago(now.subtract(const Duration(minutes: 5)), now), '5 menit lalu');
      expect(ago(now.subtract(const Duration(hours: 3)), now), '3 jam lalu');
      expect(ago(now.subtract(const Duration(days: 2)), now), '2 hari lalu');
    });

    test('diagnostik dari Android dibaca, nilai kosong jadi aman', () {
      final d = JedaDiagnostics.fromMap({
        'service_alive': true, 'last_tick_at': DateTime.now().millisecondsSinceEpoch, 'last_front_label': 'X',
        'now_code': 'outside_window', 'now_kinds': <Object?>[], 'battery_ignored': false, 'manufacturer': 'Xiaomi', 'sdk': 35,
      });
      expect((d.serviceAlive, d.nowCode, d.batteryIgnored, d.manufacturer, d.sdk), (true, 'outside_window', false, 'xiaomi', 35));
      final empty = JedaDiagnostics.fromMap(const {});
      expect((empty.serviceAlive, empty.nowCode, empty.lastTickAt, empty.batteryIgnored), (false, 'off', null, true));
    });
  });

  group('layar status', () {
    testWidgets('layanan berjalan dan siap: ditulis hijau dengan jenis kartunya', (tester) async {
      await pump(tester, diag(code: 'ready', kinds: ['night'], guarded: 'Instagram', reason: 'shown'));
      expect(text(tester, 'jeda_status_service'), contains('Layanan berjalan'));
      expect(text(tester, 'jeda_status_front'), contains('Instagram'));
      expect(text(tester, 'jeda_status_guarded'), contains('Kartu tampil.'));
      expect(text(tester, 'jeda_status_now'), contains('waktunya tidur'));
      expect(find.byKey(const Key('jeda_status_battery')), findsNothing);
    });

    testWidgets('layanan mati padahal izin lengkap: dijelaskan penyebab yang paling mungkin', (tester) async {
      await pump(tester, diag(alive: false));
      expect(text(tester, 'jeda_status_service'), allOf(contains('TIDAK berjalan'), contains('penghemat baterai')));
    });

    testWidgets('izin belum lengkap: dikatakan layanan belum berjalan karena izin', (tester) async {
      await pump(tester, diag(alive: false), perms: false);
      expect(text(tester, 'jeda_status_service'), contains('izin belum lengkap'));
    });

    testWidgets('belum ada aplikasi terdeteksi: mengarahkan ke izin akses penggunaan', (tester) async {
      await pump(tester, diag(front: null));
      expect(text(tester, 'jeda_status_front'), contains('Akses penggunaan'));
      expect(find.byKey(const Key('jeda_status_guarded')), findsNothing);
    });

    testWidgets('di luar jam kartu: dijelaskan, dengan jam-jamnya', (tester) async {
      await pump(tester, diag(code: 'outside_window', guarded: 'Instagram', reason: 'outside_window'));
      expect(text(tester, 'jeda_status_now'), contains('di luar jam kartu terjadwal'));
      expect(text(tester, 'jeda_status_guarded'), contains('di luar jam kartu terjadwal'));
    });

    testWidgets('penghemat baterai aktif: ada peringatan dan tombol membuka pengaturannya', (tester) async {
      final bridge = await pump(tester, diag(battery: false, maker: 'xiaomi'));
      expect(text(tester, 'jeda_status_battery'), contains('Xiaomi'));
      await tester.ensureVisible(find.byKey(const Key('jeda_open_battery')));
      await tester.tap(find.byKey(const Key('jeda_open_battery')));
      await tester.pump();
      expect(bridge.batteryOpened, 1);
    });

    testWidgets('galat terakhir ditampilkan apa adanya', (tester) async {
      await pump(tester, diag(error: 'SecurityException: contoh'));
      expect(text(tester, 'jeda_status_error'), contains('SecurityException: contoh'));
    });

    testWidgets('tanpa diagnostik (platform tanpa dukungan): kartu status tidak tampil', (tester) async {
      await pump(tester, null);
      expect(find.byKey(const Key('jeda_status')), findsNothing);
    });

    testWidgets('tombol muat ulang mengambil status baru', (tester) async {
      final bridge = await pump(tester, diag(code: 'ready'));
      bridge.diag = diag(code: 'skip_day');
      await tester.ensureVisible(find.byKey(const Key('jeda_status_refresh')));
      await tester.tap(find.byKey(const Key('jeda_status_refresh')));
      await tester.pumpAndSettle();
      expect(text(tester, 'jeda_status_now'), contains('04.00'));
    });
  });
}
