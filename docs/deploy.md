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
