-- RekapRapi: tes pengaturan Backup Google Sheet. Jalankan SETELAH migrasi 20261109000000.
-- Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES BACKUP LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a6', 'ka@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b6', 'kb@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000c6', 'kc@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000d6', 'kd@test.local', now(), 'authenticated', 'authenticated');

-- ===== A (pemilik): simpan, ubah, undang staf dan admin =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a6","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid; inv record; v record; failed boolean;
begin
  bid := public.create_business('Toko Backup');
  perform set_config('t.biz', bid::text, true);

  insert into public.backup_settings (business_id, script_url, token)
  values (bid, 'https://script.google.com/macros/s/AKfycbxABC_123-def/exec', 'abcdef0123456789abcdef0123456789');

  -- Upsert seperti yang dilakukan aplikasi (semua kolom payload ikut di-set).
  insert into public.backup_settings (business_id, script_url, token, spreadsheet_url, updated_at)
  values (bid, 'https://script.google.com/a/macros/contoh.com/s/AKfycbxXYZ/exec',
          'abcdef0123456789abcdef0123456789', 'https://docs.google.com/spreadsheets/d/FAKE/edit', now())
  on conflict (business_id) do update
    set business_id = excluded.business_id, script_url = excluded.script_url, token = excluded.token,
        spreadsheet_url = excluded.spreadsheet_url, updated_at = excluded.updated_at;
  if (select count(*) from public.backup_settings) <> 1 then raise exception 'GAGAL: harus satu baris per usaha'; end if;

  -- Mencatat hasil backup terakhir.
  update public.backup_settings
     set last_backup_at = now(), last_backup_by = auth.uid(), last_status = 'ok',
         last_summary = '{"Kas": 120, "Kontak": 7}', updated_at = now()
   where business_id = bid;
  select * into v from public.backup_settings where business_id = bid;
  if v.last_status <> 'ok' or (v.last_summary ->> 'Kas')::int <> 120 then raise exception 'GAGAL: hasil backup tidak tersimpan'; end if;

  -- Alamat selain Google Apps Script ditolak (mencegah data terkirim ke alamat lain).
  failed := false;
  begin update public.backup_settings set script_url = 'https://contoh.evil.com/exec' where business_id = bid;
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: alamat non-Google diterima'; end if;
  failed := false;
  begin update public.backup_settings set script_url = 'http://script.google.com/macros/s/AKfy/exec' where business_id = bid;
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: alamat http (bukan https) diterima'; end if;
  failed := false;
  begin update public.backup_settings set script_url = 'https://script.google.com/macros/s/AKfy/exec/../x' where business_id = bid;
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: alamat dengan ekor diterima'; end if;

  -- Kode rahasia terlalu pendek ditolak.
  failed := false;
  begin update public.backup_settings set token = 'pendek' where business_id = bid;
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: token pendek diterima'; end if;

  -- URL spreadsheet harus dari docs.google.com.
  failed := false;
  begin update public.backup_settings set spreadsheet_url = 'https://contoh.evil.com/sheet' where business_id = bid;
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: spreadsheet_url non-Google diterima'; end if;

  select * into inv from public.create_invitation(bid, 'kb@test.local', 'staff');
  perform set_config('t.inv_staff', inv.id::text, true);
  select * into inv from public.create_invitation(bid, 'kd@test.local', 'admin');
  perform set_config('t.inv_admin', inv.id::text, true);
end $t$;

-- ===== B (staf): tidak boleh melihat atau mengubah =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b6","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid := current_setting('t.biz')::uuid; failed boolean; n int;
begin
  perform public.accept_invitation(current_setting('t.inv_staff')::uuid);
  if (select count(*) from public.backup_settings) <> 0 then raise exception 'GAGAL: staf melihat kode rahasia backup'; end if;

  update public.backup_settings set last_status = 'x';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'GAGAL: staf mengubah pengaturan backup'; end if;

  failed := false;
  begin
    insert into public.backup_settings (business_id, script_url, token)
    values (bid, 'https://script.google.com/macros/s/AKfy/exec', 'abcdef0123456789abcdef0123456789');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: staf membuat pengaturan backup'; end if;

  delete from public.backup_settings;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'GAGAL: staf menghapus pengaturan backup'; end if;
end $t$;

-- ===== D (admin): boleh melihat dan mengubah =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d6","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare n int;
begin
  perform public.accept_invitation(current_setting('t.inv_admin')::uuid);
  if (select count(*) from public.backup_settings) <> 1 then raise exception 'GAGAL: admin tidak melihat pengaturan backup'; end if;
  update public.backup_settings set last_status = 'dari admin';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'GAGAL: admin tidak bisa mengubah pengaturan backup'; end if;
end $t$;

-- ===== C (orang luar): tidak melihat apa pun =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c6","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare failed boolean := false;
begin
  if (select count(*) from public.backup_settings) <> 0 then raise exception 'GAGAL: orang luar melihat pengaturan backup'; end if;
  begin
    insert into public.backup_settings (business_id, script_url, token)
    values (current_setting('t.biz')::uuid, 'https://script.google.com/macros/s/AKfy/exec', 'abcdef0123456789abcdef0123456789');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: orang luar membuat pengaturan backup'; end if;
end $t$;

reset role;
set local role anon;
do $t$
declare failed boolean := false;
begin
  begin perform count(*) from public.backup_settings; exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: anon membaca backup_settings'; end if;
end $t$;

reset role;
select 'SEMUA TES BACKUP LULUS' as hasil;
rollback;
