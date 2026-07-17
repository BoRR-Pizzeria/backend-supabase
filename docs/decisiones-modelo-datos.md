# Decisiones del modelo de datos

Razonamiento detrás de cada decisión clave del modelo de datos. El DER vive en [`der.md`](./der.md); este documento explica el porqué.

## 1. Un solo `pizzas` con `origin` + `is_public` independiente

**Decisión**: Una única tabla `pizzas` con columna `origin` (`pizza_origin` enum: `'house'` | `'user'`) y `is_public bool` desacoplado.

**Por qué**:
- **Mismas relaciones para todos**: `order_items.pizza_id`, `pizza_likes.pizza_id`, `pizza_ingredients.pizza_id` apuntan a la misma tabla. Sin polimorfismo, sin uniones por origen.
- **Visibilidad desacoplada**: el admin puede sacar una pizza de la casa de circulación (`is_public=false`) sin perder el historial de pedidos que la contienen. Lo mismo aplica a la comunidad.
- **Reglas claras** según combinación:
  | `origin` | `is_public` | `user_id` | Significado |
  |----------|-------------|-----------|-------------|
  | `house`  | `true`      | `null`    | Catálogo activo de la casa, visible a todos |
  | `house`  | `false`     | `null`    | Pizza de la casa **fuera de circulación** (admin la ocultó) |
  | `user`   | `true`      | `<uid>`   | Pizza pública de la comunidad |
  | `user`   | `false`     | `<uid>`   | Pizza privada del usuario (single-use para sus pedidos) |

**Constraint**: `check ((origin='house' and user_id is null) or (origin='user' and user_id is not null))`.

## 2. Pizza no publicada de usuario persiste en `pizzas`

**Decisión**: Cuando un usuario crea una pizza para un pedido sin publicarla, se guarda igualmente en `pizzas` con `origin='user'`, `is_public=false`.

**Por qué**:
- **Historial privado del creador**: el usuario puede consultar pizzas anteriores y reordenarlas.
- **Estructura uniforme** en `order_items` (siempre apunta a una `pizza_id` viva o nula).
- **Si el usuario la borra**, el `recipe_snapshot` en `order_items` mantiene el detalle del pedido (FK con `on delete set null`).

## 3. Stock con ledger (`stock_movements`)

**Decisión**: No hay columna `stock_qty` en `ingredients`. El stock se deriva de `stock_movements` (delta + reason + shop) y se agrega vía vista.

**Por qué**:
- **Auditoría histórica**: cada movimiento (compra, venta, ajuste, desperdicio, devolución, transferencia entre sucursales) queda registrado con su razón y actor.
- **Reportes y reconciliación**: análisis de costos, waste tracking, comparativa esperado vs. real.
- **Concurrencia**: insertar es siempre seguro (sin UPDATE de un mismo registro contendido).
- **Multi-sucursal natural**: `stock_movements.shop_id` permite agregar `qty_on_hand` por sucursal con un `group by`.

**Trade-off**: leer el stock actual cuesta un `sum()`. Mitigado con vista materializada o con un índice `(shop_id, ingredient_id)`. Si la cardinalidad crece, el ledger se puede archivar y mantener un snapshot mensual.

## 4. Receta congelada en `order_items` (snapshot JSONB)

**Decisión**: Cada `order_item` guarda `recipe_snapshot jsonb` con la receta + precios al momento del pedido.

**Por qué**:
- **Estándar e-commerce**: si el creador edita la pizza después, el pedido pasado queda como fue.
- **Resistencia a borrado**: si la pizza se borra (`pizza_id` se setea a null por `on delete set null`), el snapshot mantiene el detalle.
- **Simplicidad**: alternativa de "versionado de pizzas" (`pizza_versions`) sería más complejo sin beneficio claro a corto plazo.

**Trade-off**: duplicación de datos. Aceptable porque el snapshot es pequeño y los pedidos no son volátiles.

## 5. PostGIS para geolocalización

**Decisión**: Tipo `geography(Point, 4326)` para `addresses.location`, `delivery_locations.position`, `shops.location`.

**Por qué**:
- **Cálculo de distancias** nativo (`ST_Distance`, `ST_DWithin`).
- **Soporte directo en Supabase** (extensión disponible, expuesta vía PostgREST).
- **Validación de cobertura**: en futuro, polígonos `delivery_zones` por sucursal con `ST_Covers`.
- **Performance**: index GIST hace queries de proximidad O(log n).

Alternativa rechazada: `lat numeric` + `lng numeric`. Simple pero obliga a cálculos en cliente o app y no soporta queries geoespaciales.

## 6. Estados como `enum` Postgres

**Decisión**: Tipos enum nativos para `order_status`, `delivery_status`, `payment_method`, `pizza_origin`, `pizza_size`, `ing_category`, `ing_unit`, `stock_reason`, `user_role`.

**Por qué**:
- **Type safety end-to-end**: `mcp__supabase__generate_typescript_types` los expone como union types literales (`'placed' | 'preparing' | ...`). No más typos en el código.
- **Validación a nivel de tipo** sin necesidad de `check (status in (...))`.
- **Menor footprint** que `text` (4 bytes vs. tamaño variable).

**Trade-off**: agregar valores requiere `alter type ... add value` (no se puede en transacción). Mitigado porque los estados cambian raramente; cuando cambien, se documenta en una migration aparte.

## 7. Multi-sucursal desde el inicio (`shops`)

**Decisión**: Tabla `shops` con `shop_id` en `orders`, `stock_movements`, `deliveries`.

**Por qué**:
- **Migración dolorosa después**: agregar `shop_id` a tablas con datos requiere backfill, breaking changes en RLS, ajustes en queries.
- **Costo bajo ahora**: con una sola fila en `shops`, todos los registros apuntan al mismo `shop_id`.
- **Stock es por sucursal por naturaleza**: cada local tiene su inventario.

## 8. `pizza_ingredients` (M:N) además del `recipe` JSONB

**Decisión**: Mantener `pizza.recipe jsonb` (para edición UI con divisores `'stage'`, orden, posiciones) **y** una tabla relacional `pizza_ingredients (pizza_id, ingredient_id, qty, unit, position)`.

**Por qué**:
- **Queries relacionales** que el JSONB no resuelve bien:
  - "¿Cuánta mozzarella tienen las pizzas activas?"
  - Reportes de uso de ingredientes.
  - Drivers para `order_item_ingredients` al pasar a `preparing`.
- **Sincronización via trigger** desde `recipe.items` al insert/update de `pizzas` — el JSONB sigue siendo la fuente para la UI, pero la tabla relacional siempre está al día.

Alternativa rechazada: solo JSONB. Bueno para edición, malo para reporting.

## 9. Documentación del modelo junto al esquema

**Decisión**: El DER, estas decisiones y los ejemplos viven en `docs/` de `backend-supabase`, junto a las migraciones que documentan.

**Por qué**: es la regla de división de la organización (ver [`convenciones.md`](https://github.com/BoRR-Pizzeria/.github/blob/main/docs/convenciones.md)): lo que describe el código de un repo vive en ese repo; lo transversal (arquitectura, ADRs, flujos de negocio) vive en `.github/docs/`.
