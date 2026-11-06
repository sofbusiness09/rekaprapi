-- RekapRapi: tes dasar akuntansi baru (pemasukan, pengeluaran, laba) dan kategori.
-- Jalankan SETELAH migrasi 20261112000000. Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES AKUNTANSI LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a8', 'ac@test.local', now(), 'authenticated', 'authenticated');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a8","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare
  biz uuid; per uuid; cat_sale uuid; cat_other uuid; cat_gaji uuid; ct uuid; did uuid;
  s jsonb; n int; rec record; sum_inc bigint := 0; sum_exp bigint := 0; sum_net bigint := 0;
begin
  biz := public.create_business('Warung Bu Ani');
  perform set_config('t.biz', biz::text, true);

  -- Kategori awal Pembukuan Usaha: tanpa Pembelian Stok, ada Penjualan lainnya.
  if exists (select 1 from public.categories where business_id = biz and name = 'Pembelian Stok') then
    raise exception 'GAGAL: Pembelian Stok masih ada di pembukuan baru';
  end if;
  select id into cat_sale  from public.categories where business_id = biz and name = 'Penjualan';
  select id into cat_other from public.categories where business_id = biz and name = 'Penjualan lainnya';
  select id into cat_gaji  from public.categories where business_id = biz and name = 'Gaji';
  if cat_sale is null or cat_other is null or cat_gaji is null then
    raise exception 'GAGAL: kategori awal usaha tidak lengkap';
  end if;
  if exists (select 1 from public.categories where business_id = biz and name = 'Pemasukan Lain') then
    raise exception 'GAGAL: Pemasukan Lain harus bernama Penjualan lainnya';
  end if;

  insert into public.contacts (business_id, name, created_by) values (biz, 'Bu Ani', auth.uid())
    returning id into ct;

  -- Penjualan lunas: 3.000.000 (modal 2.000.000) dan 2.000.000 (modal 1.200.000).
  insert into public.cash_transactions (business_id, type, amount, category_id, txn_date, created_by,
                                        is_sale, cost_amount)
  values (biz, 'in', 3000000, cat_sale, date '2026-11-05', auth.uid(), true, 2000000),
         (biz, 'in', 2000000, cat_sale, date '2026-11-06', auth.uid(), true, 1200000);

  -- Penjualan utang 1.000.000 (modal 650.000), belum dibayar.
  did := public.create_debt(biz, ct, 'receivable', 1000000, false, date '2026-11-06', null, null,
                            true, 650000, 0, 0);

  -- Penjualan lainnya (jasa titip) 100.000.
  insert into public.cash_transactions (business_id, type, amount, category_id, txn_date, created_by)
  values (biz, 'in', 100000, cat_other, date '2026-11-07', auth.uid());

  -- Pengeluaran biasa: gaji 600.000, sewa/listrik 650.000.
  insert into public.cash_transactions (business_id, type, amount, category_id, txn_date, created_by)
  values (biz, 'out', 600000, cat_gaji, date '2026-11-08', auth.uid()),
         (biz, 'out', 650000, null,     date '2026-11-09', auth.uid());

  -- Pengeluaran berstatus hutang (beli kredit) 200.000: dihitung saat dicatat.
  perform public.create_debt(biz, ct, 'payable', 200000, false, date '2026-11-10');

  -- Pinjaman yang uangnya berpindah: TIDAK boleh masuk pemasukan atau pengeluaran.
  perform public.create_debt(biz, ct, 'payable', 300000, true, date '2026-11-10');     -- terima utang/modal
  perform public.create_debt(biz, ct, 'receivable', 400000, true, date '2026-11-10');  -- beri hutang uang

  -- Pelunasan sebagian piutang penjualan: kas otomatis, tidak menambah pemasukan lagi.
  perform public.add_debt_payment(did, 100000, date '2026-11-11');

  s := public.report_summary(biz, date '2026-11-01', date '2026-11-30');

  if (s ->> 'income_sales')::bigint   <> 6000000 then raise exception 'GAGAL: income_sales %', s; end if;
  if (s ->> 'income_other')::bigint   <> 100000  then raise exception 'GAGAL: income_other %', s; end if;
  if (s ->> 'income_total')::bigint   <> 6100000 then raise exception 'GAGAL: income_total %', s; end if;
  if (s ->> 'expense_cost')::bigint   <> 3850000 then raise exception 'GAGAL: expense_cost %', s; end if;
  if (s ->> 'expense_other')::bigint  <> 1450000 then raise exception 'GAGAL: expense_other %', s; end if;
  if (s ->> 'expense_credit')::bigint <> 200000  then raise exception 'GAGAL: expense_credit %', s; end if;
  if (s ->> 'expense_total')::bigint  <> 5300000 then raise exception 'GAGAL: expense_total %', s; end if;
  if (s ->> 'net')::bigint            <> 800000  then raise exception 'GAGAL: net %', s; end if;
  if (s ->> 'profit')::bigint         <> 2150000 then raise exception 'GAGAL: profit penjualan %', s; end if;
  if (s ->> 'sales_total')::bigint    <> 6000000 then raise exception 'GAGAL: sales_total %', s; end if;

  -- Grafik harian: jumlahnya harus sama dengan ringkasan.
  for rec in select * from public.report_daily_pl(biz, date '2026-11-01', date '2026-11-30') loop
    sum_inc := sum_inc + rec.income; sum_exp := sum_exp + rec.expense; sum_net := sum_net + rec.net;
    if rec.net <> rec.income - rec.expense then raise exception 'GAGAL: net harian %', rec; end if;
  end loop;
  if sum_inc <> 6100000 or sum_exp <> 5300000 or sum_net <> 800000 then
    raise exception 'GAGAL: grafik harian tidak cocok dengan ringkasan (% % %)', sum_inc, sum_exp, sum_net;
  end if;
  select count(*) into n from public.report_daily_pl(biz, date '2026-11-01', date '2026-11-30');
  if n <> 30 then raise exception 'GAGAL: harus 30 hari, dapat %', n; end if;

  -- Diagram per kategori: total pemasukan dan pengeluaran harus sama dengan ringkasan.
  select coalesce(sum(total), 0) into n from public.report_pl_by_category(biz, date '2026-11-01', date '2026-11-30') where type = 'in';
  if n <> 6100000 then raise exception 'GAGAL: diagram pemasukan % (harus 6100000)', n; end if;
  select coalesce(sum(total), 0) into n from public.report_pl_by_category(biz, date '2026-11-01', date '2026-11-30') where type = 'out';
  if n <> 5300000 then raise exception 'GAGAL: diagram pengeluaran % (harus 5300000)', n; end if;
  if not exists (select 1 from public.report_pl_by_category(biz, date '2026-11-01', date '2026-11-30')
                  where category_name = 'Modal barang' and total = 3850000) then
    raise exception 'GAGAL: irisan Modal barang';
  end if;

  -- Periode lain tidak terpengaruh.
  s := public.report_summary(biz, date '2026-12-01', date '2026-12-31');
  if (s ->> 'net')::bigint <> 0 or (s ->> 'income_total')::bigint <> 0 then
    raise exception 'GAGAL: Desember harus kosong %', s;
  end if;

  -- Menghapus penjualan utang mengurangi pemasukan dan modalnya.
  perform public.delete_debt(did);
  s := public.report_summary(biz, date '2026-11-01', date '2026-11-30');
  if (s ->> 'income_sales')::bigint <> 5000000 or (s ->> 'expense_cost')::bigint <> 3200000 then
    raise exception 'GAGAL: setelah hapus penjualan utang %', s;
  end if;

  -- Keuntungan di aktivitas terbaru = jumlah - modal (biaya tambahan ikut sebagai pemasukan).
  insert into public.cash_transactions (business_id, type, amount, category_id, txn_date, created_by,
                                        is_sale, cost_amount, extra_fee)
  values (biz, 'in', 55000, cat_sale, date '2026-11-12', auth.uid(), true, 30000, 5000);
  select profit into rec from public.recent_activity(biz, 1, 0);
  if rec.profit <> 25000 then raise exception 'GAGAL: profit aktivitas % (harus 25000)', rec.profit; end if;

  -- Pembukuan pribadi tidak punya Penjualan lainnya, hanya kategori pribadi.
  per := public.create_business('Pribadi', null, null, 'personal');
  if exists (select 1 from public.categories where business_id = per and name = 'Penjualan lainnya') then
    raise exception 'GAGAL: pribadi tidak boleh punya Penjualan lainnya';
  end if;
end $t$;

-- ===== Pembersihan kategori Pembelian Stok pada data lama =====
reset role;
do $t$
declare
  b1 uuid := gen_random_uuid(); b2 uuid := gen_random_uuid(); c1 uuid; c2 uuid; n int;
begin
  insert into public.businesses (id, name, kind) values (b1, 'Lama kosong', 'business'), (b2, 'Lama terpakai', 'business');
  insert into public.categories (business_id, name, type) values (b1, 'Pembelian Stok', 'out'), (b1, 'Pemasukan Lain', 'in');
  insert into public.categories (business_id, name, type) values (b2, 'Pembelian Stok', 'out') returning id into c2;
  insert into public.cash_transactions (business_id, type, amount, category_id, txn_date)
    values (b2, 'out', 1000, c2, current_date);

  -- Jalankan lagi bagian pembersihan migrasi.
  delete from public.categories c
  where c.name = 'Pembelian Stok' and not c.is_system
    and not exists (select 1 from public.cash_transactions t where t.category_id = c.id);
  update public.categories c set name = 'Penjualan lainnya'
   where c.name = 'Pemasukan Lain' and c.type = 'in' and not c.is_system
     and exists (select 1 from public.businesses b where b.id = c.business_id and b.kind = 'business')
     and not exists (select 1 from public.categories x
                      where x.business_id = c.business_id and x.type = 'in' and x.name = 'Penjualan lainnya');

  select count(*) into n from public.categories where business_id = b1 and name = 'Pembelian Stok';
  if n <> 0 then raise exception 'GAGAL: Pembelian Stok yang tak terpakai harus terhapus'; end if;
  select count(*) into n from public.categories where business_id = b2 and name = 'Pembelian Stok';
  if n <> 1 then raise exception 'GAGAL: Pembelian Stok yang masih dipakai harus tetap ada'; end if;
  select count(*) into n from public.categories where business_id = b1 and name = 'Penjualan lainnya';
  if n <> 1 then raise exception 'GAGAL: Pemasukan Lain harus berganti nama'; end if;
end $t$;

select 'SEMUA TES AKUNTANSI LULUS' as hasil;
rollback;
