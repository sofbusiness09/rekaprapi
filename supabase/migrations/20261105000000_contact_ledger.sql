-- RekapRapi: pelunasan per kontak (Lunaskan / Terima pembayaran otomatis berurutan).
-- Jalankan SETELAH 20261104000000_sales_profit.sql, sekali saja.
--
-- pay_contact_debts membagi pembayaran ke utang/piutang terbuka milik satu kontak,
-- dari yang paling lama (tanggal, lalu waktu dibuat). Jumlah kurang dari total hanya
-- melunasi sebagian. Setiap potongan menghasilkan catatan kas otomatis, sama seperti
-- add_debt_payment.

-- ---------------------------------------------------------------------------
-- 1. View debt_balances dibuat ulang agar memuat kolom penjualan (is_sale, dst.)
--    yang ditambahkan setelah view pertama dibuat.
-- ---------------------------------------------------------------------------
drop view public.debt_balances;

create view public.debt_balances with (security_invoker = true) as
select d.*,
       coalesce(p.paid, 0)              as paid,
       d.amount - coalesce(p.paid, 0)   as remaining
from public.debts d
left join lateral (
  select sum(x.amount) as paid
  from public.debt_payments x
  where x.debt_id = d.id and x.deleted_at is null
) p on true
where d.deleted_at is null;

grant select on public.debt_balances to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Fungsi dalam: satu pembayaran + catatan kasnya (pemanggil sudah mengunci
--    utang dan memeriksa hak akses)
-- ---------------------------------------------------------------------------
create function public._insert_payment(d public.debts, p_amount bigint, p_paid_on date, p_note text)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare pid uuid; cat uuid;
begin
  insert into public.debt_payments (debt_id, business_id, amount, paid_on, note, created_by)
  values (d.id, d.business_id, p_amount, coalesce(p_paid_on, current_date), p_note, auth.uid())
  returning id into pid;

  select id into cat from public.categories
   where business_id = d.business_id and is_system
     and name = case d.kind when 'receivable' then 'Pelunasan Piutang' else 'Pembayaran Utang' end;

  insert into public.cash_transactions (business_id, type, amount, category_id, note,
                                        txn_date, debt_payment_id, created_by)
  values (d.business_id,
          case d.kind when 'receivable' then 'in'::public.txn_type else 'out'::public.txn_type end,
          p_amount, cat, p_note, coalesce(p_paid_on, current_date), pid, auth.uid());
  return pid;
end $$;

revoke execute on function public._insert_payment(public.debts, bigint, date, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Pelunasan per kontak
--    p_amount null = lunaskan semuanya. Mengembalikan jumlah yang dibayarkan.
-- ---------------------------------------------------------------------------
create function public.pay_contact_debts(
  p_business uuid,
  p_contact  uuid,
  p_kind     public.debt_kind,
  p_amount   bigint default null,
  p_paid_on  date default current_date,
  p_note     text default null
) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  d public.debts;
  total bigint;
  left_amt bigint;
  r bigint;
  pay bigint;
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);

  -- Kunci semua utang kontak ini agar dua pelunasan bersamaan tidak saling menimpa.
  perform 1 from public.debts x
   where x.business_id = p_business and x.contact_id = p_contact
     and x.kind = p_kind and x.deleted_at is null
   for update;

  select coalesce(sum(b.remaining), 0) into total
  from public.debt_balances b
  where b.business_id = p_business and b.contact_id = p_contact and b.kind = p_kind;

  if total <= 0 then
    raise exception 'Tidak ada yang perlu dilunasi' using errcode = '22023';
  end if;
  if p_amount is null then p_amount := total; end if;
  if p_amount <= 0 or p_amount > total then
    raise exception 'Jumlah harus antara 1 dan sisa (%)', total using errcode = '22023';
  end if;

  left_amt := p_amount;
  for d in
    select x.* from public.debts x
     where x.business_id = p_business and x.contact_id = p_contact
       and x.kind = p_kind and x.deleted_at is null
     order by x.debt_date, x.created_at, x.id
  loop
    select d.amount - coalesce(sum(pp.amount), 0) into r
      from public.debt_payments pp
     where pp.debt_id = d.id and pp.deleted_at is null;
    continue when r <= 0;

    pay := least(r, left_amt);
    perform public._insert_payment(d, pay, p_paid_on, p_note);
    left_amt := left_amt - pay;
    exit when left_amt <= 0;
  end loop;

  return p_amount;
end $$;

revoke execute on function
  public.pay_contact_debts(uuid, uuid, public.debt_kind, bigint, date, text)
  from public, anon;
grant execute on function
  public.pay_contact_debts(uuid, uuid, public.debt_kind, bigint, date, text)
  to authenticated;
