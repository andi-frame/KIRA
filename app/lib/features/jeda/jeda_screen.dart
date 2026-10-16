import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'jeda_bridge.dart';
import 'jeda_controller.dart';
import 'jeda_models.dart';

/// Pengaturan Jeda Sosmed. Mati sampai pengguna menyalakannya, dan tiap izin dijelaskan sebelum diminta.
class JedaScreen extends ConsumerStatefulWidget {
  const JedaScreen({super.key});

  @override
  ConsumerState<JedaScreen> createState() => _JedaScreenState();
}

class _JedaScreenState extends ConsumerState<JedaScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(jedaProvider.notifier).load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kembali dari layar izin Android: baca ulang izin.
    if (state == AppLifecycleState.resumed) ref.read(jedaProvider.notifier).refreshPermissions();
  }

  JedaController get _c => ref.read(jedaProvider.notifier);

  Future<void> _pick(int current, void Function(int) apply) async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60));
    if (picked != null) apply(picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(jedaBridgeProvider);
    final state = ref.watch(jedaProvider);
    final s = state.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Jeda sosmed')),
      body: ListView(
        padding: context.pagePadding,
        children: [
          Text(
            'Sebelum membuka Instagram, X, Facebook, atau aplikasi lain yang kamu pilih, KIRA menampilkan satu kartu '
            'singkat: rencana pagi, ajakan mencatat malam hari, atau pengingat tidur. Kamu yang menentukan, dan bisa '
            'dimatikan kapan saja.',
            style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant),
          ),
          const SizedBox(height: KiraSpace.lg),
          if (!bridge.supported)
            const SoftNote(
              key: Key('jeda_unsupported'),
              icon: Icons.phone_android,
              text: 'Fitur ini hanya tersedia di aplikasi KIRA untuk Android, karena iOS dan web tidak mengizinkan '
                  'aplikasi mengetahui aplikasi lain yang sedang dibuka.',
            )
          else ...[
            Card(
              child: SwitchListTile(
                key: const Key('jeda_enabled'),
                title: const Text('Jeda sebelum sosmed'),
                subtitle: Text(_status(state)),
                value: s.enabled,
                onChanged: (v) => _c.update(s.copyWith(enabled: v)),
              ),
            ),
            if (s.enabled) ...[
              const SizedBox(height: KiraSpace.lg),
              _Permissions(state: state, bridge: bridge),
              const SizedBox(height: KiraSpace.lg),
              _Apps(state: state, onChanged: (apps) => _c.update(s.copyWith(apps: apps))),
              const SizedBox(height: KiraSpace.lg),
              Card(
                child: Column(children: [
                  _TimeTile(
                    k: 'jeda_time_morning',
                    icon: Icons.wb_sunny_outlined,
                    title: 'Rencana pagi',
                    subtitle: 'Mulai ${clock(s.morningStart)}, selama 6 jam: olahraga, makan, dan contohnya',
                    value: s.morningStart,
                    onTap: () => _pick(s.morningStart, (v) => _c.update(s.copyWith(morningStart: v))),
                  ),
                  const Divider(height: 1),
                  _TimeTile(
                    k: 'jeda_time_evening',
                    icon: Icons.edit_note,
                    title: 'Catat hari ini',
                    subtitle: 'Mulai ${clock(s.eveningStart)} sampai tengah malam, hanya bila ada yang belum tercatat',
                    value: s.eveningStart,
                    onTap: () => _pick(s.eveningStart, (v) => _c.update(s.copyWith(eveningStart: v))),
                  ),
                  const Divider(height: 1),
                  _TimeTile(
                    k: 'jeda_time_night',
                    icon: Icons.bedtime_outlined,
                    title: 'Waktunya tidur',
                    subtitle: 'Mulai ${clock(s.nightStart)} sampai pukul 04.00',
                    value: s.nightStart,
                    onTap: () => _pick(s.nightStart, (v) => _c.update(s.copyWith(nightStart: v))),
                  ),
                ]),
              ),
              const SizedBox(height: KiraSpace.sm),
              Card(
                child: SwitchListTile(
                  key: const Key('jeda_other'),
                  title: const Text('Info lain: sudah sempat cek?'),
                  subtitle: const Text('Sekali sehari bila saran cek ke dokter atau puskesmas belum kamu jawab'),
                  value: s.showOther,
                  onChanged: (v) => _c.update(s.copyWith(showOther: v)),
                ),
              ),
              const SizedBox(height: KiraSpace.sm),
              Card(
                child: SwitchListTile(
                  key: const Key('jeda_fun_fact'),
                  secondary: const Icon(Icons.lightbulb_outline),
                  title: const Text('Fun fact kesehatan'),
                  subtitle: const Text(
                    'Tiap kali sosmed dibuka, tampil satu fakta singkat berserta sumbernya (WHO, Kemenkes, jurnal), '
                    'supaya kamu memilih dengan sadar: lanjut atau tidak.',
                  ),
                  value: s.funFact,
                  onChanged: (v) => _c.update(s.copyWith(funFact: v)),
                ),
              ),
              const SizedBox(height: KiraSpace.sm),
              Card(
                child: Column(children: [
                  SwitchListTile(
                    key: const Key('jeda_use_grace'),
                    secondary: const Icon(Icons.timer_outlined),
                    title: const Text('Setelah kartu ditutup, bebas buka sosmed selama'),
                    subtitle: Text(s.useGrace
                        ? 'Setelah kamu menekan Lanjut, semua aplikasi pilihan bebas dibuka selama ${s.graceMinutes} menit.'
                        : 'Mati: kartu muncul lagi setiap kali sosmed dibuka.'),
                    value: s.useGrace,
                    onChanged: (v) => _c.update(s.copyWith(useGrace: v)),
                  ),
                  if (s.useGrace)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(KiraSpace.lg, 0, KiraSpace.lg, KiraSpace.md),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(spacing: KiraSpace.sm, children: [
                          for (final m in JedaSettings.graceChoices)
                            ChoiceChip(
                              key: Key('jeda_grace_$m'),
                              label: Text('$m menit'),
                              selected: s.graceMinutes == m,
                              onSelected: (_) => _c.update(s.copyWith(graceMinutes: m)),
                            ),
                        ]),
                      ),
                    ),
                ]),
              ),
              if (state.running) ...[
                const SizedBox(height: KiraSpace.lg),
                Text('Lihat contohnya sekarang', style: context.text.titleSmall),
                const SizedBox(height: KiraSpace.sm),
                Wrap(spacing: KiraSpace.sm, runSpacing: KiraSpace.sm, children: [
                  for (final (kind, label) in [
                    ('morning', 'Pagi'),
                    ('evening', 'Catat'),
                    ('night', 'Tidur'),
                    ('other', 'Cek'),
                    if (s.funFact) ('fact', 'Fun fact'),
                  ])
                    OutlinedButton(
                      key: Key('jeda_preview_$kind'),
                      onPressed: () => _c.preview(kind),
                      child: Text(label),
                    ),
                ]),
              ],
            ],
            const SizedBox(height: KiraSpace.lg),
            const SoftNote(
              icon: Icons.lock_outline,
              text: 'KIRA hanya tahu nama aplikasi yang sedang dibuka, bukan isinya, dan tidak mengirimnya ke mana pun. '
                  'Isi kartu disimpan di ponselmu saja. Kartu bisa dilewati untuk hari ini, dan hanya muncul untuk '
                  'aplikasi yang kamu centang.',
            ),
          ],
        ],
      ),
    );
  }

  String _status(JedaState s) {
    if (!s.settings.enabled) return 'Mati';
    if (!s.permissions.ready) return 'Menunggu izin di bawah';
    if (s.settings.apps.isEmpty) return 'Pilih minimal satu aplikasi';
    return 'Menjaga ${s.settings.apps.length} aplikasi';
  }
}

class _Permissions extends StatelessWidget {
  const _Permissions({required this.state, required this.bridge});
  final JedaState state;
  final JedaBridge bridge;

  @override
  Widget build(BuildContext context) {
    final p = state.permissions;
    return Card(
      child: Column(children: [
        _PermissionTile(
          k: 'jeda_perm_usage',
          title: 'Akses penggunaan aplikasi',
          why: 'Agar KIRA tahu kapan aplikasi sosmed yang kamu pilih dibuka.',
          granted: p.usageAccess,
          onGrant: bridge.openUsageAccess,
        ),
        const Divider(height: 1),
        _PermissionTile(
          k: 'jeda_perm_overlay',
          title: 'Tampil di atas aplikasi lain',
          why: 'Agar kartu bisa muncul sebelum aplikasi sosmed terbuka.',
          granted: p.overlay,
          onGrant: bridge.openOverlay,
        ),
        if (!p.ready) ...[
          const Divider(height: 1),
          _RestrictedHelp(bridge: bridge),
        ],
      ]),
    );
  }
}

/// Android 13 ke atas mengunci izin sensitif untuk aplikasi yang dipasang manual (bukan dari toko aplikasi), dan Android 15
/// memperluasnya ke akses penggunaan serta tampil di atas aplikasi lain. Kuncinya dibuka pengguna sendiri lewat Info aplikasi.
class _RestrictedHelp extends StatelessWidget {
  const _RestrictedHelp({required this.bridge});
  final JedaBridge bridge;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('jeda_restricted_help'),
        leading: const Icon(Icons.lock_open_outlined),
        title: const Text('Izin abu-abu atau "Dikontrol oleh setelan terbatas"?'),
        childrenPadding: const EdgeInsets.fromLTRB(KiraSpace.lg, 0, KiraSpace.lg, KiraSpace.lg),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aplikasi yang dipasang dari berkas APK (bukan dari toko aplikasi) dikunci Android untuk izin sensitif. Kamu bisa '
            'membukanya sendiri, hanya sekali:',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: KiraSpace.sm),
          Text('1. Tekan "Buka Info aplikasi" di bawah.\n'
              '2. Ketuk titik tiga (⋮) di pojok kanan atas, lalu pilih "Izinkan setelan terbatas" dan konfirmasi dengan PIN '
              'atau sidik jarimu.\n'
              '3. Kembali ke sini dan tekan Izinkan lagi.\n\n'
              'Kalau menu ⋮ belum ada, tekan Izinkan di atas sekali dulu sampai muncul pesan terkunci, tutup pesannya, lalu '
              'buka Info aplikasi lagi.',
              key: const Key('jeda_restricted_steps'),
              style: context.text.bodyMedium),
          const SizedBox(height: KiraSpace.md),
          OutlinedButton.icon(
            key: const Key('jeda_open_app_info'),
            onPressed: bridge.openAppInfo,
            icon: const Icon(Icons.settings_applications_outlined),
            label: const Text('Buka Info aplikasi'),
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({required this.k, required this.title, required this.why, required this.granted, required this.onGrant});
  final String k, title, why;
  final bool granted;
  final Future<void> Function() onGrant;

  @override
  Widget build(BuildContext context) => ListTile(
        key: Key(k),
        leading: Icon(granted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: granted ? context.scheme.primary : context.scheme.outline),
        title: Text(title),
        subtitle: Text(why),
        trailing: granted ? const Text('Diizinkan') : FilledButton.tonal(onPressed: onGrant, child: const Text('Izinkan')),
      );
}

class _Apps extends StatelessWidget {
  const _Apps({required this.state, required this.onChanged});
  final JedaState state;
  final void Function(List<String>) onChanged;

  @override
  Widget build(BuildContext context) {
    final chosen = state.settings.apps.toSet();
    if (state.installed.isEmpty) {
      return const SoftNote(icon: Icons.apps, text: 'Belum ada aplikasi sosmed yang dikenali di ponsel ini.');
    }
    return Card(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(KiraSpace.lg, KiraSpace.md, KiraSpace.lg, 0),
          child: Align(alignment: Alignment.centerLeft, child: Text('Aplikasi yang dijaga', style: context.text.titleSmall)),
        ),
        for (final a in state.installed)
          CheckboxListTile(
            key: Key('jeda_app_${a.package}'),
            title: Text(a.label),
            value: chosen.contains(a.package),
            onChanged: (v) => onChanged([
              for (final x in state.installed)
                if (x.package == a.package ? v == true : chosen.contains(x.package)) x.package,
            ]),
          ),
      ]),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.k, required this.icon, required this.title, required this.subtitle, required this.value, required this.onTap});
  final String k, title, subtitle;
  final IconData icon;
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        key: Key(k),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Text(clock(value), style: context.text.titleMedium),
        onTap: onTap,
      );
}
