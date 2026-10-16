import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/refresh.dart';
import '../../core/theme.dart';
import '../../shared/engagement_models.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart';
import '../check/check_screen.dart' show validatePressure, validatePulse;

final bpProtocolProvider = FutureProvider<BpProtocolView>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getBpProtocol();
});

String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

/// Ukur tensi di rumah 7 hari mengikuti protokol ESH 2021: pagi dan malam, dua kali tiap sesi, hari pertama dibuang.
/// Rata-ratanya jauh lebih dapat dipercaya daripada satu bacaan, dan menjadi satu hasil cek yang dipakai proyeksi.
class BpProtocolScreen extends ConsumerStatefulWidget {
  const BpProtocolScreen({super.key});

  @override
  ConsumerState<BpProtocolScreen> createState() => _BpProtocolScreenState();
}

class _BpProtocolScreenState extends ConsumerState<BpProtocolScreen> {
  bool _busy = false;
  String? _flag; // pesan darurat dari bacaan atau rata-rata yang berbahaya

  Future<void> _run(Future<BpProtocolView> Function() call, {bool finishing = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final view = await call();
      ref.invalidate(bpProtocolProvider);
      if (finishing && view.redFlag == null) {
        refreshHealthData(ref.invalidate); // hasil protokol menjadi hasil tensi: proyeksi, saran cek, tren, penanda
      }
      if (mounted) setState(() => _flag = view.redFlag);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan putaran ini?'),
        content: const Text('Bacaan yang sudah dicatat di putaran ini tidak akan dipakai. Kamu bisa memulai putaran baru kapan saja.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Lanjutkan')),
          FilledButton(key: const Key('bp_cancel_confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Batalkan')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(apiProvider).cancelBpProtocol();
    ref.invalidate(bpProtocolProvider);
  }

  Future<void> _addReading() async {
    final view = await showModalBottomSheet<BpProtocolView>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReadingSheet(),
    );
    if (view == null) return;
    ref.invalidate(bpProtocolProvider);
    if (mounted) setState(() => _flag = view.redFlag);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(bpProtocolProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tensi di rumah 7 hari')),
      body: view.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => LoadError(
          message: e is ApiException ? e.message : 'Belum bisa dimuat. Coba lagi sebentar lagi ya.',
          onRetry: () => ref.invalidate(bpProtocolProvider),
        ),
        data: (v) => ListView(
          padding: context.pagePadding,
          children: [
            if (_flag != null) ...[
              EmergencyCard(message: _flag!),
              const SizedBox(height: KiraSpace.lg),
            ],
            if (v.protocol == null)
              _Intro(busy: _busy, onStart: () => _run(() => ref.read(apiProvider).startBpProtocol()))
            else if (v.protocol!.active)
              _Active(
                state: v.protocol!,
                busy: _busy,
                onAdd: _addReading,
                onFinish: () => _run(() => ref.read(apiProvider).finishBpProtocol(), finishing: true),
                onCancel: _cancel,
              )
            else
              _Done(
                state: v.protocol!,
                home: (v.homeSys, v.homeDia),
                busy: _busy,
                onAgain: () => _run(() => ref.read(apiProvider).startBpProtocol()),
              ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.busy, required this.onStart});
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('Selama 7 hari', 'Ukur pagi dan malam, sebelum makan dan sebelum minum obat (kalau ada).'),
      ('Dua kali tiap sesi', 'Ukur dua kali dengan jeda 1 menit. Catat keduanya.'),
      ('Duduk tenang dulu', 'Duduk bersandar 5 menit, kaki tidak menyilang, lengan sejajar jantung, jangan bicara.'),
      ('KIRA yang menghitung', 'Hari pertama dibuang, sisanya dirata-ratakan. Butuh minimal 3 hari dan 12 bacaan.'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Satu bacaan di klinik bisa lebih tinggi atau lebih rendah dari biasanya. Rata-rata beberapa hari di rumah lebih '
          'bisa dipegang, dan jadi bahan yang lebih baik untuk dokter.',
          style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant)),
      const SizedBox(height: KiraSpace.lg),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(KiraSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : KiraSpace.md),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: context.scheme.primaryContainer,
                    child: Text('${i + 1}', style: context.text.labelLarge?.copyWith(color: context.scheme.onPrimaryContainer)),
                  ),
                  const SizedBox(width: KiraSpace.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(steps[i].$1, style: context.text.titleSmall),
                      Text(steps[i].$2, style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: KiraSpace.lg),
      FilledButton.icon(
        key: const Key('bp_start'),
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.play_arrow),
        label: const Text('Mulai 7 hari'),
        onPressed: busy ? null : onStart,
      ),
      const SizedBox(height: KiraSpace.md),
      Text('Protokol mengikuti panduan ESH 2021 (Stergiou dkk.). Hasilnya penanda untuk dokter, bukan diagnosis.',
          style: context.text.bodySmall),
    ]);
  }
}

class _Active extends StatelessWidget {
  const _Active({required this.state, required this.busy, required this.onAdd, required this.onFinish, required this.onCancel});
  final BpProtocolState state;
  final bool busy;
  final VoidCallback onAdd, onFinish, onCancel;

  @override
  Widget build(BuildContext context) {
    final s = state.summary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Hari ke-${state.dayIndex} dari 7', key: const Key('bp_day_index'), style: context.text.headlineSmall),
      const SizedBox(height: KiraSpace.xs),
      Text(
        s.valid
            ? 'Sudah cukup untuk dihitung. Kamu boleh menyelesaikan sekarang atau menambah bacaan sampai hari ke-7.'
            : (s.missing ?? 'Catat tensimu pagi dan malam.'),
        key: const Key('bp_missing'),
        style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant),
      ),
      const SizedBox(height: KiraSpace.lg),
      _DayStrip(days: state.days),
      const SizedBox(height: KiraSpace.sm),
      Text('Lingkaran penuh = 2 bacaan (cukup), setengah = 1 bacaan. Hari pertama dibuang dari rata-rata.', style: context.text.bodySmall),
      if (s.valid && s.avgSys != null) ...[
        const SizedBox(height: KiraSpace.lg),
        SoftNote(
          key: const Key('bp_preview'),
          icon: Icons.calculate_outlined,
          title: 'Rata-rata sementara',
          text: '${_n(s.avgSys!)}/${_n(s.avgDia!)} mmHg dari ${s.readingsUsed} bacaan di ${s.daysUsed} hari.',
        ),
      ],
      const SizedBox(height: KiraSpace.xl),
      FilledButton.icon(key: const Key('bp_add'), icon: const Icon(Icons.add), label: const Text('Catat tensi sekarang'), onPressed: onAdd),
      const SizedBox(height: KiraSpace.sm),
      OutlinedButton.icon(
        key: const Key('bp_finish'),
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.done_all),
        label: const Text('Selesai dan hitung rata-rata'),
        onPressed: state.canFinish && !busy ? onFinish : null,
      ),
      TextButton(key: const Key('bp_cancel'), onPressed: onCancel, child: const Text('Batalkan putaran')),
    ]);
  }
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.days});
  final List<BpDay> days;

  IconData _icon(int count) => count >= 2 ? Icons.circle : (count == 1 ? Icons.contrast : Icons.circle_outlined);

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('bp_days'),
      children: [
        for (final d in days)
          Expanded(
            child: Semantics(
              container: true,
              label: '${weekdayShort(d.date)} ${d.date.day}: pagi ${d.morning} bacaan, malam ${d.evening} bacaan'
                  '${d.discarded ? ', hari pertama dibuang' : ''}${d.isToday ? ', hari ini' : ''}',
              child: ExcludeSemantics(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: KiraSpace.sm),
                  decoration: BoxDecoration(
                    color: d.isToday ? context.scheme.primaryContainer : context.scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(KiraRadius.chip),
                  ),
                  child: Column(children: [
                    Text(weekdayShort(d.date), style: context.text.labelSmall),
                    Text('${d.date.day}', style: context.text.titleSmall),
                    const SizedBox(height: KiraSpace.xs),
                    Icon(_icon(d.morning), size: 14, color: context.scheme.primary),
                    const SizedBox(height: 2),
                    Icon(_icon(d.evening), size: 14, color: context.scheme.tertiary),
                    SizedBox(
                      height: 14,
                      child: d.discarded ? Text('dibuang', style: context.text.labelSmall?.copyWith(fontSize: 9)) : null,
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReadingSheet extends ConsumerStatefulWidget {
  const _ReadingSheet();

  @override
  ConsumerState<_ReadingSheet> createState() => _ReadingSheetState();
}

class _ReadingSheetState extends ConsumerState<_ReadingSheet> {
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _pulse = TextEditingController();
  late String _session = DateTime.now().hour < 12 ? 'morning' : 'evening';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _sys.dispose();
    _dia.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = validatePressure(_sys.text, _dia.text) ?? validatePulse(_pulse.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final view = await ref.read(apiProvider).addBpReading(
            int.parse(_sys.text.trim()),
            int.parse(_dia.text.trim()),
            _session,
            pulse: _pulse.text.trim().isEmpty ? null : int.parse(_pulse.text.trim()),
          );
      if (mounted) Navigator.pop(context, view);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.isNetwork ? 'Butuh sinyal untuk mencatat bacaan protokol. Coba lagi saat tersambung.' : e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(KiraSpace.xl, 0, KiraSpace.xl, KiraSpace.xl + inset),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Catat satu bacaan', style: context.text.titleLarge),
          const SizedBox(height: KiraSpace.xs),
          Text('Duduk tenang 5 menit. Ukur dua kali, jeda 1 menit, lalu catat keduanya satu per satu.', style: context.text.bodyMedium),
          const SizedBox(height: KiraSpace.lg),
          SegmentedButton<String>(
            key: const Key('bp_session'),
            segments: const [
              ButtonSegment(value: 'morning', label: Text('Pagi'), icon: Icon(Icons.wb_sunny_outlined)),
              ButtonSegment(value: 'evening', label: Text('Malam'), icon: Icon(Icons.nights_stay_outlined)),
            ],
            selected: {_session},
            onSelectionChanged: (s) => setState(() => _session = s.first),
          ),
          const SizedBox(height: KiraSpace.lg),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('bp_sys'),
                controller: _sys,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                decoration: const InputDecoration(labelText: 'Atas (sistolik)', suffixText: 'mmHg'),
              ),
            ),
            const SizedBox(width: KiraSpace.md),
            Expanded(
              child: TextField(
                key: const Key('bp_dia'),
                controller: _dia,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                decoration: const InputDecoration(labelText: 'Bawah (diastolik)', suffixText: 'mmHg'),
              ),
            ),
          ]),
          const SizedBox(height: KiraSpace.md),
          TextField(
            key: const Key('bp_pulse'),
            controller: _pulse,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Detak jantung / nadi (boleh dikosongkan)',
              suffixText: 'kali/menit',
              helperText: 'Biasanya tampil di layar tensimeter.',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: KiraSpace.md),
            Semantics(
              liveRegion: true,
              child: Text(_error!, key: const Key('bp_error'), style: context.text.bodyMedium?.copyWith(color: context.scheme.error)),
            ),
          ],
          const SizedBox(height: KiraSpace.lg),
          FilledButton(key: const Key('bp_save'), onPressed: _busy ? null : _save, child: const Text('Simpan bacaan')),
        ]),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.state, required this.home, required this.busy, required this.onAgain});
  final BpProtocolState state;
  final (int, int) home;
  final bool busy;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final high = state.resultRange == 'hypertension_range';
    final kira = context.kira;
    final bg = high ? kira.attentionContainer : kira.improveContainer;
    final fg = high ? kira.onAttentionContainer : kira.onImproveContainer;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        key: const Key('bp_result'),
        padding: const EdgeInsets.all(KiraSpace.xl),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(KiraRadius.card)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rata-rata tensi di rumah', style: context.text.labelLarge?.copyWith(color: fg)),
          const SizedBox(height: KiraSpace.xs),
          Text('${_n(state.resultSys ?? 0)}/${_n(state.resultDia ?? 0)} mmHg', style: context.text.displaySmall?.copyWith(color: fg)),
          const SizedBox(height: KiraSpace.xs),
          Text('dari ${state.resultReadings ?? 0} bacaan', style: context.text.bodyMedium?.copyWith(color: fg)),
          const SizedBox(height: KiraSpace.md),
          Text(
            high
                ? 'Berada di atas ambang tensi rumah (${home.$1}/${home.$2} mmHg). Bawa angka ini ke dokter atau Puskesmas untuk dinilai.'
                : 'Berada di bawah ambang tensi rumah (${home.$1}/${home.$2} mmHg).',
            key: const Key('bp_result_text'),
            style: context.text.bodyLarge?.copyWith(color: fg),
          ),
        ]),
      ),
      const SizedBox(height: KiraSpace.md),
      Text(
        'Ini penanda, bukan diagnosis. Ambang tensi rumah menurut ESH 2021; ambang di klinik berbeda (140/90). '
        'Hasil sudah masuk ke proyeksi dan ringkasan untuk dokter.',
        style: context.text.bodySmall,
      ),
      const SizedBox(height: KiraSpace.lg),
      Wrap(spacing: KiraSpace.sm, children: [
        FilledButton.tonal(key: const Key('bp_trends'), onPressed: () => context.push('/trends'), child: const Text('Lihat tren')),
        OutlinedButton(key: const Key('bp_again'), onPressed: busy ? null : onAgain, child: const Text('Mulai putaran baru')),
      ]),
    ]);
  }
}
