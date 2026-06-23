# Estado de endpoints — BSBORR

Qué endpoints del backend Supabase están **implementados** (consumidos hoy por el front
vía el BFF) y cuáles quedan **por finalizar** (existen en el schema + colección Postman,
pero todavía sin UI que los use).

- **Fuente**: `supabase/migrations/0001..0007` + `postman/BSBORR.postman_collection.json`.
- **Camino real**: el browser nunca habla directo con Supabase. Va
  `Front → BFF (/api/*) → Supabase (REST/RPC/GoTrue)`. La columna "BFF" indica el endpoint
  del gateway que lo expone.
- Probado de punta a punta contra el stack local del CLI (`supabase start`) con newman; ver
  `postman/README.md`.

## ✅ Implementados (consumidos por el front)

| Dominio | Supabase (objeto) | BFF | Front |
|---|---|---|---|
| Auth · signup | `POST /auth/v1/signup` | `POST /api/auth/signup` | `lib/auth.ts › signUp` |
| Auth · login | `POST /auth/v1/token?grant_type=password` | `POST /api/auth/login` | `lib/auth.ts › signIn` |
| Auth · refresh | `POST /auth/v1/token?grant_type=refresh_token` | `POST /api/auth/refresh` | `lib/auth.ts › refreshSession` |
| Auth · whoami | `GET /auth/v1/user` | `GET /api/auth/session` | `lib/auth.ts › initSession` |
| Auth · logout | `POST /auth/v1/logout` | `POST /api/auth/logout` | `lib/auth.ts › signOut` |
| Auth · anónimo | `POST /auth/v1/signup` (body vacío) | `POST /api/auth/anon` | `lib/auth.ts › signInAnonymously` (pedido sin login) |
| Catálogo · ingredientes | `GET /rest/v1/ingredients` | `GET /api/ingredients` | `lib/api.ts › fetchIngredients` |
| Feed · de la casa | `GET /rest/v1/pizzas_house_feed` (vista 0006) | `GET /api/pizzas/house` | `lib/api.ts › fetchHousePizzas` |
| Feed · comunidad | `GET /rest/v1/pizzas_community_feed` (vista 0006) | `GET /api/pizzas/community` | `lib/api.ts › fetchCommunityPizzas` |
| Sucursales | `GET /rest/v1/shops?active=eq.true` | `GET /api/shops` | `lib/services/shops.ts` (resuelve `shop_id` del pedido) |
| Pizzas · mías | `GET /rest/v1/pizzas?user_id=eq.<sub>` | `GET /api/pizzas/mine` | `lib/services/pizzas.ts › listMine` |
| Pizzas · por id | `GET /rest/v1/pizzas?id=eq.<id>` | `GET /api/pizzas/:id` | `lib/services/pizzas.ts › getById` |
| Pizzas · crear | `POST /rest/v1/pizzas` | `POST /api/pizzas` | `lib/services/pizzas.ts › create` |
| Pizzas · publicar/editar | `PATCH /rest/v1/pizzas?id=eq.<id>` | `PATCH /api/pizzas/:id` | `lib/services/pizzas.ts › setPublic/updateMeta` |
| Pedido · crear | `POST /rest/v1/rpc/place_order` (RPC 0006) | `POST /api/orders` | `lib/services/orders.ts › placeOrder` |

> `profiles_public` no es un endpoint del front: lo usa internamente la vista
> `pizzas_community_feed` para resolver el `author_username`.

## 🚧 Por finalizar (en schema + Postman, sin UI todavía)

| Dominio | Supabase | Notas |
|---|---|---|
| Perfil | `GET/PATCH /rest/v1/profiles` | Falta pantalla de perfil/ajustes. |
| Direcciones | CRUD `/rest/v1/addresses` (PostGIS) | El pedido hoy va con `address_id=null`; falta selector de dirección. |
| Social · likes | `/rest/v1/pizza_likes` | La UI muestra pizzas pero no hay wiring de like aún. |
| Pedido · flujo manual | `orders` draft → `order_items` → `placed` → timeline | Camino granular de back-office; el front usa el RPC `place_order`. |
| Pedido · estado en vivo | Realtime: `orders`, `order_status_events` | Por WebSocket (no REST); falta tracking de pedido en el front. |
| Delivery | `deliveries`, `delivery_locations` | App del repartidor (rol `delivery`); requiere delivery asignado. |
| Stock | `stock_movements`, `ingredient_stock_by_shop` | Dashboard pizzero/admin. Escritura sólo admin. |
| Gamificación | `achievements`, `user_achievements`, `points_log` | Sin UI de logros/puntos. |
| Admin · catálogo | escrituras en `shops/pizza_bases/ingredients/...` | Panel admin (rol `admin`). |
| RPC interno | `current_app_role`, `is_role` | Los evalúan las RLS; el front no los llama directo. |

## Notas de prueba

- **anon key**: usar la **JWT** (`eyJ...`), no la publishable (`sb_publishable_...`): la
  colección la usa también como Bearer de fallback y sólo el JWT funciona ahí.
- **Roles**: con un usuario `customer` recién creado, Stock/Admin devuelven 403 y Delivery
  necesita un `deliveryId` asignado. Es la RLS filtrando, no un error.
- **Pedido anónimo**: requiere `enable_anonymous_sign_ins=true` (en `config.toml` local; en
  cloud, Auth → Providers → Anonymous).
