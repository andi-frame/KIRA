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
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(label, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text(
                        '${nutrientNumber(value)} / ${nutrientNumber(limit)} $unit',
                        style: context.text.bodySmall?.copyWith(color: context.scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: over
                        ? context.kira.attentionContainer.withValues(alpha: 0.5)
                        : context.scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    words,
                    style: context.text.labelSmall?.copyWith(
                      color: over ? context.kira.attention : context.scheme.onSurfaceVariant,
                      fontWeight: over ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: limit <= 0 ? 0 : (value / limit).clamp(0, 1).toDouble(),
                minHeight: 7,
                color: color,
                backgroundColor: context.scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
