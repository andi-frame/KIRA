import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/labels.dart';
import '../../shared/models.dart';
import '../../shared/widgets.dart';
import '../goals/goals_screen.dart';
import 'projection_providers.dart';
import 'scenarios_card.dart';
import 'risk_chart.dart';
import 'weekly_recap_card.dart';

/// Proyeksi 10 tahun. Beranda memakai layar ini dengan kartu harian di atas (`leading`) dan tautan di bawah
/// (`trailing`), supaya kurva, hipertensi, what-if, target, skenario, dan rekap mingguan tetap ada di satu tempat.
class ProjectionScreen extends ConsumerWidget {
  const ProjectionScreen({
    super.key,
    this.title = 'Kira-kira 10 tahun',
    this.leading = const [],
    this.trailing = const [],
    this.onRefresh,
  });

  final String title;
  final List<Widget> leading;
  final List<Widget> trailing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projection = ref.watch(projectionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [ProfileAction()]),
      body: projection.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => LoadError(
          message: e is ApiException ? e.message : 'Ada kendala saat memuat proyeksi. Coba lagi sebentar lagi ya.',
          onRetry: () => ref.invalidate(projectionProvider),
        ),
        data: (p) => RefreshIndicator(
          onRefresh: () {
            onRefresh?.call();
            return ref.refresh(projectionProvider.future);
          },
          child: _Content(projection: p, leading: leading, trailing: trailing),
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.projection, this.leading = const [], this.trailing = const []});
  final Projection projection;
  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final whatIf = ref.watch(whatIfProvider);
    final result = whatIf.result;
    final p = projection;
    final sameCategory = p.categoryLow == p.categoryHigh;
    final headline =
        sameCategory ? 'Risiko ${categoryLabel(p.categoryLow)}' : 'Antara ${categoryLabel(p.categoryLow)} dan ${categoryLabel(p.categoryHigh)}';
    final wide = p.spread >= 8;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: context.pagePadding,
      children: [
        ...leading,
        if (p.needsProfile)
          Padding(
            padding: const EdgeInsets.only(bottom: KiraSpace.lg),
            child: SoftNote(
              key: const Key('needs_profile_note'),
              icon: Icons.person_outline,
              title: 'Profilmu belum lengkap',
              text: 'Makin lengkap datamu, makin sempit rentangnya. Rentang di bawah memakai semua kemungkinan.',
            ),
          ),
        if (p.mode == 'management')
          const Padding(
            padding: EdgeInsets.only(bottom: KiraSpace.lg),
            child: SoftNote(
              icon: Icons.favorite_outline,
              title: 'Mode pengelolaan',
              text: 'Proyeksi ini membantu melihat arah. Untuk target harian, ikuti arahan dokter atau ahli gizimu.',
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(KiraSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kalau kebiasaanmu tetap seperti sekarang',
                    style: context.text.labelLarge?.copyWith(color: context.scheme.primary)),
                const SizedBox(height: KiraSpace.sm),
                Text(headline, key: const Key('risk_headline'), style: context.text.headlineMedium),
                const SizedBox(height: KiraSpace.xs),
                Text(
                  'Perkiraan peluang diabetes dalam 10 tahun: kira-kira ${percentRange(p.p10Low, p.p10High)}.',
                  style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant),
                ),
                const SizedBox(height: KiraSpace.xl),
                RiskBandChart(
                  nowLow: p.curveLow,
                  nowHigh: p.curveHigh,
                  afterLow: result?.curveAfterLow,
                  afterHigh: result?.curveAfterHigh,
                ),
                const SizedBox(height: KiraSpace.md),
                Wrap(spacing: KiraSpace.lg, runSpacing: KiraSpace.sm, children: [
                  _LegendKey(color: context.kira.chartNow, dashed: false, label: 'Kebiasaan sekarang'),
                  _LegendKey(color: context.kira.chartBetter, dashed: true, label: 'Kalau kebiasaan diperbaiki'),
                ]),
                if (result == null) ...[
                  const SizedBox(height: KiraSpace.sm),
                  Text('Geser pengaturan di bawah untuk melihat kurva kedua.', style: context.text.bodySmall),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: KiraSpace.lg),
        ProjectionBasisCard(basis: p.basis),
        if (wide) ...[
          const SizedBox(height: KiraSpace.lg),
          _CheckHint(),
        ],
        const SizedBox(height: KiraSpace.lg),
        _HypertensionCard(risk: p.hypertension),
        const SizedBox(height: KiraSpace.lg),
        _ImpactCard(projection: p, whatIf: whatIf),
        if (ref.watch(weeklyRecapProvider).value case final recap?) ...[
          const SizedBox(height: KiraSpace.lg),
          WeeklyRecapCard(recap: recap),
        ],
        const SizedBox(height: KiraSpace.lg),
        const GoalsCard(),
        const SizedBox(height: KiraSpace.lg),
        _Controls(whatIf: whatIf),
        const SizedBox(height: KiraSpace.lg),
        ScenariosCard(whatIf: whatIf),
        const SizedBox(height: KiraSpace.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('how_calculated'),
            icon: const Icon(Icons.info_outline),
            label: const Text('Bagaimana angka ini dihitung?'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (_) => const _HowCalculated(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KiraSpace.md, vertical: KiraSpace.sm),
          child: Text('Ini perkiraan untuk menemani keputusanmu, bukan pengganti dokter.', style: context.text.bodySmall),
        ),
        ...trailing,
      ],
    );
  }
}

class _LegendKey extends StatelessWidget {
  const _LegendKey({required this.color, required this.dashed, required this.label});
  final Color color;
  final bool dashed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 28,
        height: 12,
        child: CustomPaint(painter: _SwatchPainter(color, dashed)),
      ),
      const SizedBox(width: KiraSpace.sm),
      Text(label, style: context.text.labelMedium?.copyWith(color: context.scheme.onSurface)),
    ]);
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.color, this.dashed);
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    for (double x = 0; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, y), Offset((x + 5).clamp(0, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color || old.dashed != dashed;
}

class _HypertensionCard extends StatelessWidget {
  const _HypertensionCard({required this.risk});
  final HypertensionRisk risk;

  static String _label(String? c) => switch (c) {
        'low' => 'rendah',
        'medium' => 'sedang',
        'high' => 'tinggi',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final bp = risk.sys != null ? '${risk.sys}/${risk.dia}' : null;
    final (String headline, String body) = switch (risk.status) {
      'ok' => (
          risk.categoryLow == risk.categoryHigh
              ? 'Risiko ${_label(risk.categoryLow)}'
              : 'Antara ${_label(risk.categoryLow)} dan ${_label(risk.categoryHigh)}',
          'Peluang tekanan darah tinggi dalam 4 tahun: kira-kira ${percentRange(risk.riskLow!, risk.riskHigh!)}. '
              'Tekananmu terakhir $bp.',
        ),
      'already_hypertensive' => (
          'Tekananmu $bp sudah di rentang hipertensi',
          'Temui dokter atau Puskesmas untuk pemeriksaan ulang dan arahan. KIRA tidak memberi saran obat.',
        ),
      'needs_profile' => (
          'Lengkapi profilmu dulu',
          'Usia, jenis kelamin, tinggi, dan berat badan dibutuhkan untuk menghitung risiko tekanan darah.',
        ),
      'has_diabetes' || 'out_of_age_range' => (
          'Perkiraan ini tidak berlaku untukmu',
          'Perhitungannya dikembangkan untuk usia 20-69 tahun tanpa diabetes. Ikuti arahan dokter untuk tekananmu.',
        ),
      _ => (
          'Ukur tekananmu dulu',
          'Risiko tekanan darah tinggi baru bisa dihitung setelah tekananmu diukur. Cek tensi cepat dan gratis di Posyandu atau Puskesmas.',
        ),
    };
    return Card(
      key: const Key('hypertension_card'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tekanan darah', style: context.text.labelLarge?.copyWith(color: context.scheme.primary)),
            const SizedBox(height: KiraSpace.sm),
            Text(headline, style: context.text.titleLarge),
            const SizedBox(height: KiraSpace.xs),
            Text(body, style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant)),
            if (risk.status == 'ok') ...[
              const SizedBox(height: KiraSpace.sm),
              Text(
                'Memakai skor Framingham yang dikembangkan di Amerika Serikat dan belum divalidasi pada populasi Indonesia.',
                style: context.text.bodySmall,
              ),
            ],
            if (risk.status == 'needs_bp')
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => context.go('/check'), child: const Text('Lihat saran cek')),
              ),
          ],
        ),
      ),
    );
  }
}

class _CheckHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final kira = context.kira;
    return Container(
      key: const Key('check_hint'),
      padding: const EdgeInsets.all(KiraSpace.lg),
      decoration: BoxDecoration(color: kira.attentionContainer, borderRadius: BorderRadius.circular(KiraRadius.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.fact_check_outlined, color: kira.onAttentionContainer),
          const SizedBox(width: KiraSpace.md),
          Expanded(
            child: Text(
              'Rentangnya masih lebar. Satu pemeriksaan nyata bisa mempersempitnya.',
              style: context.text.bodyLarge?.copyWith(color: kira.onAttentionContainer),
            ),
          ),
        ]),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.go('/check'),
            style: TextButton.styleFrom(foregroundColor: kira.onAttentionContainer),
            child: const Text('Lihat saran cek'),
          ),
        ),
      ]),
    );
  }
}

class _ImpactCard extends StatelessWidget {
  const _ImpactCard({required this.projection, required this.whatIf});
  final Projection projection;
  final WhatIfState whatIf;

  @override
  Widget build(BuildContext context) {
    final result = whatIf.result;
    final habit = result?.mostImpactful ?? projection.mostImpactful;
    final label = habitLabel(habit);
    if (label.isEmpty) return const SizedBox.shrink();
    final kira = context.kira;
    return Container(
      key: const Key('impact_card'),
      padding: const EdgeInsets.all(KiraSpace.lg),
      decoration: BoxDecoration(color: kira.improveContainer, borderRadius: BorderRadius.circular(KiraRadius.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.trending_down, color: kira.onImproveContainer),
          const SizedBox(width: KiraSpace.sm),
          Expanded(
            child: Text('Kebiasaan paling berdampak', style: context.text.titleSmall?.copyWith(color: kira.onImproveContainer)),
          ),
        ]),
        const SizedBox(height: KiraSpace.sm),
        Text(label, style: context.text.titleLarge?.copyWith(color: kira.onImproveContainer)),
        if (result != null) ...[
          const SizedBox(height: KiraSpace.xs),
          Text(
            'Rentang 10 tahun bergeser dari ${percentRange(projection.p10Low, projection.p10High)} '
            'menjadi ${percentRange(result.curveAfterLow.last, result.curveAfterHigh.last)}.',
            style: context.text.bodyLarge?.copyWith(color: kira.onImproveContainer),
          ),
          if (result.sugarAfter < result.sugarBefore)
            Text(
              'Gula dari minuman: ${result.sugarBefore.round()} g turun jadi ${result.sugarAfter.round()} g per hari.',
              style: context.text.bodyMedium?.copyWith(color: kira.onImproveContainer),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: KiraSpace.xs),
            child: Text('Coba atur di bawah untuk melihat dampaknya pada kurvamu.',
                style: context.text.bodyMedium?.copyWith(color: kira.onImproveContainer)),
          ),
      ]),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.whatIf});
  final WhatIfState whatIf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(whatIfProvider.notifier);
    final change = whatIf.change;
    final sweet = -change.sweetDrinksDeltaPerDay;
    final weight = -(change.weightDeltaKg ?? 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(KiraSpace.xl, KiraSpace.xl, KiraSpace.xl, KiraSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Coba ubah kebiasaanmu', style: context.text.titleMedium)),
            if (whatIf.loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
            if (!change.isEmpty && !whatIf.loading) TextButton(onPressed: controller.reset, child: const Text('Atur ulang')),
          ]),
          const SizedBox(height: KiraSpace.md),
          Text('Kurangi minuman manis: ${sweet.round()} gelas per hari', style: context.text.bodyLarge),
          Slider(
            key: const Key('sweet_slider'),
            value: sweet.clamp(0, 3).toDouble(),
            max: 3,
            divisions: 3,
            label: '${sweet.round()} gelas',
            onChanged: (v) => controller.update(change.copyWith(sweetDrinksDeltaPerDay: -v)),
          ),
          Text('Turunkan berat badan: ${weight.round()} kg', style: context.text.bodyLarge),
          Slider(
            key: const Key('weight_slider'),
            value: weight.clamp(0, 10).toDouble(),
            max: 10,
            divisions: 10,
            label: '${weight.round()} kg',
            onChanged: (v) => controller.update(change.copyWith(weightDeltaKg: -v)),
          ),
          SwitchListTile(
            key: const Key('active_switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Bergerak minimal 30 menit tiap hari'),
            value: change.active30min ?? false,
            onChanged: (v) => controller.update(_withFlags(change, active: v ? true : null, clearActive: !v)),
          ),
          SwitchListTile(
            key: const Key('veg_switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Makan sayur atau buah tiap hari'),
            value: change.dailyVegFruit ?? false,
            onChanged: (v) => controller.update(_withFlags(change, veg: v ? true : null, clearVeg: !v)),
          ),
          if (whatIf.error != null)
            Padding(
              padding: const EdgeInsets.only(top: KiraSpace.sm),
              child: Text(whatIf.error!, style: context.text.bodyMedium?.copyWith(color: context.scheme.error)),
            ),
        ]),
      ),
    );
  }

  WhatIfChange _withFlags(WhatIfChange c, {bool? active, bool? veg, bool clearActive = false, bool clearVeg = false}) =>
      WhatIfChange(
        active30min: clearActive ? null : (active ?? c.active30min),
        dailyVegFruit: clearVeg ? null : (veg ?? c.dailyVegFruit),
        weightDeltaKg: c.weightDeltaKg,
        sweetDrinksDeltaPerDay: c.sweetDrinksDeltaPerDay,
      );
}

String _n(num v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

/// "Dasar angka ini": kebiasaan yang dibaca dari catatanmu (dan karena itu ikut berubah saat kamu mencatat, mengubah, atau
/// menghapus), kebiasaan yang masih dari jawaban profil, dan faktor yang belum diketahui.
class ProjectionBasisCard extends StatelessWidget {
  const ProjectionBasisCard({super.key, required this.basis});
  final ProjectionBasis basis;

  String _activity() {
    final a = basis.activity;
    if (a.fromLog) {
      return 'Aktif: rata-rata ${_n(a.detail['avg_minutes_per_day'] as num? ?? 0)} menit per hari dari catatanmu '
          '(batas ${_n(a.detail['target_minutes'] as num? ?? 30)} menit).';
    }
    if (a.source == 'profile') {
      return 'Aktif: dari jawabanmu saat mendaftar (${a.answer == true ? 'ya' : 'belum'}). Berubah setelah ada catatan olahraga '
          'selama minimal 3 hari.';
    }
    return 'Aktif: belum diketahui, jadi dihitung untuk dua kemungkinan.';
  }

  String _veg() {
    final v = basis.vegFruit;
    if (v.fromLog) {
      return 'Sayur dan buah: muncul di ${v.detail['days_with']} dari ${v.detail['days_logged']} hari makan tercatat '
          '(perlu hampir tiap hari).';
    }
    if (v.source == 'profile') {
      return 'Sayur dan buah: dari jawabanmu saat mendaftar (${v.answer == true ? 'tiap hari' : 'belum tiap hari'}). Berubah '
          'setelah minimal 3 hari makan tercatat.';
    }
    return 'Sayur dan buah: belum diketahui, jadi dihitung untuk dua kemungkinan.';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('projection_basis'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.fact_check_outlined, size: 20, color: context.scheme.primary),
            const SizedBox(width: KiraSpace.sm),
            Text('Dasar angka ini', style: context.text.titleSmall),
          ]),
          const SizedBox(height: KiraSpace.sm),
          Text(
            'Dihitung ulang setiap kali kamu mencatat, mengubah, atau menghapus catatan. Kebiasaan dibaca dari '
            '${basis.windowDays} hari terakhir (${basis.loggedDays} hari ada catatan).',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: KiraSpace.sm),
          Text(_activity(), key: const Key('basis_activity'), style: context.text.bodyMedium),
          Text(_veg(), key: const Key('basis_veg'), style: context.text.bodyMedium),
          if (basis.unknown.isNotEmpty) ...[
            const SizedBox(height: KiraSpace.xs),
            Text('Belum diketahui: ${basis.unknown.join(', ')}. Karena itu rentangnya melebar.',
                key: const Key('basis_unknown'), style: context.text.bodyMedium),
          ],
          const SizedBox(height: KiraSpace.sm),
          Text(
            'Skor ini hanya membaca aktivitas, sayur dan buah, serta data profil dan hasil cek. Gula, garam, dan tidur tidak '
            'mengubahnya; itu dipantau di Tren dan penanda.',
            style: context.text.bodySmall,
          ),
        ]),
      ),
    );
  }
}

class _HowCalculated extends StatelessWidget {
  const _HowCalculated();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(KiraSpace.xl, 0, KiraSpace.xl, KiraSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bagaimana angka ini dihitung?', style: context.text.titleLarge),
            const SizedBox(height: KiraSpace.md),
            Text(
              'Rentang dihitung dari skor skrining diabetes FINDRISC, memakai profilmu dan kebiasaanmu 14 hari terakhir. '
              'Skor ini tervalidasi, termasuk pada populasi Indonesia. Perhitungannya dilakukan oleh fungsi yang bisa '
              'diaudit, bukan ditebak oleh AI.',
              style: context.text.bodyLarge,
            ),
            const SizedBox(height: KiraSpace.md),
            Text(
              'Faktor yang belum diketahui, misalnya gula darah atau lingkar perut, dihitung untuk semua kemungkinannya. '
              'Itu sebabnya hasilnya berupa rentang. Setelah kamu memasukkan hasil pemeriksaan, rentangnya menyempit.',
              style: context.text.bodyLarge,
            ),
            const SizedBox(height: KiraSpace.md),
            Text(
              'Persentase 10 tahun memakai estimasi resmi skor itu dari penelitian di Finlandia. Studi kohort modern di '
              'Norwegia menemukan angka yang lebih rendah, jadi anggap persentase sebagai gambaran kasar. KIRA melakukan '
              'interpolasi antar kategori skor supaya setiap perubahan kebiasaan terlihat.',
              style: context.text.bodyLarge,
            ),
            const SizedBox(height: KiraSpace.md),
            Text(
              'Nilai gizi makanan diambil dari TKPI Kemenkes 2017; gula dan ukuran porsi adalah perkiraan. '
              'Batas harian gula, natrium, dan lemak mengikuti Permenkes 30/2013.',
              style: context.text.bodyLarge,
            ),
            const SizedBox(height: KiraSpace.md),
            Text(
              'KIRA perkiraan untuk membantu keputusanmu, bukan diagnosis. Pemeriksaan di fasilitas kesehatan selalu lebih tepat.',
              style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
