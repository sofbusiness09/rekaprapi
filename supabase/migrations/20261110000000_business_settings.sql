-- RekapRapi: pilihan tampilan per usaha (Beranda dan tab Transaksi).
-- Jalankan SETELAH 20261109000000_backup_settings.sql, sekali saja.
--
-- Sebelumnya satu akun hanya punya satu pilihan tampilan (user_settings). Sekarang
-- tiap usaha punya pilihan sendiri, sehingga usaha milik sendiri dan usaha dari
-- undangan bisa ditampilkan berbeda. Satu baris per (pengguna, usaha); hanya
-- pemiliknya yang bisa membaca dan menulis, dan hanya selama ia anggota usaha itu.

create table public.user_business_settings (
  user_id      uuid not null references auth.users (id) on delete cascade,
  business_id  uuid not null references public.businesses (id) on delete cascade,
  home_prefs   jsonb not null default '{}'::jsonb
               check (jsonb_typeof(home_prefs) = 'object' and pg_column_size(home_prefs) <= 4096),
  updated_at   timestamptz not null default now(),
  primary key (user_id, business_id)
);

alter table public.user_business_settings enable row level security;

create policy user_business_settings_select on public.user_business_settings
  for select to authenticated
  using (user_id = auth.uid());
create policy user_business_settings_insert on public.user_business_settings
  for insert to authenticated
  with check (user_id = auth.uid() and public.is_member(business_id));
create policy user_business_settings_update on public.user_business_settings
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.is_member(business_id));

grant select on public.user_business_settings to authenticated;
-- Upsert dari klien juga menyertakan kolom kunci pada bagian "do update".
grant insert (user_id, business_id, home_prefs, updated_at)
  on public.user_business_settings to authenticated;
grant update (user_id, business_id, home_prefs, updated_at)
  on public.user_business_settings to authenticated;
