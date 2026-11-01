# Design — Esquema de roles y permisos de mínimo privilegio (Food Store)

> **TP — Unidad 5, Parte A.** Complementa `requirements.md`.
> Decisiones tomadas por el **equipo**; cada una puede defenderse en la devolución.

## 1. Contexto y problema

Food Store corre sobre PostgreSQL 16+ con cinco tablas de negocio
(`cliente`, `categoria`, `producto`, `pedido`, `detalle_pedido`), tres vistas y una vista
materializada. Hoy **todo se conecta como `postgres`**: cualquier error de la aplicación,
cualquier script de carga o cualquier credencial filtrada tiene control total sobre la
base. La Parte A corrige eso con un esquema de identidades explícito.

Restricción de partida detectada en el repositorio: **no existen** los artefactos de las
Clases 1 y 2 (`roles.sql`, `fn_autenticar`, `fn_resetear_password`, tablas `usuario` y
`rol`). El enunciado habilita reconstruirlos; eso es la Parte 0 y se documenta en la
bitácora.

## 2. Decisiones de arquitectura

### D1 — Tablas nuevas dentro de `TP7/sql/`, sin tocar `food_store/schema.sql`

`food_store/schema.sql` es la única fuente estructural del proyecto y está versionada con
datos y vistas ya cargados. Modificarla obligaría a recrear la base y rompería los TP
anteriores. Se agrega un script **aditivo e idempotente**
(`sql/00_reconstruccion_parte0.sql`) que sólo crea objetos nuevos.

*Trade-off:* el esquema queda repartido en dos archivos. Se acepta porque el TP7 es un
entregable autocontenido y porque `food_store/schema.sql` sigue siendo válido tal cual.

### D2 — `usuario` ≠ `cliente`

- `cliente` = dato comercial (quién compra).
- `usuario` = identidad de aplicación (quién opera el sistema: soporte, reportes, ETL, admin).

`usuario.id_cliente` es una FK **opcional** para el caso “cliente con cuenta en el portal”.
Así, la “lectura masiva de `usuario`” de la Parte C afecta datos personales de operadores,
que es exactamente lo que tiene sentido auditar, y la anonimización de la Parte D tiene
material real.

*Alternativa descartada:* reutilizar `cliente` como tabla de login. Mezcla PII comercial con
credenciales y hace imposible aplicar mínimo privilegio por separado.

### D3 — Contraseñas con `pgcrypto` (bcrypt), nunca texto plano

`crypt(password, gen_salt('bf', 12))`. La columna `password_hash` tiene un `CHECK` que
valida el formato bcrypt (`$2a$|$2b$|$2y$`): si alguien intenta insertar texto plano, la
base lo rechaza. Costo 12 ≈ 250 ms por hash, aceptable para login interactivo.

*Limitación conocida y documentada:* la comparación de hashes en `fn_autenticar` no es
estrictamente de tiempo constante. Para un TP es aceptable; en producción se resuelve en
la capa de aplicación o con un módulo de comparación en tiempo constante.

### D4 — Funciones `SECURITY DEFINER` con `search_path` fijado

`fn_autenticar` y `fn_resetear_password` corren con los privilegios del dueño
(`postgres`) para poder leer `password_hash` y escribir las tablas de traza, sin que los
roles de aplicación tengan esos permisos.

Toda función `SECURITY DEFINER` incluye `SET search_path = pg_catalog, public` para
impedir el secuestro de `search_path` (un atacante con `CREATE` en un esquema previo en el
`search_path` podría sustituir `crypt` o `usuario` por objetos propios).

Consecuencia obligatoria: `REVOKE ALL ON FUNCTION ... FROM PUBLIC` (PostgreSQL otorga
`EXECUTE` a `PUBLIC` por defecto). Sin ese `REVOKE`, cualquier rol podría autenticarse sin
credenciales válidas o resetear contraseñas ajenas: sería un escalamiento de privilegios
trivial.

### D5 — Traza de intentos de login en tabla, no sólo en el log

`login_intento` registra cada llamada a `fn_autenticar` (email intentado, éxito/fracaso,
motivo, IP, timestamp). Motivo: el log del servidor es evidencia operativa, pero **no es
consultable desde SQL ni sobrevive a una rotación de logs**. Tener la traza en tabla
permite:

- que la Parte C sea demostrable con una consulta, no sólo con un archivo de texto;
- detectar fuerza bruta con `vw_intentos_login_sospechosos` (≥ 3 fallos en 15 minutos);
- reconstruir la secuencia del incidente sin depender de `log_statement`.

*Decisión explícita:* **no** se implementa bloqueo automático de cuenta en esta entrega.
El umbral de bloqueo es una decisión de negocio (¿cuántos intentos? ¿cuánto tiempo?) que
debe acordarse con el área usuaria; implementarlo “a ojo” genera denegación de servicio
contra usuarios legítimos. Se deja la detección y se documenta como trabajo futuro. Esto
también evita que el simulacro de la Parte C (5 fallos + 1 éxito) quede bloqueado a mitad de
secuencia.

### D6 — `admin_datos` **no** es propietario de los objetos

En PostgreSQL, el dueño de una tabla tiene **todos** los privilegios de forma implícita:
si `admin_datos` fuera dueño de `usuario`, podría leer `password_hash` aunque no tenga
`GRANT`. Por eso las tablas quedan de `postgres` (DBA) y `admin_datos` recibe sólo
privilegios explícitos.

*Trade-off:* `admin_datos` no puede hacer DDL por sí mismo; el cambio de estructura lo
ejecuta el DBA. Se acepta: en Food Store el cambio de esquema es una operación controlada
con backup y ventana de mantenimiento, no una tarea del día a día.

### D7 — `admin_datos` **no** hereda `rol_auditoria` (separación de funciones)

Quien administra datos no debe poder leer ni alterar la traza de auditoría, porque podría
ser el sujeto auditado. `rol_auditoria` se asigna a una identidad separada del equipo de
seguridad.

### D8 — Privilegios por defecto: la política es “nada por defecto”

La consigna pide `ALTER DEFAULT PRIVILEGES` para que las tablas futuras hereden la misma
política. La tentación es `GRANT SELECT ON TABLES TO rol_app_lectura`: es **incorrecto**,
porque toda tabla futura (por ejemplo, una tabla de tokens o de datos de salud) quedaría
legible por el rol de la aplicación sin revisión. Consecuencia: la política implementada es

| Tipo de objeto | Política por defecto | Motivo |
|---|---|---|
| Tablas | `REVOKE ALL ... FROM PUBLIC`; sin `GRANT` genérico | Cada tabla nueva se otorga explícitamente y a nivel de columna |
| Secuencias | `GRANT USAGE` a `rol_app_escritura` y `rol_etl` | Sin `USAGE` no se puede insertar en tablas con `IDENTITY`; no son datos sensibles |
| Funciones | `REVOKE ALL ... FROM PUBLIC` | Evita que una función nueva quede ejecutable por cualquiera |

Plantilla obligatoria al crear una tabla nueva (va en el `design` para que no se olvide):

```sql
REVOKE ALL ON <tabla> FROM PUBLIC;
GRANT SELECT (<columnas_no_sensibles>) ON <tabla> TO <rol>;
```

### D9 — Guarda de entorno en todos los scripts

Cada script arranca con un bloque `DO` que aborta si `current_database()` no contiene
`test`, `dev` o `local` (norma dura de `AGENTS.md`). Escape hatch auditable para la copia
`tp_food_store`: `SET tp7.entorno_confirmado = 'si';` en la misma sesión, de modo que el
override queda visible en el historial de la sesión y no es un `--force` silencioso.

### D10 — Idempotencia

- Tablas: `CREATE TABLE IF NOT EXISTS`.
- Roles: bloque `DO` con `pg_roles` (no existe `CREATE ROLE IF NOT EXISTS`).
- Privilegios: `REVOKE ALL` sobre los roles de aplicación y luego `GRANT` explícitos. Esto
  hace que re-ejecutar `roles.sql` **converja** al estado deseado y además elimina
  privilegios “sobrantes” de versiones anteriores (clave para “ni más ni menos”).

## 3. Matriz de roles y privilegios

### 3.1 Roles de grupo (`NOLOGIN`, no se conectan)

| Rol | Operación que habilita | Por qué esa y no otra |
|---|---|---|
| `rol_app_lectura` | `SELECT` por columna en `cliente` (sin `email`/`telefono`) y `SELECT` en `categoria`, `producto`, `pedido`, `detalle_pedido` y vistas | La app necesita mostrar catálogo e historial de pedidos; no necesita datos de contacto del cliente para eso |
| `rol_app_escritura` | `INSERT` en `pedido`/`detalle_pedido` y `UPDATE (stock)` en `producto`, `USAGE` sobre la secuencia de pedidos | Es lo mínimo para registrar una compra y descontar stock; borrar historia o cambiar precios es decisión de negocio, no de la app |
| `rol_soporte` | `SELECT` por columna en `usuario` (sin `password_hash`), `SELECT` en `rol` y `login_intento`, `EXECUTE` de `fn_resetear_password` | Atención al usuario requiere ver contacto y resetear credenciales; no requiere ver pedidos ni hashes |
| `rol_reportes` | `SELECT` sólo sobre `vista_*` y `mv_facturacion_categoria_mes` | Los reportes se contestan con agregados ya definidos; el acceso a tablas base con PII no aporta nada |
| `rol_auditoria` *(adicional)* | `SELECT` en `login_intento`, `usuario_auditoria` y `vw_intentos_login_sospechosos` | Investigar un incidente exige leer la traza, y el mínimo privilegio exige no poder modificarla |
| `rol_etl` *(adicional)* | `INSERT` en `pedido`/`detalle_pedido`, `USAGE` de la secuencia | Las cargas masivas del TP3 dejan de usar el rol de la app; un error del ETL no puede pisar ni borrar datos |

### 3.2 Roles de login

| Rol | Membresías | Justificación |
|---|---|---|
| `app_web` | `rol_app_lectura` + `rol_app_escritura` | Identidad de la aplicación: lee catálogo/pedidos y registra compras. Sin `ADMIN OPTION`, sin `CREATEROLE` |
| `admin_datos` | `rol_soporte` + `rol_reportes` | Administra datos y estructura del negocio. **No** hereda `rol_auditoria` (D7) ni es dueño de objetos (D6) |
| `etl_job` | `rol_etl` | Identidad del proceso de carga; separa la carga masiva del tráfico de usuarios |

### 3.3 Privilegios a nivel de columna (caso exigido por la consigna)

| Objeto | Rol | Columnas | Privilegio | Motivo |
|---|---|---|---|---|
| `cliente` | `rol_app_lectura` | `id_cliente`, `nombre`, `activo`, `fecha_creacion` | `SELECT` | Mostrar el pedido con el nombre del cliente sin exponer `email` ni `telefono` |
| `producto` | `rol_app_escritura` | `stock` (`UPDATE`) y `id_producto`, `stock` (`SELECT`) | `UPDATE` | Descontar stock sin poder cambiar `precio_lista`; el `SELECT` mínimo es para identificar la fila a modificar |
| `usuario` | `rol_soporte` | `id_usuario`, `email`, `nombre`, `apellido`, `telefono`, `id_rol`, `fecha_alta`, `activo`, `ultimo_acceso`, `id_cliente` | `SELECT` | Contactar al usuario sin ver su hash |

Efecto buscado y verificable: `SELECT * FROM usuario` **falla** para `rol_soporte`. Es la
demostración de que el permiso es realmente de columna.

## 4. Endurecimiento del esquema

```sql
REVOKE ALL    ON SCHEMA public FROM PUBLIC;   -- sin CREATE ni USAGE implícitos
GRANT  USAGE  ON SCHEMA public TO <cada rol de aplicación>;
```

Motivo: en PostgreSQL 15+ `PUBLIC` ya no tiene `CREATE` sobre `public`, pero sí conserva
`USAGE` en instalaciones migradas, y un `CREATE` residual permitiría crear objetos que
“ensucien” el `search_path`. Sin este paso, la Parte C podría mostrar un escalamiento
exitoso que no viene de los `GRANT`, sino del esquema.

## 5. Verificación (cómo se demuestra “ni más ni menos”)

`docs/verificacion_permisos.sql` devuelve, en una sola corrida:

1. `\du` — vista de psql con todos los roles y sus atributos.
2. `pg_roles` — equivalente consultable de `\du` (para pegar en el informe).
3. `information_schema.role_table_grants` — privilegios **a nivel de tabla**.
4. `information_schema.role_column_grants` — privilegios **a nivel de columna**.
5. Un **diff contra el conjunto esperado**: cada fila se marca `OK`, `FALTANTE` o
   `SOBRANTE`. El criterio de aceptación es que no exista ninguna fila distinta de `OK`.
6. Un bloque de **pruebas negativas** con `has_table_privilege`, `has_column_privilege`
   y `pg_has_role`: los casos que *deben* dar `false` (leer `password_hash`, hacer
   `DELETE`, otorgar `admin_datos`, crear objetos en `public`).

El diff es la parte que realmente prueba el mínimo privilegio: un `GRANT ALL` accidental
aparece como `SOBRANTE` aunque las pruebas positivas sigan pasando.

## 6. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| `pgcrypto` no instalable en el servidor | La Parte 0 no corre | Verificación previa; si no hay superusuario, se documenta y se usa hash en la capa de aplicación |
| Ejecutar `roles.sql` sobre producción | Crítico | Guarda D9 + protocolo de backup de `AGENTS.md` |
| `GRANT ALL` “por comodidad” durante el desarrollo | Alto | `REVOKE ALL ... ALL TABLES` al inicio de cada corrida + diff de verificación |
| `admin_datos` termina siendo dueño de tablas | Alto (rompe todo el modelo) | D6 explícito + prueba negativa en la verificación |
| `EXECUTE` de funciones queda en `PUBLIC` | Crítico (escalamiento) | `REVOKE ... FROM PUBLIC` + `ALTER DEFAULT PRIVILEGES` para funciones |
| Contraseñas de login versionadas | Alto | `\password` fuera del repo; `roles.sql` sólo crea el rol |
| El esquema se “arregla” cambiando el rol a superusuario | Crítico | Prueba negativa: ningún rol de aplicación es `SUPERUSER` |

## 7. Orden de ejecución

```
1. pg_dump de la base dev              → db/backups/
2. sql/00_reconstruccion_parte0.sql    → tablas + funciones + seed sintético
3. sql/roles.sql                       → roles + privilegios + defaults
4. docs/verificacion_permisos.sql      → diff esperado vs real (todo OK)
5. \password app_web / admin_datos / etl_job   (interactivo, fuera del repo)
```

Todo el bloque 2–3 se prueba antes en `BEGIN; ... ROLLBACK;` cuando la operación lo permite
(los `CREATE ROLE` no son transaccionales: se validan en la copia de desarrollo, no en
producción).

## 8. Trabajo futuro (fuera del alcance de la Parte A)

- Bloqueo automático por intentos fallidos (D5) con umbral acordado con negocio.
- Row Level Security sobre `pedido` para separar por cliente.
- `pgaudit` para auditoría a nivel de fila y de parámetros (Parte B lo menciona).
- Rotación de contraseñas de roles de login y `VALID UNTIL`.
