-- RekapRapi: (1) pemulihan ke pembukuan yang masih kosong, (2) foto profil pembukuan.
-- Jalankan sekali di SQL Editor Supabase, setelah migrasi 20261117000000.

-- ---------------------------------------------------------------------------
-- 1. Pemulihan ke pembukuan yang sudah ada tetapi masih kosong
-- ---------------------------------------------------------------------------
-- Syarat: pemanggil adalah Pemilik sekaligus pembuat pembukuan, jenisnya sama dengan
-- backup, dan tidak ada transaksi, utang piutang, pembayaran, atau kontak yang masih
-- aktif. Sisa catatan yang sudah dihapus pengguna (tidak terlihat di aplikasi) dan
-- kategori bawaan dibersihkan, lalu pembukuan ditandai "sedang dipulihkan" sehingga
-- restore_rows dan restore_finish yang sama bisa dipakai.
create function public.restore_into_begin(p_business uuid, p_kind text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  b public.businesses;
begin
  perform public._require(p_business, array['owner']::public.member_role[]);
  select * into b from public.businesses where id = p_business and deleted_at is null for update;
  if b.id is null or b.created_by is distinct from uid then
    raise exception 'Hanya pembuat pembukuan yang bisa memulihkan ke pembukuan ini'
      using errcode = '42501';
  end if;
  if b.restoring then
    raise exception 'Pembukuan ini sedang dipulihkan' using errcode = 'P0001';
  end if;
  if b.kind is distinct from p_kind then
    raise exception 'Jenis pembukuan berbeda dengan data backup' using errcode = '22023';
  end if;
  if exists (select 1 from public.cash_transactions where business_id = p_business and deleted_at is null)
     or exists (select 1 from public.debts where business_id = p_business and deleted_at is null)
     or exists (select 1 from public.debt_payments where business_id = p_business and deleted_at is null)
     or exists (select 1 from public.contacts where business_id = p_business and deleted_at is null) then
    raise exception 'Pembukuan ini sudah berisi data. Pulihkan sebagai pembukuan baru.'
      using errcode = 'P0001';
  end if;

  perform public._restore_clear(p_business);
  update public.businesses set restoring = true where id = p_business;
  return p_business;
end $$;

-- Mengosongkan isi pembukuan (dipakai sebelum dan saat pembatalan pemulihan).
create function public._restore_clear(p_business uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.cash_transactions where business_id = p_business;
  delete from public.debt_payments     where business_id = p_business;
  delete from public.debts             where business_id = p_business;
  delete from public.contacts          where business_id = p_business;
  delete from public.categories        where business_id = p_business;
end $$;

-- Pemulihan gagal di tengah: data yang sempat masuk dibuang dan pembukuan kembali
-- kosong dengan kategori bawaan. Pembukuannya sendiri tidak dihapus.
create function public.restore_abort(p_business uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  b public.businesses;
begin
  perform public._require(p_business, array['owner']::public.member_role[]);
  select * into b from public.businesses where id = p_business and deleted_at is null for update;
  if b.id is null or not b.restoring or b.created_by is distinct from uid then
    raise exception 'Pembukuan ini tidak sedang dipulihkan' using errcode = '42501';
  end if;

  perform public._restore_clear(p_business);

  insert into public.categories (business_id, name, type, is_system) values
    (p_business, 'Pemberian Piutang', 'out', true),
    (p_business, 'Pelunasan Piutang', 'in',  true),
    (p_business, 'Penerimaan Utang',  'in',  true),
    (p_business, 'Pembayaran Utang',  'out', true);
  if b.kind = 'business' then
    insert into public.categories (business_id, name, type, is_sale) values
      (p_business, 'Penjualan', 'in', true);
    insert into public.categories (business_id, name, type) values
      (p_business, 'Penjualan lainnya', 'in'),
      (p_business, 'Gaji',              'out'),
      (p_business, 'Sewa',              'out'),
      (p_business, 'Listrik & Air',     'out'),
      (p_business, 'Transportasi',      'out'),
      (p_business, 'Pengeluaran Lain',  'out');
  else
    insert into public.categories (business_id, name, type) values
      (p_business, 'Gaji',             'in'),
      (p_business, 'Bonus',            'in'),
      (p_business, 'Pemasukan Lain',   'in'),
      (p_business, 'Makan & Minum',    'out'),
      (p_business, 'Transportasi',     'out'),
      (p_business, 'Belanja',          'out'),
      (p_business, 'Tagihan',          'out'),
      (p_business, 'Hiburan',          'out'),
      (p_business, 'Kesehatan',        'out'),
      (p_business, 'Pengeluaran Lain', 'out');
  end if;

  update public.businesses set restoring = false where id = p_business;
end $$;

revoke all on function public._restore_clear(uuid) from public, anon, authenticated;
revoke all on function public.restore_into_begin(uuid, text), public.restore_abort(uuid)
  from public, anon;
grant execute on function public.restore_into_begin(uuid, text), public.restore_abort(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Foto profil pembukuan
-- ---------------------------------------------------------------------------
-- Alamat foto disimpan di businesses.photo_url; berkasnya di Storage, wadah
-- "business-photos", pada jalur <id pembukuan>/<nama acak>.jpg. Wadahnya bisa dibaca
-- lewat alamat (alamatnya acak), tetapi hanya Pemilik dan Admin pembukuan itu yang bisa
-- mengunggah, mengganti, atau menghapus. Ukuran berkas dibatasi 300 KB.
alter table public.businesses
  add column photo_url text
    check (photo_url is null or char_length(photo_url) between 1 and 500);

grant update (photo_url) on public.businesses to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('business-photos', 'business-photos', true, 307200,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Folder pertama pada jalur adalah id pembukuan. Jalur yang bukan uuid ditolak.
create function public._photo_business(p_name text) returns uuid
language plpgsql immutable as $$
begin
  return (split_part(p_name, '/', 1))::uuid;
exception when others then
  return null;
end $$;

create policy business_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'business-photos'
              and public.is_admin_or_owner(public._photo_business(name)));
create policy business_photos_update on storage.objects for update to authenticated
  using (bucket_id = 'business-photos'
         and public.is_admin_or_owner(public._photo_business(name)))
  with check (bucket_id = 'business-photos'
              and public.is_admin_or_owner(public._photo_business(name)));
create policy business_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'business-photos'
         and public.is_admin_or_owner(public._photo_business(name)));
-- Daftar isi wadah hanya untuk anggota pembukuan itu (dipakai saat menghapus foto lama).
create policy business_photos_select on storage.objects for select to authenticated
  using (bucket_id = 'business-photos'
         and public.is_member(public._photo_business(name)));
