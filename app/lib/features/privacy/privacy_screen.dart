import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/share_service.dart';
import '../../core/theme.dart';
import '../../shared/account_models.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart';
import 'consent_text.dart';

final accessLogProvider = FutureProvider<List<AccessEntry>>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getAccessLog();
});

/// Data dan privasi: persetujuan, siapa yang membuka datamu, unduh data, ganti PIN, hapus akun.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await ref.read(apiProvider).exportAccount();
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      await ref.read(shareServiceProvider).shareFile(
            Uint8List.fromList(utf8.encode(json)),
            'kira-data-$stamp.json',
            'application/json',
            subject: 'Salinan data KIRA',
            message: 'Salinan data KIRA milikku. Berisi data kesehatan, simpan dengan hati-hati.',
          );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Data belum bisa diunduh. Coba lagi sebentar lagi ya.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(accessLogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Data dan privasi')),
      body: ListView(
        padding: context.pagePadding,
        children: [
          const PageIntro('Datamu milikmu: lihat siapa yang membukanya, unduh, atau hapus.'),
          const SizedBox(height: KiraSpace.lg),
          Card(
            child: ListTile(
              key: const Key('tile_consent'),
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Persetujuan data kesehatan'),
              subtitle: const Text('Baca apa saja yang diproses dan ke mana perginya'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showConsentSheet(context),
            ),
          ),
          const SizedBox(height: KiraSpace.lg),
          Card(
            key: const Key('access_log_card'),
            child: Padding(
              padding: const EdgeInsets.all(KiraSpace.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Siapa yang membuka datamu', style: context.text.titleMedium),
                const SizedBox(height: KiraSpace.xs),
                log.when(
                  loading: () => const Padding(padding: EdgeInsets.all(KiraSpace.md), child: LinearProgressIndicator()),
                  error: (_, _) => Text('Riwayat belum bisa dimuat.', style: context.text.bodyMedium),
                  data: (entries) => entries.isEmpty
                      ? Text(
                          'Belum ada. Setiap kali anggota keluarga atau penerima tautan dokter membuka ringkasanmu, '
                          'tercatat di sini.',
                          style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant),
                        )
                      : Column(children: [
                          for (final e in entries.take(10))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(e.isShareLink ? Icons.link : Icons.group_outlined),
                              title: Text(e.viewer),
                              subtitle: Text(
                                '${e.isShareLink ? 'Membuka tautan dokter' : 'Melihat status check-in'} · ${formatDateTime(e.at)}',
                              ),
                            ),
                        ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: KiraSpace.lg),
          Card(
            child: Column(children: [
              ListTile(
                key: const Key('tile_export'),
                leading: _exporting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_outlined),
                title: const Text('Unduh datamu'),
                subtitle: const Text('Satu berkas JSON berisi semua catatan, hasil cek, dan percakapan. PIN tidak ikut.'),
                onTap: _exporting ? null : _export,
              ),
              const Divider(),
              ListTile(
                key: const Key('tile_change_pin'),
                leading: const Icon(Icons.password_outlined),
                title: const Text('Ganti PIN'),
                subtitle: const Text('Perangkat lain akan keluar'),
                onTap: () => showDialog<void>(context: context, builder: (_) => const _ChangePinDialog()),
              ),
            ]),
          ),
          const SizedBox(height: KiraSpace.xl),
          OutlinedButton.icon(
            key: const Key('tile_delete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.scheme.error,
              side: BorderSide(color: context.scheme.error.withValues(alpha: 0.6)),
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Hapus akun dan semua data'),
            onPressed: () => showDialog<void>(context: context, builder: (_) => const _DeleteAccountDialog()),
          ),
          const SizedBox(height: KiraSpace.sm),
          Text(
            'Penghapusan permanen dan tidak bisa dibatalkan. Nomor HP dan nama penggunamu bisa dipakai mendaftar lagi.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({required this.fieldKey, required this.label, required this.controller, this.onSubmitted});
  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
        key: fieldKey,
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
        decoration: InputDecoration(labelText: label),
      );
}

class _ChangePinDialog extends ConsumerStatefulWidget {
  const _ChangePinDialog();

  @override
  ConsumerState<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends ConsumerState<_ChangePinDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _next2 = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _next2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = RegExp(r'^\d{4,6}$');
    if (!pin.hasMatch(_current.text)) return setState(() => _error = 'Isi PIN yang sekarang.');
    if (!pin.hasMatch(_next.text)) return setState(() => _error = 'PIN baru harus 4 sampai 6 angka.');
    if (_next.text != _next2.text) return setState(() => _error = 'Kedua PIN baru belum sama.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tokens = await ref.read(apiProvider).changePin(_current.text, _next.text);
      await ref.read(authProvider.notifier).storeRefreshed(tokens);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN sudah diganti.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ganti PIN'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _PinField(fieldKey: const Key('pin_current'), label: 'PIN sekarang', controller: _current),
            const SizedBox(height: KiraSpace.md),
            _PinField(fieldKey: const Key('pin_new'), label: 'PIN baru', controller: _next),
            const SizedBox(height: KiraSpace.md),
            _PinField(fieldKey: const Key('pin_new2'), label: 'Ulangi PIN baru', controller: _next2, onSubmitted: _save),
            if (_error != null) ...[
              const SizedBox(height: KiraSpace.md),
              Text(_error!, style: context.text.bodyMedium?.copyWith(color: context.scheme.error)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(key: const Key('pin_save'), onPressed: _busy ? null : _save, child: const Text('Simpan')),
        ],
      );
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(_pin.text)) return setState(() => _error = 'Isi PIN-mu untuk melanjutkan.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).deleteAccount(_pin.text);
      if (!mounted) return;
      Navigator.pop(context);
      await ref.read(authProvider.notifier).logout();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Hapus akun?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Semua catatan, hasil cek, percakapan, dan pengaturanmu dihapus dari server dan tidak bisa dipulihkan. '
              'Unduh datamu dulu bila ingin menyimpannya.',
            ),
            const SizedBox(height: KiraSpace.md),
            _PinField(fieldKey: const Key('delete_pin'), label: 'PIN untuk konfirmasi', controller: _pin, onSubmitted: _delete),
            if (_error != null) ...[
              const SizedBox(height: KiraSpace.md),
              Text(_error!, style: context.text.bodyMedium?.copyWith(color: context.scheme.error)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            key: const Key('delete_confirm'),
            style: FilledButton.styleFrom(backgroundColor: context.scheme.error, foregroundColor: context.scheme.onError),
            onPressed: _busy ? null : _delete,
            child: const Text('Hapus permanen'),
          ),
        ],
      );
}
