-- RekapRapi: dua jenis rekapan. Jalankan SETELAH 20261110000000_business_settings.sql, sekali saja.
--
--   * 'business' (Rekapan Usaha): fitur lengkap, termasuk penjualan, harga modal, keuntungan.
--   * 'personal' (Rekapan Pribadi): hanya pemasukan dan pengeluaran dengan kategori
--     (bisa ditambah), tanggal, dan utang piutang; tanpa penjualan.
--
-- Rekapan yang sudah ada otomatis menjadi 'business'. Batas 5 rekapan milik sendiri
-- berlaku untuk dua jenis digabung.

alter table public.businesses
  add column kind text not null default 'business'
  check (kind in ('business', 'personal'));

drop function public.create_business(text, text, text);

create function public.create_business(
  p_name text,
  p_address text default null,
  p_phone text default null,
  p_kind text default 'business'
)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  bid uuid;
  owned int;
begin
  if uid is null then raise exception 'Belum masuk' using errcode = '28000'; end if;
  if char_length(btrim(coalesce(p_name, ''))) = 0 then
    raise exception 'Nama rekapan wajib diisi' using errcode = '22023';
  end if;
  if p_kind not in ('business', 'personal') then
    raise exception 'Jenis rekapan tidak dikenal' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('create_business:' || uid::text));
  select count(*) into owned
  from public.business_members m
  join public.businesses b on b.id = m.business_id
  where m.user_id = uid and m.role = 'owner' and b.deleted_at is null;
  if owned >= 5 then
    raise exception 'Batas 5 rekapan per akun tercapai' using errcode = 'P0001';
  end if;

  insert into public.businesses (name, address, phone, created_by, kind)
  values (btrim(p_name), p_address, p_phone, uid, p_kind) returning id into bid;
  insert into public.business_members (business_id, user_id, role) values (bid, uid, 'owner');

  -- Kategori sistem dipakai utang piutang di kedua jenis.
  insert into public.categories (business_id, name, type, is_system) values
    (bid, 'Pemberian Piutang',  'out', true),
    (bid, 'Pelunasan Piutang',  'in',  true),
    (bid, 'Penerimaan Utang',   'in',  true),
    (bid, 'Pembayaran Utang',   'out', true);

  if p_kind = 'business' then
    insert into public.categories (business_id, name, type, is_sale) values
      (bid, 'Penjualan',        'in',  true);
    insert into public.categories (business_id, name, type) values
      (bid, 'Pemasukan Lain',   'in'),
      (bid, 'Pembelian Stok',   'out'),
      (bid, 'Gaji',             'out'),
      (bid, 'Sewa',             'out'),
      (bid, 'Listrik & Air',    'out'),
      (bid, 'Transportasi',     'out'),
      (bid, 'Pengeluaran Lain', 'out');
  else
    insert into public.categories (business_id, name, type) values
      (bid, 'Gaji',             'in'),
      (bid, 'Bonus',            'in'),
      (bid, 'Pemasukan Lain',   'in'),
      (bid, 'Makan & Minum',    'out'),
      (bid, 'Transportasi',     'out'),
      (bid, 'Belanja',          'out'),
      (bid, 'Tagihan',          'out'),
      (bid, 'Hiburan',          'out'),
      (bid, 'Kesehatan',        'out'),
      (bid, 'Pengeluaran Lain', 'out');
  end if;

  update public.profiles set last_business_id = bid where id = uid;
  return bid;
end $$;

revoke execute on function public.create_business(text, text, text, text) from public, anon;
grant execute on function public.create_business(text, text, text, text) to authenticated;
