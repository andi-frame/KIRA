import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/family_models.dart';
import '../../shared/widgets.dart';

final familyProvider = FutureProvider<FamilyOverview>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getFamily();
});

final _phonePattern = RegExp(r'^\+?\d{8,15}$');

class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({super.key});

  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  final _phone = TextEditingController();
  var _perms = const FamilyPermissions();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(familyProvider);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    final phone = _phone.text.trim();
    if (!_phonePattern.hasMatch(phone)) {
      setState(() => _error = 'Nomor HP belum sesuai. Pakai angka saja, 8 sampai 15 digit.');
      return;
    }
    await _run(() async {
      await ref.read(apiProvider).inviteFamily(phone, _perms);
      _phone.clear();
    });
  }

  Future<void> _confirmRemove(FamilyMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cabut akses?'),
        content: Text('${m.phone} tidak akan bisa lagi melihat ringkasan apa pun. Kamu bisa mengundang lagi nanti.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(key: const Key('confirm_remove'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Cabut')),
        ],
      ),
    );
    if (ok == true) await _run(() => ref.read(apiProvider).endFamily(m.id));
  }

  @override
  Widget build(BuildContext context) {
    final family = ref.watch(familyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Keluarga')),
      body: family.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => LoadError(
          message: e is ApiException ? e.message : 'Ada kendala saat memuat. Coba lagi sebentar lagi ya.',
          onRetry: () => ref.invalidate(familyProvider),
        ),
        data: (f) => ListView(
          padding: const EdgeInsets.all(KiraSpace.lg),
          children: [
            const SoftNote(
              key: Key('family_intro'),
              icon: Icons.lock_outline,
              title: 'Kamu yang memilih apa yang dibagikan',
              text: 'Keluarga hanya melihat status check-in dan apakah ada anjuran cek, tidak pernah detail makanan, '
                  'hasil lab, atau skor risiko. Akses bisa dicabut kapan saja, dan keluarga tidak bisa mengubah datamu.',
            ),
            if (f.invitesForMe.isNotEmpty) ...[
              const SizedBox(height: KiraSpace.xl),
              Text('Undangan untukmu', style: context.text.titleMedium),
              const SizedBox(height: KiraSpace.sm),
              for (final i in f.invitesForMe)
                Card(
                  child: ListTile(
                    title: Text('${i.ownerName} mengundangmu'),
                    subtitle: const Text('Kamu akan melihat status check-in dan anjuran cek yang dia bagikan.'),
                    trailing: Wrap(spacing: KiraSpace.xs, children: [
                      TextButton(
                        key: Key('decline_${i.id}'),
                        onPressed: _busy ? null : () => _run(() => ref.read(apiProvider).endFamily(i.id)),
                        child: const Text('Tolak'),
                      ),
                      FilledButton(
                        key: Key('accept_${i.id}'),
                        onPressed: _busy ? null : () => _run(() => ref.read(apiProvider).acceptFamily(i.id)),
                        child: const Text('Terima'),
                      ),
                    ]),
                  ),
                ),
            ],
            const SizedBox(height: KiraSpace.xl),
            Text('Keluarga yang kamu undang', style: context.text.titleMedium),
            const SizedBox(height: KiraSpace.sm),
            if (f.members.isEmpty)
              Text('Belum ada yang diundang.', key: const Key('family_empty'), style: context.text.bodyMedium)
            else
              for (final m in f.members) _MemberCard(member: m, busy: _busy, onChange: (p) => _run(() => ref.read(apiProvider).setFamilyPermissions(m.id, p)), onRemove: () => _confirmRemove(m)),
            const SizedBox(height: KiraSpace.xl),
            Text('Undang anggota keluarga', style: context.text.titleMedium),
            const SizedBox(height: KiraSpace.sm),
            TextField(
              key: const Key('invite_phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
              decoration: const InputDecoration(labelText: 'Nomor HP yang diundang', helperText: 'Contoh: 081234567890'),
            ),
            SwitchListTile(
              key: const Key('invite_perm_checkin'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Bagikan status check-in'),
              value: _perms.checkinStatus,
              onChanged: (v) => setState(() => _perms = _perms.copyWith(checkinStatus: v)),
            ),
            SwitchListTile(
              key: const Key('invite_perm_reminders'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Bagikan apakah ada anjuran cek'),
              value: _perms.checkReminders,
              onChanged: (v) => setState(() => _perms = _perms.copyWith(checkReminders: v)),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: KiraSpace.sm),
                child: Text(_error!, key: const Key('invite_error'), style: context.text.bodyMedium?.copyWith(color: context.scheme.error)),
              ),
            const SizedBox(height: KiraSpace.md),
            FilledButton(key: const Key('invite_send'), onPressed: _busy ? null : _invite, child: const Text('Kirim undangan')),
            if (f.watching.isNotEmpty) ...[
              const SizedBox(height: KiraSpace.xxl),
              Text('Kamu mendampingi', style: context.text.titleMedium),
              const SizedBox(height: KiraSpace.sm),
              for (final w in f.watching)
                Card(
                  child: ListTile(
                    key: Key('watch_${w.id}'),
                    leading: const Icon(Icons.favorite_outline),
                    title: Text(w.ownerName),
                    subtitle: const Text('Lihat ringkasan yang dibagikan'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showStatus(context, w),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showStatus(BuildContext context, FamilyContact w) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _StatusSheet(contact: w),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.busy, required this.onChange, required this.onRemove});
  final FamilyMember member;
  final bool busy;
  final ValueChanged<FamilyPermissions> onChange;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = member.permissions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(member.phone, style: context.text.titleSmall),
                Text(member.isActive ? 'Aktif' : 'Menunggu persetujuan', style: context.text.bodySmall),
              ]),
            ),
            IconButton(
              key: Key('remove_${member.id}'),
              tooltip: 'Cabut akses',
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: busy ? null : onRemove,
            ),
          ]),
          SwitchListTile(
            key: Key('perm_checkin_${member.id}'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Status check-in'),
            value: p.checkinStatus,
            onChanged: busy ? null : (v) => onChange(p.copyWith(checkinStatus: v)),
          ),
          SwitchListTile(
            key: Key('perm_reminders_${member.id}'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Anjuran cek'),
            value: p.checkReminders,
            onChanged: busy ? null : (v) => onChange(p.copyWith(checkReminders: v)),
          ),
        ]),
      ),
    );
  }
}

class _StatusSheet extends ConsumerWidget {
  const _StatusSheet({required this.contact});
  final FamilyContact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: FutureBuilder<FamilyStatus>(
        future: ref.read(apiProvider).getFamilyStatus(contact.id),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(KiraSpace.xl), child: Center(child: CircularProgressIndicator.adaptive()));
          }
          if (snap.hasError) {
            return const Padding(padding: EdgeInsets.all(KiraSpace.xl), child: Text('Ringkasan belum bisa dimuat. Coba lagi nanti ya.'));
          }
          final s = snap.data!;
          final last = s.daysAgo == null
              ? 'Belum ada check-in.'
              : (s.daysAgo == 0 ? 'Check-in terakhir: hari ini.' : 'Check-in terakhir: ${s.daysAgo} hari lalu.');
          return Padding(
            padding: const EdgeInsets.fromLTRB(KiraSpace.xl, 0, KiraSpace.xl, KiraSpace.xl),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ringkasan ${s.ownerName}', style: context.text.titleLarge),
              const SizedBox(height: KiraSpace.md),
              Text(s.checkinShared ? last : 'Status check-in tidak dibagikan.', style: context.text.bodyLarge),
              if (s.suggestion != null) ...[
                const SizedBox(height: KiraSpace.sm),
                Text(s.suggestion!, style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: KiraSpace.md),
              Text(
                s.remindersShared
                    ? (s.hasOpenCheck == true
                        ? 'Ada anjuran pemeriksaan yang masih terbuka. Bantu ingatkan dengan lembut.'
                        : 'Tidak ada anjuran pemeriksaan yang terbuka.')
                    : 'Anjuran cek tidak dibagikan.',
                style: context.text.bodyLarge,
              ),
            ]),
          );
        },
      ),
    );
  }
}
