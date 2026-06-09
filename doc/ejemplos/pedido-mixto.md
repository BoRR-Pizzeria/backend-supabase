# Ejemplo: pedido con casa + comunidad + pizza propia

Caso concreto que ejercita las tres clases de pizza del modelo y el flujo completo de stock + realtime.

## Escenario

Juan (`user_id = U_juan`) hace un pedido con:

1. **Margarita** — pizza de la casa (catálogo del admin).
2. **Veggie Power** — pizza de la comunidad, creada por María.
3. **Mi Combo** — pizza propia que Juan armó al momento, sin publicar.

## Datos previos

```sql
-- 1 sucursal
insert into shops (id, name) values ('S1', 'BoRR Centro');

-- pizza de la casa (admin)
insert into pizzas (id, user_id, origin, is_public, name, base_id, size)
values ('PZ_marg', null, 'house', true, 'Margarita', 'classic', 'M');
-- + filas en pizza_ingredients: masa, salsa, mozza, albahaca

-- pizza de la comunidad (María)
insert into pizzas (id, user_id, origin, is_public, name, base_id, size)
values ('PZ_veg', 'U_maria', 'user', true, 'Veggie Power', 'thin', 'L');
-- + filas en pizza_ingredients: masa, salsa, mozza, morrón, cebolla, champiñón

-- pizza privada de Juan (creada al armar el pedido)
insert into pizzas (id, user_id, origin, is_public, name, base_id, size)
values ('PZ_combo', 'U_juan', 'user', false, 'Mi Combo', 'classic', 'M');
-- + filas en pizza_ingredients: masa, salsa, mozza, jamón, ananá
```

## Crear el pedido

```sql
-- cabecera del pedido
insert into orders (id, user_id, shop_id, address_id, status,
                    subtotal_cents, delivery_cents, total_cents, payment_method)
values ('O_001', 'U_juan', 'S1', 'A_juan_casa', 'placed',
        10500, 800, 11300, 'cash');

-- 3 líneas (cada pizza es un order_item con su snapshot)
insert into order_items (id, order_id, pizza_id, recipe_snapshot, qty, unit_price_cents) values
  ('OI_1', 'O_001', 'PZ_marg',  '{"name":"Margarita","origin":"house",
                                  "base":{"id":"classic","price_cents":1200},"size":"M",
                                  "items":[{"ingredient_id":"masa","qty":1,"unit":"unit","price_cents":0},
                                           {"ingredient_id":"salsa","qty":1,"unit":"unit","price_cents":8000},
                                           {"ingredient_id":"mozza","qty":150,"unit":"g","price_cents":15000},
                                           {"ingredient_id":"albahaca","qty":5,"unit":"g","price_cents":600}],
                                  "subtotal_cents":3500}'::jsonb, 1, 3500),
  ('OI_2', 'O_001', 'PZ_veg',   '{"name":"Veggie Power","origin":"user", ...}'::jsonb, 1, 4200),
  ('OI_3', 'O_001', 'PZ_combo', '{"name":"Mi Combo","origin":"user", ...}'::jsonb,    1, 2800);
```

## Pasar a `preparing` (trigger genera stock + ingredients)

```sql
update orders set status = 'preparing' where id = 'O_001';
```

El trigger `on_order_status_change` hace:

1. Inserta `order_status_events`:
   ```
   from_status='placed', to_status='preparing', actor_id='U_juan'
   ```
2. Materializa `order_item_ingredients` desde `pizza_ingredients` × `qty`:
   ```
   OI_1 → masa:1u, salsa:1u, mozza:150g, albahaca:5g
   OI_2 → masa:1u, salsa:1u, mozza:200g, morrón:50g, cebolla:30g, champi:80g
   OI_3 → masa:1u, salsa:1u, mozza:150g, jamón:80g, ananá:40g
   ```
3. Agrega 1 `stock_movements` negativo por `(shop_id, ingredient_id)`:
   ```
   S1, masa,     -3,    'order', O_001
   S1, salsa,    -3,    'order', O_001
   S1, mozza,    -500,  'order', O_001
   S1, albahaca, -5,    'order', O_001
   S1, morron,   -50,   'order', O_001
   S1, cebolla,  -30,   'order', O_001
   S1, champi,   -80,   'order', O_001
   S1, jamon,    -80,   'order', O_001
   S1, ananá,    -40,   'order', O_001
   ```

## Vistas en tiempo real

| Quién | Subscripción | Ve |
|-------|--------------|-----|
| Juan (cliente) | `orders` con `id='O_001'`, `order_status_events` con `order_id='O_001'` | "Preparando" → "Lista" → "En camino" en vivo |
| Pizzero | `orders` con `shop_id='S1' and status in ('placed','preparing')` | El pedido aparece en su cola |
| Admin | `stock_movements` con `shop_id='S1'` | Dashboard de stock se actualiza, alerta si algo bajó del `min_stock_qty` |
| Repartidor | `orders` con `shop_id='S1' and status='ready'` | Aparece cuando el pizzero marca lista |

## Casos borde demostrados

### María edita "Veggie Power" después
```sql
update pizzas set name = 'Veggie Power XL' where id = 'PZ_veg';
```
→ `OI_2.recipe_snapshot.name` sigue siendo "Veggie Power". El pedido de Juan no cambia.

### Juan borra "Mi Combo" después
```sql
delete from pizzas where id = 'PZ_combo';
```
→ `OI_3.pizza_id` pasa a `null` (`on delete set null`). El `recipe_snapshot` mantiene todo el detalle del pedido.

### Admin saca de circulación una pizza de la casa
```sql
update pizzas set is_public = false where id = 'PZ_marg';
```
→ La Margarita deja de aparecer en la vista pública, pero los pedidos pasados siguen referenciándola.
