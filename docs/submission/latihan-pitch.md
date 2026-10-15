# Latihan pitching dan tanya jawab

Pelengkap `docs/konsep_kira.md` (bagian Antisipasi pertanyaan juri). Jawaban di sini disesuaikan dengan **yang benar-benar ada di kode** per 15 Oktober 2026, termasuk kelemahan yang pasti ditanyakan juri yang teliti. Jangan klaim lebih dari ini.

## Menyiapkan demo

```powershell
cd app; flutter build web --release --dart-define=API_URL=http://localhost:8000
powershell -File scripts\run_demo_stack.ps1     # Postgres, API (DEMO_CACHE=true), web di :8080; Raka di-reset
```

- Login Raka: `raka` (atau `081234567890`) / PIN `123456` (data dummy, 3 minggu catatan).
- `DEMO_CACHE=true` melayani dua kalimat skrip demo tanpa memanggil LLM. Kalimat lain tetap memanggil model (butuh `ANTHROPIC_API_KEY`); tanda bahaya tidak pernah dari cache.
- Ulang demo dari awal: `cd backend; uv run python -m seed.raka --reset`.
- Cadangan: rekaman layar penuh di HP, hotspot dari HP lain, nomor WhatsApp cadangan atau tunjukkan alur yang sama di aplikasi.
- Latih minimal 5 kali dari HP yang dipakai di panggung, termasuk dengan sinyal lemah.

## Urutan demo 4 menit (lihat tabel lengkap di konsep)

1. Check-in: "Tadi siang nasi padang rendang, es teh manis, terus begadang sampai jam 2." → kartu "Yang kucatat".
2. Kira-kira 10 Tahun: geser slider minuman manis dan aktivitas; tunjuk "kebiasaan paling berdampak".
3. Tanya porsi: "Nanti malam mau makan rendang lagi, boleh berapa?"
4. Saatnya cek → faskes terdekat.
5. Masukkan hasil gula darah puasa → rentang menyempit.
6. Tandai diagnosis → mode pengelolaan. Opsional: Profil → Ringkasan untuk dokter, Keluarga.

## Untuk dokter dan juri klinis

- Layar **Tren dan penanda** (Profil atau tab Cek): grafik tensi, gula darah puasa/sewaktu, dan HbA1c dengan garis ambang, plus kebiasaan harian. Penanda "Perlu perhatian" dan "Pantau" adalah aturan terhadap ambang pedoman, bukan diagnosis.
- **Ringkasan untuk dokter, Bagikan PDF:** PDF 1-3 halaman berisi penanda, tabel hasil terakhir, grafik, dan sumber; dibagikan lewat WhatsApp atau surel.

## Pertanyaan yang pasti muncul, dan jawaban jujur

| Pertanyaan | Jawaban |
|---|---|
| Angka risiko 10 tahun itu dari mana? | FINDRISC (Lindström & Tuomilehto 2003). Insidensi 10 tahun per kategori (1, 4, 17, 33, 50%) dikutip dari formulir resmi; kami ambil lewat sumber sekunder. Di antara kategori, kami interpolasi linear supaya perubahan kebiasaan terlihat. Interpolasi itu asumsi kami dan diungkapkan di aplikasi ("Bagaimana angka ini dihitung?"). |
| Apakah sudah divalidasi di Indonesia? | Belum oleh kami. Studi FINDRISC Indonesia (PLoS ONE 2022) menunjukkan AUC 0,73 dengan cut-off asli, jadi kami memakai cut-off asli. Kohort modern (HUNT3 Norwegia) menemukan insidensi lebih rendah untuk skor tinggi; itu kami tampilkan sebagai catatan kepada pengguna, bukan disembunyikan. |
| Kenapa rentang, bukan angka? | Data self-report tidak akurat. Skor dihitung sebagai skor bawah dan atas; rentang menyempit setelah ada hasil cek nyata. |
| Apakah akurasi ekstraksinya sudah diukur? | Belum dengan model sungguhan. Skripnya ada (`seed/eval_extraction.py`, 22 kalimat campuran) dan akan dijalankan dengan API key; kami tidak mengklaim angka akurasi sebelum itu. Kartu "Yang kucatat" bisa dikoreksi pengguna. |
| Data gizi dari mana? | 38 makanan dari TKPI 2017 dengan kode pangan. TKPI tidak memuat gula, jadi nilai gula adalah estimasi kami dan ditandai; sekitar 60 makanan lain (boba, nasi goreng, dsb.) estimasi penuh. Tool `cari_gizi` mengembalikan field sumber. |
| Bagaimana kalau LLM mengarang angka? | Angka tidak lewat LLM: risiko, gizi, dan sisa target dari fungsi Python bertes. Makanan yang tidak dikenal menghasilkan "tidak ditemukan", bukan angka karangan. Guardrail menolak balasan yang menyebut obat atau dosis. |
| Bagaimana tanda bahaya ditangani? | Aturan, bukan LLM, dan dijalankan sebelum LLM. Nilai dari foto juga dicek ulang. Bacaan ekstrem tidak disimpan sebagai data rutin. |
| Kenapa hipertensi tidak ikut proyeksi 10 tahun? | Framingham (Parikh 2008) memprediksi 4 tahun dan punya batas kelayakan usia. Kami menampilkannya sebagai kartu terpisah dengan rentang, dan menolak menampilkan angka di luar populasi modelnya. |
| WhatsApp-nya aman? | Tidak untuk produksi. Baileys meniru WhatsApp Web (risiko blokir nomor dan pelanggaran ketentuan layanan). Di sini hanya prototype dengan data dummy; produksi wajib WhatsApp Business Platform resmi. Koneksi sungguhannya belum kami uji; logikanya dites otomatis. |
| UU PDP? | Belum dipenuhi penuh (persetujuan, hak subjek data, retensi). Itu ada di roadmap; prototype memakai data dummy. |
| SATUSEHAT? | Belum diimplementasikan; roadmap. |
| Sudah ada pengguna? | Belum ada uji pengguna. Metrik di deck adalah target yang akan diukur. |
| Apakah "penanda" itu diagnosis? | Bukan. Aturan sederhana membandingkan pembacaan terakhir dengan ambang KMK 303/2026 dan PERKENI 2021, dan setiap penanda menyatakan satu pembacaan tidak cukup untuk diagnosis. Dokter yang menilai. |
| Fitur keluarga tidak invasif? | Atas undangan, izin per jenis data (status check-in, pengingat cek), bisa dicabut kapan saja; keluarga tidak pernah melihat detail makanan, hasil lab, atau skor risiko; nadanya mengajak mendukung. |
| Korelasi makanan dan gula darah itu klaim kausal? | Bukan. Hanya muncul bila ada minimal 3 pasangan data dari catatan pengguna sendiri, dengan penegasan bahwa itu pola, bukan sebab pasti. |
| Siapa yang membayar? | Rencana: freemium individu, wellness kantor (B2B), kemitraan Dinkes/Puskesmas (B2G). Belum diuji pasar. |
| Angka masalahnya dari mana? | SKI 2023 (11,7% pemeriksaan vs 2,2% diagnosis dokter, usia ≥15 tahun); BMJ Open 2025 (tingkat diagnosis hipertensi 26,9%); Kemenkes 4 Agustus 2026 (sekitar 1 juta hipertensi baru di CKG 2026). Angka 98,4% sengaja tidak dipakai karena berasal dari Riskesdas 2018 lewat ulasan sekunder. |

## Batas yang tidak boleh dilanggar saat menjawab

- Jangan menyebut KIRA mendiagnosis, memprediksi "pasti", atau memberi saran obat.
- Jangan menyebut angka akurasi, jumlah pengguna, atau hasil uji yang belum ada.
- Jangan menyebut WhatsApp sebagai kanal produksi atau menyebut kepatuhan UU PDP sebagai sudah selesai.
