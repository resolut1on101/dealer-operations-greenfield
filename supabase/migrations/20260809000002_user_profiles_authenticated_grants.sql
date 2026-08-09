-- RLS policies require matching table privileges for authenticated API callers.
-- ANON receives no privileges on this identity foundation table.

grant select, insert, update, delete on table public.user_profiles to authenticated;
