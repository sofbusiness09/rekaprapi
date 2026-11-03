-- RekapRapi: tes pelunasan per kontak. Jalankan SETELAH ketiga migrasi.
-- Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES KONTAK LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a2', 'la@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000c2', 'lc@test.local', now(), 'authenticated', 'authenticated');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare
  bid uuid; c1 uuid; c2 uuid; c3 uuid; d1 uuid; d2 uuid; d3 uuid; s jsonb;
  paid bigint; n int; failed boolean;
begin
  bid := public.create_business('Toko Kontak');
  perform set_config('t.biz', bid::text, true);

  insert into public.contacts (business_id, name, created_by) values (bid, 'Bu Evi', auth.uid()) returning id into c1;
  insert into public.contacts (business_id, name, created_by) values (bid, 'Pak Budi', auth.uid()) returning id into c2;
  -- Kontak terpisah untuk utang: kontak yang sama akan saling mengompensasi (lihat netting_test).
  insert into public.contacts (business_id, name, created_by) values (bid, 'Toko Z', auth.uid()) returning id into c3;
  perform set_config('t.c1', c1::text, true);

  -- Dua piutang non-tunai untuk Bu Evi (100.000 lebih lama, 50.000 lebih baru) dan satu untuk Pak Budi.
  d1 := public.create_debt(bid, c1, 'receivable', 100000, false, current_date - 5);
  d2 := public.create_debt(bid, c1, 'receivable',  50000, false, current_date - 1);
  d3 := public.create_debt(bid, c2, 'receivable',  70000, false, current_date);

  s := public.report_summary(bid, current_date - 10, current_date);
  if (s ->> 'receivable_open')::bigint <> 220000 then raise exception 'GAGAL: total piutang awal salah (%)', s; end if;
  if (s ->> 'balance')::bigint <> 0 then raise exception 'GAGAL: kas awal harus 0 (%)', s; end if;

  -- Bayar sebagian: 120.000 => piutang tertua lunas (100.000), berikutnya terbayar 20.000.
  paid := public.pay_contact_debts(bid, c1, 'receivable', 120000, current_date, 'cicil');
  if paid <> 120000 then raise exception 'GAGAL: jumlah dibayar salah (%)', paid; end if;
  if (select remaining from public.debt_balances where id = d1) <> 0 then raise exception 'GAGAL: piutang tertua belum lunas'; end if;
  if (select remaining from public.debt_balances where id = d2) <> 30000 then raise exception 'GAGAL: piutang kedua harus tersisa 30000'; end if;
  if (select remaining from public.debt_balances where id = d3) <> 70000 then raise exception 'GAGAL: piutang kontak lain ikut terbayar'; end if;

  s := public.report_summary(bid, current_date - 10, current_date);
  if (s ->> 'balance')::bigint <> 120000 then raise exception 'GAGAL: kas harus bertambah 120000 (%)', s; end if;
  if (s ->> 'receivable_open')::bigint <> 100000 then raise exception 'GAGAL: sisa piutang salah (%)', s; end if;

  select count(*) into n from public.cash_transactions where business_id = bid and debt_payment_id is not null;
  if n <> 2 then raise exception 'GAGAL: harus ada 2 catatan kas pembayaran, dapat %', n; end if;

  -- Melebihi sisa ditolak dan tidak mengubah apa pun.
  failed := false;
  begin perform public.pay_contact_debts(bid, c1, 'receivable', 30001);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: pembayaran melebihi sisa diterima'; end if;
  failed := false;
  begin perform public.pay_contact_debts(bid, c1, 'receivable', 0);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: pembayaran nol diterima'; end if;

  -- Lunaskan sisanya (null = semua).
  paid := public.pay_contact_debts(bid, c1, 'receivable');
  if paid <> 30000 then raise exception 'GAGAL: lunaskan harus 30000, dapat %', paid; end if;
  s := public.report_summary(bid, current_date - 10, current_date);
  if (s ->> 'balance')::bigint <> 150000 then raise exception 'GAGAL: kas setelah lunas salah (%)', s; end if;

  -- Sudah lunas semua: tidak ada yang bisa dilunasi.
  failed := false;
  begin perform public.pay_contact_debts(bid, c1, 'receivable');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: kontak lunas masih bisa dilunasi'; end if;

  -- Utang (payable) mengurangi kas.
  perform public.create_debt(bid, c3, 'payable', 40000, false, current_date);
  paid := public.pay_contact_debts(bid, c3, 'payable', 15000);
  s := public.report_summary(bid, current_date - 10, current_date);
  if (s ->> 'balance')::bigint <> 135000 then raise exception 'GAGAL: pembayaran utang harus mengurangi kas (%)', s; end if;
  if (s ->> 'payable_open')::bigint <> 25000 then raise exception 'GAGAL: sisa utang salah (%)', s; end if;

  -- Memberi pinjaman uang (di luar penjualan): kas keluar, bukan penjualan.
  perform public.create_debt(bid, c2, 'receivable', 10000, true, current_date);
  s := public.report_summary(bid, current_date - 10, current_date);
  if (s ->> 'balance')::bigint <> 125000 then raise exception 'GAGAL: memberi pinjaman harus mengurangi kas (%)', s; end if;
  if (s ->> 'profit')::bigint <> 0 or (s ->> 'sales_total')::bigint <> 0 then
    raise exception 'GAGAL: pinjaman tercatat sebagai penjualan (%)', s;
  end if;

  -- View memuat kolom penjualan.
  perform is_sale, cost_amount, discount_amount, extra_fee from public.debt_balances limit 1;
end $t$;

-- Orang luar tidak boleh melunasi.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare failed boolean := false;
begin
  begin
    perform public.pay_contact_debts(current_setting('t.biz')::uuid, current_setting('t.c1')::uuid, 'receivable');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: orang luar melunasi utang'; end if;
end $t$;

reset role;
select 'SEMUA TES KONTAK LULUS' as hasil;
rollback;
