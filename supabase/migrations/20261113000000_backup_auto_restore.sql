-- RekapRapi: backup otomatis harian dan pemulihan dari Google Sheet.
-- Jalankan SETELAH 20261112000000_accounting_v2.sql, sekali saja.
--
-- 1. backup_settings.auto_daily: saklar backup otomatis harian (dijalankan aplikasi saat dibuka).
-- 2. Pemulihan: data dari backup dimasukkan sebagai PEMBUKUAN BARU lewat tiga fungsi
--    (restore_begin, restore_rows, restore_finish). Dipecah agar tiap panggilan kecil.
--    Semua id diberi id baru dengan pemetaan tetap (_remap), jadi pemulihan aman dilakukan
--    walau pembukuan aslinya masih ada, dan tiap panggilan konsisten satu sama lain.

-- ---------------------------------------------------------------------------
-- 1. Backup otomatis harian
-- ---------------------------------------------------------------------------
alter table public.backup_settings
  add column auto_daily boolean not null default true;

grant insert (auto_daily) on public.backup_settings to authenticated;
grant update (auto_daily) on public.backup_settings to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Penanda pembukuan yang sedang dipulihkan
-- ---------------------------------------------------------------------------
alter table public.businesses
  add column restoring boolean not null default false;

-- Id baru yang selalu sama untuk pasangan (pembukuan, id lama).
create function public._remap(p_business uuid, p_old uuid) returns uuid
language sql immutable as $$
  select md5(p_business::text || ':' || p_old::text)::uuid
$$;

-- ---------------------------------------------------------------------------
-- 3. restore_begin: membuat pembukuan kosong milik pemanggil
-- ---------------------------------------------------------------------------
create function public.restore_begin(
  p_name text,
  p_kind text default 'business',
  p_address text default null,
  p_phone text default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  bid uuid;
  owned int;
begin
  if uid is null then raise exception 'Belum masuk' using errcode = '28000'; end if;
  if char_length(btrim(coalesce(p_name, ''))) = 0 then
    raise exception 'Nama pembukuan wajib diisi' using errcode = '22023';
  end if;
  if p_kind not in ('business', 'personal') then
    raise exception 'Jenis pembukuan tidak dikenal' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('create_business:' || uid::text));
  select count(*) into owned
  from public.business_members m
  join public.businesses b on b.id = m.business_id
  where m.user_id = uid and m.role = 'owner' and b.deleted_at is null;
  if owned >= 5 then
    raise exception 'Batas 5 pembukuan per akun tercapai' using errcode = 'P0001';
  end if;

  insert into public.businesses (name, address, phone, created_by, kind, restoring)
  values (btrim(p_name), p_address, p_phone, uid, p_kind, true) returning id into bid;
  insert into public.business_members (business_id, user_id, role) values (bid, uid, 'owner');
  return bid;
end $$;

-- ---------------------------------------------------------------------------
-- 4. restore_rows: memasukkan sekumpulan baris satu tabel
--    Urutan pemanggilan: categories, contacts, debts, payments, cash.
-- ---------------------------------------------------------------------------
create function public.restore_rows(p_business uuid, p_table text, p_rows jsonb) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  n int := 0;
begin
  perform public._require(p_business, array['owner']::public.member_role[]);
  if not exists (select 1 from public.businesses b
                  where b.id = p_business and b.restoring and b.created_by = uid
                    and b.deleted_at is null) then
    raise exception 'Pembukuan ini tidak sedang dipulihkan' using errcode = '42501';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Data pemulihan harus berupa daftar' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) > 2000 then
    raise exception 'Terlalu banyak baris dalam satu panggilan' using errcode = '22023';
  end if;

  if p_table = 'categories' then
    insert into public.categories (id, business_id, name, type, is_system, is_sale)
    select public._remap(p_business, (x ->> 'id')::uuid), p_business, x ->> 'name',
           (x ->> 'type')::public.txn_type,
           coalesce((x ->> 'is_system')::boolean, false),
           coalesce((x ->> 'is_sale')::boolean, false)
    from jsonb_array_elements(p_rows) x;

  elsif p_table = 'contacts' then
    insert into public.contacts (id, business_id, name, phone, address, note, created_by, created_at)
    select public._remap(p_business, (x ->> 'id')::uuid), p_business, x ->> 'name',
           x ->> 'phone', x ->> 'address', x ->> 'note', uid,
           coalesce((x ->> 'created_at')::timestamptz, now())
    from jsonb_array_elements(p_rows) x;

  elsif p_table = 'debts' then
    insert into public.debts (id, business_id, contact_id, kind, amount, cash_moved, debt_date,
                              due_date, note, created_by, created_at,
                              is_sale, cost_amount, discount_amount, extra_fee)
    select public._remap(p_business, (x ->> 'id')::uuid), p_business,
           public._remap(p_business, (x ->> 'contact_id')::uuid),
           (x ->> 'kind')::public.debt_kind, (x ->> 'amount')::bigint,
           (x ->> 'cash_moved')::boolean, (x ->> 'debt_date')::date,
           nullif(x ->> 'due_date', '')::date, x ->> 'note', uid,
           coalesce((x ->> 'created_at')::timestamptz, now()),
           coalesce((x ->> 'is_sale')::boolean, false),
           coalesce((x ->> 'cost_amount')::bigint, 0),
           coalesce((x ->> 'discount_amount')::bigint, 0),
           coalesce((x ->> 'extra_fee')::bigint, 0)
    from jsonb_array_elements(p_rows) x;

  elsif p_table = 'payments' then
    insert into public.debt_payments (id, business_id, debt_id, amount, paid_on, note,
                                      created_by, created_at, method, offset_group)
    select public._remap(p_business, (x ->> 'id')::uuid), p_business,
           public._remap(p_business, (x ->> 'debt_id')::uuid),
           (x ->> 'amount')::bigint, (x ->> 'paid_on')::date, x ->> 'note', uid,
           coalesce((x ->> 'created_at')::timestamptz, now()),
           coalesce(x ->> 'method', 'cash'),
           case when nullif(x ->> 'offset_group', '') is null then null
                else public._remap(p_business, (x ->> 'offset_group')::uuid) end
    from jsonb_array_elements(p_rows) x;

  elsif p_table = 'cash' then
    insert into public.cash_transactions (id, business_id, type, amount, category_id, note, txn_date,
                                          debt_id, debt_payment_id, created_by, created_at,
                                          is_sale, cost_amount, discount_amount, extra_fee)
    select public._remap(p_business, (x ->> 'id')::uuid), p_business,
           (x ->> 'type')::public.txn_type, (x ->> 'amount')::bigint,
           case when nullif(x ->> 'category_id', '') is null then null
                else public._remap(p_business, (x ->> 'category_id')::uuid) end,
           x ->> 'note', (x ->> 'txn_date')::date,
           case when nullif(x ->> 'debt_id', '') is null then null
                else public._remap(p_business, (x ->> 'debt_id')::uuid) end,
           case when nullif(x ->> 'debt_payment_id', '') is null then null
                else public._remap(p_business, (x ->> 'debt_payment_id')::uuid) end,
           uid, coalesce((x ->> 'created_at')::timestamptz, now()),
           coalesce((x ->> 'is_sale')::boolean, false),
           coalesce((x ->> 'cost_amount')::bigint, 0),
           coalesce((x ->> 'discount_amount')::bigint, 0),
           coalesce((x ->> 'extra_fee')::bigint, 0)
    from jsonb_array_elements(p_rows) x;

  else
    raise exception 'Tabel pemulihan tidak dikenal: %', p_table using errcode = '22023';
  end if;

  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------------
-- 5. restore_finish: merapikan dan membuka pembukuan hasil pulihan
-- ---------------------------------------------------------------------------
create function public.restore_finish(p_business uuid) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid();
begin
  perform public._require(p_business, array['owner']::public.member_role[]);
  if not exists (select 1 from public.businesses b
                  where b.id = p_business and b.restoring and b.created_by = uid
                    and b.deleted_at is null) then
    raise exception 'Pembukuan ini tidak sedang dipulihkan' using errcode = '42501';
  end if;

  -- Kategori sistem utang piutang harus ada walau tidak ikut di data pemulihan.
  insert into public.categories (business_id, name, type, is_system)
  select p_business, v.name, v.type::public.txn_type, true
  from (values ('Pemberian Piutang', 'out'), ('Pelunasan Piutang', 'in'),
               ('Penerimaan Utang', 'in'), ('Pembayaran Utang', 'out')) as v(name, type)
  where not exists (select 1 from public.categories c
                     where c.business_id = p_business and c.is_system and c.name = v.name);

  -- Pemulihan menulis ribuan catatan aktivitas otomatis; riwayat pembukuan baru
  -- cukup satu baris.
  delete from public.activity_log where business_id = p_business;
  insert into public.activity_log (business_id, user_id, action, entity, entity_id, detail)
  values (p_business, uid, 'restore', 'business', p_business,
          jsonb_build_object('source', 'google_sheet'));

  update public.businesses set restoring = false where id = p_business;
  update public.profiles set last_business_id = p_business where id = uid;
  return p_business;
end $$;

revoke execute on function
  public.restore_begin(text, text, text, text),
  public.restore_rows(uuid, text, jsonb),
  public.restore_finish(uuid)
  from public, anon;
grant execute on function
  public.restore_begin(text, text, text, text),
  public.restore_rows(uuid, text, jsonb),
  public.restore_finish(uuid)
  to authenticated;
