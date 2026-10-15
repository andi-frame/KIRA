import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'health_sync.dart';

String _lastSyncText(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Terakhir sinkron: ${t.day}/${t.month}/${t.year} ${two(t.hour)}.${two(t.minute)}';
}

/// Sinkronisasi langkah dan tidur dari Health Connect: dinyalakan sendiri oleh pengguna, bisa dimatikan kapan saja.
class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen({super.key});

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(healthSyncProvider.notifier).load());
  }

  Future<void> _confirmDisable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Matikan dan hapus?'),
        content: const Text(
          'KIRA berhenti membaca Health Connect dan menghapus catatan langkah dan tidur dari perangkat itu yang sudah '
          'tersimpan di KIRA. Catatan yang kamu ketik sendiri tidak ikut terhapus.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            key: const Key('health_disable_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Matikan dan hapus'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(healthSyncProvider.notifier).disable();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(healthSyncProvider);
    final controller = ref.read(healthSyncProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Langkah dan tidur')),
      body: ListView(
        padding: const EdgeInsets.all(KiraSpace.lg),
        children: [
          Text(
            'Kalau kamu mau, KIRA bisa mengisi catatan langkah dan tidur dari Health Connect di ponselmu, jadi kamu tidak perlu mengetiknya.',
            style: context.text.bodyLarge,
          ),
          const SizedBox(height: KiraSpace.lg),
          const SoftNote(
            icon: Icons.lock_outline,
            title: 'Yang dibaca',
            text: 'KIRA hanya membaca langkah dan sesi tidur 14 hari terakhir, tidak pernah menulis ke Health Connect. '
                'Kamu bisa mematikannya kapan saja, dan datanya ikut dihapus dari KIRA.',
          ),
          const SizedBox(height: KiraSpace.md),
          const SoftNote(
            icon: Icons.calculate_outlined,
            title: 'Cara menghitung menit aktif',
            text: 'Jalan dengan kecepatan 100 langkah per menit atau lebih dihitung sebagai aktivitas sedang '
                '(Tudor-Locke dkk., Int J Behav Nutr Phys Act 2019, untuk usia 21-40 tahun). Ini perkiraan KIRA: '
                'jalan santai yang panjang tidak ikut dihitung, jadi hasilnya cenderung lebih rendah dari kenyataan.',
          ),
          const SizedBox(height: KiraSpace.xl),
          if (s.message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: KiraSpace.md),
              child: Text(s.message!, key: const Key('health_message'), style: context.text.bodyMedium),
            ),
          if (s.enabled) ...[
            if (s.lastSync != null)
              Padding(
                padding: const EdgeInsets.only(bottom: KiraSpace.sm),
                child: Text(_lastSyncText(s.lastSync!), key: const Key('health_status'), style: context.text.bodyMedium),
              ),
            if (s.activityDays > 0 || s.sleepNights > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: KiraSpace.md),
                child: Text('${s.activityDays} hari langkah dan ${s.sleepNights} malam tidur diperbarui.',
                    style: context.text.bodySmall),
              ),
            FilledButton.icon(
              key: const Key('health_sync_button'),
              onPressed: s.busy ? null : controller.syncNow,
              icon: s.busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: const Text('Sinkronkan sekarang'),
            ),
            const SizedBox(height: KiraSpace.sm),
            TextButton.icon(
              key: const Key('health_disable_button'),
              onPressed: s.busy ? null : _confirmDisable,
              icon: const Icon(Icons.link_off),
              label: const Text('Matikan dan hapus datanya'),
            ),
          ] else
            FilledButton.icon(
              key: const Key('health_connect_button'),
              onPressed: s.busy ? null : controller.enable,
              icon: s.busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.monitor_heart_outlined),
              label: const Text('Hubungkan Health Connect'),
            ),
        ],
      ),
    );
  }
}
