-- RekapRapi: aktivitas terakhir per kontak, untuk urutan bawaan tab Utang.
-- Aktivitas = kontak dibuat, catatan utang/piutang dibuat, diubah, atau dihapus,
-- dan pembayaran/cicilan/pelunasan (termasuk perubahan dan penghapusannya).
-- Jalankan sekali di SQL Editor Supabase, setelah migrasi 20261119000000.

create function public.contact_activity(p_business uuid)
returns table (contact_id uuid, last_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  return query
  with ev as (
    select c.id as cid, c.created_at as at
      from public.contacts c
     where c.business_id = p_business and c.deleted_at is null
    union all
    select d.contact_id, d.created_at
      from public.debts d
     where d.business_id = p_business
    union all
    select d.contact_id, p.created_at
      from public.debt_payments p
      join public.debts d on d.id = p.debt_id
     where p.business_id = p_business
    -- Perubahan dan penghapusan tercatat di riwayat aktivitas.
    union all
    select d.contact_id, a.at
      from public.activity_log a
      join public.debts d on d.id = a.entity_id
     where a.business_id = p_business and a.entity = 'debts'
    union all
    select d.contact_id, a.at
      from public.activity_log a
      join public.debt_payments p on p.id = a.entity_id
      join public.debts d on d.id = p.debt_id
     where a.business_id = p_business and a.entity = 'debt_payments'
  )
  select ev.cid, max(ev.at)
    from ev
    join public.contacts c on c.id = ev.cid and c.deleted_at is null
   group by ev.cid;
end $$;

revoke all on function public.contact_activity(uuid) from public, anon;
grant execute on function public.contact_activity(uuid) to authenticated;
