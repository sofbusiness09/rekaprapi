-- RekapRapi: penjualan dengan harga modal, diskon, biaya tambahan, dan keuntungan;
-- serta data grafik laporan. Jalankan SETELAH 20261103000000_init.sql, sekali saja.
--
-- Aturan hitung untuk transaksi penjualan:
--   amount (kas/piutang yang diterima) = Total Penjualan - Diskon + Biaya Tambahan
--   Keuntungan                          = Total Penjualan - Diskon - Harga Modal
--                                       = amount - Biaya Tambahan - Harga Modal
--   Biaya Tambahan (mis. ongkir) tidak memengaruhi keuntungan.
-- Penjualan tunai dicatat di cash_transactions; penjualan kredit di debts
-- (keuntungan diakui pada tanggal penjualan, kas baru berubah saat dibayar).

-- ---------------------------------------------------------------------------
-- 1. Kolom
-- ---------------------------------------------------------------------------
alter table public.categories
  add column is_sale boolean not null default false;

update public.categories
   set is_sale = true
 where type = 'in' and name = 'Penjualan' and not is_system;

alter table public.cash_transactions
  add column is_sale         boolean not null default false,
  add column cost_amount     bigint  not null default 0 check (cost_amount >= 0),
  add column discount_amount bigint  not null default 0 check (discount_amount >= 0),
  add column extra_fee       bigint  not null default 0 check (extra_fee >= 0),
  add constraint cash_sale_fields_chk
    check (is_sale or (cost_amount = 0 and discount_amount = 0 and extra_fee = 0)),
  add constraint cash_sale_fee_chk check (extra_fee <= amount);

alter table public.debts
  add column is_sale         boolean not null default false,
  add column cost_amount     bigint  not null default 0 check (cost_amount >= 0),
  add column discount_amount bigint  not null default 0 check (discount_amount >= 0),
  add column extra_fee       bigint  not null default 0 check (extra_fee >= 0),
  add constraint debts_sale_fields_chk
    check (is_sale or (cost_amount = 0 and discount_amount = 0 and extra_fee = 0)),
  add constraint debts_sale_fee_chk check (extra_fee <= amount);

-- ---------------------------------------------------------------------------
-- 2. Hak akses kolom baru
-- ---------------------------------------------------------------------------
grant insert (is_sale), update (name, is_sale) on public.categories to authenticated;

grant insert (is_sale, cost_amount, discount_amount, extra_fee),
      update (is_sale, cost_amount, discount_amount, extra_fee)
  on public.cash_transactions to authenticated;

-- ---------------------------------------------------------------------------
-- 3. create_business: kategori "Penjualan" ditandai sebagai penjualan
-- ---------------------------------------------------------------------------
create or replace function public.create_business(p_name text, p_address text default null, p_phone text default null)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  bid uuid;
  owned int;
begin
  if uid is null then raise exception 'Belum masuk' using errcode = '28000'; end if;
  if char_length(btrim(coalesce(p_name, ''))) = 0 then
    raise exception 'Nama usaha wajib diisi' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('create_business:' || uid::text));
  select count(*) into owned
  from public.business_members m
  join public.businesses b on b.id = m.business_id
  where m.user_id = uid and m.role = 'owner' and b.deleted_at is null;
  if owned >= 5 then
    raise exception 'Batas 5 usaha per akun tercapai' using errcode = 'P0001';
  end if;

  insert into public.businesses (name, address, phone, created_by)
  values (btrim(p_name), p_address, p_phone, uid) returning id into bid;
  insert into public.business_members (business_id, user_id, role) values (bid, uid, 'owner');

  insert into public.categories (business_id, name, type, is_system) values
    (bid, 'Pemberian Piutang',  'out', true),
    (bid, 'Pelunasan Piutang',  'in',  true),
    (bid, 'Penerimaan Utang',   'in',  true),
    (bid, 'Pembayaran Utang',   'out', true);
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

  update public.profiles set last_business_id = bid where id = uid;
  return bid;
end $$;

-- ---------------------------------------------------------------------------
-- 4. create_debt: tambah data penjualan (hanya untuk piutang)
-- ---------------------------------------------------------------------------
drop function public.create_debt(uuid, uuid, public.debt_kind, bigint, boolean, date, date, text);

create function public.create_debt(
  p_business   uuid,
  p_contact    uuid,
  p_kind       public.debt_kind,
  p_amount     bigint,
  p_cash_moved boolean,
  p_debt_date  date default current_date,
  p_due_date   date default null,
  p_note       text default null,
  p_is_sale    boolean default false,
  p_cost       bigint default 0,
  p_discount   bigint default 0,
  p_fee        bigint default 0
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare did uuid; cat uuid;
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  if p_amount is null or p_amount <= 0 then
    raise exception 'Jumlah harus lebih dari 0' using errcode = '22023';
  end if;
  if p_is_sale and p_kind <> 'receivable' then
    raise exception 'Hanya piutang yang bisa berupa penjualan' using errcode = '22023';
  end if;
  if not p_is_sale then
    p_cost := 0; p_discount := 0; p_fee := 0;
  end if;
  if coalesce(p_cost, 0) < 0 or coalesce(p_discount, 0) < 0 or coalesce(p_fee, 0) < 0
     or coalesce(p_fee, 0) > p_amount then
    raise exception 'Harga modal, diskon, atau biaya tambahan tidak valid' using errcode = '22023';
  end if;

  insert into public.debts (business_id, contact_id, kind, amount, cash_moved,
                            debt_date, due_date, note, created_by,
                            is_sale, cost_amount, discount_amount, extra_fee)
  values (p_business, p_contact, p_kind, p_amount, p_cash_moved,
          coalesce(p_debt_date, current_date), p_due_date, p_note, auth.uid(),
          p_is_sale, coalesce(p_cost, 0), coalesce(p_discount, 0), coalesce(p_fee, 0))
  returning id into did;

  if p_cash_moved then
    select id into cat from public.categories
     where business_id = p_business and is_system
       and name = case p_kind when 'receivable' then 'Pemberian Piutang' else 'Penerimaan Utang' end;
    insert into public.cash_transactions (business_id, type, amount, category_id, note,
                                          txn_date, debt_id, created_by)
    values (p_business,
            case p_kind when 'receivable' then 'out'::public.txn_type else 'in'::public.txn_type end,
            p_amount, cat, p_note, coalesce(p_debt_date, current_date), did, auth.uid());
  end if;
  return did;
end $$;

revoke execute on function
  public.create_debt(uuid, uuid, public.debt_kind, bigint, boolean, date, date, text, boolean, bigint, bigint, bigint)
  from public, anon;
grant execute on function
  public.create_debt(uuid, uuid, public.debt_kind, bigint, boolean, date, date, text, boolean, bigint, bigint, bigint)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Laporan: ringkasan (kini dengan keuntungan) dan data harian untuk grafik
-- ---------------------------------------------------------------------------
create or replace function public.report_summary(p_business uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare res jsonb; sale_cash bigint; sale_cash_profit bigint; sale_debt bigint; sale_debt_profit bigint;
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  select jsonb_build_object(
    'total_in',  coalesce(sum(amount) filter (where type = 'in'  and txn_date between p_from and p_to), 0),
    'total_out', coalesce(sum(amount) filter (where type = 'out' and txn_date between p_from and p_to), 0),
    'balance',   coalesce(sum(case type when 'in' then amount else -amount end), 0)
  ) into res
  from public.cash_transactions
  where business_id = p_business and deleted_at is null;

  select coalesce(sum(amount - extra_fee), 0), coalesce(sum(amount - extra_fee - cost_amount), 0)
    into sale_cash, sale_cash_profit
  from public.cash_transactions
  where business_id = p_business and deleted_at is null
    and type = 'in' and is_sale and txn_date between p_from and p_to;

  select coalesce(sum(amount - extra_fee), 0), coalesce(sum(amount - extra_fee - cost_amount), 0)
    into sale_debt, sale_debt_profit
  from public.debts
  where business_id = p_business and deleted_at is null
    and is_sale and kind = 'receivable' and debt_date between p_from and p_to;

  return res || jsonb_build_object(
    'sales_total',     sale_cash + sale_debt,
    'profit',          sale_cash_profit + sale_debt_profit,
    'receivable_open', (select coalesce(sum(remaining), 0) from public.debt_balances
                         where business_id = p_business and kind = 'receivable'),
    'payable_open',    (select coalesce(sum(remaining), 0) from public.debt_balances
                         where business_id = p_business and kind = 'payable'));
end $$;

create function public.report_daily(p_business uuid, p_from date, p_to date)
returns table (day date, cash_in bigint, cash_out bigint, profit bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  if p_to < p_from or p_to - p_from > 1830 then
    raise exception 'Rentang tanggal tidak valid' using errcode = '22023';
  end if;
  return query
    with days as (
      select generate_series(p_from, p_to, interval '1 day')::date as d
    ),
    c as (
      select t.txn_date as d,
             sum(t.amount) filter (where t.type = 'in')  as ci,
             sum(t.amount) filter (where t.type = 'out') as co,
             sum(t.amount - t.extra_fee - t.cost_amount)
               filter (where t.type = 'in' and t.is_sale) as pr
      from public.cash_transactions t
      where t.business_id = p_business and t.deleted_at is null
        and t.txn_date between p_from and p_to
      group by t.txn_date
    ),
    dp as (
      select x.debt_date as d, sum(x.amount - x.extra_fee - x.cost_amount) as pr
      from public.debts x
      where x.business_id = p_business and x.deleted_at is null
        and x.is_sale and x.kind = 'receivable'
        and x.debt_date between p_from and p_to
      group by x.debt_date
    )
    select days.d,
           coalesce(c.ci, 0)::bigint,
           coalesce(c.co, 0)::bigint,
           (coalesce(c.pr, 0) + coalesce(dp.pr, 0))::bigint
    from days
    left join c  on c.d  = days.d
    left join dp on dp.d = days.d
    order by days.d;
end $$;

revoke execute on function public.report_daily(uuid, date, date) from public, anon;
grant execute on function public.report_daily(uuid, date, date) to authenticated;
