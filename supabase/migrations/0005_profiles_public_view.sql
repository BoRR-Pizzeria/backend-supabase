-- BoRR — Vista pública de perfiles (username + avatar)
--
-- Motivo: el feed Comunidad necesita mostrar `@username` junto a la pizza,
-- pero la RLS de `public.profiles` solo permite self-read (auth.uid() = id).
-- En vez de aflojar la RLS y exponer phone/role, creamos una vista delgada
-- con security_invoker=false (definer) que expone solo lo público.
--
-- También agregamos una FK explícita pizzas.user_id → profiles.id para que
-- PostgREST pueda resolver embeds (`profiles:user_id (...)`) si en algún
-- momento queremos volver a usarlos. La FK existente a auth.users(id) se
-- mantiene; PostgREST no expone el schema auth.

-- ─── 1. View pública ───────────────────────────────────────────────────────
create or replace view public.profiles_public
  with (security_invoker = false)
as
select
  id,
  username,
  avatar_url
from public.profiles;

-- Limitar columnas accesibles vía la API
revoke all on public.profiles_public from public, anon, authenticated;
grant select on public.profiles_public to anon, authenticated;

-- ─── 2. FK redundante a profiles para PostgREST embed ──────────────────────
-- profiles.id = auth.users.id (1:1), así que esta FK siempre se cumple cuando
-- la de auth.users también. Permite a PostgREST resolver `profiles:user_id`.
alter table public.pizzas
  add constraint pizzas_user_id_profiles_fk
  foreign key (user_id) references public.profiles(id) on delete cascade;
