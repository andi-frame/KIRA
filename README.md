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
uv run python -m seed.raka --reset            # persona demo Raka (081234567890 / PIN 123456), ulang dari awal
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
| `ANTHROPIC_API_KEY`, `LLM_MODEL_CHAT`, `LLM_MODEL_EXTRACT` | Model chat/vision dan ekstraksi |
| `STT_BASE_URL`, `STT_API_KEY`, `STT_MODEL` | Speech-to-text |
| `DEMO_CACHE` | `true` untuk mode demo |
| `CORS_ORIGINS` | Origin yang boleh memanggil API dari browser (pisahkan dengan koma) |

## Pengujian

```bash
cd backend && uv run pytest                       # 190+ tes: angka klinis, graf, API (butuh Postgres)
cd app && flutter test                            # tes widget: chat, onboarding, proyeksi, cek, tema (kontras WCAG)
```

Yang dites otomatis difokuskan pada bagian yang menghasilkan angka dan pada jalur keselamatan: tanda bahaya tidak pernah
sampai ke LLM, `user_id` tidak bisa dipalsukan lewat tool, guardrail menolak saran obat/diagnosis, dan nilai klinis
mustahil ditolak sebelum disimpan.

## Batasan yang disengaja (Fase 1)

- Proyeksi 10 tahun hanya untuk **diabetes** (FINDRISC). Hipertensi hanya sampai kategori tekanan darah dari hasil ukur;
  skor Framingham masuk Fase 2.
- WhatsApp (Baileys), fitur keluarga, scheduler, dan SATUSEHAT belum ada.
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
