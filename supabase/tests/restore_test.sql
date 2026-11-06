-- RekapRapi: tes pemulihan dari backup (restore_begin, restore_rows, restore_finish).
-- Jalankan SETELAH migrasi 20261113000000. Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES PEMULIHAN LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a9', 'ra@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b9', 'rb@test.local', now(), 'authenticated', 'authenticated');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a9","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare
  src uuid; nb uuid; ct1 uuid; ct2 uuid; d1 uuid; d2 uuid; cat_sale uuid;
  s1 jsonb; s2 jsonb; k text; n1 bigint; n2 bigint; failed boolean;
  p_cat jsonb; p_con jsonb; p_debt jsonb; p_pay jsonb; p_cash jsonb;
begin
  -- ===== Data sumber yang beragam =====
  src := public.create_business('Warung Asal');
  select id into cat_sale from public.categories where business_id = src and name = 'Penjualan';
  insert into public.contacts (business_id, name, phone, address, note, created_by)
    values (src, 'Bu Ani', '0812', 'Jl. Mawar', 'langganan', auth.uid()) returning id into ct1;
  insert into public.contacts (business_id, name, created_by) values (src, 'Pak Budi', auth.uid())
    returning id into ct2;

  insert into public.cash_transactions (business_id, type, amount, category_id, txn_date, created_by,
                                        is_sale, cost_amount, discount_amount, extra_fee, note)
  values (src, 'in', 95000, cat_sale, date '2026-11-05', auth.uid(), true, 60000, 10000, 5000, 'jual 1'),
         (src, 'out', 30000, null, date '2026-11-06', auth.uid(), false, 0, 0, 0, 'beli kardus');

  d1 := public.create_debt(src, ct1, 'receivable', 1000000, false, date '2026-11-06', date '2026-12-01',
                           'kredit', true, 650000, 0, 0);
  perform public.add_debt_payment(d1, 100000, date '2026-11-08', 'cicil');
  -- Utang uang berpindah, lalu piutang yang saling mengurangi (kompensasi).
  d2 := public.create_debt(src, ct2, 'payable', 300000, true, date '2026-11-07');
  perform public.create_debt(src, ct2, 'receivable', 200000, false, date '2026-11-09', null, 'kompensasi');
  perform public.create_debt(src, ct2, 'payable', 80000, false, date '2026-11-10');

  -- ===== Susun data seperti yang dibuat aplikasi dari backup =====
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'type', type,
                                               'is_system', is_system, 'is_sale', is_sale)), '[]')
    into p_cat from public.categories where business_id = src;
  select coalesce(jsonb_agg(to_jsonb(c)), '[]') into p_con
    from public.contacts c where business_id = src and deleted_at is null;
  select coalesce(jsonb_agg(to_jsonb(d)), '[]') into p_debt
    from public.debts d where business_id = src and deleted_at is null;
  select coalesce(jsonb_agg(to_jsonb(p)), '[]') into p_pay
    from public.debt_payments p where business_id = src and deleted_at is null;
  select coalesce(jsonb_agg(to_jsonb(t)), '[]') into p_cash
    from public.cash_transactions t where business_id = src and deleted_at is null;

  -- ===== Pulihkan =====
  nb := public.restore_begin('Warung Pulihan', 'business');
  perform set_config('t.nb', nb::text, true);
  perform set_config('t.src', src::text, true);
  perform public.restore_rows(nb, 'categories', p_cat);
  perform public.restore_rows(nb, 'contacts', p_con);
  perform public.restore_rows(nb, 'debts', p_debt);
  perform public.restore_rows(nb, 'payments', p_pay);
  perform public.restore_rows(nb, 'cash', p_cash);
  perform public.restore_finish(nb);

  -- ===== Hasilnya harus sama dengan sumber =====
  s1 := public.report_summary(src, date '2026-01-01', date '2026-12-31');
  s2 := public.report_summary(nb,  date '2026-01-01', date '2026-12-31');
  foreach k in array array['total_in','total_out','balance','income_sales','income_other',
                           'income_total','expense_cost','expense_other','expense_total','net',
                           'receivable_open','payable_open'] loop
    if s1 ->> k is distinct from s2 ->> k then
      raise exception 'GAGAL: % berbeda (asal %, pulihan %)', k, s1 ->> k, s2 ->> k;
    end if;
  end loop;

  foreach k in array array['categories','contacts','debts','debt_payments','cash_transactions'] loop
    if k = 'categories' then
      select count(*) into n1 from public.categories where business_id = src;
      select count(*) into n2 from public.categories where business_id = nb;
    else
      execute format('select count(*) from public.%I where business_id = $1 and deleted_at is null', k)
        into n1 using src;
      execute format('select count(*) from public.%I where business_id = $1 and deleted_at is null', k)
        into n2 using nb;
    end if;
    if n1 <> n2 then raise exception 'GAGAL: jumlah % berbeda (% vs %)', k, n1, n2; end if;
  end loop;

  -- Kompensasi tetap berpasangan, sisa utang per kontak sama.
  select count(distinct offset_group) into n1 from public.debt_payments where business_id = src and offset_group is not null;
  select count(distinct offset_group) into n2 from public.debt_payments where business_id = nb  and offset_group is not null;
  if n1 <> n2 or n1 = 0 then raise exception 'GAGAL: pasangan kompensasi % vs %', n1, n2; end if;
  select coalesce(sum(remaining), 0) into n1 from public.debt_balances where business_id = src;
  select coalesce(sum(remaining), 0) into n2 from public.debt_balances where business_id = nb;
  if n1 <> n2 then raise exception 'GAGAL: sisa utang piutang % vs %', n1, n2; end if;

  -- Waktu dicatat dan isian lain terjaga; id berbeda dari asal.
  if (select min(created_at) from public.cash_transactions where business_id = src)
     is distinct from (select min(created_at) from public.cash_transactions where business_id = nb) then
    raise exception 'GAGAL: waktu pencatatan berubah';
  end if;
  if exists (select 1 from public.cash_transactions a join public.cash_transactions b on a.id = b.id
              where a.business_id = src and b.business_id = nb) then
    raise exception 'GAGAL: id harus baru';
  end if;
  if not exists (select 1 from public.contacts where business_id = nb and name = 'Bu Ani'
                  and phone = '0812' and address = 'Jl. Mawar' and note = 'langganan') then
    raise exception 'GAGAL: data kontak tidak utuh';
  end if;
  if not exists (select 1 from public.cash_transactions where business_id = nb and note = 'jual 1'
                  and is_sale and cost_amount = 60000 and discount_amount = 10000 and extra_fee = 5000) then
    raise exception 'GAGAL: data penjualan tidak utuh';
  end if;

  -- Selesai: tidak lagi "memulihkan", pemilik adalah pemanggil, riwayat satu baris.
  if (select restoring from public.businesses where id = nb) then
    raise exception 'GAGAL: masih berstatus memulihkan';
  end if;
  if (select role from public.business_members where business_id = nb and user_id = auth.uid()) <> 'owner' then
    raise exception 'GAGAL: pemanggil bukan pemilik';
  end if;
  reset role;
  select count(*) into n1 from public.activity_log where business_id = nb;
  set local role authenticated;
  if n1 <> 1 then raise exception 'GAGAL: riwayat aktivitas harus satu baris, dapat %', n1; end if;

  -- ===== Penjagaan =====
  -- Pembukuan biasa (bukan sedang dipulihkan) tidak bisa disisipi data.
  failed := false;
  begin perform public.restore_rows(src, 'contacts', '[{"id":"00000000-0000-0000-0000-000000000001","name":"X"}]');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: pembukuan biasa menerima pemulihan'; end if;
  -- Setelah selesai juga tidak bisa.
  failed := false;
  begin perform public.restore_rows(nb, 'contacts', '[{"id":"00000000-0000-0000-0000-000000000002","name":"Y"}]');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: pembukuan selesai masih menerima pemulihan'; end if;

  -- Tabel tidak dikenal dan terlalu banyak baris ditolak.
  nb := public.restore_begin('Percobaan');
  perform set_config('t.nb2', nb::text, true);
  failed := false;
  begin perform public.restore_rows(nb, 'profiles', '[]'); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: tabel asing diterima'; end if;
  failed := false;
  begin perform public.restore_rows(nb, 'contacts', (select jsonb_agg(jsonb_build_object('id', gen_random_uuid(), 'name', 'k'))
                                                       from generate_series(1, 2001)));
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: lebih dari 2000 baris diterima'; end if;
  failed := false;
  begin perform public.restore_rows(nb, 'cash', '{"bukan":"daftar"}'); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: data bukan daftar diterima'; end if;

  -- Data yang melanggar aturan tabel ditolak (jumlah 0).
  failed := false;
  begin perform public.restore_rows(nb, 'cash',
    '[{"id":"00000000-0000-0000-0000-000000000003","type":"in","amount":0,"txn_date":"2026-11-01"}]');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: jumlah 0 diterima'; end if;
end $t$;

-- ===== Pengguna lain tidak bisa menyentuh pemulihan milik orang lain =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b9","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare failed boolean := false;
begin
  begin perform public.restore_rows(current_setting('t.nb2')::uuid, 'contacts',
                                    '[{"id":"00000000-0000-0000-0000-000000000004","name":"Z"}]');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: orang lain menulis ke pemulihan'; end if;
  failed := false;
  begin perform public.restore_finish(current_setting('t.nb2')::uuid); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: orang lain menyelesaikan pemulihan'; end if;
  if (select count(*) from public.businesses) <> 0 then raise exception 'GAGAL: orang lain melihat pembukuan'; end if;
end $t$;

-- Tanpa login tidak bisa.
reset role;
set local role anon;
do $t$
declare failed boolean := false;
begin
  begin perform public.restore_begin('Anon'); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: anon memulai pemulihan'; end if;
end $t$;

reset role;
select 'SEMUA TES PEMULIHAN LULUS' as hasil;
rollback;
