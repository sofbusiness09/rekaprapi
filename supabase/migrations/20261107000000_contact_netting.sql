-- RekapRapi: saldo bersih per kontak (piutang dan utang tidak lagi terpisah)
-- dan pengelolaan kontak. Jalankan SETELAH 20261106000000_recent_activity.sql, sekali saja.
--
-- Aturan:
--   * Satu kontak hanya punya utang piutang terbuka ke satu arah. Piutang (kontak berutang
--     kepada Anda: Anda memberi hutang) dan utang (Anda berutang kepada kontak: Anda diberi utang/modal) saling
--     mengurangi.
--   * Saat transaksi hutang dicatat (create_debt) dan kontak punya catatan arah
--     berlawanan yang masih terbuka, keduanya otomatis dikompensasi tanpa menggerakkan
--     kas (debt_payments.method = 'offset', berpasangan lewat offset_group).
--   * contact_transfer("receive"/"give") mencatat uang yang benar-benar berpindah:
--     melunasi arah yang ada lebih dulu (terlama dulu); kelebihannya menjadi catatan
--     baru ke arah sebaliknya (utang atau piutang).

-- ---------------------------------------------------------------------------
-- 1. Kolom dan hak akses
-- ---------------------------------------------------------------------------
alter table public.contacts add column address text;

grant insert (address) on public.contacts to authenticated;
grant update (address) on public.contacts to authenticated;
-- Menghapus kontak hanya lewat delete_contact (Pemilik/Admin, tanpa saldo terbuka).
revoke update (deleted_at) on public.contacts from authenticated;

-- Semua anggota boleh mengubah data kontak (nomor telepon, alamat, dsb).
drop policy contacts_update on public.contacts;
create policy contacts_update on public.contacts for update to authenticated
  using (public.is_member(business_id))
  with check (public.is_member(business_id));

alter table public.debt_payments
  add column method text not null default 'cash' check (method in ('cash', 'offset')),
  add column offset_group uuid,
  add constraint debt_payments_offset_chk check ((method = 'offset') = (offset_group is not null));

create index debt_payments_offset_idx on public.debt_payments (offset_group)
  where offset_group is not null;

-- ---------------------------------------------------------------------------
-- 2. Fungsi dalam
-- ---------------------------------------------------------------------------
create function public._debt_remaining(p_debt uuid) returns bigint
language sql stable security definer set search_path = public, pg_temp as $$
  select d.amount - coalesce((select sum(x.amount) from public.debt_payments x
                               where x.debt_id = d.id and x.deleted_at is null), 0)
  from public.debts d
  where d.id = p_debt and d.deleted_at is null
$$;

-- Mengompensasi piutang dengan utang milik satu kontak, terlama dulu, tanpa kas.
-- Mengembalikan total yang dikompensasi.
create function public._offset_contact(p_business uuid, p_contact uuid) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.debts; p public.debts;
  x bigint; g uuid; total bigint := 0;
begin
  perform 1 from public.debts d
   where d.business_id = p_business and d.contact_id = p_contact and d.deleted_at is null
   for update;

  loop
    select d.* into r from public.debts d
     where d.business_id = p_business and d.contact_id = p_contact
       and d.kind = 'receivable' and d.deleted_at is null
       and public._debt_remaining(d.id) > 0
     order by d.debt_date, d.created_at, d.id
     limit 1;
    exit when not found;

    select d.* into p from public.debts d
     where d.business_id = p_business and d.contact_id = p_contact
       and d.kind = 'payable' and d.deleted_at is null
       and public._debt_remaining(d.id) > 0
     order by d.debt_date, d.created_at, d.id
     limit 1;
    exit when not found;

    x := least(public._debt_remaining(r.id), public._debt_remaining(p.id));
    g := gen_random_uuid();
    insert into public.debt_payments
      (debt_id, business_id, amount, paid_on, note, created_by, method, offset_group)
    values
      (r.id, p_business, x, current_date, 'Dikompensasi dengan utang', auth.uid(), 'offset', g),
      (p.id, p_business, x, current_date, 'Dikompensasi dengan piutang',       auth.uid(), 'offset', g);
    total := total + x;
  end loop;
  return total;
end $$;

revoke execute on function public._debt_remaining(uuid) from public, anon, authenticated;
revoke execute on function public._offset_contact(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. create_debt: setelah mencatat, kompensasikan dengan catatan arah berlawanan
-- ---------------------------------------------------------------------------
create or replace function public.create_debt(
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

  perform public._offset_contact(p_business, p_contact);
  return did;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Uang yang berpindah per kontak: terima / berikan
-- ---------------------------------------------------------------------------
create function public.contact_transfer(
  p_business  uuid,
  p_contact   uuid,
  p_direction text,
  p_amount    bigint,
  p_paid_on   date default current_date,
  p_note      text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  settle_kind public.debt_kind;
  new_kind public.debt_kind;
  d public.debts;
  r bigint; pay bigint; left_amt bigint; settled bigint := 0;
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  if p_direction not in ('receive', 'give') then
    raise exception 'Arah tidak valid' using errcode = '22023';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Jumlah harus lebih dari 0' using errcode = '22023';
  end if;
  if not exists (select 1 from public.contacts c
                  where c.id = p_contact and c.business_id = p_business and c.deleted_at is null) then
    raise exception 'Kontak tidak ditemukan' using errcode = 'P0002';
  end if;

  perform public._offset_contact(p_business, p_contact);

  -- Terima uang: melunasi piutang; kelebihannya menjadi utang (Anda berutang kepada kontak).
  -- Berikan uang: melunasi utang; kelebihannya menjadi piutang (Anda memberi hutang).
  settle_kind := case when p_direction = 'receive' then 'receivable' else 'payable' end;
  new_kind    := case when p_direction = 'receive' then 'payable'    else 'receivable' end;

  left_amt := p_amount;
  for d in
    select x.* from public.debts x
     where x.business_id = p_business and x.contact_id = p_contact
       and x.kind = settle_kind and x.deleted_at is null
     order by x.debt_date, x.created_at, x.id
  loop
    r := public._debt_remaining(d.id);
    continue when r <= 0;
    pay := least(r, left_amt);
    perform public._insert_payment(d, pay, p_paid_on, p_note);
    settled := settled + pay;
    left_amt := left_amt - pay;
    exit when left_amt <= 0;
  end loop;

  if left_amt > 0 then
    perform public.create_debt(p_business, p_contact, new_kind, left_amt, true, p_paid_on, null, p_note);
  end if;

  return jsonb_build_object('settled', settled, 'new_debt', left_amt);
end $$;

-- Lunaskan saldo bersih: terima bila kontak berutang, bayar/kembalikan bila Anda berutang.
create function public.settle_contact(
  p_business uuid,
  p_contact  uuid,
  p_paid_on  date default current_date,
  p_note     text default null
) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare net bigint;
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  perform public._offset_contact(p_business, p_contact);

  select coalesce(sum(case b.kind when 'receivable' then b.remaining else -b.remaining end), 0)
    into net
  from public.debt_balances b
  where b.business_id = p_business and b.contact_id = p_contact;

  if net = 0 then
    raise exception 'Tidak ada yang perlu dilunasi' using errcode = '22023';
  end if;
  if net > 0 then
    perform public.contact_transfer(p_business, p_contact, 'receive', net, p_paid_on, p_note);
  else
    perform public.contact_transfer(p_business, p_contact, 'give', -net, p_paid_on, p_note);
  end if;
  return abs(net);
end $$;

create function public.delete_contact(p_contact uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.contacts;
begin
  select * into c from public.contacts where id = p_contact and deleted_at is null;
  if not found then raise exception 'Kontak tidak ditemukan' using errcode = 'P0002'; end if;
  perform public._require(c.business_id, array['owner', 'admin']::public.member_role[]);
  if exists (select 1 from public.debt_balances b
              where b.contact_id = p_contact and b.remaining > 0) then
    raise exception 'Masih ada utang piutang yang belum lunas' using errcode = '22023';
  end if;
  update public.contacts set deleted_at = now() where id = p_contact;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Menghapus catatan/pembayaran yang berpasangan kompensasi
-- ---------------------------------------------------------------------------
create or replace function public.delete_debt(p_debt uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare d public.debts;
begin
  select * into d from public.debts where id = p_debt and deleted_at is null for update;
  if not found then raise exception 'Data tidak ditemukan' using errcode = 'P0002'; end if;
  if not public._can_modify(d.business_id, d.created_by) then
    raise exception 'Tidak punya akses' using errcode = '42501';
  end if;

  update public.cash_transactions set deleted_at = now()
   where deleted_at is null
     and (debt_id = p_debt
          or debt_payment_id in (select id from public.debt_payments where debt_id = p_debt));

  -- Pasangan kompensasi di catatan lawan ikut dihapus agar saldonya kembali.
  update public.debt_payments set deleted_at = now()
   where deleted_at is null
     and offset_group in (select o.offset_group from public.debt_payments o
                           where o.debt_id = p_debt and o.method = 'offset');

  update public.debt_payments set deleted_at = now() where debt_id = p_debt and deleted_at is null;
  update public.debts set deleted_at = now() where id = p_debt;
end $$;

create or replace function public.update_debt_payment(
  p_payment uuid,
  p_amount  bigint,
  p_paid_on date,
  p_note    text
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare pay public.debt_payments; d public.debts; others bigint;
begin
  select * into pay from public.debt_payments where id = p_payment and deleted_at is null;
  if not found then raise exception 'Data tidak ditemukan' using errcode = 'P0002'; end if;
  if pay.method = 'offset' then
    raise exception 'Kompensasi tidak dapat diubah. Hapus lalu catat ulang.' using errcode = '22023';
  end if;
  select * into d from public.debts where id = pay.debt_id for update;
  if not public._can_modify(pay.business_id, pay.created_by) then
    raise exception 'Tidak punya akses' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Jumlah harus lebih dari 0' using errcode = '22023';
  end if;
  select coalesce(sum(amount), 0) into others
    from public.debt_payments where debt_id = d.id and deleted_at is null and id <> p_payment;
  if p_amount > d.amount - others then
    raise exception 'Pembayaran melebihi sisa' using errcode = '22023';
  end if;

  update public.debt_payments
     set amount = p_amount, paid_on = coalesce(p_paid_on, paid_on), note = p_note
   where id = p_payment;
  update public.cash_transactions
     set amount = p_amount, txn_date = coalesce(p_paid_on, txn_date), note = p_note
   where debt_payment_id = p_payment and deleted_at is null;
end $$;

create or replace function public.delete_debt_payment(p_payment uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare pay public.debt_payments;
begin
  select * into pay from public.debt_payments where id = p_payment and deleted_at is null;
  if not found then raise exception 'Data tidak ditemukan' using errcode = 'P0002'; end if;
  perform 1 from public.debts where id = pay.debt_id for update;
  if not public._can_modify(pay.business_id, pay.created_by) then
    raise exception 'Tidak punya akses' using errcode = '42501';
  end if;

  -- Kompensasi otomatis tidak dihapus sendiri: membukanya kembali akan membuat piutang
  -- dan utang terbuka bersamaan, lalu langsung dikompensasi ulang. Hapus catatan penjualan
  -- atau utang yang salah; pasangan kompensasinya ikut terhapus (lihat delete_debt).
  if pay.method = 'offset' then
    raise exception 'Kompensasi otomatis tidak dapat dihapus. Hapus catatan penjualan atau utang terkait bila salah.'
      using errcode = '22023';
  end if;

  update public.cash_transactions set deleted_at = now()
   where debt_payment_id = p_payment and deleted_at is null;
  update public.debt_payments set deleted_at = now() where id = p_payment;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Hak eksekusi
-- ---------------------------------------------------------------------------
revoke execute on function
  public.contact_transfer(uuid, uuid, text, bigint, date, text),
  public.settle_contact(uuid, uuid, date, text),
  public.delete_contact(uuid)
  from public, anon;
grant execute on function
  public.contact_transfer(uuid, uuid, text, bigint, date, text),
  public.settle_contact(uuid, uuid, date, text),
  public.delete_contact(uuid)
  to authenticated;
