# backend-supabase — Backend Supabase de BoRR

Backend de datos del ecosistema **BoRR** (pizzería digital). Contiene el schema completo de Postgres/Supabase: migraciones, seed, RLS, triggers y realtime. La arquitectura general de la organización está en [.github/docs](https://github.com/BoRR-Pizzeria/.github/blob/main/docs/README.md).

Forma parte del split en 3 repos (ex FFBORR / BFFBORR / BSBORR):

- **[front-clientes-web](https://github.com/BoRR-Pizzeria/front-clientes-web)** — front (Astro + React islands).
- **[bff-clientes](https://github.com/BoRR-Pizzeria/bff-clientes)** — backend-for-frontend / gateway en Cloudflare Workers (toda la app pasa por acá, maneja cache y reenvía el JWT del usuario a Supabase).
- **backend-supabase** — este repo: el backend Supabase.

> El cliente **nunca** habla directo con este backend: pasa por el BFF (bff-clientes), que reenvía el JWT del usuario para que **RLS** siga aplicando por usuario.

## Proyecto Supabase

- **Dev**: stack local del CLI (`supabase start`), expuesto en la malla ZeroTier como `Supa = 10.144.0.1`.
- **Prod**: proyecto cloud — ref `rikafvgarvjhnbkauxzi`, URL `https://rikafvgarvjhnbkauxzi.supabase.co`.

### Dev local sobre ZeroTier (nodo 10.144.0.1)

El stack local lo configura [`supabase/config.toml`](./supabase/config.toml) (API en `:54321`,
confirmación de email off para dev). El **BFF (bff-clientes)** apunta a `http://10.144.0.1:54321`.

```bash
supabase start            # levanta el stack local (Docker)
supabase db reset         # aplica TODAS las migraciones + seed al stack local
supabase status           # muestra API URL y la anon key (ponela en el .env del BFF)
```

**Exponer sobre ZeroTier**: el CLI mapea los puertos del lado del host. Probá desde otro nodo:

```bash
curl http://10.144.0.1:54321/rest/v1/   # debería responder (401/200), no timeout
```

Si da timeout (el CLI quedó atado a `127.0.0.1`), reenviá el puerto en el nodo .1, por ejemplo:

```bash
socat TCP-LISTEN:54321,fork,reuseaddr,bind=10.144.0.1 TCP:127.0.0.1:54321
```

> La anon key local default del CLI ya está pre-cargada en `bff-clientes/.env.example`. Si tu
> `supabase status` muestra otra (JWT secret distinto), reemplazala en el `.env`/`.dev.vars` del BFF.

### Prod (cloud)

```bash
supabase link --project-ref rikafvgarvjhnbkauxzi
supabase db push           # aplica migraciones pendientes al cloud
supabase db reset --linked # resetea y reaplica todo + seed (¡destructivo!)
```

## Estructura

```
supabase/
  migrations/   ← 0001..0007 (init, triggers, realtime, security fixes, vistas de feed y RPC de pedido)
  seed.sql      ← datos iniciales (sucursal, bases, ingredientes, pizzas de la casa, stock, achievements)
  README.md     ← setup paso a paso del backend
docs/
  der.md                     ← modelo entidad-relación (tablas, enums, triggers)
  decisiones-modelo-datos.md ← razonamiento detrás de cada decisión del modelo
  ejemplos/pedido-mixto.md   ← ejemplo concreto de pedido mixto
.claude/skills/              ← skills del dominio (supabase, supabase-postgres-best-practices)
```

Ver [`supabase/README.md`](./supabase/README.md) para el detalle de migraciones, seed, env y verificación.

## Documentación

- [`docs/`](./docs/README.md) — modelo de datos y decisiones de este repo.
- [Docs de la organización](https://github.com/BoRR-Pizzeria/.github/blob/main/docs/README.md) — arquitectura, dominios, flujos y ADRs transversales.

## Variables de entorno

Copiar `.env.example` a `.env`. Los valores salen de **Project Settings → API**. Nunca commitear `.env` ni exponer la `service_role` key.
