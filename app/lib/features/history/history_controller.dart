import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../shared/models.dart';

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

  Future<void> _patch(Future<void> Function() call) async {
    await call();
    await reload();
  }

  Future<void> correctItem(HistoryEntry entry, LoggedItem item, double grams) => _patch(() => ref
      .read(apiProvider)
      .patchLog(entry.logId,
          items: [for (final i in entry.items) i.id == item.id ? i.toPatch(portionG: grams) : i.toPatch()]));

  Future<void> halveGroup(HistoryEntry entry, String group) =>
      _patch(() => ref.read(apiProvider).patchLog(entry.logId, scale: 0.5, group: group));

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
