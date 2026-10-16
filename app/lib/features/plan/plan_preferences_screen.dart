import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/models.dart';
import '../../shared/widgets.dart';
import '../home/home_screen.dart';
import 'plan_screen.dart';

final planPreferencesProvider = FutureProvider<PlanPreferences>((ref) => ref.read(apiProvider).getPlanPreferences());

const _dayShort = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _slotNames = {'breakfast': 'Sarapan', 'lunch': 'Makan siang', 'snack': 'Selingan', 'dinner': 'Makan malam'};
const _goals = {'jaga': 'Menjaga kebiasaan', 'turun_berat': 'Menurunkan berat badan', 'aktif': 'Lebih aktif bergerak'};
const _kinds = ['jalan cepat', 'bersepeda', 'senam', 'berenang'];

/// Preferensi rencana: jam bangun/makan/olahraga, hari olahraga, jenis, tujuan, dan pengingat WhatsApp.
class PlanPreferencesScreen extends ConsumerWidget {
  const PlanPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(planPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Preferensi rencana')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => LoadError(message: friendlyError(e), onRetry: () => ref.invalidate(planPreferencesProvider)),
        data: (prefs) => _Form(initial: prefs),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.initial});
  final PlanPreferences initial;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late PlanPreferences _p = widget.initial;
  bool _saving = false;

  Future<void> _pickTime(String current, void Function(String) apply) async {
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked != null) {
      setState(() => apply('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).savePlanPreferences(_p);
      ref
        ..invalidate(planPreferencesProvider)
        ..invalidate(planTodayProvider)
        ..invalidate(planWeekProvider)
        ..invalidate(dashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferensi rencana tersimpan.')));
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _timeTile(String key, String label, String value, void Function(String) apply) => ListTile(
        key: Key(key),
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: Text(value.replaceAll(':', '.'), style: context.text.titleMedium),
        onTap: () => _pickTime(value, apply),
      );

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return ListView(
      padding: context.pagePadding,
      children: [
        Text('Jam', style: context.text.titleMedium),
        _timeTile('pref_wake', 'Bangun', p.wakeTime, (v) => _p = p.copyWith(wakeTime: v)),
        for (final slot in _slotNames.keys)
          _timeTile('pref_meal_$slot', _slotNames[slot]!, p.mealTimes[slot] ?? '12:00',
              (v) => _p = p.copyWith(mealTimes: {...p.mealTimes, slot: v})),
        _timeTile('pref_exercise_time', 'Olahraga', p.exerciseTime, (v) => _p = p.copyWith(exerciseTime: v)),
        const Divider(height: KiraSpace.xl),
        Text('Hari olahraga', style: context.text.titleMedium),
        Text('Sisakan minimal satu hari istirahat.', style: context.text.bodySmall),
        Wrap(spacing: KiraSpace.sm, children: [
          for (var d = 0; d < 7; d++)
            FilterChip(
              key: Key('pref_day_$d'),
              label: Text(_dayShort[d]),
              selected: p.exerciseDays.contains(d),
              onSelected: (on) {
                final days = {...p.exerciseDays};
                on ? days.add(d) : days.remove(d);
                if (days.length < 7) setState(() => _p = p.copyWith(exerciseDays: days.toList()..sort()));
              },
            ),
        ]),
        const SizedBox(height: KiraSpace.md),
        Text('Jenis olahraga', style: context.text.titleMedium),
        Wrap(spacing: KiraSpace.sm, children: [
          for (final k in _kinds)
            FilterChip(
              key: Key('pref_kind_$k'),
              label: Text(k),
              selected: p.exerciseKinds.contains(k),
              onSelected: (on) {
                final kinds = [...p.exerciseKinds.where((x) => x != k), if (on) k];
                if (kinds.isNotEmpty) setState(() => _p = p.copyWith(exerciseKinds: kinds));
              },
            ),
        ]),
        SwitchListTile(
          key: const Key('pref_strength'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Tambah penguatan otot 2 hari per minggu'),
          value: p.strengthDays >= 2,
          onChanged: (on) => setState(() => _p = p.copyWith(strengthDays: on ? 2 : 0)),
        ),
        const Divider(height: KiraSpace.xl),
        Text('Tujuan', style: context.text.titleMedium),
        RadioGroup<String>(
          groupValue: p.goal,
          onChanged: (v) => setState(() => _p = p.copyWith(goal: v)),
          child: Column(children: [
            for (final g in _goals.entries)
              RadioListTile<String>(key: Key('pref_goal_${g.key}'), contentPadding: EdgeInsets.zero, value: g.key,
                  title: Text(g.value)),
          ]),
        ),
        if (p.goal == 'turun_berat')
          Text('Bila IMT 25 atau lebih, energi harian dikurangi sedikit. Ini bukan diet medis; konsultasikan dengan ahli gizi.',
              style: context.text.bodySmall),
        const Divider(height: KiraSpace.xl),
        Text('Pengingat WhatsApp', style: context.text.titleMedium),
        Text('Butuh nomor WhatsApp yang sudah ditautkan. Maksimal 4 pesan sehari, tidak di jam tenang '
            '(${p.quietStart.replaceAll(':', '.')}-${p.quietEnd.replaceAll(':', '.')}). Balas "stop pengingat" untuk berhenti.',
            style: context.text.bodySmall),
        SwitchListTile(
          key: const Key('pref_whatsapp'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Kirim pengingat rencana lewat WhatsApp'),
          value: p.whatsapp,
          onChanged: (on) => setState(() => _p = p.copyWith(whatsapp: on)),
        ),
        for (final r in const {'meals': 'Waktu makan', 'exercise': 'Olahraga', 'sleep': 'Jam tidur', 'weekly_plan': 'Rencana mingguan'}.entries)
          CheckboxListTile(
            key: Key('pref_reminder_${r.key}'),
            contentPadding: EdgeInsets.zero,
            title: Text(r.value),
            value: p.reminders[r.key] ?? true,
            onChanged: p.whatsapp
                ? (on) => setState(() => _p = p.copyWith(reminders: {...p.reminders, r.key: on ?? false}))
                : null,
          ),
        const SizedBox(height: KiraSpace.lg),
        FilledButton(
          key: const Key('pref_save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan...' : 'Simpan'),
        ),
      ],
    );
  }
}
