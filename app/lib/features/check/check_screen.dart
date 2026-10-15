import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/diagnosis_dialog.dart';
import '../../shared/labels.dart';
import '../../shared/models.dart';
import '../../shared/widgets.dart';
import '../chat/media.dart';
import '../projection/projection_providers.dart';
import 'check_providers.dart';

/// Validasi isian hasil cek. Mengembalikan pesan kesalahan, atau null bila valid.
String? validateGlucose(String raw) {
  final v = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (v == null) return 'Isi angka gula darah dalam mg/dL.';
  if (v < 20 || v > 800) return 'Angkanya tampak tidak mungkin (harus antara 20 dan 800 mg/dL). Cek lagi hasilnya ya.';
  return null;
}

String? validatePressure(String sysRaw, String diaRaw) {
  final sys = int.tryParse(sysRaw.trim()), dia = int.tryParse(diaRaw.trim());
  if (sys == null || dia == null) return 'Isi kedua angka tensi, misalnya 120 dan 80.';
  if (sys < 50 || sys > 300 || dia < 30 || dia > 200) return 'Angka tensi tampak tidak mungkin. Cek lagi hasilnya ya.';
  if (dia >= sys) return 'Angka bawah (diastolik) harus lebih kecil dari angka atas (sistolik).';
  return null;
}

class CheckScreen extends ConsumerWidget {
  const CheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(checkProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Saatnya cek'), actions: const [ProfileAction()]),
      body: check.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => LoadError(
          message: e is ApiException ? e.message : 'Ada kendala saat memuat. Coba lagi sebentar lagi ya.',
          onRetry: () => ref.invalidate(checkProvider),
        ),
        data: (rec) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(faskesProvider);
            ref.invalidate(checkProvider);
            await ref.read(checkProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(KiraSpace.lg),
            children: [
              rec == null ? const _EmptyState() : _RecommendationCard(rec: rec),
              const SizedBox(height: KiraSpace.xl),
              const _FaskesSection(),
              const SizedBox(height: KiraSpace.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('trends_button'),
                  icon: const Icon(Icons.show_chart),
                  label: const Text('Lihat tren hasil cek dan penanda'),
                  onPressed: () => context.push('/trends'),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('diagnosis_button'),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Sudah didiagnosis dokter?'),
                  onPressed: () => showDiagnosisDialog(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showResultSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ResultSheet(),
    );

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('check_empty'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_outline, size: 36, color: context.kira.improve),
            const SizedBox(height: KiraSpace.md),
            Text('Belum ada yang perlu dicek', style: context.text.titleLarge),
            const SizedBox(height: KiraSpace.xs),
            Text(
              'KIRA terus memantau dari check-in harianmu dan akan memberi tahu kalau saatnya periksa.',
              style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant),
            ),
            const SizedBox(height: KiraSpace.lg),
            OutlinedButton.icon(
              key: const Key('enter_result_button'),
              icon: const Icon(Icons.edit_note),
              label: const Text('Punya hasil pemeriksaan? Masukkan'),
              onPressed: () => showResultSheet(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.rec});
  final CheckRecommendation rec;

  @override
  Widget build(BuildContext context) {
    final kira = context.kira;
    final prep = rec.testKind == 'fasting_glucose'
        ? 'Puasa sekitar 8 jam sebelum cek (air putih boleh).'
        : 'Duduk tenang 5 menit sebelum tensi diukur.';
    return Container(
      padding: const EdgeInsets.all(KiraSpace.xl),
      decoration: BoxDecoration(color: kira.attentionContainer, borderRadius: BorderRadius.circular(KiraRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.fact_check_outlined, color: kira.onAttentionContainer),
            const SizedBox(width: KiraSpace.sm),
            Text('Saatnya cek', style: context.text.labelLarge?.copyWith(color: kira.onAttentionContainer)),
          ]),
          const SizedBox(height: KiraSpace.sm),
          Text(rec.label, style: context.text.headlineSmall?.copyWith(color: kira.onAttentionContainer)),
          const SizedBox(height: KiraSpace.sm),
          Text(rec.reason, style: context.text.bodyLarge?.copyWith(color: kira.onAttentionContainer)),
          const SizedBox(height: KiraSpace.sm),
          Text(prep, style: context.text.bodyMedium?.copyWith(color: kira.onAttentionContainer)),
          const SizedBox(height: KiraSpace.lg),
          FilledButton.icon(
            key: const Key('enter_result_button'),
            icon: const Icon(Icons.edit_note),
            label: const Text('Masukkan hasil'),
            onPressed: () => showResultSheet(context),
          ),
        ],
      ),
    );
  }
}

class _FaskesSection extends ConsumerWidget {
  const _FaskesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faskes = ref.watch(faskesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tempat cek terdekat', style: context.text.titleMedium),
        const SizedBox(height: KiraSpace.md),
        faskes.when(
          loading: () => const Padding(padding: EdgeInsets.all(KiraSpace.lg), child: Center(child: CircularProgressIndicator.adaptive())),
          error: (e, _) => SoftNote(
            icon: Icons.location_off_outlined,
            text: 'Daftar tempat cek belum bisa dimuat. Puskesmas atau Posyandu terdekat juga bisa mengukur tensi dan gula darah.',
          ),
          data: (data) => Column(children: [
            if (data.approximate)
              const Padding(
                padding: EdgeInsets.only(bottom: KiraSpace.md),
                child: SoftNote(
                  key: Key('location_note'),
                  icon: Icons.location_searching,
                  text: 'Lokasimu belum aktif, jadi daftar ini memakai area contoh. Aktifkan lokasi untuk yang paling dekat denganmu.',
                ),
              ),
            for (final f in data.faskes)
              Padding(
                padding: const EdgeInsets.only(bottom: KiraSpace.sm),
                child: _FaskesTile(f),
              ),
          ]),
        ),
      ],
    );
  }
}

class _FaskesTile extends StatelessWidget {
  const _FaskesTile(this.f);
  final Faskes f;

  @override
  Widget build(BuildContext context) {
    final km = f.distanceKm.toStringAsFixed(1).replaceAll('.', ',');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: KiraSpace.lg, vertical: KiraSpace.xs),
        leading: CircleAvatar(
          backgroundColor: context.scheme.primaryContainer,
          child: Icon(f.kind == 'puskesmas' ? Icons.local_hospital_outlined : Icons.volunteer_activism_outlined,
              color: context.scheme.onPrimaryContainer),
        ),
        title: Text(f.name, style: context.text.titleSmall),
        subtitle: Text('${f.kind == 'puskesmas' ? 'Puskesmas' : 'Posyandu'}, $km km${f.address == null ? '' : '\n${f.address}'}'),
        isThreeLine: f.address != null,
      ),
    );
  }
}

class _ResultSheet extends ConsumerStatefulWidget {
  const _ResultSheet();

  @override
  ConsumerState<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends ConsumerState<_ResultSheet> {
  final _glucose = TextEditingController();
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  bool _bp = false;
  bool _fasting = true; // gula puasa vs sewaktu/setelah makan (ambang risikonya berbeda)
  bool _busy = false;
  String? _error;
  ResultOutcome? _outcome;
  Projection? _before;
  String? _photoReply;
  bool _photoFlag = false;

  @override
  void dispose() {
    _glucose.dispose();
    _sys.dispose();
    _dia.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = _bp ? validatePressure(_sys.text, _dia.text) : validateGlucose(_glucose.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _before = await ref.read(projectionProvider.future);
    } catch (_) {
      _before = null; // tanpa pembanding, hasil tetap disimpan
    }
    try {
      final outcome = _bp
          ? await ref.read(apiProvider).postResult(
              'blood_pressure', {'sys': int.parse(_sys.text.trim()), 'dia': int.parse(_dia.text.trim())})
          : await ref.read(apiProvider).postResult(
              _fasting ? 'fasting_glucose' : 'random_glucose',
              {'mg_dl': double.parse(_glucose.text.trim().replaceAll(',', '.'))});
      ref
        ..invalidate(projectionProvider)
        ..invalidate(checkProvider);
      if (mounted) setState(() => _outcome = outcome);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fromPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Ambil dengan kamera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Pilih dari galeri'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final media = await ref.read(photoPickerProvider).pick(source);
    if (media == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reply = await ref.read(apiProvider).sendPhoto('result', media.bytes, media.name);
      ref
        ..invalidate(projectionProvider)
        ..invalidate(checkProvider);
      if (mounted) {
        setState(() {
          _photoReply = reply.reply;
          _photoFlag = reply.redFlag != null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
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
        child: _outcome != null ? _OutcomeView(outcome: _outcome!, before: _before) : _form(context),
      ),
    );
  }

  Widget _form(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Masukkan hasil pemeriksaan', style: context.text.titleLarge),
        const SizedBox(height: KiraSpace.xs),
        Text('Hasil nyata menggantikan perkiraan, jadi rentang risikomu akan menyempit.', style: context.text.bodyMedium),
        const SizedBox(height: KiraSpace.lg),
        Wrap(spacing: KiraSpace.sm, children: [
          ChoiceChip(
            key: const Key('result_kind_glucose'),
            label: const Text('Gula darah'),
            selected: !_bp,
            onSelected: (_) => setState(() {
              _bp = false;
              _error = null;
            }),
          ),
          ChoiceChip(
            key: const Key('result_kind_bp'),
            label: const Text('Tekanan darah'),
            selected: _bp,
            onSelected: (_) => setState(() {
              _bp = true;
              _error = null;
            }),
          ),
        ]),
        const SizedBox(height: KiraSpace.lg),
        if (!_bp) ...[
          Wrap(spacing: KiraSpace.sm, children: [
            ChoiceChip(
              key: const Key('glucose_fasting_chip'),
              label: const Text('Puasa'),
              selected: _fasting,
              onSelected: (_) => setState(() => _fasting = true),
            ),
            ChoiceChip(
              key: const Key('glucose_random_chip'),
              label: const Text('Setelah makan / sewaktu'),
              selected: !_fasting,
              onSelected: (_) => setState(() => _fasting = false),
            ),
          ]),
          const SizedBox(height: KiraSpace.md),
          TextField(
            key: const Key('glucose_input'),
            controller: _glucose,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: _fasting ? 'Gula darah puasa' : 'Gula darah sewaktu', suffixText: 'mg/dL'),
          ),
        ] else
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('sys_input'),
                controller: _sys,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Atas (sistolik)', suffixText: 'mmHg'),
              ),
            ),
            const SizedBox(width: KiraSpace.md),
            Expanded(
              child: TextField(
                key: const Key('dia_input'),
                controller: _dia,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Bawah (diastolik)', suffixText: 'mmHg'),
              ),
            ),
          ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: KiraSpace.md),
            child: Semantics(
              liveRegion: true,
              child: Text(_error!, key: const Key('result_error'), style: context.text.bodyMedium?.copyWith(color: context.scheme.error)),
            ),
          ),
        if (_photoReply != null)
          Padding(
            padding: const EdgeInsets.only(top: KiraSpace.md),
            child: _photoFlag ? EmergencyCard(message: _photoReply!) : SoftNote(icon: Icons.photo_outlined, text: _photoReply!),
          ),
        const SizedBox(height: KiraSpace.lg),
        Row(children: [
          OutlinedButton.icon(
            key: const Key('result_photo'),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Baca dari foto'),
            onPressed: _busy ? null : _fromPhoto,
          ),
          const Spacer(),
          FilledButton(
            key: const Key('result_save'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Simpan hasil'),
          ),
        ]),
      ],
    );
  }
}

class _OutcomeView extends StatelessWidget {
  const _OutcomeView({required this.outcome, required this.before});
  final ResultOutcome outcome;
  final Projection? before;

  @override
  Widget build(BuildContext context) {
    if (outcome.redFlagMessage != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        EmergencyCard(message: outcome.redFlagMessage!),
        const SizedBox(height: KiraSpace.lg),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))),
      ]);
    }
    final after = outcome.projection;
    final kira = context.kira;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const Key('outcome_saved'),
          width: double.infinity,
          padding: const EdgeInsets.all(KiraSpace.lg),
          decoration: BoxDecoration(color: kira.improveContainer, borderRadius: BorderRadius.circular(KiraRadius.card)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.check_circle_outline, color: kira.onImproveContainer),
              const SizedBox(width: KiraSpace.sm),
              Text('Tersimpan', style: context.text.titleMedium?.copyWith(color: kira.onImproveContainer)),
            ]),
            const SizedBox(height: KiraSpace.sm),
            Text('Proyeksimu sudah dikalibrasi ulang dengan hasil nyata.',
                style: context.text.bodyLarge?.copyWith(color: kira.onImproveContainer)),
            if (after != null && before != null)
              Padding(
                padding: const EdgeInsets.only(top: KiraSpace.xs),
                child: Text(
                  'Rentang 10 tahun: sebelumnya ${percentRange(before!.p10Low, before!.p10High)}, '
                  'sekarang ${percentRange(after.p10Low, after.p10High)}.',
                  style: context.text.bodyLarge?.copyWith(color: kira.onImproveContainer),
                ),
              ),
            if (outcome.bpCategory != null)
              Padding(
                padding: const EdgeInsets.only(top: KiraSpace.xs),
                child: Text('Tekanan darahmu tergolong ${bpLabel(outcome.bpCategory)}.',
                    style: context.text.bodyLarge?.copyWith(color: kira.onImproveContainer)),
              ),
          ]),
        ),
        const SizedBox(height: KiraSpace.lg),
        Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Selesai'))),
      ],
    );
  }
}
