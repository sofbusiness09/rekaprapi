# Membangun APK Android dan versi web di GitHub

GitHub menyediakan mesin yang sudah berisi Java dan Android SDK, jadi komputer Anda tidak perlu
memasang apa pun. Alur kerjanya ada di `.github/workflows/build.yml`.

Nilai yang perlu Anda tempel ke GitHub ada di `secrets_local\github_secrets.txt` dan
`secrets_local\ANDROID_KEYSTORE_BASE64.txt`. **Folder `secrets_local` tidak boleh diunggah** dan
sudah dikecualikan. Simpan cadangannya di tempat aman (USB atau pengelola password). Kalau kunci
tanda tangan hilang, APK versi baru tidak bisa dipasang menimpa versi lama.

## 1. Unggah proyek ke GitHub

Panduan lengkap lewat browser (tanpa GitHub Desktop), termasuk pilihan repositori publik atau privat,
ada di `PASANG_GITHUB_BROWSER.md`. Gunakan panduan itu untuk langkah 1 sampai 4; bagian di bawah ini
hanya ringkasan.

## 2. Isi Secrets dan Variables di GitHub

Di halaman repositori di github.com: **Settings** > **Secrets and variables** > **Actions**.

- Tab **Secrets** > **New repository secret** (4 kali). Ambil nama dan nilainya dari
  `secrets_local\github_secrets.txt`:
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEYSTORE_BASE64`.
  Untuk `ANDROID_KEYSTORE_BASE64`, buka `ANDROID_KEYSTORE_BASE64.txt`, tekan Ctrl+A lalu Ctrl+C,
  dan tempel seluruhnya (satu baris panjang).
- Tab **Variables** > **New repository variable** (2 kali): `SUPABASE_URL` dan `SUPABASE_ANON_KEY`
  (nilainya ada di berkas yang sama; kunci ini publik).

## 3. Jalankan pembangunan

1. Tab **Actions**. Bila diminta, klik tombol untuk mengaktifkan Actions.
2. Pilih **Build RekapRapi** di kiri, klik **Run workflow**, lalu **Run workflow** lagi.
3. Tunggu sekitar 8 sampai 12 menit. Centang hijau berarti berhasil.
4. Buka hasil pembangunannya. Di bagian **Artifacts** (paling bawah) ada:
   - `RekapRapi-apk` : zip berisi `app-release.apk`
   - `RekapRapi-web` : isi untuk Cloudflare/Netlify (lihat `PASANG_WEB.md`)

Hasil unduhan GitHub kedaluwarsa setelah 90 hari, jadi simpan salinannya.

## 4. Memasang APK di ponsel

1. Ekstrak zip, kirim `app-release.apk` ke ponsel (WhatsApp, Drive, atau kabel USB).
2. Buka berkasnya. Bila diminta, izinkan **Pasang dari sumber tidak dikenal** untuk aplikasi pembukanya.
3. Google Play Protect mungkin memperingatkan karena aplikasinya tidak dari Play Store.
   Pilih **Tetap instal**.

## 5. Memperbarui versi

1. Setelah kode berubah, di GitHub Desktop klik **Commit** lalu **Push origin**.
2. Naikkan nomor di `pubspec.yaml` pada baris `version:`, misalnya `1.0.1+2`. Angka setelah tanda `+`
   **harus lebih besar** dari sebelumnya, kalau tidak Android menolak memasangnya menimpa versi lama.
3. Jalankan lagi **Run workflow**.

## Jika gagal

Buka tab **Actions**, klik pembangunan yang bertanda merah, lalu klik langkah yang merah.
Salin tulisan galatnya dan kirim ke saya.

## Catatan

- Repositori privat gratis dengan jatah 2.000 menit per bulan. Satu pembangunan memakai sekitar 10 menit.
- Alur kerja ini belum pernah dijalankan di GitHub, jadi pembangunan pertama bisa menampilkan
  galat kecil yang perlu disesuaikan.
- Kunci tanda tangan dan kata sandinya hanya ada di komputer Anda dan di GitHub Secrets.
