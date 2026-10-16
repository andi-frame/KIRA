# Deploy KIRA ke satu server (HTTPS)

Status jujur: berkas di bawah ini **belum pernah dijalankan di server sungguhan** (belum ada domain/server). Yang sudah
diperiksa di mesin pengembangan: `docker compose -f docker-compose.prod.yml config` valid, dan image backend berhasil dibangun.
Jalankan langkah 1-5 sekali di server percobaan sebelum hari demo.

## Yang dibutuhkan

- Satu server Linux (1 vCPU / 2 GB RAM cukup untuk demo) dengan Docker + Docker Compose.
- Satu domain/subdomain yang A-record-nya mengarah ke server (mis. `api.contoh-kira.id`). Port 80 dan 443 terbuka.
- Kunci model bahasa (Anthropic, atau penyedia kompatibel OpenAI seperti 9router) dan, bila memakai suara, kunci STT.

## Langkah

1. **Salin kode** ke server: `git clone https://github.com/andi-frame/KIRA.git /opt/kira && cd /opt/kira`.
2. **Isi konfigurasi**: `cp .env.production.example .env.production`, lalu isi `KIRA_DOMAIN`, `POSTGRES_PASSWORD`,
   `JWT_SECRET` (`openssl rand -hex 32`), `CORS_ORIGINS`, dan kunci model. `ENVIRONMENT=production` otomatis dari Compose:
   API menolak start bila `JWT_SECRET` bawaan atau pendek.
3. **Jalankan**: `docker compose -f docker-compose.prod.yml --env-file .env.production up -d --build`.
   Migrasi basis data dan seed makanan/faskes berjalan sendiri saat backend start (idempoten).
4. **Periksa**: `curl https://$KIRA_DOMAIN/health/ready` harus `{"status":"ready"}`. Sertifikat HTTPS diurus Caddy
   (pertama kali butuh beberapa detik; lihat `docker compose -f docker-compose.prod.yml logs caddy` bila gagal).
5. **Bangun aplikasi dengan alamat server**:
   ```bash
   cd app
   flutter build apk --release --dart-define=API_URL=https://$KIRA_DOMAIN
   flutter build web --release --dart-define=API_URL=https://$KIRA_DOMAIN   # opsional: tautan prototype tanpa instal
   ```
   APK yang dibangun dengan `http://10.0.2.2:8000` hanya jalan di emulator.
6. **Akun demo** (opsional, data dummy): `docker compose -f docker-compose.prod.yml exec backend uv run --no-dev python -m seed.raka`.
7. **WhatsApp (prototype)**: isi `BOT_SECRET`, lalu `docker compose -f docker-compose.prod.yml --profile whatsapp up -d`
   dan scan QR dari `docker compose ... logs -f wa-bot`. Lihat peringatan di `wa-bot/README.md`: tidak resmi, nomor khusus, data dummy.

## Lewat Coolify

Pakai `docker-compose.coolify.yml`, bukan `docker-compose.prod.yml`: berkas produksi memuat Caddy yang ikut meminta port 80/443,
padahal proxy Coolify (Traefik) sudah memegangnya dan sudah mengurus HTTPS. Berkas Coolify hanya berisi Postgres dan API.
Belum diuji di Coolify sungguhan; sudah lolos `docker compose -f docker-compose.coolify.yml config`.

1. Resource baru > repositori GitHub > build pack **Docker Compose**, branch `main`, **Docker Compose Location**
   `/docker-compose.coolify.yml`.
2. Tab **Environment Variables**: isi `POSTGRES_PASSWORD`, `JWT_SECRET` (`openssl rand -hex 32`), `CORS_ORIGINS`, dan kunci model
   (untuk 9router: `LLM_BASE_URL=https://9router.byhan.id/v1`, `LLM_API_KEY`, `LLM_MODEL_CHAT=ag/gemini-3.8-flash-high`,
   `LLM_MODEL_EXTRACT=ag/gemini-3.8-flash-low`). Variabel yang wajib dan kosong ditandai Coolify dan menahan deploy.
   `KIRA_DOMAIN` tidak dipakai di sini.
3. Layanan **backend** > **Domains**: `https://api.contoh-kira.id:8000` (port 8000 = port dalam kontainer; DNS A-record
   domain itu harus mengarah ke server Coolify). `PUBLIC_BASE_URL` terisi otomatis dari domain ini.
4. Deploy, lalu `curl https://api.contoh-kira.id/health/ready` harus `{"status":"ready"}`. Bangun aplikasi seperti langkah 5 di atas
   dengan `API_URL` domain itu.
5. WhatsApp: hapus komentar blok `wa-bot` di berkas Compose dan isi `BOT_SECRET` (peringatan di `wa-bot/README.md` berlaku).

## Pengguna demo

Untuk demo yang lebih baik ada tujuh pengguna dengan data berbeda (semua dummy, PIN `123456`): Raka (alur utama), Sari (hipertensi
terkontrol), Budi (prediabetes), Dewi (sehat dan aktif), Pak Joko (diabetes dan tensi tinggi), Nia (pekerja shift, tidur tidak
teratur), dan Tara (pengguna baru, baru 3 hari tercatat). Dibuat dengan skrip yang idempoten dan deterministik:

```bash
cd backend
uv run python -m seed.demo_users --list           # daftar persona dan cara masuk
uv run python -m seed.demo_users --reset          # hapus lalu buat ulang semuanya (juga Raka)
uv run python -m seed.demo_users --only sari,budi # hanya yang disebut
```

Di server Coolify: buka terminal kontainer backend, lalu `uv run --no-dev python -m seed.demo_users --reset`. Masuk dengan nama
pengguna (mis. `sari`) atau nomor telepon. Jangan jalankan di basis data berisi pengguna sungguhan tanpa `--only`: `--reset`
hanya menghapus akun demo (dikenali dari nomor `0812000100NN` dan Raka), tetapi akun demo tetap tampil bagi siapa pun yang tahu PIN-nya.

## Peta untuk "Tempat cek terdekat"

Tanpa pengaturan apa pun, daftar diambil dari OpenStreetMap (Overpass API, beberapa server dicoba bergantian karena server
publik kadang penuh) dan tiap tempat punya tombol rute Google Maps. Bila `GOOGLE_PLACES_API_KEY` diisi, Google Places
(Places API New, pencarian teks "puskesmas", "klinik kesehatan", "rumah sakit") didahulukan; bagian ini belum diuji dengan kunci
sungguhan. Bila semua sumber gagal, data contoh dipakai dan aplikasi mengatakannya, dengan tombol "Cari puskesmas di Google Maps".

## Cadangan dan pemulihan

- `scripts/backup-db.sh [folder]` membuat `pg_dump` terkompresi dan menghapus yang lebih tua dari 14 hari. Jadwalkan dengan cron
  dan **salin keluar server** (rclone ke penyimpanan objek).
- `scripts/restore-db.sh <berkas>` memulihkan (meminta konfirmasi). Latih sekali di mesin lain; cadangan yang belum pernah
  dipulihkan belum bisa disebut cadangan.

## Pemantauan

- `GET /health` (hidup) dan `GET /health/ready` (basis data terjangkau). Caddy memakai yang kedua untuk menentukan API sehat.
- Setiap respons membawa `X-Request-ID`, dan log mencatat satu baris per permintaan: metode, jalur, status, durasi, id
  (tanpa isi permintaan dan tanpa query, jadi tidak ada data kesehatan di log).
- Disarankan: pantau `/health/ready` dari layanan luar (UptimeRobot, Better Stack) dan tambahkan pelacak galat (mis. Sentry)
  sebelum pengguna sungguhan. Keduanya belum dipasang.

## Batas laju

- Masuk: 5 salah PIN per akun lalu terkunci 15 menit. Atur ulang PIN: 3 permintaan per jam.
- Pesan ke KIRA (teks, suara, foto): 20 per menit dan 400 per hari per pengguna, supaya satu akun tidak menghabiskan kuota model.
- Semuanya di memori satu proses. Untuk lebih dari satu proses/mesin, pindahkan ke penyimpanan bersama (mis. Redis) dan tambahkan
  batas per IP di Caddy (plugin rate-limit) atau di penyedia hosting.

## Keamanan: daftar periksa sebelum membuka ke pengguna

- [ ] `CORS_ORIGINS` diisi origin web yang sebenarnya (bukan `*`).
- [ ] Hanya port 80/443 yang terbuka; Postgres tidak dipublikasikan (memang tanpa `ports` di Compose).
- [ ] `JWT_SECRET` dan `POSTGRES_PASSWORD` acak dan tidak ada di git (`.env.production` sudah di `.gitignore`).
- [ ] Enkripsi disk di penyedia hosting aktif (data kesehatan di basis data tidak dienkripsi per kolom).
- [ ] Teks persetujuan dan kebijakan retensi ditinjau konsultan hukum (UU PDP): lihat `docs/privasi-dan-keamanan.md`.
- [ ] Cadangan terjadwal dan **sudah pernah dipulihkan**.
- [ ] Kanal WhatsApp produksi memakai WhatsApp Business Platform resmi, bukan Baileys.
