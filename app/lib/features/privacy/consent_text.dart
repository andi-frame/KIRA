import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Ringkasan persetujuan dalam bahasa sehari-hari. Isinya harus sama dengan yang sebenarnya dilakukan sistem:
/// ubah teks ini bersamaan dengan `CONSENT_VERSION` di backend bila praktik pemrosesan berubah.
const consentSummary = 'Data kesehatan tergolong data pribadi yang spesifik (UU PDP No. 27 Tahun 2022). '
    'Sebelum memakai KIRA, baca dan setujui hal berikut.';

const consentPoints = <({String title, String body})>[
  (
    title: 'Data apa yang diproses',
    body: 'Profilmu (usia, jenis kelamin, tinggi, berat), catatan makan, minum, tidur, dan aktivitas, hasil '
        'pemeriksaan yang kamu masukkan, percakapan dengan KIRA, dan bila kamu menyalakannya, langkah serta tidur '
        'dari Health Connect.',
  ),
  (
    title: 'Untuk apa',
    body: 'Menghitung proyeksi risiko, target harian, dan rekomendasi cek. Tidak untuk iklan dan tidak dijual.',
  ),
  (
    title: 'Ke mana data pergi',
    body: 'Disimpan di server KIRA. Teks dan foto percakapan dikirim ke penyedia model bahasa agar bisa dibaca '
        'menjadi catatan, dan suara dikirim ke layanan transkripsi. Angka risiko dan gizi dihitung oleh KIRA, '
        'bukan oleh model bahasa.',
  ),
  (
    title: 'Siapa yang bisa melihat',
    body: 'Hanya kamu. Keluarga atau dokter hanya melihat apa yang kamu izinkan, dan kamu bisa melihat riwayat '
        'siapa yang membukanya.',
  ),
  (
    title: 'Hakmu',
    body: 'Kamu bisa mengunduh seluruh datamu dan menghapus akun beserta isinya kapan saja di Profil, Data dan '
        'privasi. Menghapus akun sama dengan menarik persetujuan.',
  ),
  (
    title: 'Batas KIRA',
    body: 'KIRA bukan alat diagnosis dan tidak memberi saran obat.',
  ),
];

/// Isi persetujuan yang bisa digulir. Dipakai di bottom sheet (saat daftar) dan di dialog persetujuan ulang.
class ConsentBody extends StatelessWidget {
  const ConsentBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(consentSummary, style: context.text.bodyMedium),
        for (final p in consentPoints) ...[
          const SizedBox(height: KiraSpace.md),
          Text(p.title, style: context.text.titleSmall),
          const SizedBox(height: KiraSpace.xs),
          Text(p.body, style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

Future<void> showConsentSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 1,
        snap: true,
        snapSizes: const [0.6],
        builder: (_, controller) => ListView(
          key: const Key('consent_sheet'),
          controller: controller,
          padding: const EdgeInsets.fromLTRB(KiraSpace.xl, 0, KiraSpace.xl, KiraSpace.xl),
          children: [
            Text('Persetujuan data kesehatan', style: ctx.text.titleLarge),
            const SizedBox(height: KiraSpace.md),
            const ConsentBody(),
            const SizedBox(height: KiraSpace.xl),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mengerti')),
          ],
        ),
      ),
    );
