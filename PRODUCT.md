# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Stack
Flutter (Android sebagai target utama, APK untuk juri). Build Flutter web hanya sebagai link prototype. Backend FastAPI; aplikasi hanya merekam input, memanggil API, dan menampilkan hasil. (Sumber: `docs/rencana_implementasi.md`, dikonfirmasi pengguna.)

## Users
Orang usia 20-40 tahun di Indonesia yang merasa sehat dan belum rutin cek gula darah atau tensi, misalnya Raka (28, software engineer, tidur 5 jam, ayah diabetes). Mereka tidak punya keluhan, jadi tidak memeriksakan diri. Pengguna kedua: orang yang sudah terdiagnosis dan butuh pendampingan harian. Banyak yang tidak nyaman mengetik, jadi suara dan foto setara dengan teks.

## Product Purpose
KIRA adalah teman ngobrol 1 menit sehari yang memproyeksikan risiko diabetes pengguna 10 tahun ke depan, menunjukkan kebiasaan yang paling berdampak, dan memberi tahu kapan harus memeriksakan diri. Hasil pemeriksaan nyata dipakai untuk mengkalibrasi ulang proyeksi; setelah diagnosis, fokus pindah dari pencegahan ke pengelolaan. Sukses: pengguna kembali check-in dan benar-benar pergi cek ketika diminta.

## Positioning
Berbeda dari aplikasi diet dan chatbot umum: (1) "Kira-kira 10 Tahun", dua proyeksi berdampingan dengan slider; (2) tahu kapan dan cek apa yang paling berguna (ketidakpastian ditampilkan sebagai rentang); (3) berganti mode setelah diagnosis. Angka risiko dan gizi berasal dari fungsi deterministik yang bisa diaudit, bukan tebakan LLM.

## Operating Context
Dipakai singkat di HP, sering sambil melakukan hal lain, dengan sinyal seluler yang tidak selalu baik. Input: teks, tahan-untuk-bicara, foto makanan/struk/hasil lab. Bahasa Indonesia santai, bercampur slang. Dipresentasikan juri hackathon JOINTS 2026 (Healthcare subtema 5) dari satu HP Android.

## Capabilities and Constraints
- KIRA bukan alat diagnosis: tidak ada saran obat atau dosis, tidak ada kata "kamu menderita" atau "kamu aman"; gunakan "proyeksi risiko", "skrining", "masih sesuai targetmu hari ini".
- Risiko selalu berupa rentang dan selalu bersama jalur perbaikan; tidak menakut-nakuti.
- Tanda bahaya (nyeri dada, sesak, gula/tensi ekstrem) langsung diarahkan ke IGD/Puskesmas.
- Seluruh data demo adalah data dummy. Angka klinis sementara sampai diverifikasi tim.
- WhatsApp, fitur keluarga, dan Framingham ditunda ke Fase 2.

## Brand Commitments
Nama KIRA ("Knowledge-driven Insight for Risk Awareness", juga dari "kira-kira"). Tagline: "Kira-kira kesehatanmu 10 tahun lagi seperti apa? Tanya KIRA." Nada: teman yang hangat, singkat, tidak menggurui.

## Evidence on Hand
Data pendukung masalah ada di `docs/konsep_kira.md` (SKI 2023, CKG 2026) dengan tautan sumber. Tidak ada testimoni, pelanggan, atau studi pengguna; jangan dikarang.

## Product Principles
1. Jujur tentang ketidakpastian: rentang, bukan satu angka pasti.
2. Setiap proyeksi datang bersama langkah yang bisa dilakukan hari ini.
3. Mendorong ke pemeriksaan nyata; data klinis mengalahkan self-report.
4. Satu menit sehari: check-in secepat mungkin, dengan suara dan foto setara teks.
5. Bahasa tenang dan manusiawi, tanpa jargon medis dan tanpa menakut-nakuti.

## Accessibility & Inclusion
Pengguna yang tidak nyaman mengetik (suara, bahasa sederhana). Kontras teks minimal WCAG AA, target sentuh nyaman, dan dapat dipakai dengan satu tangan. Tidak bergantung pada warna saja untuk menyampaikan tingkat risiko.

## Standing Visual Preference
Arah visual yang dipilih pengguna: standar kategori aplikasi kesehatan, dieksekusi penuh tanpa metafora dunia khusus (dipilih setelah beberapa putaran undi arah, 2026-10-14). Tolok ukur kualitas dan nuansa: Apple Health / Google Fit (grafik tren tenang, kartu ringkasan rapi) dan Flo / Headspace (hangat, ramah). Masukan pengguna atas arah-arah sebelumnya: kurang terpercaya/klinis, kurang hangat, kurang berani; jadi hasil harus kredibel, hangat, dan tetap punya satu hal yang diingat.
