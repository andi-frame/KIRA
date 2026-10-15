import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/models.dart';
import 'api_client.dart';
import 'providers.dart';

const _prefsKey = 'outbox_v1';

/// Pesan darurat yang menyertai setiap kiriman tertunda: antrean tidak boleh membuat orang menunggu saat gawat.
const offlineEmergencyHint =
    'Kalau ini darurat (nyeri dada, sesak, lemas mendadak), jangan menunggu sinyal: hubungi 119 atau ke IGD terdekat.';

String newOutboxId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';

enum OutboxKind { message, result }

class OutboxItem {
  const OutboxItem({required this.id, required this.kind, required this.payload, required this.createdAt});
  final String id; // juga dipakai sebagai Idempotency-Key, jadi kiriman ulang tidak tercatat dua kali
  final OutboxKind kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  String get text => payload['text'] as String? ?? '';

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind.name, 'payload': payload, 'at': createdAt.toIso8601String()};

  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
        id: j['id'] as String,
        kind: OutboxKind.values.firstWhere((k) => k.name == j['kind']),
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        createdAt: DateTime.parse(j['at'] as String),
      );
}

/// Hasil pengiriman satu item antrean.
class OutboxEvent {
  const OutboxEvent(this.item, {this.reply, this.outcome, this.error});
  final OutboxItem item;
  final ChatReply? reply; // untuk pesan
  final ResultOutcome? outcome; // untuk hasil cek
  final String? error; // ditolak server (bukan masalah sinyal): tidak dicoba lagi

  bool get ok => error == null;
}

/// Kiriman yang tertunda karena tidak ada sinyal, disimpan terenkripsi di ponsel dan dikirim ulang otomatis.
/// Hanya teks pesan dan hasil cek; foto dan suara membutuhkan sinyal saat itu juga.
class OutboxController extends Notifier<List<OutboxItem>> {
  final _events = StreamController<OutboxEvent>.broadcast();
  bool _flushing = false;
  bool _loaded = false;

  Stream<OutboxEvent> get events => _events.stream;

  @override
  List<OutboxItem> build() {
    ref.onDispose(_events.close);
    // Antrean milik satu akun: berhenti dipakai begitu akun berganti atau keluar.
    ref.listen(authProvider.select((s) => s.token), (prev, next) {
      if (prev != null && prev != next) _replace(const []);
    });
    return const [];
  }

  PrefsStore get _prefs => ref.read(prefsStoreProvider);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await _prefs.read(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final loaded = (jsonDecode(raw) as List).map((e) => OutboxItem.fromJson(e as Map<String, dynamic>)).toList();
      state = [...loaded, ...state];
    } catch (_) {
      await _prefs.write(_prefsKey, null); // berkas rusak: lebih aman dibuang daripada mengirim yang tidak jelas
    }
  }

  void _replace(List<OutboxItem> items) {
    state = items;
    _prefs.write(_prefsKey, items.isEmpty ? null : jsonEncode([for (final i in items) i.toJson()]));
  }

  OutboxItem enqueueMessage(String text, {String? id}) {
    final item = OutboxItem(
      id: id ?? newOutboxId(), kind: OutboxKind.message, payload: {'text': text}, createdAt: DateTime.now(),
    );
    _replace([...state, item]);
    return item;
  }

  OutboxItem enqueueResult(String kind, Map<String, num> value, {String source = 'self', String? id}) {
    final item = OutboxItem(
      id: id ?? newOutboxId(),
      kind: OutboxKind.result,
      payload: {'kind': kind, 'value': value, 'source': source},
      createdAt: DateTime.now(),
    );
    _replace([...state, item]);
    return item;
  }

  /// Kirim berurutan. Berhenti di masalah jaringan atau server (dicoba lagi nanti); 4xx berarti ditolak dan dibuang.
  Future<void> flush() async {
    if (_flushing || state.isEmpty) return;
    _flushing = true;
    try {
      final api = ref.read(apiProvider);
      for (final item in List.of(state)) {
        try {
          if (item.kind == OutboxKind.message) {
            final reply = await api.sendMessage(item.text, idempotencyKey: item.id);
            _done(item, OutboxEvent(item, reply: reply));
          } else {
            final value = (item.payload['value'] as Map).map((k, v) => MapEntry(k as String, v as num));
            final outcome = await api.postResult(
              item.payload['kind'] as String, value,
              source: item.payload['source'] as String? ?? 'self', idempotencyKey: item.id,
            );
            _done(item, OutboxEvent(item, outcome: outcome));
          }
        } on ApiException catch (e) {
          final retryable = e.status == null || e.status! >= 500 || e.status == 429;
          if (retryable) return;
          _done(item, OutboxEvent(item, error: e.message));
        }
      }
    } finally {
      _flushing = false;
    }
  }

  void _done(OutboxItem item, OutboxEvent event) {
    _replace([
      for (final i in state)
        if (i.id != item.id) i,
    ]);
    if (!_events.isClosed) _events.add(event);
  }
}

final outboxProvider = NotifierProvider<OutboxController, List<OutboxItem>>(OutboxController.new);
