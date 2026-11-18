# Lupa password dengan kode 6 angka

Sejak versi 1.0.16, aplikasi meminta **kode dari email**, bukan tautan. Supaya email
berisi kode, templat email Supabase perlu diganti sekali.

## Langkah

1. Supabase > **Authentication** > **Emails** (atau Email Templates) > **Reset Password**.
2. **Subject**: `Kode ganti password RekapRapi`
3. **Body**: ganti seluruh isinya dengan teks di bawah, lalu **Save**.

```html
<h2>Ganti password RekapRapi</h2>
<p>Masukkan kode berikut di aplikasi RekapRapi:</p>
<p style="font-size:28px;font-weight:bold;letter-spacing:6px">{{ .Token }}</p>
<p>Kode berlaku sebentar dan hanya bisa dipakai sekali. Bila Anda tidak meminta
ganti password, abaikan email ini; password Anda tidak berubah.</p>
```

`{{ .Token }}` diisi Supabase dengan kode angka. Jangan ubah tulisan itu.

## Catatan

- Panjang kode mengikuti pengaturan Supabase (bawaannya 6 angka). Aplikasi menerima 6 sampai 10 angka.
- Masa berlaku kode: Authentication > Providers > Email > **Email OTP Expiration**.
- Email lama yang masih berisi tautan tetap bisa dipakai di web. Bila tautannya sudah
  tidak berlaku sementara peramban sudah masuk, aplikasi sekarang memberi tahu,
  tidak lagi diam-diam membuka Rekapan.
- Mengirim kode baru membatalkan kode sebelumnya.
