-- RekapRapi: tes Bot Telegram. Jalankan SETELAH migrasi 20261114000000.
-- Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES TELEGRAM LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a7', 'ta@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b7', 'tb@test.local', now(), 'authenticated', 'authenticated');

-- ===== A: bot belum aktif -> tidak bisa membuat kode =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a7","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid; pid uuid; failed boolean := false;
begin
  bid := public.create_business('Toko Tele');
  pid := public.create_business('Dompet', null, null, 'personal');
  perform set_config('t.biz', bid::text, true);
  perform set_config('t.pers', pid::text, true);
  if (public.telegram_status() ->> 'linked')::boolean then raise exception 'GAGAL: belum terhubung'; end if;
  begin perform public.telegram_create_code(bid); exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: kode dibuat padahal bot belum aktif'; end if;

  -- Pengguna biasa tidak bisa memanggil fungsi server bot maupun membaca tabelnya.
  failed := false;
  begin perform public.tg_context(1); exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'GAGAL: pengguna memanggil tg_context'; end if;
  failed := false;
  begin perform public.tg_record(1, '{}'); exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'GAGAL: pengguna memanggil tg_record'; end if;
  failed := false;
  begin perform 1 from public.telegram_links; exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'GAGAL: pengguna membaca telegram_links'; end if;
end $t$;

-- ===== Server bot mengaktifkan bot =====
reset role;
set local role service_role;
select public.tg_set_bot('RekapRapiTestBot');

-- ===== A membuat kode =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a7","role":"authenticated"}', true);
set local role authenticated;
do $t$
declare r jsonb; r2 jsonb;
begin
  r := public.telegram_create_code(current_setting('t.biz')::uuid);
  if r ->> 'bot' <> 'RekapRapiTestBot' or char_length(r ->> 'code') <> 32 then
    raise exception 'GAGAL: kode %', r;
  end if;
  -- Kode baru membatalkan kode lama.
  r2 := public.telegram_create_code(current_setting('t.biz')::uuid);
  perform set_config('t.old', r ->> 'code', true);
  perform set_config('t.code', r2 ->> 'code', true);
end $t$;

-- B tidak bisa membuat kode untuk pembukuan A.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b7","role":"authenticated"}', true);
set local role authenticated;
do $t$
declare failed boolean := false;
begin
  begin perform public.telegram_create_code(current_setting('t.biz')::uuid);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: orang lain membuat kode'; end if;
end $t$;

-- ===== Server bot: menghubungkan dan mencatat =====
reset role;
set local role service_role;
do $t$
declare
  r jsonb; ctx jsonb; n bigint; bid uuid := current_setting('t.biz')::uuid;
  pid uuid := current_setting('t.pers')::uuid; s jsonb;
begin
  if (public.tg_context(111) ->> 'linked')::boolean then raise exception 'GAGAL: belum terhubung'; end if;
  if (public.tg_link('salah', 111, 111, 'A') ->> 'ok')::boolean then raise exception 'GAGAL: kode salah diterima'; end if;
  if (public.tg_link(current_setting('t.old'), 111, 111, 'A') ->> 'ok')::boolean then
    raise exception 'GAGAL: kode lama masih berlaku';
  end if;
  r := public.tg_link(current_setting('t.code'), 111, 111, 'Pak A');
  if not (r ->> 'ok')::boolean or r ->> 'business' <> 'Toko Tele' then raise exception 'GAGAL: tg_link %', r; end if;
  -- Kode hanya sekali pakai.
  if (public.tg_link(current_setting('t.code'), 222, 222, 'X') ->> 'ok')::boolean then
    raise exception 'GAGAL: kode dipakai dua kali';
  end if;

  ctx := public.tg_context(111);
  if ctx #>> '{business,name}' <> 'Toko Tele' or ctx #>> '{business,role}' <> 'owner'
     or jsonb_array_length(ctx -> 'businesses') <> 2 then
    raise exception 'GAGAL: konteks %', ctx;
  end if;

  -- Penjualan dengan modal.
  r := public.tg_record(111, '{"kind":"sale","amount":50000,"cost":30000,"note":"kopi"}');
  if not (r ->> 'ok')::boolean or r ->> 'category' <> 'Penjualan' then raise exception 'GAGAL: jual %', r; end if;
  -- Tanpa modal ditolak.
  if (public.tg_record(111, '{"kind":"sale","amount":50000}') ->> 'ok')::boolean then
    raise exception 'GAGAL: jual tanpa modal diterima';
  end if;
  -- Pemasukan lain dan pengeluaran dengan kategori dari awal catatan.
  r := public.tg_record(111, '{"kind":"income","amount":10000}');
  if r ->> 'category' <> 'Penjualan lainnya' then raise exception 'GAGAL: masuk %', r; end if;
  r := public.tg_record(111, '{"kind":"expense","amount":20000,"note":"Listrik & air bulan ini"}');
  if r ->> 'category' <> 'Listrik & Air' then raise exception 'GAGAL: kategori %', r; end if;
  r := public.tg_record(111, '{"kind":"expense","amount":5000,"note":"parkir"}');
  if r ->> 'category' is not null then raise exception 'GAGAL: kategori harus kosong %', r; end if;
  if (public.tg_record(111, '{"kind":"expense","amount":0}') ->> 'ok')::boolean then
    raise exception 'GAGAL: jumlah 0 diterima';
  end if;

  select count(*) into n from public.cash_transactions
   where business_id = bid and created_by = '00000000-0000-0000-0000-0000000000a7' and deleted_at is null;
  if n <> 4 then raise exception 'GAGAL: jumlah catatan %', n; end if;
  if not exists (select 1 from public.cash_transactions where business_id = bid and is_sale
                  and amount = 50000 and cost_amount = 30000 and note = 'kopi') then
    raise exception 'GAGAL: penjualan tidak tersimpan utuh';
  end if;
  -- Riwayat aktivitas mencatat pengguna yang terhubung.
  select count(*) into n from public.activity_log
   where business_id = bid and entity = 'cash_transactions'
     and user_id = '00000000-0000-0000-0000-0000000000a7';
  if n <> 4 then raise exception 'GAGAL: riwayat aktivitas %', n; end if;

  -- /batal menghapus catatan terakhir saja, sekali.
  r := public.tg_undo(111);
  if not (r ->> 'ok')::boolean or (r ->> 'amount')::int <> 5000 then raise exception 'GAGAL: batal %', r; end if;
  if (public.tg_undo(111) ->> 'ok')::boolean then raise exception 'GAGAL: batal dua kali'; end if;

  -- Konfirmasi: nomor harus cocok, dan hanya bisa diambil sekali.
  perform public.tg_set_pending(111, '{"n":"abc","kind":"expense","amount":1}');
  if public.tg_take_pending(111, 'lain') is not null then raise exception 'GAGAL: nomor lain diterima'; end if;
  if public.tg_take_pending(111, 'abc') is null then raise exception 'GAGAL: pending hilang'; end if;
  if public.tg_take_pending(111, 'abc') is not null then raise exception 'GAGAL: pending diambil dua kali'; end if;

  -- Pindah ke Pembukuan Pribadi: penjualan ditolak, pemasukan tanpa kategori.
  if not public.tg_set_business(111, pid) then raise exception 'GAGAL: pindah pembukuan'; end if;
  if (public.tg_record(111, '{"kind":"sale","amount":5,"cost":1}') ->> 'error') <> 'personal' then
    raise exception 'GAGAL: penjualan di pribadi';
  end if;
  r := public.tg_record(111, '{"kind":"income","amount":7000,"note":"gaji"}');
  if not (r ->> 'ok')::boolean or r ->> 'business' <> 'Dompet' then raise exception 'GAGAL: pribadi %', r; end if;

  -- Tidak bisa pindah ke pembukuan orang lain.
  if public.tg_set_business(111, gen_random_uuid()) then raise exception 'GAGAL: pindah ke pembukuan asing'; end if;

  -- Akun Telegram yang tidak terhubung tidak bisa mencatat.
  if (public.tg_record(999, '{"kind":"expense","amount":1000}') ->> 'error') <> 'unlinked' then
    raise exception 'GAGAL: akun asing mencatat';
  end if;
end $t$;

-- ===== B bergabung sebagai staf lalu dikeluarkan: akses lewat bot ikut hilang =====
reset role;
insert into public.business_members (business_id, user_id, role)
values (current_setting('t.biz')::uuid, '00000000-0000-0000-0000-0000000000b7', 'staff');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b7","role":"authenticated"}', true);
set local role authenticated;
select set_config('t.codeb', public.telegram_create_code(current_setting('t.biz')::uuid) ->> 'code', true);

reset role;
set local role service_role;
do $t$
declare r jsonb;
begin
  r := public.tg_link(current_setting('t.codeb'), 222, 222, 'Staf B');
  if not (r ->> 'ok')::boolean then raise exception 'GAGAL: staf terhubung %', r; end if;
  if public.tg_context(222) #>> '{business,role}' <> 'staff' then raise exception 'GAGAL: peran staf'; end if;
  if not (public.tg_record(222, '{"kind":"expense","amount":3000}') ->> 'ok')::boolean then
    raise exception 'GAGAL: staf mencatat';
  end if;
end $t$;

reset role;
delete from public.business_members
 where business_id = current_setting('t.biz')::uuid and user_id = '00000000-0000-0000-0000-0000000000b7';

set local role service_role;
do $t$
begin
  if (public.tg_record(222, '{"kind":"expense","amount":3000}') ->> 'error') <> 'business' then
    raise exception 'GAGAL: anggota yang dikeluarkan masih mencatat';
  end if;
  if public.tg_context(222) -> 'business' <> 'null'::jsonb and public.tg_context(222) -> 'business' is not null then
    raise exception 'GAGAL: anggota yang dikeluarkan masih punya pembukuan aktif';
  end if;
end $t$;

-- ===== A memutuskan dari aplikasi =====
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a7","role":"authenticated"}', true);
set local role authenticated;
do $t$
begin
  if not (public.telegram_status() ->> 'linked')::boolean or public.telegram_status() ->> 'name' <> 'Pak A' then
    raise exception 'GAGAL: status %', public.telegram_status();
  end if;
  perform public.telegram_unlink();
  if (public.telegram_status() ->> 'linked')::boolean then raise exception 'GAGAL: masih terhubung'; end if;
end $t$;

reset role;
set local role service_role;
do $t$
begin
  if (public.tg_context(111) ->> 'linked')::boolean then raise exception 'GAGAL: bot masih mengenali'; end if;
end $t$;

-- Tanpa login tidak bisa apa-apa.
reset role;
set local role anon;
do $t$
declare failed boolean := false;
begin
  begin perform public.telegram_status(); exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'GAGAL: anon membaca status'; end if;
  failed := false;
  begin perform public.tg_link('x', 1, 1, 'x'); exception when insufficient_privilege then failed := true; end;
  if not failed then raise exception 'GAGAL: anon memanggil tg_link'; end if;
end $t$;

reset role;
select 'SEMUA TES TELEGRAM LULUS' as hasil;
rollback;
