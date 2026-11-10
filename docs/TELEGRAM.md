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

## 6. Tahap 2: ringkasan, utang piutang, laporan harian

1. Jalankan `supabase/migrations/20261114000001_telegram_patch.sql` (bila belum) lalu
   `supabase/migrations/20261115000000_telegram_reports.sql` di SQL Editor.
2. Edge Functions > `telegram-bot` > Code: ganti seluruh isi dengan `index.ts` terbaru, Deploy.
3. Buka lagi alamat aktivasi (langkah 5) supaya daftar perintah di Telegram diperbarui.
4. Jadwalkan laporan harian. Di SQL Editor jalankan ini, dengan dua bagian dalam kurung sudut
   diganti (jangan simpan hasilnya di GitHub karena memuat rahasia):

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule('rekaprapi-telegram-harian', '0 13 * * *', $$
  select net.http_post(
    url := 'https://<ref-proyek>.supabase.co/functions/v1/telegram-bot',
    headers := '{"Content-Type":"application/json","X-Cron-Secret":"<TELEGRAM_WEBHOOK_SECRET>"}'::jsonb,
    body := '{}'::jsonb);
$$);
```

`0 13 * * *` adalah pukul 13.00 UTC, yaitu 20.00 WIB setiap hari. Untuk mengganti jam, jalankan
lagi dengan jadwal lain (nama yang sama menimpa jadwal lama). Untuk menghentikan:
`select cron.unschedule('rekaprapi-telegram-harian');`

Laporan hanya dikirim kepada akun yang hari itu punya catatan atau punya utang piutang yang jatuh
tempo sampai 3 hari ke depan. Tiap pengguna bisa mematikannya sendiri dengan `/laporan`.

## Memakai bot

```
jual 50000 modal 30000 kopi
jual 50000 modal 30000 utang Budi
masuk 25rb titipan
keluar 20000 listrik
piutang 100000 Budi, pinjam modal
utang 100000 Budi
```

- Jumlah boleh ditulis `50000`, `50.000`, `50rb`, `50k`, `1,5jt`.
- Bot selalu menanyakan konfirmasi (Simpan / Batal) sebelum menyimpan.
- Kata pertama catatan pengeluaran yang sama dengan nama kategori dipakai sebagai kategorinya.
- `piutang` = meminjamkan uang ke kontak, `utang` = menerima pinjaman dari kontak (keduanya menggerakkan kas).
  `jual ... utang Nama` = penjualan utang (piutang, belum masuk kas). Catatan ditulis setelah koma.
- Kontak dicocokkan dari nama (huruf besar kecil diabaikan). Nama yang belum ada dibuat sebagai kontak baru,
  dan itu disebut di pesan konfirmasi.
- `/hari_ini`, `/bulan_ini`, `/utang` menampilkan ringkasan. Staf tidak menerima angka pengeluaran dan laba.
- `/pembukuan` pindah pembukuan, `/batal` menghapus catatan terakhir dari bot (paling lama 30 menit),
  `/laporan` menghidupkan atau mematikan ringkasan harian, `/putuskan` memutuskan sambungan.
- Tanggal catatan memakai waktu Indonesia bagian barat (WIB).
- Belum bisa lewat bot: mencatat pembayaran atau cicilan utang piutang, diskon dan biaya tambahan, jatuh tempo.

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
