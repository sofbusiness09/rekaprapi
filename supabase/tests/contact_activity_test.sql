-- RekapRapi: tes aktivitas terakhir per kontak. Jalankan SETELAH migrasi 20261120000000.
-- Berjalan dalam transaksi yang di-ROLLBACK.
-- Sukses -> baris terakhir "SEMUA TES AKTIVITAS KONTAK LULUS".

begin;

insert into auth.users (id, email, email_confirmed_at, aud, role) values
  ('00000000-0000-0000-0000-0000000000a1', 'za@test.local', now(), 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b1', 'zb@test.local', now(), 'authenticated', 'authenticated');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid; ani uuid; budi uuid; cici uuid;
begin
  bid := public.create_business('Toko Aktif');
  insert into public.contacts (business_id, name, created_by) values (bid, 'Ani', auth.uid())
    returning id into ani;
  insert into public.contacts (business_id, name, created_by) values (bid, 'Budi', auth.uid())
    returning id into budi;
  insert into public.contacts (business_id, name, created_by) values (bid, 'Cici', auth.uid())
    returning id into cici;
  perform set_config('t.biz', bid::text, true);
  perform set_config('t.ani', ani::text, true);
  perform set_config('t.budi', budi::text, true);
  perform set_config('t.cici', cici::text, true);
  perform set_config('t.dani', public.create_debt(bid, ani, 'receivable', 100000, false)::text, true);
  perform set_config('t.dbudi', public.create_debt(bid, budi, 'receivable', 50000, false)::text, true);
end $t$;

-- Waktu dibuat dimundurkan (hanya admin database yang boleh mengubah kolom waktu).
reset role;
update public.contacts set created_at = now() - interval '10 days'
 where id in (current_setting('t.ani')::uuid, current_setting('t.budi')::uuid);
update public.contacts set created_at = now() - interval '1 day' where id = current_setting('t.cici')::uuid;
update public.debts set created_at = now() - interval '5 days'
 where id in (current_setting('t.dani')::uuid, current_setting('t.dbudi')::uuid);
update public.activity_log set at = now() - interval '5 days' where business_id = current_setting('t.biz')::uuid;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;

do $t$
declare bid uuid := current_setting('t.biz')::uuid;
        ani uuid := current_setting('t.ani')::uuid;
        budi uuid := current_setting('t.budi')::uuid;
        cici uuid := current_setting('t.cici')::uuid;
        a_ani timestamptz; a_budi timestamptz; a_cici timestamptz;
begin
  -- Cici dibuat 1 hari lalu tanpa catatan; Ani dan Budi terakhir 5 hari lalu.
  select last_at into a_cici from public.contact_activity(bid) where contact_id = cici;
  select last_at into a_ani from public.contact_activity(bid) where contact_id = ani;
  if a_cici is null or a_ani is null or a_cici <= a_ani then
    raise exception 'GAGAL: kontak baru harus lebih baru (% vs %)', a_cici, a_ani;
  end if;
  if a_ani > now() - interval '4 days' then raise exception 'GAGAL: waktu Ani %', a_ani; end if;

  -- Budi mencicil sekarang: Budi menjadi yang terbaru.
  perform public.add_debt_payment(current_setting('t.dbudi')::uuid, 10000, current_date, 'cicil');
  select last_at into a_budi from public.contact_activity(bid) where contact_id = budi;
  if a_budi <= a_cici then raise exception 'GAGAL: pembayaran tidak menaikkan aktivitas'; end if;

  -- Catatan Ani diubah: tercatat di riwayat aktivitas, Ani naik.
  perform public.update_debt(current_setting('t.dani')::uuid, ani, 100000, current_date, null, 'diubah');
  select last_at into a_ani from public.contact_activity(bid) where contact_id = ani;
  if a_ani < now() - interval '1 minute' then raise exception 'GAGAL: perubahan tidak menaikkan aktivitas'; end if;

  -- Kontak yang dihapus tidak ikut.
  perform public.delete_contact(cici);
  if exists (select 1 from public.contact_activity(bid) where contact_id = cici) then
    raise exception 'GAGAL: kontak terhapus ikut';
  end if;
end $t$;

-- Bukan anggota ditolak.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
set local role authenticated;
do $t$
declare failed boolean := false;
begin
  begin perform * from public.contact_activity(current_setting('t.biz')::uuid);
  exception when others then failed := true; end;
  if not failed then raise exception 'GAGAL: bukan anggota membaca aktivitas'; end if;
end $t$;

reset role;
select 'SEMUA TES AKTIVITAS KONTAK LULUS' as hasil;
rollback;
