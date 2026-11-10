-- RekapRapi: Bot Telegram.
-- Satu bot dipakai bersama; tiap akun Telegram terikat ke SATU akun RekapRapi dan hanya
-- bekerja pada pembukuan yang akun itu menjadi anggotanya.
--
-- Aplikasi (pengguna login) hanya memakai: telegram_status, telegram_create_code,
-- telegram_unlink. Semua fungsi tg_* hanya untuk server bot (service_role).
-- Jalankan sekali di SQL Editor Supabase, setelah migrasi 20261113000000.

-- ---------------------------------------------------------------------------
-- 1. Tabel (tanpa policy: tidak bisa dibaca/ditulis langsung dari aplikasi)
-- ---------------------------------------------------------------------------
create table public.telegram_config (
  id            boolean primary key default true check (id),
  bot_username  text,
  updated_at    timestamptz not null default now()
);
insert into public.telegram_config (id) values (true);

create table public.telegram_links (
  telegram_id         bigint primary key,
  user_id             uuid not null unique references auth.users (id) on delete cascade,
  chat_id             bigint not null,
  tg_name             text,
  active_business_id  uuid references public.businesses (id) on delete set null,
  pending             jsonb,          -- catatan yang menunggu konfirmasi
  pending_at          timestamptz,
  last_tx_id          uuid,           -- catatan terakhir dari bot, untuk /batal
  last_tx_at          timestamptz,
  linked_at           timestamptz not null default now()
);

create table public.telegram_link_codes (
  code         text primary key,
  user_id      uuid not null references auth.users (id) on delete cascade,
  business_id  uuid not null references public.businesses (id) on delete cascade,
  expires_at   timestamptz not null
);
create index telegram_link_codes_user_idx on public.telegram_link_codes (user_id);

alter table public.telegram_config     enable row level security;
alter table public.telegram_links      enable row level security;
alter table public.telegram_link_codes enable row level security;
revoke all on public.telegram_config, public.telegram_links, public.telegram_link_codes
  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Fungsi untuk aplikasi (pengguna login)
-- ---------------------------------------------------------------------------
create function public.telegram_status() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'bot', (select bot_username from public.telegram_config),
    'linked', l.telegram_id is not null,
    'name', l.tg_name,
    'linked_at', l.linked_at)
  from (select 1) x
  left join public.telegram_links l on l.user_id = auth.uid()
$$;

-- Kode sekali pakai (10 menit) untuk dikirim ke bot lewat tombol Start.
create function public.telegram_create_code(p_business uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  v_code text;
  v_bot text;
begin
  if uid is null then raise exception 'Belum masuk' using errcode = '28000'; end if;
  if not public.is_member(p_business) then
    raise exception 'Tidak punya akses' using errcode = '42501';
  end if;
  select bot_username into v_bot from public.telegram_config;
  if v_bot is null then
    raise exception 'Bot Telegram belum diaktifkan' using errcode = 'P0001';
  end if;

  delete from public.telegram_link_codes where user_id = uid or expires_at < now();
  v_code := replace(gen_random_uuid()::text, '-', '');
  insert into public.telegram_link_codes (code, user_id, business_id, expires_at)
  values (v_code, uid, p_business, now() + interval '10 minutes');
  return jsonb_build_object('code', v_code, 'bot', v_bot);
end $$;

create function public.telegram_unlink() returns void
language sql security definer set search_path = public, pg_temp as $$
  delete from public.telegram_links where user_id = auth.uid();
  delete from public.telegram_link_codes where user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- 3. Fungsi untuk server bot (service_role saja)
-- ---------------------------------------------------------------------------
create function public.tg_set_bot(p_username text) returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.telegram_config set bot_username = btrim(p_username), updated_at = now();
$$;

-- Menukar kode dengan sambungan. Sambungan lama akun Telegram atau akun RekapRapi
-- yang sama diganti.
create function public.tg_link(p_code text, p_tg_id bigint, p_chat_id bigint, p_name text)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare c record; v_name text;
begin
  delete from public.telegram_link_codes
   where code = p_code and expires_at >= now()
  returning user_id, business_id into c;
  if c.user_id is null then
    return jsonb_build_object('ok', false, 'error', 'code');
  end if;
  if not exists (select 1 from public.business_members m
                   join public.businesses b on b.id = m.business_id and b.deleted_at is null
                  where m.user_id = c.user_id and m.business_id = c.business_id) then
    return jsonb_build_object('ok', false, 'error', 'member');
  end if;

  delete from public.telegram_links where telegram_id = p_tg_id or user_id = c.user_id;
  insert into public.telegram_links (telegram_id, user_id, chat_id, tg_name, active_business_id)
  values (p_tg_id, c.user_id, p_chat_id, nullif(btrim(coalesce(p_name, '')), ''), c.business_id);
  select name into v_name from public.businesses where id = c.business_id;
  return jsonb_build_object('ok', true, 'business', v_name);
end $$;

-- Siapa pengirim dan pembukuan mana yang aktif. Pembukuan aktif yang sudah tidak
-- bisa diakses diganti dengan pembukuan lain milik pengguna.
create function public.tg_context(p_tg_id bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  l public.telegram_links;
  v_active uuid;
  v_list jsonb;
begin
  select * into l from public.telegram_links where telegram_id = p_tg_id;
  if l.telegram_id is null then return jsonb_build_object('linked', false); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'name', b.name, 'kind', b.kind, 'role', m.role) order by b.name), '[]')
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

create function public.tg_set_business(p_tg_id bigint, p_business uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.telegram_links l
     set active_business_id = p_business, pending = null, pending_at = null
   where l.telegram_id = p_tg_id
     and exists (select 1 from public.business_members m
                   join public.businesses b on b.id = m.business_id and b.deleted_at is null
                  where m.user_id = l.user_id and m.business_id = p_business);
  return found;
end $$;

create function public.tg_set_pending(p_tg_id bigint, p_payload jsonb) returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.telegram_links set pending = p_payload, pending_at = now()
   where telegram_id = p_tg_id;
$$;

-- Mengambil catatan yang menunggu (sekali saja). Null bila tidak ada, sudah lewat
-- 15 menit, atau nomornya tidak cocok dengan tombol yang ditekan.
create function public.tg_take_pending(p_tg_id bigint, p_nonce text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  select pending into v from public.telegram_links
   where telegram_id = p_tg_id
     and pending ->> 'n' = p_nonce
     and pending_at > now() - interval '15 minutes'
   for update;
  if v is null then return null; end if;
  update public.telegram_links set pending = null, pending_at = null where telegram_id = p_tg_id;
  return v;
end $$;

-- Menyimpan satu catatan ke pembukuan aktif atas nama pengguna yang terhubung.
-- p_payload: {kind: 'sale'|'income'|'expense', amount, cost, note}
create function public.tg_record(p_tg_id bigint, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  l public.telegram_links;
  b public.businesses;
  v_kind text := p_payload ->> 'kind';
  v_amount bigint := (p_payload ->> 'amount')::bigint;
  v_cost bigint := coalesce((p_payload ->> 'cost')::bigint, 0);
  v_note text := nullif(btrim(coalesce(p_payload ->> 'note', '')), '');
  v_cat uuid;
  v_cat_name text;
  v_type public.txn_type;
  v_id uuid;
  -- Tanggal mengikuti waktu Indonesia bagian barat, bukan UTC.
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
begin
  select * into l from public.telegram_links where telegram_id = p_tg_id;
  if l.telegram_id is null then return jsonb_build_object('ok', false, 'error', 'unlinked'); end if;

  select bz.* into b
    from public.businesses bz
    join public.business_members m on m.business_id = bz.id and m.user_id = l.user_id
   where bz.id = l.active_business_id and bz.deleted_at is null and not bz.restoring;
  if b.id is null then return jsonb_build_object('ok', false, 'error', 'business'); end if;

  if v_kind not in ('sale', 'income', 'expense') or v_amount is null or v_amount <= 0
     or v_amount > 1000000000000 then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;

  if v_kind = 'sale' then
    if b.kind <> 'business' then return jsonb_build_object('ok', false, 'error', 'personal'); end if;
    if v_cost <= 0 then return jsonb_build_object('ok', false, 'error', 'cost'); end if;
    v_type := 'in';
    select id, name into v_cat, v_cat_name from public.categories
     where business_id = b.id and type = 'in' and is_sale order by created_at limit 1;
  elsif v_kind = 'income' then
    v_type := 'in';
    v_cost := 0;
    if b.kind = 'business' then
      select id, name into v_cat, v_cat_name from public.categories
       where business_id = b.id and type = 'in' and name = 'Penjualan lainnya';
    end if;
  else
    v_type := 'out';
    v_cost := 0;
  end if;

  -- Kategori yang namanya sama dengan awal catatan dipakai (yang terpanjang menang).
  if v_cat is null and v_note is not null then
    select id, name into v_cat, v_cat_name from public.categories
     where business_id = b.id and type = v_type and not is_system and not is_sale
       and lower(v_note) like lower(name) || '%'
     order by char_length(name) desc limit 1;
  end if;

  -- Riwayat aktivitas dan pencatat memakai pengguna yang terhubung.
  perform set_config('request.jwt.claims',
                     jsonb_build_object('sub', l.user_id, 'role', 'authenticated')::text, true);

  insert into public.cash_transactions (business_id, type, amount, category_id, note, txn_date,
                                        created_by, is_sale, cost_amount)
  values (b.id, v_type, v_amount, v_cat, v_note, v_date, l.user_id, v_kind = 'sale', v_cost)
  returning id into v_id;

  update public.telegram_links set last_tx_id = v_id, last_tx_at = now()
   where telegram_id = p_tg_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'category', v_cat_name,
                            'business', b.name);
end $$;

-- /batal: menghapus catatan terakhir yang dibuat lewat bot, paling lama 30 menit lalu.
create function public.tg_undo(p_tg_id bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare l public.telegram_links; t record;
begin
  select * into l from public.telegram_links where telegram_id = p_tg_id;
  if l.last_tx_id is null or l.last_tx_at < now() - interval '30 minutes' then
    return jsonb_build_object('ok', false);
  end if;
  perform set_config('request.jwt.claims',
                     jsonb_build_object('sub', l.user_id, 'role', 'authenticated')::text, true);
  update public.cash_transactions c set deleted_at = now()
   where c.id = l.last_tx_id and c.created_by = l.user_id and c.deleted_at is null
     and exists (select 1 from public.business_members m
                  where m.business_id = c.business_id and m.user_id = l.user_id)
  returning c.type, c.amount into t;
  update public.telegram_links set last_tx_id = null, last_tx_at = null where telegram_id = p_tg_id;
  if t.amount is null then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'type', t.type, 'amount', t.amount);
end $$;

create function public.tg_unlink(p_tg_id bigint) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.telegram_links where telegram_id = p_tg_id;
  return found;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Hak menjalankan
-- ---------------------------------------------------------------------------
revoke all on function
  public.telegram_status(), public.telegram_create_code(uuid), public.telegram_unlink(),
  public.tg_set_bot(text), public.tg_link(text, bigint, bigint, text),
  public.tg_context(bigint), public.tg_set_business(bigint, uuid),
  public.tg_set_pending(bigint, jsonb), public.tg_take_pending(bigint, text),
  public.tg_record(bigint, jsonb), public.tg_undo(bigint), public.tg_unlink(bigint)
  from public, anon, authenticated;

grant execute on function
  public.telegram_status(), public.telegram_create_code(uuid), public.telegram_unlink()
  to authenticated;

grant execute on function
  public.tg_set_bot(text), public.tg_link(text, bigint, bigint, text),
  public.tg_context(bigint), public.tg_set_business(bigint, uuid),
  public.tg_set_pending(bigint, jsonb), public.tg_take_pending(bigint, text),
  public.tg_record(bigint, jsonb), public.tg_undo(bigint), public.tg_unlink(bigint)
  to service_role;
