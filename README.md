# KIRA

**Kira-kira kesehatanmu 10 tahun lagi seperti apa? Tanya KIRA.**

KIRA adalah teman ngobrol 1 menit sehari yang memproyeksikan risiko diabetes pengguna 10 tahun ke depan, menunjukkan kebiasaan yang paling berdampak, dan tahu kapan pengguna harus memeriksakan diri, lalu belajar dari hasil pemeriksaannya. Hackathon JOINTS 2026, Healthcare subtema 5.

> KIRA bukan alat diagnosis dan tidak memberi saran obat atau dosis. Seluruh data di repo ini adalah data dummy.

Dokumen produk dan teknis: [`docs/konsep_kira.md`](docs/konsep_kira.md), [`docs/rencana_implementasi.md`](docs/rencana_implementasi.md).
Spec dan rencana implementasi Fase 1: [`docs/superpowers/`](docs/superpowers/).

## Alur solusi

```
Check-in (teks / suara / foto)
        │
        ▼
  Ekstraksi AI ──► log makan, minum, tidur, aktivitas
        │
        ▼
  Proyeksi 10 tahun (rentang, bukan satu angka) ──► What-if: dua kurva berdampingan
        │
        ▼
  Rentang lebar / risiko naik ──► "Saatnya cek" (cek apa yang paling berguna + faskes terdekat)
        │
        ▼
  Hasil pemeriksaan masuk ──► proyeksi dikalibrasi ulang ──► diagnosis dokter → mode pengelolaan
```

Prinsip teknis: **angka tidak pernah datang dari LLM.** Risiko, gizi, dan sisa target dihitung fungsi Python deterministik
(`backend/app/core_calc/`); LLM hanya mengekstrak, memutuskan kapan memanggil tool, dan merangkai jawaban. Tanda bahaya
dideteksi oleh aturan sebelum LLM bekerja.

| Lapisan | Teknologi |
|---|---|
| Aplikasi | Flutter (Android sebagai target utama, build web untuk prototype), Riverpod, go_router, fl_chart |
| Backend | FastAPI, SQLAlchemy 2 (async) + Alembic, PostgreSQL 16 |
| Orkestrasi AI | LangGraph (`safety_check → extract → save_logs → build_context → agent ⇄ tools → output_guardrail`) |
| Model | Anthropic Claude (chat, tool calling, vision), STT lewat endpoint kompatibel OpenAI (mis. Groq Whisper) |
| Skor | FINDRISC (diabetes 10 tahun), kategori tekanan darah |

## Menjalankan

Prasyarat: Docker, [uv](https://docs.astral.sh/uv/) (mengelola Python dan dependensi), Flutter 3.47+.

```bash
# 1. Database
docker compose up -d db                       # Postgres di localhost:5455

# 2. Backend (uv: https://docs.astral.sh/uv/)
cd backend
cp ../.env.example ../.env                    # isi ANTHROPIC_API_KEY dan STT_API_KEY
uv sync                                       # membuat .venv dari pyproject.toml + uv.lock
uv run alembic upgrade head
uv run python -m seed.load                    # ~100 makanan lokal + faskes dummy
uv run python -m seed.raka --reset            # persona demo Raka (raka atau 081234567890 / PIN 123456), ulang dari awal
uv run uvicorn app.main:app --port 8000

# 3. Aplikasi
cd ../app
flutter run -d chrome --dart-define=API_URL=http://localhost:8000
# APK: flutter build apk --release --dart-define=API_URL=https://<server-kamu>
# Web: flutter build web --release --dart-define=API_URL=https://<server-kamu>
```

Skrip satu perintah untuk demo lokal (API + web statis, `DEMO_CACHE` aktif): `powershell -File scripts/run_demo_stack.ps1`.

Backend dalam container: `docker compose --profile app up --build`.

### Mode demo (cache)

`DEMO_CACHE=true` melayani kalimat skrip demo dari `backend/seed/demo_cache.json` tanpa memanggil LLM, supaya demo tetap
jalan bila API lambat atau gagal. Cache hanya untuk pitching; kalimat tanda bahaya tidak pernah dilayani dari cache.
Bangun ulang dengan `python -m seed.build_demo_cache` bila skrip demo berubah.

### Variabel lingkungan

| Variabel | Fungsi |
|---|---|
| `DATABASE_URL`, `TEST_DATABASE_URL` | Koneksi Postgres (asyncpg) |
| `JWT_SECRET` | Kunci token login (gunakan string acak ≥ 32 karakter) |
| `ANTHROPIC_API_KEY`, `LLM_MODEL_CHAT`, `LLM_MODEL_EXTRACT` | Model chat/vision dan ekstraksi (Anthropic bila `LLM_BASE_URL` kosong) |
| `LLM_BASE_URL`, `LLM_API_KEY` (atau `9ROUTER_API_KEY`) | Penyedia kompatibel OpenAI menggantikan Anthropic, mis. `https://9router.byhan.id/v1` |
| `LLM_HEDGE_AFTER_SECONDS` | Panggilan model yang belum selesai setelah sekian detik (bawaan 18) didampingi satu salinan, hasil yang lebih dulu dipakai; `0` mematikan |
| `STT_BASE_URL`, `STT_API_KEY`, `STT_MODEL` | Speech-to-text |
| `DEMO_CACHE` | `true` untuk mode demo |
| `CORS_ORIGINS` | Origin yang boleh memanggil API dari browser (pisahkan dengan koma) |
| `ENVIRONMENT` | `production` membuat API menolak jalan dengan `JWT_SECRET` bawaan atau pendek |
| `BOT_SECRET` | Rahasia bersama dengan bot WhatsApp; kosong berarti kanal WhatsApp nonaktif |
| `PUBLIC_BASE_URL` | Alamat publik API, dipakai membentuk tautan ringkasan untuk dokter |
| `SCHEDULER_ENABLED` | `true` menjalankan penjadwal (ringkasan mingguan, pemeriksaan malam, pengingat) di dalam API |

## Pengujian

```bash
cd backend && uv run pytest                       # 260+ tes: angka klinis, graf, API, penjadwal, keluarga, WhatsApp (butuh Postgres)
cd app && flutter test                            # tes widget: chat, onboarding, proyeksi, cek, keluarga, ringkasan dokter, tema
cd wa-bot && npm test                             # logika jembatan WhatsApp (tanpa nomor sungguhan)
cd backend && uv run python -m seed.eval_extraction   # akurasi ekstraksi pada 22 kalimat campur; memanggil model SUNGGUHAN (butuh API key, berbayar)
```

Yang dites otomatis difokuskan pada bagian yang menghasilkan angka dan pada jalur keselamatan: tanda bahaya tidak pernah
sampai ke LLM, `user_id` tidak bisa dipalsukan lewat tool, guardrail menolak saran obat/diagnosis, dan nilai klinis
mustahil ditolak sebelum disimpan.

## Fase 2

- **Hipertensi:** risiko 4 tahun dengan skor Framingham (Parikh 2008), tampil sebagai rentang di layar 10 Tahun bila profil dan tensi tersedia.
- **Keluarga:** undangan, izin per jenis data (status check-in, pengingat cek), bisa dicabut; anggota hanya melihat yang diizinkan.
- **Ringkasan dokter:** `GET /summary/doctor?days=7..90` (teks siap salin) dan `GET /insights/food-glucose` (butuh minimal 3 pasangan data).
- **Penjadwal** (`backend/app/scheduler.py`, jam WIB): ringkasan mingguan Senin 00:10, pemeriksaan "Saatnya cek" 02:00, pengingat check-in 19:00
  (maksimal 1 per hari, hanya bila belum ada catatan), dorongan dukungan ke keluarga 19:30.
- **WhatsApp (prototype):** endpoint tautan dan webhook di backend, jembatan Baileys di [`wa-bot/`](wa-bot/README.md). Tidak resmi; lihat peringatannya.
- **Dokumen submission:** [`docs/submission/`](docs/submission/) (naskah video, pitch deck, proposal, checklist).

## Fase 3

- **Label gizi kemasan:** foto tabel informasi nilai gizi (`POST /chat/photo?kind=label`, atau keterangan "label" di WhatsApp). Angka gula, natrium, lemak,
  dan kalori yang tercetak dibaca model, lalu dihitung per sajian oleh `core_calc/label.py` (nilai mustahil seperti gula melebihi berat sajian ditolak).
  Hasilnya bersumber label, bukan estimasi tim, dan koreksi porsi menskalakan angka itu secara proporsional.
- **Jejak perhitungan:** tiap balasan yang memakai tool menawarkan "Lihat cara KIRA menghitung": tool apa yang dipanggil, angka masuknya, dan sumbernya
  (TKPI atau estimasi). Tool yang belum dikenal tetap tampil dengan nama aslinya.
- **Langkah dan tidur dari Health Connect (Android):** opsional, dinyalakan sendiri oleh pengguna dari Profil. `POST /sync/passive` menerima segmen langkah
  dan sesi tidur; menit aktif dihitung server (`core_calc/steps.py`: kadensi >= 100 langkah/menit, Tudor-Locke dkk. 2019). Sinkron ulang hanya mengganti
  hari yang dikirim; `DELETE /sync/passive` menghapus semua data perangkat. Langkah ganda dari beberapa aplikasi dibuang (hanya sumber terbanyak dipakai).
- **Rekap minggu lalu:** `GET /summary/weekly` (dihitung langsung dari catatan) dan kartu di layar 10 Tahun, dengan perubahan dari minggu sebelumnya.
- **Masuk dengan nama pengguna:** akun baru mendaftar dengan nama pengguna + nomor HP (nomor tetap wajib untuk WhatsApp dan undangan keluarga); masuk memakai nama pengguna ATAU nomor. Nama pengguna 3-20 karakter, diawali huruf (jadi tidak ambigu dengan nomor), tidak membedakan huruf besar/kecil. Batas percobaan masuk dibagi per akun, bukan per ketikan. Akun lama bisa membuatnya dari Profil (`PUT /auth/username`).
- **Tren dan penanda triase:** `GET /insights/trends?days=7..90` menghasilkan deret tensi, gula darah puasa/sewaktu, HbA1c (180 hari), deret harian gula, tidur, dan menit aktif, plus penanda
  (`perhatian`, `pantau`, `info`) dari aturan murni `core_calc/triage.py` terhadap ambang KMK 303/2026 dan PERKENI 2021. Layar "Tren dan penanda" menampilkan grafik dengan garis ambang;
  kata tingkat penanda dan arah tren selalu tertulis, bukan hanya warna, dan tiap grafik punya alternatif teks untuk pembaca layar.
- **PDF untuk dokter:** `GET /summary/doctor.pdf?days=1..90` (reportlab, grafik vektor, 1-3 halaman): penanda, tabel hasil terakhir, grafik tren, kebiasaan harian, skrining, dan sumber. Tombol "Bagikan PDF" di layar
  Ringkasan untuk dokter membuka menu bagikan sistem (mis. WhatsApp). PDF tidak memuat nomor HP.
- Perbaikan build: manifest Android sekarang mendeklarasikan `INTERNET` dan izin lokasi (sebelumnya APK rilis tidak bisa memanggil API).

## Fase 4: akun dan privasi

Rincian dan batasnya ada di [`docs/privasi-dan-keamanan.md`](docs/privasi-dan-keamanan.md).

- **Sesi:** token akses 60 menit + token penyegar 30 hari yang berputar (`POST /auth/refresh`, `/auth/logout`). Aplikasi menukar token diam-diam saat 401 dan mengulang permintaan yang gagal; pengguna tidak terlempar keluar tiap beberapa jam.
- **Persetujuan UU PDP:** kotak centang saat daftar (server menolak tanpa `consent`), dan dialog persetujuan ulang untuk akun lama atau saat teks berubah.
- **Hak pemilik data:** unduh semua data (`GET /account/export`), hapus akun dengan PIN (`POST /account/delete`), riwayat siapa yang membuka ringkasanmu (`GET /account/access-log`). Layar Profil, Data dan privasi.
- **Lupa PIN:** kode 6 angka lewat WhatsApp yang tertaut (`/auth/pin-reset/request`, `/confirm`); ganti PIN saat masuk (`PUT /auth/pin`) mengeluarkan perangkat lain.
- **Tautan untuk dokter:** `POST /summary/share` membuat tautan sementara (1-30 hari, bisa dicabut) ke halaman ringkasan dan PDF tanpa perlu akun; pembukaannya tercatat.

## Fase 5: keterlibatan, klinis, dan platform

- **Model bahasa dari penyedia mana pun:** `LLM_BASE_URL` terisi memakai penyedia kompatibel OpenAI (mis. gerbang 9router, kunci `LLM_API_KEY` atau `9ROUTER_API_KEY`),
  kosong memakai Anthropic. Ekstraksi memakai function calling (didukung hampir semua gerbang). Sudah dicoba nyata dengan `ag/gemini-3.8-flash-high`: chat, tool calling,
  output terstruktur, dan gambar jalan; model penalaran "high" butuh sekitar 10 detik per panggilan, jadi balasan dengan beberapa tool bisa puluhan detik
  (varian `-medium`/`-low` kira-kira dua kali lebih cepat). Balasan yang melanggar guardrail ditulis ulang sekali sebelum diganti kalimat baku.
- **Menutup lingkaran "Saatnya cek":** setelah 3 hari KIRA bertanya "sudah dicek?" (Sudah / Nanti / Tidak perlu), di aplikasi dan sekali-dua kali lewat WhatsApp.
- **Antrean offline:** pesan teks dan hasil cek tanpa sinyal tersimpan terenkripsi di ponsel dan dikirim otomatis dengan `Idempotency-Key` (tidak tercatat dua kali). Selalu disertai pengingat 119/IGD.
- **Pengingat lokal (opt-in):** check-in harian, rekap mingguan, tanya "sudah dicek?". Isi notifikasi tidak memuat data kesehatan; check-in dilewati bila hari itu sudah mencatat.
- **Pindai kode batang** (`GET /products/{kode}`, `POST /logs/barcode`): gizi dari Open Food Facts dengan sumber ditampilkan, di-cache, dan divalidasi seperti foto label; fallback ketik nomor dan foto label.
- **Makanan yang sering dicatat:** chip sekali ketuk di chat (`GET /logs/frequent`).
- **Tensi di rumah 7 hari** (`/bp-protocol`): protokol ESH 2021, rata-rata tanpa hari pertama menjadi satu hasil cek dan memengaruhi proyeksi, penanda, dan ringkasan dokter.
- **Pola tidur** (`/insights/patterns`), **riwayat skor FINDRISC** (`/insights/risk-history`), **skenario what-if tersimpan** (`/projection/scenarios`), dan **buka tempat cek di peta**.
- **Platform:** batas pesan per pengguna (20/menit, 400/hari), `X-Request-ID` + log per permintaan, `GET /health/ready`, CI GitHub Actions,
  `docker-compose.prod.yml` + Caddy (HTTPS otomatis), skrip cadangan/pemulihan. Lihat [`docs/deploy.md`](docs/deploy.md) (belum pernah dijalankan di server sungguhan).

## Batasan yang disengaja

- Proyeksi 10 tahun untuk diabetes memakai FINDRISC; hipertensi memakai Framingham 4 tahun dan hanya untuk usia dan kondisi yang memenuhi syarat kelayakannya.
- Health Connect belum diuji di perangkat sungguhan (logikanya dites dengan sumber palsu; build APK berhasil). Satu ponsel berarti satu sumber utama; tidur terputus-putus dihitung per sesi.
- Koneksi WhatsApp sungguhan belum diuji (butuh nomor khusus dan pemindaian QR); logikanya dites otomatis.
- Integrasi SATUSEHAT belum diimplementasikan (roadmap).
- Pengguna sungguhan di produksi memerlukan WhatsApp Business Platform resmi, OTP asli, dan persetujuan data sesuai UU PDP.

## Sumber angka klinis

Semua konstanta klinis ada di [`backend/app/core_calc/constants.py`](backend/app/core_calc/constants.py), masing-masing dengan sumber dan
status verifikasinya. Rincian, tautan, dan **daftar yang belum bersumber** (gula makanan, porsi khas, dan sebagian natrium
adalah estimasi KIRA karena TKPI tidak memuatnya) ada di [`docs/sumber-angka-klinis.md`](docs/sumber-angka-klinis.md).

Ringkasnya: poin dan kategori FINDRISC, ambang tekanan darah (KMK 303/2026), kriteria glukosa (PERKENI 2021), dan batas
harian gula/garam/lemak (Permenkes 30/2013) dibaca dari sumber resmi. Persentase insidensi 10 tahun per kategori berasal dari
estimasi resmi formulir FINDRISC (kohort Finlandia); studi modern menemukan angka lebih rendah sehingga aplikasi
mengungkapkannya, dan interpolasi antar kategori adalah asumsi KIRA.

## Arah visual

Standar kategori aplikasi kesehatan yang dieksekusi penuh, bernuansa Material 3: [`docs/superpowers/design/kira-visual-direction.md`](docs/superpowers/design/kira-visual-direction.md).
