import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/chat/chat_screen.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

Future<void> send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('chat_input')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('send_button')));
  await tester.pumpAndSettle();
}

const gizi = ToolCall(
  name: 'cari_gizi',
  args: {'makanan': 'rendang', 'porsi_gram': 70},
  result: {
    'found': true,
    'name': 'rendang sapi',
    'portion_g': 70,
    'sugar_g': 0.5,
    'sodium_mg': 280,
    'fat_g': 5.5,
    'kcal': 160,
    'sumber': 'TKPI 2017 FP062; gula: estimasi KIRA',
  },
);

const sisa = ToolCall(
  name: 'sisa_target_harian',
  result: {
    'mode': 'prevention',
    'limits': {'sugar_g': 50, 'sodium_mg': 2000, 'fat_g': 67},
    'consumed': {'sugar_g': 38, 'sodium_mg': 900, 'fat_g': 30},
    'remaining': {'sugar_g': 12, 'sodium_mg': 1100, 'fat_g': 37},
  },
);

void main() {
  testWidgets('balasan dengan tool menawarkan "cara KIRA menghitung" dan membukanya', (tester) async {
    final api = FakeApi()
      ..onMessage = (t) async => const ChatReply(reply: 'Boleh satu potong.', toolCalls: [gizi, sisa]);
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    await send(tester, 'boleh rendang?');

    expect(find.byKey(const Key('trace_panel')), findsNothing);
    await tester.tap(find.byKey(const Key('trace_toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trace_panel')), findsOneWidget);
    expect(find.textContaining('rendang sapi'), findsOneWidget);
    expect(find.textContaining('TKPI 2017 FP062'), findsOneWidget);
    expect(find.textContaining('perkiraan KIRA'), findsOneWidget); // gula berstatus estimasi
    expect(find.textContaining('12 g'), findsOneWidget); // sisa gula hari ini
  });

  testWidgets('balasan tanpa tool tidak menampilkan jejak perhitungan', (tester) async {
    final api = FakeApi()..onMessage = (t) async => const ChatReply(reply: 'Halo juga.');
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    await send(tester, 'halo');
    expect(find.byKey(const Key('trace_toggle')), findsNothing);
  });

  testWidgets('makanan yang tidak ditemukan dinyatakan jujur, bukan angka karangan', (tester) async {
    final api = FakeApi()
      ..onMessage = (t) async => const ChatReply(
            reply: 'Makanan itu belum ada di database gizi.',
            toolCalls: [ToolCall(name: 'cari_gizi', args: {'makanan': 'seblak'}, result: {'found': false})],
          );
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    await send(tester, 'seblak');
    await tester.tap(find.byKey(const Key('trace_toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('tidak mengarang'), findsOneWidget);
  });

  testWidgets('tool tak dikenal tetap tampil dengan nama aslinya tanpa membuat layar rusak', (tester) async {
    final api = FakeApi()
      ..onMessage = (t) async => const ChatReply(
            reply: 'Ok.',
            toolCalls: [ToolCall(name: 'alat_baru', args: {'x': 1}, result: 'teks bebas')],
          );
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    await send(tester, 'tes');
    await tester.tap(find.byKey(const Key('trace_toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('alat_baru'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
