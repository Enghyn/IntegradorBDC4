# Requirements — Esquema de roles y permisos de mínimo privilegio (Food Store)

> **Trabajo Práctico — Unidad 5 (Base de Datos II)**
> Parte A — Diseño e implementación de roles y permisos de mínimo privilegio.
> Modalidad: **equipo**. Base de datos de trabajo: copia **local/dev** (`tp_food_store` o
> `foodstore_test`), nunca producción.
> PostgreSQL 16 o superior.

## 1. Introducción

Food Store necesita un esquema de permisos que permita operar la aplicación, la atención
al usuario, los reportes y las cargas masivas **sin que ningún rol pueda hacer más de lo
que su función exige**. El repositorio no conserva los artefactos de las Clases 1 y 2
(`roles.sql`, `fn_autenticar`, `fn_resetear_password`, tabla `usuario`), por lo que este
documento asume su **reconstrucción previa** (Parte 0), habilitada explícitamente por el
enunciado del TP.

Cada rol se justifica en una oración: **qué operación habilita y por qué esa operación y
no otra**.

Fuera de alcance de esta especificación:

- Implementación de la auditoría de servidor (Parte B).
- Simulacro de incidente (Parte C).
- Anonimización de datos (Parte D).
- Alta disponibilidad, replicación y backups automáticos.

## 2. Glosario

| Término | Significado |
|---|---|
| **Rol de grupo** | Rol de PostgreSQL `NOLOGIN` que sólo agrupa privilegios. No se conecta. |
| **Rol de login** | Rol de PostgreSQL con `LOGIN` que representa una identidad real de conexión. |
| **PII** | Datos personales identificables: `email`, `nombre`, `apellido`, `telefono`, `fecha_alta`. |
| **Mínimo privilegio** | Cada rol recibe exactamente los privilegios que su operación requiere, ni más ni menos. |
| **Separación de funciones** | Quien administra datos no es quien audita, y quien opera la app no administra. |

## 3. Requisitos

### Requisito 1 — Modelo de identidades reconstruido (Parte 0)

**Historia:** Como equipo, necesito la estructura de identidades de Food Store
(`rol`, `usuario`, `login_intento`, `usuario_auditoria`) y las funciones de
autenticación, para poder diseñar y verificar permisos sobre objetos reales.

#### Criterios de aceptación

1. CUANDO se ejecute el script de reconstrucción, ENTONCES deben existir las tablas
   `rol`, `usuario`, `login_intento` y `usuario_auditoria`, y las funciones
   `fn_autenticar` y `fn_resetear_password`.
2. CUANDO se inspeccione `usuario`, ENTONCES debe contener las columnas PII
   `email`, `nombre`, `apellido`, `telefono` y `fecha_alta`, además de
   `password_hash`, `id_rol`, `activo`, `ultimo_acceso` e `id_cliente`.
3. CUANDO se inspeccione `usuario.password_hash`, ENTONCES ningún valor debe estar en
   texto plano: todos deben cumplir el formato bcrypt (`$2a$`, `$2b$` o `$2y$`).
4. CUANDO se ejecute la reconstrucción dos veces, ENTONCES no debe fallar ni duplicar
   objetos ni filas.
5. CUANDO se ejecute sobre una base cuyo nombre no contenga `test`, `dev` o `local`,
   ENTONCES el script debe abortar salvo confirmación explícita del equipo.

### Requisito 2 — Catálogo de roles justificados

**Historia:** Como responsable de seguridad, necesito que cada rol tenga una justificación
escrita de una oración, para poder defender ante la cátedra por qué existe y por qué no
tiene más permisos.

#### Criterios de aceptación

1. CUANDO se lea la especificación, ENTONCES cada rol debe tener asociada **una oración**
   con: operación que habilita + por qué esa y no otra.
2. CUANDO se enumeren los roles de grupo, ENTONCES deben estar al menos
   `rol_app_lectura`, `rol_app_escritura`, `rol_soporte` y `rol_reportes` (los cuatro de
   la Clase 1), más los adicionales que el equipo justifique.
3. CUANDO se enumeren los roles de login, ENTONCES deben existir al menos `app_web` y
   `admin_datos`.
4. CUANDO se inspeccione cualquier rol del esquema, ENTONCES ninguno debe ser
   `SUPERUSER` ni tener `CREATEROLE` o `CREATEDB`.

### Requisito 3 — Privilegios de mínimo privilegio por rol

**Historia:** Como equipo, necesito que cada rol tenga sólo los privilegios de su función,
para que un compromiso de credenciales tenga el menor impacto posible.

#### Criterios de aceptación

1. CUANDO `rol_app_lectura` consulte `cliente`, ENTONCES debe ver `id_cliente`, `nombre`,
   `activo` y `fecha_creacion`, y NO debe poder leer `email` ni `telefono`.
2. CUANDO `rol_app_escritura` modifique `producto`, ENTONCES sólo debe poder actualizar la
   columna `stock`, no `precio_lista` ni el resto.
3. CUANDO `rol_app_escritura` intente `DELETE` sobre `pedido`, `detalle_pedido` o
   `producto`, ENTONCES la operación debe fallar por permisos.
4. CUANDO `rol_soporte` consulte `usuario`, ENTONCES debe poder leer los datos de contacto
   y `id_rol`, pero NO `password_hash`.
5. CUANDO `rol_reportes` consulte datos de negocio, ENTONCES debe hacerlo únicamente a
   través de las vistas (`vista_*`, `mv_facturacion_categoria_mes`) y no de las tablas
   base con PII.
6. CUANDO `rol_auditoria` consulte `login_intento` o `usuario_auditoria`, ENTONCES debe
   poder leerlos, y NO debe poder modificarlos ni borrarlos.
7. CUANDO `rol_etl` cargue pedidos, ENTONCES sólo debe poder insertar en `pedido` y
   `detalle_pedido`, sin `UPDATE` ni `DELETE`.

### Requisito 4 — Membresías sin capacidad de delegación

#### Criterios de aceptación

1. CUANDO se otorgue un rol de grupo a un rol de login, ENTONCES el `GRANT` no debe
   incluir `WITH ADMIN OPTION`.
2. CUANDO `app_web` intente `GRANT admin_datos TO app_web` (o a cualquier rol),
   ENTONCES la operación debe fallar con error de permisos.
3. CUANDO se inspeccione `admin_datos`, ENTONCES NO debe ser miembro de
   `rol_auditoria` (separación de funciones entre administración y auditoría).
4. CUANDO se inspeccione `admin_datos`, ENTONCES NO debe ser propietario de las tablas
   del esquema: el DDL lo ejecuta el DBA con `postgres` (ser propietario anularía los
   `GRANT` porque el dueño tiene todos los privilegios implícitos).

### Requisito 5 — Permiso a nivel de columna (caso exigido)

#### Criterios de aceptación

1. CUANDO se inspeccione `information_schema.role_column_grants`, ENTONCES debe existir al
   menos un privilegio otorgado a nivel de columna.
2. CUANDO `rol_soporte` ejecute `SELECT * FROM usuario`, ENTONCES debe fallar: la lectura
   debe hacerse enumerando columnas, sin `password_hash`.
3. CUANDO `rol_app_lectura` ejecute `SELECT * FROM cliente`, ENTONCES debe fallar por la
   misma razón.

### Requisito 6 — Privilegios por defecto para objetos futuros

#### Criterios de aceptación

1. CUANDO se cree una tabla nueva en el esquema `public`, ENTONCES no debe quedar
   accesible para los roles de aplicación sin un `GRANT` explícito.
2. CUANDO se cree una secuencia nueva, ENTONCES los roles de escritura y ETL deben poder
   usarla sin intervención manual.
3. CUANDO se cree una función nueva, ENTONCES no debe quedar ejecutable por `PUBLIC`.
4. CUANDO se revise `ALTER DEFAULT PRIVILEGES`, ENTONCES debe existir al menos una
   sentencia aplicada al rol propietario de los objetos (`postgres`) en el esquema
   `public`.

### Requisito 7 — Endurecimiento del esquema `public`

#### Criterios de aceptación

1. CUANDO se inspeccione el privilegio `CREATE` sobre el esquema `public`, ENTONCES
   `PUBLIC` no debe tenerlo.
2. CUANDO se inspeccione el privilegio `USAGE` sobre el esquema `public`, ENTONCES cada
   rol de aplicación debe tenerlo de forma explícita.

### Requisito 8 — Verificación de privilegios (ni más ni menos)

#### Criterios de aceptación

1. CUANDO se ejecute la verificación, ENTONCES debe incluir la salida de `\du`.
2. CUANDO se ejecute la verificación, ENTONCES debe incluir una consulta sobre
   `information_schema.role_table_grants` y otra sobre `role_column_grants`.
3. CUANDO se compare lo esperado contra lo real, ENTONCES el resultado debe distinguir
   privilegios **FALTANTES** y **SOBRANTES**, y ambos conjuntos deben quedar vacíos.
4. CUANDO exista cualquier privilegio sobrante, ENTONCES debe considerarse un defecto del
   esquema, no un detalle cosmético.

### Requisito 9 — Sin secretos ni PII expuesta

#### Criterios de aceptación

1. CUANDO se revise `roles.sql`, ENTONCES no debe contener contraseñas, tokens ni claves.
2. CUANDO se necesite asignar contraseña a un rol de login, ENTONCES debe hacerse fuera
   del repositorio (`\password`), nunca con `ALTER ROLE ... PASSWORD 'texto'` versionado.
3. CUANDO una función falle, ENTONCES no debe devolver el error SQL original ni detalles
   de la estructura interna.
4. CUANDO un rol sin permiso intente una operación, ENTONCES el mensaje debe ser el
   genérico del motor (`permission denied`), sin información adicional del esquema.

### Requisito 10 — Trazabilidad y repetibilidad

#### Criterios de aceptación

1. CUANDO se ejecute `roles.sql` dos veces, ENTONCES no debe fallar (idempotencia).
2. CUANDO se ejecute cualquier script del TP, ENTONCES debe existir un backup previo
   (`pg_dump`) en `db/backups/`.
3. CUANDO se agregue o modifique un privilegio, ENTONCES debe quedar registrado en
   `BITACORA.md` junto con la validación humana aplicada.
4. CUANDO se confirme un cambio de permisos, ENTONCES debe existir un commit de Git con
   mensaje que explique **qué se hizo y por qué**.

## 4. Matriz de trazabilidad consigna → requisito → evidencia

| Consigna (Parte A) | Requisito | Evidencia |
|---|---|---|
| 1. Spec de Kiro con roles justificados | R2 | `docs/kiro_roles_spec/requirements.md` + `design.md` |
| 2. `roles.sql` con CREATE ROLE / GRANT / REVOKE | R1, R3, R4, R7 | `sql/roles.sql` |
| 2. Permiso a nivel de columna | R5 | `GRANT SELECT (…) ON cliente` / `usuario` |
| 2. `ALTER DEFAULT PRIVILEGES` | R6 | bloque 8 de `sql/roles.sql` |
| 3. Verificación con `\du` + `information_schema` | R8 | `docs/verificacion_permisos.sql` y su salida |
| 4. Auditoría de la IA sobre `roles.sql` | R10 | `BITACORA.md` (caso de permiso demasiado amplio) |

## 5. Supuestos y dependencias

- `food_store/schema.sql` ya creó `cliente`, `categoria`, `producto`, `pedido` y
  `detalle_pedido`, y `views.sql` creó las vistas del TP5.
- La extensión `pgcrypto` puede instalarse (requiere superusuario).
- Los scripts se ejecutan con un rol con `CREATEROLE` (el DBA, `postgres`).
- El equipo trabaja sobre una copia de desarrollo; producción queda explícitamente fuera.
