-- BoRR — Vistas de feed con precio + autor, y RPC transaccional de pedido
--
-- Motivo: el BFF (BFFBORR) calculaba el precio de cada pizza en JS (enrichPizzas)
-- y, para el feed Comunidad, hacía un segundo query a profiles_public + merge en
-- memoria. Movemos esa lógica al back con dos vistas que ya devuelven price_cents
-- (y el autor en Comunidad), así el BFF queda como un proxy fino de una sola query.
--
-- Además, la creación de pedido pasa de dos inserts desde el cliente (orders +
-- order_items) a un RPC atómico `place_order` que calcula los precios server-side
-- (no confía en el cliente). Habilita el flujo de pedido para usuarios logueados
-- y anónimos (sign-in anónimo de Supabase → auth.uid() real con is_anonymous=true).

-- ─── 1. price_recipe(recipe jsonb) ───────────────────────────────────────────
-- Replica computePriceCents de BFFBORR/src/lib/borr/pricing.ts:
--   base (pizza_bases.price_cents por recipe.baseId)
--   + Σ items kind='ing': si el ingrediente es unit='g' → round(price_cents*qty/100),
--     sino price_cents*qty. (La unidad sale del catálogo, no del item.)
-- SECURITY DEFINER + search_path fijo: lee catálogo público; reutilizable por las
-- vistas (invoker) y por place_order.
create or replace function public.price_recipe(recipe jsonb)
  returns int
  language sql
  stable
  security definer
  set search_path = public
as $$
  select
    coalesce((select b.price_cents from public.pizza_bases b where b.id = recipe->>'baseId'), 0)
    + coalesce((
        select sum(
          case when i.unit = 'g'
            then round(i.price_cents * (item->>'qty')::numeric / 100.0)
            else i.price_cents * (item->>'qty')::numeric
          end
        )::int
        from jsonb_array_elements(coalesce(recipe->'items', '[]'::jsonb)) as item
        join public.ingredients i on i.id = item->>'ingredientId'
        where item->>'kind' = 'ing'
      ), 0);
$$;

-- ─── 2. Feed de la casa ──────────────────────────────────────────────────────
-- security_invoker=true: la RLS de pizzas ya limita a públicas y el catálogo
-- (ingredients/pizza_bases) es legible por anon → evita el advisor "definer view".
create or replace view public.pizzas_house_feed
  with (security_invoker = true)
as
select
  p.id,
  p.name,
  p.base_id,
  p.size,
  p.recipe,
  p.tags,
  p.preview_url,
  public.price_recipe(p.recipe) as price_cents,
  p.created_at
from public.pizzas p
where p.origin = 'house' and p.is_public and p.deleted_at is null
order by p.created_at asc;

-- ─── 3. Feed de comunidad (+ autor) ──────────────────────────────────────────
-- author_username sale de profiles_public (vista definer de 0005 que expone
-- username/avatar a anon, sin aflojar la RLS de profiles).
create or replace view public.pizzas_community_feed
  with (security_invoker = true)
as
select
  p.id,
  p.name,
  p.base_id,
  p.size,
  p.recipe,
  p.tags,
  p.preview_url,
  public.price_recipe(p.recipe) as price_cents,
  p.user_id,
  p.created_at,
  pp.username as author_username
from public.pizzas p
left join public.profiles_public pp on pp.id = p.user_id
where p.origin = 'user' and p.is_public and p.deleted_at is null
order by p.created_at desc;

grant select on public.pizzas_house_feed     to anon, authenticated;
grant select on public.pizzas_community_feed  to anon, authenticated;

-- ─── 4. place_order(...) — pedido transaccional ──────────────────────────────
-- SECURITY INVOKER: corre como el usuario, así la RLS de orders/order_items
-- (user_id = auth.uid()) aplica naturalmente. El precio de cada línea se calcula
-- en el back con price_recipe(snapshot); el cliente no lo decide.
-- payment_method puede ser null (pago = TODO). Devuelve el id del pedido.
create or replace function public.place_order(
  p_shop_id        uuid,
  p_address_id     uuid,
  p_payment_method payment_method,
  p_notes          text,
  p_items          jsonb
) returns uuid
  language plpgsql
  security invoker
  set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_order_id  uuid;
  v_subtotal  int := 0;
  v_item      jsonb;
begin
  if v_uid is null then
    raise exception 'No autenticado';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido no tiene items';
  end if;

  -- Subtotal calculado server-side desde cada recipe_snapshot.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_subtotal := v_subtotal
      + public.price_recipe(v_item->'recipe_snapshot') * coalesce((v_item->>'qty')::int, 1);
  end loop;

  insert into public.orders
    (user_id, shop_id, address_id, status, subtotal_cents, payment_method, notes, placed_at)
  values
    (v_uid, p_shop_id, p_address_id, 'placed', v_subtotal, p_payment_method, p_notes, now())
  returning id into v_order_id;

  insert into public.order_items
    (order_id, pizza_id, recipe_snapshot, qty, unit_price_cents)
  select
    v_order_id,
    nullif(elem->>'pizza_id', '')::uuid,
    elem->'recipe_snapshot',
    coalesce((elem->>'qty')::int, 1),
    public.price_recipe(elem->'recipe_snapshot')
  from jsonb_array_elements(p_items) as elem;

  return v_order_id;
end;
$$;

-- Sólo usuarios con sesión (incluye anónimos: su JWT tiene role=authenticated).
revoke execute on function public.place_order(uuid, uuid, payment_method, text, jsonb) from anon, public;
grant  execute on function public.place_order(uuid, uuid, payment_method, text, jsonb) to authenticated;
