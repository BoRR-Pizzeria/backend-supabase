-- BoRR — Fix recursión infinita en RLS de orders ↔ deliveries (SQLSTATE 42P17)
--
-- Síntoma: cualquier SELECT/INSERT sobre orders, order_items, deliveries, etc.
-- hecho por un usuario no-admin devolvía:
--   "infinite recursion detected in policy for relation \"orders\""
-- Esto bloqueaba por completo el flujo de pedidos (place_order + leer "mis pedidos").
--
-- Causa: dos policies de SELECT se referenciaban mutuamente formando un ciclo:
--   orders."orders delivery read assigned"      → exists(select … from deliveries …)
--   deliveries."deliveries owner read via order" → exists(select … from orders …)
-- Al evaluar una, Postgres aplica la RLS de la otra y entra en bucle.
--
-- Fix: encapsular los lookups cross-table en funciones SECURITY DEFINER (corren
-- como el owner de las tablas = bypassean RLS, cortando el ciclo). Mismo patrón
-- que public.is_role()/current_app_role() ya usados por el resto de las policies.

-- ─── Helpers (security definer = sin recursión de RLS) ───────────────────────
-- Devuelven sólo un boolean sobre la relación del propio caller (no filtran data),
-- por eso se dejan ejecutables por todos los roles: las expresiones de las policies
-- se evalúan con el rol que consulta (anon/authenticated) y necesitan EXECUTE.
create or replace function public.owns_order(p_order_id uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = public
as $$
  select exists (
    select 1 from public.orders o
    where o.id = p_order_id and o.user_id = auth.uid()
  );
$$;

create or replace function public.is_order_courier(p_order_id uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = public
as $$
  select exists (
    select 1 from public.deliveries d
    where d.order_id = p_order_id and d.courier_id = auth.uid()
  );
$$;

-- ─── orders: repartidor ve sus pedidos asignados (sin recursión a deliveries) ─
drop policy if exists "orders delivery read assigned" on public.orders;
create policy "orders delivery read assigned"
  on public.orders for select
  using (public.is_role('delivery') and public.is_order_courier(orders.id));

-- ─── deliveries: dueño del pedido ve su delivery (sin recursión a orders) ─────
drop policy if exists "deliveries owner read via order" on public.deliveries;
create policy "deliveries owner read via order"
  on public.deliveries for select
  using (public.owns_order(order_id));
