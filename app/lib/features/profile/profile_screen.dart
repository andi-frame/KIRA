import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/diagnosis_dialog.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) => const Center(child: Text('Profil belum bisa dimuat.')),
        data: (p) => ListView(
          padding: const EdgeInsets.all(KiraSpace.lg),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(KiraSpace.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.displayName ?? 'Kamu', style: context.text.headlineSmall),
                  const SizedBox(height: KiraSpace.sm),
                  Chip(
                    avatar: Icon(p.isManagement ? Icons.favorite_outline : Icons.shield_outlined, size: 18),
                    label: Text(p.isManagement ? 'Mode pengelolaan' : 'Mode pencegahan'),
                  ),
                  const SizedBox(height: KiraSpace.lg),
                  _Row('Usia', p.age == null ? '-' : '${p.age} tahun'),
                  _Row('Jenis kelamin', p.sex == 'male' ? 'Laki-laki' : (p.sex == 'female' ? 'Perempuan' : '-')),
                  _Row('Tinggi', p.heightCm == null ? '-' : '${p.heightCm!.round()} cm'),
                  _Row('Berat', p.weightKg == null ? '-' : '${p.weightKg!.round()} kg'),
                ]),
              ),
            ),
            const SizedBox(height: KiraSpace.lg),
            OutlinedButton.icon(
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Tandai diagnosis dokter'),
              onPressed: () => showDiagnosisDialog(context),
            ),
            const SizedBox(height: KiraSpace.sm),
            TextButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Keluar'),
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted && Navigator.canPop(context)) Navigator.pop(context);
              },
            ),
            const SizedBox(height: KiraSpace.xl),
            Text(
              'KIRA bukan alat diagnosis dan tidak memberi saran obat. Data yang tampil di sini adalah data demo.',
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
        child: Row(children: [
          Expanded(child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant))),
          Text(value, style: context.text.bodyLarge),
        ]),
      );
}

