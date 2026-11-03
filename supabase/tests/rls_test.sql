-- RekapRapi: tes hak akses dan sinkron kas (jalankan SETELAH migrasi init).
-- Cara pakai: tempel di Supabase SQL Editor pada proyek PENGEMBANGAN, lalu Run.
-- Seluruhnya di dalam satu transaksi yang di-ROLLBACK, jadi tidak ada data tersisa.
-- Gagal  -> muncul error "GAGAL: ..." dan skrip berhenti.
-- Sukses -> baris terakhir menampilkan "SEMUA TES LULUS".

begin;

-- Pengguna uji: A pemilik, B staf, C orang luar, D admin, E penerima kode.
insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000000c', 'c@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000000d', 'd@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000000e', 'e@test.local', now(), 'authenticated', 'authenticated');

-- ===== A: buat usaha, catat kas, undang B (staf) dan D (admin) =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid; tid uuid; inv record;
begin
  bid := public.create_business('Warung A');
  perform set_config('t.biz', bid::text, true);

  if (select count(*) from public.categories where business_id = bid and is_system) <> 4 then
    raise exception 'GAGAL: kategori sistem tidak terbentuk';
  end if;

  insert into public.cash_transactions (business_id, type, amount, category_id, note, created_by)
  select bid, 'in', 500000, id, 'jual', auth.uid()
  from public.categories where business_id = bid and name = 'Penjualan'
  returning id into tid;
  perform set_config('t.txn_a', tid::text, true);

  select * into inv from public.create_invitation(bid, 'B@test.local', 'staff');
  perform set_config('t.inv_b', inv.id::text, true);
  select * into inv from public.create_invitation(bid, 'd@test.local', 'admin');
  perform set_config('t.inv_d', inv.id::text, true);
end $t$;

-- ===== C (orang luar): tidak boleh melihat atau menulis apa pun =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid := current_setting('t.biz')::uuid; failed boolean;
begin
  if (select count(*) from public.businesses) <> 0 then raise exception 'GAGAL: C melihat usaha orang lain'; end if;
  if (select count(*) from public.cash_transactions) <> 0 then raise exception 'GAGAL: C melihat kas orang lain'; end if;
  if (select count(*) from public.invitations) <> 0 then raise exception 'GAGAL: C melihat undangan orang lain'; end if;
  if (select count(*) from public.profiles where id <> auth.uid()) <> 0 then raise exception 'GAGAL: C melihat profil orang lain'; end if;

  failed := false;
  begin
    insert into public.cash_transactions (business_id, type, amount, created_by)
    values (bid, 'in', 1, auth.uid());
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: C bisa menulis kas usaha A'; end if;

  failed := false;
  begin perform public.create_invitation(bid, 'x@test.local', 'staff');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: C bisa mengundang'; end if;

  failed := false;
  begin perform public.report_summary(bid, current_date, current_date);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: C bisa membaca laporan'; end if;
end $t$;

-- ===== B (staf): terima undangan, batas hak =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare
  bid uuid := current_setting('t.biz')::uuid;
  txn_a uuid := current_setting('t.txn_a')::uuid;
  own uuid; n int; failed boolean;
begin
  perform public.accept_invitation(current_setting('t.inv_b')::uuid);
  if (select count(*) from public.businesses) <> 1 then raise exception 'GAGAL: B tidak melihat usaha setelah menerima'; end if;
  if (select count(*) from public.cash_transactions where id = txn_a) <> 1 then
    raise exception 'GAGAL: staf harus bisa melihat semua transaksi';
  end if;

  update public.cash_transactions set amount = 1 where id = txn_a;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'GAGAL: staf mengubah transaksi orang lain'; end if;

  insert into public.cash_transactions (business_id, type, amount, note, created_by)
  values (bid, 'out', 20000, 'beli plastik', auth.uid()) returning id into own;
  update public.cash_transactions set amount = 25000 where id = own;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'GAGAL: staf tidak bisa mengubah transaksinya sendiri'; end if;

  failed := false;
  begin
    insert into public.cash_transactions (business_id, type, amount, created_by)
    values (bid, 'out', 1, '00000000-0000-0000-0000-00000000000a');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: staf menulis atas nama orang lain'; end if;

  failed := false;
  begin insert into public.categories (business_id, name, type) values (bid, 'X', 'in');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: staf menambah kategori'; end if;

  failed := false;
  begin perform public.create_invitation(bid, 'y@test.local', 'staff');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: staf mengundang'; end if;

  failed := false;
  begin perform public.delete_business(bid);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: staf menghapus usaha'; end if;

  if (select count(*) from public.activity_log) <> 0 then raise exception 'GAGAL: staf melihat riwayat aktivitas'; end if;
  if (public.report_summary(bid, current_date, current_date) ->> 'balance')::bigint <> 475000 then
    raise exception 'GAGAL: saldo awal salah (harus 475000)';
  end if;
end $t$;

-- ===== A: utang piutang tersinkron dengan kas =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare
  bid uuid := current_setting('t.biz')::uuid;
  cid uuid; did uuid; n int; failed boolean; s jsonb;
begin
  insert into public.contacts (business_id, name, created_by) values (bid, 'Bu Sari', auth.uid())
  returning id into cid;

  did := public.create_debt(bid, cid, 'receivable', 100000, true);
  perform set_config('t.debt', did::text, true);
  s := public.report_summary(bid, current_date, current_date);
  if (s ->> 'balance')::bigint <> 375000 then raise exception 'GAGAL: piutang tunai harus mengurangi kas (%)', s; end if;
  if (s ->> 'receivable_open')::bigint <> 100000 then raise exception 'GAGAL: sisa piutang salah (%)', s; end if;

  perform public.add_debt_payment(did, 40000);
  s := public.report_summary(bid, current_date, current_date);
  if (s ->> 'balance')::bigint <> 415000 then raise exception 'GAGAL: cicilan harus menambah kas (%)', s; end if;
  if (s ->> 'receivable_open')::bigint <> 60000 then raise exception 'GAGAL: sisa setelah cicilan salah (%)', s; end if;

  failed := false;
  begin perform public.add_debt_payment(did, 70000);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: pembayaran melebihi sisa diterima'; end if;

  update public.cash_transactions set amount = 1 where debt_id = did or debt_payment_id is not null;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'GAGAL: kas otomatis bisa diubah langsung'; end if;

  -- Piutang non-tunai (barang kredit) tidak menggerakkan kas.
  perform public.create_debt(bid, cid, 'receivable', 30000, false);
  s := public.report_summary(bid, current_date, current_date);
  if (s ->> 'balance')::bigint <> 415000 then raise exception 'GAGAL: piutang non-tunai mengubah kas (%)', s; end if;
  if (s ->> 'receivable_open')::bigint <> 90000 then raise exception 'GAGAL: total piutang salah (%)', s; end if;
end $t$;

-- B (staf) tidak boleh menghapus utang yang bukan miliknya.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare failed boolean := false;
begin
  begin perform public.delete_debt(current_setting('t.debt')::uuid);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: staf menghapus utang orang lain'; end if;
end $t$;

-- A menghapus utang -> kas kembali seperti semula.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid := current_setting('t.biz')::uuid; s jsonb;
begin
  perform public.delete_debt(current_setting('t.debt')::uuid);
  s := public.report_summary(bid, current_date, current_date);
  if (s ->> 'balance')::bigint <> 475000 then raise exception 'GAGAL: hapus utang tidak mengembalikan kas (%)', s; end if;
  if (s ->> 'receivable_open')::bigint <> 30000 then raise exception 'GAGAL: sisa piutang setelah hapus salah (%)', s; end if;
end $t$;

-- ===== D (admin): batas hak admin =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000d","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid := current_setting('t.biz')::uuid; failed boolean;
begin
  perform public.accept_invitation(current_setting('t.inv_d')::uuid);

  failed := false;
  begin perform public.remove_member(bid, '00000000-0000-0000-0000-00000000000a');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: admin mengeluarkan pemilik'; end if;

  perform public.change_member_role(bid, '00000000-0000-0000-0000-00000000000b', 'admin');

  failed := false;
  begin perform public.remove_member(bid, '00000000-0000-0000-0000-00000000000b');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: admin mengeluarkan sesama admin'; end if;

  failed := false;
  begin perform public.delete_business(bid);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: admin menghapus usaha'; end if;

  if (select count(*) from public.activity_log) = 0 then raise exception 'GAGAL: admin tidak melihat riwayat aktivitas'; end if;
end $t$;

-- ===== A: pemilik =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid := current_setting('t.biz')::uuid; failed boolean; i int; inv record;
begin
  failed := false;
  begin perform public.leave_business(bid);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: pemilik bisa keluar tanpa mengalihkan'; end if;

  perform public.remove_member(bid, '00000000-0000-0000-0000-00000000000b');

  -- Batas 5 usaha per akun (sudah punya 1).
  for i in 1..4 loop perform public.create_business('Usaha ' || i); end loop;
  failed := false;
  begin perform public.create_business('Usaha ke-6');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: batas 5 usaha tidak berlaku'; end if;

  select * into inv from public.create_invitation(bid, 'kode@test.local', 'staff');
  perform set_config('t.code', inv.code, true);
end $t$;

-- ===== B dikeluarkan: tidak boleh melihat apa pun lagi =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
set local role authenticated;

do $t$
begin
  if (select count(*) from public.businesses) <> 0 or (select count(*) from public.cash_transactions) <> 0 then
    raise exception 'GAGAL: anggota yang dikeluarkan masih bisa melihat data';
  end if;
end $t$;

-- ===== E: bergabung lewat kode, sekali pakai =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000e","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare failed boolean := false;
begin
  perform public.accept_invitation_by_code(current_setting('t.code'));
  if (select count(*) from public.businesses) <> 1 then raise exception 'GAGAL: E tidak masuk lewat kode'; end if;
  begin perform public.accept_invitation_by_code(current_setting('t.code'));
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: kode bisa dipakai dua kali'; end if;
end $t$;

reset role;
select 'SEMUA TES LULUS' as hasil;
rollback;
