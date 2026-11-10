-- RekapRapi: Bot Telegram, pelunasan dan cicilan utang piutang lewat chat.
--   lunas Budi          melunasi seluruh sisa dengan Budi
--   cicil 50000 Budi    membayar sebagian
-- Arah uang mengikuti saldo bersih kontak: kontak berutang -> uang diterima;
-- pengguna berutang -> uang dibayarkan. Memakai contact_transfer yang sama dengan aplikasi.
-- Jalankan sekali di SQL Editor Supabase, setelah migrasi 20261115000000.

-- Saldo bersih satu kontak di pembukuan aktif (positif = kontak berutang kepada pengguna).
create function public.tg_contact_balance(p_tg_id bigint, p_name text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare c record; ct record;
begin
  select * into c from public._tg_ctx(p_tg_id);
  if c.business_id is null then return jsonb_build_object('found', false); end if;
  select x.id, x.name into ct from public.contacts x
   where x.business_id = c.business_id and x.deleted_at is null
     and lower(btrim(x.name)) = lower(btrim(p_name))
   order by x.created_at limit 1;
  if ct.id is null then return jsonb_build_object('found', false); end if;
  return jsonb_build_object(
    'found', true, 'name', ct.name,
    'net', (select coalesce(sum(case b.kind when 'receivable' then b.remaining
                                             else -b.remaining end), 0)
              from public.debt_balances b
             where b.business_id = c.business_id and b.contact_id = ct.id));
end $$;

-- p_payload: {contact, amount, note}; amount 0 atau kosong = seluruh sisa.
-- Jumlah yang melebihi sisa ditolak agar tidak diam-diam menjadi utang arah sebaliknya.
create function public.tg_settle(p_tg_id bigint, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c record;
  v_contact text := nullif(btrim(coalesce(p_payload ->> 'contact', '')), '');
  v_amount bigint := coalesce((p_payload ->> 'amount')::bigint, 0);
  v_note text := nullif(btrim(coalesce(p_payload ->> 'note', '')), '');
  v_contact_id uuid;
  v_name text;
  v_net bigint;
  v_dir text;
  v_date date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if not exists (select 1 from public.telegram_links where telegram_id = p_tg_id) then
    return jsonb_build_object('ok', false, 'error', 'unlinked');
  end if;
  select * into c from public._tg_ctx(p_tg_id);
  if c.business_id is null then return jsonb_build_object('ok', false, 'error', 'business'); end if;

  select x.id, x.name into v_contact_id, v_name from public.contacts x
   where x.business_id = c.business_id and x.deleted_at is null
     and lower(btrim(x.name)) = lower(v_contact)
   order by x.created_at limit 1;
  if v_contact_id is null then return jsonb_build_object('ok', false, 'error', 'contact'); end if;

  select coalesce(sum(case b.kind when 'receivable' then b.remaining else -b.remaining end), 0)
    into v_net
    from public.debt_balances b
   where b.business_id = c.business_id and b.contact_id = v_contact_id;
  if v_net = 0 then return jsonb_build_object('ok', false, 'error', 'settled'); end if;

  if v_amount < 0 then return jsonb_build_object('ok', false, 'error', 'invalid'); end if;
  if v_amount = 0 then v_amount := abs(v_net); end if;
  if v_amount > abs(v_net) then
    return jsonb_build_object('ok', false, 'error', 'over', 'net', v_net);
  end if;

  v_dir := case when v_net > 0 then 'receive' else 'give' end;
  perform public.contact_transfer(c.business_id, v_contact_id, v_dir, v_amount, v_date, v_note);

  -- Pelunasan tidak bisa dibatalkan dengan /batal; hapus dari aplikasi bila salah.
  update public.telegram_links
     set last_tx_id = null, last_debt_id = null, last_tx_at = null
   where telegram_id = p_tg_id;
  return jsonb_build_object('ok', true, 'business', c.name, 'contact', v_name,
                            'direction', v_dir, 'amount', v_amount,
                            'remaining', abs(v_net) - v_amount);
end $$;

revoke all on function public.tg_contact_balance(bigint, text), public.tg_settle(bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.tg_contact_balance(bigint, text), public.tg_settle(bigint, jsonb)
  to service_role;
