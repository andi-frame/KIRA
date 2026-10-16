import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/features/chat/chat_controller.dart';
import 'package:kira/features/chat/chat_screen.dart';
import 'package:kira/features/projection/projection_providers.dart';
import 'package:kira/shared/models.dart';
import 'package:kira/shared/record_models.dart';
import 'package:kira/shared/widgets.dart';

import 'chat_test.dart' show typeAndSend;
import 'support/fakes.dart';

const _geprek = [
  LoggedItem(id: 'a', name: 'Ayam goreng tepung', portionG: 100, kcal: 268, sugarG: 0.5, sodiumMg: 269, fatG: 15.8,
      foodId: 'ayam_goreng_tepung', group: 'Ayam geprek'),
  LoggedItem(id: 'b', name: 'Nasi putih', portionG: 150, kcal: 270, sugarG: 0.2, sodiumMg: 2, fatG: 0.5,
      foodId: 'nasi_putih', group: 'Ayam geprek'),
];

ChatHistoryMessage _msg(String id, String role, String text, {List<MealLog> meals = const [], String? redFlag}) =>
    ChatHistoryMessage(id: id, role: role, text: text, at: DateTime(2026, 10, 16, 9), meals: meals, redFlag: redFlag);

void main() {
  testWidgets('obrolan hari ini dipulihkan dari server beserta kartu catatan makan, tanpa sapaan awal', (tester) async {
    final api = FakeApi()
      ..chatHistory = [
        _msg('1', 'user', 'tadi makan ayam geprek'),
        _msg('2', 'assistant', 'Sudah kucatat ya.', meals: [MealLog(id: 'log1', items: _geprek, mealSlot: 'lunch')]),
      ];
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();

    expect(api.chatHistoryCalls, 1);
    expect(find.text('tadi makan ayam geprek'), findsOneWidget);
    expect(find.text('Sudah kucatat ya.'), findsOneWidget);
    expect(find.byKey(const Key('extraction_card')), findsOneWidget);
    expect(find.text('Ayam goreng tepung'), findsOneWidget);
    expect(find.textContaining('Ceritakan makan'), findsNothing); // sapaan hanya untuk obrolan kosong
    expect(find.byKey(const Key('chat_restoring')), findsNothing);
  });

  testWidgets('tanpa obrolan hari ini sapaan awal tetap muncul', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ceritakan makan'), findsOneWidget);
  });

  testWidgets('gagal memulihkan (tanpa sinyal) tidak menghalangi mulai mengobrol', (tester) async {
    final api = FakeApi()..chatHistoryError = ApiException('Tidak bisa terhubung ke server.');
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ceritakan makan'), findsOneWidget);
    await typeAndSend(tester, 'halo');
    expect(api.messages, ['halo']);
  });

  testWidgets('pesan darurat dipulihkan sebagai kartu darurat', (tester) async {
    final api = FakeApi()
      ..chatHistory = [_msg('1', 'user', 'dadaku sakit'), _msg('2', 'assistant', 'Segera ke IGD.', redFlag: 'chest')];
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    expect(find.text('Segera ke IGD.'), findsOneWidget);
    expect(find.byType(EmergencyCard), findsOneWidget);
  });

  testWidgets('tombol riwayat di kiri atas membuka riwayat hari ini dan bisa menghapusnya', (tester) async {
    final api = FakeApi()
      ..chatHistory = [_msg('1', 'user', 'tadi makan nasi padang'), _msg('2', 'assistant', 'Sudah kucatat.')];
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat_history_button')));
    await tester.pumpAndSettle();
    expect(find.text('Riwayat obrolan hari ini'), findsOneWidget);
    expect(find.textContaining('Satu riwayat untuk satu hari'), findsOneWidget);
    expect(find.text('tadi makan nasi padang'), findsNWidgets(2)); // di obrolan dan di daftar riwayat

    await tester.tap(find.byKey(const Key('chat_clear_today')));
    await tester.pumpAndSettle();
    expect(api.chatClears, 0); // menunggu konfirmasi
    await tester.tap(find.byKey(const Key('chat_clear_confirm')));
    await tester.pumpAndSettle();
    expect(api.chatClears, 1);
    expect(find.text('tadi makan nasi padang'), findsNothing);
    expect(find.textContaining('Ceritakan makan'), findsOneWidget);
  });

  testWidgets('riwayat kosong: tombol hapus nonaktif dan ada keterangan', (tester) async {
    await tester.pumpWidget(testApp(const ChatScreen(), api: FakeApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat_history_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_history_empty')), findsOneWidget);
    expect(tester.widget<TextButton>(find.byKey(const Key('chat_clear_today'))).onPressed, isNull);
  });

  testWidgets('koreksi lewat chat memperbarui kartu yang ada, bukan menambah kartu baru yang tampak dobel', (tester) async {
    final halfItems = [
      for (final i in _geprek) LoggedItem(id: i.id, name: i.name, portionG: i.portionG! / 2, kcal: i.kcal! / 2, group: i.group, foodId: i.foodId),
    ];
    var step = 0;
    final api = FakeApi()
      ..onMessage = (t) async {
        step++;
        return step == 1
            ? ChatReply(
                reply: 'Sudah kucatat.',
                extraction: const ExtractionData(items: [FoodEntry(name: 'ayam geprek')]),
                logIds: const ['log1'],
                meals: [MealLog(id: 'log1', items: _geprek, mealSlot: 'lunch')],
              )
            : ChatReply(
                reply: 'Sudah kuubah jadi setengah porsi.',
                extraction: const ExtractionData(intent: 'correction'),
                logIds: const ['log1'],
                meals: [MealLog(id: 'log1', items: halfItems, mealSlot: 'lunch', halvedGroups: const ['Ayam geprek'], corrected: true)],
              );
      };
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    await typeAndSend(tester, 'makan siang ayam geprek');
    expect(find.textContaining('100 g · 268 kkal'), findsOneWidget);

    await typeAndSend(tester, 'ralat, tadi cuma setengah porsi');
    expect(find.byKey(const Key('extraction_card')), findsOneWidget); // tetap satu kartu
    expect(find.textContaining('50 g · 134 kkal'), findsOneWidget);
    expect(find.text('Porsi biasa'), findsOneWidget); // tombolnya sudah menjadi saklar balik
  });

  testWidgets('koreksi yang menghapus catatan memuat ulang angka turunan walau tanpa id baru', (tester) async {
    final api = FakeApi()
      ..onMessage = (t) async => ChatReply(
            reply: 'Sudah kuhapus.',
            extraction: const ExtractionData(intent: 'correction'),
          );
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
    await container.read(projectionProvider.future);
    final before = api.projectionCalls;
    await typeAndSend(tester, 'hapus catatan makan yang tadi');
    await container.read(projectionProvider.future);
    expect(api.projectionCalls, before + 1);
  });

  testWidgets('hari berganti saat aplikasi dibuka lagi: obrolan hari baru mulai bersih', (tester) async {
    var now = DateTime(2026, 10, 16, 21);
    final api = FakeApi()
      ..chatHistory = [_msg('1', 'user', 'semalam makan'), _msg('2', 'assistant', 'Sudah kucatat.')];
    await tester.pumpWidget(testApp(const ChatScreen(), api: api, overrides: [clockProvider.overrideWithValue(() => now)]));
    await tester.pumpAndSettle();
    expect(find.text('semalam makan'), findsOneWidget);

    now = DateTime(2026, 10, 17, 7);
    api.chatHistory = const []; // server membersihkan obrolan kemarin saat hari berganti
    final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
    await container.read(chatProvider.notifier).syncDay();
    await tester.pumpAndSettle();
    expect(find.text('semalam makan'), findsNothing);
    expect(find.textContaining('Ceritakan makan'), findsOneWidget);
    expect(api.chatHistoryCalls, 2);
  });

  testWidgets('hari yang sama: sinkron hari tidak memuat ulang', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
    await container.read(chatProvider.notifier).syncDay();
    expect(api.chatHistoryCalls, 1);
  });
}
