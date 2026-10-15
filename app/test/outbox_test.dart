import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/core/outbox.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/features/chat/chat_screen.dart';
import 'package:kira/features/check/check_screen.dart';
import 'package:kira/shared/account_models.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

final offline = ApiException('Tidak bisa terhubung ke server. Cek koneksimu lalu coba lagi.');

ProviderContainer containerFor(FakeApi api, MemoryPrefsStore prefs, {String token = 'token'}) {
  final c = ProviderContainer(overrides: [
    apiProvider.overrideWithValue(api),
    tokenStoreProvider.overrideWithValue(MemoryTokenStore(token)),
    prefsStoreProvider.overrideWithValue(prefs),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> pumpChat(WidgetTester tester, FakeApi api, MemoryPrefsStore prefs) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const ChatScreen(), api: api, prefs: prefs));
  await tester.pumpAndSettle();
}

Future<void> typeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('chat_input')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('send_button')));
  await tester.pumpAndSettle();
}

void main() {
  group('pesan chat tanpa sinyal', () {
    testWidgets('tersimpan di ponsel, ditandai menunggu, dan disertai pesan darurat (119)', (tester) async {
      final api = FakeApi()..networkError = offline;
      final prefs = MemoryPrefsStore();
      await pumpChat(tester, api, prefs);
      await typeAndSend(tester, 'tadi makan nasi padang');

      expect(find.textContaining('Menunggu sinyal'), findsOneWidget);
      expect(find.textContaining('tersimpan di ponsel'), findsOneWidget);
      expect(find.textContaining('119'), findsOneWidget);
      expect(find.textContaining('Tidak bisa terhubung'), findsNothing); // bukan error buntu
      final saved = jsonDecode((await prefs.read('outbox_v1'))!) as List;
      expect(saved, hasLength(1));
      expect(saved.single['payload']['text'], 'tadi makan nasi padang');
    });

    testWidgets('begitu sinyal kembali: terkirim dengan kunci yang sama, balasan KIRA muncul, antrean kosong', (tester) async {
      final api = FakeApi()..networkError = offline;
      final prefs = MemoryPrefsStore();
      await pumpChat(tester, api, prefs);
      await typeAndSend(tester, 'tadi makan nasi padang');
      final queuedId = (jsonDecode((await prefs.read('outbox_v1'))!) as List).single['id'] as String;

      api.networkError = null;
      final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
      await container.read(outboxProvider.notifier).flush();
      await tester.pumpAndSettle();

      expect(api.messages, ['tadi makan nasi padang']);
      expect(api.messageKeys, [queuedId]); // kunci sama dengan percobaan pertama: server tahu ini kiriman ulang
      expect(find.textContaining('Menunggu sinyal'), findsNothing);
      expect(find.text('tadi makan nasi padang'), findsOneWidget);
      expect(find.text('Sip, sudah kucatat.'), findsOneWidget);
      expect(await prefs.read('outbox_v1'), isNull);
    });

    testWidgets('pesan yang berhasil terkirim memakai kunci agar aman diulang', (tester) async {
      final api = FakeApi();
      await pumpChat(tester, api, MemoryPrefsStore());
      await typeAndSend(tester, 'halo');
      expect(api.messageKeys.single, isNotNull);
      expect(api.messageKeys.single!.length, greaterThanOrEqualTo(8));
    });

    testWidgets('error server (bukan sinyal) tetap error biasa dengan tombol coba lagi, tidak masuk antrean', (tester) async {
      final api = FakeApi()..onMessage = (_) async => throw ApiException('Ada kendala di server.', status: 500);
      final prefs = MemoryPrefsStore();
      await pumpChat(tester, api, prefs);
      await typeAndSend(tester, 'halo');
      expect(find.text('Ada kendala di server.'), findsOneWidget);
      expect(await prefs.read('outbox_v1'), isNull);
    });
  });

  group('OutboxController', () {
    test('dimuat kembali setelah aplikasi dibuka ulang', () async {
      final prefs = MemoryPrefsStore();
      final first = containerFor(FakeApi(), prefs);
      first.read(outboxProvider.notifier).enqueueMessage('catatan satu');
      first.read(outboxProvider.notifier).enqueueResult('blood_pressure', {'sys': 130, 'dia': 85});

      final second = containerFor(FakeApi(), prefs);
      await second.read(outboxProvider.notifier).load();
      final items = second.read(outboxProvider);
      expect(items.map((i) => i.kind), [OutboxKind.message, OutboxKind.result]);
      expect(items.first.text, 'catatan satu');
    });

    test('dikirim berurutan; hasil cek memakai kunci kirimannya', () async {
      final api = FakeApi();
      final c = containerFor(api, MemoryPrefsStore());
      final ctl = c.read(outboxProvider.notifier);
      ctl.enqueueMessage('pertama');
      final res = ctl.enqueueResult('fasting_glucose', {'mg_dl': 98});
      ctl.enqueueMessage('ketiga');
      await ctl.flush();
      expect(api.messages, ['pertama', 'ketiga']);
      expect(api.results.single.kind, 'fasting_glucose');
      expect(api.resultKeys, [res.id]);
      expect(c.read(outboxProvider), isEmpty);
    });

    test('masalah jaringan atau server menghentikan pengiriman dan menyimpan sisanya', () async {
      final api = FakeApi()..networkError = offline;
      final c = containerFor(api, MemoryPrefsStore());
      final ctl = c.read(outboxProvider.notifier);
      ctl.enqueueMessage('satu');
      ctl.enqueueMessage('dua');
      await ctl.flush();
      expect(c.read(outboxProvider), hasLength(2));

      api
        ..networkError = null
        ..onMessage = (_) async => throw ApiException('Server sibuk', status: 503);
      await ctl.flush();
      expect(c.read(outboxProvider), hasLength(2)); // 5xx dicoba lagi nanti
      expect(api.messages, ['satu']); // berhenti di yang pertama, urutan terjaga
    });

    test('ditolak server (4xx) dibuang dan dilaporkan, yang lain tetap dikirim', () async {
      final api = FakeApi()
        ..onMessage = (t) async {
          if (t == 'buruk') throw ApiException('Pesan tidak boleh kosong', status: 422);
          return const ChatReply(reply: 'oke');
        };
      final c = containerFor(api, MemoryPrefsStore());
      final ctl = c.read(outboxProvider.notifier);
      final events = <OutboxEvent>[];
      ctl.events.listen(events.add);
      ctl.enqueueMessage('buruk');
      ctl.enqueueMessage('baik');
      await ctl.flush();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(outboxProvider), isEmpty);
      expect(events.map((e) => e.ok), [false, true]);
      expect(events.first.error, 'Pesan tidak boleh kosong');
    });

    test('keluar atau ganti akun mengosongkan antrean (tidak bocor ke akun lain)', () async {
      final prefs = MemoryPrefsStore();
      final c = containerFor(FakeApi(), prefs);
      await c.read(authProvider.notifier).setTokens(const AuthTokens('akun-a', 'r'));
      c.read(outboxProvider.notifier).enqueueMessage('rahasia akun A');
      expect(c.read(outboxProvider), hasLength(1));
      await c.read(authProvider.notifier).setTokens(const AuthTokens('akun-b', 'r'));
      expect(c.read(outboxProvider), isEmpty);
      expect(await prefs.read('outbox_v1'), isNull);
    });

    test('berkas antrean rusak dibuang, bukan membuat aplikasi gagal', () async {
      final prefs = MemoryPrefsStore();
      await prefs.write('outbox_v1', '{bukan json');
      final c = containerFor(FakeApi(), prefs);
      await c.read(outboxProvider.notifier).load();
      expect(c.read(outboxProvider), isEmpty);
      expect(await prefs.read('outbox_v1'), isNull);
    });
  });

  group('hasil cek tanpa sinyal', () {
    testWidgets('tersimpan di ponsel dengan pesan darurat; dikirim saat tersambung', (tester) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final api = FakeApi()..networkError = offline;
      final prefs = MemoryPrefsStore();
      await tester.pumpWidget(testApp(const CheckScreen(), api: api, prefs: prefs, overrides: [locationOverride()]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('enter_result_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('glucose_input')), '98');
      await tester.tap(find.byKey(const Key('result_save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('result_queued')), findsOneWidget);
      expect(find.textContaining('119'), findsOneWidget);
      expect(find.byKey(const Key('result_error')), findsNothing);
      final saved = jsonDecode((await prefs.read('outbox_v1'))!) as List;
      expect(saved.single['payload']['kind'], 'fasting_glucose');

      api.networkError = null;
      final container = ProviderScope.containerOf(tester.element(find.byType(CheckScreen)));
      await container.read(outboxProvider.notifier).flush();
      expect(api.results.single.kind, 'fasting_glucose');
      expect(api.results.single.value, {'mg_dl': 98.0});
      expect(api.resultKeys.single, saved.single['id']);
    });
  });
}
