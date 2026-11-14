-- RekapRapi: tes kategori tersering. Jalankan SETELAH migrasi 20261117000000.
-- Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES KATEGORI TERSERING LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a4', 'wa@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b4', 'wb@test.local', now(), 'authenticated', 'authenticated');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid; gaji uuid; sewa uuid; listrik uuid; ct uuid; n bigint;
begin
  bid := public.create_business('Toko Kategori');
  perform set_config('t.biz', bid::text, true);
  select id into gaji from public.categories where business_id = bid and name = 'Gaji';
  select id into sewa from public.categories where business_id = bid and name = 'Sewa';
  select id into listrik from public.categories where business_id = bid and name = 'Listrik & Air';

  if (select count(*) from public.category_usage(bid)) <> 0 then
    raise exception 'GAGAL: pembukuan baru harus kosong';
  end if;

  insert into public.cash_transactions (business_id, type, amount, category_id, txn_date, created_by) values
    (bid, 'out', 1000, gaji, current_date, auth.uid()),
    (bid, 'out', 1000, gaji, current_date - 10, auth.uid()),
    (bid, 'out', 1000, gaji, current_date - 89, auth.uid()),
    (bid, 'out', 1000, sewa, current_date, auth.uid()),
    (bid, 'out', 1000, sewa, current_date - 120, auth.uid()),   -- lebih dari 90 hari: tidak dihitung
    (bid, 'out', 1000, listrik, current_date - 200, auth.uid()),-- tidak dihitung
    (bid, 'out', 1000, null, current_date, auth.uid());         -- tanpa kategori

  -- Yang dihapus tidak dihitung.
  update public.cash_transactions set deleted_at = now()
   where id = (select id from public.cash_transactions
                where business_id = bid and category_id = gaji and txn_date = current_date - 10);

  if (select uses from public.category_usage(bid) where category_id = gaji) <> 2 then
    raise exception 'GAGAL: hitungan Gaji';
  end if;
  if (select uses from public.category_usage(bid) where category_id = sewa) <> 1 then
    raise exception 'GAGAL: hitungan Sewa';
  end if;
  if exists (select 1 from public.category_usage(bid) where category_id = listrik) then
    raise exception 'GAGAL: transaksi lama ikut dihitung';
  end if;

  -- Kas otomatis dari pinjaman tidak dihitung.
  insert into public.contacts (business_id, name, created_by) values (bid, 'Budi', auth.uid())
    returning id into ct;
  perform public.create_debt(bid, ct, 'receivable', 5000, true);
  select count(*) into n from public.category_usage(bid);
  if n <> 2 then raise exception 'GAGAL: kas otomatis ikut dihitung (% baris)', n; end if;
end $t$;

-- Bukan anggota ditolak.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b4","role":"authenticated"}', true);
set local role authenticated;
do $t$
declare failed boolean := false;
begin
  begin perform * from public.category_usage(current_setting('t.biz')::uuid);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: bukan anggota membaca pemakaian kategori'; end if;
end $t$;

reset role;
select 'SEMUA TES KATEGORI TERSERING LULUS' as hasil;
rollback;
