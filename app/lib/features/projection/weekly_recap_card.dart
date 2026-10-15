import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/insight_models.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

String _date(String iso) {
  final d = DateTime.parse(iso);
  return '${d.day} ${_months[d.month - 1]}';
}

String _num(double v) {
  final text = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  return text.replaceAll('.', ',');
}

/// Kalimat perubahan dengan kata, supaya arahnya tidak bergantung pada warna.
String _changeText(MetricChange c, String unit) {
  if (c.trend == 'same') return 'hampir sama dengan minggu sebelumnya';
  final verb = c.delta < 0 ? 'turun' : 'naik';
  return '$verb ${_num(c.delta.abs())}$unit dari minggu sebelumnya';
}

/// Rekap minggu lalu: kebiasaan rata-rata per hari dan perubahannya. Nadanya mengamati, tidak menghakimi.
class WeeklyRecapCard extends StatelessWidget {
  const WeeklyRecapCard({super.key, required this.recap});
  final WeeklyRecap recap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final changes = recap.changes;
    Widget row(IconData icon, String label, String value, MetricChange? change, String unit) => Padding(
          padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: KiraSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$label: $value', style: context.text.bodyLarge),
                if (change != null)
                  Text(_changeText(change, unit),
                      style: context.text.bodySmall?.copyWith(
                        color: change.trend == 'better' ? context.kira.improve : scheme.onSurfaceVariant,
                      )),
              ]),
            ),
          ]),
        );

    return Container(
      key: const Key('weekly_recap_card'),
      padding: const EdgeInsets.all(KiraSpace.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(KiraRadius.card),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Rekap minggu lalu', style: context.text.titleMedium),
        Text('${_date(recap.start)} - ${_date(recap.end)} · tercatat ${recap.daysLogged} hari',
            style: context.text.bodySmall),
        const SizedBox(height: KiraSpace.sm),
        if (recap.sweetDrinksPerDay != null)
          row(Icons.local_cafe_outlined, 'Minuman manis', '${_num(recap.sweetDrinksPerDay!)} per hari',
              changes?['sweet_drinks_per_day'], ''),
        if (recap.sugarGPerDay != null)
          row(Icons.grain, 'Gula dari makan dan minum', '${_num(recap.sugarGPerDay!)} g per hari',
              changes?['sugar_g_per_day'], ' g'),
        if (recap.activeMinutesPerDay != null)
          row(Icons.directions_walk, 'Aktif', '${_num(recap.activeMinutesPerDay!)} menit per hari',
              changes?['active_minutes_per_day'], ' menit'),
        if (recap.sleepHoursAvg != null)
          row(Icons.bedtime_outlined, 'Tidur rata-rata', '${_num(recap.sleepHoursAvg!)} jam', null, ''),
        if (changes == null)
          Padding(
            padding: const EdgeInsets.only(top: KiraSpace.xs),
            child: Text('Belum ada minggu pembanding. Perubahan muncul setelah dua minggu tercatat.',
                style: context.text.bodySmall),
          ),
      ]),
    );
  }
}
