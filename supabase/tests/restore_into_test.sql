-- RekapRapi: tes pemulihan ke pembukuan kosong dan kolom foto profil.
-- Jalankan SETELAH migrasi 20261118000000. Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES PULIHKAN KE PEMBUKUAN LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a3', 'xa@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b3', 'xb@test.local', now(), 'authenticated', 'authenticated');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare
  src uuid; dst uuid; pers uuid; ct uuid; cat uuid; n bigint; failed boolean;
  p_cat jsonb; p_con jsonb; p_debt jsonb; p_pay jsonb; p_cash jsonb; s1 jsonb; s2 jsonb; k text;
begin
  -- ===== Sumber =====
  src := public.create_business('Toko Asal');
  select id into cat from public.categories where business_id = src and name = 'Penjualan';
  insert into public.categories (business_id, name, type) values (src, 'Kemasan', 'out');
  insert into public.contacts (business_id, name, created_by) values (src, 'Bu Ani', auth.uid())
    returning id into ct;
  insert into public.cash_transactions (business_id, type, amount, category_id, txn_date, created_by,
                                        is_sale, cost_amount)
  values (src, 'in', 90000, cat, date '2026-11-05', auth.uid(), true, 50000);
  perform public.create_debt(src, ct, 'receivable', 40000, false, date '2026-11-06', null, 'kredit', true, 25000);

  select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'type', type,
                                      'is_system', is_system, 'is_sale', is_sale))
    into p_cat from public.categories where business_id = src;
  select coalesce(jsonb_agg(to_jsonb(c)), '[]') into p_con from public.contacts c where business_id = src;
  select coalesce(jsonb_agg(to_jsonb(d)), '[]') into p_debt from public.debts d where business_id = src;
  select coalesce(jsonb_agg(to_jsonb(p)), '[]') into p_pay from public.debt_payments p where business_id = src;
  select coalesce(jsonb_agg(to_jsonb(t)), '[]') into p_cash from public.cash_transactions t where business_id = src;

  -- ===== Tujuan: pembukuan kosong yang pernah dicoba lalu dihapus isinya =====
  dst := public.create_business('Toko Baru');
  pers := public.create_business('Dompet', null, null, 'personal');
  perform set_config('t.dst', dst::text, true);
  perform set_config('t.src', src::text, true);
  insert into public.cash_transactions (business_id, type, amount, txn_date, created_by)
  values (dst, 'out', 500, current_date, auth.uid());

  -- Masih berisi data: ditolak.
  failed := false;
  begin perform public.restore_into_begin(dst, 'business'); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: pembukuan berisi data diterima'; end if;
  failed := false;
  begin perform public.restore_into_begin(src, 'business'); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: pembukuan sumber diterima'; end if;

  update public.cash_transactions set deleted_at = now() where business_id = dst;

  -- Jenis berbeda: ditolak.
  failed := false;
  begin perform public.restore_into_begin(pers, 'business'); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: jenis berbeda diterima'; end if;

  -- ===== Gagal di tengah lalu dibatalkan: kembali kosong dengan kategori bawaan =====
  perform public.restore_into_begin(dst, 'business');
  if not (select restoring from public.businesses where id = dst) then raise exception 'GAGAL: belum ditandai'; end if;
  select count(*) into n from public.categories where business_id = dst;
  if n <> 0 then raise exception 'GAGAL: kategori bawaan belum dibersihkan'; end if;
  perform public.restore_rows(dst, 'categories', p_cat);
  perform public.restore_rows(dst, 'contacts', p_con);
  perform public.restore_abort(dst);
  if (select restoring from public.businesses where id = dst) then raise exception 'GAGAL: masih ditandai'; end if;
  select count(*) into n from public.contacts where business_id = dst;
  if n <> 0 then raise exception 'GAGAL: kontak tersisa setelah batal'; end if;
  select count(*) into n from public.categories where business_id = dst;
  if n <> 11 then raise exception 'GAGAL: kategori bawaan setelah batal, %', n; end if;
  if not exists (select 1 from public.categories where business_id = dst and name = 'Penjualan' and is_sale) then
    raise exception 'GAGAL: kategori Penjualan tidak kembali';
  end if;
  -- Batal dua kali ditolak; pembukuan biasa tidak bisa dibatalkan.
  failed := false;
  begin perform public.restore_abort(dst); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: batal pada pembukuan biasa'; end if;

  -- ===== Pemulihan penuh ke pembukuan kosong =====
  perform public.restore_into_begin(dst, 'business');
  perform public.restore_rows(dst, 'categories', p_cat);
  perform public.restore_rows(dst, 'contacts', p_con);
  perform public.restore_rows(dst, 'debts', p_debt);
  perform public.restore_rows(dst, 'payments', p_pay);
  perform public.restore_rows(dst, 'cash', p_cash);
  perform public.restore_finish(dst);

  s1 := public.report_summary(src, date '2026-01-01', date '2026-12-31');
  s2 := public.report_summary(dst, date '2026-01-01', date '2026-12-31');
  foreach k in array array['income_total', 'expense_total', 'net', 'receivable_open', 'balance'] loop
    if s1 ->> k is distinct from s2 ->> k then
      raise exception 'GAGAL: % berbeda (asal %, tujuan %)', k, s1 ->> k, s2 ->> k;
    end if;
  end loop;
  if (select name from public.businesses where id = dst) <> 'Toko Baru' then
    raise exception 'GAGAL: nama pembukuan berubah';
  end if;
  if not exists (select 1 from public.categories where business_id = dst and name = 'Kemasan') then
    raise exception 'GAGAL: kategori dari backup tidak masuk';
  end if;
  select count(*) into n from public.categories where business_id = dst and name = 'Penjualan';
  if n <> 1 then raise exception 'GAGAL: kategori ganda, %', n; end if;
  if (select restoring from public.businesses where id = dst) then raise exception 'GAGAL: belum selesai'; end if;

  -- Sudah berisi: tidak bisa dipulihkan lagi ke sini.
  failed := false;
  begin perform public.restore_into_begin(dst, 'business'); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: pemulihan kedua diterima'; end if;

  -- ===== Foto profil: Pemilik boleh mengisi =====
  update public.businesses set photo_url = 'https://x/storage/v1/object/public/business-photos/a/b.jpg'
   where id = dst;
  if (select photo_url from public.businesses where id = dst) is null then
    raise exception 'GAGAL: foto tidak tersimpan';
  end if;
end $t$;

-- ===== Orang lain: admin tidak bisa memulihkan; bukan anggota tidak bisa apa-apa =====
reset role;
insert into public.business_members (business_id, user_id, role)
values (current_setting('t.dst')::uuid, '00000000-0000-0000-0000-0000000000b3', 'staff');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b3","role":"authenticated"}', true);
set local role authenticated;
do $t$
declare failed boolean := false; n int;
begin
  begin perform public.restore_into_begin(current_setting('t.dst')::uuid, 'business');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: staf memulai pemulihan'; end if;
  failed := false;
  begin perform public.restore_abort(current_setting('t.dst')::uuid);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: staf membatalkan pemulihan'; end if;
  failed := false;
  begin perform public._restore_clear(current_setting('t.dst')::uuid);
  exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'GAGAL: pengguna memanggil _restore_clear'; end if;

  -- Staf tidak bisa mengganti foto.
  update public.businesses set photo_url = 'x' where id = current_setting('t.dst')::uuid;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'GAGAL: staf mengganti foto'; end if;
  -- Pembukuan orang lain tidak terlihat.
  failed := false;
  begin perform public.restore_into_begin(current_setting('t.src')::uuid, 'business');
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: bukan anggota memulai pemulihan'; end if;
end $t$;

-- Jalur foto: folder pertama harus id pembukuan.
reset role;
do $t$
begin
  if public._photo_business('bukan-uuid/x.jpg') is not null then raise exception 'GAGAL: jalur asing'; end if;
  if public._photo_business(current_setting('t.dst') || '/x.jpg') <> current_setting('t.dst')::uuid then
    raise exception 'GAGAL: jalur foto';
  end if;
end $t$;

select 'SEMUA TES PULIHKAN KE PEMBUKUAN LULUS' as hasil;
rollback;
