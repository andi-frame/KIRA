import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/insight_models.dart';
import '../../shared/widgets.dart';
import 'insight_cards.dart';
import 'trends_widgets.dart';

final trendsProvider = FutureProvider.family<TrendsData, int>((ref, days) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getTrends(days);
});

/// Tren hasil pemeriksaan dan kebiasaan, beserta penanda untuk membantu dokter memprioritaskan.
class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final trends = ref.watch(trendsProvider(_days));
    return Scaffold(
      appBar: AppBar(title: const Text('Tren dan penanda')),
      body: ListView(
        padding: const EdgeInsets.all(KiraSpace.lg),
        children: [
          Text('Gambaran hasil pemeriksaan dan kebiasaanmu dari waktu ke waktu, untuk dibahas bersama dokter.',
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
          trends.when(
            loading: () => const Padding(padding: EdgeInsets.all(KiraSpace.xl), child: Center(child: CircularProgressIndicator.adaptive())),
            error: (e, _) => SizedBox(
              height: 240,
              child: LoadError(
                message: e is ApiException ? e.message : 'Tren belum bisa dimuat. Coba lagi sebentar lagi ya.',
                onRetry: () => ref.invalidate(trendsProvider(_days)),
              ),
            ),
            data: (data) => TrendsSection(data: data),
          ),
          const SizedBox(height: KiraSpace.xl),
          const RiskHistoryCard(),
          const SizedBox(height: KiraSpace.lg),
          const SleepPatternsCard(),
        ],
      ),
    );
  }
}
