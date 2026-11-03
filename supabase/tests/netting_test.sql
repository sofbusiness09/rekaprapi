-- RekapRapi: tes saldo bersih per kontak (utang vs piutang) dan pengelolaan kontak.
-- Jalankan SETELAH kelima migrasi. Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES SALDO KONTAK LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a4', 'na@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b4', 'nb@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000c4', 'nc@test.local', now(), 'authenticated', 'authenticated');

-- ===== A (pemilik) =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare
  bid uuid; c1 uuid; c2 uuid; sale1 uuid; sale2 uuid; s jsonb; j jsonb; n int;
  failed boolean; inv record; pay uuid;
begin
  bid := public.create_business('Toko Saldo');
  perform set_config('t.biz', bid::text, true);
  insert into public.contacts (business_id, name, phone, created_by) values (bid, 'Bu Evi', '0811', auth.uid()) returning id into c1;
  insert into public.contacts (business_id, name, created_by) values (bid, 'Pak Budi', auth.uid()) returning id into c2;
  perform set_config('t.c1', c1::text, true);

  -- 1) Bu Evi memberi utang/modal 100.000 (tanpa piutang): Anda berutang kepadanya, kas masuk.
  j := public.contact_transfer(bid, c1, 'receive', 100000);
  if (j ->> 'settled')::bigint <> 0 or (j ->> 'new_debt')::bigint <> 100000 then raise exception 'GAGAL: utang salah (%)', j; end if;
  s := public.report_summary(bid, current_date - 5, current_date);
  if (s ->> 'balance')::bigint <> 100000 then raise exception 'GAGAL: kas setelah utang (%)', s; end if;
  if (s ->> 'payable_open')::bigint <> 100000 then raise exception 'GAGAL: utang (%)', s; end if;

  -- 2) Penjualan kredit 60.000 (modal 20.000): otomatis mengurangi utang, kas tidak berubah.
  sale1 := public.create_debt(bid, c1, 'receivable', 60000, false, current_date, null, null, true, 20000, 0, 0);
  s := public.report_summary(bid, current_date - 5, current_date);
  if (s ->> 'payable_open')::bigint <> 40000 then raise exception 'GAGAL: utang harus tersisa 40000 (%)', s; end if;
  if (s ->> 'receivable_open')::bigint <> 0 then raise exception 'GAGAL: piutang harus 0 (%)', s; end if;
  if (s ->> 'balance')::bigint <> 100000 then raise exception 'GAGAL: kompensasi mengubah kas (%)', s; end if;
  if (s ->> 'profit')::bigint <> 40000 then raise exception 'GAGAL: keuntungan penjualan harus tetap 40000 (%)', s; end if;
  if (select remaining from public.debt_balances where id = sale1) <> 0 then raise exception 'GAGAL: penjualan harus lunas oleh utang'; end if;
  select count(*) into n from public.cash_transactions where business_id = bid and debt_payment_id is not null;
  if n <> 0 then raise exception 'GAGAL: kompensasi tidak boleh membuat catatan kas, dapat %', n; end if;

  -- 3) Penjualan kredit 70.000: utang 40.000 habis, sisa piutang 30.000.
  sale2 := public.create_debt(bid, c1, 'receivable', 70000, false, current_date, null, null, true, 30000, 0, 0);
  s := public.report_summary(bid, current_date - 5, current_date);
  if (s ->> 'payable_open')::bigint <> 0 then raise exception 'GAGAL: utang harus habis (%)', s; end if;
  if (s ->> 'receivable_open')::bigint <> 30000 then raise exception 'GAGAL: piutang harus 30000 (%)', s; end if;
  if (s ->> 'balance')::bigint <> 100000 then raise exception 'GAGAL: kas berubah (%)', s; end if;

  -- 4) Terima 50.000: melunasi piutang 30.000 (kas masuk), kelebihan 20.000 jadi utang baru.
  j := public.contact_transfer(bid, c1, 'receive', 50000);
  if (j ->> 'settled')::bigint <> 30000 or (j ->> 'new_debt')::bigint <> 20000 then raise exception 'GAGAL: terima 50000 (%)', j; end if;
  s := public.report_summary(bid, current_date - 5, current_date);
  if (s ->> 'balance')::bigint <> 150000 then raise exception 'GAGAL: kas harus 150000 (%)', s; end if;
  if (s ->> 'receivable_open')::bigint <> 0 or (s ->> 'payable_open')::bigint <> 20000 then raise exception 'GAGAL: saldo setelah terima (%)', s; end if;

  -- 5) Berikan 5.000: membayar utang (kas keluar).
  j := public.contact_transfer(bid, c1, 'give', 5000);
  if (j ->> 'settled')::bigint <> 5000 or (j ->> 'new_debt')::bigint <> 0 then raise exception 'GAGAL: berikan 5000 (%)', j; end if;
  s := public.report_summary(bid, current_date - 5, current_date);
  if (s ->> 'balance')::bigint <> 145000 or (s ->> 'payable_open')::bigint <> 15000 then raise exception 'GAGAL: saldo setelah berikan (%)', s; end if;

  -- 6) Berikan 25.000 > utang 15.000: utang lunas, kelebihan 10.000 jadi pinjaman (piutang).
  j := public.contact_transfer(bid, c1, 'give', 25000);
  if (j ->> 'settled')::bigint <> 15000 or (j ->> 'new_debt')::bigint <> 10000 then raise exception 'GAGAL: berikan 25000 (%)', j; end if;
  s := public.report_summary(bid, current_date - 5, current_date);
  if (s ->> 'balance')::bigint <> 120000 then raise exception 'GAGAL: kas harus 120000 (%)', s; end if;
  if (s ->> 'receivable_open')::bigint <> 10000 or (s ->> 'payable_open')::bigint <> 0 then raise exception 'GAGAL: saldo akhir (%)', s; end if;

  -- 7) Lunaskan: piutang 10.000 diterima.
  if public.settle_contact(bid, c1) <> 10000 then raise exception 'GAGAL: settle harus 10000'; end if;
  s := public.report_summary(bid, current_date - 5, current_date);
  if (s ->> 'balance')::bigint <> 130000 or (s ->> 'receivable_open')::bigint <> 0 then raise exception 'GAGAL: setelah lunas (%)', s; end if;
  failed := false;
  begin perform public.settle_contact(bid, c1); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: kontak lunas masih bisa dilunasi'; end if;

  -- 8) Pak Budi: memberi utang/modal 100.000, penjualan kredit 60.000 dikompensasi, lalu penjualan dihapus
  --    => utang kembali 100.000 (pasangan kompensasi ikut terhapus).
  perform public.contact_transfer(bid, c2, 'receive', 100000);
  sale1 := public.create_debt(bid, c2, 'receivable', 60000, false, current_date, null, null, true, 10000, 0, 0);
  if (select coalesce(sum(remaining), 0) from public.debt_balances where contact_id = c2 and kind = 'payable') <> 40000 then
    raise exception 'GAGAL: utang Pak Budi harus 40000 setelah kompensasi';
  end if;
  perform public.delete_debt(sale1);
  if (select coalesce(sum(remaining), 0) from public.debt_balances where contact_id = c2 and kind = 'payable') <> 100000 then
    raise exception 'GAGAL: menghapus penjualan harus membayar utang 100000';
  end if;

  -- 9) Kompensasi otomatis tidak bisa diubah/dihapus sendiri (menjaga saldo satu arah).
  sale2 := public.create_debt(bid, c2, 'receivable', 30000, false, current_date);
  select p.id into pay from public.debt_payments p
   join public.debts d on d.id = p.debt_id
   where d.contact_id = c2 and d.kind = 'payable' and p.method = 'offset' and p.deleted_at is null limit 1;
  failed := false;
  begin perform public.update_debt_payment(pay, 1, current_date, null); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: kompensasi bisa diubah'; end if;
  failed := false;
  begin perform public.delete_debt_payment(pay); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: kompensasi bisa dihapus sendiri'; end if;
  if (select remaining from public.debt_balances where id = sale2) <> 0 then raise exception 'GAGAL: penjualan harus tetap lunas oleh utang'; end if;
  if (select coalesce(sum(remaining), 0) from public.debt_balances where contact_id = c2 and kind = 'payable') <> 70000 then
    raise exception 'GAGAL: utang harus 70000 setelah kompensasi 30000';
  end if;

  -- 10) Tidak pernah ada piutang dan utang terbuka bersamaan pada satu kontak.
  if exists (
    select 1 from public.debt_balances a join public.debt_balances b
      on a.contact_id = b.contact_id and a.kind = 'receivable' and b.kind = 'payable'
    where a.remaining > 0 and b.remaining > 0
  ) then raise exception 'GAGAL: kontak punya piutang dan utang terbuka bersamaan'; end if;

  -- 11) Kontak: ubah data, hapus hanya tanpa saldo.
  update public.contacts set phone = '0822', address = 'Jl. Mawar 1', note = 'langganan' where id = c1;
  if (select phone from public.contacts where id = c1) <> '0822' then raise exception 'GAGAL: ubah kontak'; end if;
  failed := false;
  begin perform public.delete_contact(c2); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: kontak bersaldo bisa dihapus'; end if;
  perform public.delete_contact(c1);
  if exists (select 1 from public.contacts where id = c1 and deleted_at is null) then raise exception 'GAGAL: kontak tidak terhapus'; end if;
  failed := false;
  begin perform public.contact_transfer(bid, c1, 'receive', 1000); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: kontak terhapus masih menerima transaksi'; end if;

  select * into inv from public.create_invitation(bid, 'nb@test.local', 'staff');
  perform set_config('t.inv', inv.id::text, true);
  perform set_config('t.c2', c2::text, true);
end $t$;

-- ===== B (staf): boleh ubah data kontak dan mencatat uang, tidak boleh menghapus kontak =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b4","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare
  bid uuid := current_setting('t.biz')::uuid; c2 uuid := current_setting('t.c2')::uuid;
  failed boolean; n int;
begin
  perform public.accept_invitation(current_setting('t.inv')::uuid);

  update public.contacts set phone = '0899' where id = c2;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'GAGAL: staf tidak bisa mengubah nomor telepon'; end if;

  failed := false;
  begin update public.contacts set deleted_at = now() where id = c2; exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: staf menghapus kontak lewat tabel'; end if;

  failed := false;
  begin perform public.delete_contact(c2); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: staf menghapus kontak'; end if;

  perform public.contact_transfer(bid, c2, 'give', 1000);
end $t$;

-- ===== C (orang luar) =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c4","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare failed boolean := false;
begin
  begin perform public.contact_transfer(current_setting('t.biz')::uuid, current_setting('t.c2')::uuid, 'receive', 1000);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: orang luar mencatat uang kontak'; end if;
  failed := false;
  begin perform public.settle_contact(current_setting('t.biz')::uuid, current_setting('t.c2')::uuid);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: orang luar melunasi kontak'; end if;
end $t$;

reset role;
select 'SEMUA TES SALDO KONTAK LULUS' as hasil;
rollback;
