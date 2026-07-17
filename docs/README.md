# Documentación de backend-supabase

Documentación del modelo de datos de este repo. Lo transversal (arquitectura, dominios, flujos de negocio, ADRs) vive en [.github/docs](https://github.com/BoRR-Pizzeria/.github/blob/main/docs/README.md).

## Índice

- [`der.md`](./der.md) — Modelo entidad-relación: diagrama, enums, tablas, RLS y triggers.
- [`decisiones-modelo-datos.md`](./decisiones-modelo-datos.md) — Razonamiento detrás de cada decisión del modelo (origen de pizzas, ledger de stock, snapshots, multi-sucursal, PostGIS, enums).
- [`ejemplos/pedido-mixto.md`](./ejemplos/pedido-mixto.md) — Ejemplo concreto de un pedido con pizza de la casa, de la comunidad y privada.

El setup paso a paso (migraciones, seed, env) está en [`../supabase/README.md`](../supabase/README.md).
