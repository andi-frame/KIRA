import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/chat/chat_screen.dart';
import 'package:kira/shared/models.dart';

import 'chat_test.dart' show typeAndSend;
import 'support/fakes.dart';

const _geprek = [
  LoggedItem(id: 'a', name: 'Ayam goreng tepung', portionG: 100, kcal: 268, sugarG: 0.5, sodiumMg: 269, fatG: 15.8,
      foodId: 'ayam_goreng_tepung', group: 'Ayam geprek'),
  LoggedItem(id: 'b', name: 'Nasi putih', portionG: 150, kcal: 270, sugarG: 0.2, sodiumMg: 2, fatG: 0.5,
      foodId: 'nasi_putih', group: 'Ayam geprek'),
  LoggedItem(id: 'c', name: 'Sambal bawang', portionG: 25, kcal: 33, sugarG: 1, sodiumMg: 225, fatG: 2.5,
      foodId: 'sambal_bawang', group: 'Ayam geprek'),
  LoggedItem(id: 'd', name: 'Timun', portionG: 30, kcal: 2.4, sugarG: 0.5, sodiumMg: 0.6, fatG: 0.1,
      foodId: 'timun', group: 'Ayam geprek'),
];

const _extraction = ExtractionData(items: [FoodEntry(name: 'ayam geprek')]);

ChatReply _reply(List<LoggedItem> items) => ChatReply(
      reply: 'Sudah kucatat.',
      extraction: _extraction,
      logIds: const ['log1'],
      meals: [MealLog(id: 'log1', items: items)],
    );

Future<FakeApi> _send(WidgetTester tester, List<LoggedItem> items) async {
  final api = FakeApi()..onMessage = (t) async => _reply(items);
  await tester.pumpWidget(testApp(const ChatScreen(), api: api));
  await tester.pumpAndSettle();
  await typeAndSend(tester, 'makan ayam geprek');
  return api;
}

void main() {
  testWidgets('hidangan tampil terkelompok dengan komponen, gizi tiap komponen, dan total', (tester) async {
    await _send(tester, _geprek);

    expect(find.byKey(const Key('meal_group_0')), findsOneWidget);
    expect(find.text('Ayam geprek'), findsOneWidget);
    for (final name in ['Ayam goreng tepung', 'Nasi putih', 'Sambal bawang', 'Timun']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.textContaining('100 g · 268 kkal · gula 0,5 g, natrium 269 mg, lemak 16 g'), findsOneWidget);
    // total = jumlah komponen, ditulis dengan kata
    final total = tester.widget<Text>(find.byKey(const Key('group_total_0'))).data!;
    expect(total, startsWith('Total: 573 kkal, gula 2,2 g, natrium 497 mg, lemak 19 g'));
    expect(find.textContaining('Perkiraan resep'), findsOneWidget);
  });

  testWidgets('setengah porsi menskalakan seluruh hidangan lewat satu koreksi', (tester) async {
    final api = await _send(tester, _geprek);
    api.patchResult = MealLog(id: 'log1', corrected: true, items: [
      for (final i in _geprek)
        LoggedItem(id: i.id, name: i.name, portionG: i.portionG! / 2, kcal: i.kcal! / 2, sugarG: i.sugarG! / 2,
            sodiumMg: i.sodiumMg! / 2, fatG: i.fatG! / 2, foodId: i.foodId, group: i.group),
    ]);

    await tester.tap(find.byKey(const Key('halve_group_0')));
    await tester.pumpAndSettle();

    // Saklar: dikirim sebagai half=true (bukan scale), supaya server yang memegang keadaannya.
    expect(api.patchScales.single, (scale: null, group: 'Ayam geprek'));
    expect(api.patchFields.single.fields, {'half': true, 'group': 'Ayam geprek'});
    expect(find.textContaining('50 g · 134 kkal'), findsOneWidget); // kartu memakai hasil server
  });

  testWidgets('setengah porsi adalah saklar: ketukan kedua mengembalikan ke porsi biasa, bukan menurun lagi', (tester) async {
    final api = await _send(tester, _geprek);
    MealLog halved(bool on) => MealLog(
          id: 'log1',
          corrected: true,
          halvedGroups: on ? const ['Ayam geprek'] : const [],
          items: [
            for (final i in _geprek)
              LoggedItem(id: i.id, name: i.name, portionG: on ? i.portionG! / 2 : i.portionG, kcal: on ? i.kcal! / 2 : i.kcal,
                  foodId: i.foodId, group: i.group),
          ],
        );
    expect(find.text('Setengah porsi'), findsOneWidget);
    expect(find.text('Porsi biasa'), findsNothing);

    api.patchResult = halved(true);
    await tester.tap(find.byKey(const Key('halve_group_0')));
    await tester.pumpAndSettle();
    expect(find.text('Porsi biasa'), findsOneWidget);
    expect(find.text('Setengah porsi'), findsNothing);
    expect(find.textContaining('Sekarang setengah porsi'), findsOneWidget);

    api.patchResult = halved(false);
    await tester.tap(find.byKey(const Key('halve_group_0')));
    await tester.pumpAndSettle();
    expect(api.patchFields.map((p) => p.fields['half']), [true, false]); // naik-turun, bukan setengah dua kali
    expect(find.text('Setengah porsi'), findsOneWidget);
    expect(find.textContaining('150 g'), findsOneWidget);
  });

  testWidgets('waktu makan yang hanya ditebak ditanyakan dengan pilihan satu ketukan', (tester) async {
    final api = FakeApi()
      ..onMessage = (t) async => ChatReply(
            reply: 'Sudah kucatat. Ini makan siang atau selingan?',
            extraction: _extraction,
            logIds: const ['log1'],
            meals: [MealLog(id: 'log1', items: _geprek, mealSlot: 'snack', slotConfirmed: false)],
          );
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    await typeAndSend(tester, 'aku sudah makan nasi dengan ayam katsu');

    expect(find.byKey(const Key('slot_question')), findsOneWidget);
    expect(find.textContaining('menebak selingan'), findsOneWidget);
    api.patchResult = MealLog(id: 'log1', items: _geprek, mealSlot: 'lunch', slotConfirmed: true, corrected: true);
    await tester.tap(find.byKey(const Key('slot_lunch')));
    await tester.pumpAndSettle();

    expect(api.patchFields.single.fields, {'meal_slot': 'lunch'});
    expect(find.byKey(const Key('slot_question')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('slot_label'))).data, 'Makan siang');
  });

  testWidgets('waktu makan yang sudah pasti tidak ditanyakan tetapi bisa diubah', (tester) async {
    final api = FakeApi()
      ..onMessage = (t) async => ChatReply(
            reply: 'Sudah kucatat.',
            extraction: _extraction,
            logIds: const ['log1'],
            meals: [MealLog(id: 'log1', items: _geprek, mealSlot: 'lunch')],
          );
    await tester.pumpWidget(testApp(const ChatScreen(), api: api));
    await tester.pumpAndSettle();
    await typeAndSend(tester, 'makan siang ayam geprek');
    expect(find.byKey(const Key('slot_question')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('slot_label'))).data, 'Makan siang');

    api.patchResult = MealLog(id: 'log1', items: _geprek, mealSlot: 'dinner', corrected: true);
    await tester.tap(find.byKey(const Key('slot_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Makan malam').last);
    await tester.pumpAndSettle();
    expect(api.patchFields.single.fields, {'meal_slot': 'dinner'});
  });

  testWidgets('hapus catatan dari kartu meminta konfirmasi lalu melepas kartunya', (tester) async {
    final api = await _send(tester, _geprek);
    await tester.ensureVisible(find.byKey(const Key('delete_log')));
    await tester.tap(find.byKey(const Key('delete_log')));
    await tester.pumpAndSettle();
    expect(api.deletedLogs, isEmpty); // belum: menunggu konfirmasi
    await tester.tap(find.byKey(const Key('delete_log_confirm')));
    await tester.pumpAndSettle();
    expect(api.deletedLogs, ['log1']);
    expect(find.byKey(const Key('extraction_card')), findsNothing);
  });

  testWidgets('ubah gram satu komponen mengirim semua item dengan food_id dan kelompoknya', (tester) async {
    final api = await _send(tester, _geprek);
    await tester.tap(find.byKey(const Key('edit_item_b')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('portion_input')), '75');
    await tester.tap(find.byKey(const Key('portion_save')));
    await tester.pumpAndSettle();

    final sent = api.patches.single.items;
    expect(sent, hasLength(4));
    expect(sent[1], {'name': 'Nasi putih', 'portion_g': 75.0, 'food_id': 'nasi_putih', 'group': 'Ayam geprek'});
    expect(sent[0]['portion_g'], 100);
  });

  testWidgets('hapus komponen ("tanpa nasi") tidak mengirim komponen itu', (tester) async {
    final api = await _send(tester, _geprek);
    await tester.tap(find.byKey(const Key('remove_item_b')));
    await tester.pumpAndSettle();
    expect(api.patches.single.items.map((i) => i['food_id']), isNot(contains('nasi_putih')));
    expect(api.patches.single.items, hasLength(3));
  });

  testWidgets('komponen tak dikenal ditandai belum terhitung dan bisa dicari', (tester) async {
    const unknown = LoggedItem(id: 'x', name: 'cakalang suwir', portionG: 50, group: 'Nasi bakar');
    const rice = LoggedItem(id: 'y', name: 'Nasi putih', portionG: 150, kcal: 270, sugarG: 0.2, sodiumMg: 2, fatG: 0.5,
        foodId: 'nasi_putih', group: 'Nasi bakar');
    final api = await _send(tester, const [rice, unknown]);
    api.foodSuggestions = const [
      FoodSuggestion(kind: 'dish', id: 'nasi_padang', name: 'Nasi padang'), // hidangan tidak ditawarkan untuk komponen
      FoodSuggestion(kind: 'food', id: 'ikan_bakar', name: 'Ikan bakar', portionG: 100),
    ];

    expect(find.textContaining('belum ada di database gizi'), findsOneWidget);
    expect(find.textContaining('belum termasuk yang belum terhitung'), findsOneWidget);
    await tester.tap(find.byKey(const Key('find_item_x')));
    await tester.pumpAndSettle();

    expect(api.searches, ['cakalang suwir']);
    expect(find.byKey(const Key('food_result_nasi_padang')), findsNothing);
    await tester.tap(find.byKey(const Key('food_result_ikan_bakar')));
    await tester.pumpAndSettle();

    final sent = api.patches.single.items;
    expect(sent[1], {'name': 'Ikan bakar', 'portion_g': 50.0, 'food_id': 'ikan_bakar', 'group': 'Nasi bakar'});
  });

  testWidgets('koreksi gagal menampilkan pesan, kartu tidak berubah', (tester) async {
    final api = await _send(tester, _geprek);
    api.patchError = Exception('Koneksi terputus');
    await tester.tap(find.byKey(const Key('halve_group_0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Koneksi terputus'), findsOneWidget);
    expect(find.textContaining('100 g · 268 kkal'), findsOneWidget);
  });
}
