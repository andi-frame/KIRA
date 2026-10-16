/// Fun fact kesehatan untuk kartu Jeda sosmed: satu fakta singkat yang menemani keputusan "lanjut buka atau tidak?".
///
/// Setiap angka dan pernyataan di sini sudah dicocokkan dengan sumbernya (lihat [JedaFact.source]); yang bergantung pada
/// studi kecil ditulis sebagai studi kecil. Tidak ada nasihat obat atau dosis, tidak ada diagnosis, dan tidak memakai kata
/// "aman". Kalimat dijaga netral: fakta, bukan ceramah. Verifikasi terakhir: 16 Oktober 2026.
library;

class JedaFact {
  const JedaFact({required this.id, required this.category, required this.text, required this.source});

  /// Stabil: dipakai untuk menguji dan agar urutan putar tidak berubah diam-diam.
  final String id;

  /// Judul bagian kartu, mis. "Bergerak", "Makan", "Tidur".
  final String category;
  final String text;
  final String source;

  Map<String, dynamic> toMap() => {'id': id, 'category': category, 'text': text, 'source': source};
}

const jedaFacts = <JedaFact>[
  JedaFact(
    id: 'who_activity_150',
    category: 'Bergerak',
    text: 'Orang dewasa disarankan bergerak dengan intensitas sedang minimal 150 menit per minggu, kira-kira 30 menit '
        'lima hari seminggu. Berapa pun gerak yang kamu tambah lebih baik daripada tidak bergerak sama sekali.',
    source: 'WHO, Physical activity fact sheet (26 Jun 2024)',
  ),
  JedaFact(
    id: 'who_sedentary',
    category: 'Bergerak',
    text: 'Duduk atau berbaring lama saat terjaga disebut perilaku sedenter. Scroll sambil rebahan termasuk di dalamnya. '
        'Berdiri dan berjalan sebentar di sela-selanya sudah mengurangi waktu sedenter.',
    source: 'WHO, Physical activity fact sheet (26 Jun 2024)',
  ),
  JedaFact(
    id: 'dpp_lifestyle_58',
    category: 'Bergerak',
    text: 'Pada penelitian besar terhadap 3.234 orang berisiko diabetes, program gaya hidup (turun berat badan dan aktif '
        'bergerak) menurunkan kejadian diabetes tipe 2 sebesar 58% dibanding kelompok pembanding.',
    source: 'Diabetes Prevention Program Research Group, N Engl J Med 2002;346:393-403',
  ),
  JedaFact(
    id: 'walk_after_meal',
    category: 'Bergerak',
    text: 'Pada studi kecil (41 orang dengan diabetes tipe 2), jalan santai 10 menit setelah makan membuat kenaikan gula '
        'darah setelah makan lebih rendah. Bila kamu punya penyakit jantung, tanyakan dulu ke dokter.',
    source: 'Reynolds dkk., Diabetologia 2016 (studi acak silang, 41 orang)',
  ),
  JedaFact(
    id: 'who_veg_400',
    category: 'Makan',
    text: 'Semua orang di atas 10 tahun disarankan makan buah dan sayur setidaknya 400 gram per hari. Isi piringmu dengan '
        'sayur dulu sebelum lauk dan nasi.',
    source: 'WHO, Healthy diet fact sheet (26 Jan 2026)',
  ),
  JedaFact(
    id: 'who_sugar',
    category: 'Makan',
    text: 'WHO menyarankan gula bebas kurang dari 10% energi harian, kira-kira 50 gram atau 12 sendok teh untuk kebutuhan '
        '2.000 kalori. Menurunkannya sampai 5% atau kurang bisa memberi manfaat tambahan.',
    source: 'WHO, Healthy diet fact sheet (26 Jan 2026)',
  ),
  JedaFact(
    id: 'who_salt',
    category: 'Makan',
    text: 'Batas garam untuk orang dewasa kurang dari 5 gram per hari, setara sekitar 2 gram natrium. Banyak garam datang '
        'dari bumbu, saus, dan makanan olahan, bukan hanya dari garam di meja.',
    source: 'WHO, Healthy diet fact sheet (26 Jan 2026)',
  ),
  JedaFact(
    id: 'who_hypertension_silent',
    category: 'Tekanan darah',
    text: 'Sebagian besar penderita hipertensi tidak merasakan gejala apa pun. Diperkirakan 44% orang dengan hipertensi '
        'tidak tahu bahwa mereka mengidapnya. Satu-satunya cara tahu adalah mengukur tekanan darah.',
    source: 'WHO, Hypertension fact sheet (25 Sep 2025)',
  ),
  JedaFact(
    id: 'riskesdas_hypertension',
    category: 'Tekanan darah',
    text: 'Pada Riskesdas 2018, 34,1% penduduk Indonesia berusia 18 tahun ke atas terukur memiliki tekanan darah tinggi. '
        'Mengukur tekanan darah di Puskesmas atau di rumah adalah langkah kecil yang berguna.',
    source: 'Kemenkes, Riskesdas 2018 (hasil pengukuran, usia 18 tahun ke atas)',
  ),
  JedaFact(
    id: 'idf_undiagnosed',
    category: 'Gula darah',
    text: 'Di kawasan Asia Tenggara, lebih dari separuh orang dengan diabetes diperkirakan belum terdiagnosis. Cek gula '
        'darah sesekali membantu menangkapnya lebih awal.',
    source: 'International Diabetes Federation, IDF Diabetes Atlas edisi ke-10 (2021)',
  ),
  JedaFact(
    id: 'heart_rate_rest',
    category: 'Jantung',
    text: 'Detak jantung istirahat orang dewasa umumnya 60 sampai 100 kali per menit. Di bawah 60 sering wajar pada orang '
        'yang rutin berolahraga. Kafein, kurang tidur, dan stres bisa menaikkannya sementara.',
    source: 'American Heart Association dan Mayo Clinic (detak jantung istirahat dewasa)',
  ),
  JedaFact(
    id: 'sleep_7h',
    category: 'Tidur',
    text: 'Orang dewasa disarankan tidur 7 jam atau lebih setiap malam untuk menjaga kesehatan. Menutup aplikasi lebih awal '
        'adalah cara termurah menambah jam tidur.',
    source: 'Watson dkk., konsensus American Academy of Sleep Medicine dan Sleep Research Society, 2015',
  ),
  JedaFact(
    id: 'sleep_appetite',
    category: 'Tidur',
    text: 'Pada studi kecil (12 pria muda), dua malam tidur yang dibatasi membuat hormon lapar ghrelin naik 28%, hormon '
        'kenyang leptin turun 18%, dan rasa lapar naik 24%, terutama pada makanan manis dan berkarbohidrat.',
    source: 'Spiegel dkk., Annals of Internal Medicine 2004;141:846-850 (12 pria)',
  ),
  JedaFact(
    id: 'screen_melatonin',
    category: 'Tidur',
    text: 'Studi kecil (12 orang): membaca 4 jam sebelum tidur di perangkat berlayar bercahaya menekan melatonin, membuat '
        'jam biologis bergeser lebih malam, dan membuat lebih lama tertidur dibanding membaca buku cetak.',
    source: 'Chang dkk., PNAS 2015;112:1232-1237 (12 orang)',
  ),
];

/// Kalimat di bawah fakta: ajakan untuk memutuskan dengan sadar, tanpa menceramahi.
const jedaFactPrompt = 'Tarik napas sebentar, lalu putuskan dengan sadar: lanjut buka, atau lakukan satu hal kecil untuk dirimu dulu?';
