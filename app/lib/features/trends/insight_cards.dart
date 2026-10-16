import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/clinical_extras_models.dart';
import '../../shared/labels.dart';
import 'trends_widgets.dart' show niceScale;

final riskHistoryProvider = FutureProvider.autoDispose<RiskHistory>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getRiskHistory(180);
});

final sleepPatternsProvider = FutureProvider.autoDispose<SleepPatterns>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getPatterns(60);
});

String _n(double v) => (v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1)).replaceAll('.', ',');

/// Bagaimana rentang skor FINDRISC berubah seiring data masuk. Pita mewakili rentang, bukan satu angka pasti.
class RiskHistoryCard extends ConsumerWidget {
  const RiskHistoryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(riskHistoryProvider);
    return Card(
      key: const Key('risk_history_card'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Skor risiko dari waktu ke waktu', style: context.text.titleMedium),
          const SizedBox(height: KiraSpace.xs),
          history.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Text('Riwayat skor belum bisa dimuat.', style: context.text.bodyMedium),
            data: (h) => _body(context, h),
          ),
        ]),
      ),
    );
  }

  Widget _body(BuildContext context, RiskHistory h) {
    if (h.points.length < 2) {
      return Text(
        h.points.isEmpty
            ? 'Belum ada riwayat. Skor mulai dicatat saat kamu check-in atau memasukkan hasil cek.'
            : 'Baru satu hari tercatat. Grafik muncul setelah ada dua hari atau lebih.',
        key: const Key('risk_history_empty'),
        style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant),
      );
    }
    final t0 = h.points.first.date;
    double x(RiskPoint p) => p.date.difference(t0).inDays.toDouble();
    final span = math.max(h.points.last.date.difference(t0).inDays, 1).toDouble();
    final scale = niceScale(
      math.min(h.points.map((p) => p.low).reduce(math.min).toDouble(), 0),
      math.max(h.points.map((p) => p.high).reduce(math.max).toDouble(), 8),
      zeroBased: true,
    );
    final kira = context.kira;
    final scheme = context.scheme;
    final label = context.text.labelSmall;
    final first = h.points.first, last = h.points.last;
    final narrowed = (last.high - last.low) < (first.high - first.low);
    final semantic = 'Skor FINDRISC ${first.low}-${first.high} pada ${formatDate(first.date)} menjadi ${last.low}-${last.high} '
        'pada ${formatDate(last.date)}${narrowed ? ', rentangnya menyempit' : ''}.';

    LineChartBarData line(List<FlSpot> spots, Color color, {BarAreaData? area}) => LineChartBarData(
          spots: spots,
          color: color,
          barWidth: 2.5,
          isCurved: false,
          belowBarData: area ?? BarAreaData(show: false),
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 3, color: color, strokeWidth: 1.5, strokeColor: scheme.surface),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Rentang skor ${first.low}-${first.high} → ${last.low}-${last.high}'
        '${narrowed ? ' (menyempit karena data nyata masuk)' : ''}',
        key: const Key('risk_history_summary'),
        style: context.text.bodyMedium,
      ),
      const SizedBox(height: KiraSpace.md),
      Semantics(
        label: semantic,
        image: true,
        child: ExcludeSemantics(
          child: AspectRatio(
            aspectRatio: 1.7,
            child: LineChart(
              key: const Key('chart_risk_history'),
              LineChartData(
                minX: 0,
                maxX: span,
                minY: scale.min,
                maxY: scale.max,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: scale.step,
                  getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 1),
                ),
                lineTouchData: const LineTouchData(enabled: false),
                extraLinesData: ExtraLinesData(horizontalLines: [
                  for (final b in h.boundaries.where((b) => b > scale.min && b < scale.max))
                    HorizontalLine(
                      y: b.toDouble(),
                      color: kira.attention.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        style: label?.copyWith(color: kira.attention),
                        labelResolver: (_) => 'kategori naik di $b',
                      ),
                    ),
                ]),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: scale.step,
                      getTitlesWidget: (v, _) => Padding(padding: const EdgeInsets.only(right: 6), child: Text(_n(v), style: label)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: span,
                      getTitlesWidget: (v, _) {
                        if (v != 0 && v != span) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(formatDate(t0.add(Duration(days: v.round()))).replaceAll(RegExp(r' \d{4}$'), ''), style: label),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  line([for (final p in h.points) FlSpot(x(p), p.high.toDouble())], kira.chartNow),
                  line([for (final p in h.points) FlSpot(x(p), p.low.toDouble())], kira.chartBetter),
                ],
                betweenBarsData: [
                  BetweenBarsData(fromIndex: 0, toIndex: 1, color: kira.chartNow.withValues(alpha: 0.12)),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: KiraSpace.sm),
      Text(
        'Garis atas = kemungkinan tertinggi, garis bawah = terendah. Rentang melebar saat profil atau hasil cek belum ada.',
        style: context.text.bodySmall,
      ),
    ]);
  }
}

/// Pola deskriptif: hari tidur pendek dibanding hari lain. Selalu disertai catatan "bukan sebab pasti".
class SleepPatternsCard extends ConsumerWidget {
  const SleepPatternsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sleepPatternsProvider);
    return Card(
      key: const Key('sleep_patterns_card'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tidur dan kebiasaanmu', style: context.text.titleMedium),
          const SizedBox(height: KiraSpace.xs),
          data.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Text('Pola belum bisa dimuat.', style: context.text.bodyMedium),
            data: (p) => _body(context, p),
          ),
        ]),
      ),
    );
  }

  Widget _body(BuildContext context, SleepPatterns p) {
    final h = _n(p.thresholdHours);
    if (p.needsMoreData) {
      return Text(
        'Butuh minimal ${p.minPerGroup} hari tidur kurang dari $h jam dan ${p.minPerGroup} hari lainnya untuk dibandingkan. '
        'Sekarang ${p.shortDays} hari tidur pendek dan ${p.otherDays} hari lainnya. Catat tidurmu tiap pagi.',
        key: const Key('patterns_need_more'),
        style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Hari tidur kurang dari $h jam (${p.shortDays} hari) dibanding hari lain (${p.otherDays} hari):', style: context.text.bodyMedium),
      const SizedBox(height: KiraSpace.sm),
      for (final c in p.comparisons)
        Padding(
          key: Key('pattern_${c.key}'),
          padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(c.label, style: context.text.bodyLarge)),
            Text(
              '${_n(c.shortAvg)} vs ${_n(c.otherAvg)} ${c.unit}  (${c.diff >= 0 ? '+' : ''}${_n(c.diff)})',
              style: context.text.bodyMedium,
            ),
          ]),
        ),
      const SizedBox(height: KiraSpace.sm),
      Text(
        p.disclaimer.isEmpty
            ? 'Ini pola dari catatanmu sendiri, bukan sebab pasti.'
            : p.disclaimer,
        key: const Key('patterns_disclaimer'),
        style: context.text.bodySmall,
      ),
    ]);
  }
}
