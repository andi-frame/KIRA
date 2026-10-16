import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/diagnosis_dialog.dart';
import '../../shared/widgets.dart';
import '../auth/login_screen.dart' show usernamePattern, usernameRule;

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
          padding: context.pagePadding,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(KiraSpace.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.displayName ?? 'Kamu', style: context.text.headlineSmall),
                  if (p.username != null)
                    Text('@${p.username}', style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant))
                  else
                    TextButton.icon(
                      key: const Key('tile_username'),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                      icon: const Icon(Icons.alternate_email, size: 18),
                      label: const Text('Buat nama pengguna untuk masuk'),
                      onPressed: () => showDialog<void>(context: context, builder: (_) => const _UsernameDialog()),
                    ),
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
            const SectionHeader('Kesehatanmu'),
            LinkGroup(children: [
                ListTile(
                  key: const Key('tile_doctor'),
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Ringkasan untuk dokter'),
                  subtitle: const Text('Satu halaman untuk dibawa'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/doctor'),
                ),
                ListTile(
                  key: const Key('tile_records'),
                  leading: const Icon(Icons.folder_shared_outlined),
                  title: const Text('Rekam medis'),
                  subtitle: const Text('Diagnosis, lab, obat, alergi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/records'),
                ),
                ListTile(
                  key: const Key('tile_trends'),
                  leading: const Icon(Icons.show_chart),
                  title: const Text('Tren dan penanda'),
                  subtitle: const Text('Tensi, gula darah, kebiasaan'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/trends'),
                ),
                ListTile(
                  key: const Key('tile_plan'),
                  leading: const Icon(Icons.event_note_outlined),
                  title: const Text('Rencana'),
                  subtitle: const Text('Usulan makan, olahraga, tidur'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/plan'),
                ),
                ListTile(
                  key: const Key('tile_diagnosis'),
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('Tandai diagnosis dokter'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDiagnosisDialog(context),
                ),
            ]),
            const SectionHeader('Terhubung'),
            LinkGroup(children: [
                ListTile(
                  key: const Key('tile_family'),
                  leading: const Icon(Icons.group_outlined),
                  title: const Text('Keluarga'),
                  subtitle: const Text('Undang dan pilih yang dibagikan'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/family'),
                ),
                ListTile(
                  key: const Key('tile_health'),
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: const Text('Langkah dan tidur'),
                  subtitle: const Text('Dari Health Connect'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/health'),
                ),
                ListTile(
                  key: const Key('tile_whatsapp'),
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('Tautkan WhatsApp'),
                  subtitle: const Text('Check-in tanpa membuka aplikasi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showWhatsapp(context, ref),
                ),
            ]),
            const SectionHeader('Pengaturan'),
            LinkGroup(children: [
                ListTile(
                  key: const Key('tile_reminders'),
                  leading: const Icon(Icons.notifications_none),
                  title: const Text('Pengingat'),
                  subtitle: const Text('Hanya yang kamu nyalakan'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/reminders'),
                ),
                ListTile(
                  key: const Key('tile_jeda'),
                  leading: const Icon(Icons.hourglass_bottom),
                  title: const Text('Jeda sosmed'),
                  subtitle: const Text('Kartu singkat sebelum sosmed'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/jeda'),
                ),
                ListTile(
                  key: const Key('tile_privacy'),
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Data dan privasi'),
                  subtitle: const Text('Akses, unduh, PIN, hapus akun'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/privacy'),
                ),
            ]),
            TextButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Keluar'),
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted && Navigator.canPop(context)) Navigator.pop(context);
              },
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



class _UsernameDialog extends ConsumerStatefulWidget {
  const _UsernameDialog();

  @override
  ConsumerState<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends ConsumerState<_UsernameDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim().toLowerCase();
    if (!usernamePattern.hasMatch(name)) {
      setState(() => _error = usernameRule);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).setUsername(name);
      ref.invalidate(profileProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nama pengguna'),
      content: TextField(
        key: const Key('username_input'),
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: 'Nama pengguna',
          helperText: 'Dipakai untuk masuk, bersama atau sebagai pengganti nomor HP',
          helperMaxLines: 2,
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(key: const Key('username_save'), onPressed: _busy ? null : _save, child: const Text('Simpan')),
      ],
    );
  }
}
