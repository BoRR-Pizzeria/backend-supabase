-- BoRR — Habilitar Supabase Realtime sobre tablas relevantes
-- Para ver:
--  - estado de pedidos (cliente, pizzero, repartidor)
--  - timeline de cambios de estado
--  - tracking GPS del repartidor
--  - movimientos de stock (dashboard low-stock)
--
-- Los filtros (user_id, shop_id, order_id, delivery_id) se aplican desde el cliente
-- vía .channel().on().filter() y se respetan por RLS.

alter publication supabase_realtime add table public.orders;
alter publication supabase_realtime add table public.order_status_events;
alter publication supabase_realtime add table public.deliveries;
alter publication supabase_realtime add table public.delivery_locations;
alter publication supabase_realtime add table public.stock_movements;
alter publication supabase_realtime add table public.pizzas;
