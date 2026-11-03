-- RekapRapi: pengaturan Backup ke Google Sheet (per usaha).
-- Jalankan SETELAH 20261108000000_user_settings.sql, sekali saja.
--
-- Backup dikirim dari aplikasi ke Google Apps Script milik pemilik yang menempel pada
-- Google Sheet-nya. Tabel ini menyimpan alamat skrip, kode rahasia, dan hasil backup
-- terakhir. Hanya Pemilik dan Admin yang bisa membaca atau mengubahnya (kode rahasia
-- cukup untuk menulis ke Sheet itu, jadi tidak boleh terlihat oleh Staf).

create table public.backup_settings (
  business_id      uuid primary key references public.businesses (id) on delete cascade,
  -- Hanya alamat Web App Google Apps Script yang diterima, agar data tidak
  -- terkirim ke alamat lain karena salah tempel.
  script_url       text not null
                   check (script_url ~ '^https://script\.google\.com/(a/macros/[^/]+|macros)/s/[A-Za-z0-9_-]+/exec$'),
  token            text not null check (char_length(token) between 16 and 128),
  spreadsheet_url  text check (spreadsheet_url is null
                               or spreadsheet_url ~ '^https://docs\.google\.com/spreadsheets/'),
  last_backup_at   timestamptz,
  last_backup_by   uuid references auth.users (id) on delete set null,
  last_status      text,
  last_summary     jsonb check (last_summary is null or pg_column_size(last_summary) <= 4096),
  updated_at       timestamptz not null default now()
);

alter table public.backup_settings enable row level security;

create policy backup_select on public.backup_settings for select to authenticated
  using (public.is_admin_or_owner(business_id));
create policy backup_insert on public.backup_settings for insert to authenticated
  with check (public.is_admin_or_owner(business_id));
create policy backup_update on public.backup_settings for update to authenticated
  using (public.is_admin_or_owner(business_id))
  with check (public.is_admin_or_owner(business_id));
create policy backup_delete on public.backup_settings for delete to authenticated
  using (public.is_admin_or_owner(business_id));

grant select, delete on public.backup_settings to authenticated;
grant insert (business_id, script_url, token, spreadsheet_url, updated_at)
  on public.backup_settings to authenticated;
-- Upsert dari klien menyertakan business_id pada bagian "do update"; kebijakan di atas
-- tetap memastikan pemanggil harus Pemilik/Admin usaha itu.
grant update (business_id, script_url, token, spreadsheet_url,
              last_backup_at, last_backup_by, last_status, last_summary, updated_at)
  on public.backup_settings to authenticated;
