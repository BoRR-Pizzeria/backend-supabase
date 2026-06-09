# Supabase — setup

Backend del proyecto BoRR. El modelo completo (tablas, enums, RLS, triggers, realtime) está en [`../doc/der.md`](../doc/der.md). Las decisiones de diseño en [`../doc/decisiones-de-diseno.md`](../doc/decisiones-de-diseno.md). La integración con Cloudflare Pages en [`../doc/integracion-supabase.md`](../doc/integracion-supabase.md).

## Project info

- Project ref: `rikafvgarvjhnbkauxzi`
- URL: `https://rikafvgarvjhnbkauxzi.supabase.co`
- MCP: configurado en `.mcp.json` — Claude Code se conecta vía MCP para gestionar el schema desde el IDE.

## Migrations

Las migrations viven en `supabase/migrations/` y son idempotentes-en-orden (greenfield):

| Archivo | Qué hace |
|---------|----------|
| `0001_init.sql` | Extensiones (`pgcrypto`, `postgis`), enums, todas las tablas, RLS, helper `is_role`, trigger `handle_new_user`. |
| `0002_triggers.sql` | Triggers de sincronización: `pizzas → pizza_ingredients`, `orders → order_status_events`, `placed→preparing → order_item_ingredients + stock_movements`, `touch_updated_at`. |
| `0003_realtime.sql` | Habilita Supabase Realtime para `orders`, `order_status_events`, `deliveries`, `delivery_locations`, `stock_movements`, `pizzas`. |
| `0004_security_fixes.sql` | Correcciones detectadas por advisors: view a `security invoker`, lock de `search_path`, revoke `EXECUTE` de funciones internas. |

### Aplicar con Supabase CLI

```bash
supabase db push   # aplica todas las migrations pendientes al cloud
```

Para resetear y volver a aplicar todo desde cero (incluye seed):

```bash
supabase db reset --linked
```

## Seed

`seed.sql` carga datos iniciales:
- 1 sucursal (`shops`)
- 3 bases (`pizza_bases`)
- 15 ingredientes (`ingredients`)
- 4 pizzas de la casa (`pizzas` con `origin='house'`)
- Stock inicial de cada ingrediente en la sucursal (5kg para gramos, 50 unidades para el resto)
- 4 achievements

## Variables de entorno

Copiar `.env.example` a `.env` en la raíz del repo. Los valores se obtienen desde **Project Settings → API**:
- `PUBLIC_SUPABASE_URL`: project URL.
- `PUBLIC_SUPABASE_ANON_KEY`: "anon public" (JWT) o la publishable key (`sb_publishable_...`).

> **Nunca** commitear el `.env` ni exponer la `service_role` key con prefijo `PUBLIC_`.

## Auth — confirmaciones de email

En **Authentication → Providers → Email**, durante desarrollo desactivar "Confirm email" para que `signUp` + `signIn` funcionen sin pasar por la bandeja.

## Verificación

Después de aplicar las migrations + seed, validar:

```sql
-- Como anon (sin sesión):
select count(*) from public.ingredients;          -- 15
select count(*) from public.pizzas where is_public; -- 4 (house)
select count(*) from public.shops;                -- 1

-- Vistas geo
select id, ST_AsText(location) from public.shops;

-- Stock por sucursal (vista materializada)
select * from public.ingredient_stock_by_shop;

-- Sin sesión, NO se ven pizzas privadas:
select count(*) from public.pizzas where origin='user' and is_public=false;  -- 0
```

## Realtime channels disponibles

Los clientes se suscriben con `supabase.channel('foo').on('postgres_changes', { event: '*', schema: 'public', table: 'orders', filter: '...' }, cb)`:

| Tabla | Para qué |
|-------|----------|
| `orders` | Estado de pedido del cliente / cola de pizzero / disponibles repartidor |
| `order_status_events` | Timeline visual del pedido |
| `deliveries`, `delivery_locations` | Tracking GPS del repartidor |
| `stock_movements` | Dashboard low-stock admin/pizzero |
| `pizzas` | Feed comunidad en vivo (cuando se publique una pizza nueva) |
