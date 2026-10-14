import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
            Card(
              child: Column(children: [
                ListTile(
                  key: const Key('tile_doctor'),
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Ringkasan untuk dokter'),
                  subtitle: const Text('Pola makan, tidur, dan hasil cek dalam satu halaman'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/doctor'),
                ),
                const Divider(),
                ListTile(
                  key: const Key('tile_family'),
                  leading: const Icon(Icons.group_outlined),
                  title: const Text('Keluarga'),
                  subtitle: const Text('Undang, dan pilih apa yang dibagikan'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/family'),
                ),
                const Divider(),
                ListTile(
                  key: const Key('tile_whatsapp'),
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('Tautkan WhatsApp'),
                  subtitle: const Text('Check-in lewat WhatsApp tanpa membuka aplikasi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showWhatsapp(context, ref),
                ),
              ]),
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

Future<void> _showWhatsapp(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tautkan WhatsApp'),
      content: FutureBuilder<String>(
        future: ref.read(apiProvider).whatsappLinkCode(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 56, child: Center(child: CircularProgressIndicator.adaptive()));
          }
          if (snap.hasError) return const Text('Kode belum bisa dibuat. Coba lagi sebentar lagi ya.');
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Kirim kode ini ke nomor bot KIRA di WhatsApp. Kode berlaku 15 menit dan hanya sekali pakai.'),
            const SizedBox(height: KiraSpace.md),
            Center(child: SelectableText(snap.data!, key: const Key('wa_code'), style: context.text.headlineMedium)),
            const SizedBox(height: KiraSpace.md),
            Text(
              'Kanal WhatsApp masih prototype (tidak resmi): pakai nomor khusus dan data dummy.',
              style: context.text.bodySmall,
            ),
          ]);
        },
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
    ),
  );
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

