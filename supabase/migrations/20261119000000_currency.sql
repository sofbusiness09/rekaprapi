-- RekapRapi: mata uang per pembukuan.
-- Satu pembukuan memakai satu mata uang (bawaan IDR). Jumlah tetap bilangan bulat
-- tanpa sen; mengganti mata uang hanya mengganti tampilan, bukan mengonversi nilai.
-- Jalankan sekali di SQL Editor Supabase, setelah migrasi 20261118000000.

alter table public.businesses
  add column currency text not null default 'IDR'
    check (currency ~ '^[A-Z]{3}$');

-- Pemilik dan Admin boleh mengganti (aturan baris businesses_update sudah membatasi).
grant update (currency) on public.businesses to authenticated;

-- Bot Telegram: mata uang ikut dalam data pembukuan yang dikirim ke bot.
create or replace function public.tg_context(p_tg_id bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  l public.telegram_links;
  v_active uuid;
  v_list jsonb;
begin
  select * into l from public.telegram_links where telegram_id = p_tg_id;
  if l.telegram_id is null then return jsonb_build_object('linked', false); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'name', b.name, 'kind', b.kind, 'role', m.role,
           'currency', b.currency) order by b.name), '[]')
    into v_list
    from public.business_members m
    join public.businesses b on b.id = m.business_id and b.deleted_at is null
   where m.user_id = l.user_id and not b.restoring;

  select (e ->> 'id')::uuid into v_active
    from jsonb_array_elements(v_list) e
   where (e ->> 'id')::uuid = l.active_business_id;
  if v_active is null then
    select (e ->> 'id')::uuid into v_active from jsonb_array_elements(v_list) e limit 1;
    update public.telegram_links set active_business_id = v_active, pending = null
     where telegram_id = p_tg_id;
  end if;

  return jsonb_build_object(
    'linked', true,
    'business', (select e from jsonb_array_elements(v_list) e
                  where (e ->> 'id')::uuid = v_active),
    'businesses', v_list);
end $$;

create or replace function public.tg_daily_batch() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  l record; c record; s jsonb; d jsonb; v_cur text;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  out_rows jsonb := '[]';
begin
  for l in select telegram_id, chat_id from public.telegram_links where daily_report loop
    select * into c from public._tg_ctx(l.telegram_id);
    continue when c.business_id is null;
    s := public._tg_summary(c.business_id, c.kind, c.role, v_today, v_today);
    d := public._tg_due(c.business_id, v_today + 3);
    continue when jsonb_array_length(d) = 0
      and coalesce((s ->> 'income_total')::bigint, 0) = 0
      and coalesce((s ->> 'expense_total')::bigint, 0) = 0
      and not exists (select 1 from public.cash_transactions t
                       where t.business_id = c.business_id and t.deleted_at is null
                         and t.txn_date = v_today);
    select currency into v_cur from public.businesses where id = c.business_id;
    out_rows := out_rows || jsonb_build_object(
      'chat_id', l.chat_id, 'to', v_today,
      'business', jsonb_build_object('name', c.name, 'kind', c.kind, 'role', c.role,
                                     'currency', v_cur),
      'summary', s, 'due', d);
  end loop;
  return out_rows;
end $$;
