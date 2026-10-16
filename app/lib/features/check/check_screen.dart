import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/link_opener.dart';
import '../../core/outbox.dart';
import '../../core/providers.dart';
import '../../core/refresh.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/diagnosis_dialog.dart';
import '../../shared/labels.dart';
import '../../shared/models.dart';
import '../../shared/widgets.dart';
import '../chat/media.dart';
import '../projection/projection_providers.dart';
import 'check_providers.dart';
import 'location.dart';

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

/// Detak jantung istirahat (kali/menit). Batas 25-250 hanya penyaring salah ketik, bukan batas klinis.
String? validateHeartRate(String raw) {
  final v = int.tryParse(raw.trim());
  if (v == null) return 'Isi angka detak jantung dalam kali per menit, misalnya 72.';
  if (v < 25 || v > 250) return 'Angkanya tampak tidak mungkin (antara 25 dan 250 kali/menit). Hitung lagi ya.';
  return null;
}

/// Nadi yang menyertai tensi: boleh kosong.
String? validatePulse(String raw) => raw.trim().isEmpty ? null : validateHeartRate(raw);

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
            refreshHealthData(ref.invalidate);
            await ref.read(checkProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: context.pagePadding,
            children: [
              rec == null ? const _EmptyState() : _RecommendationCard(rec: rec),
              const _FaskesSection(),
              const SectionHeader('Catat dan pantau'),
              LinkGroup(children: [
                ListTile(
                  key: const Key('heart_rate_button'),
                  leading: const Icon(Icons.favorite_border),
                  title: const Text('Catat detak jantung'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showResultSheet(context, initial: 'hr'),
                ),
                ListTile(
                  key: const Key('bp_protocol_button'),
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: const Text('Ukur tensi di rumah 7 hari'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/bp-protocol'),
                ),
                ListTile(
                  key: const Key('trends_button'),
                  leading: const Icon(Icons.show_chart),
                  title: const Text('Lihat tren hasil cek dan penanda'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/trends'),
                ),
                ListTile(
                  key: const Key('diagnosis_button'),
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('Sudah didiagnosis dokter?'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDiagnosisDialog(context),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// [initial]: 'glucose' | 'bp' | 'hr' (jenis hasil yang sudah terpilih saat sheet dibuka).
Future<void> showResultSheet(BuildContext context, {String initial = 'glucose'}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ResultSheet(initial: initial),
    );

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('check_empty'),
      child: EmptyState(
        title: 'Belum ada yang perlu dicek',
        message: 'KIRA memantau dari check-in harianmu dan memberi tahu kalau saatnya periksa.',
        action: OutlinedButton.icon(
          key: const Key('enter_result_button'),
          icon: const Icon(Icons.edit_note),
          label: const Text('Masukkan hasil pemeriksaan'),
          onPressed: () => showResultSheet(context),
        ),
      ),
    );
  }
}

class _RecommendationCard extends ConsumerWidget {
  const _RecommendationCard({required this.rec});
  final CheckRecommendation rec;

  /// Jawaban atas "sudah dicek?". Nadanya bertanya, bukan menagih: menunda dan "tidak perlu" selalu tersedia.
  Future<void> _respond(BuildContext context, WidgetRef ref, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final out = await ref.read(apiProvider).respondCheck(rec.id, action);
      ref.invalidate(checkProvider);
      if (action == 'snooze') {
        messenger.showSnackBar(const SnackBar(content: Text('Oke, KIRA tanya lagi dalam 3 hari.')));
      } else if (action == 'dismiss') {
        messenger.showSnackBar(const SnackBar(content: Text('Baik, KIRA tidak menyarankan ini lagi dalam waktu dekat.')));
      } else if (out.resultNeeded && context.mounted) {
        await showResultSheet(context); // sudah dicek: langsung masukkan angkanya supaya proyeksi terbarui
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          if (rec.followUp) ...[
            const SizedBox(height: KiraSpace.lg),
            Divider(color: kira.onAttentionContainer.withValues(alpha: 0.25)),
            const SizedBox(height: KiraSpace.sm),
            Semantics(
              container: true,
              label: 'Tindak lanjut',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'Sudah sempat cek? Saran ini muncul ${rec.ageDays} hari lalu.',
                  key: const Key('followup_question'),
                  style: context.text.titleSmall?.copyWith(color: kira.onAttentionContainer),
                ),
                const SizedBox(height: KiraSpace.sm),
                Wrap(spacing: KiraSpace.sm, runSpacing: KiraSpace.xs, children: [
                  OutlinedButton(
                    key: const Key('followup_done'),
                    onPressed: () => _respond(context, ref, 'done'),
                    child: const Text('Sudah'),
                  ),
                  OutlinedButton(
                    key: const Key('followup_snooze'),
                    onPressed: () => _respond(context, ref, 'snooze'),
                    child: const Text('Nanti'),
                  ),
                  TextButton(
                    key: const Key('followup_dismiss'),
                    onPressed: () => _respond(context, ref, 'dismiss'),
                    child: const Text('Tidak perlu'),
                  ),
                ]),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _FaskesSection extends ConsumerStatefulWidget {
  const _FaskesSection();

  @override
  ConsumerState<_FaskesSection> createState() => _FaskesSectionState();
}

class _FaskesSectionState extends ConsumerState<_FaskesSection> {
  // Kembali dari pengaturan lokasi/aplikasi: baca ulang lokasi supaya daftar langsung muncul.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(onResume: () {
    if (ref.read(faskesProvider).value?.location != LocationStatus.found) ref.invalidate(faskesProvider);
  });

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _search(Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(linkOpenerProvider).open(uri);
    if (!ok) messenger.showSnackBar(const SnackBar(content: Text('Aplikasi peta belum bisa dibuka di perangkat ini.')));
  }

  Future<void> _fixLocation(LocationStatus status) async {
    final location = ref.read(locationProvider);
    switch (status) {
      case LocationStatus.serviceOff || LocationStatus.unavailable:
        await location.openLocationSettings();
      case LocationStatus.blocked:
        await location.openAppSettings();
      case LocationStatus.needsPermission:
        await location.requestAndLocate();
        ref.invalidate(faskesProvider);
      case LocationStatus.found:
        ref.invalidate(faskesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final faskes = ref.watch(faskesProvider);
    final mapsButton = OutlinedButton.icon(
      key: const Key('faskes_search_maps'),
      icon: const Icon(Icons.map_outlined),
      label: const Text('Cari puskesmas di Google Maps'),
      onPressed: () => _search(faskes.value?.lat == null
          ? faskesSearchNearbyUri()
          : faskesSearchUri(faskes.value!.lat!, faskes.value!.lng!)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Tempat cek terdekat'),
        faskes.when(
          loading: () => const Padding(padding: EdgeInsets.all(KiraSpace.lg), child: Center(child: CircularProgressIndicator.adaptive())),
          error: (e, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SoftNote(
              icon: Icons.cloud_off_outlined,
              text: 'Daftar tempat cek belum bisa dimuat. Puskesmas atau Posyandu terdekat juga bisa mengukur tensi dan gula darah.',
            ),
            const SizedBox(height: KiraSpace.sm),
            mapsButton,
          ]),
          data: (data) {
            if (data.location != LocationStatus.found) {
              return _LocationPrompt(
                status: data.location,
                onFix: () => _fixLocation(data.location),
                onMaps: () => _search(faskesSearchNearbyUri()),
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (data.mapDataMissing)
                const Padding(
                  padding: EdgeInsets.only(bottom: KiraSpace.md),
                  child: SoftNote(
                    key: Key('faskes_unavailable'),
                    icon: Icons.cloud_off_outlined,
                    text: 'Data peta di sekitarmu belum bisa dimuat. Cari langsung di Google Maps, '
                        'atau datangi Puskesmas terdekat.',
                  ),
                ),
              for (final f in data.faskes)
                Padding(
                  padding: const EdgeInsets.only(bottom: KiraSpace.sm),
                  child: _FaskesTile(f),
                ),
              if (data.faskes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: KiraSpace.sm),
                  child: Text(
                    'Data dari ${data.faskes.first.source == 'google' ? 'Google Maps' : 'OpenStreetMap'}. Jam buka dan layanan '
                    'bisa berubah, jadi konfirmasi dulu sebelum berangkat.',
                    key: const Key('faskes_source'),
                    style: context.text.bodySmall,
                  ),
                ),
              mapsButton,
            ]);
          },
        ),
      ],
    );
  }
}

/// Ajakan mengaktifkan lokasi, dengan satu tombol yang sesuai penyebabnya. Tanpa lokasi tidak ada daftar contoh.
class _LocationPrompt extends StatelessWidget {
  const _LocationPrompt({required this.status, required this.onFix, required this.onMaps});
  final LocationStatus status;
  final VoidCallback onFix;
  final VoidCallback onMaps;

  @override
  Widget build(BuildContext context) {
    const title = 'Aktifkan lokasi';
    const action = 'Aktifkan lokasi';
    final message = switch (status) {
      LocationStatus.serviceOff => 'Lokasi di ponselmu sedang mati. Nyalakan supaya KIRA bisa menunjukkan tempat cek terdekat.',
      LocationStatus.blocked => 'Izin lokasi untuk KIRA ditolak. Izinkan di pengaturan aplikasi, lalu kembali ke sini.',
      LocationStatus.unavailable => 'Lokasimu belum terbaca. Pastikan lokasi dan GPS di ponselmu menyala.',
      _ => 'Supaya KIRA bisa menunjukkan puskesmas dan klinik terdekat. Lokasi hanya dipakai untuk pencarian ini.',
    };
    return Card(
      key: const Key('location_prompt'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: context.scheme.primaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.location_on_outlined, size: 20, color: context.scheme.onPrimaryContainer),
          ),
          const SizedBox(width: KiraSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: KiraSpace.xs),
              Text(title, style: context.text.titleSmall),
              const SizedBox(height: 2),
              Text(message, style: context.text.bodySmall?.copyWith(color: context.scheme.onSurfaceVariant)),
              const SizedBox(height: KiraSpace.md),
              Wrap(spacing: KiraSpace.xs, runSpacing: KiraSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                FilledButton.tonal(
                  key: const Key('location_fix'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: KiraSpace.lg)),
                  onPressed: onFix,
                  child: Text(action),
                ),
                TextButton(
                  key: const Key('faskes_search_maps'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: onMaps,
                  child: const Text('Cari di Google Maps'),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Pencarian "puskesmas" di Google Maps di sekitar titik pengguna (tanpa kunci apa pun).
Uri faskesSearchUri(double lat, double lng, {String query = 'puskesmas'}) =>
    Uri.parse('https://www.google.com/maps/search/${Uri.encodeComponent(query)}/@$lat,$lng,15z');

/// Tanpa koordinat: Google Maps sendiri memakai lokasi perangkat untuk "terdekat".
Uri faskesSearchNearbyUri() => Uri.parse('https://www.google.com/maps/search/${Uri.encodeComponent('puskesmas terdekat')}');

String faskesKindLabel(String kind) => switch (kind) {
      'puskesmas' => 'Puskesmas',
      'posyandu' => 'Posyandu',
      'rumah_sakit' => 'Rumah sakit',
      _ => 'Klinik',
    };

class _FaskesTile extends ConsumerWidget {
  const _FaskesTile(this.f);
  final Faskes f;

  Future<void> _openMap(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    // Rute di Google Maps dari lokasi pengguna; bila tautan rute tidak ada, titiknya saja.
    final route = f.routeUrl;
    final uri = route != null ? Uri.parse(route) : mapsUri(f.lat!, f.lng!, label: f.name);
    final ok = await ref.read(linkOpenerProvider).open(uri);
    if (!ok) messenger.showSnackBar(const SnackBar(content: Text('Aplikasi peta belum bisa dibuka di perangkat ini.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final km = f.distanceKm.toStringAsFixed(1).replaceAll('.', ',');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: KiraSpace.lg, vertical: KiraSpace.xs),
        leading: CircleAvatar(
          backgroundColor: context.scheme.primaryContainer,
          child: Icon(
              switch (f.kind) {
                'puskesmas' => Icons.local_hospital_outlined,
                'rumah_sakit' => Icons.emergency_outlined,
                'klinik' => Icons.medical_services_outlined,
                _ => Icons.volunteer_activism_outlined,
              },
              color: context.scheme.onPrimaryContainer),
        ),
        title: Text(f.name, style: context.text.titleSmall),
        subtitle: Text([
          '${faskesKindLabel(f.kind)}, $km km',
          if (f.address != null) f.address!,
          if (f.openingHours != null) 'Buka: ${f.openingHours}',
          if (f.phone != null) f.phone!,
        ].join('\n')),
        isThreeLine: f.address != null || f.phone != null || f.openingHours != null,
        trailing: f.lat == null || f.lng == null
            ? null
            : IconButton(
                key: Key('map_${f.name}'),
                tooltip: 'Rute ke ${f.name} di Google Maps',
                icon: const Icon(Icons.directions_outlined),
                onPressed: () => _openMap(context, ref),
              ),
      ),
    );
  }
}

class _ResultSheet extends ConsumerStatefulWidget {
  const _ResultSheet({this.initial = 'glucose'});
  final String initial;

  @override
  ConsumerState<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends ConsumerState<_ResultSheet> {
  final _glucose = TextEditingController();
  final _sys = TextEditingController();
  final _dia = TextEditingController();
  final _pulse = TextEditingController();
  final _hr = TextEditingController();
  late bool _bp = widget.initial == 'bp';
  late bool _heart = widget.initial == 'hr';
  bool _fasting = true; // gula puasa vs sewaktu/setelah makan (ambang risikonya berbeda)
  bool _busy = false;
  String? _error;
  ResultOutcome? _outcome;
  Projection? _before;
  String? _photoReply;
  bool _photoFlag = false;
  bool _queued = false; // tersimpan di ponsel karena tidak ada sinyal

  @override
  void dispose() {
    _glucose.dispose();
    _sys.dispose();
    _dia.dispose();
    _pulse.dispose();
    _hr.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = _heart
        ? validateHeartRate(_hr.text)
        : _bp
            ? validatePressure(_sys.text, _dia.text) ?? validatePulse(_pulse.text)
            : validateGlucose(_glucose.text);
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
    final kind = _heart ? 'resting_heart_rate' : (_bp ? 'blood_pressure' : (_fasting ? 'fasting_glucose' : 'random_glucose'));
    final Map<String, num> value = _heart
        ? {'bpm': int.parse(_hr.text.trim())}
        : _bp
            ? {
                'sys': int.parse(_sys.text.trim()),
                'dia': int.parse(_dia.text.trim()),
                if (_pulse.text.trim().isNotEmpty) 'pulse': int.parse(_pulse.text.trim()),
              }
            : {'mg_dl': double.parse(_glucose.text.trim().replaceAll(',', '.'))};
    final key = newOutboxId();
    try {
      final outcome = await ref.read(apiProvider).postResult(kind, value, idempotencyKey: key);
      refreshHealthData(ref.invalidate); // proyeksi, saran cek, tren dan penanda ikut dihitung ulang
      if (mounted) setState(() => _outcome = outcome);
    } on ApiException catch (e) {
      if (e.isNetwork) {
        // Tanpa sinyal: simpan di ponsel dengan kunci yang sama, kirim otomatis nanti tanpa tercatat dua kali.
        ref.read(outboxProvider.notifier).enqueueResult(kind, value, id: key);
        if (mounted) setState(() => _queued = true);
      } else if (mounted) {
        setState(() => _error = e.message);
      }
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
      refreshHealthData(ref.invalidate);
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
        child: _queued
            ? _QueuedView(onClose: () => Navigator.pop(context))
            : (_outcome != null ? _OutcomeView(outcome: _outcome!, before: _before) : _form(context)),
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
            selected: !_bp && !_heart,
            onSelected: (_) => setState(() {
              _bp = false;
              _heart = false;
              _error = null;
            }),
          ),
          ChoiceChip(
            key: const Key('result_kind_bp'),
            label: const Text('Tekanan darah'),
            selected: _bp,
            onSelected: (_) => setState(() {
              _bp = true;
              _heart = false;
              _error = null;
            }),
          ),
          ChoiceChip(
            key: const Key('result_kind_hr'),
            label: const Text('Detak jantung'),
            selected: _heart,
            onSelected: (_) => setState(() {
              _heart = true;
              _bp = false;
              _error = null;
            }),
          ),
        ]),
        const SizedBox(height: KiraSpace.lg),
        if (_heart) ...[
          TextField(
            key: const Key('hr_input'),
            controller: _hr,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: const InputDecoration(
              labelText: 'Detak jantung istirahat',
              suffixText: 'kali/menit',
              helperText: 'Duduk tenang 5 menit, lalu hitung nadi di pergelangan selama 1 menit (atau baca dari tensimeter/jam tangan).',
              helperMaxLines: 3,
            ),
          ),
        ] else if (!_bp) ...[
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
        if (_bp) ...[
          const SizedBox(height: KiraSpace.md),
          TextField(
            key: const Key('pulse_input'),
            controller: _pulse,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: const InputDecoration(labelText: 'Nadi (boleh dikosongkan)', suffixText: 'kali/menit'),
          ),
        ],
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

/// Kalimat untuk hasil detak jantung istirahat. Mengacu pada rentang normal dewasa 60-100 kali/menit (AHA); bukan diagnosis.
String heartRateSentence(String range) => switch (range) {
      'below_range' =>
        'Detak jantung istirahatmu di bawah 60. Ini sering wajar pada orang yang rutin berolahraga; bila kamu bukan atlet, '
            'atau merasa pusing, bicarakan dengan tenaga kesehatan.',
      'above_range' =>
        'Detak jantung istirahatmu di atas 100. Ukur ulang setelah duduk tenang 5 menit; kafein, kurang tidur, dan stres bisa '
            'menaikkannya. Bila tetap tinggi, bicarakan dengan tenaga kesehatan.',
      _ => 'Detak jantung istirahatmu ada di rentang 60-100 kali/menit, rentang yang umum untuk dewasa saat istirahat.',
    };

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
            Text(
                outcome.hrRange != null
                    ? 'Muncul di Tren dan penanda serta ringkasan untuk dokter. Detak jantung tidak mengubah proyeksi diabetes.'
                    : 'Proyeksimu sudah dikalibrasi ulang dengan hasil nyata.',
                key: const Key('outcome_note'),
                style: context.text.bodyLarge?.copyWith(color: kira.onImproveContainer)),
            if (after != null && before != null && outcome.hrRange == null)
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
            if (outcome.hrRange != null)
              Padding(
                padding: const EdgeInsets.only(top: KiraSpace.xs),
                child: Text(heartRateSentence(outcome.hrRange!),
                    key: const Key('hr_outcome'), style: context.text.bodyLarge?.copyWith(color: kira.onImproveContainer)),
              ),
          ]),
        ),
        const SizedBox(height: KiraSpace.lg),
        Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Selesai'))),
      ],
    );
  }
}

/// Hasil cek tersimpan di ponsel karena tidak ada sinyal.
class _QueuedView extends StatelessWidget {
  const _QueuedView({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('result_queued'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.schedule, size: 36, color: context.scheme.primary),
        const SizedBox(height: KiraSpace.md),
        Text('Tersimpan di ponselmu', style: context.text.titleLarge),
        const SizedBox(height: KiraSpace.xs),
        Text(
          'Belum ada sinyal, jadi hasilnya dikirim otomatis begitu tersambung. Proyeksimu diperbarui setelah itu.',
          style: context.text.bodyLarge,
        ),
        const SizedBox(height: KiraSpace.md),
        const SoftNote(icon: Icons.emergency_outlined, text: offlineEmergencyHint),
        const SizedBox(height: KiraSpace.lg),
        FilledButton(key: const Key('result_queued_close'), onPressed: onClose, child: const Text('Mengerti')),
      ],
    );
  }
}
