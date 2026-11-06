-- RekapRapi: tes jenis rekapan (usaha / pribadi). Jalankan SETELAH migrasi 20261111000000.
-- Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES JENIS REKAPAN LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a7', 'ka@test.local', now(), 'authenticated', 'authenticated');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a7","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare biz uuid; per uuid; n int; failed boolean; k text;
begin
  -- Tanpa jenis: usaha, seperti sebelumnya.
  biz := public.create_business('Warung A');
  select kind into k from public.businesses where id = biz;
  if k <> 'business' then raise exception 'GAGAL: bawaan harus usaha, dapat %', k; end if;
  if not exists (select 1 from public.categories where business_id = biz and is_sale) then
    raise exception 'GAGAL: usaha harus punya kategori Penjualan';
  end if;

  -- Pribadi: tanpa kategori penjualan, ada kategori pribadi dan kategori sistem utang.
  per := public.create_business('Keuangan Saya', null, null, 'personal');
  select kind into k from public.businesses where id = per;
  if k <> 'personal' then raise exception 'GAGAL: jenis pribadi tidak tersimpan'; end if;
  if exists (select 1 from public.categories where business_id = per and is_sale) then
    raise exception 'GAGAL: rekapan pribadi tidak boleh punya kategori penjualan';
  end if;
  select count(*) into n from public.categories where business_id = per and is_system;
  if n <> 4 then raise exception 'GAGAL: kategori sistem utang harus 4, dapat %', n; end if;
  select count(*) into n from public.categories
   where business_id = per and not is_system and type = 'in';
  if n <> 3 then raise exception 'GAGAL: kategori pemasukan pribadi harus 3, dapat %', n; end if;
  select count(*) into n from public.categories
   where business_id = per and not is_system and type = 'out';
  if n <> 7 then raise exception 'GAGAL: kategori pengeluaran pribadi harus 7, dapat %', n; end if;

  -- Kategori boleh ditambah oleh pemiliknya.
  insert into public.categories (business_id, name, type) values (per, 'Zakat', 'out');

  -- Jenis tidak dikenal ditolak.
  failed := false;
  begin perform public.create_business('X', null, null, 'lain'); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: jenis tidak dikenal diterima'; end if;

  -- Batas 5 berlaku untuk dua jenis digabung (sudah 2, tambah 3 lagi lalu yang ke-6 ditolak).
  perform public.create_business('U3');
  perform public.create_business('P4', null, null, 'personal');
  perform public.create_business('U5');
  failed := false;
  begin perform public.create_business('P6', null, null, 'personal'); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: batas 5 rekapan tidak berlaku lintas jenis'; end if;

  -- Jenis tidak bisa diubah oleh klien.
  failed := false;
  begin update public.businesses set kind = 'personal' where id = biz; exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: klien bisa mengubah jenis rekapan'; end if;
end $t$;

reset role;
select 'SEMUA TES JENIS REKAPAN LULUS' as hasil;
rollback;
