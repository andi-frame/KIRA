import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/share_service.dart';
import '../../core/theme.dart';
import '../../shared/family_models.dart';
import '../../shared/widgets.dart';
import '../trends/trends_screen.dart';
import 'share_links.dart';
import '../trends/trends_widgets.dart';

final doctorSummaryProvider = FutureProvider.family<DoctorSummary, int>((ref, days) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getDoctorSummary(days);
});

final foodGlucoseProvider = FutureProvider<FoodGlucose>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getFoodGlucose();
});

class DoctorSummaryScreen extends ConsumerStatefulWidget {
  const DoctorSummaryScreen({super.key});

  @override
  ConsumerState<DoctorSummaryScreen> createState() => _DoctorSummaryScreenState();
}

class _DoctorSummaryScreenState extends ConsumerState<DoctorSummaryScreen> {
  int _days = 30;
  bool _sharing = false;

  /// PDF dibuat server dari angka yang sama dengan layar ini, lalu dibagikan lewat menu bagikan sistem (mis. WhatsApp).
  Future<void> _sharePdf() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(apiProvider).getDoctorPdf(_days);
      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      await ref.read(shareServiceProvider).sharePdf(
            bytes,
            'kira-ringkasan-$stamp.pdf',
            message: 'Ringkasan KIRA untuk dokter ($_days hari). Dibuat otomatis dari catatan pengguna; bukan diagnosis.',
          );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('PDF belum bisa dibagikan. Coba lagi, atau salin ringkasannya.')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ringkasan disalin. Tempel ke pesan atau cetak.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(doctorSummaryProvider(_days));
    return Scaffold(
      appBar: AppBar(title: const Text('Ringkasan untuk dokter')),
      body: ListView(
        padding: context.pagePadding,
        children: [
          const PageIntro('Pola makan, tidur, dan hasil cekmu dalam satu halaman untuk dokter atau ahli gizi.'),
          Wrap(spacing: KiraSpace.sm, children: [
            for (final d in const [7, 30, 90])
              ChoiceChip(
                key: Key('period_$d'),
                label: Text('$d hari'),
                selected: _days == d,
                onSelected: (_) => setState(() => _days = d),
              ),
          ]),
          const SizedBox(height: KiraSpace.lg),
          summary.when(
            loading: () => const Padding(padding: EdgeInsets.all(KiraSpace.xl), child: Center(child: CircularProgressIndicator.adaptive())),
            error: (e, _) => SizedBox(
              height: 240,
              child: LoadError(
                message: e is ApiException ? e.message : 'Ringkasan belum bisa dimuat. Coba lagi sebentar lagi ya.',
                onRetry: () => ref.invalidate(doctorSummaryProvider(_days)),
              ),
            ),
            data: (s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (s.daysLogged == 0)
                const Padding(
                  padding: EdgeInsets.only(bottom: KiraSpace.md),
                  child: SoftNote(
                    key: Key('summary_empty_hint'),
                    icon: Icons.edit_note,
                    text: 'Belum ada catatan pada periode ini. Mulai check-in dulu supaya ringkasan terisi.',
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(KiraSpace.lg),
                  child: SelectableText(s.text, key: const Key('summary_text'), style: context.text.bodyLarge),
                ),
              ),
              const SizedBox(height: KiraSpace.md),
              Wrap(spacing: KiraSpace.sm, runSpacing: KiraSpace.sm, children: [
                FilledButton.icon(
                  key: const Key('share_pdf'),
                  icon: _sharing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Bagikan PDF'),
                  onPressed: _sharing ? null : _sharePdf,
                ),
                OutlinedButton.icon(
                  key: const Key('copy_summary'),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Salin ringkasan'),
                  onPressed: () => _copy(s.text),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: KiraSpace.lg),
          ShareLinksCard(days: _days),
          const SizedBox(height: KiraSpace.xl),
          ref.watch(trendsProvider(_days)).when(
                loading: () => const Padding(padding: EdgeInsets.all(KiraSpace.lg), child: Center(child: CircularProgressIndicator.adaptive())),
                error: (_, _) => Text('Grafik tren belum bisa dimuat.', style: context.text.bodyMedium),
                data: (t) => TrendsSection(data: t),
              ),
          const SizedBox(height: KiraSpace.xl),
          const _FoodGlucoseCard(),
        ],
      ),
    );
  }
}

class _FoodGlucoseCard extends ConsumerWidget {
  const _FoodGlucoseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(foodGlucoseProvider);
    return Card(
      key: const Key('food_glucose_card'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Makanan dan gula darahmu', style: context.text.titleMedium),
          const SizedBox(height: KiraSpace.xs),
          data.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Text('Wawasan ini belum bisa dimuat.', style: context.text.bodyMedium),
            data: (g) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (g.needsMoreData)
                Text(
                  'Untuk yang punya glukometer: catat gula darah sewaktu setelah makan. Butuh minimal 3 pasang data per '
                  'makanan untuk menampilkan pola. Sudah ada ${g.totalReadings} pembacaan.',
                  style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant),
                )
              else
                for (final f in g.foods)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
                    child: Row(children: [
                      Expanded(child: Text(f.name, style: context.text.bodyLarge)),
                      Text('rata-rata ${f.avgMgDl} mg/dL (${f.samples}x)', style: context.text.bodyMedium),
                    ]),
                  ),
              if (g.disclaimer.isNotEmpty) ...[
                const SizedBox(height: KiraSpace.sm),
                Text(g.disclaimer, style: context.text.bodySmall),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
