-- RekapRapi: tes penjualan, keuntungan, dan data grafik.
-- Jalankan SETELAH kedua migrasi (init dan sales_profit). Berjalan dalam transaksi
-- yang di-ROLLBACK. Sukses -> baris terakhir "SEMUA TES PENJUALAN LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a1', 'sa@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b1', 'sb@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000c1', 'sc@test.local', now(), 'authenticated', 'authenticated');

-- ===== A: pemilik, penjualan tunai dan kredit =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare
  bid uuid; cat uuid; cid uuid; s jsonb; n int; failed boolean; inv record;
begin
  bid := public.create_business('Toko Uji');
  perform set_config('t.biz', bid::text, true);

  if (select count(*) from public.categories where business_id = bid and is_sale and name = 'Penjualan') <> 1 then
    raise exception 'GAGAL: kategori Penjualan tidak ditandai sebagai penjualan';
  end if;
  select id into cat from public.categories where business_id = bid and is_sale;

  -- Total 100.000, diskon 10.000, biaya tambahan 5.000 => kas masuk 95.000.
  -- Modal 60.000 => keuntungan = jumlah (biaya tambahan ikut sebagai pemasukan) - modal
  -- = 95.000 - 60.000 = 35.000.
  insert into public.cash_transactions
    (business_id, type, amount, category_id, created_by, is_sale, cost_amount, discount_amount, extra_fee)
  values (bid, 'in', 95000, cat, auth.uid(), true, 60000, 10000, 5000);

  s := public.report_summary(bid, current_date, current_date);
  if (s ->> 'profit')::bigint <> 35000 then raise exception 'GAGAL: keuntungan tunai salah (%)', s; end if;
  if (s ->> 'sales_total')::bigint <> 95000 then raise exception 'GAGAL: total penjualan salah (%)', s; end if;
  if (s ->> 'balance')::bigint <> 95000 then raise exception 'GAGAL: saldo kas salah (%)', s; end if;

  -- Penjualan kredit 50.000, modal 20.000 => untung 30.000 (total 65.000); kas tidak berubah.
  insert into public.contacts (business_id, name, created_by) values (bid, 'Pembeli', auth.uid())
  returning id into cid;
  perform public.create_debt(bid, cid, 'receivable', 50000, false, current_date, null, null,
                             true, 20000, 0, 0);
  s := public.report_summary(bid, current_date, current_date);
  if (s ->> 'profit')::bigint <> 65000 then raise exception 'GAGAL: keuntungan kredit tidak terhitung (%)', s; end if;
  if (s ->> 'balance')::bigint <> 95000 then raise exception 'GAGAL: penjualan kredit mengubah kas (%)', s; end if;
  if (s ->> 'receivable_open')::bigint <> 50000 then raise exception 'GAGAL: piutang salah (%)', s; end if;

  -- Bukan penjualan tidak boleh membawa modal/diskon/biaya.
  failed := false;
  begin
    insert into public.cash_transactions (business_id, type, amount, created_by, cost_amount)
    values (bid, 'in', 1000, auth.uid(), 500);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: modal diterima pada transaksi non-penjualan'; end if;

  -- Biaya tambahan tidak boleh melebihi jumlah.
  failed := false;
  begin
    insert into public.cash_transactions (business_id, type, amount, created_by, is_sale, extra_fee)
    values (bid, 'in', 1000, auth.uid(), true, 2000);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: biaya tambahan melebihi jumlah diterima'; end if;

  -- Utang (payable) tidak boleh berupa penjualan.
  failed := false;
  begin
    perform public.create_debt(bid, cid, 'payable', 1000, false, current_date, null, null, true, 0, 0, 0);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: utang ditandai sebagai penjualan'; end if;

  -- Data harian untuk grafik.
  select count(*) into n from public.report_daily(bid, current_date - 6, current_date);
  if n <> 7 then raise exception 'GAGAL: report_daily harus 7 baris, dapat %', n; end if;
  if (select cash_in from public.report_daily(bid, current_date, current_date)) <> 95000
     or (select profit from public.report_daily(bid, current_date, current_date)) <> 65000 then
    raise exception 'GAGAL: nilai report_daily salah';
  end if;

  failed := false;
  begin perform * from public.report_daily(bid, current_date, current_date - 1);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: rentang terbalik diterima'; end if;

  select * into inv from public.create_invitation(bid, 'sb@test.local', 'staff');
  perform set_config('t.inv', inv.id::text, true);
end $t$;

-- ===== B (staf): boleh mencatat penjualan, tetapi tidak membuat kategori penjualan =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid := current_setting('t.biz')::uuid; cat uuid; failed boolean; s jsonb;
begin
  perform public.accept_invitation(current_setting('t.inv')::uuid);
  select id into cat from public.categories where business_id = bid and is_sale;
  insert into public.cash_transactions
    (business_id, type, amount, category_id, created_by, is_sale, cost_amount)
  values (bid, 'in', 10000, cat, auth.uid(), true, 4000);
  s := public.report_summary(bid, current_date, current_date);
  if (s ->> 'profit')::bigint <> 71000 then raise exception 'GAGAL: keuntungan setelah penjualan staf salah (%)', s; end if;

  failed := false;
  begin insert into public.categories (business_id, name, type, is_sale) values (bid, 'Jual X', 'in', true);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: staf membuat kategori'; end if;
end $t$;

-- ===== C (orang luar): tidak boleh membaca grafik =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid := current_setting('t.biz')::uuid; failed boolean := false;
begin
  begin perform * from public.report_daily(bid, current_date, current_date);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: orang luar membaca report_daily'; end if;
end $t$;

reset role;
select 'SEMUA TES PENJUALAN LULUS' as hasil;
rollback;
