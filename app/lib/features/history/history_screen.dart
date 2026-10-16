import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/insight_models.dart';
import '../../shared/labels.dart';
import '../../shared/limit_bar.dart';
import '../../shared/models.dart';
import '../../shared/widgets.dart';
import '../chat/meal_card.dart';
import '../trends/trends_widgets.dart';
import 'history_controller.dart';

/// Riwayat: per hari apa yang dimakan dan diminum (gizinya, posisinya terhadap batas harian), olahraga, dan tidur. Semuanya bisa diubah atau dihapus.
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
            text: 'Belum ada catatan di periode ini. Ceritakan makan, minum, olahraga, dan tidurmu di Ngobrol, nanti muncul di sini dan bisa kamu ubah atau hapus.',
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
          if (day.activities.isNotEmpty) ...[
            const SizedBox(height: KiraSpace.sm),
            Text('Olahraga dan aktivitas', style: context.text.titleSmall),
            for (final a in day.activities) _ActivityTile(activity: a),
          ],
          if (day.sleeps.isNotEmpty) ...[
            const SizedBox(height: KiraSpace.sm),
            Text('Tidur', style: context.text.titleSmall),
            for (final s in day.sleeps) _SleepTile(sleep: s),
          ],
        ]),
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

String _clock(DateTime t) =>
    '${t.toLocal().hour.toString().padLeft(2, '0')}.${t.toLocal().minute.toString().padLeft(2, '0')}';

Future<bool> _confirm(BuildContext context, String title, String body, {String action = 'Hapus'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Batal')),
        FilledButton(key: const Key('confirm_delete'), onPressed: () => Navigator.pop(dialog, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

Future<void> _guarded(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// Satu catatan olahraga: bisa diubah (jenis dan menit) atau dihapus, dan semua angka turunannya dihitung ulang.
class _ActivityTile extends ConsumerWidget {
  const _ActivityTile({required this.activity});
  final HistoryActivity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.read(historyProvider.notifier);
    return ListTile(
      key: Key('history_activity_${activity.logId}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Tooltip(message: 'dari ${sourceLabel(activity.source)}', child: const Icon(Icons.directions_walk)),
      title: Text('${activity.kind} · ${nutrientNumber(activity.minutes)} menit'),
      subtitle: Text(_clock(activity.time)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: Key('edit_activity_${activity.logId}'),
          tooltip: 'Ubah olahraga',
          icon: const Icon(Icons.edit_outlined, size: 20),
          onPressed: () async {
            final result = await showDialog<({String kind, int minutes})>(
              context: context,
              builder: (_) => ActivityEditDialog(kind: activity.kind, minutes: activity.minutes.round()),
            );
            if (result != null && context.mounted) {
              await _guarded(context, () => history.editActivity(activity, minutes: result.minutes, kind: result.kind));
            }
          },
        ),
        IconButton(
          key: Key('delete_activity_${activity.logId}'),
          tooltip: 'Hapus olahraga',
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () async {
            if (await _confirm(context, 'Hapus catatan olahraga?', 'Menit aktif hari ini dan target mingguan dihitung ulang.') &&
                context.mounted) {
              await _guarded(context, () => history.deleteEntry(activity.logId));
            }
          },
        ),
      ]),
    );
  }
}

class _SleepTile extends ConsumerWidget {
  const _SleepTile({required this.sleep});
  final HistorySleep sleep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.read(historyProvider.notifier);
    final span = [
      if (sleep.bedTime != null) 'tidur ${sleep.bedTime}',
      if (sleep.wakeTime != null) 'bangun ${sleep.wakeTime}',
    ].join(', ');
    return ListTile(
      key: Key('history_sleep_${sleep.logId}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Tooltip(message: 'dari ${sourceLabel(sleep.source)}', child: const Icon(Icons.bedtime_outlined)),
      title: Text(sleep.hours == null ? 'Tidur' : '${nutrientNumber(sleep.hours!)} jam tidur'),
      subtitle: span.isEmpty ? null : Text(span),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: Key('edit_sleep_${sleep.logId}'),
          tooltip: 'Ubah tidur',
          icon: const Icon(Icons.edit_outlined, size: 20),
          onPressed: () async {
            final result = await showDialog<({String? bed, String? wake, double? hours})>(
              context: context,
              builder: (_) => SleepEditDialog(bedTime: sleep.bedTime, wakeTime: sleep.wakeTime, hours: sleep.hours),
            );
            if (result != null && context.mounted) {
              await _guarded(
                  context, () => history.editSleep(sleep, bedTime: result.bed, wakeTime: result.wake, hours: result.hours));
            }
          },
        ),
        IconButton(
          key: Key('delete_sleep_${sleep.logId}'),
          tooltip: 'Hapus tidur',
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () async {
            if (await _confirm(context, 'Hapus catatan tidur?', 'Rata-rata tidur dan pola tidur dihitung ulang.') &&
                context.mounted) {
              await _guarded(context, () => history.deleteEntry(sleep.logId));
            }
          },
        ),
      ]),
    );
  }
}

/// Ubah jenis dan lama olahraga.
class ActivityEditDialog extends StatefulWidget {
  const ActivityEditDialog({super.key, required this.kind, required this.minutes});
  final String kind;
  final int minutes;

  @override
  State<ActivityEditDialog> createState() => _ActivityEditDialogState();
}

class _ActivityEditDialogState extends State<ActivityEditDialog> {
  late final _kind = TextEditingController(text: widget.kind);
  late final _minutes = TextEditingController(text: widget.minutes.toString());
  String? _error;

  @override
  void dispose() {
    _kind.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _save() {
    final minutes = int.tryParse(_minutes.text.trim());
    final kind = _kind.text.trim();
    if (kind.isEmpty || minutes == null || minutes < 1 || minutes > 1440) {
      setState(() => _error = 'Isi jenis olahraga dan lama antara 1 dan 1440 menit.');
      return;
    }
    Navigator.pop(context, (kind: kind, minutes: minutes));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ubah olahraga'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('activity_kind'), controller: _kind, decoration: const InputDecoration(labelText: 'Jenis')),
          const SizedBox(height: KiraSpace.sm),
          TextField(
            key: const Key('activity_minutes'),
            controller: _minutes,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(labelText: 'Berapa menit?', suffixText: 'menit', errorText: _error),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(key: const Key('activity_save'), onPressed: _save, child: const Text('Simpan')),
        ],
      );
}

/// Ubah jam tidur dan bangun (lama dihitung ulang), atau lamanya saja bila jamnya tidak dicatat.
class SleepEditDialog extends StatefulWidget {
  const SleepEditDialog({super.key, this.bedTime, this.wakeTime, this.hours});
  final String? bedTime, wakeTime;
  final double? hours;

  @override
  State<SleepEditDialog> createState() => _SleepEditDialogState();
}

class _SleepEditDialogState extends State<SleepEditDialog> {
  late String? _bed = widget.bedTime;
  late String? _wake = widget.wakeTime;
  late final _hours = TextEditingController(text: widget.hours == null ? '' : nutrientNumber(widget.hours!));
  String? _error;

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  Future<void> _pick(bool bed) async {
    final current = (bed ? _bed : _wake)?.split(':');
    final initial = current == null ? const TimeOfDay(hour: 22, minute: 0) : TimeOfDay(hour: int.parse(current[0]), minute: int.parse(current[1]));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => bed ? _bed = text : _wake = text);
  }

  void _save() {
    final hasTimes = _bed != null && _wake != null;
    final hours = double.tryParse(_hours.text.trim().replaceAll(',', '.'));
    if (!hasTimes && (hours == null || hours <= 0 || hours > 24)) {
      setState(() => _error = 'Pilih jam tidur dan bangun, atau isi lama tidur 1 sampai 24 jam.');
      return;
    }
    Navigator.pop(context, (bed: _bed, wake: _wake, hours: hasTimes ? null : hours));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ubah tidur'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          OutlinedButton.icon(
            key: const Key('sleep_bed'),
            onPressed: () => _pick(true),
            icon: const Icon(Icons.bedtime_outlined),
            label: Text(_bed == null ? 'Pilih jam tidur' : 'Tidur $_bed'),
          ),
          const SizedBox(height: KiraSpace.sm),
          OutlinedButton.icon(
            key: const Key('sleep_wake'),
            onPressed: () => _pick(false),
            icon: const Icon(Icons.wb_sunny_outlined),
            label: Text(_wake == null ? 'Pilih jam bangun' : 'Bangun $_wake'),
          ),
          const SizedBox(height: KiraSpace.md),
          TextField(
            key: const Key('sleep_hours'),
            controller: _hours,
            enabled: _bed == null || _wake == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Atau lama tidur saja',
              suffixText: 'jam',
              helperText: _bed != null && _wake != null ? 'Dihitung dari jam tidur dan bangun.' : null,
              errorText: _error,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(key: const Key('sleep_save'), onPressed: _save, child: const Text('Simpan')),
        ],
      );
}

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
              halve: (group, {required half}) => history.halveGroup(entry, group, half: half),
              remove: (item) => history.removeItem(entry, item),
              replace: (item, food) => history.replaceItem(entry, item, food),
              search: (q) => ref.read(apiProvider).searchFoods(q),
              setSlot: entry.kind == 'meal' ? (slot) => history.setMealSlot(entry, slot) : null,
              deleteLog: () => history.deleteEntry(entry.logId),
            ),
          ),
      ],
    );
  }
}
