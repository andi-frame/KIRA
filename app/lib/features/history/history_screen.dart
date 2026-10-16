import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/insight_models.dart';
import '../../shared/labels.dart';
import '../../shared/models.dart';
import '../../shared/widgets.dart';
import '../chat/meal_card.dart';
import '../trends/trends_widgets.dart';
import 'history_controller.dart';

/// Riwayat makan: per hari apa yang dimakan dan diminum, gizinya, dan posisinya terhadap batas harian.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat'), actions: const [ProfileAction()]),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => LoadError(message: friendlyError(e), onRetry: () => ref.invalidate(historyProvider)),
        data: (state) => RefreshIndicator(
          onRefresh: () => ref.read(historyProvider.notifier).reload(),
          child: _HistoryList(state: state),
        ),
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.state});
  final HistoryState state;

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(historyProvider.notifier).loadMore();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anyLogged = state.days.any((d) => d.logged);
    return ListView(
      key: const Key('history_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(KiraSpace.lg),
      children: [
        if (!anyLogged)
          const SoftNote(
            key: Key('history_empty'),
            icon: Icons.restaurant_outlined,
            text: 'Belum ada catatan makan di periode ini. Ceritakan makan dan minummu di Ngobrol, nanti muncul di sini.',
          )
        else
          _WeekStrip(days: state.days.take(7).toList()),
        const SizedBox(height: KiraSpace.lg),
        for (final day in state.days) _DayCard(day: day),
        const SizedBox(height: KiraSpace.md),
        Center(
          child: state.loadingMore
              ? const CircularProgressIndicator.adaptive()
              : OutlinedButton.icon(
                  key: const Key('history_load_more'),
                  onPressed: () => _loadMore(context, ref),
                  icon: const Icon(Icons.history),
                  label: const Text('Muat 14 hari sebelumnya'),
                ),
        ),
      ],
    );
  }
}

/// Strip 7 hari terakhir: kalori dan gula per hari, gula dengan garis batas harian.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days});
  final List<HistoryDay> days;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final d in days.reversed) // grafik dari yang terlama
        DailyPoint(
          date: d.date.toIso8601String().substring(0, 10),
          logged: d.logged,
          kcal: d.logged ? d.totals.kcal : null,
          sugarG: d.logged ? d.totals.sugarG : null,
        ),
    ];
    final limit = days.isEmpty ? 50.0 : days.first.limits.sugarG;
    return Card(
      key: const Key('history_week_strip'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('7 hari terakhir', style: context.text.titleMedium),
          const SizedBox(height: KiraSpace.md),
          DailyBarChart(title: 'Kalori per hari', days: points, valueOf: (d) => d.kcal, unit: 'kkal'),
          const SizedBox(height: KiraSpace.lg),
          DailyBarChart(
            title: 'Gula per hari',
            days: points,
            valueOf: (d) => d.sugarG,
            unit: 'g',
            limit: limit,
            limitLabel: 'batas ${nutrientNumber(limit)} g',
          ),
        ]),
      ),
    );
  }
}

String dayTitle(DateTime date, DateTime today) {
  final d = DateTime(date.year, date.month, date.day);
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(d).inDays;
  if (diff == 0) return 'Hari ini';
  if (diff == 1) return 'Kemarin';
  return '${weekdayShort(d)}, ${formatDate(d)}';
}

class _DayCard extends ConsumerWidget {
  const _DayCard({required this.day});
  final HistoryDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = dayTitle(day.date, ref.read(clockProvider)());
    final key = Key('history_day_${day.date.toIso8601String().substring(0, 10)}');
    if (!day.logged) {
      return Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: KiraSpace.sm),
        child: Row(children: [
          Expanded(child: Text(title, style: context.text.titleSmall)),
          Text('tidak tercatat', style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
        ]),
      );
    }
    final t = day.totals;
    final extras = [
      if (day.sleepHours != null) 'tidur ${nutrientNumber(day.sleepHours!)} jam',
      if (day.activityMinutes != null) 'aktif ${nutrientNumber(day.activityMinutes!)} menit',
    ];
    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(vertical: KiraSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: context.text.titleMedium)),
            Text('${nutrientNumber(t.kcal)} kkal', style: context.text.titleSmall),
          ]),
          if (extras.isNotEmpty) Text(extras.join(' · '), style: context.text.bodySmall),
          const SizedBox(height: KiraSpace.sm),
          LimitBar(label: 'Gula', value: t.sugarG, limit: day.limits.sugarG, unit: 'g'),
          LimitBar(label: 'Natrium', value: t.sodiumMg, limit: day.limits.sodiumMg, unit: 'mg'),
          LimitBar(label: 'Lemak', value: t.fatG, limit: day.limits.fatG, unit: 'g'),
          const SizedBox(height: KiraSpace.sm),
          if (day.entries.isEmpty)
            Text('Tidak ada makan atau minum tercatat; hanya tidur/aktivitas.', style: context.text.bodySmall),
          for (final entry in day.entries) _EntryTile(entry: entry),
        ]),
      ),
    );
  }
}

/// Posisi terhadap batas harian, ditulis dengan kata ("sisa 12 g" / "melewati batas 8 g"), bukan hanya warna.
class LimitBar extends StatelessWidget {
  const LimitBar({super.key, required this.label, required this.value, required this.limit, required this.unit});
  final String label;
  final double value;
  final double limit;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final over = value > limit;
    final words = over
        ? 'melewati batas ${nutrientNumber(value - limit)} $unit'
        : 'sisa ${nutrientNumber(limit - value)} $unit';
    final color = over ? context.kira.attention : context.scheme.primary;
    return Semantics(
      label: '$label ${nutrientNumber(value)} dari batas ${nutrientNumber(limit)} $unit, $words',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('$label ${nutrientNumber(value)} / ${nutrientNumber(limit)} $unit',
                  style: context.text.bodyMedium)),
              Text(words, style: context.text.bodySmall?.copyWith(fontWeight: over ? FontWeight.w700 : null)),
            ]),
            const SizedBox(height: 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: limit <= 0 ? 0 : (value / limit).clamp(0, 1).toDouble(),
                minHeight: 6,
                color: color,
                backgroundColor: context.scheme.surfaceContainerHighest,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

IconData sourceIcon(String source) => switch (source) {
      'voice' => Icons.mic_none,
      'barcode' => Icons.qr_code_scanner,
      'photo_label' => Icons.fact_check_outlined,
      final s when s.startsWith('photo') => Icons.photo_camera_outlined,
      _ => Icons.chat_bubble_outline,
    };

String sourceLabel(String source) => switch (source) {
      'voice' => 'suara',
      'barcode' => 'kode batang',
      'photo_label' => 'foto label',
      final s when s.startsWith('photo') => 'foto',
      'device' => 'perangkat',
      _ => 'teks',
    };

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = '${entry.time.toLocal().hour.toString().padLeft(2, '0')}.${entry.time.toLocal().minute.toString().padLeft(2, '0')}';
    final subtitle = [
      time,
      '${nutrientNumber(entry.totals.kcal)} kkal',
      if (entry.uncounted > 0) '${entry.uncounted} belum terhitung',
      if (entry.corrected) 'dikoreksi',
    ].join(' · ');
    final history = ref.read(historyProvider.notifier);
    return ExpansionTile(
      key: Key('history_entry_${entry.logId}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: KiraSpace.sm),
      leading: Tooltip(message: 'dari ${sourceLabel(entry.source)}', child: Icon(sourceIcon(entry.source))),
      title: Text(entry.title),
      subtitle: Text(subtitle),
      children: [
        if (entry.items.isEmpty)
          const Text('Tidak ada rincian item.')
        else
          MealGroupsView(
            meal: entry.asMeal,
            actions: MealCardActions(
              correct: (item, grams) => history.correctItem(entry, item, grams),
              halve: (group) => history.halveGroup(entry, group),
              remove: (item) => history.removeItem(entry, item),
              replace: (item, food) => history.replaceItem(entry, item, food),
              search: (q) => ref.read(apiProvider).searchFoods(q),
            ),
          ),
      ],
    );
  }
}
