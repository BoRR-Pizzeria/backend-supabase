# DER — Modelo de datos BoRR

Modelo entidad-relación del sistema integral. Cubre identidad, sucursales, catálogo, pedidos, stock, delivery y gamificación. Multi-sucursal desde el inicio. PostGIS para geo. Enums Postgres en lugar de `text + check` para type safety.

El razonamiento detrás de cada decisión está en [`decisiones-de-diseno.md`](./decisiones-de-diseno.md). Un ejemplo concreto del flujo está en [`ejemplos/pedido-mixto.md`](./ejemplos/pedido-mixto.md).

## Diagrama

```
                              ┌──────────────────┐
                              │   auth.users     │ (Supabase Auth)
                              └────────┬─────────┘
                                       │ 1:1
                                       ▼
                              ┌──────────────────┐ 1     N ┌──────────────────────┐
                              │    profiles      │─────────│    addresses         │
                              │──────────────────│         │──────────────────────│
                              │ id  uuid PK,FK   │         │ id          uuid PK  │
                              │ username  text U │         │ user_id  uuid FK     │
                              │ role  user_role  │         │ label    text        │
                              │ points    int    │         │ street   text        │
                              │ phone     text   │         │ location geography(Pt)│
                              │ avatar_url       │         │ is_default bool      │
                              └────────┬─────────┘         └──────────────────────┘
                                       │
                                       │ 1:N (orders, pizzas, likes)
                                       │
                       ┌───────────────┼─────────────────┐
                       ▼               ▼                 ▼
              ┌────────────────┐ ┌────────────┐ ┌──────────────┐
              │   pizzas       │ │  orders    │ │ pizza_likes  │
              │────────────────│ │────────────│ │──────────────│
              │ id    uuid PK  │ │ id  PK     │ │ user_id FK   │
              │ user_id FK NULL│ │ user_id FK │ │ pizza_id FK  │
              │ origin         │ │ shop_id FK │ │ created_at   │
              │  pizza_origin  │ │ address_id │ │ PK(user,pizza)
              │ is_public bool │ │ status     │ └──────────────┘
              │ name  text     │ │  order_st. │
              │ base_id FK     │ │ subtotal_  │
              │ size  pizza_sz │ │   cents    │
              │ recipe jsonb   │ │ delivery_  │
              │ preview_url    │ │   cents    │
              │ tags text[]    │ │ discount_  │
              │ created_at     │ │   cents    │
              │ updated_at     │ │ total_cents│
              │ deleted_at     │ │ payment_m. │
              └────────┬───────┘ │ paid_at    │
                       │         │ placed_at  │
                       │ N:M     │ created_at │
                       ▼         │ updated_at │
              ┌────────────────────┐ │ notes  │
              │ pizza_ingredients  │ └──────┬─┘
              │────────────────────│        │ 1:N
              │ pizza_id FK        │        ▼
              │ ingredient_id FK   │┌──────────────────────┐
              │ qty   numeric      ││   order_items        │
              │ unit  ing_unit     ││──────────────────────│
              │ position int       ││ id        uuid PK    │
              │ PK(pizza,ingr)     ││ order_id  FK         │
              └────────┬───────────┘│ pizza_id  FK NULL    │
                       │            │  on delete set null  │
                       │ N:1        │ recipe_snapshot jsonb│
                       ▼            │ qty       int        │
              ┌──────────────────────┐ │ unit_price_cents  │
              │   ingredients        │ │ line_total_cents  │
              │──────────────────────│ │  (generated)      │
              │ id   text PK (slug)  │ └──────────┬────────┘
              │ name text            │            │ 1:N
              │ category ing_cat     │            ▼
              │ price_cents int      │ ┌──────────────────────────┐
              │ unit  ing_unit       │ │ order_item_ingredients   │
              │ is_base bool         │ │──────────────────────────│
              │ active bool          │ │ order_item_id FK         │
              │ min_stock_qty num    │ │ ingredient_id FK         │
              └──────┬───────────────┘ │ qty       numeric        │
                     │ 1:N             │ unit      ing_unit       │
                     ▼                 └──────────┬───────────────┘
            ┌──────────────────────┐              │ trigger insert
            │  stock_movements     │◄─────────────┘ on order placed→preparing
            │  (ledger por shop)   │
            │──────────────────────│
            │ id        uuid PK    │
            │ shop_id   FK         │
            │ ingredient_id FK     │
            │ delta     numeric    │ (+ in, - out)
            │ reason  stock_reason │
            │ order_id  FK NULL    │
            │ actor_id  FK profile │
            │ note      text       │
            │ created_at           │
            └──────────────────────┘
            ┌── view: ingredient_stock_by_shop
            │   sum(delta) group by shop_id, ingredient_id
            └─────────────────────────────────

┌──────────────────────┐  ┌────────────────────────┐
│  shops               │  │  order_status_events   │
│──────────────────────│  │────────────────────────│
│ id       uuid PK     │  │ id       uuid PK       │
│ name     text        │  │ order_id FK            │
│ address  text        │  │ from_status order_st.  │
│ location geography(Pt│  │ to_status   order_st.  │
│ phone    text        │  │ actor_id FK profiles   │
│ active   bool        │  │ note     text          │
│ created_at           │  │ created_at             │
└──────────────────────┘  └────────────────────────┘
        ▲ shop_id usado en
        │ orders, stock_movements,
        │ deliveries

┌──────────────────────┐  ┌────────────────────────┐
│  deliveries          │ 1│  delivery_locations    │ N
│──────────────────────│──│────────────────────────│
│ id       uuid PK     │  │ id        uuid PK      │
│ order_id FK U        │  │ delivery_id FK         │
│ shop_id  FK          │  │ position  geography(Pt)│
│ courier_id FK profile│  │ heading   numeric      │
│ status   delivery_st.│  │ speed     numeric      │
│ assigned_at          │  │ recorded_at            │
│ picked_up_at         │  └────────────────────────┘
│ delivered_at         │
│ route_seq int        │
└──────────────────────┘

┌──────────────────────┐
│  pizza_bases         │       ┌────────────────────────┐
│──────────────────────│       │  achievements          │
│ id   text PK         │       │────────────────────────│
│ name text            │       │ id        text PK      │
│ price_cents int      │       │ name      text         │
│ active bool          │       │ description text       │
└──────────────────────┘       │ points    int          │
                                │ icon      text         │
                                └────────┬───────────────┘
                                         │ N:M
                                         ▼
                                ┌────────────────────────┐
                                │  user_achievements     │
                                │────────────────────────│
                                │ user_id FK             │
                                │ achievement_id FK      │
                                │ unlocked_at            │
                                │ PK(user, achievement)  │
                                └────────────────────────┘

┌──────────────────────┐
│  points_log (ledger) │
│──────────────────────│
│ id       uuid PK     │
│ user_id  FK          │
│ delta    int         │
│ reason   text        │
│ ref_type text        │
│ ref_id   uuid        │
│ created_at           │
└──────────────────────┘
```

## Enums

```sql
create type user_role        as enum ('customer','delivery','pizzero','admin');
create type pizza_origin     as enum ('house','user');
create type pizza_size       as enum ('S','M','L');
create type ing_category     as enum ('Base','Quesos','Carnes','Verdes','Hongos','Otros');
create type ing_unit         as enum ('unit','g');
create type order_status     as enum ('draft','placed','preparing','ready','delivering','delivered','cancelled');
create type delivery_status  as enum ('pending','assigned','picked_up','delivered','cancelled');
create type payment_method   as enum ('cash','card','mercadopago');
create type stock_reason     as enum ('purchase','order','adjust','waste','return','transfer');
```

`mcp__supabase__generate_typescript_types` los expone como union types literales en TS.

## Tablas

### Identidad y direcciones

- **`profiles`** — extiende `auth.users`. `id pk fk`, `username unique`, `role user_role`, `points int`, `phone`, `avatar_url`. RLS: self read/update; admin all.
- **`addresses`** — `id`, `user_id fk`, `label`, `street`, `city`, `notes`, `location geography(Point,4326)`, `is_default`. Index GIST en `location`. RLS: owner all.

### Sucursales

- **`shops`** — `id uuid pk`, `name`, `address`, `location geography(Point,4326)`, `phone`, `active`. Por ahora 1 fila; preparado para N.

### Catálogo

- **`pizza_bases`** — `id text pk` (slug), `name`, `price_cents`, `description`, `active`.
- **`ingredients`** — `id text pk` (slug), `name`, `category ing_category`, `color`, `model_url`, `price_cents`, `unit ing_unit`, `step`, `default_qty`, `is_base bool`, `active bool`, `min_stock_qty numeric` (umbral alerta low-stock). Sin columna de stock — se deriva del ledger. RLS: lectura pública si `active`.
- **`pizzas`** — `id`, `user_id uuid NULL fk auth.users`, `origin pizza_origin`, `is_public bool default false`, `name`, `base_id fk pizza_bases`, `size pizza_size`, `recipe jsonb`, `preview_url`, `tags text[]`, `created_at`, `updated_at`, `deleted_at`. **Constraint**: `check ((origin='house' and user_id is null) or (origin='user' and user_id is not null))`.
- **`pizza_ingredients`** (M:N) — `pizza_id fk`, `ingredient_id fk`, `qty numeric`, `unit ing_unit`, `position int`, `PK(pizza_id, ingredient_id)`. Sincronizado por trigger desde `recipe.items`.

### Pedidos

- **`orders`** — `id`, `user_id fk`, `shop_id fk shops`, `address_id fk addresses NULL` (null para take-away), `status order_status default 'draft'`, `subtotal_cents`, `delivery_cents`, `discount_cents`, `total_cents` (generated), `payment_method payment_method`, `paid_at`, `placed_at`, `notes text`, `created_at`, `updated_at`.
- **`order_items`** — `id`, `order_id fk`, `pizza_id fk NULL on delete set null`, `recipe_snapshot jsonb`, `qty int`, `unit_price_cents`, `line_total_cents` (generated `qty * unit_price_cents`).
- **`order_item_ingredients`** — `order_item_id fk`, `ingredient_id fk`, `qty numeric`, `unit ing_unit`. Materializado por trigger al pasar `placed → preparing`.
- **`order_status_events`** — `id`, `order_id fk`, `from_status order_status`, `to_status order_status`, `actor_id fk profiles`, `note`, `created_at`. Insertado por trigger en update de `orders.status`.

### Stock

- **`stock_movements`** — `id`, `shop_id fk`, `ingredient_id fk`, `delta numeric` (+ in, - out), `reason stock_reason`, `order_id fk NULL`, `actor_id fk profiles`, `note`, `created_at`. Index `(shop_id, ingredient_id, created_at desc)`.
- **`ingredient_stock_by_shop`** (vista) — `select shop_id, ingredient_id, sum(delta) as qty_on_hand from stock_movements group by 1,2`.

### Delivery

- **`deliveries`** — `id`, `order_id fk unique`, `shop_id fk`, `courier_id fk profiles` (rol delivery), `status delivery_status`, `assigned_at`, `picked_up_at`, `delivered_at`, `route_seq int`.
- **`delivery_locations`** — `id`, `delivery_id fk`, `position geography(Point,4326)`, `heading numeric`, `speed numeric`, `recorded_at`. Particionable por día (alta frecuencia).

### Social y gamificación

- **`pizza_likes`** — `user_id fk`, `pizza_id fk`, `created_at`, `PK(user, pizza)`.
- **`achievements`** — catálogo (id, name, description, points, icon).
- **`user_achievements`** — `user_id fk`, `achievement_id fk`, `unlocked_at`, `PK(user, achievement)`.
- **`points_log`** — ledger de puntos (`delta`, `reason`, `ref_type`, `ref_id`).

## Triggers / lógica server-side

1. **`pizzas` insert/update** → sincronizar `pizza_ingredients` desde `recipe.items` (mantener relacional al día).
2. **`orders.status` update** → insertar `order_status_events` con (from, to, actor).
3. **`orders.status: placed → preparing`** → materializar `order_item_ingredients` desde `pizza_ingredients × qty` y agregar `stock_movements` (1 fila negativa por ingrediente).
4. **`auth.users` insert** → crear `profiles` (heredado del MVP 1).
5. **Helper RLS**: `function is_role(text) returns bool` que lee `profiles.role`.

## Realtime channels (Supabase Realtime)

| Canal | Filtro | Subscripción |
|-------|--------|--------------|
| `orders` | `user_id=auth.uid()` | Cliente — ve estado de SUS pedidos |
| `orders` | `shop_id=X and status in ('placed','preparing')` | Pizzero — cola de producción |
| `orders` | `shop_id=X and status='ready'` | Repartidor — pedidos listos |
| `order_status_events` | `order_id=X` | Cliente del pedido |
| `delivery_locations` | `delivery_id=X` | Cliente del pedido en delivery |
| `stock_movements` | `shop_id=X` | Admin/Pizzero — dashboard low-stock |

Habilitado vía: `alter publication supabase_realtime add table orders, order_status_events, delivery_locations, stock_movements;`

## DDL

El DDL completo está en `supabase/migrations/`:
- `0001_init.sql` — extensiones, enums, tablas, índices, RLS, triggers de auth.
- `0002_triggers.sql` — triggers de sincronización (pizzas→ingredients, orders→events, stock).
- `0003_realtime.sql` — `alter publication`.
- `seed.sql` — datos iniciales (shop, bases, ingredientes, house pizzas).
