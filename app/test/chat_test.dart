import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/projection/projection_providers.dart';
import 'package:kira/features/chat/chat_screen.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

Future<void> typeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('chat_input')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('send_button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menyapa dulu, lalu mengirim pesan dan menampilkan balasan', (tester) async {
    final api = FakeApi()..onMessage = (t) async => const ChatReply(reply: 'Sip, sudah kucatat ya.');
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ceritakan makan'), findsOneWidget);
    await typeAndSend(tester, 'tadi siang nasi padang');

    expect(find.text('tadi siang nasi padang'), findsOneWidget);
    expect(find.text('Sip, sudah kucatat ya.'), findsOneWidget);
    expect(api.messages, ['tadi siang nasi padang']);
  });

  testWidgets('pesan kosong atau spasi saja tidak terkirim', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();

    final send = find.byKey(const Key('send_button'));
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('chat_input')), '    ');
    await tester.pump();
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    expect(api.messages, isEmpty);
  });

  testWidgets('gangguan jaringan menampilkan pesan ramah dan bisa dicoba lagi', (tester) async {
    var attempts = 0;
    final api = FakeApi()
      ..onMessage = (t) async {
        attempts++;
        if (attempts == 1) throw ApiException('Tidak bisa terhubung ke server. Cek koneksimu lalu coba lagi.');
        return const ChatReply(reply: 'Berhasil sekarang.');
      };
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();

    await typeAndSend(tester, 'halo');
    expect(find.textContaining('Tidak bisa terhubung'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry_button')));
    await tester.pumpAndSettle();

    expect(find.text('Berhasil sekarang.'), findsOneWidget);
    expect(find.textContaining('Tidak bisa terhubung'), findsNothing);
    expect(attempts, 2);
  });

  testWidgets('tanda bahaya tampil sebagai kartu darurat yang menonjol', (tester) async {
    final api = FakeApi()
      ..onMessage = (t) async => const ChatReply(
            reply: 'Ini bisa jadi tanda bahaya. Segera ke IGD atau Puskesmas terdekat.',
            redFlag: 'symptom',
          );
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    await typeAndSend(tester, 'nyeri dada');

    expect(find.byKey(const Key('emergency_card')), findsOneWidget);
    expect(find.textContaining('Segera ke IGD'), findsOneWidget);
  });

  testWidgets('kartu hasil ekstraksi muncul dan porsi bisa dikoreksi', (tester) async {
    final api = FakeApi()
      ..onMessage = (t) async => ChatReply(
            reply: 'Sudah kucatat.',
            logIds: const ['meal-1'],
            extraction: const ExtractionData(
              items: [FoodEntry(name: 'rendang', portionText: '1 potong', portionG: 70)],
            ),
          );
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    await typeAndSend(tester, 'makan rendang');

    expect(find.byKey(const Key('extraction_card')), findsOneWidget);
    expect(find.text('rendang'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit_item_0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('portion_input')), '35');
    await tester.tap(find.byKey(const Key('portion_save')));
    await tester.pumpAndSettle();

    expect(api.patches.single.id, 'meal-1');
    expect(api.patches.single.items.single, {'name': 'rendang', 'portion_g': 35.0});
  });

  testWidgets('chip saran mengirim kalimat contoh', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('suggestion_0')));
    await tester.pumpAndSettle();
    expect(api.messages, hasLength(1));
  });

  testWidgets('foto dikirim dengan jenis yang dipilih', (tester) async {
    String? sentKind;
    final api = FakeApi()
      ..onPhoto = (kind) async {
        sentKind = kind;
        return const ChatReply(reply: 'Foto struk terbaca.');
      };
    await tester.pumpWidget(testApp(
      const ChatScreen(),
      api: api,
      overrides: [photoPickerOverride(Uint8List.fromList([1, 2, 3]))],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('camera_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo_kind_receipt')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo_source_gallery')));
    await tester.pumpAndSettle();

    expect(sentKind, 'receipt');
    expect(find.text('Foto struk terbaca.'), findsOneWidget);
  });

  testWidgets('check-in yang tersimpan memuat ulang proyeksi', (tester) async {
    final api = FakeApi()
      ..onMessage = (t) async => const ChatReply(reply: 'Sudah kucatat.', logIds: ['log-1']);
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
    await container.read(projectionProvider.future);
    expect(api.projectionCalls, 1);

    await typeAndSend(tester, 'makan rendang');
    await container.read(projectionProvider.future);
    expect(api.projectionCalls, 2);
  });
}
