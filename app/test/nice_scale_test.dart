import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/trends/trends_widgets.dart';

void main() {
  test('skala memakai kelipatan bulat dan mencakup semua nilai', () {
    final s = niceScale(104, 131);
    expect(s.step, 10);
    expect(s.min, 100);
    expect(s.max, 140);
    expect(s.min <= 104 && s.max >= 131, isTrue);
  });

  test('skala berbasis nol untuk batang, batas atas mencakup nilai tertinggi', () {
    final s = niceScale(0, 72, zeroBased: true);
    expect(s.min, 0);
    expect(s.max, greaterThanOrEqualTo(72));
    expect(s.max % s.step, 0);
  });

  test('rentang sangat sempit tetap menghasilkan empat langkah', () {
    final s = niceScale(5.9, 5.9);
    expect((s.max - s.min) / s.step, greaterThanOrEqualTo(3));
    expect(s.min <= 5.9 && s.max >= 5.9, isTrue);
  });

  test('nilai pecahan (HbA1c) memakai langkah pecahan', () {
    final s = niceScale(5.6, 6.6);
    expect(s.step, lessThan(1));
    expect(s.min <= 5.6 && s.max >= 6.6, isTrue);
  });

  test('satu nilai tunggal tidak menghasilkan skala mikroskopis', () {
    final s = niceScale(120, 120);
    expect(s.step, greaterThanOrEqualTo(1));
    expect(s.min <= 120 && s.max >= 120, isTrue);
  });

  test('batas atas tidak digelembungkan tanpa perlu (88 dengan batas 50 tidak menjadi 200)', () {
    final s = niceScale(0, 88, zeroBased: true);
    expect(s.max, lessThanOrEqualTo(100));
  });
}
