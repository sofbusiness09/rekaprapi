# Memasang Bot Telegram RekapRapi

Dikerjakan sekali oleh pemilik proyek Supabase. Pengguna aplikasi tidak perlu melakukan ini;
mereka cukup membuka Pengaturan > Telegram > Hubungkan.

## 1. Jalankan migrasi SQL

Di Supabase > SQL Editor, jalankan isi `supabase/migrations/20261114000000_telegram.sql`.

## 2. Buat bot di Telegram

1. Buka chat dengan **@BotFather**, kirim `/newbot`.
2. Isi nama bot (bebas) dan nama pengguna bot (harus berakhiran `bot`, misalnya `RekapRapiBot`).
3. BotFather memberi **token**. Token ini kunci bot: jangan dibagikan, jangan ditaruh di GitHub.

## 3. Pasang fungsi di Supabase

1. Supabase > **Edge Functions** > **Deploy a new function** > **Via Editor**.
2. Nama fungsi harus persis: `telegram-bot`.
3. Hapus isi contoh, tempel seluruh isi `supabase/functions/telegram-bot/index.ts`.
4. Matikan **Verify JWT** (Telegram tidak mengirim JWT; keaslian diperiksa dengan kode rahasia di langkah 4).
5. Tekan **Deploy**.

## 4. Isi rahasia

Supabase > Edge Functions > **Secrets**, tambahkan dua rahasia:

| Nama | Isi |
| --- | --- |
| `TELEGRAM_BOT_TOKEN` | token dari BotFather |
| `TELEGRAM_WEBHOOK_SECRET` | teks acak buatan sendiri, 20 karakter atau lebih, hanya huruf, angka, `_` atau `-` |

`SUPABASE_URL` dan `SUPABASE_SERVICE_ROLE_KEY` sudah tersedia otomatis, tidak perlu diisi.

## 5. Aktifkan

Buka sekali di peramban (ganti dua bagian dalam kurung sudut):

```
https://<ref-proyek>.supabase.co/functions/v1/telegram-bot?setup=<TELEGRAM_WEBHOOK_SECRET>
```

Jawaban yang benar: `{"ok":true,"webhook":"Webhook was set","bot":"NamaBotAnda"}`.
Setelah itu menu Pengaturan > Telegram di aplikasi menampilkan tombol **Hubungkan**.

Bila jawabannya hanya tulisan `RekapRapi bot`, kode di alamat tidak sama dengan rahasia yang disimpan.

## Memakai bot

```
jual 50000 modal 30000 kopi
masuk 25rb titipan
keluar 20000 listrik
```

- Jumlah boleh ditulis `50000`, `50.000`, `50rb`, `50k`, `1,5jt`.
- Bot selalu menanyakan konfirmasi (Simpan / Batal) sebelum menyimpan.
- Kata pertama catatan pengeluaran yang sama dengan nama kategori dipakai sebagai kategorinya.
- `/pembukuan` pindah pembukuan, `/batal` menghapus catatan terakhir dari bot (paling lama 30 menit), `/putuskan` memutuskan sambungan.
- Tanggal catatan memakai waktu Indonesia bagian barat (WIB).

## Keamanan

- Bot hanya melayani chat pribadi dan mengenali orang dari ID akun Telegram.
- Satu akun Telegram terikat ke satu akun RekapRapi, lewat kode sekali pakai yang berlaku 10 menit dan hanya bisa dibuat dari dalam aplikasi.
- Bot hanya bisa mencatat ke pembukuan yang pengguna itu masih menjadi anggotanya.
- Bila token bocor: di BotFather kirim `/revoke`, isi token baru di Secrets, lalu ulangi langkah 5.

## Menguji perubahan kode

```
node tools/telegram_parser_test.mjs
```

dan `supabase/tests/telegram_test.sql` pada database uji.
