import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../shared/models.dart';
import '../projection/projection_providers.dart';

enum ChatKind { user, kira, extraction, emergency, error }

class ChatItem {
  const ChatItem._(this.kind, {this.text = '', this.data, this.logIds = const [], this.retry, this.calls = const []});

  const ChatItem.user(String text) : this._(ChatKind.user, text: text);
  const ChatItem.kira(String text, {List<ToolCall> calls = const []}) : this._(ChatKind.kira, text: text, calls: calls);
  const ChatItem.emergency(String text) : this._(ChatKind.emergency, text: text);
  const ChatItem.extraction(ExtractionData data, List<String> logIds)
      : this._(ChatKind.extraction, data: data, logIds: logIds);
  const ChatItem.error(String text, Future<void> Function() retry) : this._(ChatKind.error, text: text, retry: retry);

  final ChatKind kind;
  final String text;
  final ExtractionData? data;
  final List<String> logIds;
  final Future<void> Function()? retry;
  final List<ToolCall> calls;
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
  ChatState build() => const ChatState(items: [ChatItem.kira(greetingText)]);

  void _add(ChatItem item) => state = state.copyWith(items: [...state.items, item]);

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || state.busy) return;
    _add(ChatItem.user(text));
    await _run(() => ref.read(apiProvider).sendMessage(text));
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

  Future<void> _run(Future<ChatReply> Function() call) async {
    state = state.copyWith(busy: true);
    try {
      _apply(await call());
    } on ApiException catch (e) {
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
    if (reply.logIds.isNotEmpty) ref.invalidate(projectionProvider); // catatan baru mengubah proyeksi
    final data = reply.extraction;
    if (data != null && !data.isEmpty && reply.logIds.isNotEmpty && reply.redFlag == null) {
      _add(ChatItem.extraction(data, reply.logIds));
    }
  }

  /// Koreksi porsi satu makanan di kartu hasil ekstraksi ("porsinya setengah, bukan satu").
  Future<void> correctPortion(ChatItem card, int index, double grams) async {
    final data = card.data!;
    final items = [
      for (var i = 0; i < data.items.length; i++)
        {'name': data.items[i].name, 'portion_g': i == index ? grams : data.items[i].portionG},
    ];
    await ref.read(apiProvider).patchLog(card.logIds.first, items);
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
