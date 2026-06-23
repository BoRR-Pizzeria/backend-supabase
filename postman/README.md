# Postman — BSBORR (Supabase API)

Colección con **todos los endpoints expuestos por el backend Supabase de BoRR**, derivada del schema en [`../supabase/migrations`](../supabase/migrations).

## Archivos

| Archivo | Qué es |
|---|---|
| `BSBORR.postman_collection.json` | La colección (Auth + REST/PostgREST + RPC). |
| `BSBORR.prod.postman_environment.json` | Environment del proyecto cloud (`rikafvgarvjhnbkauxzi`). |
| `BSBORR.local.postman_environment.json` | Environment del stack local del CLI sobre ZeroTier (`10.144.0.1:54321`). |

## Setup

1. **Importar** en Postman la colección + un environment.
2. Cargar `apikey` en el environment elegido — **usar la anon key JWT** (`eyJ...`), NO la publishable (`sb_publishable_...`):
   - **prod**: Project Settings → API → `anon public` (legacy JWT).
   - **local**: salida de `supabase status -o env` (campo `ANON_KEY`). Ya viene cargada en `BSBORR.local`.
   - **Por qué JWT y no publishable**: la colección usa la `apikey` también como `Bearer` de fallback para el acceso anónimo, y PostgREST/GoTrue sólo aceptan un JWT en `Authorization`. La publishable key da `401`.
3. Activar el environment y ejecutar **`01 · Auth → Login (password)`** (o **`Signup`**). El test script guarda `accessToken`, `refreshToken` y `userId` en variables de **colección**; el resto de los requests autentican solos vía un pre-request a nivel colección que inyecta `apikey` + `Authorization: Bearer` (precedencia: **environment > colección**).

> Si todavía no hiciste login, los requests usan la `anon key` como bearer (acceso anónimo) — sirve para las lecturas públicas de la carpeta `02 · Catálogo`.

### Correr con newman (CLI)

```bash
npx newman run BSBORR.postman_collection.json \
  -e BSBORR.local.postman_environment.json \
  --env-var "supabaseUrl=http://127.0.0.1:54321"   # si tu stack local no está en la IP del env
```

## Estructura

- **01 · Auth (GoTrue)** `/auth/v1` — signup, **signup anónimo**, login, refresh, user, recover, logout.
- **02 · Catálogo público** — shops, pizza_bases, ingredients, pizzas (house/comunidad), las **vistas feed `pizzas_house_feed` / `pizzas_community_feed`** (★ usadas por el front, con `price_cents` del back) y `profiles_public`.
- **03–07** — perfil, direcciones, pizzas del usuario, likes, pedidos. El pedido real se crea con el **RPC `place_order`** (★, atómico); el flujo manual draft → order_items → placed queda para back-office.
- **08 · Delivery** — deliveries + tracking GPS (`delivery_locations`).
- **09 · Stock** — `stock_movements` + vista `ingredient_stock_by_shop` (rol pizzero/admin).
- **10 · Gamificación** — achievements, user_achievements, points_log.
- **11 · Admin** — escrituras de catálogo (rol admin).
- **12 · RPC** — `current_app_role`, `is_role` (las funciones trigger-only **no** están: tienen `EXECUTE` revocado en [`0004_security_fixes.sql`](../supabase/migrations/0004_security_fixes.sql)).

## Notas

- **RLS aplica siempre.** Un usuario `customer` recién registrado obtiene 0 filas (o error de policy) en las carpetas de Stock/Admin: filtra la policy, no la URL. Para probarlas, cambiá el `role` del profile a `admin`/`pizzero`/`delivery` desde el Studio/SQL.
- **Geografía**: los campos `geography(Point,4326)` (`addresses.location`, `shops.location`, `delivery_locations.position`) se mandan como EWKT — `SRID=4326;POINT(lon lat)` — o GeoJSON.
- **Columnas generadas** (`orders.total_cents`, `order_items.line_total_cents`): no enviarlas en el body.
- **Realtime** no es REST: las tablas `orders`, `order_status_events`, `deliveries`, `delivery_locations`, `stock_movements`, `pizzas` están en la publicación `supabase_realtime` y se consumen por WebSocket con `supabase-js`, no desde Postman.
- No commitear keys reales: los `apikey`/`password` quedan como placeholders.
