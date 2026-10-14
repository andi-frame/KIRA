import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/theme.dart';

void main() {
  for (final entry in {'terang': kiraLightTheme, 'gelap': kiraDarkTheme}.entries) {
    group('tema ${entry.key}', () {
      final scheme = entry.value.colorScheme;
      final kira = entry.value.extension<KiraColors>()!;

      test('teks utama dan sekunder lolos WCAG AA pada permukaan dan kartu', () {
        for (final bg in [scheme.surface, scheme.surfaceContainerLowest]) {
          expect(contrastRatio(scheme.onSurface, bg), greaterThanOrEqualTo(7), reason: 'onSurface/$bg');
          expect(contrastRatio(scheme.onSurfaceVariant, bg), greaterThanOrEqualTo(4.5), reason: 'muted/$bg');
        }
      });

      test('tombol primer terbaca', () {
        expect(contrastRatio(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(scheme.onPrimaryContainer, scheme.primaryContainer), greaterThanOrEqualTo(4.5));
      });

      test('kartu perhatian, perbaikan, dan darurat terbaca', () {
        expect(contrastRatio(kira.onAttentionContainer, kira.attentionContainer), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(kira.onImproveContainer, kira.improveContainer), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(scheme.onErrorContainer, scheme.errorContainer), greaterThanOrEqualTo(4.5));
      });

      test('warna teks perhatian dan perbaikan terbaca di atas kartu putih/gelap', () {
        expect(contrastRatio(kira.attention, scheme.surfaceContainerLowest), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(kira.improve, scheme.surfaceContainerLowest), greaterThanOrEqualTo(4.5));
      });

      test('garis grafik terlihat jelas di atas kartu (minimal 3:1)', () {
        expect(contrastRatio(kira.chartNow, scheme.surfaceContainerLowest), greaterThanOrEqualTo(3));
        expect(contrastRatio(kira.chartBetter, scheme.surfaceContainerLowest), greaterThanOrEqualTo(3));
      });
    });
  }

  test('dua kurva grafik tidak bergantung pada warna saja: berbeda luminans', () {
    final k = KiraColors.light;
    expect((k.chartNow.computeLuminance() - k.chartBetter.computeLuminance()).abs(), greaterThan(0.08));
  });
}
