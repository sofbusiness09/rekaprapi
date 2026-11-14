-- RekapRapi: kategori yang paling sering dipakai.
-- Formulir Pemasukan/Pengeluaran menampilkan 5 kategori tersering dalam 90 hari terakhir
-- (dihitung dari semua anggota pembukuan); sisanya di balik tombol "Lainnya".
-- Jalankan sekali di SQL Editor Supabase, setelah migrasi 20261116000000.

create function public.category_usage(p_business uuid)
returns table (category_id uuid, uses bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  return query
    select t.category_id, count(*)::bigint
      from public.cash_transactions t
     where t.business_id = p_business
       and t.deleted_at is null
       and t.category_id is not null
       -- Kas otomatis dari utang piutang bukan pilihan pengguna.
       and t.debt_id is null and t.debt_payment_id is null
       and t.txn_date >= current_date - 90
     group by t.category_id;
end $$;

revoke all on function public.category_usage(uuid) from public, anon;
grant execute on function public.category_usage(uuid) to authenticated;
