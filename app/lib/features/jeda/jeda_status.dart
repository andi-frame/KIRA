import 'jeda_bridge.dart';
import 'jeda_models.dart';

/// Kata-kata layar status Jeda sosmed. Fungsi murni supaya mudah diuji.

const kindLabels = {'morning': 'rencana pagi', 'evening': 'catat hari ini', 'night': 'waktunya tidur', 'other': 'sudah sempat cek', 'fact': 'fun fact'};

String ago(DateTime? at, DateTime now) {
  if (at == null) return 'belum pernah';
  final s = now.difference(at).inSeconds;
  if (s < 5) return 'baru saja';
  if (s < 60) return '$s detik lalu';
  if (s < 3600) return '${s ~/ 60} menit lalu';
  if (s < 86400) return '${s ~/ 3600} jam lalu';
  return '${s ~/ 86400} hari lalu';
}

String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';

/// Seandainya aplikasi pilihan dibuka SEKARANG: kartu apa yang akan tampil, atau mengapa tidak ada.
String nowExplanation(JedaDiagnostics d, JedaSettings s) {
  switch (d.nowCode) {
    case 'ready':
      return 'Siap. Bila aplikasi pilihan dibuka sekarang, tampil: ${d.nowKinds.map((k) => kindLabels[k] ?? k).join(', ')}.';
    case 'off':
      return 'Jeda sosmed sedang mati.';
    case 'no_apps':
      return 'Belum ada aplikasi yang dicentang. Pilih minimal satu di bawah.';
    case 'skip_day':
      return 'Kamu memilih "Lewati sampai besok", jadi kartu berhenti sampai pukul 04.00.';
    case 'grace':
      return 'Sedang masa bebas${d.graceUntil == null ? '' : ' sampai ${_clock(d.graceUntil!)}'} setelah kartu terakhir kamu tutup. '
          'Matikan "bebas buka sosmed selama" bila ingin kartu di setiap pembukaan.';
    case 'no_content':
      return 'Isi kartu belum sampai ke ponsel (butuh sinyal saat KIRA dibuka). Buka KIRA sebentar dengan koneksi aktif, '
          'atau nyalakan Fun fact yang tidak butuh sinyal.';
    case 'cap_reached':
      return 'Jatah tiga kali hari ini untuk kartu yang berlaku sekarang sudah terpakai. Besok mulai dari nol.';
    case 'already_logged':
      return 'Semua yang perlu diingatkan sudah tercatat, jadi tidak ada kartu sekarang.';
    case 'outside_window':
    default:
      final fun = s.funFact ? '' : ' Nyalakan "Fun fact kesehatan" supaya ada kartu di jam berapa pun.';
      return 'Sekarang di luar jam kartu terjadwal (pagi mulai ${clock(s.morningStart)}, catat mulai ${clock(s.eveningStart)}, '
          'tidur mulai ${clock(s.nightStart)}), jadi aplikasi sosmed dibuka biasa.$fun';
  }
}

/// Apa yang terjadi pada pembukaan aplikasi pilihan yang terakhir.
String lastReasonText(JedaDiagnostics d) {
  switch (d.lastReason) {
    case 'shown':
      return 'Kartu tampil.';
    case 'overlay_failed':
      return 'Kartu gagal dipasang oleh sistem${d.lastError.isEmpty ? '' : ' (${d.lastError})'}. Cek izin "Tampil di atas aplikasi lain".';
    case 'no_overlay_permission':
      return 'Kartu siap tampil tetapi izin "Tampil di atas aplikasi lain" tidak aktif.';
    case 'outside_window':
      return 'Tidak ada kartu: di luar jam kartu terjadwal.';
    case 'grace':
      return 'Tidak ada kartu: sedang masa bebas.';
    case 'skip_day':
      return 'Tidak ada kartu: dilewati sampai besok.';
    case 'cap_reached':
      return 'Tidak ada kartu: jatah tiga kali sudah terpakai.';
    case 'already_logged':
      return 'Tidak ada kartu: semua sudah tercatat.';
    case 'no_content':
      return 'Tidak ada kartu: isi kartu belum ada di ponsel.';
    case '':
      return '';
    default:
      return d.lastReason;
  }
}

/// Saran sesuai merek ponsel: sebagian pabrikan mematikan layanan latar secara agresif.
String? batteryHint(JedaDiagnostics d) {
  if (d.batteryIgnored) return null;
  final brand = d.manufacturer;
  final specific = switch (brand) {
    'xiaomi' || 'redmi' || 'poco' => ' Di Xiaomi/Redmi/POCO: Pengaturan > Aplikasi > KIRA > Mulai otomatis (aktifkan) dan Penghemat baterai > Tanpa batasan.',
    'oppo' || 'realme' || 'oneplus' => ' Di Oppo/Realme/OnePlus: Pengaturan > Baterai > KIRA > izinkan aktivitas latar dan mulai otomatis.',
    'vivo' || 'iqoo' => ' Di Vivo/iQOO: Pengaturan > Baterai > Konsumsi daya latar > KIRA > Izinkan.',
    'huawei' || 'honor' => ' Di Huawei/Honor: Pengaturan > Aplikasi > Peluncuran aplikasi > KIRA > Kelola manual, aktifkan semua.',
    'samsung' => ' Di Samsung: Pengaturan > Baterai > Batas penggunaan di latar belakang, keluarkan KIRA dari daftar "Aplikasi tidur".',
    _ => '',
  };
  return 'Penghemat baterai bisa mematikan layanan Jeda sosmed saat layar terkunci atau lama tidak dipakai. '
      'Kecualikan KIRA dari penghemat baterai.$specific';
}
