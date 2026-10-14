import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/family_models.dart';
import '../../shared/widgets.dart';

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
        padding: const EdgeInsets.all(KiraSpace.lg),
        children: [
          Text('Satu halaman untuk dibawa ke dokter atau ahli gizi: pola makan, tidur, dan hasil pemeriksaanmu.',
              style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant)),
          const SizedBox(height: KiraSpace.lg),
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
              FilledButton.icon(
                key: const Key('copy_summary'),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Salin ringkasan'),
                onPressed: () => _copy(s.text),
              ),
            ]),
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
