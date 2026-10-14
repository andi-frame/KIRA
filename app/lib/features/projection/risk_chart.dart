import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/labels.dart';

/// Dua pita rentang risiko kumulatif 0-10 tahun: kebiasaan sekarang (garis penuh, koral) dan
/// kebiasaan diperbaiki (garis putus, teal). Pita, bukan satu garis, karena ketidakpastian ditampilkan.
class RiskBandChart extends StatelessWidget {
  const RiskBandChart({
    super.key,
    required this.nowLow,
    required this.nowHigh,
    this.afterLow,
    this.afterHigh,
  });

  final List<double> nowLow, nowHigh;
  final List<double>? afterLow, afterHigh;

  List<FlSpot> _spots(List<double> curve) => [for (var i = 0; i < curve.length; i++) FlSpot(i.toDouble(), curve[i] * 100)];

  String get semanticsLabel {
    final now = percentRange(nowLow.last, nowHigh.last);
    final base = 'Grafik risiko 10 tahun. Kebiasaan sekarang, kira-kira $now.';
    if (afterLow == null || afterHigh == null) return base;
    return '$base Kalau kebiasaan diperbaiki, kira-kira ${percentRange(afterLow!.last, afterHigh!.last)}.';
  }

  @override
  Widget build(BuildContext context) {
    final kira = context.kira;
    final scheme = context.scheme;
    final peak = [nowHigh.last, afterHigh?.last ?? 0].reduce(math.max) * 100;
    final maxY = math.max(10.0, (peak / 10).ceil() * 10.0).clamp(10.0, 100.0);
    final labelStyle = context.text.labelSmall;

    LineChartBarData line(List<double> curve, Color color, {bool dashed = false}) => LineChartBarData(
          spots: _spots(curve),
          color: color,
          barWidth: 3,
          isCurved: true,
          curveSmoothness: 0.15,
          dotData: const FlDotData(show: false),
          dashArray: dashed ? [8, 5] : null,
        );

    final hasAfter = afterLow != null && afterHigh != null;
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: 1.45,
          child: LineChart(
            key: const Key('risk_chart'),
            LineChartData(
              minX: 0,
              maxX: 10,
              minY: 0,
              maxY: maxY,
              lineTouchData: const LineTouchData(enabled: false),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: maxY / 4,
                    getTitlesWidget: (value, meta) =>
                        Padding(padding: const EdgeInsets.only(right: 6), child: Text('${value.round()}%', style: labelStyle, textAlign: TextAlign.right)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 2,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(value == 0 ? 'Kini' : '${value.round()} th', style: labelStyle),
                    ),
                  ),
                ),
              ),
              lineBarsData: [
                line(nowLow, kira.chartNow),
                line(nowHigh, kira.chartNow),
                if (hasAfter) line(afterLow!, kira.chartBetter, dashed: true),
                if (hasAfter) line(afterHigh!, kira.chartBetter, dashed: true),
              ],
              betweenBarsData: [
                BetweenBarsData(fromIndex: 0, toIndex: 1, color: kira.chartNow.withAlpha(46)),
                if (hasAfter) BetweenBarsData(fromIndex: 2, toIndex: 3, color: kira.chartBetter.withAlpha(46)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
