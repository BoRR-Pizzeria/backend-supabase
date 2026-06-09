# Modelo de ramas

3 ramas principales:

| Rama | Rol | Recibe merges de |
|---|---|---|
| `production` | Rama principal (default). Lo desplegado en prod. | `staging` |
| `staging` | Pre-producción / QA. Se promueve a `production`. | `develop` |
| `develop` | Integración de features. | `feat/*`, `fix/*` |

Flujo: `feat/* → develop → staging → production`.

Las ramas de trabajo (`feat/...`, `fix/...`) salen de `develop` y vuelven a `develop` por PR.
