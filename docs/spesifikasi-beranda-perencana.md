# Spesifikasi: makanan per komponen, riwayat makan, Beranda hidup, dan perencana harian/mingguan

Status: **belum diimplementasikan**. Dokumen ini ditulis supaya agent lain bisa melanjutkan tanpa konteks percakapan sebelumnya.
Cabang kerja: `feat/dashboard-planner` (dibuat dari `main` setelah merge `78fc9db`; belum ada commit selain dokumen ini).

## 0. Cara bekerja di repo ini (WAJIB dibaca)

- **Stack:** `backend/` FastAPI + SQLAlchemy 2 async + Alembic + PostgreSQL 16, LangGraph/LangChain; `app/` Flutter 3.47 (Riverpod 3, go_router, Dio, fl_chart);
  `wa-bot/` Node (Baileys, prototype). Windows, Git Bash + PowerShell.
- **Perintah:**
  - Backend: `cd backend && uv run pytest -q` (butuh Docker `kira-db-1` menyala; port 5455). **Jangan jalankan dua pytest bersamaan**: basis data uji sama, hasilnya saling menghapus.
  - Migrasi dev: `uv run alembic upgrade head`. Seed: `uv run python -m seed.load` dan `uv run python -m seed.raka --reset`.
  - Flutter: `C:\src\flutter\bin\flutter.bat analyze` dan `... test` (di folder `app`). Web: `flutter build web --release --dart-define=API_URL=http://localhost:8000` (sekitar 90 dtk).
  - Server dev: `SCHEDULER_ENABLED=false uv run uvicorn app.main:app --port 8000`; web statis `python -m http.server 8080 --directory app/build/web`.
- **Git:** commit modular, **tanpa trailer `Co-Authored-By` atau atribusi Claude** (aturan pengguna). Setelah tes lulus: commit per modul, merge `--no-ff` ke `main`, push (instruksi tetap pengguna). Satu baris subjek.
- **Aturan produk:**
  - Angka (gizi, risiko, target, kebutuhan energi) **tidak pernah dari LLM**; hanya dari fungsi murni di `backend/app/core_calc/` yang dites dan bersumber. LLM hanya membaca bahasa dan merangkai kalimat.
  - Tidak boleh ada kata "aman" sebagai klaim kesehatan di UI maupun balasan (guardrail menolak `aman`, `amanmu`, `amannya`), tidak ada diagnosis, tidak ada saran obat.
  - Semua angka klinis baru harus bersumber kredibel dan dicatat di `docs/sumber-angka-klinis.md` (status Primer/Sekunder/Asumsi KIRA). Asumsi tim ditulis sebagai asumsi.
  - Nada UI bahasa Indonesia, tenang, tanpa menghukum. Kemajuan ditulis dengan kata, bukan hanya warna.
  - Isi notifikasi tidak boleh memuat data kesehatan (layar kunci).
- **Jebakan yang sudah pernah terjadi:**
  - Heredoc Bash dengan kutip rumit sering gagal: pakai alat Write/Edit, atau tulis skrip Python ke berkas lalu jalankan.
  - Web (dart2js): `1 << 32` bernilai 0. Jangan pakai operasi bit 32+ atau `Random.nextInt(1 << 32)`; tes Flutter berjalan di VM dan tidak menangkap ini.
  - Playwright pada Flutter web: klik placeholder `flt-semantics-placeholder` dulu; klik tombol dengan JS `.click()` pada node `flt-semantics` (klik mouse sering tidak mengenai); deep link saat reload dialihkan ke `/chat`, jadi ubah `location.hash` setelah halaman muat; naikkan tinggi viewport untuk layar panjang.
  - Gerbang 9router wajib dikirimi header `User-Agent` (tanpa itu jawaban kosong). Tidak ada endpoint embeddings di 9router.
  - Pytest memakai tabel nyata: tabel baru yang menyimpan cache global (seperti `products`) harus ikut di-`truncate` pada `tests/conftest.py`.
  - Model "high" Gemini lambat (sekitar 10 dtk per panggilan). Jumlah panggilan tool per pesan harus dijaga kecil.
- **Dokumentasi yang wajib diperbarui tiap fase:** `README.md` (bagian Fase), `docs/sumber-angka-klinis.md`, `docs/privasi-dan-keamanan.md` bila ada data/pihak baru,
  `docs/screenshots/` (lihat 7.3), dan checklist submission bila relevan.
- **Screenshot:** `docs/screenshots` hanya berisi tangkapan terbaru yang cocok dengan kode. Ubah UI berarti ambil ulang yang terdampak, hapus yang usang, perbarui `docs/screenshots/README.md`, dan cetak ulang PDF deck/proposal bila gambar itu dipakai (`chrome --headless=new --print-to-pdf`, lihat `docs/submission/checklist.md`).

## 1. Permintaan pengguna (kata-katanya)

1. Pencatatan makanan harus bisa memecah satu porsi menjadi komponen: "satu porsi ayam geprek = ayam goreng + nasi + timun", masing-masing dihitung kandungan gizinya, supaya perkiraan kondisi tubuh dan penyakit yang mungkin lebih akurat. Ini dikerjakan lewat pencocokan makanan yang lebih pintar (RAG/semantik).
2. Aplikasi harus menampilkan **riwayat** apa saja yang dimakan beserta gizinya, dengan tampilan yang baik.
3. Tab "10 Tahun" terasa sekali pakai. Ubah menjadi **dashboard yang terus diperbarui** dari kondisi harian pengguna. Bukan hanya makanan: **olahraga dan waktu tidur** juga. Tujuannya memakai data pengguna sebanyak mungkin untuk memperkirakan kebiasaan harian dan potensi bahaya kesehatan, lalu memberi saran kegiatan yang sesuai kondisi tubuh dan target pengguna.
4. **Perencana/penjadwal**: pengingat apa yang harus dimakan, olahraga apa, tidur berapa jam hari itu, dan/atau usulan jadwal hidup sepanjang minggu. Terintegrasi dengan WhatsApp.

## 2. Keputusan dan temuan riset (jangan diulang, sudah diuji)

- **9router tidak punya embeddings** (`/v1/embeddings` ditolak untuk semua model). Chat, tool calling, output terstruktur lewat function calling, dan gambar jalan; `response_format=json_schema` gagal.
- **Embedding saraf murni tidak cocok untuk makanan.** Probe `paraphrase-multilingual-MiniLM-L12-v2` (fastembed, ONNX, memuat 48 dtk, unduh sekitar 220 MB) pada 26 makanan:
  "ayam geprek" paling mirip "bubur ayam" (0,92) dan "soto ayam", bukan "ayam goreng"; "nasi uduk" paling mirip "sambal"; "mi ayam" paling mirip "soto ayam".
  Untuk tabel gizi, salah cocok lebih buruk daripada tidak cocok. **Jangan memakai embedding saraf sebagai penentu**.
- **Rancangan yang dipilih (hibrida, abstain bila ragu):**
  1. **Resep hidangan terkurasi** (tabel `dishes`): hidangan umum dipecah deterministik menjadi komponen berbobot gram.
  2. **Katalog-dalam-konteks**: ekstraksi LLM menerima katalog ringkas `id|nama` (makanan + hidangan) dan wajib memetakan ke `food_id`/`dish_id` bila ada, atau memecah hidangan tak dikenal menjadi komponen sederhana (`components`) dengan perkiraan gram. LLM **tidak** mengisi angka gizi.
  3. **Validasi server**: id yang tidak ada di katalog dibuang; nama tanpa id dicocokkan dengan `match_food` yang ada, lalu indeks n-gram karakter (3.3), lalu **abstain** (catatan "belum ada di database gizi", tidak menebak).
  4. Semua angka gizi tetap dari tabel `foods` (TKPI Kemenkes 2017 / USDA / estimasi bertanda).
- **Sumber data baru:** USDA FoodData Central (domain publik) untuk bahan generik mentah (timun, tomat, kol, selada, dst.) karena memuat gula dan natrium, yang tidak ada di TKPI. API: `https://api.nal.usda.gov/fdc/v1/foods/search?query=...&dataType=SR%20Legacy&pageSize=1&api_key=DEMO_KEY`
  (DEMO_KEY dibatasi sekitar 30 permintaan/jam per IP; ambil sekali, simpan ke JSON, jangan memanggil saat runtime). TKPI tetap sumber utama bila ada padanan.
  Nilai yang tidak ada padanannya ditandai "Estimasi KIRA" di `source_note`, seperti seed yang sudah ada.

## 3. Fase 1: makanan per komponen dan pencocokan

### 3.1 Keadaan sekarang (rujukan kode)
- Seed: `backend/seed/foods.json` (kolom `id,name,aliases,sugar_g,sodium_mg,fat_g,kcal,carb_g,default_portion_g`; 107 baris, kebanyakan hidangan jadi, bukan bahan) dan `seed/tkpi_2017.json` (38 padanan TKPI yang menimpa energi/lemak/karbohidrat/natrium). Pemuat: `seed/load.py` (`_food_rows`, `load_seed`).
- Model: `app/models/logs.py` (`Food`, `Log`, `LogItem` dengan `food_id, name, portion_g, sugar_g, sodium_mg, fat_g, kcal`).
- Pencocokan: `app/core_calc/nutrition.py` (`FoodRecord`, `match_food`, `nutrition_for`), repo `app/repos/foods.py`, item: `app/services/nutrition_items.py` (`item_data`).
- Ekstraksi: `app/schemas/extraction.py` (`FoodItem{name,portion_text,portion_g_guess,meal_time}`), `app/services/extraction.py` (prompt), simpan: `app/graph/nodes/save_logs.py`.
- Tool LLM: `app/tools/nutrition.py` (`cari_gizi`). Prompt agent: `app/graph/prompts.py`. Konteks: `app/graph/nodes/build_context.py`.
- Koreksi porsi: `app/api/logs.py` (`PATCH /logs/{id}`), Flutter `chat_controller.correctPortion`.

### 3.2 Data baru
- `seed/components.json`: sekitar 40-60 bahan/komponen sederhana (mis. timun, tomat, kol, selada, kemangi, daun singkong, ayam goreng tepung, lele goreng, nila goreng, tahu putih, tempe mentah, telur ayam, sambal terasi, sambal bawang, kecap manis, santan, gula pasir, minyak goreng, nasi merah, bihun, mi basah, kerupuk udang, emping, dst.).
  Format baris sama dengan `foods.json` ditambah `source` (`TKPI:APxxx` | `USDA:fdcId` | `ESTIMASI`). Skrip pengambil: `seed/fetch_usda.py` (sekali jalan, hasil dikomit; tidak dipanggil saat runtime/tes).
- `seed/dishes.json`: resep hidangan. Skema:
  ```json
  {"id": "ayam_geprek", "name": "Ayam geprek", "aliases": ["ayam geprek", "geprek"],
   "serving_g": 305, "meal_kinds": ["lunch","dinner"],
   "components": [{"food_id": "ayam_goreng_tepung", "grams": 100, "label": "ayam goreng tepung"},
                  {"food_id": "nasi_putih", "grams": 150}, {"food_id": "timun", "grams": 30}, {"food_id": "sambal_bawang", "grams": 25}],
   "source_note": "Resep rumahan umum; gram per komponen adalah perkiraan KIRA"}
  ```
  Minimal 25 hidangan umum: ayam geprek, ayam penyet, ayam bakar+nasi+lalapan, pecel lele, nasi campur, nasi padang (nasi+rendang+sayur+sambal), nasi uduk lengkap, nasi goreng telur, soto ayam+nasi, mie ayam bakso, gado-gado+lontong, nasi kuning lengkap, bubur ayam lengkap, sarapan roti telur, dst.
  Bobot gram = **asumsi KIRA** dan harus tertulis begitu di `docs/sumber-angka-klinis.md`.
- Migrasi Alembic baru (satu berkas): tabel `dishes` (`id text pk, name, aliases text[], serving_g float, meal_kinds text[], components jsonb, source_note`), kolom `log_items.group_name text null` (nama hidangan induk), kolom `log_items.role text null` (opsional: `staple|protein|veg|sauce|drink|other`), dan indeks yang diperlukan. Isi `dishes` oleh `seed/load.py` (idempoten, `on_conflict_do_update`). Tambahkan `dishes` ke `truncate` di `tests/conftest.py` bila perlu.

### 3.3 Kode
- `app/core_calc/foodindex.py` (fungsi murni): vektor n-gram karakter (3-gram, hashing 2048 dimensi, TF-IDF atau biner ternormalisasi), `search(query, entries, top_k, min_score)`; deterministik, tanpa dependensi baru. Dipakai sebagai cadangan dan untuk saran "maksudmu ...?".
- `app/core_calc/dishes.py`: `DishRecord`, `match_dish(query, dishes)` (nama persis/alias, lalu semua kata ada, lalu indeks n-gram dengan ambang tinggi; ambigu/rendah → `None`), `expand_dish(dish, portion_g|servings, foods)` → daftar `ComponentPortion(food, grams, label)` dengan skala `portion_g / serving_g`.
- `app/schemas/extraction.py`: `FoodItem` tambah `dish_id: str | None`, `food_id: str | None`, `components: list[ComponentGuess] = []` dengan `ComponentGuess{food_id|None, name, portion_g_guess}`. Batasi `components` maks 8.
- `app/services/extraction.py`: sisipkan katalog ringkas ke prompt (mis. `food_id|nama` per baris, hidangan di bagian terpisah dengan ringkasan komponen). Dengan 100-250 entri katalog sekitar 3-4 ribu token; bila katalog tumbuh >400, prasaring dengan `foodindex.search` terhadap kata di pesan. Instruksi: "isi `dish_id`/`food_id` hanya dari katalog; hidangan komposit yang tidak ada di katalog dipecah ke `components`; JANGAN mengisi angka gizi".
- `app/graph/nodes/save_logs.py`: untuk tiap `FoodItem`: (1) `dish_id` valid atau `match_dish(name)` → `expand_dish`; (2) `food_id` valid atau `match_food(name)`; (3) `components` dari LLM → tiap komponen via id valid/`match_food`/`foodindex`; (4) tak ada kecocokan → catatan sistem seperti sekarang. Setiap komponen menjadi satu `LogItem` dengan `group_name` = nama hidangan dan `food_id` terisi. Satu `Log` per `FoodItem` (kind `meal`) seperti sekarang; `extracted` menyimpan `dish_id` dan komponen yang dipakai (untuk jejak).
- `app/tools/nutrition.py`: `cari_gizi` juga mengenali hidangan dan mengembalikan `{found, hidangan, komponen:[{nama,gram,gula_g,natrium_mg,lemak_g,kkal,sumber}], total:{...}}`. Pertahankan bentuk lama untuk makanan atom.
- `PATCH /logs/{id}`: koreksi porsi pada komponen tetap menghitung ulang dari `foods`; tambahkan opsi `scale` untuk menskalakan seluruh hidangan (mis. "setengah porsi") dan penghapusan satu komponen ("tanpa nasi").
- `GET /foods/search?q=` (baru, untuk UI koreksi dan saran): gabungan `match_food`, `match_dish`, `foodindex`; kembalikan maks 8 dengan `kind: food|dish`.

### 3.4 Flutter
- Kartu "Yang kucatat" (`chat_screen.dart`, `ExtractionCard`): hidangan tampil sebagai kelompok dengan komponennya (nama, gram, kkal, gula/natrium/lemak), total hidangan, tombol ubah porsi per komponen dan "setengah porsi" untuk kelompok. Komponen tak dikenali ditandai "belum terhitung" dengan tombol cari (`/foods/search`).

### 3.5 Tes (minimal)
- `tests/core_calc/test_foodindex.py`, `test_dishes.py`: kasus ayam geprek/penyet/krispi, "nasi uduk" tidak boleh jatuh ke "sambal", ambigu → `None`, skala porsi, jumlah gram total.
- `tests/graph/test_decomposition.py` dengan model palsu (`tests/graph/fakes.py`): hidangan terkurasi → 4 `LogItem` ber-`group_name`; komponen dari LLM dengan id valid/tak valid; abstain; total gizi = jumlah komponen (hitung ulang manual dari tabel).
- `tests/api/test_food_search.py`, tes `PATCH` (skala, hapus komponen), tes seed (setiap `food_id` di `dishes.json` ada di `foods`; tiap komponen punya `source`).
- `seed.eval_extraction`: tambah kasus hidangan komposit (jangan dijalankan di CI; berbayar).

## 4. Fase 2: Riwayat makan dan gizi

### 4.1 Backend
`GET /logs/history?days=14&before=YYYY-MM-DD` → 
```json
{"days": [{"date": "2026-10-15", "totals": {"kcal":1820,"sugar_g":48,"sodium_mg":1900,"fat_g":55},
           "limits": {"sugar_g":50,"sodium_mg":2000,"fat_g":67},
           "meals": [{"log_id":"...","kind":"meal","time":"2026-10-15T12:30:00+07:00","source":"text|voice|photo_*|barcode",
                      "title":"Ayam geprek","items":[{"id":"...","name":"Ayam goreng tepung","group":"Ayam geprek","portion_g":100,"kcal":260,"sugar_g":0.3,"sodium_mg":400,"fat_g":18,"food_id":"..."}],
                      "totals":{...},"corrected":false}],
           "drinks": [...], "activity_minutes": 30, "sleep_hours": 6.5}],
 "next_before": "2026-10-01"}
```
Satuan batas harian dari `DAILY_LIMITS`/`DAILY_LIMITS_MANAGEMENT` (mode pengguna). Pengelompokan per hari memakai tanggal WIB (`app/timeutil.py`). Tambahkan kunci `kcal` target setelah Fase 4 (kebutuhan energi). Akses hanya data milik sendiri.

### 4.2 Flutter
- Tab baru **Riwayat** (lihat 5.3): daftar per hari (header tanggal + total harian dengan bilah terhadap batas gula/natrium/lemak, ditulis dengan kata "sisa 12 g" / "melewati batas 8 g"), kartu per waktu makan yang bisa dibuka untuk melihat komponen dan gizi masing-masing, ikon sumber (teks/suara/foto/kode batang), hari tanpa catatan ditulis "tidak tercatat" (bukan nol), tarik-untuk-muat-lebih-lama, ketuk item untuk koreksi porsi (memakai `PATCH`). Strip mingguan di atas: batang kkal/gula per hari dengan garis batas (gaya `DailyBarChart` di `features/trends/trends_widgets.dart`).
- Keadaan kosong, memuat, dan galat harus ada (pola `LoadError`).

## 5. Fase 3: Beranda hidup (menggantikan tab "10 Tahun")

### 5.1 Mesin kebiasaan (fungsi murni): `app/core_calc/habits.py`
Masukan: deret harian 14-28 hari (gula, natrium, lemak, kkal, minuman manis, menit aktif, jam tidur, jumlah hari tercatat), profil, hasil cek terakhir, mode. Keluaran: daftar **sinyal** `{key, level: perhatian|pantau|baik|info, title, detail, evidence:{...}, source}` dan **kondisi hari ini** per dimensi.
Ambang (semua harus tercatat sumbernya di `docs/sumber-angka-klinis.md`; sumber yang sudah ada di repo ditandai ✔):
- Gula: > 50 g/hari rata-rata atau pada ≥ 3 hari dalam 7 hari terakhir ✔ Permenkes 30/2013. Mode pengelolaan: 25 g (asumsi KIRA, `DAILY_LIMITS_MANAGEMENT`) ✔.
- Natrium > 2000 mg/hari ✔ Permenkes 30/2013 (dan acuan WHO 2 g natrium; **verifikasi sebelum dikutip**). Lemak > 67 g ✔.
- Aktivitas: < 150 menit/minggu intensitas sedang ✔ WHO 2020 (sudah dipakai di `core_calc/goals.py`), dihitung dari log aktivitas dan Health Connect.
- Tidur: rata-rata < 7 jam atau ≥ 3 malam < 6 jam dalam 7 hari ✔ AASM/SRS (Watson dkk. 2015) (batas 6 jam = asumsi KIRA, sudah ada di `core_calc/patterns.py`).
- Pola gabungan (deskriptif): tidur pendek + gula tinggi pada hari yang sama (memakai `compare_by_sleep`), tren naik/turun mingguan (selisih minggu ini vs lalu dengan ambang derau yang sudah ada di `services/jobs.py::weekly_changes`).
- Tekanan darah/gula darah terakhir: pakai `core_calc/triage.py` yang sudah ada (jangan menduplikasi ambang).
Bahasa: penanda, **bukan diagnosis** ("kebiasaan yang bila berlanjut dikaitkan dengan peningkatan risiko ..."); tidak menyebut penyakit pasti. Setiap sinyal membawa `evidence` angka (dari data sendiri) dan `source`.
Cakupan data: bila hari tercatat < 3 dalam 7 hari, kembalikan `data_quality: "kurang"` dan ajakan mencatat, jangan menyimpulkan.

### 5.2 Endpoint: `GET /dashboard`
Satu panggilan memuat Beranda: 
```json
{"today": {"date":"...", "nutrition": {"kcal":..,"sugar_g":..,"sodium_mg":..,"fat_g":..,"limits":{...},"kcal_target":null|2150},
           "activity_minutes":..,"activity_target_today":..,"sleep_hours_last_night":..,"sleep_target":{"hours":8,"bedtime":"22:00"},
           "meals_logged": 2, "last_log_at": "..."},
 "week": {"days":[...7 hari ringkas...], "vs_last_week": {...}},
 "signals": [...], "data_quality": "cukup|kurang",
 "risk": {...isi /projection...},          // proyeksi 10 tahun + hipertensi, diperbarui tiap catatan baru
 "risk_history": {...ringkas...},          // arah skor 30 hari
 "plan_today": {...dari Fase 4, boleh null sebelum Fase 4...},
 "goals": [...ringkas dari /goals...], "next_best_action": {"kind":"log_meal|measure_bp|check|exercise|sleep","text":"..."}}
```
`next_best_action` aturan deterministik (prioritas: tanda bahaya/penanda perhatian → saran cek yang jatuh tempo → catat makan yang belum ada menurut jam → olahraga yang tersisa → tidur).
Proyeksi 10 tahun harus **dihitung ulang dari kebiasaan terkini** (sudah begitu lewat `risk.compute_risk_state`); tambahkan input kebiasaan harian yang belum dipakai bila ada sumber yang sah (jangan menambah faktor ke FINDRISC di luar definisinya; FINDRISC hanya memuat aktivitas, sayur/buah, dll.). Faktor kebiasaan lain (tidur, natrium) ditampilkan sebagai **sinyal**, bukan ditambahkan ke skor.

### 5.3 Navigasi dan UI Flutter
- Tab bawah: **Ngobrol | Beranda | Riwayat | Cek** (ganti "10 Tahun" → "Beranda"; `lib/core/router.dart`, `lib/shared/app_shell.dart`). Rute lama `/projection` diarahkan ke Beranda.
- Beranda (`lib/features/home/`): urutan kartu: (1) sapaan + `next_best_action`; (2) **Hari ini**: tiga cincin/bilah (gizi vs batas, aktivitas vs target hari ini, tidur semalam vs target) dengan teks; (3) **Rencana hari ini** (Fase 4); (4) **Sinyal kebiasaan** (urut perhatian→pantau→baik) dengan detail yang bisa dibuka dan sumbernya; (5) **Proyeksi 10 tahun** (kartu kurva + hipertensi yang sudah ada, dipadatkan) + skenario/what-if/target/rekap mingguan yang sudah ada (pindahkan, jangan hapus); (6) tautan Tren, Ringkasan dokter.
- Muat ulang otomatis: Beranda memantau `chatProvider`/log baru (invalidasi `dashboardProvider` saat ada catatan baru, mengikuti pola `ref.invalidate(projectionProvider)` di `chat_controller.dart`) dan menyegarkan saat aplikasi dibuka kembali.
- Semua kartu punya keadaan kosong/data kurang yang jelas, teks alternatif untuk pembaca layar, dan tidak hanya mengandalkan warna.

### 5.4 Tes
- `tests/core_calc/test_habits.py` (tiap sinyal di batas ambang, data kurang → tidak menyimpulkan, mode pengelolaan), `tests/api/test_dashboard.py` (pengguna baru, Raka, data pengguna lain tidak bocor, `next_best_action` per prioritas), tes widget Beranda/Riwayat dengan `FakeApi` (perbarui `app/test/support/fakes.dart`, tambahkan metode baru ke `KiraApi` di `lib/core/api_client.dart`), perbarui tes yang menunjuk `ProjectionScreen` (`test/projection_test.dart`, `test/clinical_extras_test.dart`).

## 6. Fase 4: Perencana harian dan mingguan, pengingat, WhatsApp

### 6.1 Prinsip
Rencana dibuat **deterministik** dari profil, target, kebiasaan, dan katalog hidangan; LLM tidak menentukan angka. LLM boleh menarasikan rencana lewat tool (lihat 6.5). Rencana bersifat **usulan**, bukan resep medis; tidak ada saran obat; selalu bisa diubah pengguna.

### 6.2 Kebutuhan energi dan makro (WAJIB diverifikasi dari sumber sebelum dipakai)
- Sumber utama yang diusulkan: **AKG 2019 (Permenkes 28/2019)** untuk energi per kelompok usia/jenis kelamin dewasa. Nilai yang diingat penulis spesifikasi **belum diverifikasi** dan tidak boleh dipakai sebelum dibaca dari dokumen resmi:
  laki-laki 19-29: 2650 kkal, 30-49: 2550, 50-64: 2150, 65-80: 1800; perempuan 19-29: 2250, 30-49: 2150, 50-64: 1800, 65-80: 1550 (tambahan trimester/menyusui di luar cakupan).
  Cara verifikasi: unduh Permenkes 28/2019 (JDIH Kemenkes / BPK) dan kutip tabel; catat tautan dan status Primer di `docs/sumber-angka-klinis.md`. Bila tidak bisa diverifikasi, gunakan persamaan Mifflin-St Jeor × faktor aktivitas (FAO/WHO/UNU) **dan** tandai Sekunder.
- Penyesuaian berat: bila IMT ≥ 25 dan pengguna bertujuan menurunkan berat, kurangi 300-500 kkal/hari (asumsi KIRA; tulis sebagai asumsi, tidak di bawah 1200 kkal untuk perempuan / 1500 untuk laki-laki dan **jangan** menyajikannya sebagai diet medis; arahkan ke ahli gizi). Tujuan pengguna (`goal`: jaga | turun berat | tingkatkan aktivitas) disimpan di preferensi.
- Anggaran per waktu makan: pembagian bawaan sarapan 25% / siang 35% / malam 30% / selingan 10% (asumsi KIRA). Gula, natrium, lemak dibagi proporsional memakai batas harian yang sudah ada.

### 6.3 Penyusun rencana (fungsi murni): `app/core_calc/planner.py`
- **Tidur:** target jam = 8 (rentang 7-9, AASM/SRS) bila rata-rata terkini < 7, selain itu pertahankan; jam tidur = `jam_bangun - target`. Jam bangun dari preferensi (bawaan 06:00). Bila Health Connect/log tidur ada, tampilkan selisih dari semalam.
- **Olahraga:** target mingguan 150 menit sedang (WHO 2020); **tanjakan** untuk pengguna yang kini jauh di bawah: mulai dari max(30, 1,2 × rata-rata 2 minggu terakhir) menit/minggu dan naik ≤ 20%/minggu sampai 150 (**asumsi KIRA**, tulis sebagai asumsi); sebar pada hari pilihan pengguna (bawaan 5 hari × 30 menit, min. 1 hari istirahat), jenis dari preferensi (jalan cepat, bersepeda, senam, berenang) dengan bawaan jalan cepat; tambah 2 hari penguatan otot bila pengguna memilih (WHO 2020). Jika ada penanda tensi "perhatian" atau pengguna mengisi kondisi (mis. nyeri dada, sesak) **jangan** memberi rencana latihan baru: tampilkan arahan ke tenaga kesehatan (pakai `core_calc/red_flags.py`).
- **Makan:** untuk tiap waktu makan pilih 1-2 kandidat dari `dishes` (+ minuman/camilan dari `foods`) yang memenuhi anggaran gula/natrium/lemak/kkal waktu itu; hindari yang ada di `food_preferences.dislikes` profil; variasi lintas hari (tidak mengulang hidangan yang sama dalam 3 hari; rotasi deterministik dengan benih = tanggal+id pengguna agar stabil dalam sehari); mode pengelolaan memakai batas gula 25 g. Keluaran: `{meal, title, components[], totals, why}` dengan `why` berupa kalimat dari aturan (mis. "natrium rendah untuk siang, kamu sudah 1.400 mg dari kemarin"), tanpa klaim penyakit.
- **Adaptif:** rencana hari ini dihitung ulang dari sisa anggaran berdasarkan yang sudah dicatat (sisa gula/natrium/kkal) dan menyebut kenapa berubah.
- **Mingguan:** 7 hari ke depan (Senin-Minggu atau 7 hari bergulir): tiap hari {tidur, olahraga, 3 waktu makan + selingan}. Deterministik dan idempoten; tidak disimpan kecuali penyesuaian pengguna.
- Tes properti: total tiap hari tidak melewati batas harian kecuali tidak ada kandidat (lalu ditandai), tidak ada hidangan yang melanggar preferensi, rencana sama untuk masukan sama, mode pengelolaan lebih ketat.

### 6.4 Data dan endpoint
- Tabel `plan_preferences` (`user_id pk, wake_time, meal_times jsonb {breakfast,lunch,dinner,snack}, exercise_time, exercise_days smallint[], exercise_kinds text[], strength_days int, goal text, channels jsonb {app:true, whatsapp:false}, reminders jsonb {meals,exercise,sleep,weekly_plan}, quiet_hours jsonb, updated_at`).
- Tabel `plan_overrides` (`user_id, date, slot, replacement jsonb`) untuk penggantian manual satu slot (opsional, fase akhir).
- Endpoint: `GET/PUT /plan/preferences`, `GET /plan/today`, `GET /plan/week`, `POST /plan/today/swap {slot}` (ganti satu usulan dengan alternatif lain yang memenuhi anggaran).
- Pengingat WhatsApp: tabel yang ada `wa_outbox` (`kind`: tambah `plan`, `plan_reminder`; `ref` = `YYYY-MM-DD:slot` untuk mencegah pengulangan). Job penjadwal baru di `app/scheduler.py` (zona WIB, **per pengguna sesuai preferensi**): (a) ringkasan rencana hari itu pada `wake_time` + 15 menit; (b) pengingat per waktu makan/olahraga/tidur 10-15 menit sebelum waktunya, hanya bila kanal WhatsApp aktif, nomor tertaut (`wa_links`), bukan jam tenang, dan belum tercatat (mis. makan siang sudah dicatat → lewati); (c) ringkasan mingguan rencana pada hari/jam pilihan (bawaan Minggu 18:00). Maksimal 4 pesan WhatsApp/hari/pengguna (batas keras), pesan singkat, tanpa angka kesehatan yang sensitif (angka gizi boleh, hasil cek tidak).
  Idempoten: satu `ref` satu kali. Tambahkan fungsi di `app/services/jobs.py` atau modul baru `app/services/planner_jobs.py`, daftarkan di `scheduler.py`, ubah `tests/test_scheduler.py` (jumlah job).
- WhatsApp dua arah: pesan masuk "rencana", "jadwal", "rencana besok", "rencana minggu" dijawab oleh agent lewat tool (6.5); "stop pengingat" mematikan kanal WhatsApp di preferensi (tangani **sebelum** LLM di `app/services/whatsapp.py`/`app/api/whatsapp.py`, deterministik).

### 6.5 Tool LLM baru (`app/tools/`)
`rencana_hari_ini()`, `rencana_minggu()`, `riwayat_makan(hari=3)` (ringkasan makan dan gizi dari log), semuanya hanya-baca dan membungkus fungsi/serivis di atas; daftarkan di `TOOLS` (cari `TOOLS` di `app/graph/kira_graph.py`/`app/tools/__init__.py`). Perbarui `SYSTEM_PROMPT` (`app/graph/prompts.py`): bila pengguna bertanya "makan apa/olahraga apa/tidur jam berapa", panggil tool dan sampaikan hasilnya; **jangan** mengarang rencana sendiri.

### 6.6 Flutter
- `lib/features/plan/`: layar **Rencana** (dibuka dari kartu di Beranda dan menu Profil): hari ini (daftar slot waktu dengan usulan makan beserta komponen dan gizi, olahraga, tidur), tombol "ganti usulan" per slot, ikon centang saat sudah tercatat; tab mingguan (7 hari, dapat digulir); layar **Preferensi rencana** (jam bangun/makan/olahraga, hari olahraga, jenis, tujuan, kanal, pengingat, jam tenang).
- Pengingat lokal: perluas `features/reminders/reminder_plan.dart` (`planReminders`) agar membuat notifikasi per slot rencana (isi generik: "Waktunya makan siang", "Waktunya jalan cepat", "Waktunya bersiap tidur"; **tanpa** data kesehatan), memakai preferensi rencana, dilewati bila sudah tercatat (mengikuti pola `loggedToday`); ID unik per slot per hari; jadwalkan 7 hari ke depan dan jadwalkan ulang saat aplikasi dibuka/ada catatan baru. Pertahankan opt-in dan default mati.
- Konsistensi kanal: bila WhatsApp aktif untuk suatu pengingat, jangan juga kirim notifikasi lokal yang sama (pilihan per pengingat di preferensi).

### 6.7 Tes
`tests/core_calc/test_planner.py` (lihat 6.3), `tests/api/test_plan.py` (preferensi, `today`, `week`, `swap`, data pengguna lain), `tests/services/test_planner_jobs.py` (pengingat WA: satu kali per `ref`, jam tenang, sudah tercatat → lewati, batas 4/hari, tanpa nomor tertaut → tidak ada), tes percakapan WhatsApp "rencana"/"stop pengingat", tes widget Rencana dan Preferensi, tes `planReminders` yang diperluas.

## 7. Lintas fase

### 7.1 Urutan kerja yang disarankan (commit modular per butir, tes hijau sebelum lanjut)
1. Fase 1.2 data (components, dishes, migrasi, seed + tes seed) → 3.3 core_calc (`foodindex`, `dishes`) → ekstraksi/`save_logs`/tool → `/foods/search` → Flutter kartu hidangan.
2. Fase 2 riwayat (backend lalu Flutter tab Riwayat).
3. Fase 3 `habits` + `/dashboard` + Flutter Beranda (ganti tab).
4. Fase 4 `planner` + preferensi/endpoint + tool LLM + job WA + Flutter Rencana + pengingat lokal.
5. Dokumentasi, screenshot, cetak ulang PDF, merge ke `main`, push.

### 7.2 Kriteria selesai (acceptance)
- "Aku makan ayam geprek" menghasilkan satu catatan dengan ≥ 3 komponen ber-gizi dari tabel `foods`, total = jumlah komponen; di Riwayat tampil terkelompok; koreksi porsi/skala bekerja; hidangan tak dikenal tidak menghasilkan angka karangan.
- Beranda menampilkan kondisi hari ini (gizi/olahraga/tidur), sinyal kebiasaan bersumber, proyeksi yang berubah setelah catatan baru (tanpa muat ulang manual), dan rencana hari ini.
- Pengguna dapat mengatur preferensi, melihat rencana hari ini dan minggu ini, dan menerima pengingat lewat notifikasi lokal dan/atau WhatsApp tanpa duplikasi dan dengan batas harian.
- Semua angka baru bersumber atau ditandai asumsi di `docs/sumber-angka-klinis.md`; tidak ada kata "aman"; tidak ada angka dari LLM.
- `uv run pytest -q` hijau, `flutter analyze` bersih, `flutter test` hijau, `npm test` (wa-bot) hijau bila disentuh.

### 7.3 Screenshot yang perlu diambil ulang/ditambah (setelah UI selesai)
`05-chat-checkin` (kartu hidangan terkelompok), `07-projection` dan `07b-...` (kini Beranda; ganti nama berkas menjadi `07-beranda*.png` dan perbarui referensi di `docs/submission/deck.html`, `proposal.html`, `docs/screenshots/README.md`), tambahkan `Riwayat`, `Rencana hari ini`, `Rencana minggu`, `Preferensi rencana`. Setelahnya cetak ulang `KIRA-pitch-deck.pdf` (12 hlm) dan `KIRA-proposal.pdf` (batas 10 hlm).

### 7.4 Risiko dan keputusan terbuka (untuk pemilik produk)
- Akurasi gram per komponen pada resep adalah perkiraan; sebaiknya tampilkan "perkiraan" dan izinkan koreksi (sudah dalam rencana).
- Kebutuhan energi memakai AKG/persamaan yang belum diverifikasi saat spesifikasi ini ditulis (6.2): verifikasi dulu.
- Beban LLM: ekstraksi dengan katalog dalam konteks menambah ribuan token per pesan; ukur latensi pada model "high" dan pertimbangkan varian `-medium`/`-low` untuk ekstraksi.
- Pengingat WhatsApp melewati Baileys (tidak resmi); produksi butuh WhatsApp Business Platform. Jaga batas 4 pesan/hari.
- Rencana makan bukan terapi gizi medis; sampaikan itu di UI dan arahkan pengguna dengan penanda "perhatian" ke tenaga kesehatan.
