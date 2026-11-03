-- RekapRapi: tambalan kecil untuk 20261107000000_contact_netting.sql.
-- AMAN dijalankan berulang (hanya create or replace dan satu update).
-- Jalankan bila migrasi 20261107000000 sudah pernah dijalankan dengan versi lama berkas itu:
--   * catatan kompensasi memakai kata "titipan" -> diganti "utang"
--   * kompensasi otomatis tidak boleh dihapus sendiri (menjaga saldo satu arah)

create or replace function public._offset_contact(p_business uuid, p_contact uuid) returns bigint
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
      (r.id, p_business, x, current_date, 'Dikompensasi dengan utang',   auth.uid(), 'offset', g),
      (p.id, p_business, x, current_date, 'Dikompensasi dengan piutang', auth.uid(), 'offset', g);
    total := total + x;
  end loop;
  return total;
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

-- Catatan kompensasi lama yang masih memakai kata "titipan".
update public.debt_payments
   set note = 'Dikompensasi dengan utang'
 where method = 'offset' and note = 'Dikompensasi dengan titipan/utang';
