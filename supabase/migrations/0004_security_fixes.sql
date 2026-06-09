-- BoRR — Correcciones de advisors de seguridad post-aplicación inicial
-- Detectados por mcp__supabase__get_advisors:
--   1. ingredient_stock_by_shop view → security_definer view (downgrade a invoker)
--   2. touch_updated_at → search_path mutable (lock)
--   3. trigger-only functions expuestas por rpc → revocar execute a anon/authenticated

-- ─── 1. View con security invoker (no definer) ──────────────────────────────
drop view if exists public.ingredient_stock_by_shop;

create view public.ingredient_stock_by_shop
  with (security_invoker = true)
as
select
  shop_id,
  ingredient_id,
  sum(delta) as qty_on_hand
from public.stock_movements
group by shop_id, ingredient_id;

-- ─── 2. Lock search_path en touch_updated_at ────────────────────────────────
create or replace function public.touch_updated_at()
  returns trigger
  language plpgsql
  set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ─── 3. Revocar EXECUTE en trigger-only functions ───────────────────────────
-- Estas funciones se invocan SOLO desde triggers internos. Exponerlas por
-- /rest/v1/rpc/{name} es innecesario y un vector de superficie.
revoke execute on function public.sync_pizza_ingredients()           from public, anon, authenticated;
revoke execute on function public.record_order_status_change()       from public, anon, authenticated;
revoke execute on function public.materialize_order_consumption()    from public, anon, authenticated;
revoke execute on function public.handle_new_user()                  from public, anon, authenticated;
revoke execute on function public.touch_updated_at()                 from public, anon, authenticated;

-- is_role() y current_app_role() SÍ necesitan EXECUTE para authenticated:
-- las RLS policies las evalúan en cada query. Se mantienen accesibles.
