import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/refresh.dart';
import '../../shared/meal_models.dart';
import '../../shared/models.dart';
import '../jeda/jeda_controller.dart';

const historyPageDays = 14;
const _maxReloadDays = 60; // batas server per permintaan

class HistoryState {
  const HistoryState({required this.days, required this.nextBefore, this.loadingMore = false});
  final List<HistoryDay> days; // terbaru dulu
  final String nextBefore;
  final bool loadingMore;

  HistoryState copyWith({List<HistoryDay>? days, String? nextBefore, bool? loadingMore}) => HistoryState(
        days: days ?? this.days,
        nextBefore: nextBefore ?? this.nextBefore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Riwayat makan per hari. Dimuat 14 hari sekaligus; "muat lebih lama" menambah halaman sebelumnya.
class HistoryController extends AsyncNotifier<HistoryState> {
  @override
  Future<HistoryState> build() async {
    final page = await ref.read(apiProvider).getHistory(days: historyPageDays);
    return HistoryState(days: page.days, nextBefore: page.nextBefore);
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(apiProvider).getHistory(days: historyPageDays, before: current.nextBefore);
      state = AsyncData(HistoryState(days: [...current.days, ...page.days], nextBefore: page.nextBefore));
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }

  /// Setelah koreksi: muat ulang rentang yang sedang terlihat supaya total harian ikut berubah.
  Future<void> reload() async {
    final shown = state.asData?.value.days.length ?? historyPageDays;
    final days = shown.clamp(historyPageDays, _maxReloadDays);
    final page = await ref.read(apiProvider).getHistory(days: days);
    state = AsyncData(HistoryState(days: page.days, nextBefore: page.nextBefore));
  }

  /// Setelah koreksi: Riwayat dimuat ulang (halaman yang sudah dibuka dipertahankan) dan semua tampilan turunannya
  /// (proyeksi, Beranda, Tren, rencana, target) ikut dimuat ulang, jadi tidak ada yang tertahan pada angka lama.
  Future<void> _patch(Future<void> Function() call) async {
    await call();
    refreshHealthData(ref.invalidate, includeHistory: false);
    await reload();
    // Kartu Jeda sosmed ("catat hari ini dulu?") bergantung pada apa yang sudah tercatat.
    await ref.read(jedaProvider.notifier).refresh();
  }

  Future<void> correctItem(HistoryEntry entry, LoggedItem item, double grams) => _patch(() => ref
      .read(apiProvider)
      .patchLog(entry.logId,
          items: [for (final i in entry.items) i.id == item.id ? i.toPatch(portionG: grams) : i.toPatch()]));

  /// Saklar "setengah porsi": true = jadikan setengah, false = kembali ke porsi biasa.
  Future<void> halveGroup(HistoryEntry entry, String group, {required bool half}) =>
      _patch(() => ref.read(apiProvider).patchLog(entry.logId, half: half, group: group));

  Future<void> setMealSlot(HistoryEntry entry, String slot) =>
      _patch(() => ref.read(apiProvider).patchLog(entry.logId, mealSlot: slot));

  Future<void> deleteEntry(String logId) => _patch(() => ref.read(apiProvider).deleteLog(logId));

  Future<void> editActivity(HistoryActivity a, {required int minutes, required String kind}) =>
      _patch(() => ref.read(apiProvider).patchLog(a.logId, minutes: minutes, activityKind: kind));

  Future<void> editSleep(HistorySleep s, {String? bedTime, String? wakeTime, double? hours}) => _patch(() =>
      ref.read(apiProvider).patchLog(s.logId, bedTime: bedTime, wakeTime: wakeTime, hours: hours));

  Future<void> removeItem(HistoryEntry entry, LoggedItem item) => _patch(() => ref
      .read(apiProvider)
      .patchLog(entry.logId, items: [for (final i in entry.items) if (i.id != item.id) i.toPatch()]));

  Future<void> replaceItem(HistoryEntry entry, LoggedItem item, FoodSuggestion food) =>
      _patch(() => ref.read(apiProvider).patchLog(entry.logId, items: [
            for (final i in entry.items)
              i.id == item.id
                  ? i.toPatch(name: food.name, foodId: food.id, portionG: item.portionG ?? food.portionG)
                  : i.toPatch(),
          ]));
}

final historyProvider = AsyncNotifierProvider<HistoryController, HistoryState>(HistoryController.new);
