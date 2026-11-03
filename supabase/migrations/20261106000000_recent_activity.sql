-- RekapRapi: feed aktivitas perputaran uang untuk Beranda.
-- Jalankan SETELAH 20261105000000_contact_ledger.sql, sekali saja.
--
-- recent_activity menyatukan SEMUA aktivitas uang usaha, terbaru dulu:
--   * transaksi kas (masuk/keluar, lunas) termasuk kas otomatis dari pelunasan
--     dan pemberian/penerimaan pinjaman uang  -> kind = 'cash'
--   * transaksi hutang (barang dijual/dibeli kredit, uang belum berpindah)
--                                              -> kind = 'credit'
-- Catatan utang yang uangnya sudah berpindah tidak muncul dua kali: yang tampil
-- adalah catatan kas otomatisnya.

create function public.recent_activity(
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
           (case when t.is_sale then t.amount - t.extra_fee - t.cost_amount end)::bigint,
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
           (case when d.is_sale then d.amount - d.extra_fee - d.cost_amount end)::bigint,
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

revoke execute on function public.recent_activity(uuid, int, int) from public, anon;
grant execute on function public.recent_activity(uuid, int, int) to authenticated;
