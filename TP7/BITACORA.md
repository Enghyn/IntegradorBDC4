# BITÁCORA DE USO DE IA — TP Unidad 5 (Food Store)

> **Formato obligatorio del TP:** tabla de tres columnas con *prompt enviado*,
> *respuesta relevante recibida* (resumida) y *validación o corrección humana aplicada*.
> Cada fila registra una interacción real con el asistente (OpenCode).

- **Asignatura:** Base de Datos II — Unidad 5 (Administración y seguridad).
- **Trabajo:** en equipo. Integrantes: `[completar con los nombres del equipo]`.
- **Herramientas:** OpenCode (asistente de terminal) y Git. Las especificaciones siguen el
  formato de Kiro (`requirements` / `design`).
- **Entorno de validación:** clúster PostgreSQL 17.11 local con la base `foodstore_test`
  recreada desde `food_store/schema.sql`. **Nunca** producción.

---

## 1. Registro

| Parte | Prompt enviado a la IA | Respuesta relevante recibida (resumida) | Validación o corrección humana aplicada |
|---|---|---|---|
| **0 — Reconstrucción** | "No conservamos los artefactos de la Clase 1 y 2 (`roles.sql`, `fn_autenticar`, `fn_resetear_password`, tabla `usuario`). Revisá qué falta en el repo y proponé cómo reconstruirlo como paso previo a la Parte A." | Relevó el esquema existente (`cliente`, `categoria`, `producto`, `pedido`, `detalle_pedido`) y confirmó que no existe ningún artefacto de identidades. Propuso un script aditivo con `rol`, `usuario`, `login_intento`, `usuario_auditoria`, `pgcrypto` y dos funciones `SECURITY DEFINER`. | **Aceptado con cambios.** El equipo exigió: (a) que `usuario` contenga PII real (email, nombre, apellido, teléfono, `fecha_alta`) para que la Parte D tenga sentido; (b) que la contraseña se guarde sólo como hash bcrypt; (c) que el script no toque `food_store/schema.sql`; (d) que sea idempotente y con guarda de entorno. |
| **0 — Reconstrucción** | "¿Cómo evito que `fn_autenticar` permita enumerar usuarios y que los roles de aplicación lean el hash?" | Propuso devolver siempre `false` con el mismo motivo ante usuario inexistente, inactivo o contraseña incorrecta, y resolver el acceso al hash con `SECURITY DEFINER` + `search_path` fijo + `REVOKE EXECUTE FROM PUBLIC`. | **Aceptado.** Se agregó además el `CHECK` de formato bcrypt sobre `password_hash`, que la IA no había propuesto: se detectó que sin él un `INSERT` manual podía dejar texto plano en la base. |
| **A — Especificación Kiro** | "Redactá `requirements.md` y `design.md` para el esquema de roles de Food Store, con una justificación de una oración por rol y trazabilidad a las consignas del TP." | Generó 10 requisitos con criterios de aceptación en formato WHEN/THEN, la matriz de roles, la política de privilegios por defecto y la tabla de riesgos. | **Aceptado con ajustes.** El equipo agregó la decisión de que `admin_datos` **no** sea propietario de las tablas y **no** herede `rol_auditoria` (separación de funciones); la IA no lo había planteado y sin eso el resto del esquema quedaba decorativo. |
| **A — `roles.sql`** | "Escribí `roles.sql` con CREATE ROLE, GRANT y REVOKE para los roles definidos, incluyendo un permiso a nivel de columna y `ALTER DEFAULT PRIVILEGES`." | Propuso la estructura general correcta, pero **otorgó privilegios más amplios de lo necesario**: `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO rol_app_lectura, rol_app_escritura` y `ALTER DEFAULT PRIVILEGES ... GRANT SELECT ON TABLES TO rol_app_lectura`. | **Rechazado en esa forma.** Ver caso destacado en la sección 2. Se reemplazó por `REVOKE ALL` inicial + `GRANT` explícitos, lectura **por columna** en `cliente` y `usuario`, `UPDATE (stock)` acotado y política de defaults "nada por defecto". |
| **A — `roles.sql`** | "¿Está bien que `admin_datos` sea dueño de las tablas para que pueda hacer DDL?" | Respondió que sí, que asignar ownership simplifica la administración. | **Rechazado.** En PostgreSQL el dueño tiene **todos** los privilegios implícitos: si `admin_datos` fuera dueño de `usuario`, podría leer `password_hash` aunque no tuviera `GRANT`, y el mínimo privilegio quedaría anulado. Se decidió que el DDL lo ejecute el DBA (`postgres`) y que `admin_datos` reciba sólo privilegios explícitos. |
| **A — Verificación** | "Armá la consulta que demuestre que cada rol tiene exactamente los privilegios de la spec, ni más ni menos." | Propuso consultar `information_schema.role_table_grants` y comparar a ojo con la spec. | **Corregido.** Comparar a ojo no demuestra nada: se implementó un **diff automático** (esperado vs real con `FULL OUTER JOIN`) que marca `FALTANTE`/`SOBRANTE`, se agregó `role_column_grants` (los permisos por columna **no** aparecen en `role_table_grants`) y una batería de pruebas negativas con `has_column_privilege` / `pg_has_role`. |
| **0 + A — Ejecución real** | "Ejecutá los scripts en una instancia limpia (base creada desde `schema.sql` + vistas + materializada) y decime si el diff da 0/0/0/0." | La primera corrida devolvió `faltantes_tabla = 20` y `faltantes_columna = 15`: los scripts **no** producían el estado que la propia spec declaraba. | **Aceptado como prueba de que valía la pena ejecutar.** Se detectaron tres errores reales (sección 2.1) que la revisión "a ojo" del SQL no había visto. Tras corregirlos: `0/0/0/0 → APROBADO`, `EXIT=0`, sin `WARNING`, e idempotente en una segunda corrida. |
| **A — Pruebas funcionales** | "Probá con `SET ROLE` los casos que deben fallar: leer `usuario`, otorgar `admin_datos`, `DELETE`, `UPDATE precio_lista`." | Los 10 casos se comportaron como se esperaba; `fn_autenticar` devolvió `(t, 7, rol_soporte)` con la clave correcta y `(f, NULL, NULL)` con clave incorrecta e inexistente. | **Aceptado.** Se verificó además que `fn_resetear_password` deja la fila en `usuario_auditoria` con `{costo_bcrypt: 12}` y que `app_web` recibe `permission denied to grant role "admin_datos"`. |
| **B — Auditoría** | *(pendiente de ejecución)* | — | — |
| **C — Simulacro** | *(pendiente de ejecución)* | — | — |
| **D — Anonimización** | *(pendiente de ejecución)* | — | — |
| **E — Cierre** | *(pendiente de consolidación)* | — | — |

---

## 2. Caso más significativo de error de la IA (obligatorio)

**Error detectado:** la IA propuso `GRANT ALL` / `ALTER DEFAULT PRIVILEGES ... GRANT SELECT
ON TABLES TO rol_app_lectura` como atajo para "que las tablas futuras hereden la política".

**Cómo se detectó:** al contrastar la propuesta con la consigna, el equipo notó dos
problemas concretos y verificables:

1. Un `GRANT ALL` sobre `usuario` incluye `SELECT` sobre `password_hash` y `DELETE` sobre
   la traza de auditoría: exactamente lo que la Parte C intenta explotar.
2. La política por defecto con `GRANT SELECT` haría que **toda tabla futura** quedara
   legible por el rol de la aplicación sin revisión, incluida una eventual tabla de tokens
   o de datos sensibles. La política correcta es la inversa: nada por defecto y `GRANT`
   explícito (a nivel de columna cuando hay PII) al crear cada objeto.

**Corrección aplicada:** `REVOKE ALL` inicial sobre los roles de aplicación + `GRANT`
puntuales; `ALTER DEFAULT PRIVILEGES` limitado a `REVOKE ... FROM PUBLIC` y `USAGE` sobre
secuencias (que no son datos sensibles). El `GRANT ALL` habría pasado las pruebas
positivas, pero el diff de verificación lo marca como `SOBRANTE`.

**Por qué importa para la evaluación:** es un caso donde la IA no se equivocó en la
sintaxis sino en el **criterio de seguridad**, y donde el equipo pudo demostrar el error
con una consulta, no con una opinión.

---

## 2.1 Errores detectados sólo al ejecutar (segunda revisión)

Los tres errores siguientes **no se ven leyendo el SQL**: aparecieron al correr los
scripts sobre una instancia limpia y comparar el resultado con lo esperado. Se registran
porque son la evidencia de que la validación humana fue real y no una firma al pie.

| # | Síntoma observado | Causa | Corrección aplicada |
|---|---|---|---|
| 1 | `SELECT * FROM fn_autenticar(...)` devolvía **0 filas** en los tres casos, aunque `login_intento` sí registraba la traza (es decir, la función se ejecutaba). | Las funciones son `RETURNS TABLE`, y se cerraban con `RETURN;` en lugar de `RETURN NEXT;`. En PL/pgSQL `RETURN` sin argumentos **termina** la función sin emitir la fila: la traza se escribía y el llamador no recibía nada. | Cada rama de salida usa `RETURN NEXT;` seguido de `RETURN;`. Verificado: `(t, 7, 'rol_soporte')` con clave correcta, `(f, NULL, NULL)` en los otros dos casos. |
| 2 | `SET ROLE rol_app_escritura; UPDATE producto SET stock = stock WHERE id_producto = 1;` fallaba con `permission denied for table producto`, **aun teniendo** `GRANT UPDATE (stock)`. | Un `UPDATE ... WHERE` necesita **leer** la columna del `WHERE` y el valor actual de la columna modificada. `GRANT UPDATE (stock)` solo no alcanza: PostgreSQL exige además `SELECT` sobre `id_producto` y `stock`. | Se agregó `GRANT SELECT (id_producto, stock) ON producto TO rol_app_escritura` y las dos filas correspondientes al conjunto esperado. El resto de `producto` (`nombre`, `precio_lista`, `id_categoria`) sigue fuera de su alcance, y `UPDATE precio_lista` continúa fallando. |
| 3 | El diff marcaba 8 filas `SOBRANTE` con grantee `postgres` sobre `mv_facturacion_categoria_mes`, y a la vez 15 `FALTANTE` de columnas que sí estaban otorgadas. | Dos trampas de `information_schema`: (a) **no expone vistas materializadas**, por lo que el diff leía su ACL por otra vía y arrastraba el ACL del dueño; (b) `role_column_grants` **expande** los grants de tabla como si fueran de columna, así que no sirve para distinguir un permiso por columna de uno por tabla. | El diff lee el ACL real (`pg_class.relacl` para tablas y MVs, `pg_attribute.attacl` para columnas) y filtra a los roles de la Parte A en ambas fuentes. |

**Lección de método:** el `EXIT=0` del script no prueba nada por sí solo —los tres casos
terminaban con código 0 mientras el resultado era incorrecto—. Lo que prueba es la
**comparación contra el estado esperado**: el diff 0/0/0/0 y las 22 pruebas negativas.

---

## 3. Estado y pendientes

> **Entorno de validación.** El equipo no dispone de las credenciales del servidor
> PostgreSQL compartido (`localhost:5432`) y `AGENTS.md` prohíbe operar sobre una base que
> no sea de test/dev/local. Por eso la validación se hizo sobre un **clúster temporal
> limpio (PostgreSQL 17.11)** levantado para el TP, con la base `foodstore_test` creada
> desde el esquema del proyecto. La salida adjunta corresponde a esa instancia.

| Ítem | Estado |
|---|---|
| Parte 0 (reconstrucción) | **Ejecutado y validado** en instancia limpia PostgreSQL 17.11 (base creada desde `food_store/schema.sql` + `views.sql` + `materializadas.sql`). `sql/00_reconstruccion_parte0.sql` deja `rol = 6`, `usuario = 12` (10 activos, 6 roles distintos, 12 hashes bcrypt) e idempotente en una segunda corrida. |
| Parte A — spec de Kiro | Escrita: `docs/kiro_roles_spec/requirements.md` (10 requisitos + trazabilidad) y `design.md` (decisiones D1–D10, matriz de roles, riesgos). |
| Parte A — `roles.sql` | **Ejecutado y validado**: `EXIT=0`, sin `WARNING`, idempotente en una segunda corrida (converge al mismo estado). |
| Parte A — verificación | **Ejecutada**: `docs/verificacion_permisos.txt` (salida real). Veredicto `faltantes_tabla = 0, sobrantes_tabla = 0, faltantes_columna = 0, sobrantes_columna = 0 → APROBADO` y 22 pruebas negativas sin ninguna `FALLA`. |
| Parte A — pruebas funcionales | **Ejecutadas** con `SET ROLE` (10 casos): lectura por columna, `UPDATE` acotado, `DELETE` denegado, delegación de rol denegada, `fn_autenticar` / `fn_resetear_password` con traza en `login_intento` y `usuario_auditoria`. |
| Partes B, C, D, E | Pendientes. |

### Cómo reproducir la salida de la verificación (para el equipo)

```bash
# 1. copia de desarrollo (nunca producción)
createdb foodstore_test
psql -U postgres -d foodstore_test -f food_store/schema.sql
psql -U postgres -d foodstore_test -f food_store/views.sql
psql -U postgres -d foodstore_test -f food_store/materializadas.sql

# 2. Parte 0 y Parte A
psql -U postgres -d foodstore_test -f TP7/sql/00_reconstruccion_parte0.sql
psql -U postgres -d foodstore_test -f TP7/sql/roles.sql

# 3. salida de verificación (es el entregable)
psql -U postgres -d foodstore_test -f TP7/docs/verificacion_permisos.sql \
     > TP7/docs/verificacion_permisos.txt 2>&1
```

> La salida adjunta se generó sobre una instancia limpia (PostgreSQL 17.11) creada con
> los pasos 1–3. Si el equipo la regenera sobre su propia copia, el veredicto debe ser el
> mismo `APROBADO`; cualquier diferencia indica un `GRANT` dado a mano por fuera de
> `roles.sql`.
>
> El script de la Parte 0 usa meta-comandos de `psql` (`\if :{?seed_password}`), así que
> **debe** ejecutarse con `psql`, no con un cliente gráfico. Contraseña semilla por
> defecto: `FoodStore.Dev#2026` (sólo para el entorno local).

### Nota sobre el historial de Git (Parte E)

Pendiente de revisión al cierre. Criterio acordado: **un commit por parte**
(0, A, B, C, D, E) con mensaje que explique qué se hizo y por qué, sin un commit final
único con todo el contenido.

---

## 4. Cómo se usa esta bitácora

- Se agrega **una fila por cada interacción relevante** con el asistente, no por cada
  mensaje.
- La columna de validación humana nunca queda vacía: si la respuesta se aceptó tal cual,
  se escribe "Aceptado" y el motivo; si se corrigió, se explica **qué se cambió y por qué**.
- No se copia la respuesta completa de la IA: se resume lo relevante.
- Los prompts se registran **anonimizados**: nunca se pega PII real de la base.
