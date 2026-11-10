-- RekapRapi: tes pelunasan lewat Bot Telegram. Jalankan SETELAH migrasi 20261116000000.
-- Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES PELUNASAN TELEGRAM LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a5', 'va@test.local', now(), 'authenticated', 'authenticated');

reset role;
set local role service_role;
select public.tg_set_bot('UjiBot');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a5","role":"authenticated"}', true);
set local role authenticated;
do $t$
declare bid uuid;
begin
  bid := public.create_business('Toko Lunas');
  perform set_config('t.biz', bid::text, true);
  perform set_config('t.code', public.telegram_create_code(bid) ->> 'code', true);
end $t$;

-- Pengguna biasa tidak bisa memanggil fungsi server bot.
do $t$
declare failed boolean := false;
begin
  begin perform public.tg_settle(1, '{}'); exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'GAGAL: pengguna memanggil tg_settle'; end if;
  failed := false;
  begin perform public.tg_contact_balance(1, 'x'); exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'GAGAL: pengguna memanggil tg_contact_balance'; end if;
end $t$;

reset role;
set local role service_role;
do $t$
declare r jsonb; n bigint; bid uuid := current_setting('t.biz')::uuid;
begin
  perform public.tg_link(current_setting('t.code'), 111, 1110, 'Pemilik');

  -- Budi berutang 120.000 (penjualan utang 100.000 + pinjaman 20.000); saya berutang 70.000 ke Joko.
  perform public.tg_record(111, '{"kind":"sale","amount":100000,"cost":60000,"contact":"Budi"}');
  perform public.tg_record(111, '{"kind":"receivable","amount":20000,"contact":"Budi"}');
  perform public.tg_record(111, '{"kind":"payable","amount":70000,"contact":"Joko"}');

  r := public.tg_contact_balance(111, ' bUDI ');
  if not (r ->> 'found')::boolean or r ->> 'name' <> 'Budi' or (r ->> 'net')::int <> 120000 then
    raise exception 'GAGAL: saldo Budi %', r;
  end if;
  if (public.tg_contact_balance(111, 'joko') ->> 'net')::int <> -70000 then raise exception 'GAGAL: saldo Joko'; end if;
  if (public.tg_contact_balance(111, 'Tidak Ada') ->> 'found')::boolean then raise exception 'GAGAL: kontak asing ditemukan'; end if;

  -- Cicilan: uang diterima, sisa berkurang, kas bertambah.
  r := public.tg_settle(111, '{"contact":"budi","amount":50000,"note":"cicilan 1"}');
  if not (r ->> 'ok')::boolean or r ->> 'direction' <> 'receive' or (r ->> 'remaining')::int <> 70000 then
    raise exception 'GAGAL: cicilan %', r;
  end if;
  if (public.tg_contact_balance(111, 'Budi') ->> 'net')::int <> 70000 then raise exception 'GAGAL: sisa setelah cicilan'; end if;
  select coalesce(sum(amount), 0) into n from public.cash_transactions
   where business_id = bid and debt_payment_id is not null and type = 'in' and deleted_at is null;
  if n <> 50000 then raise exception 'GAGAL: kas pelunasan %', n; end if;

  -- Melebihi sisa ditolak dan tidak mengubah apa pun.
  r := public.tg_settle(111, '{"contact":"Budi","amount":70001}');
  if r ->> 'error' <> 'over' or (r ->> 'net')::int <> 70000 then raise exception 'GAGAL: kelebihan %', r; end if;
  if (public.tg_contact_balance(111, 'Budi') ->> 'net')::int <> 70000 then raise exception 'GAGAL: kelebihan mengubah saldo'; end if;

  -- Tanpa jumlah: seluruh sisa.
  r := public.tg_settle(111, '{"contact":"Budi"}');
  if not (r ->> 'ok')::boolean or (r ->> 'amount')::int <> 70000 or (r ->> 'remaining')::int <> 0 then
    raise exception 'GAGAL: lunas %', r;
  end if;
  if public.tg_settle(111, '{"contact":"Budi"}') ->> 'error' <> 'settled' then raise exception 'GAGAL: lunas dua kali'; end if;

  -- Utang saya ke Joko: uang dibayarkan.
  r := public.tg_settle(111, '{"contact":"Joko","amount":0}');
  if r ->> 'direction' <> 'give' or (r ->> 'amount')::int <> 70000 then raise exception 'GAGAL: bayar utang %', r; end if;
  r := public.tg_debt_overview(111);
  if (r ->> 'receivable_open')::int <> 0 or (r ->> 'payable_open')::int <> 0 then
    raise exception 'GAGAL: masih ada sisa %', r;
  end if;
  -- Tidak ada utang baru arah sebaliknya yang tercipta.
  select count(*) into n from public.debts where business_id = bid and deleted_at is null;
  if n <> 3 then raise exception 'GAGAL: jumlah catatan utang %', n; end if;

  -- Pelunasan tidak bisa di-/batal.
  if (public.tg_undo(111) ->> 'ok')::boolean then raise exception 'GAGAL: pelunasan terbatalkan'; end if;

  if public.tg_settle(111, '{"contact":"Tidak Ada"}') ->> 'error' <> 'contact' then raise exception 'GAGAL: kontak asing'; end if;
  if public.tg_settle(999, '{"contact":"Budi"}') ->> 'error' <> 'unlinked' then raise exception 'GAGAL: akun asing'; end if;
end $t$;

reset role;
select 'SEMUA TES PELUNASAN TELEGRAM LULUS' as hasil;
rollback;
