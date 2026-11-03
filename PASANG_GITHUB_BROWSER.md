# Memasang semuanya lewat GitHub (hanya dengan browser)

Satu kali jalan membangun **APK Android dan versi web sekaligus**. Tidak ada urutan "web dulu atau
APK dulu"; keduanya keluar dari alur kerja yang sama.

## Pilih dulu: repositori publik atau privat?

| | Publik | Privat |
|---|---|---|
| Kode terbaca orang lain | Ya (data tetap aman) | Tidak |
| Web di GitHub Pages (otomatis) | **Ya, gratis** | Tidak (butuh paket berbayar) |
| APK | Ya, dari Artifacts | Ya, dari Artifacts |
| Web di tempat lain | Tidak perlu | Cloudflare/Netlify (lihat `PASANG_WEB.md`) |

Yang terlihat publik hanyalah kode dan skema database. Isi data usaha ada di Supabase dan dilindungi
login. Kunci tanda tangan APK dan kata sandinya ada di GitHub Secrets, bukan di kode.

**Rekomendasi:** publik bila Anda tidak keberatan kodenya terbaca, karena web terpasang sendiri.

## 1. Buat repositori

1. Masuk ke https://github.com, klik tanda **+** di kanan atas > **New repository**.
2. **Repository name**: `rekaprapi`. Pilih **Public** atau **Private**.
3. **Jangan** mencentang README, .gitignore, atau license. Klik **Create repository**.

## 2. Unggah proyek (dua kali, karena GitHub membatasi 100 berkas per unggahan)

Berkas sudah dipilah di `D:\01 PROJECT\RekapRapi-upload`. Isinya tidak memuat kunci, APK, atau berkas besar.

1. Di halaman repositori yang masih kosong, klik **uploading an existing file**.
2. Buka folder `RekapRapi-upload\bagian-1`, tekan **Ctrl+A**, lalu **seret semuanya** ke kotak unggah.
   Tunggu sampai semua berkas tampil, lalu klik **Commit changes**.
3. Klik **Add file** > **Upload files**. Ulangi dengan isi folder `bagian-2` (**Ctrl+A**, seret, **Commit changes**).
4. Periksa di halaman repositori: harus ada folder `.github`, `android`, `assets`, `design`, `lib`,
   `supabase`, `test`, `tools`, `web`, dan berkas `pubspec.yaml`. Buka `.github/workflows` dan pastikan
   ada `build.yml`.

Setelah selesai, folder `RekapRapi-upload` boleh dihapus.

## 3. Isi Secrets dan Variables

Di repositori: **Settings** > **Secrets and variables** > **Actions**. Nilainya ada di
`secrets_local\github_secrets.txt` (jangan diunggah dan jangan dibagikan).

- Tab **Secrets** > **New repository secret**, empat kali: `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEYSTORE_BASE64`.
  Untuk `ANDROID_KEYSTORE_BASE64`, buka `secrets_local\ANDROID_KEYSTORE_BASE64.txt`, **Ctrl+A**,
  **Ctrl+C**, tempel seluruhnya.
- Tab **Variables** > **New repository variable**: `SUPABASE_URL` dan `SUPABASE_ANON_KEY`.
- **Khusus repositori publik, untuk web otomatis:**
  1. Tambah variabel `DEPLOY_PAGES` dengan nilai `true`.
  2. **Settings** > **Pages** > **Build and deployment** > **Source**: pilih **GitHub Actions**.

## 4. Jalankan

1. Tab **Actions** > **Build RekapRapi** > **Run workflow** (klik dua kali sesuai petunjuk di layar).
   Bila diminta, aktifkan Actions lebih dulu.
2. Tunggu sekitar 10 menit. Centang hijau di semua pekerjaan berarti selesai.
3. **APK**: buka hasil pembangunan, bagian **Artifacts** di paling bawah, unduh `RekapRapi-apk`.
4. **Web (publik)**: alamatnya `https://NAMA-AKUN-ANDA.github.io/rekaprapi/`
   (muncul juga di ringkasan pekerjaan **Pasang web ke GitHub Pages**).
   **Web (privat)**: unduh `RekapRapi-web` dari Artifacts lalu pasang seperti di `PASANG_WEB.md`.

## 5. Setelah web aktif

Beri tahu Supabase alamatnya: **Authentication** > **URL Configuration**. Isi **Site URL** dengan alamat web,
dan tambahkan **Redirect URL** `ALAMAT-WEB/**`. Tanpa ini tautan verifikasi email dan reset password salah.

## 6. Memasang APK di ponsel

Ekstrak zip, kirim `app-release.apk` ke ponsel, buka, izinkan pemasangan dari sumber tidak dikenal.
Bila Google Play Protect memperingatkan, pilih **Tetap instal**.

## 7. Memperbarui

Perubahan kode dilakukan lewat saya: saya buatkan berkas yang berubah, lalu Anda unggah ulang ke
repositori (klik berkasnya > ikon pensil, atau **Add file** > **Upload files** yang menimpa berkas lama),
naikkan baris `version:` di `pubspec.yaml` (angka setelah `+` harus lebih besar), lalu **Run workflow** lagi.

## Jika gagal

Buka **Actions**, klik pembangunan yang merah, klik langkah yang merah, salin tulisan galatnya ke saya.
