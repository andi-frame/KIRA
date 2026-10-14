# KIRA WhatsApp bot (prototype)

Jembatan kecil dari WhatsApp ke API KIRA. Semua logika ada di backend (`POST /webhooks/whatsapp`); bot hanya meneruskan teks,
voice note, dan foto, lalu mengirim balasan. Bot juga mengirim pengingat check-in dari antrean keluar API.

> **Hanya prototype.** Baileys meniru WhatsApp Web (bukan API resmi): nomor bisa diblokir, melanggar ketentuan layanan
> WhatsApp, dan tidak layak untuk data kesehatan. Pakai nomor khusus dan data dummy. Produksi wajib memakai
> WhatsApp Business Platform resmi.

## Menjalankan

```bash
# backend: isi BOT_SECRET di .env lalu jalankan API (uv run uvicorn app.main:app)
cd wa-bot
npm install
cp .env.example .env        # samakan BOT_SECRET dengan backend
node --env-file=.env src/index.js   # scan QR di terminal sekali; sesi tersimpan di folder auth/
```

Menautkan akun: di aplikasi KIRA buat kode (`POST /whatsapp/link-code`, tombol Tautkan WhatsApp di Profil), lalu kirim
`KIRA 1234` (kode yang tampil) ke nomor bot.

## Tes

```bash
npm test     # logika inti (penerusan pesan, pembatas balasan, antrean keluar) tanpa nomor WhatsApp
```

Koneksi Baileys sungguhan tidak diuji otomatis (butuh nomor dan scan QR).
