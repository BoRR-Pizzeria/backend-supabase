# backend-supabase

Backend de datos de BoRR: esquema Postgres/Supabase (migraciones, seed, RLS, triggers, realtime, RPCs). Los clientes llegan siempre a través de un BFF; la RLS es la autoridad de permisos y la lógica de dominio vive en RPCs.

## Documentación

- Lo que describe **este repo** (modelo de datos, decisiones del esquema, ejemplos) va en [`docs/`](./docs/README.md); actualizá su índice en el mismo commit.
- Lo **transversal** (arquitectura, dominios, flujos, ADRs, convenciones) va en [.github/docs](https://github.com/BoRR-Pizzeria/.github/blob/main/docs/README.md). Regla completa en [`convenciones.md`](https://github.com/BoRR-Pizzeria/.github/blob/main/docs/convenciones.md).
- Toda migración que cambie el modelo debe reflejarse en `docs/der.md` (y en `docs/decisiones-modelo-datos.md` si hay una decisión detrás).

## Skills y MCP

- Skills del dominio en [`.claude/skills/`](./.claude/skills/) (`supabase`, `supabase-postgres-best-practices`) — trackeadas en git y detectadas automáticamente por Claude Code. Solo `.claude/settings.local.json` queda fuera de git.
- MCP en [`.mcp.json`](./.mcp.json): servidor `supabase` del proyecto.

## Convenciones

- Commits: Conventional Commits con cuerpo en español, sin trailers de atribución.
- Ramas: `feature/* → develop → staging → production`, siempre vía PR.
