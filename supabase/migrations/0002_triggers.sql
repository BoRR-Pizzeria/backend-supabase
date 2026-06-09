-- BoRR — Triggers de sincronización y lógica de pedidos
-- 1) pizzas → pizza_ingredients (mantener M:N relacional al día desde recipe.items)
-- 2) orders.status → order_status_events (timeline auditable)
-- 3) orders.status placed→preparing → order_item_ingredients + stock_movements

-- ─── 1. Sincronizar pizza_ingredients desde recipe.items ─────────────────────
-- recipe.items es array de { kind: 'ing'|'stage', ingredientId, qty, unit? }.
-- Solo los kind='ing' van a la tabla relacional.
create or replace function public.sync_pizza_ingredients()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  item        jsonb;
  idx         int := 0;
  ing_id      text;
  ing_qty     numeric;
  ing_unit_v  ing_unit;
  ing_default ing_unit;
begin
  -- Borrar filas previas (en update) y reconstruir.
  delete from public.pizza_ingredients where pizza_id = new.id;

  if new.recipe is null or jsonb_typeof(new.recipe -> 'items') <> 'array' then
    return new;
  end if;

  for item in select * from jsonb_array_elements(new.recipe -> 'items')
  loop
    if item ->> 'kind' = 'ing' then
      ing_id  := item ->> 'ingredientId';
      ing_qty := (item ->> 'qty')::numeric;

      -- unit: si viene en el item, se usa; sino se hereda del catálogo.
      if item ? 'unit' then
        ing_unit_v := (item ->> 'unit')::ing_unit;
      else
        select unit into ing_default from public.ingredients where id = ing_id;
        ing_unit_v := coalesce(ing_default, 'unit'::ing_unit);
      end if;

      insert into public.pizza_ingredients (pizza_id, ingredient_id, qty, unit, position)
      values (new.id, ing_id, ing_qty, ing_unit_v, idx)
      on conflict (pizza_id, ingredient_id) do update
        set qty = excluded.qty,
            unit = excluded.unit,
            position = excluded.position;

      idx := idx + 1;
    end if;
  end loop;

  return new;
end;
$$;

create trigger pizzas_sync_ingredients
  after insert or update of recipe on public.pizzas
  for each row execute function public.sync_pizza_ingredients();

-- ─── 2. Registrar cambios de status en order_status_events ───────────────────
create or replace function public.record_order_status_change()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    insert into public.order_status_events (order_id, from_status, to_status, actor_id)
    values (new.id, null, new.status, auth.uid());
  elsif (tg_op = 'UPDATE' and new.status is distinct from old.status) then
    insert into public.order_status_events (order_id, from_status, to_status, actor_id)
    values (new.id, old.status, new.status, auth.uid());
  end if;
  return new;
end;
$$;

create trigger orders_record_status_change
  after insert or update of status on public.orders
  for each row execute function public.record_order_status_change();

-- ─── 3. Materializar order_item_ingredients y stock_movements ────────────────
-- Disparado al pasar a 'preparing'. Idempotente: no re-ejecuta si ya hay movimientos.
create or replace function public.materialize_order_consumption()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
declare
  already_done int;
begin
  -- Solo cuando se pasa a 'preparing'
  if new.status <> 'preparing' or old.status = 'preparing' then
    return new;
  end if;

  -- Idempotencia: si ya generamos movimientos para este pedido, salir.
  select count(*) into already_done
  from public.stock_movements
  where order_id = new.id and reason = 'order';

  if already_done > 0 then
    return new;
  end if;

  -- Materializar order_item_ingredients (multiplicando qty del order_item × pizza_ingredients.qty)
  insert into public.order_item_ingredients (order_item_id, ingredient_id, qty, unit)
  select
    oi.id,
    pi.ingredient_id,
    pi.qty * oi.qty,
    pi.unit
  from public.order_items oi
  join public.pizza_ingredients pi on pi.pizza_id = oi.pizza_id
  where oi.order_id = new.id
  on conflict (order_item_id, ingredient_id) do update
    set qty  = excluded.qty,
        unit = excluded.unit;

  -- Emitir stock_movements (1 fila negativa por ingrediente, agregando todas las líneas)
  insert into public.stock_movements (shop_id, ingredient_id, delta, reason, order_id, actor_id)
  select
    new.shop_id,
    oii.ingredient_id,
    -sum(oii.qty),
    'order'::stock_reason,
    new.id,
    auth.uid()
  from public.order_item_ingredients oii
  join public.order_items oi on oi.id = oii.order_item_id
  where oi.order_id = new.id
  group by oii.ingredient_id;

  return new;
end;
$$;

create trigger orders_materialize_consumption
  after update of status on public.orders
  for each row execute function public.materialize_order_consumption();

-- ─── updated_at touch (helper genérico) ──────────────────────────────────────
create or replace function public.touch_updated_at()
  returns trigger
  language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger pizzas_touch_updated_at
  before update on public.pizzas
  for each row execute function public.touch_updated_at();

create trigger orders_touch_updated_at
  before update on public.orders
  for each row execute function public.touch_updated_at();
