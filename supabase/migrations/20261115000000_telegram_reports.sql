-- RekapRapi: Bot Telegram tahap 2.
--   * tanya ringkasan (/hari_ini, /bulan_ini, /utang)
--   * mencatat utang piutang dan penjualan utang lewat chat
--   * ringkasan harian terjadwal dan pengingat jatuh tempo
-- Semua fungsi tg_* hanya untuk server bot (service_role).
-- Jalankan sekali di SQL Editor Supabase, setelah migrasi 20261114000001.

alter table public.telegram_links
  add column daily_report  boolean not null default true,
  add column last_debt_id  uuid;

-- ---------------------------------------------------------------------------
-- 1. Bantuan: pembukuan aktif pengirim, sekaligus bertindak sebagai pengguna itu
-- ---------------------------------------------------------------------------
create function public._tg_ctx(
  p_tg_id bigint,
  out user_id uuid, out business_id uuid, out name text, out kind text,
  out role public.member_role
)
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  select l.user_id, b.id, b.name, b.kind, m.role
    into user_id, business_id, name, kind, role
    from public.telegram_links l
    join public.businesses b on b.id = l.active_business_id
                            and b.deleted_at is null and not b.restoring
    join public.business_members m on m.business_id = b.id and m.user_id = l.user_id
   where l.telegram_id = p_tg_id;
  if user_id is not null then
    -- Fungsi lain (ringkasan, create_debt, riwayat) memeriksa dan mencatat pengguna ini.
    perform set_config('request.jwt.claims',
                       jsonb_build_object('sub', user_id, 'role', 'authenticated')::text, true);
  end if;
end $$;

-- Staf Pembukuan Usaha tidak menerima angka pengeluaran, modal, laba, dan saldo.
create function public._tg_summary(p_business uuid, p_kind text, p_role public.member_role,
                                   p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare s jsonb;
begin
  s := public.report_summary(p_business, p_from, p_to);
  if p_kind = 'business' and p_role = 'staff' then
    s := s - array['expense_cost', 'expense_other', 'expense_credit', 'expense_total',
                   'net', 'profit', 'balance', 'total_out', 'total_in'];
  end if;
  return s;
end $$;

-- Catatan yang jatuh tempo sampai p_until dan belum lunas.
create function public._tg_due(p_business uuid, p_until date) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(x order by x.due_date), '[]')
  from (
    select c.name, d.kind, d.remaining, d.due_date
      from public.debt_balances d
      join public.contacts c on c.id = d.contact_id
     where d.business_id = p_business and d.remaining > 0
       and d.due_date is not null and d.due_date <= p_until
     order by d.due_date
     limit 10
  ) x
$$;

-- ---------------------------------------------------------------------------
-- 2. Tanya ringkasan
-- ---------------------------------------------------------------------------
-- p_period: 'today' atau 'month' (awal bulan sampai hari ini), waktu Indonesia barat.
create function public.tg_report(p_tg_id bigint, p_period text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c record;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_from date;
begin
  select * into c from public._tg_ctx(p_tg_id);
  if c.business_id is null then return jsonb_build_object('ok', false); end if;
  v_from := case p_period when 'month' then date_trunc('month', v_today)::date else v_today end;
  return jsonb_build_object(
    'ok', true, 'period', p_period, 'from', v_from, 'to', v_today,
    'business', jsonb_build_object('name', c.name, 'kind', c.kind, 'role', c.role),
    'summary', public._tg_summary(c.business_id, c.kind, c.role, v_from, v_today));
end $$;

create function public.tg_debt_overview(p_tg_id bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c record;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  select * into c from public._tg_ctx(p_tg_id);
  if c.business_id is null then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object(
    'ok', true,
    'business', jsonb_build_object('name', c.name, 'kind', c.kind, 'role', c.role),
    'receivable_open', (select coalesce(sum(remaining), 0) from public.debt_balances
                         where business_id = c.business_id and kind = 'receivable'),
    'payable_open', (select coalesce(sum(remaining), 0) from public.debt_balances
                      where business_id = c.business_id and kind = 'payable'),
    -- Positif = kontak berutang kepada pengguna; negatif = pengguna berutang.
    'contacts', (select coalesce(jsonb_agg(x order by abs(x.net) desc), '[]') from (
                   select ct.name,
                          sum(case d.kind when 'receivable' then d.remaining else -d.remaining end) as net
                     from public.debt_balances d
                     join public.contacts ct on ct.id = d.contact_id
                    where d.business_id = c.business_id and d.remaining > 0
                    group by ct.id, ct.name
                   having sum(case d.kind when 'receivable' then d.remaining else -d.remaining end) <> 0
                    order by abs(sum(case d.kind when 'receivable' then d.remaining
                                                  else -d.remaining end)) desc
                    limit 10) x),
    'due', public._tg_due(c.business_id, v_today + 7),
    'today', v_today);
end $$;

-- Nama kontak yang sudah ada (ejaan tersimpan), atau null bila belum ada.
create function public.tg_find_contact(p_tg_id bigint, p_name text) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare c record; v text;
begin
  select * into c from public._tg_ctx(p_tg_id);
  if c.business_id is null then return null; end if;
  select ct.name into v from public.contacts ct
   where ct.business_id = c.business_id and ct.deleted_at is null
     and lower(btrim(ct.name)) = lower(btrim(p_name))
   order by ct.created_at limit 1;
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Mencatat: sekarang juga utang piutang
-- ---------------------------------------------------------------------------
-- p_payload: {kind, amount, cost, note, contact}
--   sale       penjualan; dengan contact = penjualan utang (piutang, bukan kas)
--   income     pemasukan lain
--   expense    pengeluaran
--   receivable meminjamkan uang ke contact (kas keluar)
--   payable    menerima pinjaman uang dari contact (kas masuk)
create or replace function public.tg_record(p_tg_id bigint, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c record;
  v_kind text := p_payload ->> 'kind';
  v_amount bigint := (p_payload ->> 'amount')::bigint;
  v_cost bigint := coalesce((p_payload ->> 'cost')::bigint, 0);
  v_note text := nullif(btrim(coalesce(p_payload ->> 'note', '')), '');
  v_contact text := nullif(btrim(coalesce(p_payload ->> 'contact', '')), '');
  v_contact_id uuid;
  v_new_contact boolean := false;
  v_cat uuid;
  v_cat_name text;
  v_type public.txn_type;
  v_id uuid;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if not exists (select 1 from public.telegram_links where telegram_id = p_tg_id) then
    return jsonb_build_object('ok', false, 'error', 'unlinked');
  end if;
  select * into c from public._tg_ctx(p_tg_id);
  if c.business_id is null then return jsonb_build_object('ok', false, 'error', 'business'); end if;

  if v_kind not in ('sale', 'income', 'expense', 'receivable', 'payable')
     or v_amount is null or v_amount <= 0 or v_amount > 1000000000000 then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if v_kind = 'sale' then
    if c.kind <> 'business' then return jsonb_build_object('ok', false, 'error', 'personal'); end if;
    if v_cost <= 0 then return jsonb_build_object('ok', false, 'error', 'cost'); end if;
  end if;
  if v_kind in ('receivable', 'payable') and v_contact is null then
    return jsonb_build_object('ok', false, 'error', 'contact');
  end if;

  -- ----- Utang piutang (termasuk penjualan utang) -----
  if v_contact is not null and v_kind in ('sale', 'receivable', 'payable') then
    if char_length(v_contact) > 100 then
      return jsonb_build_object('ok', false, 'error', 'contact');
    end if;
    select ct.id into v_contact_id from public.contacts ct
     where ct.business_id = c.business_id and ct.deleted_at is null
       and lower(btrim(ct.name)) = lower(v_contact)
     order by ct.created_at limit 1;
    if v_contact_id is not null then
      -- Pakai ejaan nama yang sudah tersimpan.
      select ct.name into v_contact from public.contacts ct where ct.id = v_contact_id;
    else
      insert into public.contacts (business_id, name, created_by)
      values (c.business_id, v_contact, c.user_id) returning id into v_contact_id;
      v_new_contact := true;
    end if;

    v_id := public.create_debt(
      c.business_id, v_contact_id,
      (case v_kind when 'payable' then 'payable' else 'receivable' end)::public.debt_kind,
      v_amount,
      v_kind <> 'sale',          -- pinjaman uang menggerakkan kas; penjualan utang tidak
      v_date, null, v_note,
      v_kind = 'sale', case when v_kind = 'sale' then v_cost else 0 end);

    update public.telegram_links
       set last_debt_id = v_id, last_tx_id = null, last_tx_at = now()
     where telegram_id = p_tg_id;
    return jsonb_build_object('ok', true, 'id', v_id, 'business', c.name,
                              'contact', v_contact, 'new_contact', v_new_contact);
  end if;

  -- ----- Kas: penjualan lunas, pemasukan lain, pengeluaran -----
  if v_kind = 'sale' then
    v_type := 'in';
    select id, name into v_cat, v_cat_name from public.categories
     where business_id = c.business_id and type = 'in' and is_sale order by created_at limit 1;
  elsif v_kind = 'income' then
    v_type := 'in';
    v_cost := 0;
    if c.kind = 'business' then
      select id, name into v_cat, v_cat_name from public.categories
       where business_id = c.business_id and type = 'in' and name = 'Penjualan lainnya';
    end if;
  else
    v_type := 'out';
    v_cost := 0;
  end if;

  if v_cat is null and v_note is not null then
    select id, name into v_cat, v_cat_name from public.categories
     where business_id = c.business_id and type = v_type and not is_system and not is_sale
       and lower(v_note) like lower(name) || '%'
     order by char_length(name) desc limit 1;
  end if;

  insert into public.cash_transactions (business_id, type, amount, category_id, note, txn_date,
                                        created_by, is_sale, cost_amount)
  values (c.business_id, v_type, v_amount, v_cat, v_note, v_date, c.user_id, v_kind = 'sale', v_cost)
  returning id into v_id;

  update public.telegram_links
     set last_tx_id = v_id, last_debt_id = null, last_tx_at = now()
   where telegram_id = p_tg_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'category', v_cat_name, 'business', c.name);
end $$;

-- /batal: catatan terakhir dari bot (kas atau utang piutang), paling lama 30 menit lalu.
create or replace function public.tg_undo(p_tg_id bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare l public.telegram_links; v_amount bigint;
begin
  select * into l from public.telegram_links where telegram_id = p_tg_id;
  if l.telegram_id is null or l.last_tx_at is null
     or l.last_tx_at < now() - interval '30 minutes'
     or (l.last_tx_id is null and l.last_debt_id is null) then
    return jsonb_build_object('ok', false);
  end if;
  perform set_config('request.jwt.claims',
                     jsonb_build_object('sub', l.user_id, 'role', 'authenticated')::text, true);

  if l.last_debt_id is not null then
    select amount into v_amount from public.debts
     where id = l.last_debt_id and created_by = l.user_id and deleted_at is null;
    if v_amount is not null then
      begin
        perform public.delete_debt(l.last_debt_id);
      exception when others then
        v_amount := null;
      end;
    end if;
  else
    update public.cash_transactions t set deleted_at = now()
     where t.id = l.last_tx_id and t.created_by = l.user_id and t.deleted_at is null
       and exists (select 1 from public.business_members m
                    where m.business_id = t.business_id and m.user_id = l.user_id)
    returning t.amount into v_amount;
  end if;

  update public.telegram_links
     set last_tx_id = null, last_debt_id = null, last_tx_at = null
   where telegram_id = p_tg_id;
  if v_amount is null then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'amount', v_amount);
end $$;

-- ---------------------------------------------------------------------------
-- 4. Ringkasan harian terjadwal
-- ---------------------------------------------------------------------------
-- Menghidupkan/mematikan ringkasan harian; mengembalikan keadaan baru.
create function public.tg_toggle_daily(p_tg_id bigint) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare v boolean;
begin
  update public.telegram_links set daily_report = not daily_report
   where telegram_id = p_tg_id returning daily_report into v;
  return v;
end $$;

-- Satu baris per akun yang perlu dikirimi: hanya bila hari ini ada catatan atau ada
-- yang jatuh tempo sampai 3 hari ke depan.
create function public.tg_daily_batch() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  l record; c record; s jsonb; d jsonb;
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
    out_rows := out_rows || jsonb_build_object(
      'chat_id', l.chat_id, 'to', v_today,
      'business', jsonb_build_object('name', c.name, 'kind', c.kind, 'role', c.role),
      'summary', s, 'due', d);
  end loop;
  return out_rows;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Hak menjalankan
-- ---------------------------------------------------------------------------
revoke all on function
  public._tg_ctx(bigint), public._tg_summary(uuid, text, public.member_role, date, date),
  public._tg_due(uuid, date),
  public.tg_report(bigint, text), public.tg_debt_overview(bigint),
  public.tg_find_contact(bigint, text), public.tg_toggle_daily(bigint), public.tg_daily_batch()
  from public, anon, authenticated;

grant execute on function
  public.tg_report(bigint, text), public.tg_debt_overview(bigint),
  public.tg_find_contact(bigint, text), public.tg_toggle_daily(bigint), public.tg_daily_batch()
  to service_role;
