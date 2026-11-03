-- RekapRapi: tes feed aktivitas Beranda. Jalankan SETELAH keempat migrasi.
-- Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES AKTIVITAS LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a3', 'aa@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000c3', 'ac@test.local', now(), 'authenticated', 'authenticated');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare
  bid uuid; cat uuid; cid uuid; d1 uuid; n int; failed boolean; r record;
begin
  bid := public.create_business('Toko Aktivitas');
  perform set_config('t.biz', bid::text, true);
  select id into cat from public.categories where business_id = bid and name = 'Pembelian Stok';
  insert into public.contacts (business_id, name, created_by) values (bid, 'Bu Evi', auth.uid()) returning id into cid;

  -- 1) kas keluar manual, 2) penjualan kredit 5.000, 3) pembayaran 2.000, 4) pinjaman uang 1.000
  insert into public.cash_transactions (business_id, type, amount, category_id, created_by, note)
  values (bid, 'out', 3000, cat, auth.uid(), 'beli stok');
  d1 := public.create_debt(bid, cid, 'receivable', 5000, false, current_date, null, null, true, 2000, 0, 0);
  perform public.pay_contact_debts(bid, cid, 'receivable', 2000);
  perform public.create_debt(bid, cid, 'receivable', 1000, true);

  select count(*) into n from public.recent_activity(bid, 50);
  if n <> 4 then raise exception 'GAGAL: harus 4 aktivitas (kas manual, hutang, pelunasan, pinjaman), dapat %', n; end if;

  if (select count(*) from public.recent_activity(bid, 50) where kind = 'credit') <> 1 then
    raise exception 'GAGAL: transaksi hutang harus tampil sekali';
  end if;

  -- Pinjaman uang tidak boleh muncul dua kali (catatan hutang + kas otomatis).
  if (select count(*) from public.recent_activity(bid, 50) where title = 'Pemberian Piutang') <> 1 then
    raise exception 'GAGAL: pinjaman tampil ganda atau hilang';
  end if;

  -- Pelunasan: arus masuk, bernama kontak, terhubung ke catatan hutang.
  select * into r from public.recent_activity(bid, 50) where title = 'Pelunasan Piutang';
  if r.flow <> 'in' or r.amount <> 2000 or r.contact_name <> 'Bu Evi' or r.debt_id <> d1 or not r.is_auto then
    raise exception 'GAGAL: baris pelunasan salah (%)', r;
  end if;

  -- Penjualan kredit: sisa dan keuntungan.
  select * into r from public.recent_activity(bid, 50) where kind = 'credit';
  if r.title <> 'Penjualan' or r.amount <> 5000 or r.remaining <> 3000 or r.profit <> 3000 or r.flow <> 'in' then
    raise exception 'GAGAL: baris penjualan kredit salah (%)', r;
  end if;

  -- Kas manual: tanpa kontak, bukan otomatis.
  select * into r from public.recent_activity(bid, 50) where title = 'Pembelian Stok';
  if r.contact_name is not null or r.is_auto or r.flow <> 'out' then
    raise exception 'GAGAL: baris kas manual salah (%)', r;
  end if;

  -- Batas dan lompatan.
  if (select count(*) from public.recent_activity(bid, 2)) <> 2 then raise exception 'GAGAL: limit tidak berlaku'; end if;
  if (select count(*) from public.recent_activity(bid, 50, 3)) <> 1 then raise exception 'GAGAL: offset tidak berlaku'; end if;

  -- Urutan terbaru dulu.
  if exists (
    select 1 from (select txn_date, created_at,
                          lag(txn_date) over (order by ord) as pd, lag(created_at) over (order by ord) as pc
                   from (select a.*, row_number() over () as ord from public.recent_activity(bid, 50) a) x) y
    where pd is not null and (txn_date > pd or (txn_date = pd and created_at > pc))
  ) then raise exception 'GAGAL: urutan bukan terbaru dulu'; end if;

  -- Catatan yang dihapus tidak tampil.
  perform public.delete_debt(d1);
  select count(*) into n from public.recent_activity(bid, 50);
  if n <> 2 then raise exception 'GAGAL: setelah hapus harus 2 aktivitas (kas manual, pinjaman), dapat %', n; end if;
end $t$;

-- Orang luar tidak boleh melihat.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare failed boolean := false;
begin
  begin perform * from public.recent_activity(current_setting('t.biz')::uuid, 10);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: orang luar membaca aktivitas'; end if;
end $t$;

reset role;
select 'SEMUA TES AKTIVITAS LULUS' as hasil;
rollback;
