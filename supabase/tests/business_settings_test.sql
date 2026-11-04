-- RekapRapi: tes pilihan tampilan per usaha (user_business_settings).
-- Jalankan SETELAH migrasi 20261110000000. Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES PENGATURAN USAHA LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a6', 'qa@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b6', 'qb@test.local', now(), 'authenticated', 'authenticated');

-- ===== A: punya dua usaha sendiri, pilihan tiap usaha terpisah =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a6","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare b1 uuid; b2 uuid; n int; failed boolean; v jsonb;
begin
  b1 := public.create_business('Usaha Satu');
  b2 := public.create_business('Usaha Dua');
  perform set_config('t.b1', b1::text, true);
  perform set_config('t.b2', b2::text, true);

  insert into public.user_business_settings (user_id, business_id, home_prefs, updated_at)
  values (auth.uid(), b1, '{"showProfit": false}', now()),
         (auth.uid(), b2, '{"showProfit": true, "txCredit": true}', now());

  -- Upsert seperti yang dilakukan aplikasi: konflik pada (user_id, business_id).
  insert into public.user_business_settings (user_id, business_id, home_prefs, updated_at)
  values (auth.uid(), b1, '{"showProfit": false, "activityCount": 15}', now())
  on conflict (user_id, business_id) do update
    set user_id = excluded.user_id, business_id = excluded.business_id,
        home_prefs = excluded.home_prefs, updated_at = excluded.updated_at;

  select count(*) into n from public.user_business_settings;
  if n <> 2 then raise exception 'GAGAL: harus satu baris per usaha, dapat %', n; end if;

  select home_prefs into v from public.user_business_settings where business_id = b1;
  if (v ->> 'activityCount')::int <> 15 then raise exception 'GAGAL: upsert usaha 1 tidak berubah (%)', v; end if;
  select home_prefs into v from public.user_business_settings where business_id = b2;
  if (v ->> 'txCredit')::boolean is not true then raise exception 'GAGAL: usaha 2 ikut berubah (%)', v; end if;

  -- Tidak boleh menulis atas nama orang lain.
  failed := false;
  begin
    insert into public.user_business_settings (user_id, business_id, home_prefs)
    values ('00000000-0000-0000-0000-0000000000b6', b1, '{}');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: A menulis pengaturan B'; end if;

  -- Batas isi: harus objek dan tidak terlalu besar.
  failed := false;
  begin update public.user_business_settings set home_prefs = '[1]'; exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: home_prefs bukan objek diterima'; end if;
  failed := false;
  begin update public.user_business_settings set home_prefs = jsonb_build_object('x', repeat('a', 6000)); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: home_prefs terlalu besar diterima'; end if;

  -- Usaha yang sudah dihapus (nonaktif): tidak bisa lagi menyimpan pilihan untuknya.
  perform public.delete_business(b2);
  failed := false;
  begin
    update public.user_business_settings set home_prefs = '{}' where business_id = b2;
    insert into public.user_business_settings (user_id, business_id, home_prefs)
    values (auth.uid(), b2, '{}') on conflict (user_id, business_id) do update set home_prefs = excluded.home_prefs;
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: pengaturan usaha yang sudah dihapus masih bisa diubah'; end if;
end $t$;

-- ===== B: bukan anggota usaha A, tidak bisa menyimpan atau melihat =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b6","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare failed boolean := false;
begin
  if (select count(*) from public.user_business_settings) <> 0 then
    raise exception 'GAGAL: B melihat pengaturan A';
  end if;
  begin
    insert into public.user_business_settings (user_id, business_id, home_prefs)
    values (auth.uid(), current_setting('t.b1')::uuid, '{}');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: B menyimpan pengaturan untuk usaha yang bukan miliknya'; end if;
end $t$;

-- ===== Tanpa login (anon) tidak bisa apa pun =====
set local role anon;
do $t$
declare failed boolean := false;
begin
  begin perform count(*) from public.user_business_settings; exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: anon membaca user_business_settings'; end if;
end $t$;

reset role;
select 'SEMUA TES PENGATURAN USAHA LULUS' as hasil;
rollback;
