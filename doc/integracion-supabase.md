# Integración Supabase ↔ Web (Cloudflare Pages)

Análisis de opciones para conectar el frontend (Astro + React, deploy en Cloudflare Pages) con Supabase, optimizando para cache eficiente y costo de bandwidth.

## Opciones evaluadas

### A. `supabase-js` 100% en cliente

```
[Browser] ──supabase-js──▶ [Supabase REST/Realtime/Auth]
```

- **Cómo funciona**: el cliente JS importa `@supabase/supabase-js`, hace queries directas con la `anon key` (segura porque RLS protege filas).
- **Implementación**: ya está en el proyecto (`src/lib/supabase.ts`).
- **Pros**:
  - Mínimo código.
  - Realtime nativo (WebSockets).
  - Auth (login/signup/session) listo.
  - RLS centraliza la seguridad.
  - Compatible con `output: 'static'` de Astro (no requiere SSR).
- **Contras**:
  - Cada visita a la home dispara queries a Supabase (catálogo, house pizzas, etc.). **No hay edge cache**.
  - Latencia geográfica del usuario hasta Supabase.
  - Bandwidth pagado por cada cliente que carga la home.
  - El SEO de páginas con datos de DB no funciona bien (datos llegan post-hidratación).

### B. Astro endpoints como proxy con CF Cache API

```
[Browser] ──fetch /api/...──▶ [Astro endpoint en CF Worker] ──supabase-js (server)──▶ [Supabase]
                                          │
                                          └─ caches.default (CF edge cache)
```

- **Cómo funciona**: rutas en `src/pages/api/*.ts` corren como CF Workers; usan `caches.default` y `Cache-Control` headers para que CF cachee respuestas en el edge más cercano al usuario.
- **Requiere**: cambiar `output: 'static'` → `'hybrid'` (la mayoría queda estático; solo `/api/*` es SSR).
- **Pros**:
  - **Edge cache real**: la home se sirve sin tocar Supabase si el catálogo está cacheado.
  - Bandwidth Supabase reducido drásticamente (1 hit cada N visitas).
  - SSR de datos públicos para SEO si querés.
  - Mutaciones siguen yendo client-side con RLS — no se pierde seguridad.
- **Contras**:
  - Más código (endpoints + invalidación).
  - Realtime no se beneficia (sigue siendo WebSocket directo).
  - Cache invalidation: cuando el admin agrega una pizza nueva, hay que invalidar (purge) o esperar que expire.

### C. Static Generation (SSG) con re-build periódico

```
[npm run build] ──▶ astro fetch ──▶ Supabase
                          │
                          └─▶ HTML estático con datos embebidos
```

- **Cómo funciona**: en build time, Astro hace fetch a Supabase y embebe los datos en HTML. Periódicamente CI dispara rebuilds (cada N minutos / via webhook).
- **Pros**: cero costo runtime, performance máxima.
- **Contras**: catálogo desactualizado entre builds; community pizzas (que cambian seguido) no se actualizan.

### D. Hybrid (recomendado)

| Tipo de dato | Estrategia |
|--------------|-----------|
| Catálogo público (ingredients, pizza_bases, house pizzas) | Astro endpoint + CF cache `s-maxage=300` |
| Pizzas comunidad (cambian seguido) | Astro endpoint + CF cache `s-maxage=60, swr=600` |
| Auth (login/signup/session) | `supabase-js` cliente |
| Pizzas privadas del usuario | `supabase-js` cliente con sesión |
| Crear pizza / pedido (mutaciones) | `supabase-js` cliente con RLS |
| Estado de pedido en vivo | `supabase-js` Realtime cliente |

**Por qué este mix**:
- Catálogo: alto tráfico, baja frecuencia de cambio → cache vale oro.
- Auth/mutaciones: baja frecuencia, requiere sesión → cliente directo.
- Realtime: WebSocket, no se cachea de todas formas → cliente directo.

## Recomendación: D (hybrid)

Cuando hagamos deploy a Cloudflare Pages:
- Activar `output: 'hybrid'` en Astro.
- Endpoints en `/api/*` con `Cache-Control: public, s-maxage=300, stale-while-revalidate=3600`.
- Cliente sigue usando `supabase-js` para auth/private/realtime.

Mientras tanto, en dev, los endpoints siguen funcionando (sin cache real, pero con la misma interfaz).

## Implementación inicial

Primera iteración (la que hacemos ahora):
1. **Login funcional**: ya está; verificar `.env` y testear.
2. **Catálogo dinámico en home**: 
   - Crear endpoint `/api/pizzas/house` que lee `pizzas where origin='house' and is_public=true`.
   - Crear endpoint `/api/pizzas/community` que lee `pizzas where origin='user' and is_public=true`.
   - `HomeScreen.tsx` hace fetch a esos endpoints con SWR-style (cache local en cliente + revalidación).
3. **Guardar pizza**: ya existe en `PizzaEditor.tsx`. Ajustar el insert para incluir `origin: 'user'` (constraint del nuevo schema) y `base_id`.

Iteraciones siguientes:
- Edge cache real cuando se haga deploy a Cloudflare.
- Endpoint `/api/ingredients` (para reemplazar fallback hardcoded).
- ISR / webhook de invalidación cuando admin actualice catálogo.

## Variables de entorno

```
PUBLIC_SUPABASE_URL=https://rikafvgarvjhnbkauxzi.supabase.co
PUBLIC_SUPABASE_ANON_KEY=<anon key — pedir al admin>
```

> **Nota**: el `PUBLIC_` prefix expone la variable al cliente (Astro). La `anon key` está diseñada para eso; las RLS protegen los datos. **Nunca** exponer `service_role` con prefijo público.
