import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/features/health/health_screen.dart';
import 'package:kira/features/health/health_source.dart';
import 'package:kira/features/health/health_sync.dart';

import 'support/fakes.dart';

Future<void> pumpHealth(WidgetTester tester, FakeApi api, FakeHealthSource source, {PrefsStore? prefs}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const HealthScreen(), api: api, overrides: [healthOverride(source)], prefs: prefs, token: 't'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menjelaskan apa yang dibaca, dasar perhitungan menit aktif, dan bahwa bisa dimatikan', (tester) async {
    await pumpHealth(tester, FakeApi(), FakeHealthSource());
    expect(find.textContaining('hanya membaca'), findsOneWidget);
    expect(find.textContaining('100 langkah per menit'), findsOneWidget);
    expect(find.textContaining('Tudor-Locke'), findsOneWidget);
    expect(find.byKey(const Key('health_connect_button')), findsOneWidget);
    expect(find.byKey(const Key('health_disable_button')), findsNothing);
  });

  testWidgets('menghubungkan: izin diminta, data dibaca lalu dikirim ke server, status sinkron tampil', (tester) async {
    final api = FakeApi();
    final source = FakeHealthSource();
    await pumpHealth(tester, api, source);
    await tester.tap(find.byKey(const Key('health_connect_button')));
    await tester.pumpAndSettle();

    expect(source.accessRequests, 1);
    expect(api.passiveBatches, hasLength(1));
    expect(api.passiveBatches.single.steps.single.count, 1100);
    expect(api.passiveBatches.single.sleep, hasLength(1));
    expect(find.byKey(const Key('health_sync_button')), findsOneWidget);
    expect(find.textContaining('Terakhir sinkron'), findsOneWidget);
    expect(find.byKey(const Key('health_connect_button')), findsNothing);
  });

  testWidgets('izin ditolak: tidak ada yang dibaca atau dikirim', (tester) async {
    final api = FakeApi();
    final source = FakeHealthSource(grant: false);
    await pumpHealth(tester, api, source);
    await tester.tap(find.byKey(const Key('health_connect_button')));
    await tester.pumpAndSettle();

    expect(source.reads, 0);
    expect(api.passiveBatches, isEmpty);
    expect(find.textContaining('Izin belum diberikan'), findsOneWidget);
    expect(find.byKey(const Key('health_connect_button')), findsOneWidget);
  });

  testWidgets('Health Connect belum terpasang atau tidak didukung dijelaskan, tanpa meminta izin', (tester) async {
    final source = FakeHealthSource(status: HealthAvailability.notInstalled);
    await pumpHealth(tester, FakeApi(), source);
    await tester.tap(find.byKey(const Key('health_connect_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Play Store'), findsOneWidget);
    expect(source.accessRequests, 0);

    source.status = HealthAvailability.unsupported;
    await tester.tap(find.byKey(const Key('health_connect_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('hanya tersedia di aplikasi Android'), findsOneWidget);
  });

  testWidgets('belum ada data di Health Connect: pesan jelas dan tidak ada panggilan ke server', (tester) async {
    final api = FakeApi();
    await pumpHealth(tester, api, FakeHealthSource(steps: [], sleep: []));
    await tester.tap(find.byKey(const Key('health_connect_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Belum ada data langkah atau tidur'), findsOneWidget);
    expect(api.passiveBatches, isEmpty);
  });

  testWidgets('gagal kirim ke server tampil sebagai pesan ramah dan tetap bisa dicoba lagi', (tester) async {
    final api = FakeApi()..passiveError = ApiException('Tidak bisa terhubung ke server.');
    await pumpHealth(tester, api, FakeHealthSource());
    await tester.tap(find.byKey(const Key('health_connect_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tidak bisa terhubung'), findsOneWidget);
    expect(find.byKey(const Key('health_sync_button')), findsOneWidget);

    api.passiveError = null;
    await tester.tap(find.byKey(const Key('health_sync_button')));
    await tester.pumpAndSettle();
    expect(api.passiveBatches, hasLength(1));
  });

  testWidgets('mematikan menghapus data dari server setelah konfirmasi, dan sinkron tidak berjalan lagi', (tester) async {
    final api = FakeApi();
    final prefs = MemoryPrefsStore();
    await pumpHealth(tester, api, FakeHealthSource(), prefs: prefs);
    await tester.tap(find.byKey(const Key('health_connect_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('health_disable_button')));
    await tester.pumpAndSettle();
    expect(api.deletedPassive, 0); // menunggu konfirmasi
    await tester.tap(find.byKey(const Key('health_disable_confirm')));
    await tester.pumpAndSettle();

    expect(api.deletedPassive, 1);
    expect(find.byKey(const Key('health_connect_button')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('health_message'))).data, contains('dihapus dari KIRA'));
    expect(await prefs.read('health_enabled'), isNull);
  });

  testWidgets('batal pada konfirmasi tidak menghapus apa pun', (tester) async {
    final api = FakeApi();
    await pumpHealth(tester, api, FakeHealthSource());
    await tester.tap(find.byKey(const Key('health_connect_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('health_disable_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(api.deletedPassive, 0);
    expect(find.byKey(const Key('health_sync_button')), findsOneWidget);
  });

  testWidgets('sinkron otomatis hanya jika sudah dinyalakan dan terakhir lebih dari 6 jam lalu', (tester) async {
    final api = FakeApi();
    final source = FakeHealthSource();
    final prefs = MemoryPrefsStore();
    await prefs.write('health_enabled', '1');
    await prefs.write('health_last_sync', DateTime.now().subtract(const Duration(hours: 7)).toIso8601String());
    await pumpHealth(tester, api, source, prefs: prefs);
    final container = ProviderScope.containerOf(tester.element(find.byType(HealthScreen)));

    await container.read(healthSyncProvider.notifier).syncIfDue();
    expect(api.passiveBatches, hasLength(1));
    await container.read(healthSyncProvider.notifier).syncIfDue(); // baru saja: tidak mengulang
    expect(api.passiveBatches, hasLength(1));
  });

  testWidgets('sinkron otomatis tidak jalan bila pengguna belum menyalakannya', (tester) async {
    final api = FakeApi();
    await pumpHealth(tester, api, FakeHealthSource());
    final container = ProviderScope.containerOf(tester.element(find.byType(HealthScreen)));
    await container.read(healthSyncProvider.notifier).syncIfDue();
    expect(api.passiveBatches, isEmpty);
  });
}
