-- RekapRapi: tes Bot Telegram tahap 2 (ringkasan, utang piutang, laporan harian).
-- Jalankan SETELAH migrasi 20261115000000. Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES LAPORAN TELEGRAM LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a8', 'ua@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b8', 'ub@test.local', now(), 'authenticated', 'authenticated');

reset role;
set local role service_role;
select public.tg_set_bot('UjiBot');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a8","role":"authenticated"}', true);
set local role authenticated;
do $t$
declare bid uuid;
begin
  bid := public.create_business('Toko Lapor');
  perform set_config('t.biz', bid::text, true);
  perform set_config('t.code', public.telegram_create_code(bid) ->> 'code', true);
end $t$;

-- B menjadi staf.
reset role;
insert into public.business_members (business_id, user_id, role)
values (current_setting('t.biz')::uuid, '00000000-0000-0000-0000-0000000000b8', 'staff');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b8","role":"authenticated"}', true);
set local role authenticated;
select set_config('t.codeb', public.telegram_create_code(current_setting('t.biz')::uuid) ->> 'code', true);

-- Pengguna biasa tidak bisa memanggil fungsi baru.
do $t$
declare failed boolean := false;
begin
  begin perform public.tg_daily_batch(); exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'GAGAL: pengguna memanggil tg_daily_batch'; end if;
  failed := false;
  begin perform public.tg_report(1, 'today'); exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'GAGAL: pengguna memanggil tg_report'; end if;
  failed := false;
  begin perform public._tg_ctx(1); exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'GAGAL: pengguna memanggil _tg_ctx'; end if;
end $t$;

reset role;
set local role service_role;
do $t$
declare
  r jsonb; s jsonb; n bigint; bid uuid := current_setting('t.biz')::uuid;
  batch jsonb; row_a jsonb;
begin
  perform public.tg_link(current_setting('t.code'), 111, 1110, 'Pemilik');
  perform public.tg_link(current_setting('t.codeb'), 222, 2220, 'Staf');

  -- Belum ada apa-apa hari ini: laporan harian tidak dikirim ke siapa pun.
  if jsonb_array_length(public.tg_daily_batch()) <> 0 then
    raise exception 'GAGAL: laporan dikirim padahal kosong';
  end if;

  -- ===== Catatan: kas, penjualan utang, pinjaman =====
  perform public.tg_record(111, '{"kind":"sale","amount":50000,"cost":30000}');
  perform public.tg_record(111, '{"kind":"expense","amount":5000,"note":"parkir"}');

  if public.tg_find_contact(111, 'budi') is not null then raise exception 'GAGAL: kontak belum ada'; end if;
  r := public.tg_record(111, '{"kind":"sale","amount":100000,"cost":60000,"contact":"Budi","note":"kredit"}');
  if not (r ->> 'ok')::boolean or not (r ->> 'new_contact')::boolean or r ->> 'contact' <> 'Budi' then
    raise exception 'GAGAL: penjualan utang %', r;
  end if;
  if public.tg_find_contact(111, '  bUDI ') <> 'Budi' then raise exception 'GAGAL: kontak tidak ditemukan'; end if;
  -- Kontak yang sama dipakai lagi, ejaan tersimpan dipertahankan.
  r := public.tg_record(111, '{"kind":"receivable","amount":20000,"contact":"budi"}');
  if (r ->> 'new_contact')::boolean or r ->> 'contact' <> 'Budi' then raise exception 'GAGAL: kontak ganda %', r; end if;
  select count(*) into n from public.contacts where business_id = bid;
  if n <> 1 then raise exception 'GAGAL: jumlah kontak %', n; end if;

  r := public.tg_record(111, '{"kind":"payable","amount":70000,"contact":"Pak Joko"}');
  if not (r ->> 'ok')::boolean then raise exception 'GAGAL: utang %', r; end if;
  if (public.tg_record(111, '{"kind":"payable","amount":70000}') ->> 'error') <> 'contact' then
    raise exception 'GAGAL: utang tanpa kontak diterima';
  end if;

  -- Penjualan utang bukan kas dan menyimpan modal; pinjaman menggerakkan kas.
  if not exists (select 1 from public.debts where business_id = bid and is_sale and not cash_moved
                  and kind = 'receivable' and amount = 100000 and cost_amount = 60000
                  and created_by = '00000000-0000-0000-0000-0000000000a8') then
    raise exception 'GAGAL: penjualan utang tidak tersimpan utuh';
  end if;
  select count(*) into n from public.cash_transactions
   where business_id = bid and debt_id is not null and deleted_at is null;
  if n <> 2 then raise exception 'GAGAL: kas pinjaman %', n; end if;

  -- ===== Ringkasan pemilik =====
  r := public.tg_report(111, 'today');
  s := r -> 'summary';
  if (s ->> 'income_total')::int <> 150000 or (s ->> 'expense_total')::int <> 95000
     or (s ->> 'net')::int <> 55000 then
    raise exception 'GAGAL: ringkasan pemilik %', s;
  end if;
  if (public.tg_report(111, 'month') #>> '{summary,income_total}')::int <> 150000 then
    raise exception 'GAGAL: ringkasan bulan';
  end if;

  -- ===== Staf tidak menerima pengeluaran, laba, dan saldo =====
  s := public.tg_report(222, 'today') -> 'summary';
  if (s ->> 'income_total')::int <> 150000 then raise exception 'GAGAL: pemasukan staf %', s; end if;
  if s ? 'net' or s ? 'expense_total' or s ? 'expense_cost' or s ? 'profit' or s ? 'balance' then
    raise exception 'GAGAL: staf menerima angka laba %', s;
  end if;

  -- ===== /utang =====
  r := public.tg_debt_overview(111);
  if (r ->> 'receivable_open')::int <> 120000 or (r ->> 'payable_open')::int <> 70000 then
    raise exception 'GAGAL: total utang piutang %', r;
  end if;
  if r #>> '{contacts,0,name}' <> 'Budi' or (r #>> '{contacts,0,net}')::int <> 120000
     or (r #>> '{contacts,1,net}')::int <> -70000 then
    raise exception 'GAGAL: daftar kontak %', r -> 'contacts';
  end if;

  -- Jatuh tempo besok muncul di /utang dan di laporan harian.
  update public.debts set due_date = (now() at time zone 'Asia/Jakarta')::date + 1
   where business_id = bid and is_sale;
  r := public.tg_debt_overview(111);
  if jsonb_array_length(r -> 'due') <> 1 or r #>> '{due,0,name}' <> 'Budi' then
    raise exception 'GAGAL: jatuh tempo %', r -> 'due';
  end if;

  -- ===== Laporan harian =====
  batch := public.tg_daily_batch();
  if jsonb_array_length(batch) <> 2 then raise exception 'GAGAL: penerima laporan %', batch; end if;
  select e into row_a from jsonb_array_elements(batch) e where (e ->> 'chat_id')::bigint = 1110;
  if (row_a #>> '{summary,net}')::int <> 55000 or jsonb_array_length(row_a -> 'due') <> 1 then
    raise exception 'GAGAL: isi laporan pemilik %', row_a;
  end if;
  if exists (select 1 from jsonb_array_elements(batch) e
              where (e ->> 'chat_id')::bigint = 2220 and (e -> 'summary') ? 'net') then
    raise exception 'GAGAL: laporan staf memuat laba';
  end if;

  -- Dimatikan: tidak lagi dikirimi.
  if public.tg_toggle_daily(222) then raise exception 'GAGAL: seharusnya mati'; end if;
  if jsonb_array_length(public.tg_daily_batch()) <> 1 then raise exception 'GAGAL: staf masih dikirimi'; end if;
  if not public.tg_toggle_daily(222) then raise exception 'GAGAL: seharusnya hidup'; end if;

  -- ===== /batal untuk utang piutang =====
  r := public.tg_undo(111);   -- catatan terakhir: utang Pak Joko 70000
  if not (r ->> 'ok')::boolean or (r ->> 'amount')::int <> 70000 then raise exception 'GAGAL: batal utang %', r; end if;
  if (public.tg_debt_overview(111) ->> 'payable_open')::int <> 0 then raise exception 'GAGAL: utang belum terhapus'; end if;
  select count(*) into n from public.cash_transactions
   where business_id = bid and debt_id is not null and deleted_at is null;
  if n <> 1 then raise exception 'GAGAL: kas pinjaman tidak ikut terhapus, %', n; end if;
  if (public.tg_undo(111) ->> 'ok')::boolean then raise exception 'GAGAL: batal dua kali'; end if;

  -- Staf juga boleh mencatat utang piutang, atas namanya sendiri.
  r := public.tg_record(222, '{"kind":"receivable","amount":1000,"contact":"Budi"}');
  if not (r ->> 'ok')::boolean then raise exception 'GAGAL: staf mencatat piutang %', r; end if;
  if not exists (select 1 from public.debts where business_id = bid and amount = 1000
                  and created_by = '00000000-0000-0000-0000-0000000000b8') then
    raise exception 'GAGAL: pencatat staf salah';
  end if;

  -- Akun tak dikenal.
  if (public.tg_report(999, 'today') ->> 'ok')::boolean then raise exception 'GAGAL: akun asing dapat ringkasan'; end if;
  if (public.tg_debt_overview(999) ->> 'ok')::boolean then raise exception 'GAGAL: akun asing dapat utang'; end if;
end $t$;

reset role;
select 'SEMUA TES LAPORAN TELEGRAM LULUS' as hasil;
rollback;
