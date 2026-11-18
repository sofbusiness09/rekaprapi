-- RekapRapi: tes mata uang pembukuan. Jalankan SETELAH migrasi 20261119000000.
-- Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES MATA UANG LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a2', 'ya@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b2', 'yb@test.local', now(), 'authenticated', 'authenticated');

reset role;
set local role service_role;
select public.tg_set_bot('UjiBot');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid; n int; failed boolean := false;
begin
  bid := public.create_business('Toko Dubai');
  perform set_config('t.biz', bid::text, true);
  perform set_config('t.code', public.telegram_create_code(bid) ->> 'code', true);
  if (select currency from public.businesses where id = bid) <> 'IDR' then
    raise exception 'GAGAL: bawaan bukan IDR';
  end if;

  update public.businesses set currency = 'AED' where id = bid;
  get diagnostics n = row_count;
  if n <> 1 or (select currency from public.businesses where id = bid) <> 'AED' then
    raise exception 'GAGAL: pemilik tidak bisa mengganti mata uang';
  end if;

  begin
    update public.businesses set currency = 'aed' where id = bid;
  exception when check_violation then failed := true; end;
  if not failed then raise exception 'GAGAL: kode huruf kecil diterima'; end if;
end $t$;

-- Staf tidak bisa mengganti mata uang.
reset role;
insert into public.business_members (business_id, user_id, role)
values (current_setting('t.biz')::uuid, '00000000-0000-0000-0000-0000000000b2', 'staff');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}', true);
set local role authenticated;
do $t$
declare n int;
begin
  update public.businesses set currency = 'USD' where id = current_setting('t.biz')::uuid;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'GAGAL: staf mengganti mata uang'; end if;
end $t$;

-- Bot Telegram menerima mata uang pembukuan.
reset role;
set local role service_role;
do $t$
declare ctx jsonb; batch jsonb;
begin
  perform public.tg_link(current_setting('t.code'), 333, 3330, 'Pemilik');
  ctx := public.tg_context(333);
  if ctx #>> '{business,currency}' <> 'AED' or ctx #>> '{businesses,0,currency}' <> 'AED' then
    raise exception 'GAGAL: mata uang di konteks bot %', ctx;
  end if;
  perform public.tg_record(333, '{"kind":"expense","amount":250}');
  batch := public.tg_daily_batch();
  if batch #>> '{0,business,currency}' <> 'AED' then
    raise exception 'GAGAL: mata uang di laporan harian %', batch;
  end if;
end $t$;

reset role;
select 'SEMUA TES MATA UANG LULUS' as hasil;
rollback;
