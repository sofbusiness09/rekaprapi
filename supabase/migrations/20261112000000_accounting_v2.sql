-- RekapRapi: dasar akuntansi baru untuk Pembukuan Usaha. Jalankan SETELAH
-- 20261111000000_rekapan_kind.sql, sekali saja.
--
-- Aturan (khusus Pembukuan Usaha):
--   Pemasukan   = penjualan (lunas maupun utang, dihitung saat dijual)
--                 + penjualan lainnya (pemasukan bukan penjualan, termasuk biaya tambahan)
--   Pengeluaran = modal barang (cost_amount dari penjualan)
--                 + pengeluaran biasa (lunas) + pengeluaran berstatus hutang (saat dicatat)
--   Laba/rugi   = Pemasukan - Pengeluaran
--
-- Utang dan piutang yang uangnya berpindah (cash_moved), serta pembayaran dan
-- pelunasannya, adalah pinjaman: tidak masuk pemasukan maupun pengeluaran.
-- Catatan hutang tanpa perpindahan uang (cash_moved = false) adalah barang atau jasa
-- yang ditukar secara kredit: piutang masuk pemasukan, utang masuk pengeluaran.
--
-- Pembelian stok tidak lagi dicatat; modal dihitung saat barang terjual.

-- ---------------------------------------------------------------------------
-- 1. Kategori: hapus "Pembelian Stok", "Pemasukan Lain" menjadi "Penjualan lainnya"
-- ---------------------------------------------------------------------------
do $$
declare used int;
begin
  -- Yang dipakai transaksi tidak dihapus (agar tidak ada transaksi kehilangan kategori).
  select count(*) into used
  from public.categories c
  where c.name = 'Pembelian Stok' and not c.is_system
    and exists (select 1 from public.cash_transactions t where t.category_id = c.id);
  if used > 0 then
    raise notice '% kategori "Pembelian Stok" masih dipakai transaksi dan tidak dihapus', used;
  end if;

  delete from public.categories c
  where c.name = 'Pembelian Stok' and not c.is_system
    and not exists (select 1 from public.cash_transactions t where t.category_id = c.id);

  update public.categories c
     set name = 'Penjualan lainnya'
   where c.name = 'Pemasukan Lain' and c.type = 'in' and not c.is_system
     and exists (select 1 from public.businesses b
                  where b.id = c.business_id and b.kind = 'business')
     and not exists (select 1 from public.categories x
                      where x.business_id = c.business_id and x.type = 'in'
                        and x.name = 'Penjualan lainnya');
end $$;

-- ---------------------------------------------------------------------------
-- 2. create_business: kategori awal Pembukuan Usaha yang baru
-- ---------------------------------------------------------------------------
create or replace function public.create_business(
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

  insert into public.businesses (name, address, phone, created_by, kind)
  values (btrim(p_name), p_address, p_phone, uid, p_kind) returning id into bid;
  insert into public.business_members (business_id, user_id, role) values (bid, uid, 'owner');

  insert into public.categories (business_id, name, type, is_system) values
    (bid, 'Pemberian Piutang',  'out', true),
    (bid, 'Pelunasan Piutang',  'in',  true),
    (bid, 'Penerimaan Utang',   'in',  true),
    (bid, 'Pembayaran Utang',   'out', true);

  if p_kind = 'business' then
    insert into public.categories (business_id, name, type, is_sale) values
      (bid, 'Penjualan',        'in',  true);
    insert into public.categories (business_id, name, type) values
      (bid, 'Penjualan lainnya', 'in'),
      (bid, 'Gaji',              'out'),
      (bid, 'Sewa',              'out'),
      (bid, 'Listrik & Air',     'out'),
      (bid, 'Transportasi',      'out'),
      (bid, 'Pengeluaran Lain',  'out');
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

-- ---------------------------------------------------------------------------
-- 3. Ringkasan: pemasukan, pengeluaran, dan laba
-- ---------------------------------------------------------------------------
create or replace function public.report_summary(p_business uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  res jsonb;
  s_cash bigint; s_cash_cost bigint;       -- penjualan lunas dan modalnya
  s_debt bigint; s_debt_cost bigint;       -- penjualan utang dan modalnya
  o_cash bigint; o_debt bigint;            -- penjualan lainnya (lunas, utang)
  e_cash bigint; e_debt bigint;            -- pengeluaran biasa (lunas, hutang)
  inc_sales bigint; inc_other bigint; cost bigint; exp_other bigint;
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);

  select jsonb_build_object(
    'total_in',  coalesce(sum(amount) filter (where type = 'in'  and txn_date between p_from and p_to), 0),
    'total_out', coalesce(sum(amount) filter (where type = 'out' and txn_date between p_from and p_to), 0),
    'balance',   coalesce(sum(case type when 'in' then amount else -amount end), 0)
  ) into res
  from public.cash_transactions
  where business_id = p_business and deleted_at is null;

  -- Catatan kas yang dibuat otomatis oleh utang piutang (debt_id / debt_payment_id) selalu
  -- dikecualikan: itu perpindahan uang pinjaman, bukan pemasukan atau pengeluaran.
  select coalesce(sum(amount) filter (where type = 'in' and is_sale), 0),
         coalesce(sum(cost_amount) filter (where type = 'in' and is_sale), 0),
         coalesce(sum(amount) filter (where type = 'in' and not is_sale), 0),
         coalesce(sum(amount) filter (where type = 'out'), 0)
    into s_cash, s_cash_cost, o_cash, e_cash
  from public.cash_transactions
  where business_id = p_business and deleted_at is null
    and debt_id is null and debt_payment_id is null
    and txn_date between p_from and p_to;

  select coalesce(sum(amount) filter (where is_sale), 0),
         coalesce(sum(cost_amount) filter (where is_sale), 0),
         coalesce(sum(amount) filter (where not is_sale), 0)
    into s_debt, s_debt_cost, o_debt
  from public.debts
  where business_id = p_business and deleted_at is null
    and kind = 'receivable' and not cash_moved
    and debt_date between p_from and p_to;

  select coalesce(sum(amount), 0) into e_debt
  from public.debts
  where business_id = p_business and deleted_at is null
    and kind = 'payable' and not cash_moved
    and debt_date between p_from and p_to;

  inc_sales := s_cash + s_debt;
  inc_other := o_cash + o_debt;
  cost      := s_cash_cost + s_debt_cost;
  exp_other := e_cash + e_debt;

  return res || jsonb_build_object(
    'income_sales',   inc_sales,
    'income_other',   inc_other,
    'income_total',   inc_sales + inc_other,
    'expense_cost',   cost,
    'expense_other',  exp_other,
    'expense_credit', e_debt,
    'expense_total',  cost + exp_other,
    'net',            inc_sales + inc_other - cost - exp_other,
    -- Nama lama: penjualan dan keuntungan per penjualan (penjualan - modal).
    'sales_total',    inc_sales,
    'profit',         inc_sales - cost,
    'receivable_open', (select coalesce(sum(remaining), 0) from public.debt_balances
                         where business_id = p_business and kind = 'receivable'),
    'payable_open',    (select coalesce(sum(remaining), 0) from public.debt_balances
                         where business_id = p_business and kind = 'payable'));
end $$;

-- ---------------------------------------------------------------------------
-- 4. Data harian untuk grafik: pemasukan, pengeluaran, laba per hari
-- ---------------------------------------------------------------------------
create function public.report_daily_pl(p_business uuid, p_from date, p_to date)
returns table (day date, income bigint, expense bigint, net bigint)
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
    ev as (
      select t.txn_date as d,
             (case when t.type = 'in' then t.amount else 0 end)::bigint as inc,
             ((case when t.type = 'out' then t.amount else 0 end)
              + (case when t.type = 'in' and t.is_sale then t.cost_amount else 0 end))::bigint as exp
      from public.cash_transactions t
      where t.business_id = p_business and t.deleted_at is null
        and t.debt_id is null and t.debt_payment_id is null
        and t.txn_date between p_from and p_to
      union all
      select x.debt_date,
             (case when x.kind = 'receivable' then x.amount else 0 end)::bigint,
             ((case when x.kind = 'payable' then x.amount else 0 end)
              + (case when x.kind = 'receivable' and x.is_sale then x.cost_amount else 0 end))::bigint
      from public.debts x
      where x.business_id = p_business and x.deleted_at is null
        and not x.cash_moved
        and x.debt_date between p_from and p_to
    ),
    agg as (
      select ev.d, sum(ev.inc) as i, sum(ev.exp) as e from ev group by ev.d
    )
    select days.d,
           coalesce(agg.i, 0)::bigint,
           coalesce(agg.e, 0)::bigint,
           (coalesce(agg.i, 0) - coalesce(agg.e, 0))::bigint
    from days
    left join agg on agg.d = days.d
    order by days.d;
end $$;

revoke execute on function public.report_daily_pl(uuid, date, date) from public, anon;
grant execute on function public.report_daily_pl(uuid, date, date) to authenticated;


-- ---------------------------------------------------------------------------
-- 4b. report_daily lama: keuntungan harian memakai rumus yang sama (jumlah - modal)
-- ---------------------------------------------------------------------------
create or replace function public.report_daily(p_business uuid, p_from date, p_to date)
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
             sum(t.amount - t.cost_amount)
               filter (where t.type = 'in' and t.is_sale) as pr
      from public.cash_transactions t
      where t.business_id = p_business and t.deleted_at is null
        and t.txn_date between p_from and p_to
      group by t.txn_date
    ),
    dp as (
      select x.debt_date as d, sum(x.amount - x.cost_amount) as pr
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
-- ---------------------------------------------------------------------------
-- 5. Aktivitas terbaru: keuntungan per penjualan = jumlah - modal (biaya tambahan ikut)
-- ---------------------------------------------------------------------------
create or replace function public.recent_activity(
  p_business uuid,
  p_limit    int default 10,
  p_offset   int default 0
)
returns table (
  kind         text,
  ref_id       uuid,
  debt_id      uuid,
  txn_date     date,
  created_at   timestamptz,
  flow         text,
  amount       bigint,
  title        text,
  contact_name text,
  note         text,
  is_sale      boolean,
  profit       bigint,
  remaining    bigint,
  created_by   uuid,
  is_auto      boolean
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  if p_limit is null or p_limit < 1 or p_limit > 200 then p_limit := 10; end if;
  if p_offset is null or p_offset < 0 then p_offset := 0; end if;

  return query
  select * from (
    select 'cash'::text,
           t.id,
           coalesce(t.debt_id, pay.debt_id),
           t.txn_date,
           t.created_at,
           t.type::text,
           t.amount,
           coalesce(c.name, 'Tanpa kategori'),
           ct.name,
           t.note,
           t.is_sale,
           (case when t.is_sale then t.amount - t.cost_amount end)::bigint,
           null::bigint,
           t.created_by,
           (t.debt_id is not null or t.debt_payment_id is not null)
    from public.cash_transactions t
    left join public.categories c   on c.id = t.category_id
    left join public.debt_payments pay on pay.id = t.debt_payment_id
    left join public.debts dd       on dd.id = coalesce(t.debt_id, pay.debt_id)
    left join public.contacts ct    on ct.id = dd.contact_id
    where t.business_id = p_business and t.deleted_at is null

    union all

    select 'credit'::text,
           d.id,
           d.id,
           d.debt_date,
           d.created_at,
           (case d.kind when 'receivable' then 'in' else 'out' end)::text,
           d.amount,
           (case when d.is_sale then 'Penjualan'
                 when d.kind = 'receivable' then 'Piutang'
                 else 'Utang' end)::text,
           ct.name,
           d.note,
           d.is_sale,
           (case when d.is_sale then d.amount - d.cost_amount end)::bigint,
           (d.amount - coalesce((select sum(x.amount) from public.debt_payments x
                                  where x.debt_id = d.id and x.deleted_at is null), 0))::bigint,
           d.created_by,
           false
    from public.debts d
    join public.contacts ct on ct.id = d.contact_id
    where d.business_id = p_business and d.deleted_at is null and not d.cash_moved
  ) a
  order by 4 desc, 5 desc
  limit p_limit offset p_offset;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Diagram per kategori untuk Pembukuan Usaha: totalnya sama dengan Pemasukan dan Pengeluaran
-- ---------------------------------------------------------------------------
create function public.report_pl_by_category(p_business uuid, p_from date, p_to date)
returns table (category_name text, type text, total bigint, tx_count bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  return query
    with ev as (
      select t.type::text as ty,
             (case when t.type = 'in' and t.is_sale then 'Penjualan'
                   else coalesce(c.name, 'Tanpa kategori') end)::text as nm,
             t.amount::bigint as amt,
             (case when t.type = 'in' and t.is_sale then t.cost_amount else 0 end)::bigint as cost
      from public.cash_transactions t
      left join public.categories c on c.id = t.category_id
      where t.business_id = p_business and t.deleted_at is null
        and t.debt_id is null and t.debt_payment_id is null
        and t.txn_date between p_from and p_to
      union all
      select (case when d.kind = 'receivable' then 'in' else 'out' end)::text,
             (case when d.kind = 'receivable' and d.is_sale then 'Penjualan'
                   when d.kind = 'receivable' then 'Penjualan lainnya'
                   else 'Pengeluaran hutang' end)::text,
             d.amount::bigint,
             (case when d.kind = 'receivable' and d.is_sale then d.cost_amount else 0 end)::bigint
      from public.debts d
      where d.business_id = p_business and d.deleted_at is null
        and not d.cash_moved
        and d.debt_date between p_from and p_to
    )
    select r.nm, r.ty, r.tot, r.cnt from (
      select ev.nm, ev.ty, sum(ev.amt)::bigint as tot, count(*)::bigint as cnt
      from ev group by ev.ty, ev.nm
      union all
      select 'Modal barang'::text, 'out'::text, sum(ev.cost)::bigint, count(*) filter (where ev.cost > 0)::bigint
      from ev having sum(ev.cost) > 0
    ) r
    order by r.ty, r.tot desc;
end $$;

revoke execute on function public.report_pl_by_category(uuid, date, date) from public, anon;
grant execute on function public.report_pl_by_category(uuid, date, date) to authenticated;