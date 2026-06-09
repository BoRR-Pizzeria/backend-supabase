-- BoRR — Seed inicial
-- Idempotente: usa on conflict do nothing.
-- Ejecutar DESPUÉS de aplicar las migrations 0001/0002/0003.

-- ─── Sucursal default ────────────────────────────────────────────────────────
-- ID fijo para que los seeds de pizzas/stock referencien la misma fila.
insert into public.shops (id, name, address, active) values
  ('00000000-0000-0000-0000-000000000001', 'BoRR Centro', 'Av. Siempreviva 123', true)
on conflict (id) do nothing;

-- ─── Bases de pizza ──────────────────────────────────────────────────────────
insert into public.pizza_bases (id, name, description, price_cents, active) values
  ('classic',  'Masa madre clásica',  'Masa fermentada 24h, miga aireada',  1200, true),
  ('thin',     'Masa fina',           'Crocante, estilo romana',            1200, true),
  ('integral', 'Masa integral',       'Harina integral + semillas',         1400, true)
on conflict (id) do nothing;

-- ─── Ingredientes (catálogo) ─────────────────────────────────────────────────
-- Precios en cents (multiplicar ARS × 100). Los `unit='g'` usan price_cents
-- por 100g (la app calcula `line_cost = price_cents * qty / 100`).
insert into public.ingredients
  (id, name, category, color, price_cents, unit, step, default_qty, is_base, active)
values
  -- Base (siempre incluida)
  ('masa',              'Masa madre',         'Base',    '#E8C386',     0, 'unit',  1,   1, true,  true),
  ('salsa',             'Salsa tomate',       'Base',    '#C9342A',  8000, 'unit',  1,   1, true,  true),

  -- Quesos
  ('mozza',             'Mozzarella',         'Quesos',  '#FBF1C7', 32000, 'unit',  1,   1, false, true),
  ('parm',              'Parmesano',          'Quesos',  '#F2D88A', 28000, 'unit',  1,   1, false, true),
  ('gorg',              'Gorgonzola',         'Quesos',  '#E8E0C0', 38000, 'unit',  1,   1, false, true),

  -- Verdes
  ('albahaca',          'Albahaca',           'Verdes',  '#4A7A3B',  9000, 'unit',  1,   1, false, true),
  ('rucula',            'Rúcula',             'Verdes',  '#5C8A48', 11000, 'unit',  1,   1, false, true),
  ('cebolla',           'Cebolla morada',     'Verdes',  '#7E3C5A',  8000, 'unit',  1,   1, false, true),
  ('aceituna',          'Aceituna',           'Verdes',  '#2E2A1F', 12000, 'unit',  1,   1, false, true),
  ('morron',            'Morrón',             'Verdes',  '#D9472E',  9000, 'unit',  1,   1, false, true),

  -- Carnes
  ('carne_desmechada',  'Carne desmechada',   'Carnes',  '#9C4628',  3500, 'g',    25, 100, false, true),
  ('jamon',             'Jamón crudo',        'Carnes',  '#D67A6A', 36000, 'unit',  1,   1, false, true),
  ('bacon',             'Panceta',            'Carnes',  '#A24A2C', 24000, 'unit',  1,   1, false, true),

  -- Hongos
  ('champi',            'Champignón',         'Hongos',  '#C9B299', 18000, 'unit',  1,   1, false, true),
  ('porto',             'Portobello',         'Hongos',  '#705541', 22000, 'unit',  1,   1, false, true)
on conflict (id) do nothing;

-- ─── Pizzas de la casa (admin) ───────────────────────────────────────────────
-- IDs fijos para que la UI pueda destacarlas si hace falta.
-- recipe.items sigue el schema v2: { kind: 'ing', ingredientId, qty, unit? }.
insert into public.pizzas
  (id, user_id, origin, is_public, name, base_id, size, recipe, tags)
values
  ('10000000-0000-0000-0000-000000000001', null, 'house', true, 'Margarita', 'classic', 'M',
   '{
     "baseId": "classic",
     "size": "M",
     "items": [
       {"kind":"ing","ingredientId":"masa","qty":1},
       {"kind":"ing","ingredientId":"salsa","qty":1},
       {"kind":"ing","ingredientId":"mozza","qty":1},
       {"kind":"ing","ingredientId":"albahaca","qty":1}
     ],
     "version": 2
   }'::jsonb,
   array['casa','clasica']),

  ('10000000-0000-0000-0000-000000000002', null, 'house', true, 'Cuatro Quesos', 'classic', 'M',
   '{
     "baseId": "classic",
     "size": "M",
     "items": [
       {"kind":"ing","ingredientId":"masa","qty":1},
       {"kind":"ing","ingredientId":"salsa","qty":1},
       {"kind":"ing","ingredientId":"mozza","qty":1},
       {"kind":"ing","ingredientId":"parm","qty":1},
       {"kind":"ing","ingredientId":"gorg","qty":1}
     ],
     "version": 2
   }'::jsonb,
   array['casa','quesos']),

  ('10000000-0000-0000-0000-000000000003', null, 'house', true, 'Bacon Lover', 'thin', 'M',
   '{
     "baseId": "thin",
     "size": "M",
     "items": [
       {"kind":"ing","ingredientId":"masa","qty":1},
       {"kind":"ing","ingredientId":"salsa","qty":1},
       {"kind":"ing","ingredientId":"mozza","qty":1},
       {"kind":"ing","ingredientId":"bacon","qty":1},
       {"kind":"ing","ingredientId":"cebolla","qty":1}
     ],
     "version": 2
   }'::jsonb,
   array['casa','carne']),

  ('10000000-0000-0000-0000-000000000004', null, 'house', true, 'Funghi', 'integral', 'M',
   '{
     "baseId": "integral",
     "size": "M",
     "items": [
       {"kind":"ing","ingredientId":"masa","qty":1},
       {"kind":"ing","ingredientId":"salsa","qty":1},
       {"kind":"ing","ingredientId":"mozza","qty":1},
       {"kind":"ing","ingredientId":"champi","qty":1},
       {"kind":"ing","ingredientId":"porto","qty":1},
       {"kind":"ing","ingredientId":"rucula","qty":1}
     ],
     "version": 2
   }'::jsonb,
   array['casa','hongos','veggie'])
on conflict (id) do nothing;
-- Nota: los inserts disparan el trigger pizzas_sync_ingredients que llena
-- pizza_ingredients automáticamente desde recipe.items.

-- ─── Stock inicial (carga simulada al inventario de la sucursal) ─────────────
-- Movimiento de tipo 'purchase' por cada ingrediente para arrancar con stock real.
-- Idempotencia: solo insertar si no hay movimientos previos para ese (shop, ingr).
insert into public.stock_movements
  (shop_id, ingredient_id, delta, reason, note)
select
  '00000000-0000-0000-0000-000000000001',
  i.id,
  case i.unit when 'g' then 5000 else 50 end,  -- 5kg si gramos, 50 unidades sino
  'purchase'::stock_reason,
  'seed inicial'
from public.ingredients i
where not exists (
  select 1 from public.stock_movements sm
  where sm.shop_id = '00000000-0000-0000-0000-000000000001'
    and sm.ingredient_id = i.id
);

-- ─── Achievements iniciales (gamificación) ──────────────────────────────────
insert into public.achievements (id, name, description, points, icon, active) values
  ('first_pizza',    'Primera pizza',     'Creaste tu primera pizza',          50,  'pizza',     true),
  ('first_order',    'Primer pedido',     'Hiciste tu primer pedido',          100, 'cart',      true),
  ('publish_pizza',  'Publicado',         'Publicaste una pizza a la comunidad', 75, 'megaphone', true),
  ('ten_pizzas',     'Maestro pizzero',   'Creaste 10 pizzas',                 200, 'crown',     true)
on conflict (id) do nothing;
