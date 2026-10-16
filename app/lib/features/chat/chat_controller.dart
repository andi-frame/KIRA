import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/outbox.dart';
import '../../core/providers.dart';
import '../../shared/models.dart';
import '../history/history_controller.dart';
import '../home/home_screen.dart';
import '../projection/projection_providers.dart';
import '../jeda/jeda_controller.dart';
import '../reminders/reminders_controller.dart';
import 'frequent_foods.dart';

enum ChatKind { user, pending, kira, extraction, emergency, error }

class ChatItem {
  const ChatItem._(this.kind,
      {this.text = '', this.data, this.logIds = const [], this.retry, this.calls = const [], this.id, this.meal});

  const ChatItem.user(String text) : this._(ChatKind.user, text: text);
  /// Pesan yang belum terkirim karena tidak ada sinyal; tersimpan di ponsel dan dikirim otomatis.
  const ChatItem.pending(String text, String id) : this._(ChatKind.pending, text: text, id: id);
  const ChatItem.kira(String text, {List<ToolCall> calls = const []}) : this._(ChatKind.kira, text: text, calls: calls);
  const ChatItem.emergency(String text) : this._(ChatKind.emergency, text: text);
  const ChatItem.extraction(ExtractionData data, List<String> logIds, {MealLog? meal})
      : this._(ChatKind.extraction, data: data, logIds: logIds, meal: meal);
  const ChatItem.error(String text, Future<void> Function() retry) : this._(ChatKind.error, text: text, retry: retry);

  final ChatKind kind;
  final String text;
  final ExtractionData? data;
  final List<String> logIds;
  final Future<void> Function()? retry;
  final List<ToolCall> calls;
  final String? id;

  /// Catatan makan yang tersimpan (item, gizi, kelompok hidangan); null untuk balasan lama tanpa rincian.
  final MealLog? meal;
}

class ChatState {
  const ChatState({this.items = const [], this.busy = false});
  final List<ChatItem> items;
  final bool busy;

  /// Hanya sapaan awal yang ada: saat yang tepat menawarkan kalimat contoh.
  bool get isFresh => items.length == 1;

  ChatState copyWith({List<ChatItem>? items, bool? busy}) => ChatState(items: items ?? this.items, busy: busy ?? this.busy);
}

const greetingText =
    'Hai! Aku KIRA. Ceritakan makan, minum, dan tidurmu hari ini, pakai kata-katamu sendiri. Satu menit cukup.';

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() {
    final outbox = ref.read(outboxProvider.notifier);
    final sub = outbox.events.listen(_onOutbox);
    ref.onDispose(sub.cancel);
    return const ChatState(items: [ChatItem.kira(greetingText)]);
  }

  /// Pesan tertunda sudah terkirim (atau ditolak): ganti gelembung "menunggu" dengan hasilnya.
  void _onOutbox(OutboxEvent event) {
    if (event.item.kind != OutboxKind.message) return;
    final id = event.item.id;
    final items = [
      for (final i in state.items)
        if (i.kind == ChatKind.pending && i.id == id) ChatItem.user(i.text) else i,
    ];
    state = state.copyWith(items: items);
    if (event.reply != null) {
      _apply(event.reply!);
    } else if (event.error != null) {
      _add(ChatItem.kira('Pesan "${event.item.text}" tidak bisa dikirim: ${event.error}'));
    }
  }

  void _add(ChatItem item) => state = state.copyWith(items: [...state.items, item]);

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || state.busy) return;
    final id = newOutboxId();
    _add(ChatItem.user(text));
    await _run(() => ref.read(apiProvider).sendMessage(text, idempotencyKey: id), onOffline: () {
      // Tanpa sinyal: simpan di ponsel (dengan kunci yang sama, jadi tidak tercatat dua kali) dan kirim otomatis nanti.
      ref.read(outboxProvider.notifier).enqueueMessage(text, id: id);
      final items = [...state.items];
      final at = items.lastIndexWhere((i) => i.kind == ChatKind.user && i.text == text);
      if (at >= 0) items[at] = ChatItem.pending(text, id);
      state = state.copyWith(items: [
        ...items,
        const ChatItem.kira('Belum ada sinyal. Pesanmu tersimpan di ponsel dan akan dikirim otomatis begitu tersambung. '
            '$offlineEmergencyHint'),
      ]);
    });
  }

  Future<void> sendPhoto(String kind, Uint8List bytes, String name) async {
    if (state.busy) return;
    const labels = {
      'food': 'Foto makanan',
      'receipt': 'Foto struk belanja',
      'label': 'Foto label gizi kemasan',
      'result': 'Foto hasil pemeriksaan',
    };
    _add(ChatItem.user(labels[kind] ?? 'Foto'));
    await _run(() => ref.read(apiProvider).sendPhoto(kind, bytes, name));
  }

  Future<void> sendVoice(Uint8List bytes, String name) async {
    if (state.busy) return;
    await _run(() => ref.read(apiProvider).sendVoice(bytes, name));
  }

  Future<void> _run(Future<ChatReply> Function() call, {void Function()? onOffline}) async {
    state = state.copyWith(busy: true);
    try {
      _apply(await call());
      unawaited(ref.read(outboxProvider.notifier).flush()); // sinyal ada: sekalian kirim yang tertunda
    } on ApiException catch (e) {
      if (e.isNetwork && onOffline != null) {
        onOffline();
        return;
      }
      _add(ChatItem.error(e.message, () async {
        state = state.copyWith(items: [...state.items]..removeWhere((i) => i.kind == ChatKind.error));
        await _run(call);
      }));
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  void _apply(ChatReply reply) {
    if (reply.transcript != null && reply.transcript!.trim().isNotEmpty) _add(ChatItem.user(reply.transcript!));
    _add(reply.redFlag != null ? ChatItem.emergency(reply.reply) : ChatItem.kira(reply.reply, calls: reply.toolCalls));
    if (reply.logIds.isNotEmpty) {
      ref
        ..invalidate(projectionProvider) // catatan baru mengubah proyeksi
        ..invalidate(historyProvider)
        ..invalidate(dashboardProvider)
        ..invalidate(frequentFoodsProvider);
      unawaited(ref.read(remindersProvider.notifier).reschedule()); // sudah mencatat: pengingat hari ini tak perlu
      unawaited(ref.read(jedaProvider.notifier).refresh()); // kartu "catat hari ini" ikut menyesuaikan
    }
    final data = reply.extraction;
    if (data != null && !data.isEmpty && reply.logIds.isNotEmpty && reply.redFlag == null) {
      _add(ChatItem.extraction(data, reply.logIds, meal: reply.meals.isEmpty ? null : reply.meals.first));
    }
  }

  Future<void> _patchMeal(ChatItem card, Future<MealLog> Function(KiraApi api, MealLog meal) patch) async {
    final updated = await patch(ref.read(apiProvider), card.meal!);
    state = state.copyWith(items: [
      for (final i in state.items) identical(i, card) ? ChatItem.extraction(card.data!, card.logIds, meal: updated) : i,
    ]);
    ref
      ..invalidate(projectionProvider) // gizi berubah, proyeksi ikut berubah
      ..invalidate(historyProvider)
      ..invalidate(dashboardProvider);
  }

  /// Ubah gram satu item (makanan tunggal atau komponen hidangan); item lain tetap.
  Future<void> correctItem(ChatItem card, LoggedItem item, double grams) => _patchMeal(
        card,
        (api, meal) => api.patchLog(meal.id,
            items: [for (final i in meal.items) i.id == item.id ? i.toPatch(portionG: grams) : i.toPatch()]),
      );

  /// "Setengah porsi" untuk satu hidangan: semua komponennya diskalakan.
  Future<void> halveGroup(ChatItem card, String group) =>
      _patchMeal(card, (api, meal) => api.patchLog(meal.id, scale: 0.5, group: group));

  /// Hapus satu komponen ("tanpa nasi").
  Future<void> removeItem(ChatItem card, LoggedItem item) => _patchMeal(
        card,
        (api, meal) => api.patchLog(meal.id, items: [for (final i in meal.items) if (i.id != item.id) i.toPatch()]),
      );

  /// Ganti komponen yang belum terhitung dengan makanan dari database gizi (hasil pencarian).
  Future<void> replaceItem(ChatItem card, LoggedItem item, FoodSuggestion food) => _patchMeal(
        card,
        (api, meal) => api.patchLog(meal.id, items: [
          for (final i in meal.items)
            i.id == item.id
                ? i.toPatch(name: food.name, foodId: food.id, portionG: item.portionG ?? food.portionG)
                : i.toPatch(),
        ]),
      );

  Future<List<FoodSuggestion>> searchFoods(String query) => ref.read(apiProvider).searchFoods(query);

  /// Koreksi porsi satu makanan di kartu hasil ekstraksi ("porsinya setengah, bukan satu").
  Future<void> correctPortion(ChatItem card, int index, double grams) async {
    final data = card.data!;
    final items = [
      for (var i = 0; i < data.items.length; i++)
        {'name': data.items[i].name, 'portion_g': i == index ? grams : data.items[i].portionG},
    ];
    await ref.read(apiProvider).patchLog(card.logIds.first, items: items);
    final updated = ExtractionData(
      items: [
        for (var i = 0; i < data.items.length; i++)
          FoodEntry(
            name: data.items[i].name,
            portionText: i == index ? '${grams.round()} g' : data.items[i].portionText,
            portionG: i == index ? grams : data.items[i].portionG,
          ),
      ],
      drinks: data.drinks,
      sleepBed: data.sleepBed,
      sleepWake: data.sleepWake,
      activities: data.activities,
      intent: data.intent,
    );
    state = state.copyWith(items: [
      for (final i in state.items) identical(i, card) ? ChatItem.extraction(updated, card.logIds) : i,
    ]);
  }
}

final chatProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);
