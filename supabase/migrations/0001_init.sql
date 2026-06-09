-- BoRR — Modelo de datos completo
-- Identidad, sucursales, catálogo, pedidos, stock (ledger), delivery, social, gamificación.
-- Multi-sucursal desde el inicio. PostGIS para geo. Enums Postgres para type safety.
-- Doc: ./doc/der.md, ./doc/decisiones-de-diseno.md

-- ─── Extensiones ─────────────────────────────────────────────────────────────
create extension if not exists pgcrypto;
create extension if not exists postgis;

-- ─── Enums ───────────────────────────────────────────────────────────────────
create type user_role        as enum ('customer','delivery','pizzero','admin');
create type pizza_origin     as enum ('house','user');
create type pizza_size       as enum ('S','M','L');
create type ing_category     as enum ('Base','Quesos','Carnes','Verdes','Hongos','Otros');
create type ing_unit         as enum ('unit','g');
create type order_status     as enum ('draft','placed','preparing','ready','delivering','delivered','cancelled');
create type delivery_status  as enum ('pending','assigned','picked_up','delivered','cancelled');
create type payment_method   as enum ('cash','card','mercadopago');
create type stock_reason     as enum ('purchase','order','adjust','waste','return','transfer');

-- ─── profiles: extiende auth.users ───────────────────────────────────────────
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text unique not null,
  role        user_role not null default 'customer',
  points      int  not null default 0,
  phone       text,
  avatar_url  text,
  created_at  timestamptz not null default now()
);

-- ─── Helper functions (después de profiles) ──────────────────────────────────
-- plpgsql (no sql) para evitar resolución eager de `profiles` antes de existir.
create or replace function public.is_role(target user_role)
  returns boolean
  language plpgsql
  stable
  security definer
  set search_path = public
as $$
begin
  return exists (
    select 1 from public.profiles
    where id = auth.uid() and role = target
  );
end;
$$;

create or replace function public.current_app_role()
  returns user_role
  language plpgsql
  stable
  security definer
  set search_path = public
as $$
declare r user_role;
begin
  select role into r from public.profiles where id = auth.uid();
  return r;
end;
$$;

-- ─── addresses: direcciones del cliente (PostGIS) ────────────────────────────
create table public.addresses (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  label       text not null,
  street      text not null,
  city        text,
  notes       text,
  location    geography(Point, 4326),
  is_default  boolean not null default false,
  created_at  timestamptz not null default now()
);
create index addresses_user_id_idx on public.addresses (user_id);
create index addresses_location_gix on public.addresses using gist (location);

-- ─── shops: sucursales ───────────────────────────────────────────────────────
create table public.shops (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  address     text,
  location    geography(Point, 4326),
  phone       text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create index shops_location_gix on public.shops using gist (location);

-- ─── pizza_bases: catálogo de bases ──────────────────────────────────────────
create table public.pizza_bases (
  id           text primary key,
  name         text not null,
  description  text,
  price_cents  int not null default 0,
  active       boolean not null default true
);

-- ─── ingredients: catálogo de ingredientes ───────────────────────────────────
create table public.ingredients (
  id              text primary key,
  name            text not null,
  category        ing_category not null default 'Otros',
  color           text,
  model_url       text,
  price_cents     int not null default 0,
  unit            ing_unit not null default 'unit',
  step            int not null default 1,
  default_qty     int not null default 1,
  is_base         boolean not null default false,
  active          boolean not null default true,
  min_stock_qty   numeric(12,3) not null default 0
);

-- ─── pizzas: creaciones (casa + usuario) ─────────────────────────────────────
create table public.pizzas (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete cascade,
  origin       pizza_origin not null,
  is_public    boolean not null default false,
  name         text,
  base_id      text references public.pizza_bases(id),
  size         pizza_size not null default 'M',
  recipe       jsonb not null,
  preview_url  text,
  tags         text[] not null default '{}',
  views_count  int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  constraint pizzas_origin_owner_check check (
    (origin = 'house' and user_id is null) or
    (origin = 'user'  and user_id is not null)
  )
);
create index pizzas_user_id_idx       on public.pizzas (user_id) where user_id is not null;
create index pizzas_origin_public_idx on public.pizzas (origin, is_public) where deleted_at is null;
create index pizzas_created_at_idx    on public.pizzas (created_at desc) where deleted_at is null;

-- ─── pizza_ingredients: M:N relacional (sincronizado desde recipe) ───────────
create table public.pizza_ingredients (
  pizza_id      uuid not null references public.pizzas(id) on delete cascade,
  ingredient_id text not null references public.ingredients(id) on delete restrict,
  qty           numeric(12,3) not null check (qty > 0),
  unit          ing_unit not null,
  position      int not null default 0,
  primary key (pizza_id, ingredient_id)
);
create index pizza_ingredients_ingredient_idx on public.pizza_ingredients (ingredient_id);

-- ─── orders: cabecera de pedido ──────────────────────────────────────────────
create table public.orders (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  shop_id         uuid not null references public.shops(id),
  address_id      uuid references public.addresses(id),
  status          order_status not null default 'draft',
  subtotal_cents  int not null default 0,
  delivery_cents  int not null default 0,
  discount_cents  int not null default 0,
  total_cents     int generated always as
                    (subtotal_cents + delivery_cents - discount_cents) stored,
  payment_method  payment_method,
  paid_at         timestamptz,
  placed_at       timestamptz,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index orders_user_id_idx     on public.orders (user_id, created_at desc);
create index orders_shop_status_idx on public.orders (shop_id, status);

-- ─── order_items: líneas del pedido (cada pizza pedida) ──────────────────────
create table public.order_items (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references public.orders(id) on delete cascade,
  pizza_id          uuid references public.pizzas(id) on delete set null,
  recipe_snapshot   jsonb not null,
  qty               int not null check (qty > 0),
  unit_price_cents  int not null check (unit_price_cents >= 0),
  line_total_cents  int generated always as (qty * unit_price_cents) stored
);
create index order_items_order_id_idx on public.order_items (order_id);
create index order_items_pizza_id_idx on public.order_items (pizza_id) where pizza_id is not null;

-- ─── order_item_ingredients: materializado para descuento de stock ───────────
create table public.order_item_ingredients (
  order_item_id  uuid not null references public.order_items(id) on delete cascade,
  ingredient_id  text not null references public.ingredients(id) on delete restrict,
  qty            numeric(12,3) not null check (qty > 0),
  unit           ing_unit not null,
  primary key (order_item_id, ingredient_id)
);
create index order_item_ingredients_ingredient_idx
  on public.order_item_ingredients (ingredient_id);

-- ─── order_status_events: timeline auditable ─────────────────────────────────
create table public.order_status_events (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders(id) on delete cascade,
  from_status  order_status,
  to_status    order_status not null,
  actor_id     uuid references public.profiles(id),
  note         text,
  created_at   timestamptz not null default now()
);
create index order_status_events_order_idx on public.order_status_events (order_id, created_at);

-- ─── stock_movements: ledger de stock por sucursal ───────────────────────────
create table public.stock_movements (
  id             uuid primary key default gen_random_uuid(),
  shop_id        uuid not null references public.shops(id),
  ingredient_id  text not null references public.ingredients(id) on delete restrict,
  delta          numeric(12,3) not null,
  reason         stock_reason not null,
  order_id       uuid references public.orders(id) on delete set null,
  actor_id       uuid references public.profiles(id),
  note           text,
  created_at     timestamptz not null default now()
);
create index stock_movements_shop_ing_idx
  on public.stock_movements (shop_id, ingredient_id, created_at desc);
create index stock_movements_order_idx
  on public.stock_movements (order_id) where order_id is not null;

-- ─── ingredient_stock_by_shop: vista agregada ────────────────────────────────
create view public.ingredient_stock_by_shop as
select
  shop_id,
  ingredient_id,
  sum(delta) as qty_on_hand
from public.stock_movements
group by shop_id, ingredient_id;

-- ─── deliveries: 1:1 con orders cuando aplica ───────────────────────────────
create table public.deliveries (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null unique references public.orders(id) on delete cascade,
  shop_id       uuid not null references public.shops(id),
  courier_id    uuid references public.profiles(id),
  status        delivery_status not null default 'pending',
  assigned_at   timestamptz,
  picked_up_at  timestamptz,
  delivered_at  timestamptz,
  route_seq     int
);
create index deliveries_courier_idx on public.deliveries (courier_id, status);
create index deliveries_shop_status_idx on public.deliveries (shop_id, status);

-- ─── delivery_locations: tracking GPS (alta frecuencia) ──────────────────────
create table public.delivery_locations (
  id           uuid primary key default gen_random_uuid(),
  delivery_id  uuid not null references public.deliveries(id) on delete cascade,
  position     geography(Point, 4326) not null,
  heading      numeric(5,2),
  speed        numeric(6,2),
  recorded_at  timestamptz not null default now()
);
create index delivery_locations_delivery_idx
  on public.delivery_locations (delivery_id, recorded_at desc);
create index delivery_locations_position_gix
  on public.delivery_locations using gist (position);

-- ─── Social ──────────────────────────────────────────────────────────────────
create table public.pizza_likes (
  user_id     uuid not null references auth.users(id) on delete cascade,
  pizza_id    uuid not null references public.pizzas(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, pizza_id)
);
create index pizza_likes_pizza_idx on public.pizza_likes (pizza_id);

-- ─── Gamificación ────────────────────────────────────────────────────────────
create table public.achievements (
  id           text primary key,
  name         text not null,
  description  text,
  points       int not null default 0,
  icon         text,
  active       boolean not null default true
);

create table public.user_achievements (
  user_id        uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null references public.achievements(id) on delete cascade,
  unlocked_at    timestamptz not null default now(),
  primary key (user_id, achievement_id)
);

create table public.points_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  delta       int not null,
  reason      text not null,
  ref_type    text,
  ref_id      uuid,
  created_at  timestamptz not null default now()
);
create index points_log_user_idx on public.points_log (user_id, created_at desc);

-- ─── RLS: habilitación ───────────────────────────────────────────────────────
alter table public.profiles                enable row level security;
alter table public.addresses               enable row level security;
alter table public.shops                   enable row level security;
alter table public.pizza_bases             enable row level security;
alter table public.ingredients             enable row level security;
alter table public.pizzas                  enable row level security;
alter table public.pizza_ingredients       enable row level security;
alter table public.orders                  enable row level security;
alter table public.order_items             enable row level security;
alter table public.order_item_ingredients  enable row level security;
alter table public.order_status_events     enable row level security;
alter table public.stock_movements         enable row level security;
alter table public.deliveries              enable row level security;
alter table public.delivery_locations      enable row level security;
alter table public.pizza_likes             enable row level security;
alter table public.achievements            enable row level security;
alter table public.user_achievements       enable row level security;
alter table public.points_log              enable row level security;

-- ─── RLS: profiles ───────────────────────────────────────────────────────────
create policy "profiles self read"
  on public.profiles for select using (auth.uid() = id);
create policy "profiles admin read"
  on public.profiles for select using (public.is_role('admin'));
create policy "profiles self update"
  on public.profiles for update using (auth.uid() = id);

-- ─── RLS: addresses ──────────────────────────────────────────────────────────
create policy "addresses owner all"
  on public.addresses for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─── RLS: shops ──────────────────────────────────────────────────────────────
create policy "shops public read active"
  on public.shops for select using (active);
create policy "shops admin write"
  on public.shops for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));

-- ─── RLS: pizza_bases ────────────────────────────────────────────────────────
create policy "pizza_bases public read active"
  on public.pizza_bases for select using (active);
create policy "pizza_bases admin write"
  on public.pizza_bases for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));

-- ─── RLS: ingredients ────────────────────────────────────────────────────────
create policy "ingredients public read active"
  on public.ingredients for select using (active);
create policy "ingredients admin write"
  on public.ingredients for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));

-- ─── RLS: pizzas ─────────────────────────────────────────────────────────────
-- Lectura pública: pizzas de la casa visibles + comunidad pública (no soft-deleted)
create policy "pizzas public read"
  on public.pizzas for select
  using (
    deleted_at is null
    and (
      (origin = 'house' and is_public)
      or (origin = 'user' and is_public)
    )
  );
-- Owner read all suyas (incluso privadas / soft-deleted)
create policy "pizzas owner read"
  on public.pizzas for select using (auth.uid() = user_id);
-- Owner manage propias (solo origin='user')
create policy "pizzas owner insert"
  on public.pizzas for insert
  with check (auth.uid() = user_id and origin = 'user');
create policy "pizzas owner update"
  on public.pizzas for update
  using (auth.uid() = user_id and origin = 'user')
  with check (auth.uid() = user_id and origin = 'user');
create policy "pizzas owner delete"
  on public.pizzas for delete
  using (auth.uid() = user_id and origin = 'user');
-- Admin gestiona todo (incluyendo origin='house')
create policy "pizzas admin all"
  on public.pizzas for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));

-- ─── RLS: pizza_ingredients ──────────────────────────────────────────────────
-- Lectura: cualquier pizza visible para el usuario
create policy "pizza_ingredients read via pizza"
  on public.pizza_ingredients for select
  using (
    exists (
      select 1 from public.pizzas p
      where p.id = pizza_id
        and (
          (p.deleted_at is null and p.is_public)
          or p.user_id = auth.uid()
          or public.is_role('admin')
        )
    )
  );
-- Escritura: owner de la pizza, o admin
create policy "pizza_ingredients owner write"
  on public.pizza_ingredients for all
  using (
    exists (select 1 from public.pizzas p where p.id = pizza_id and p.user_id = auth.uid())
    or public.is_role('admin')
  )
  with check (
    exists (select 1 from public.pizzas p where p.id = pizza_id and p.user_id = auth.uid())
    or public.is_role('admin')
  );

-- ─── RLS: orders ─────────────────────────────────────────────────────────────
create policy "orders owner all"
  on public.orders for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "orders pizzero read"
  on public.orders for select using (public.is_role('pizzero'));
create policy "orders admin all"
  on public.orders for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));
create policy "orders delivery read assigned"
  on public.orders for select
  using (
    public.is_role('delivery')
    and exists (
      select 1 from public.deliveries d
      where d.order_id = orders.id and d.courier_id = auth.uid()
    )
  );

-- ─── RLS: order_items ────────────────────────────────────────────────────────
create policy "order_items via order"
  on public.order_items for all
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (
          o.user_id = auth.uid()
          or public.is_role('admin')
          or public.is_role('pizzero')
          or (public.is_role('delivery') and exists (
                select 1 from public.deliveries d
                where d.order_id = o.id and d.courier_id = auth.uid()))
        )
    )
  )
  with check (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (o.user_id = auth.uid() or public.is_role('admin'))
    )
  );

-- ─── RLS: order_item_ingredients ─────────────────────────────────────────────
create policy "order_item_ingredients via order_item"
  on public.order_item_ingredients for select
  using (
    exists (
      select 1 from public.order_items oi
      join public.orders o on o.id = oi.order_id
      where oi.id = order_item_id
        and (
          o.user_id = auth.uid()
          or public.is_role('admin')
          or public.is_role('pizzero')
          or (public.is_role('delivery') and exists (
                select 1 from public.deliveries d
                where d.order_id = o.id and d.courier_id = auth.uid()))
        )
    )
  );
-- Insert/update solo desde triggers (security definer); admin puede manualmente
create policy "order_item_ingredients admin write"
  on public.order_item_ingredients for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));

-- ─── RLS: order_status_events ────────────────────────────────────────────────
create policy "order_status_events via order"
  on public.order_status_events for select
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (
          o.user_id = auth.uid()
          or public.is_role('admin')
          or public.is_role('pizzero')
          or (public.is_role('delivery') and exists (
                select 1 from public.deliveries d
                where d.order_id = o.id and d.courier_id = auth.uid()))
        )
    )
  );
-- Insert por trigger (security definer); admin puede manualmente
create policy "order_status_events admin write"
  on public.order_status_events for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));

-- ─── RLS: stock_movements ────────────────────────────────────────────────────
create policy "stock_movements pizzero read"
  on public.stock_movements for select using (public.is_role('pizzero'));
create policy "stock_movements admin all"
  on public.stock_movements for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));

-- ─── RLS: deliveries ─────────────────────────────────────────────────────────
create policy "deliveries owner read via order"
  on public.deliveries for select
  using (
    exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid())
  );
create policy "deliveries courier read assigned"
  on public.deliveries for select
  using (public.is_role('delivery') and courier_id = auth.uid());
create policy "deliveries pizzero read"
  on public.deliveries for select using (public.is_role('pizzero'));
create policy "deliveries admin all"
  on public.deliveries for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));
-- Courier acepta delivery (toma pedido ready)
create policy "deliveries courier update assigned"
  on public.deliveries for update
  using (public.is_role('delivery') and courier_id = auth.uid())
  with check (public.is_role('delivery') and courier_id = auth.uid());

-- ─── RLS: delivery_locations ─────────────────────────────────────────────────
create policy "delivery_locations owner read via order"
  on public.delivery_locations for select
  using (
    exists (
      select 1 from public.deliveries d
      join public.orders o on o.id = d.order_id
      where d.id = delivery_id and o.user_id = auth.uid()
    )
  );
create policy "delivery_locations courier insert"
  on public.delivery_locations for insert
  with check (
    exists (
      select 1 from public.deliveries d
      where d.id = delivery_id and d.courier_id = auth.uid()
    )
  );
create policy "delivery_locations admin all"
  on public.delivery_locations for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));

-- ─── RLS: pizza_likes ────────────────────────────────────────────────────────
create policy "pizza_likes public read"
  on public.pizza_likes for select using (true);
create policy "pizza_likes owner insert"
  on public.pizza_likes for insert with check (auth.uid() = user_id);
create policy "pizza_likes owner delete"
  on public.pizza_likes for delete using (auth.uid() = user_id);

-- ─── RLS: achievements ───────────────────────────────────────────────────────
create policy "achievements public read"
  on public.achievements for select using (active);
create policy "achievements admin write"
  on public.achievements for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));

-- ─── RLS: user_achievements ──────────────────────────────────────────────────
create policy "user_achievements self read"
  on public.user_achievements for select using (auth.uid() = user_id);
create policy "user_achievements public read"
  on public.user_achievements for select using (true);
create policy "user_achievements admin write"
  on public.user_achievements for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));

-- ─── RLS: points_log ─────────────────────────────────────────────────────────
create policy "points_log self read"
  on public.points_log for select using (auth.uid() = user_id);
create policy "points_log admin write"
  on public.points_log for all
  using (public.is_role('admin'))
  with check (public.is_role('admin'));

-- ─── Auto-creación de profile al registrar user ──────────────────────────────
create or replace function public.handle_new_user()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(
      split_part(new.email, '@', 1),
      'user_' || substr(new.id::text, 1, 8)
    )
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
