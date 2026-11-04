# RekapRapi

Aplikasi Android + Web untuk pencatatan kas dan utang piutang, dengan banyak usaha dan tim.
Teknologi: Flutter + Supabase.

Status: **Tahap 0 selesai, Tahap 1a dimulai** (lihat "Status" di bawah).

## Struktur

```
supabase/migrations/20261103000000_init.sql   skema, RLS, fungsi (RPC), trigger
supabase/migrations/20261104000000_sales_profit.sql   penjualan: modal, diskon, biaya tambahan, keuntungan, data grafik
supabase/migrations/20261105000000_contact_ledger.sql  pelunasan per kontak (Lunaskan / terima pembayaran otomatis)
supabase/migrations/20261106000000_recent_activity.sql  feed aktivitas uang untuk Beranda
supabase/migrations/20261107000000_contact_netting.sql  saldo bersih per kontak (piutang vs utang), kelola kontak
supabase/tests/netting_test.sql               tes saldo bersih dan kontak
supabase/migrations/20261107000001_netting_patch.sql  tambalan aman-diulang untuk migrasi 20261107000000
supabase/migrations/20261108000000_user_settings.sql  pengaturan pribadi per akun (Tampilan Beranda ikut ke semua perangkat)
supabase/tests/settings_test.sql              tes pengaturan pribadi
supabase/migrations/20261109000000_backup_settings.sql  pengaturan Backup Google Sheet per usaha (alamat skrip + kode rahasia)
supabase/migrations/20261110000000_business_settings.sql  tampilan Beranda dan Transaksi per usaha (tiap usaha punya pilihan sendiri)
supabase/tests/backup_test.sql                tes pengaturan backup
assets/backup_apps_script.gs                  skrip Google Apps Script yang ditempel pengguna di Google Sheet-nya
tools/apps_script_harness.js                menguji skrip itu dengan tiruan Google Sheet (Node): node tools/apps_script_harness.js assets/backup_apps_script.gs [build/backup_test/payload.json]
supabase/tests/ledger_test.sql                tes pelunasan per kontak
supabase/tests/activity_test.sql              tes feed aktivitas
supabase/tests/rls_test.sql                   tes hak akses dan sinkron kas
supabase/tests/sales_test.sql                 tes penjualan dan keuntungan
lib/                                          aplikasi Flutter (login, pemilih usaha)
pubspec.yaml
```

## Memasang dan membangun

- Versi web online: lihat `PASANG_WEB.md`
- APK Android lewat GitHub Actions: lihat `PASANG_ANDROID_GITHUB.md`

## 1. Siapkan Supabase

1. Buat proyek di https://supabase.com (paket gratis cukup).
2. **Authentication > Providers > Email**: aktifkan, dan **biarkan "Confirm email" menyala**.
   Penerimaan undangan lewat email mengandalkan email yang sudah terverifikasi.
3. **SQL Editor**: tempel isi `supabase/migrations/20261103000000_init.sql`, lalu Run.
4. Untuk menguji: tempel `supabase/tests/rls_test.sql` dan Run. Hasil yang diharapkan:
   satu baris `SEMUA TES LULUS`. Tes berjalan dalam transaksi yang di-rollback,
   tetapi sebaiknya tetap dijalankan di proyek pengembangan.
5. **Project Settings > API**: catat `Project URL` dan `anon public` key.
   Jangan memakai `service_role` key di aplikasi.

## 2. Jalankan aplikasi

Prasyarat: Flutter SDK 3.27+ (https://docs.flutter.dev/get-started/install).

```bash
flutter create . --platforms=android,web --project-name rekap_rapi
flutter pub get
flutter run -d chrome --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
```

`flutter create .` hanya menambahkan folder `android/` dan `web/`; berkas yang sudah ada
(`pubspec.yaml`, `lib/main.dart`) tidak ditimpa.

Di Supabase, tambahkan URL aplikasi web Anda (mis. `http://localhost:xxxx` untuk uji) pada
**Authentication > URL Configuration** agar tautan verifikasi email dan reset password kembali ke aplikasi.

## Aturan penting (hasil rancangan)

- Semua data milik **usaha**. Peran per usaha: Pemilik, Admin, Staf.
- Satu akun maksimal **memiliki 5 usaha** (menjadi anggota usaha orang lain tidak dihitung).
- Utang piutang dan kas **tersinkron**: kas otomatis dibuat/diubah/dihapus oleh fungsi database
  (`create_debt`, `add_debt_payment`, dst). Transaksi kas otomatis tidak bisa diubah langsung.
- Klien tidak punya izin tulis langsung ke anggota, undangan, utang, dan cicilan; semuanya lewat RPC.

## Status

| Tahap | Isi | Status |
|---|---|---|
| 0 | Skema, RLS, RPC, tes SQL | Ditulis, **belum dijalankan** |
| 1a | Login, pemilih usaha | Kerangka ditulis, **belum dikompilasi** |
| 1b | Anggota, undangan, riwayat aktivitas (UI) | Ditulis di Pengaturan, **belum dikompilasi** |
| 2 | Pencatatan kas (UI): beranda, daftar per bulan, tambah/ubah/hapus, realtime | Ditulis, **belum dikompilasi** |
| 3 | Utang piutang (UI): daftar, catat, cicilan/pelunasan, sinkron kas | Ditulis, **belum dikompilasi** |
| 4 | Laporan, ekspor Excel/CSV, pengaturan (profil, kategori, akun) | Ditulis, **belum dikompilasi** |
| 5 | Ekspor Google Sheet, rilis web dan APK | Belum |

## Catatan keamanan

- Staf dapat melihat semua transaksi usaha (keputusan produk). Larangan ekspor untuk Staf
  hanya ada di antarmuka, bukan di database.
- Fungsi baru yang Anda tambahkan di skema `public` bisa dipanggil siapa saja secara default.
  Untuk setiap fungsi baru jalankan `revoke execute ... from public, anon;` lalu beri grant seperlunya.
- Menghapus akun pemilik tidak menghapus usahanya; fitur hapus akun perlu dirancang tersendiri.
