# Memasang RekapRapi di internet (versi web)

Hasil build ada di folder `dist\`:

- `dist\RekapRapi-web.zip` : satu berkas zip (sekitar 14 MB)
- `dist\RekapRapi-web\`    : isi yang sama dalam bentuk folder

Alamat Supabase dan kunci **publishable** sudah tertanam di build. Kunci itu memang dirancang
publik; data tetap dilindungi aturan RLS di database. Kunci rahasia (`sb_secret_...`) **tidak** ada di build.

## Cara A: Cloudflare Pages (gratis)

1. Buka https://dash.cloudflare.com dan masuk (atau daftar gratis).
2. Menu **Workers & Pages** > **Create** > tab **Pages** > **Upload assets** (Direct Upload).
3. Isi **Project name**, misalnya `rekaprapi`, lalu **Create project**.
4. Seret folder `RekapRapi-web` (atau berkas `RekapRapi-web.zip`) ke kotak unggah, lalu **Deploy site**.
5. Selesai. Alamatnya `https://rekaprapi.pages.dev` (sesuai nama proyek Anda).

## Cara B: Netlify (gratis)

1. Buka https://app.netlify.com/drop dan masuk (atau daftar gratis).
2. Seret folder `RekapRapi-web` ke halaman itu.
3. Alamat acak seperti `https://nama-acak.netlify.app` langsung aktif. Ganti namanya di
   **Site configuration** > **Change site name**.

## Wajib setelah situs aktif: beri tahu Supabase alamatnya

Tanpa ini, tautan verifikasi email dan reset password tidak kembali ke aplikasi dengan benar.

1. Supabase > **Authentication** > **URL Configuration**.
2. **Site URL**: isi alamat situs Anda, misalnya `https://rekaprapi.pages.dev`.
3. **Redirect URLs**: klik **Add URL**, isi `https://rekaprapi.pages.dev/**`.
   (Biarkan `http://localhost:5000/**` kalau masih ingin uji di komputer.)
4. **Save**.

## Memasang di ponsel tanpa APK

Buka alamat situs di Chrome ponsel, lalu menu titik tiga > **Tambahkan ke layar utama**
(atau **Instal aplikasi**). RekapRapi muncul seperti aplikasi biasa dengan ikonnya sendiri.

## Memperbarui versi

Setiap ada perubahan kode, build web dibuat ulang dan berkas baru diunggah lagi dengan cara yang
sama (di Cloudflare: **Create deployment**; di Netlify: seret folder baru ke tab **Deploys**).
Pengguna cukup memuat ulang halaman, kadang dua kali.

## Catatan

- Alamat memakai tanda `#` (misalnya `.../#/`). Itu normal untuk aplikasi ini.
- Situs bisa dibuka siapa saja, tetapi data hanya terlihat setelah masuk dengan akun, dan
  tiap akun hanya melihat usaha miliknya.
- Layanan hosting gratis cukup untuk pemakaian usaha kecil. Cek batas terbaru di situs masing-masing.
