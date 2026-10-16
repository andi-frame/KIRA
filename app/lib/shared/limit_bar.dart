import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'labels.dart';

/// Posisi terhadap batas harian, ditulis dengan kata ("sisa 12 g" / "melewati batas 8 g"), bukan hanya warna.
class LimitBar extends StatelessWidget {
  const LimitBar({super.key, required this.label, required this.value, required this.limit, required this.unit});
  final String label;
  final double value;
  final double limit;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final over = value > limit;
    final words = over
        ? 'melewati batas ${nutrientNumber(value - limit)} $unit'
        : 'sisa ${nutrientNumber(limit - value)} $unit';
    final color = over ? context.kira.attention : context.scheme.primary;
    return Semantics(
      label: '$label ${nutrientNumber(value)} dari batas ${nutrientNumber(limit)} $unit, $words',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('$label ${nutrientNumber(value)} / ${nutrientNumber(limit)} $unit',
                  style: context.text.bodyMedium)),
              Text(words, style: context.text.bodySmall?.copyWith(fontWeight: over ? FontWeight.w700 : null)),
            ]),
            const SizedBox(height: 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: limit <= 0 ? 0 : (value / limit).clamp(0, 1).toDouble(),
                minHeight: 6,
                color: color,
                backgroundColor: context.scheme.surfaceContainerHighest,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
