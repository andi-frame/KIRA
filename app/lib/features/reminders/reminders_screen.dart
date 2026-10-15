import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'reminder_plan.dart';
import 'reminders_controller.dart';

/// Pengingat di ponsel. Semua mati sampai pengguna menyalakannya, dan isi notifikasi tidak memuat data kesehatan.
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  String? _denied;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(remindersProvider.notifier).load());
  }

  Future<void> _set(ReminderSettings next) async {
    final ok = await ref.read(remindersProvider.notifier).update(next);
    if (mounted) {
      setState(() => _denied = ok ? null : 'Izin notifikasi belum diberikan, jadi pengingat belum menyala. '
          'Kamu bisa mengizinkannya di pengaturan ponsel lalu menyalakan lagi di sini.');
    }
  }

  Future<void> _pickTime(ReminderSettings s) async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s.hour, minute: s.minute));
    if (picked != null) await _set(s.copyWith(hour: picked.hour, minute: picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(remindersProvider);
    String two(int v) => v.toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(title: const Text('Pengingat')),
      body: ListView(
        padding: const EdgeInsets.all(KiraSpace.lg),
        children: [
          Text(
            'Pengingat lembut di ponselmu, hanya yang kamu nyalakan. Isi notifikasinya tidak memuat data kesehatan, '
            'jadi tidak membocorkan apa pun di layar kunci.',
            style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant),
          ),
          const SizedBox(height: KiraSpace.lg),
          Card(
            child: Column(children: [
              SwitchListTile(
                key: const Key('reminder_daily'),
                title: const Text('Check-in harian'),
                subtitle: Text('Setiap hari pukul ${two(s.hour)}.${two(s.minute)}, kecuali kalau kamu sudah mencatat hari itu'),
                value: s.daily,
                onChanged: (v) => _set(s.copyWith(daily: v)),
              ),
              if (s.daily)
                ListTile(
                  key: const Key('reminder_time'),
                  contentPadding: const EdgeInsets.only(left: KiraSpace.xl, right: KiraSpace.lg),
                  leading: const Icon(Icons.schedule),
                  title: const Text('Jam pengingat'),
                  trailing: Text('${two(s.hour)}.${two(s.minute)}', style: context.text.titleMedium),
                  onTap: () => _pickTime(s),
                ),
              const Divider(height: 1),
              SwitchListTile(
                key: const Key('reminder_weekly'),
                title: const Text('Rekap mingguan'),
                subtitle: const Text('Senin pukul 08.00: apa yang berubah dari minggu lalu'),
                value: s.weekly,
                onChanged: (v) => _set(s.copyWith(weekly: v)),
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const Key('reminder_check'),
                title: const Text('Tanya "sudah dicek?"'),
                subtitle: const Text('Sekali, kalau saran cek sudah beberapa hari dan belum kamu jawab'),
                value: s.checkFollowUp,
                onChanged: (v) => _set(s.copyWith(checkFollowUp: v)),
              ),
            ]),
          ),
          if (_denied != null) ...[
            const SizedBox(height: KiraSpace.md),
            Semantics(liveRegion: true, child: SoftNote(key: const Key('reminder_denied'), icon: Icons.notifications_off_outlined, text: _denied!)),
          ],
          const SizedBox(height: KiraSpace.lg),
          Text(
            'Pengingat disusun ulang tiap kamu membuka KIRA. Kalau lama tidak dibuka, pengingat berhenti sendiri setelah beberapa hari.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}
