-- RekapRapi: pengaturan pribadi per akun yang ikut ke semua perangkat
-- (saat ini: pilihan Tampilan Beranda). Jalankan SETELAH 20261107000000 (dan tambalannya), sekali saja.
--
-- Satu baris per pengguna. Hanya pemiliknya yang bisa membaca dan menulis; anggota
-- usaha yang sama tidak bisa melihatnya.

create table public.user_settings (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  home_prefs  jsonb not null default '{}'::jsonb
              check (jsonb_typeof(home_prefs) = 'object' and pg_column_size(home_prefs) <= 2048),
  updated_at  timestamptz not null default now()
);

alter table public.user_settings enable row level security;

create policy user_settings_select on public.user_settings for select to authenticated
  using (user_id = auth.uid());
create policy user_settings_insert on public.user_settings for insert to authenticated
  with check (user_id = auth.uid());
create policy user_settings_update on public.user_settings for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select on public.user_settings to authenticated;
-- Upsert dari klien juga menyertakan user_id pada bagian "do update", jadi kolom itu
-- perlu hak ubah; kebijakan di atas tetap memastikan user_id harus milik pemanggil.
grant insert (user_id, home_prefs, updated_at) on public.user_settings to authenticated;
grant update (user_id, home_prefs, updated_at) on public.user_settings to authenticated;
