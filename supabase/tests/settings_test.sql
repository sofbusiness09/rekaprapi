-- RekapRapi: tes pengaturan pribadi (user_settings). Jalankan SETELAH migrasi 20261108000000.
-- Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES PENGATURAN LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a5', 'pa@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b5', 'pb@test.local', now(), 'authenticated', 'authenticated');

-- ===== A: menyimpan (insert lalu upsert seperti yang dilakukan aplikasi) =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a5","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare n int; failed boolean; v jsonb;
begin
  insert into public.user_settings (user_id, home_prefs, updated_at)
  values (auth.uid(), '{"showBalance": false, "activityCount": 5}', now());

  -- Upsert: pada konflik semua kolom payload ikut di-set, termasuk user_id.
  insert into public.user_settings (user_id, home_prefs, updated_at)
  values (auth.uid(), '{"showBalance": false, "activityCount": 10}', now())
  on conflict (user_id) do update
    set user_id = excluded.user_id, home_prefs = excluded.home_prefs, updated_at = excluded.updated_at;

  select home_prefs into v from public.user_settings where user_id = auth.uid();
  if (v ->> 'activityCount')::int <> 10 or (v ->> 'showBalance')::boolean then
    raise exception 'GAGAL: upsert tidak mengubah nilai (%)', v;
  end if;
  select count(*) into n from public.user_settings;
  if n <> 1 then raise exception 'GAGAL: harus satu baris per pengguna, dapat %', n; end if;

  -- Tidak boleh menulis atas nama orang lain.
  failed := false;
  begin
    insert into public.user_settings (user_id, home_prefs)
    values ('00000000-0000-0000-0000-0000000000b5', '{}');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: A menulis pengaturan B'; end if;

  -- Tidak boleh memindahkan baris sendiri ke pengguna lain.
  failed := false;
  begin
    update public.user_settings set user_id = '00000000-0000-0000-0000-0000000000b5';
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: A memindahkan barisnya ke B'; end if;

  -- Batas isi: harus objek dan tidak terlalu besar.
  failed := false;
  begin update public.user_settings set home_prefs = '[1,2,3]'; exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: home_prefs bukan objek diterima'; end if;
  failed := false;
  begin update public.user_settings set home_prefs = jsonb_build_object('x', repeat('a', 5000)); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: home_prefs terlalu besar diterima'; end if;
end $t$;

-- ===== B: tidak melihat milik A, punya baris sendiri =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b5","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare n int; failed boolean;
begin
  if (select count(*) from public.user_settings) <> 0 then raise exception 'GAGAL: B melihat pengaturan A'; end if;

  update public.user_settings set home_prefs = '{"showProfit": false}';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'GAGAL: B mengubah pengaturan A'; end if;

  insert into public.user_settings (user_id, home_prefs) values (auth.uid(), '{"showProfit": false}');
  if (select count(*) from public.user_settings) <> 1 then raise exception 'GAGAL: B harus melihat satu baris miliknya'; end if;
end $t$;

-- ===== Tanpa login (anon) tidak bisa apa pun =====
reset role;
set local role anon;
do $t$
declare failed boolean := false;
begin
  begin perform count(*) from public.user_settings; exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: anon membaca user_settings'; end if;
end $t$;

reset role;
select 'SEMUA TES PENGATURAN LULUS' as hasil;
rollback;
