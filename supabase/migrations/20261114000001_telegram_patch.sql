-- RekapRapi: perbaikan aktivasi Bot Telegram.
-- Supabase menolak UPDATE tanpa WHERE lewat API ("UPDATE requires a WHERE clause"),
-- sehingga nama bot gagal disimpan. Jalankan sekali bila migrasi 20261114000000 sudah
-- dijalankan sebelum perbaikan ini; aman dijalankan ulang.

create or replace function public.tg_set_bot(p_username text) returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.telegram_config set bot_username = btrim(p_username), updated_at = now()
   where id;
$$;
