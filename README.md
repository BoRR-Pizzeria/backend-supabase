# BSBORR — Backend Supabase BoRR

Backend de datos del ecosistema **BoRR** (pizzería digital). Contiene el schema completo de Postgres/Supabase: migraciones, seed, RLS, triggers y realtime.

Forma parte del split en 3 repos:

- **FFBORR** — front (Astro + React islands).
- **BFFBORR** — backend-for-frontend / gateway en Cloudflare Pages + Workers (toda la app pasa por acá, maneja cache y reenvía el JWT del usuario a Supabase).
- **BSBORR** — este repo: el backend Supabase.

> El cliente **nunca** habla directo con este backend en el nuevo stack: pasa por el BFF (BFFBORR), que reenvía el JWT del usuario para que **RLS** siga aplicando por usuario.

## Proyecto Supabase

- Project ref: `rikafvgarvjhnbkauxzi`
- URL: `https://rikafvgarvjhnbkauxzi.supabase.co`

El proyecto se gestiona **remoto** (cloud), no hay `supabase start` local. Para operar con la CLI:

```bash
supabase link --project-ref rikafvgarvjhnbkauxzi
supabase db push          # aplica migraciones pendientes al cloud
supabase db reset --linked # resetea y reaplica todo + seed (¡destructivo!)
```

## Estructura

```
supabase/
  migrations/   ← 0001..0005 (init, triggers, realtime, security fixes, profiles_public view)
  seed.sql      ← datos iniciales (sucursal, bases, ingredientes, pizzas de la casa, stock, achievements)
  README.md     ← setup paso a paso del backend
doc/
  der.md                 ← modelo entidad-relación (tablas, enums, triggers)
  decisiones-de-diseno.md
  integracion-supabase.md
  ejemplos/pedido-mixto.md
```

Ver [`supabase/README.md`](./supabase/README.md) para el detalle de migraciones, seed, env y verificación.

## Variables de entorno

Copiar `.env.example` a `.env`. Los valores salen de **Project Settings → API**. Nunca commitear `.env` ni exponer la `service_role` key.
