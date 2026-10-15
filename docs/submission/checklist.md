# Checklist submission KIRA

Batas pengumpulan: **16 Oktober 2026, 23.50 WIB**. Targetkan submit beberapa jam lebih awal.

## Sudah siap di repo

- [x] Repositori dengan `README.md` (alur solusi dan cara menjalankan)
- [x] Pitch deck 12 slide dengan slide Penggunaan AI: [`KIRA-pitch-deck.pdf`](KIRA-pitch-deck.pdf) (sumber: `deck.html`)
- [x] Proposal A4, 7 halaman (batas 10): [`KIRA-proposal.pdf`](KIRA-proposal.pdf) (sumber: `proposal.html`)
- [x] Naskah video 2 menit: [`video-script.md`](video-script.md)
- [x] Latihan pitching dan tanya jawab (jawaban jujur sesuai kode): [`latihan-pitch.md`](latihan-pitch.md)
- [x] Angka bersumber: [`../sumber-angka-klinis.md`](../sumber-angka-klinis.md)
- [x] APK rilis dibangun (`app/build/app/outputs/flutter-apk/app-release.apk`, tidak ikut git). Dibangun dengan `API_URL=http://10.0.2.2:8000` (alamat emulator); untuk HP sungguhan bangun ulang dengan URL server kamu. APK yang dibangun sebelum 15 Okt 2026 sore tidak punya izin INTERNET (build rilis tidak mewarisinya dari manifest debug), jadi **bangun ulang** sebelum dipakai.

## Perlu dikerjakan tim (tidak bisa dikerjakan dari repo)

- [ ] Isi placeholder merah di deck dan proposal: nama tim, anggota, URL GitHub, URL prototype, URL YouTube. Cari dengan `grep -n "isi " docs/submission/*.html`, ubah di `.html`, lalu cetak ulang PDF (lihat bawah).
- [ ] **Deploy backend ke HTTPS** (mis. VPS atau layanan container) dan bangun ulang APK dan web dengan `API_URL` tersebut. Tanpa ini, prototype tidak bisa dicoba juri.
- [ ] Unggah build web sebagai tautan prototype; uji dari HP lain.
- [ ] Rekam video 2 menit mengikuti `video-script.md`, unggah ke YouTube dengan visibilitas **Publik**, uji dari jendela samaran.
- [ ] Isi `ANTHROPIC_API_KEY` dan `STT_API_KEY` di server; jalankan `uv run python -m seed.eval_extraction` sekali dan catat hasilnya jika ingin dicantumkan di proposal (saat ini proposal menyatakan uji akurasi belum dilakukan).
- [ ] Latihan demo minimal 5 kali dari HP yang dipakai saat pitching, termasuk dengan sinyal lemah. Siapkan `DEMO_CACHE=true` dan rekaman layar sebagai cadangan.
- [ ] Jika memakai WhatsApp saat demo: nomor cadangan khusus, data dummy, dan alur yang sama di aplikasi sebagai fallback.
- [ ] Cek akhir: tidak ada data pribadi asli di seed data, screenshot, atau video.

## Mencetak ulang PDF

```bash
chrome --headless=new --no-pdf-header-footer --allow-file-access-from-files \
  --print-to-pdf=docs/submission/KIRA-pitch-deck.pdf file:///<path>/docs/submission/deck.html
chrome --headless=new --no-pdf-header-footer --allow-file-access-from-files \
  --print-to-pdf=docs/submission/KIRA-proposal.pdf file:///<path>/docs/submission/proposal.html
```

Hal yang sengaja jujur di materi: uji pengguna belum ada; akurasi ekstraksi dengan model sungguhan belum diukur; WhatsApp sungguhan belum diuji; SATUSEHAT dan kepatuhan UU PDP masih roadmap; insidensi per kategori FINDRISC bersumber sekunder; nilai gula makanan adalah estimasi tim.
