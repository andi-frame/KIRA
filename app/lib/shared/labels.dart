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

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

const _weekdayNames = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// "Sen", "Sel", ... (DateTime.weekday: 1 = Senin)
String weekdayShort(DateTime d) => _weekdayNames[d.weekday - 1];

/// "12 Okt 2026"
String formatDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

/// "12 Okt 2026, 14.05"
String formatDateTime(DateTime d) =>
    '${formatDate(d)}, ${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';

/// Angka gizi gaya Indonesia: desimal koma untuk nilai kecil ("2,7"), titik pemisah ribuan ("1.987").
String nutrientNumber(double v) {
  if (v.abs() < 10 && (v * 10).round() != v.round() * 10) return v.toStringAsFixed(1).replaceAll('.', ',');
  return v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
}

/// "gula 2,7 g, natrium 225 mg, lemak 1,2 g" (urutan sama di semua layar).
String nutrientLine({required double sugarG, required double sodiumMg, required double fatG}) =>
    'gula ${nutrientNumber(sugarG)} g, natrium ${nutrientNumber(sodiumMg)} mg, lemak ${nutrientNumber(fatG)} g';
