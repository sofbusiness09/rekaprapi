-- RekapRapi: skema awal (Tahap 0)
-- Isi: tabel, RLS, fungsi (RPC), trigger, grant.
-- Cara pakai: tempel seluruh berkas ini di Supabase Dashboard > SQL Editor, lalu Run.
--
-- Prinsip:
--   * Semua data milik USAHA (business_id), bukan akun.
--   * Hak akses ditegakkan di database lewat RLS + fungsi, bukan di aplikasi.
--   * Perubahan yang memengaruhi lebih dari satu tabel (anggota, undangan, utang
--     piutang + kas) hanya lewat fungsi (RPC); klien tidak diberi izin tulis langsung.
--   * Uang = bilangan bulat rupiah (bigint).

-- ---------------------------------------------------------------------------
-- 1. Tipe
-- ---------------------------------------------------------------------------
create type public.member_role as enum ('owner', 'admin', 'staff');
create type public.txn_type as enum ('in', 'out');
create type public.debt_kind as enum ('receivable', 'payable');  -- piutang | utang
create type public.invitation_status as enum ('pending', 'accepted', 'declined', 'cancelled');

-- ---------------------------------------------------------------------------
-- 2. Tabel
-- ---------------------------------------------------------------------------
create table public.businesses (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 1 and 100),
  address     text,
  phone       text,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  email             text,
  display_name      text,
  last_business_id  uuid references public.businesses (id) on delete set null,
  created_at        timestamptz not null default now()
);

create table public.business_members (
  business_id  uuid not null references public.businesses (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,
  role         public.member_role not null,
  joined_at    timestamptz not null default now(),
  primary key (business_id, user_id)
);
create index business_members_user_idx on public.business_members (user_id);

create table public.invitations (
  id             uuid primary key default gen_random_uuid(),
  business_id    uuid not null references public.businesses (id) on delete cascade,
  business_name  text not null,
  email          text not null,
  role           public.member_role not null check (role in ('admin', 'staff')),
  code           text not null unique,
  invited_by     uuid references auth.users (id) on delete set null,
  status         public.invitation_status not null default 'pending',
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null default now() + interval '7 days'
);
create unique index invitations_one_pending_idx
  on public.invitations (business_id, email) where status = 'pending';
create index invitations_email_idx on public.invitations (email);

create table public.categories (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses (id) on delete cascade,
  name         text not null check (char_length(btrim(name)) between 1 and 60),
  type         public.txn_type not null,
  is_system    boolean not null default false,   -- dipakai sinkron utang piutang
  created_at   timestamptz not null default now(),
  unique (business_id, type, name),
  unique (id, business_id)
);

create table public.contacts (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses (id) on delete cascade,
  name         text not null check (char_length(btrim(name)) between 1 and 100),
  phone        text,
  note         text,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (id, business_id)
);

create table public.debts (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses (id) on delete cascade,
  contact_id   uuid not null,
  kind         public.debt_kind not null,
  amount       bigint not null check (amount > 0),
  cash_moved   boolean not null,
  debt_date    date not null default current_date,
  due_date     date,
  note         text,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (id, business_id),
  foreign key (contact_id, business_id) references public.contacts (id, business_id)
);
create index debts_business_idx on public.debts (business_id, kind);

create table public.debt_payments (
  id           uuid primary key default gen_random_uuid(),
  debt_id      uuid not null,
  business_id  uuid not null references public.businesses (id) on delete cascade,
  amount       bigint not null check (amount > 0),
  paid_on      date not null default current_date,
  note         text,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  unique (id, business_id),
  foreign key (debt_id, business_id) references public.debts (id, business_id)
);
create index debt_payments_debt_idx on public.debt_payments (debt_id);

create table public.cash_transactions (
  id               uuid primary key default gen_random_uuid(),
  business_id      uuid not null references public.businesses (id) on delete cascade,
  type             public.txn_type not null,
  amount           bigint not null check (amount > 0),
  category_id      uuid,
  note             text,
  txn_date         date not null default current_date,
  debt_id          uuid,   -- terisi = kas awal dari utang piutang (otomatis)
  debt_payment_id  uuid,   -- terisi = kas dari cicilan/pelunasan (otomatis)
  created_by       uuid references auth.users (id) on delete set null,
  updated_by       uuid references auth.users (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  foreign key (category_id, business_id) references public.categories (id, business_id),
  foreign key (debt_id, business_id) references public.debts (id, business_id),
  foreign key (debt_payment_id, business_id) references public.debt_payments (id, business_id)
);
create index cash_tx_business_date_idx on public.cash_transactions (business_id, txn_date desc);
create index cash_tx_debt_idx on public.cash_transactions (debt_id) where debt_id is not null;
create index cash_tx_payment_idx on public.cash_transactions (debt_payment_id) where debt_payment_id is not null;

create table public.activity_log (
  id           bigint generated always as identity primary key,
  business_id  uuid not null references public.businesses (id) on delete cascade,
  user_id      uuid,
  action       text not null,
  entity       text not null,
  entity_id    uuid,
  detail       jsonb,
  at           timestamptz not null default now()
);
create index activity_log_business_idx on public.activity_log (business_id, at desc);

-- Sisa utang dihitung, tidak disimpan, supaya tidak bisa selisih.
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

-- ---------------------------------------------------------------------------
-- 3. Fungsi bantu (dipakai RLS dan RPC)
-- ---------------------------------------------------------------------------
create function public.my_email() returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select lower(email) from auth.users where id = auth.uid()
$$;

-- Peran pengguna saat ini di sebuah usaha; null bila bukan anggota / usaha dihapus.
create function public.role_in(p_business uuid) returns public.member_role
language sql stable security definer set search_path = public, pg_temp as $$
  select m.role
  from public.business_members m
  join public.businesses b on b.id = m.business_id
  where m.business_id = p_business
    and m.user_id = auth.uid()
    and b.deleted_at is null
$$;

create function public.is_member(p_business uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select public.role_in(p_business) is not null
$$;

create function public.is_admin_or_owner(p_business uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(public.role_in(p_business) in ('owner', 'admin'), false)
$$;

create function public.shares_business_with(p_user uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
    from public.business_members a
    join public.business_members b on b.business_id = a.business_id
    join public.businesses bz on bz.id = a.business_id and bz.deleted_at is null
    where a.user_id = auth.uid() and b.user_id = p_user
  )
$$;

-- Memastikan peran pemanggil; melempar 42501 bila tidak berhak.
create function public._require(p_business uuid, p_roles public.member_role[])
returns public.member_role
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare r public.member_role;
begin
  r := public.role_in(p_business);
  if r is null or not (r = any (p_roles)) then
    raise exception 'Tidak punya akses' using errcode = '42501';
  end if;
  return r;
end $$;

-- Pemilik/Admin boleh ubah apa saja; Staf hanya miliknya sendiri.
create function public._can_modify(p_business uuid, p_created_by uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select case public.role_in(p_business)
           when 'owner' then true
           when 'admin' then true
           when 'staff' then p_created_by = auth.uid()
           else false
         end
$$;

-- ---------------------------------------------------------------------------
-- 4. Trigger
-- ---------------------------------------------------------------------------
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, lower(new.email),
          coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(new.email, '@', 1)));
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.touch_cash_transaction() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;

create trigger cash_transactions_touch
  before update on public.cash_transactions
  for each row execute function public.touch_cash_transaction();

-- Riwayat aktivitas. Kas otomatis dari utang piutang tidak dicatat dua kali.
create function public.log_activity() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  j jsonb;
  act text;
begin
  if tg_op = 'DELETE' then
    j := to_jsonb(old);
    act := 'remove';
  else
    j := to_jsonb(new);
    if tg_op = 'INSERT' then
      act := 'create';
    elsif j ->> 'deleted_at' is not null and to_jsonb(old) ->> 'deleted_at' is null then
      act := 'delete';
    else
      act := 'update';
    end if;
  end if;

  if tg_table_name = 'cash_transactions'
     and (j ->> 'debt_id' is not null or j ->> 'debt_payment_id' is not null) then
    return coalesce(new, old);
  end if;

  insert into public.activity_log (business_id, user_id, action, entity, entity_id, detail)
  values ((j ->> 'business_id')::uuid, auth.uid(), act, tg_table_name,
          nullif(j ->> 'id', '')::uuid,
          jsonb_strip_nulls(jsonb_build_object(
            'type', j -> 'type', 'kind', j -> 'kind', 'amount', j -> 'amount',
            'role', j -> 'role', 'user_id', j -> 'user_id')));
  return coalesce(new, old);
end $$;

create trigger log_cash_transactions after insert or update on public.cash_transactions
  for each row execute function public.log_activity();
create trigger log_debts after insert or update on public.debts
  for each row execute function public.log_activity();
create trigger log_debt_payments after insert or update on public.debt_payments
  for each row execute function public.log_activity();
create trigger log_business_members after insert or update or delete on public.business_members
  for each row execute function public.log_activity();

-- ---------------------------------------------------------------------------
-- 5. RLS
-- ---------------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.businesses        enable row level security;
alter table public.business_members  enable row level security;
alter table public.invitations       enable row level security;
alter table public.categories        enable row level security;
alter table public.contacts          enable row level security;
alter table public.debts             enable row level security;
alter table public.debt_payments     enable row level security;
alter table public.cash_transactions enable row level security;
alter table public.activity_log      enable row level security;

create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_business_with(id));
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid()
              and (last_business_id is null or public.is_member(last_business_id)));

create policy businesses_select on public.businesses for select to authenticated
  using (public.is_member(id));
create policy businesses_update on public.businesses for update to authenticated
  using (public.is_admin_or_owner(id)) with check (public.is_admin_or_owner(id));

create policy members_select on public.business_members for select to authenticated
  using (public.is_member(business_id));

create policy invitations_select on public.invitations for select to authenticated
  using (public.is_admin_or_owner(business_id) or email = public.my_email());

create policy categories_select on public.categories for select to authenticated
  using (public.is_member(business_id));
create policy categories_insert on public.categories for insert to authenticated
  with check (public.is_admin_or_owner(business_id) and not is_system);
create policy categories_update on public.categories for update to authenticated
  using (public.is_admin_or_owner(business_id) and not is_system)
  with check (public.is_admin_or_owner(business_id) and not is_system);
create policy categories_delete on public.categories for delete to authenticated
  using (public.is_admin_or_owner(business_id) and not is_system);

-- Staf boleh menambah kontak (perlu saat mencatat utang), tetapi tidak mengubahnya.
create policy contacts_select on public.contacts for select to authenticated
  using (public.is_member(business_id));
create policy contacts_insert on public.contacts for insert to authenticated
  with check (public.is_member(business_id) and created_by = auth.uid());
create policy contacts_update on public.contacts for update to authenticated
  using (public.is_admin_or_owner(business_id))
  with check (public.is_admin_or_owner(business_id));

create policy debts_select on public.debts for select to authenticated
  using (public.is_member(business_id));
create policy debt_payments_select on public.debt_payments for select to authenticated
  using (public.is_member(business_id));

-- Semua anggota melihat semua transaksi; Staf hanya mengubah miliknya.
-- Kas otomatis (terhubung ke utang piutang) tidak bisa diubah langsung.
create policy cash_select on public.cash_transactions for select to authenticated
  using (public.is_member(business_id));
create policy cash_insert on public.cash_transactions for insert to authenticated
  with check (public.is_member(business_id) and created_by = auth.uid()
              and debt_id is null and debt_payment_id is null);
create policy cash_update on public.cash_transactions for update to authenticated
  using (debt_id is null and debt_payment_id is null
         and public.is_member(business_id)
         and (public.is_admin_or_owner(business_id) or created_by = auth.uid()))
  with check (debt_id is null and debt_payment_id is null and public.is_member(business_id));

create policy activity_select on public.activity_log for select to authenticated
  using (public.is_admin_or_owner(business_id));

-- ---------------------------------------------------------------------------
-- 6. RPC: usaha dan anggota
-- ---------------------------------------------------------------------------
create function public.create_business(p_name text, p_address text default null, p_phone text default null)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  bid uuid;
  owned int;
begin
  if uid is null then raise exception 'Belum masuk' using errcode = '28000'; end if;
  if char_length(btrim(coalesce(p_name, ''))) = 0 then
    raise exception 'Nama usaha wajib diisi' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('create_business:' || uid::text));
  select count(*) into owned
  from public.business_members m
  join public.businesses b on b.id = m.business_id
  where m.user_id = uid and m.role = 'owner' and b.deleted_at is null;
  if owned >= 5 then
    raise exception 'Batas 5 usaha per akun tercapai' using errcode = 'P0001';
  end if;

  insert into public.businesses (name, address, phone, created_by)
  values (btrim(p_name), p_address, p_phone, uid) returning id into bid;
  insert into public.business_members (business_id, user_id, role) values (bid, uid, 'owner');

  insert into public.categories (business_id, name, type, is_system) values
    (bid, 'Pemberian Piutang',  'out', true),
    (bid, 'Pelunasan Piutang',  'in',  true),
    (bid, 'Penerimaan Utang',   'in',  true),
    (bid, 'Pembayaran Utang',   'out', true);
  insert into public.categories (business_id, name, type) values
    (bid, 'Penjualan',        'in'),
    (bid, 'Pemasukan Lain',   'in'),
    (bid, 'Pembelian Stok',   'out'),
    (bid, 'Gaji',             'out'),
    (bid, 'Sewa',             'out'),
    (bid, 'Listrik & Air',    'out'),
    (bid, 'Transportasi',     'out'),
    (bid, 'Pengeluaran Lain', 'out');

  update public.profiles set last_business_id = bid where id = uid;
  return bid;
end $$;

create function public.delete_business(p_business uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require(p_business, array['owner']::public.member_role[]);
  update public.businesses set deleted_at = now() where id = p_business;
end $$;

create function public.transfer_ownership(p_business uuid, p_new_owner uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require(p_business, array['owner']::public.member_role[]);
  if p_new_owner = auth.uid() then
    raise exception 'Pilih anggota lain' using errcode = '22023';
  end if;
  perform 1 from public.business_members
   where business_id = p_business and user_id = p_new_owner for update;
  if not found then raise exception 'Anggota tidak ditemukan' using errcode = 'P0002'; end if;
  update public.business_members set role = 'admin'
   where business_id = p_business and user_id = auth.uid();
  update public.business_members set role = 'owner'
   where business_id = p_business and user_id = p_new_owner;
end $$;

create function public.change_member_role(p_business uuid, p_user uuid, p_role public.member_role)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare actor public.member_role; target public.member_role;
begin
  actor := public._require(p_business, array['owner', 'admin']::public.member_role[]);
  if p_role not in ('admin', 'staff') then
    raise exception 'Peran tidak valid' using errcode = '22023';
  end if;
  if p_user = auth.uid() then
    raise exception 'Tidak dapat mengubah peran sendiri' using errcode = '42501';
  end if;
  select role into target from public.business_members
   where business_id = p_business and user_id = p_user for update;
  if target is null then raise exception 'Anggota tidak ditemukan' using errcode = 'P0002'; end if;
  if target = 'owner' or (actor = 'admin' and target = 'admin') then
    raise exception 'Tidak punya akses' using errcode = '42501';
  end if;
  update public.business_members set role = p_role
   where business_id = p_business and user_id = p_user;
end $$;

create function public.remove_member(p_business uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare actor public.member_role; target public.member_role;
begin
  actor := public._require(p_business, array['owner', 'admin']::public.member_role[]);
  if p_user = auth.uid() then
    raise exception 'Gunakan "Keluar dari usaha"' using errcode = '42501';
  end if;
  select role into target from public.business_members
   where business_id = p_business and user_id = p_user for update;
  if target is null then raise exception 'Anggota tidak ditemukan' using errcode = 'P0002'; end if;
  if target = 'owner' or (actor = 'admin' and target = 'admin') then
    raise exception 'Tidak punya akses' using errcode = '42501';
  end if;
  delete from public.business_members where business_id = p_business and user_id = p_user;
  update public.profiles set last_business_id = null
   where id = p_user and last_business_id = p_business;
end $$;

create function public.leave_business(p_business uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.member_role;
begin
  r := public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  if r = 'owner' then
    raise exception 'Pemilik harus mengalihkan kepemilikan atau menghapus usaha' using errcode = '42501';
  end if;
  delete from public.business_members where business_id = p_business and user_id = auth.uid();
  update public.profiles set last_business_id = null
   where id = auth.uid() and last_business_id = p_business;
end $$;

-- ---------------------------------------------------------------------------
-- 7. RPC: undangan
-- ---------------------------------------------------------------------------
create function public.create_invitation(p_business uuid, p_email text, p_role public.member_role)
returns public.invitations
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  em text := lower(btrim(coalesce(p_email, '')));
  bname text;
  rec public.invitations;
begin
  perform public._require(p_business, array['owner', 'admin']::public.member_role[]);
  if p_role not in ('admin', 'staff') then
    raise exception 'Peran tidak valid' using errcode = '22023';
  end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Email tidak valid' using errcode = '22023';
  end if;
  if exists (select 1 from public.business_members m
             join auth.users u on u.id = m.user_id
             where m.business_id = p_business and lower(u.email) = em) then
    raise exception 'Sudah menjadi anggota' using errcode = '23505';
  end if;

  select name into bname from public.businesses where id = p_business;
  update public.invitations set status = 'cancelled'
   where business_id = p_business and email = em and status = 'pending';

  insert into public.invitations (business_id, business_name, email, role, code, invited_by)
  values (p_business, bname, em, p_role,
          upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)), auth.uid())
  returning * into rec;
  return rec;
end $$;

create function public.cancel_invitation(p_invitation uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare inv public.invitations;
begin
  select * into inv from public.invitations where id = p_invitation;
  if not found then raise exception 'Undangan tidak ditemukan' using errcode = 'P0002'; end if;
  perform public._require(inv.business_id, array['owner', 'admin']::public.member_role[]);
  update public.invitations set status = 'cancelled' where id = p_invitation and status = 'pending';
end $$;

create function public.decline_invitation(p_invitation uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.invitations set status = 'declined'
   where id = p_invitation and status = 'pending' and email = public.my_email();
  if not found then raise exception 'Undangan tidak ditemukan' using errcode = 'P0002'; end if;
end $$;

create function public._accept(inv public.invitations) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if inv.status <> 'pending' or inv.expires_at < now() then
    raise exception 'Undangan tidak berlaku' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.businesses where id = inv.business_id and deleted_at is null) then
    raise exception 'Usaha sudah dihapus' using errcode = 'P0001';
  end if;
  insert into public.business_members (business_id, user_id, role)
  values (inv.business_id, auth.uid(), inv.role)
  on conflict (business_id, user_id) do nothing;
  update public.invitations set status = 'accepted' where id = inv.id;
  update public.profiles set last_business_id = inv.business_id where id = auth.uid();
  return inv.business_id;
end $$;

-- Terima lewat daftar undangan: email harus sama dan sudah terverifikasi.
create function public.accept_invitation(p_invitation uuid) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare inv public.invitations;
begin
  select * into inv from public.invitations where id = p_invitation for update;
  if not found or inv.email is distinct from public.my_email() then
    raise exception 'Undangan tidak ditemukan' using errcode = 'P0002';
  end if;
  if not exists (select 1 from auth.users where id = auth.uid() and email_confirmed_at is not null) then
    raise exception 'Verifikasi email Anda terlebih dahulu' using errcode = '42501';
  end if;
  return public._accept(inv);
end $$;

-- Terima lewat kode/tautan (dibagikan via WhatsApp): siapa pun pemegang kode, sekali pakai.
create function public.accept_invitation_by_code(p_code text) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare inv public.invitations;
begin
  select * into inv from public.invitations
   where code = upper(btrim(coalesce(p_code, ''))) for update;
  if not found then raise exception 'Kode tidak ditemukan' using errcode = 'P0002'; end if;
  return public._accept(inv);
end $$;

-- ---------------------------------------------------------------------------
-- 8. RPC: utang piutang yang tersinkron dengan kas
--    receivable (piutang): uang keluar saat dipinjamkan, masuk saat dibayar.
--    payable (utang)     : uang masuk saat meminjam, keluar saat dibayar.
-- ---------------------------------------------------------------------------
create function public.create_debt(
  p_business   uuid,
  p_contact    uuid,
  p_kind       public.debt_kind,
  p_amount     bigint,
  p_cash_moved boolean,
  p_debt_date  date default current_date,
  p_due_date   date default null,
  p_note       text default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare did uuid; cat uuid;
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  if p_amount is null or p_amount <= 0 then
    raise exception 'Jumlah harus lebih dari 0' using errcode = '22023';
  end if;

  insert into public.debts (business_id, contact_id, kind, amount, cash_moved,
                            debt_date, due_date, note, created_by)
  values (p_business, p_contact, p_kind, p_amount, p_cash_moved,
          coalesce(p_debt_date, current_date), p_due_date, p_note, auth.uid())
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
  return did;
end $$;

create function public.update_debt(
  p_debt      uuid,
  p_contact   uuid,
  p_amount    bigint,
  p_debt_date date,
  p_due_date  date,
  p_note      text
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare d public.debts; paid bigint;
begin
  select * into d from public.debts where id = p_debt and deleted_at is null for update;
  if not found then raise exception 'Data tidak ditemukan' using errcode = 'P0002'; end if;
  if not public._can_modify(d.business_id, d.created_by) then
    raise exception 'Tidak punya akses' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Jumlah harus lebih dari 0' using errcode = '22023';
  end if;
  select coalesce(sum(amount), 0) into paid
    from public.debt_payments where debt_id = p_debt and deleted_at is null;
  if p_amount < paid then
    raise exception 'Jumlah lebih kecil dari yang sudah dibayar' using errcode = '22023';
  end if;

  update public.debts
     set contact_id = p_contact, amount = p_amount, debt_date = coalesce(p_debt_date, debt_date),
         due_date = p_due_date, note = p_note
   where id = p_debt;
  update public.cash_transactions
     set amount = p_amount, txn_date = coalesce(p_debt_date, txn_date), note = p_note
   where debt_id = p_debt and deleted_at is null;
end $$;

create function public.delete_debt(p_debt uuid) returns void
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
  update public.debt_payments set deleted_at = now() where debt_id = p_debt and deleted_at is null;
  update public.debts set deleted_at = now() where id = p_debt;
end $$;

create function public.add_debt_payment(
  p_debt   uuid,
  p_amount bigint,
  p_paid_on date default current_date,
  p_note   text default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare d public.debts; paid bigint; pid uuid; cat uuid;
begin
  select * into d from public.debts where id = p_debt and deleted_at is null for update;
  if not found then raise exception 'Data tidak ditemukan' using errcode = 'P0002'; end if;
  perform public._require(d.business_id, array['owner', 'admin', 'staff']::public.member_role[]);
  if p_amount is null or p_amount <= 0 then
    raise exception 'Jumlah harus lebih dari 0' using errcode = '22023';
  end if;
  select coalesce(sum(amount), 0) into paid
    from public.debt_payments where debt_id = p_debt and deleted_at is null;
  if p_amount > d.amount - paid then
    raise exception 'Pembayaran melebihi sisa' using errcode = '22023';
  end if;

  insert into public.debt_payments (debt_id, business_id, amount, paid_on, note, created_by)
  values (p_debt, d.business_id, p_amount, coalesce(p_paid_on, current_date), p_note, auth.uid())
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

create function public.update_debt_payment(
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

create function public.delete_debt_payment(p_payment uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare pay public.debt_payments;
begin
  select * into pay from public.debt_payments where id = p_payment and deleted_at is null;
  if not found then raise exception 'Data tidak ditemukan' using errcode = 'P0002'; end if;
  perform 1 from public.debts where id = pay.debt_id for update;
  if not public._can_modify(pay.business_id, pay.created_by) then
    raise exception 'Tidak punya akses' using errcode = '42501';
  end if;
  update public.cash_transactions set deleted_at = now()
   where debt_payment_id = p_payment and deleted_at is null;
  update public.debt_payments set deleted_at = now() where id = p_payment;
end $$;

-- ---------------------------------------------------------------------------
-- 9. RPC: laporan ringkas (dibaca semua peran)
-- ---------------------------------------------------------------------------
create function public.report_summary(p_business uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare res jsonb;
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  select jsonb_build_object(
    'total_in',  coalesce(sum(amount) filter (where type = 'in'  and txn_date between p_from and p_to), 0),
    'total_out', coalesce(sum(amount) filter (where type = 'out' and txn_date between p_from and p_to), 0),
    'balance',   coalesce(sum(case type when 'in' then amount else -amount end), 0)
  ) into res
  from public.cash_transactions
  where business_id = p_business and deleted_at is null;

  return res || jsonb_build_object(
    'receivable_open', (select coalesce(sum(remaining), 0) from public.debt_balances
                         where business_id = p_business and kind = 'receivable'),
    'payable_open',    (select coalesce(sum(remaining), 0) from public.debt_balances
                         where business_id = p_business and kind = 'payable'));
end $$;

create function public.report_by_category(p_business uuid, p_from date, p_to date)
returns table (category_id uuid, category_name text, type public.txn_type, total bigint, tx_count bigint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require(p_business, array['owner', 'admin', 'staff']::public.member_role[]);
  return query
    select t.category_id, coalesce(c.name, 'Tanpa kategori'), t.type,
           sum(t.amount)::bigint, count(*)::bigint
    from public.cash_transactions t
    left join public.categories c on c.id = t.category_id
    where t.business_id = p_business and t.deleted_at is null
      and t.txn_date between p_from and p_to
    group by t.category_id, c.name, t.type
    order by t.type, 4 desc;
end $$;

-- ---------------------------------------------------------------------------
-- 10. Hak akses tabel dan fungsi
-- ---------------------------------------------------------------------------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

grant select on public.profiles, public.businesses, public.business_members,
                public.invitations, public.categories, public.contacts,
                public.debts, public.debt_payments, public.debt_balances,
                public.cash_transactions, public.activity_log
  to authenticated;

grant update (display_name, last_business_id) on public.profiles to authenticated;
grant update (name, address, phone)           on public.businesses to authenticated;
grant insert (business_id, name, type), update (name) on public.categories to authenticated;
grant delete on public.categories to authenticated;
grant insert (business_id, name, phone, note, created_by),
      update (name, phone, note, deleted_at) on public.contacts to authenticated;
grant insert (business_id, type, amount, category_id, note, txn_date, created_by),
      update (type, amount, category_id, note, txn_date, deleted_at)
  on public.cash_transactions to authenticated;

-- Fungsi yang boleh dipanggil klien (RPC). Fungsi internal (_require, _accept,
-- trigger) sengaja tidak diberi grant.
grant execute on function
  public.my_email(), public.role_in(uuid), public.is_member(uuid),
  public.is_admin_or_owner(uuid), public.shares_business_with(uuid),
  public.create_business(text, text, text), public.delete_business(uuid),
  public.transfer_ownership(uuid, uuid),
  public.change_member_role(uuid, uuid, public.member_role),
  public.remove_member(uuid, uuid), public.leave_business(uuid),
  public.create_invitation(uuid, text, public.member_role),
  public.cancel_invitation(uuid), public.decline_invitation(uuid),
  public.accept_invitation(uuid), public.accept_invitation_by_code(text),
  public.create_debt(uuid, uuid, public.debt_kind, bigint, boolean, date, date, text),
  public.update_debt(uuid, uuid, bigint, date, date, text), public.delete_debt(uuid),
  public.add_debt_payment(uuid, bigint, date, text),
  public.update_debt_payment(uuid, bigint, date, text), public.delete_debt_payment(uuid),
  public.report_summary(uuid, date, date), public.report_by_category(uuid, date, date)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Realtime (tim melihat perubahan tanpa refresh)
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.cash_transactions, public.debts, public.debt_payments, public.business_members;
  end if;
end $$;
