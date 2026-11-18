# Menerbitkan versi baru

Setiap **Run workflow** (Actions > Build RekapRapi) sekarang juga membuat **GitHub Release**
berisi `RekapRapi.apk`. Aplikasi Android memeriksa rilis terbaru saat dibuka dan menawarkan
pembaruan.

## Langkah tiap versi

1. Naikkan `version` di `pubspec.yaml` (mis. `1.0.16+17` menjadi `1.0.17+18`).
   Nomor sebelum `+` menjadi nama rilis (`v1.0.17`) dan dibandingkan dengan versi di HP
   pengguna. Tanpa kenaikan versi, pengguna tidak diberi tahu.
2. Commit, Push origin, lalu Actions > Build RekapRapi > Run workflow.
3. Selesai. Rilis dan catatan perubahannya muncul di
   `https://github.com/sofbusiness09/rekaprapi/releases`.

## Catatan perubahan

Diambil otomatis dari **judul commit** sejak rilis sebelumnya, satu baris per commit.
Tulis judul commit yang bisa dipahami pengguna, karena itulah yang mereka baca.

## Pembaruan wajib

Tulis `[wajib]` di judul salah satu commit, mis. `[wajib] Sesuaikan dengan database baru`.
Pengguna tidak bisa menunda atau menutup jendela pembaruan sampai versi baru terpasang.
Pakai hanya bila versi lama benar-benar rusak tanpa pembaruan.

## Alamat unduh tetap

`https://github.com/sofbusiness09/rekaprapi/releases/latest/download/RekapRapi.apk`
selalu mengarah ke APK terbaru. Alamat ini bisa dibagikan ke pengguna baru.

## Batasan

- Pengingat muncul saat aplikasi dibuka (paling sering tiap 6 jam), bukan notifikasi push.
- "Nanti" menunda pengingat versi yang sama selama sehari.
- Pengguna versi 1.0.15 ke bawah belum punya fitur ini; mereka memasang 1.0.16 secara manual sekali.
- Android meminta izin "Instal aplikasi tidak dikenal" untuk peramban pada pemasangan pertama.
- Menjalankan workflow dua kali dengan versi yang sama mengganti APK di rilis yang sama.
