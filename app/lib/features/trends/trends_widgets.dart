import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/insight_models.dart';

const _kindTitle = {
  'blood_pressure': 'Tekanan darah',
  'fasting_glucose': 'Gula darah puasa',
  'random_glucose': 'Gula darah sewaktu',
  'hba1c': 'HbA1c',
  'waist': 'Lingkar perut',
};
const _kindUnit = {
  'blood_pressure': 'mmHg',
  'fasting_glucose': 'mg/dL',
  'random_glucose': 'mg/dL',
  'hba1c': '%',
  'waist': 'cm',
};
const _bandWord = {
  'normal': 'normal',
  'prehypertension': 'normal-tinggi',
  'hypertension': 'rentang hipertensi',
  'prediabetes': 'rentang prediabetes',
  'diabetes_range': 'rentang diabetes',
  'below_cutoff': 'di bawah ambang',
};

/// Skala sumbu dengan batas bulat (kelipatan 1, 2, atau 5 x 10^n) agar tiap garis bantu punya angka sendiri
/// dan tidak ada label ganda di ujung.
({double min, double max, double step}) niceScale(double lo, double hi, {bool zeroBased = false}) {
  // Rentang nol (satu nilai) diberi lebar minimal 5% nilainya supaya skala tidak merosot.
  final span = math.max(hi - lo, math.max(hi.abs() * 0.05, 1e-6));
  final raw = span / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final step = [1.0, 2.0, 5.0, 10.0].map((m) => m * mag).firstWhere((v) => v >= raw);
  final min = zeroBased ? 0.0 : (lo / step).floor() * step;
  var max = (hi / step).ceil() * step;
  if (max - min < step * 2) max = min + step * 4;
  return (min: min, max: max, step: step);
}

String _n(double v) => (v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1)).replaceAll('.', ',');

String _shortDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

String valueText(String kind, ClinicalPoint p) =>
    kind == 'blood_pressure' ? '${p.sys}/${p.dia} ${_kindUnit[kind]}' : '${_n(p.value ?? 0)} ${_kindUnit[kind]}';

// ---------- penanda triase ----------

class TriageCard extends StatelessWidget {
  const TriageCard({super.key, required this.flags});
  final List<TriageFlag> flags;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final kira = context.kira;
    final shown = flags.where((f) => f.level != 'info').toList();
    final infos = flags.where((f) => f.level == 'info').toList();
    ({String label, IconData icon, Color bg, Color fg}) style(String level) => switch (level) {
          'perhatian' => (label: 'Perlu perhatian', icon: Icons.priority_high, bg: kira.attentionContainer, fg: kira.onAttentionContainer),
          'pantau' => (label: 'Pantau', icon: Icons.visibility_outlined, bg: scheme.secondaryContainer, fg: scheme.onSecondaryContainer),
          _ => (label: 'Info', icon: Icons.info_outline, bg: scheme.surfaceContainer, fg: scheme.onSurfaceVariant),
        };

    Widget row(TriageFlag f) {
      final s = style(f.level);
      return Padding(
        padding: const EdgeInsets.only(top: KiraSpace.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: KiraSpace.sm, vertical: 4),
            decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(KiraRadius.chip)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(s.icon, size: 14, color: s.fg),
              const SizedBox(width: 4),
              Text(s.label, style: context.text.labelSmall?.copyWith(color: s.fg, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: KiraSpace.md),
          Expanded(child: Text(f.text, style: context.text.bodyMedium)),
        ]),
      );
    }

    return Card(
      key: const Key('triage_card'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Penanda untuk perhatian', style: context.text.titleMedium),
          if (shown.isEmpty && infos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: KiraSpace.xs),
              child: Text('Tidak ada penanda dari data yang ada.', style: context.text.bodyMedium),
            ),
          for (final f in [...shown, ...infos]) row(f),
          const SizedBox(height: KiraSpace.md),
          Text(
            'Penanda adalah aturan terhadap ambang pedoman (KMK 303/2026 untuk tekanan darah, PERKENI 2021 untuk gula darah), '
            'bukan penegakan penyakit.',
            style: context.text.bodySmall,
          ),
        ]),
      ),
    );
  }
}

// ---------- tren hasil pemeriksaan ----------

class ClinicalTrendCard extends StatelessWidget {
  const ClinicalTrendCard({super.key, required this.kind, required this.series});
  final String kind;
  final ClinicalSeries series;

  @override
  Widget build(BuildContext context) {
    final latest = series.latest!;
    final trend = series.trend;
    final trendIcon = switch (trend) {
      'naik' => Icons.trending_up,
      'turun' => Icons.trending_down,
      _ => Icons.trending_flat,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_kindTitle[kind] ?? kind, style: context.text.titleMedium),
          const SizedBox(height: KiraSpace.xs),
          Text(valueText(kind, latest), style: context.text.headlineSmall),
          Text(
            '${_shortDate(latest.day)}${latest.band != null ? ' · ${_bandWord[latest.band] ?? latest.band}' : ''}',
            style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant),
          ),
          const SizedBox(height: KiraSpace.xs),
          if (trend != null)
            Row(children: [
              Icon(trendIcon, size: 18, color: context.scheme.onSurfaceVariant),
              const SizedBox(width: KiraSpace.xs),
              Text(trend, style: context.text.labelLarge),
              const SizedBox(width: KiraSpace.xs),
              Text('sejak pengukuran pertama (${series.points.length}x)', style: context.text.bodySmall),
            ])
          else
            Text('baru satu pengukuran, belum ada tren', style: context.text.bodySmall),
          const SizedBox(height: KiraSpace.md),
          ClinicalTrendChart(kind: kind, series: series),
        ]),
      ),
    );
  }
}

class ClinicalTrendChart extends StatelessWidget {
  const ClinicalTrendChart({super.key, required this.kind, required this.series}) ;
  final String kind;
  final ClinicalSeries series;

  String get semanticsLabel {
    final p = series.latest!;
    return '${_kindTitle[kind]}: ${series.points.length} pengukuran, terakhir ${valueText(kind, p)} pada ${_shortDate(p.day)}'
        '${series.trend != null ? ', tren ${series.trend}' : ''}.';
  }

  @override
  Widget build(BuildContext context) {
    final kira = context.kira;
    final scheme = context.scheme;
    final label = context.text.labelSmall;
    final points = series.points;
    final t0 = points.first.day;
    final span = math.max(points.last.day.difference(t0).inDays, 1).toDouble();
    double x(ClinicalPoint p) => p.day.difference(t0).inDays.toDouble();

    final isBp = kind == 'blood_pressure';
    final lines = <List<FlSpot>>[
      [for (final p in points) FlSpot(x(p), (isBp ? p.sys! : p.value!).toDouble())],
      if (isBp) [for (final p in points) FlSpot(x(p), p.dia!.toDouble())],
    ];
    // Ambang normal-tinggi hanya di teks: dua pasang garis ambang yang berdekatan membuat label bertumpuk.
    final refs = [for (final r in series.references) if (!r.label.startsWith('Normal-tinggi')) r];
    final all = [for (final l in lines) ...l.map((s) => s.y), ...refs.map((r) => r.value)];
    final scale = niceScale(all.reduce(math.min), all.reduce(math.max));
    final minY = scale.min, maxY = scale.max, step = scale.step;

    LineChartBarData bar(List<FlSpot> spots, Color color, {bool dashed = false}) => LineChartBarData(
          spots: spots,
          color: color,
          barWidth: 2.5,
          isCurved: false,
          dashArray: dashed ? [6, 4] : null,
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 3.5, color: color, strokeWidth: 1.5, strokeColor: scheme.surface),
          ),
        );

    return Semantics(
      label: semanticsLabel,
      image: true,
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1.6,
            child: LineChart(
              key: Key('chart_$kind'),
              LineChartData(
                minX: points.length == 1 ? -1 : 0,
                maxX: points.length == 1 ? 1 : span,
                minY: minY,
                maxY: maxY,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 1),
                ),
                lineTouchData: const LineTouchData(enabled: false),
                extraLinesData: ExtraLinesData(horizontalLines: [
                  for (final r in refs)
                    HorizontalLine(
                      y: r.value,
                      color: kira.attention,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        style: label?.copyWith(color: kira.attention),
                        labelResolver: (_) => '${r.label} ${_n(r.value)}',
                      ),
                    ),
                ]),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: step,
                      getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(_n(double.parse(v.toStringAsFixed(step >= 1 ? 0 : 1))), style: label, textAlign: TextAlign.right),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: points.length == 1 ? 1 : span,
                      getTitlesWidget: (v, _) => points.length == 1 && v.round() != 0
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(_shortDate(t0.add(Duration(days: v.round()))), style: label),
                            ),
                    ),
                  ),
                ),
                lineBarsData: [
                  bar(lines[0], kira.chartNow),
                  if (isBp) bar(lines[1], kira.chartBetter, dashed: true),
                ],
              ),
            ),
          ),
          if (isBp)
            Wrap(spacing: KiraSpace.lg, children: [
              _Key(color: kira.chartNow, text: 'Sistolik'),
              _Key(color: kira.chartBetter, text: 'Diastolik', dashed: true),
            ]),
        ]),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.text, this.dashed = false});
  final Color color;
  final String text;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 18, height: 3, color: dashed ? null : color, child: dashed ? Row(children: [for (var i = 0; i < 3; i++) Expanded(child: Container(color: i.isEven ? color : Colors.transparent))]) : null),
        const SizedBox(width: 6),
        Text(text, style: context.text.labelSmall),
      ]);
}

// ---------- kebiasaan harian ----------

class DailyBarChart extends StatelessWidget {
  const DailyBarChart({
    super.key,
    required this.title,
    required this.days,
    required this.valueOf,
    required this.unit,
    this.limit,
    this.limitLabel,
  });

  final String title, unit;
  final List<DailyPoint> days;
  final double? Function(DailyPoint) valueOf;
  final double? limit;
  final String? limitLabel;

  @override
  Widget build(BuildContext context) {
    final kira = context.kira;
    final scheme = context.scheme;
    final label = context.text.labelSmall;
    final values = [for (final d in days) valueOf(d)];
    final present = values.whereType<double>().toList();
    final scale = niceScale(0, [...present, limit ?? 0, 1.0].reduce(math.max), zeroBased: true);
    final maxVal = scale.max;
    final avg = present.isEmpty ? null : present.reduce((a, b) => a + b) / present.length;
    final dense = days.length > 31;
    final barWidth = math.max(1.5, (dense ? 3.0 : 7.0));

    return Semantics(
      label: '$title: ${present.length} dari ${days.length} hari tercatat'
          '${avg != null ? ', rata-rata ${_n(avg)} $unit' : ''}'
          '${limit != null ? ', batas ${_n(limit!)} $unit' : ''}.',
      image: true,
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$title ($unit)', style: context.text.titleSmall),
          const SizedBox(height: KiraSpace.sm),
          AspectRatio(
            aspectRatio: 2.2,
            child: BarChart(
              BarChartData(
                maxY: maxVal,
                minY: 0,
                alignment: BarChartAlignment.spaceBetween,
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(enabled: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: scale.step,
                  getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 1),
                ),
                extraLinesData: ExtraLinesData(horizontalLines: [
                  if (limit != null)
                    HorizontalLine(y: limit!, color: scheme.onSurface, strokeWidth: 1, dashArray: [4, 4]),
                ]),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: scale.step,
                      getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(_n(double.parse(v.toStringAsFixed(scale.step >= 1 ? 0 : 1))), style: label, textAlign: TextAlign.right),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        final i = v.round();
                        if (days.isEmpty || (i != 0 && i != days.length - 1)) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_shortDate(DateTime.parse(days[i].date)), style: label),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < days.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: values[i] ?? 0,
                        width: barWidth,
                        borderRadius: BorderRadius.circular(1.5),
                        color: values[i] != null && limit != null && values[i]! > limit! ? kira.attention : kira.chartBetter,
                      ),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: KiraSpace.xs),
          Text(
            [
              if (avg != null) 'rata-rata ${_n(avg)} $unit',
              if (limit != null) 'garis putus: ${limitLabel ?? 'batas ${_n(limit!)} $unit'}; batang koral melewatinya',
              'hari tanpa catatan tidak diberi batang',
            ].join(' · '),
            style: context.text.bodySmall,
          ),
        ]),
      ),
    );
  }
}

// ---------- gabungan ----------

/// Isi bersama layar tren dan ringkasan dokter: penanda, tren hasil pemeriksaan, dan kebiasaan harian.
class TrendsSection extends StatelessWidget {
  const TrendsSection({super.key, required this.data, this.showTriage = true});
  final TrendsData data;
  final bool showTriage;

  @override
  Widget build(BuildContext context) {
    const kinds = ['blood_pressure', 'fasting_glucose', 'random_glucose', 'hba1c'];
    final withData = [for (final k in kinds) if (data.series(k).points.isNotEmpty) k];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showTriage) ...[TriageCard(flags: data.triage), const SizedBox(height: KiraSpace.lg)],
      Text('Tren hasil pemeriksaan', style: context.text.titleLarge),
      const SizedBox(height: KiraSpace.sm),
      if (withData.isEmpty)
        Card(
          key: const Key('clinical_empty'),
          child: Padding(
            padding: const EdgeInsets.all(KiraSpace.lg),
            child: Text(
              'Belum ada hasil pemeriksaan. Setelah kamu mencatat hasil gula darah atau tensi lewat tab Cek, tren-nya muncul di sini.',
              style: context.text.bodyMedium,
            ),
          ),
        )
      else
        for (final k in withData) ...[ClinicalTrendCard(kind: k, series: data.series(k)), const SizedBox(height: KiraSpace.md)],
      const SizedBox(height: KiraSpace.md),
      Text('Kebiasaan harian', style: context.text.titleLarge),
      Text('${data.daysLogged} dari ${data.daily.length} hari tercatat', style: context.text.bodyMedium),
      const SizedBox(height: KiraSpace.md),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(KiraSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KeyedSubtree(
              key: const Key('chart_sugar'),
              child: DailyBarChart(
                title: 'Gula dari makan dan minum per hari',
                days: data.daily,
                valueOf: (d) => d.sugarG,
                unit: 'g',
                limit: data.sugarLimitG,
                limitLabel: 'batas ${_n(data.sugarLimitG)} g per hari (Permenkes 30/2013)',
              ),
            ),
            const SizedBox(height: KiraSpace.xl),
            KeyedSubtree(
              key: const Key('chart_sleep'),
              child: DailyBarChart(title: 'Jam tidur per malam', days: data.daily, valueOf: (d) => d.sleepHours, unit: 'jam'),
            ),
            const SizedBox(height: KiraSpace.xl),
            KeyedSubtree(
              key: const Key('chart_active'),
              child: DailyBarChart(
                title: 'Menit aktif per hari',
                days: data.daily,
                valueOf: (d) => d.activeMinutes,
                unit: 'menit',
                limit: data.activeTargetMin,
                limitLabel: 'target ${_n(data.activeTargetMin)} menit',
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}
