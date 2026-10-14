/// Kata-kata produk. Tidak ada "aman" atau "menderita"; risiko selalu diungkapkan sebagai rentang kategori.
String categoryLabel(String category) => switch (category) {
      'low' => 'rendah',
      'slightly_elevated' => 'sedikit meningkat',
      'moderate' => 'sedang',
      'high' => 'tinggi',
      'very_high' => 'sangat tinggi',
      _ => category,
    };

String habitLabel(String? habit) => switch (habit) {
      'activity' => 'Bergerak 30 menit sehari',
      'veg_fruit' => 'Sayur atau buah setiap hari',
      'weight' => 'Turun sedikit berat badan',
      'sweet_drinks' => 'Kurangi minuman manis',
      _ => '',
    };

String percent(double fraction) => '${(fraction * 100).round()}%';

String percentRange(double low, double high) {
  final a = (low * 100).round(), b = (high * 100).round();
  return a == b ? '$a%' : '$a-$b%';
}

String bpLabel(String? category) => switch (category) {
      'normal' => 'normal',
      'prehypertension' => 'di atas normal (prehipertensi)',
      'hypertension' => 'tinggi (hipertensi)',
      _ => '',
    };
