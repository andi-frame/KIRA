import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/share_service.dart';
import '../../core/theme.dart';
import '../../shared/account_models.dart';
import '../../shared/labels.dart';

final shareLinksProvider = FutureProvider<List<ShareLinkData>>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).listShareLinks();
});

/// Tautan ringkasan untuk dokter: dokter membuka tanpa akun, tautan kedaluwarsa dan bisa dicabut kapan saja.
class ShareLinksCard extends ConsumerStatefulWidget {
  const ShareLinksCard({super.key, required this.days});
  final int days;

  @override
  ConsumerState<ShareLinksCard> createState() => _ShareLinksCardState();
}

class _ShareLinksCardState extends ConsumerState<ShareLinksCard> {
  int _validDays = 7;
  bool _busy = false;
  ShareLinkData? _fresh; // tautan yang baru dibuat; URL-nya hanya terlihat sekarang

  String _message(ShareLinkData link) =>
      'Ringkasan KIRA untuk dokter (${link.days} hari). Berlaku sampai ${formatDate(link.expiresAt)}. '
      'Dibuat otomatis dari catatan pengguna; bukan diagnosis.\n${link.url}';

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final link = await ref.read(apiProvider).createShareLink(days: widget.days, validDays: _validDays);
      ref.invalidate(shareLinksProvider);
      if (mounted) setState(() => _fresh = link);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(ShareLinkData link) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiProvider).revokeShareLink(link.id);
      ref.invalidate(shareLinksProvider);
      if (_fresh?.id == link.id && mounted) setState(() => _fresh = null);
      messenger.showSnackBar(const SnackBar(content: Text('Tautan dicabut. Tidak bisa dibuka lagi.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final links = ref.watch(shareLinksProvider);
    final fresh = _fresh;
    return Card(
      key: const Key('share_links_card'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tautan untuk dokter', style: context.text.titleMedium),
          const SizedBox(height: KiraSpace.xs),
          Text(
            'Dokter membuka ringkasan ${widget.days} hari lewat tautan, tanpa perlu akun. Tautannya sementara dan bisa '
            'kamu cabut kapan saja.',
            style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant),
          ),
          const SizedBox(height: KiraSpace.md),
          Wrap(spacing: KiraSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Berlaku', style: context.text.bodyMedium),
            for (final d in const [1, 7, 30])
              ChoiceChip(
                key: Key('valid_$d'),
                label: Text(d == 1 ? '1 hari' : '$d hari'),
                selected: _validDays == d,
                onSelected: (_) => setState(() => _validDays = d),
              ),
          ]),
          const SizedBox(height: KiraSpace.md),
          FilledButton.icon(
            key: const Key('create_share_link'),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.link),
            label: const Text('Buat tautan'),
            onPressed: _busy ? null : _create,
          ),
          if (fresh != null && fresh.url != null) ...[
            const SizedBox(height: KiraSpace.md),
            Container(
              key: const Key('fresh_link'),
              padding: const EdgeInsets.all(KiraSpace.md),
              decoration: BoxDecoration(
                color: context.scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(KiraRadius.field),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SelectableText(fresh.url!, style: context.text.bodyMedium),
                const SizedBox(height: KiraSpace.xs),
                Text(
                  'Berlaku sampai ${formatDateTime(fresh.expiresAt)}. Tautan ini hanya ditampilkan sekarang; '
                  'bagikan atau salin sebelum menutup.',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: KiraSpace.sm),
                Wrap(spacing: KiraSpace.sm, children: [
                  FilledButton.tonalIcon(
                    key: const Key('share_link_send'),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Bagikan'),
                    onPressed: () => ref.read(shareServiceProvider).shareText(_message(fresh), subject: 'Ringkasan KIRA'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('share_link_copy'),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Salin'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: fresh.url!));
                      messenger.showSnackBar(const SnackBar(content: Text('Tautan disalin.')));
                    },
                  ),
                ]),
              ]),
            ),
          ],
          const SizedBox(height: KiraSpace.md),
          links.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Text('Daftar tautan belum bisa dimuat.', style: context.text.bodyMedium),
            data: (all) {
              final active = all.where((l) => l.active).toList();
              if (active.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tautan aktif', style: context.text.titleSmall),
                for (final l in active)
                  ListTile(
                    key: Key('link_${l.id}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('${l.days} hari · sampai ${formatDate(l.expiresAt)}'),
                    subtitle: Text(l.openCount == 0 ? 'Belum dibuka' : 'Dibuka ${l.openCount} kali'),
                    trailing: TextButton(
                      key: Key('revoke_${l.id}'),
                      onPressed: () => _revoke(l),
                      child: const Text('Cabut'),
                    ),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}
