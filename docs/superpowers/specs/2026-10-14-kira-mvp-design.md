# KIRA — Spec Desain MVP Fase 1

Tanggal: 2026-10-14 · Batas pengumpulan: 2026-10-16 23.50 WIB
Sumber desain: `docs/konsep_kira.md` dan `docs/rencana_implementasi.md`. Spec ini hanya mengunci keputusan yang di dokumen itu masih terbuka dan menetapkan cakupan Fase 1. Jika ada konflik, spec ini yang berlaku.

## 1. Tujuan dan kriteria sukses

Prototype yang menjalankan alur demo Raka dari awal sampai akhir: onboarding → check-in (teks/suara/foto) → proyeksi diabetes 10 tahun dengan what-if → rekomendasi cek → input hasil cek → proyeksi terkalibrasi → mode pengelolaan.

Sukses berarti:
- Alur demo berjalan 5 kali berturut-turut dari satu perangkat dengan data persona Raka.
- Setiap angka di layar (risiko, gizi, sisa target) berasal dari fungsi Python deterministik, bukan teks LLM.
- Pesan dengan tanda bahaya selalu mendapat balasan darurat tanpa memanggil LLM.
- Tersedia link prototype (Flutter web) dan, bila Android SDK siap, APK.

Bukan tujuan Fase 1: WhatsApp, fitur keluarga, Framingham, scheduler, notifikasi push, SATUSEHAT.

## 2. Keputusan yang dikunci

| Topik | Keputusan |
|---|---|
| Frontend | Flutter. Prioritas build web (link prototype), APK menyusul bila Android SDK siap. SDK Flutter dipasang di sesi ini. |
| Kurva 10 tahun | Skor FINDRISC → perkiraan insidensi diabetes 10 tahun per kategori skor → risiko kumulatif tahun 0–10 dengan hazard konstan: `R(t) = 1 − (1 − p10)^(t/10)`. Input yang tidak diketahui menghasilkan pita (rentang skor → rentang p10). |
| Hipertensi | Fase 1 hanya kategori tensi dari hasil ukur + aturan "tensi belum pernah diukur → rekomendasi cek tensi". Tidak ada proyeksi 10 tahun hipertensi. Framingham masuk Fase 2 setelah koefisien diverifikasi dari paper. |
| WhatsApp | Ditunda ke Fase 2. Adegan diskusi di demo memakai chat di app dengan graf yang sama. |
| LLM | Anthropic Claude untuk chat, tool calling, dan vision. STT dari layanan terpisah di balik antarmuka `SttService`. |
| Minuman manis dan tidur | Tidak ada di FINDRISC. Ditampilkan sebagai gula harian vs target dan kebiasaan tidur, bukan sebagai angka risiko. |

## 3. Arsitektur

Monorepo:

```text
KIRA/
├── README.md
├── docker-compose.yml        # postgres (+ backend untuk dev)
├── backend/                  # FastAPI
│   ├── app/{main.py, api/, models/, schemas/, db.py, config.py}
│   ├── app/core_calc/        # modul angka murni, tanpa I/O dan tanpa LLM
│   ├── app/tools/            # pembungkus @tool tipis di atas core_calc + repo
│   ├── app/graph/            # KiraState, kira_graph.py, nodes/
│   ├── app/services/         # llm.py, stt.py, vision.py, summarizer.py
│   ├── alembic/  seed/  tests/
└── app/                      # Flutter
```

Perubahan dari dokumen asli: logika angka dipisah ke `core_calc/` (fungsi murni) dan `tools/` hanya membungkusnya untuk LLM. Alasannya, tes angka tidak perlu database atau LangChain, dan endpoint `/projection` memakai fungsi yang sama dengan tool `hitung_risiko`.

### 3.1 Unit dan antarmuka

| Unit | Tugas | Bergantung pada |
|---|---|---|
| `core_calc.findrisc` | Poin per faktor, `score_range(known)`, kategori, peta skor → p10 | tidak ada |
| `core_calc.projection` | Kurva kumulatif dan pita dari rentang skor | `findrisc` |
| `core_calc.whatif` | Hitung ulang skor untuk perubahan aktivitas, sayur/buah, berat badan; dampak gula harian untuk minuman manis | `findrisc` |
| `core_calc.bp` | Kategori tensi dari sys/dia | tidak ada |
| `core_calc.targets` | Sisa target gula/natrium/lemak dari log hari ini | tidak ada |
| `core_calc.nutrition` | Pencocokan makanan + agregasi gizi per porsi | tabel `foods` lewat repo |
| `core_calc.red_flags` | Deteksi tanda bahaya berbasis aturan | tidak ada |
| `core_calc.check_trigger` | Kapan dan cek apa yang disarankan (§5) | `findrisc`, `bp` |
| `services.llm` | Antarmuka `ChatModel` (Claude), mode cache untuk demo, `FakeChatModel` untuk tes | SDK penyedia |
| `graph.*` | Delapan node dan `run_kira_graph()` | semua di atas |
| `api.*` | Router HTTP; hanya memanggil repo, `core_calc`, atau `run_kira_graph` | |

Aturan keras: `user_id` tidak pernah menjadi argumen yang diisi LLM; disuntikkan ke tool dari state graf. Semua query difilter per `user_id`.

## 4. Data dan API Fase 1

Skema database mengikuti `rencana_implementasi.md`, kecuali tabel `family_links` (Fase 2) tidak dibuat. Urutan migrasi: `foods` sebelum `log_items`. Endpoint yang dibuat: `/auth/register`, `/auth/login`, `/profile`, `/chat/message`, `/chat/voice`, `/chat/photo`, `/logs`, `/targets/today`, `/projection`, `/projection/whatif`, `/recommendations/check`, `/results`, `/faskes/nearby`, `/diagnoses`. Tidak dibuat: `/family/*`, `/webhooks/whatsapp`.

Seed: sekitar 100 makanan lokal populer (nasi padang, gorengan, es teh, kopi susu gula aren, dan sejenisnya), 5–10 faskes dummy, dan persona Raka dengan data 3 minggu.

## 5. Proyeksi, ketidakpastian, dan pemicu cek

- Input FINDRISC yang belum diketahui (lingkar perut, aktivitas, sayur/buah, gula darah tinggi) dihitung untuk semua kemungkinan kategorinya, lalu diambil skor minimum dan maksimum.
- Aktivitas dan sayur/buah diturunkan dari log 14 hari terakhir; hasil cek gula darah tinggi mengisi faktor "pernah gula darah tinggi" dengan pasti.
- Pemicu cek: (a) rentang melintasi batas kategori, (b) batas atas masuk kategori tinggi, (c) tren kebiasaan 2 minggu memburuk, (d) tensi belum pernah diukur.
- Jenis cek yang disarankan adalah input yang paling mempersempit rentang (cek gula darah bila rentang lebar karena gula darah belum diketahui).
- Kalibrasi: hasil cek disimpan, `hitung_risiko` dijalankan ulang, `risk_snapshots` bertambah. Diagnosis terkonfirmasi mengubah `users.mode` menjadi `management`.

## 6. Graf LangGraph

Delapan node sesuai dokumen: `extract → safety_check → (emergency_reply | save_logs → build_context → agent ⇄ tools → output_guardrail)`. `safety_check` memakai `core_calc.red_flags` dan berjalan sebelum LLM utama. `output_guardrail` menolak balasan yang menyebut obat/dosis atau klaim diagnosis, lalu menggantinya dengan balasan aman. Batas putaran agent–tools: `recursion_limit=12`. Versi LangGraph dikunci di `requirements.txt` dan impor dicocokkan dengan dokumentasi versi terpasang.

## 7. Aplikasi Flutter

Layar utama dengan bilah bawah 4 tujuan: Ngobrol (chat teks, rekam suara, kamera, kartu ekstraksi), Beranda (ringkasan target harian, kartu aksi, dan proyeksi Kira-kira 10 Tahun dengan kurva + pita), Riwayat (riwayat makanan dan kebiasaan 14 hari), dan Cek (alasan, jenis cek, daftar faskes terdekat, tombol masukkan hasil). Profil diakses dari avatar bilah atas. Paket: riverpod, dio, go_router, record, image_picker, fl_chart, flutter_secure_storage.

Arah visual: tenang, native, palet Discord dark gray (`#313338`) dengan aksen hijau KIRA dan kuning hangat untuk perhatian, menghindari *cognitive overload* dan template kaku. Detail visual mutakhir dikunci dan didokumentasikan di `docs/superpowers/design/kira-visual-direction.md`.

## 8. Keamanan dan privasi

Bahasa produk "proyeksi risiko" dan "saran gaya hidup", tidak pernah "kamu aman" atau "kamu menderita". Tidak ada saran obat atau dosis. Foto diproses lalu dibuang, hanya hasil ekstraksi yang disimpan. PIN di-hash (argon2/bcrypt), JWT berumur pendek, HTTPS, secret hanya di env. Semua data demo dummy. Halaman "bagaimana angka ini dihitung" menyebut skor dan asumsi yang dipakai.

## 9. Data klinis yang wajib diverifikasi manusia

Saya tidak mengisi angka berikut dari ingatan. Di kode semuanya konstanta bersumber yang diberi komentar `TODO-VERIFY` beserta nama sumber yang diharapkan, dan harus dicocokkan sebelum dipakai di pitch:

1. Tabel poin FINDRISC dan varian cut-off Asia (IMT dan lingkar perut).
2. Peta kategori skor FINDRISC → insidensi diabetes 10 tahun.
3. Ambang kategori tekanan darah (Kemenkes/CKG).
4. Ambang tanda bahaya (tensi dan gula darah sangat tinggi/rendah, gejala).
5. Batas harian gula, garam, lemak (Kemenkes).
6. Nilai gizi 100 g pada seed makanan (Tabel Komposisi Pangan Indonesia).

Untuk development, nilai sementara dipakai agar alur bisa jalan; angka sementara tidak boleh tampil di materi submission tanpa verifikasi.

## 10. Pengujian

- pytest otomatis untuk `findrisc`, `projection`, `whatif`, `bp`, `nutrition` (makanan tak dikenal → `found: false`), `targets`, `red_flags`, `check_trigger`, dan `output_guardrail`. Dibangun test-first.
- Tes graf dengan `FakeChatModel`: tanda bahaya tidak pernah memanggil LLM; `user_id` tidak bisa dipalsukan lewat argumen tool; loop berhenti di batas rekursi.
- Tes API untuk alur utama dengan Postgres uji.
- Uji manual: 20 kalimat check-in bahasa campur, foto makanan/struk nyata, skrip demo penuh 5 kali.
- UI: pemeriksaan visual dan alur klik dengan Playwright pada Flutter web.

## 11. Urutan kerja dan pemotongan

1. Pasang Flutter dan Android SDK, scaffold monorepo, `docker-compose` Postgres.
2. `core_calc` + tes.
3. Skema, migrasi, seed.
4. Graf dan endpoint.
5. Layar Flutter.
6. Seed persona Raka, uji end-to-end, `graphify` pada kode.
7. README, video, deck.

Bila waktu kurang, potong berurutan: foto struk, input suara, peta faskes (jadi daftar statis). Tidak boleh dipotong: chat teks + ekstraksi, layar Kira-kira 10 Tahun, rekomendasi "saatnya cek", input hasil + kalibrasi.

## 12. Risiko

| Risiko | Mitigasi |
|---|---|
| Setup Flutter/Android SDK memakan waktu | Build web dulu; APK terakhir |
| LLM lambat/gagal saat demo | Mode cache untuk input demo, video rekaman layar |
| Ekstraksi foto meleset | Kartu ekstraksi bisa dikoreksi; foto demo diuji dulu |
| Angka klinis sementara terbawa ke materi | Daftar §9 dicek sebelum deck dan video final |
| Pergeseran API LangGraph | Versi dikunci, impor dicocokkan dengan dokumentasi terpasang |
