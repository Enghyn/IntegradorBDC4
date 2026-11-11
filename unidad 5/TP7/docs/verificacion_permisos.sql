-- ============================================================================
-- VERIFICACION_PERMISOS.SQL
-- TP — Unidad 5, Parte A, consigna 3:
--   "Verificar, con \du y con una consulta sobre information_schema.role_table_grants,
--    que cada rol tiene exactamente los privilegios previstos en la especificación
--    de Kiro —ni más, ni menos—. Adjuntar la salida de esa verificación."
--
-- CÓMO SE USA (la salida de este archivo es el entregable)
--   psql -U postgres -d foodstore_test -f TP7/docs/verificacion_permisos.sql \
--        > TP7/docs/verificacion_permisos.txt 2>&1
--
-- QUÉ MUESTRA
--   1. \du                                   -> vista de psql de todos los roles
--   2. Atributos consultables (pg_roles)      -> equivalente para pegar en el informe
--   3. Privilegios a nivel de TABLA           -> information_schema.role_table_grants
--   4. Privilegios a nivel de COLUMNA         -> information_schema.role_column_grants
--   5. Diff contra el conjunto ESPERADO       -> OK / FALTANTE / SOBRANTE
--   6. Pruebas NEGATIVAS (lo que debe fallar) -> has_table_privilege / has_column_privilege
--   7. Veredicto final
--
-- CRITERIO DE ACEPTACIÓN
--   - Cero filas FALTANTE y cero filas SOBRANTE en 5.
--   - Cero filas FALLA en 6.
--   - veredicto = 'APROBADO' en 7.
-- ============================================================================

\pset pager off
\pset border 2
-- Sin NOTICEs de "table does not exist, skipping": la salida es un entregable.
SET client_min_messages = warning;

\echo ''
\echo '================================================================'
\echo '1. \\du - ROLES DEL SERVIDOR'
\echo '================================================================'
\du

\echo ''
\echo '================================================================'
\echo '2. ATRIBUTOS (equivalente consultable de \\du, sólo roles de la Parte A)'
\echo '================================================================'
SELECT r.rolname                       AS rol,
       r.rolcanlogin                   AS login,
       r.rolsuper                      AS superuser,
       r.rolcreaterole                 AS createrole,
       r.rolcreatedb                   AS createdb,
       r.rolbypassrls                  AS bypass_rls,
       (SELECT count(*) FROM pg_catalog.pg_auth_members m
         WHERE m.member = r.oid)       AS hereda_de,
       (SELECT bool_or(m.admin_option) FROM pg_catalog.pg_auth_members m
         WHERE m.member = r.oid)       AS puede_delegar
FROM pg_catalog.pg_roles AS r
WHERE r.rolname IN ('rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes',
                    'rol_auditoria','rol_etl','app_web','admin_datos','etl_job')
ORDER BY r.rolname;

\echo ''
\echo '================================================================'
\echo '3. PRIVILEGIOS A NIVEL DE TABLA / VISTA (information_schema.role_table_grants)'
\echo '================================================================'
SELECT g.grantee,
       g.table_name,
       g.privilege_type
FROM information_schema.role_table_grants AS g
WHERE g.table_schema = 'public'
  AND g.grantee IN ('rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes',
                    'rol_auditoria','rol_etl','app_web','admin_datos','etl_job')
ORDER BY g.grantee, g.table_name, g.privilege_type;

\echo ''
\echo '================================================================'
\echo '4a. PRIVILEGIOS A NIVEL DE COLUMNA (information_schema.role_column_grants)'
\echo '    OJO: esta vista incluye la EXPANSION de los grants a nivel de tabla,'
\echo '    por eso se filtra a las tablas con PII y se compara en 5b contra el ACL real.'
\echo '================================================================'
SELECT g.grantee,
       g.table_name,
       g.column_name,
       g.privilege_type
FROM information_schema.role_column_grants AS g
WHERE g.table_schema = 'public'
  AND g.table_name IN ('cliente', 'usuario', 'producto')
  AND g.grantee IN ('rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes',
                    'rol_auditoria','rol_etl','app_web','admin_datos','etl_job')
ORDER BY g.grantee, g.table_name, g.column_name;

\echo ''
\echo '================================================================'
\echo '4b. ACL REAL POR COLUMNA (pg_attribute.attacl)'
\echo '    Es el unico lugar donde viven los grants A NIVEL DE COLUMNA:'
\echo '    information_schema no permite distinguirlos de los de tabla.'
\echo '================================================================'
SELECT pg_catalog.pg_get_userbyid(x.grantee) AS grantee,
       c.relname                             AS tabla,
       a.attname                             AS columna,
       x.privilege_type
FROM pg_catalog.pg_attribute AS a
JOIN pg_catalog.pg_class     AS c ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) AS x
WHERE n.nspname = 'public'
  AND a.attacl IS NOT NULL
  AND a.attnum > 0
ORDER BY 1, 2, 3;

-- ----------------------------------------------------------------------------
-- 5. DIFF: LO ESPERADO (spec de Kiro) vs LO REAL
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS pg_temp.esperado_tabla;
CREATE TEMP TABLE esperado_tabla (rol TEXT, tabla TEXT, privilegio TEXT);

INSERT INTO esperado_tabla (rol, tabla, privilegio) VALUES
    -- rol_app_lectura: catálogo y pedidos
    ('rol_app_lectura',   'categoria',                          'SELECT'),
    ('rol_app_lectura',   'producto',                           'SELECT'),
    ('rol_app_lectura',   'pedido',                             'SELECT'),
    ('rol_app_lectura',   'detalle_pedido',                     'SELECT'),
    ('rol_app_lectura',   'vista_productos_vigentes_categoria', 'SELECT'),
    ('rol_app_lectura',   'vista_pedidos_usuario',              'SELECT'),
    ('rol_app_lectura',   'vista_detalle_pedido_producto',      'SELECT'),
    -- rol_app_escritura: alta de pedidos (cliente/producto van a nivel de columna)
    ('rol_app_escritura', 'pedido',                             'INSERT'),
    ('rol_app_escritura', 'detalle_pedido',                     'INSERT'),
    -- rol_soporte: identidad y trazas de login (usuario va a nivel de columna)
    ('rol_soporte',       'rol',                                'SELECT'),
    ('rol_soporte',       'login_intento',                      'SELECT'),
    -- rol_reportes: sólo vistas
    ('rol_reportes',      'vista_productos_vigentes_categoria', 'SELECT'),
    ('rol_reportes',      'vista_pedidos_usuario',              'SELECT'),
    ('rol_reportes',      'vista_detalle_pedido_producto',      'SELECT'),
    ('rol_reportes',      'mv_facturacion_categoria_mes',       'SELECT'),
    -- rol_auditoria: trazas, sin escritura
    ('rol_auditoria',     'login_intento',                      'SELECT'),
    ('rol_auditoria',     'usuario_auditoria',                  'SELECT'),
    ('rol_auditoria',     'vw_intentos_login_sospechosos',      'SELECT'),
    -- rol_etl: carga masiva
    ('rol_etl',           'pedido',                             'INSERT'),
    ('rol_etl',           'detalle_pedido',                     'INSERT');

DROP TABLE IF EXISTS pg_temp.esperado_columna;
CREATE TEMP TABLE esperado_columna (rol TEXT, tabla TEXT, columna TEXT, privilegio TEXT);

INSERT INTO esperado_columna (rol, tabla, columna, privilegio) VALUES
    -- rol_app_lectura: cliente SIN email ni telefono
    ('rol_app_lectura',   'cliente', 'id_cliente',     'SELECT'),
    ('rol_app_lectura',   'cliente', 'nombre',         'SELECT'),
    ('rol_app_lectura',   'cliente', 'activo',         'SELECT'),
    ('rol_app_lectura',   'cliente', 'fecha_creacion', 'SELECT'),
    -- rol_app_escritura: stock de producto (UPDATE + lectura mínima para identificar la fila)
    ('rol_app_escritura', 'producto', 'stock',         'UPDATE'),
    ('rol_app_escritura', 'producto', 'stock',         'SELECT'),
    ('rol_app_escritura', 'producto', 'id_producto',   'SELECT'),
    -- rol_soporte: usuario SIN password_hash
    ('rol_soporte',       'usuario', 'id_usuario',     'SELECT'),
    ('rol_soporte',       'usuario', 'email',          'SELECT'),
    ('rol_soporte',       'usuario', 'nombre',         'SELECT'),
    ('rol_soporte',       'usuario', 'apellido',       'SELECT'),
    ('rol_soporte',       'usuario', 'telefono',       'SELECT'),
    ('rol_soporte',       'usuario', 'id_rol',         'SELECT'),
    ('rol_soporte',       'usuario', 'fecha_alta',     'SELECT'),
    ('rol_soporte',       'usuario', 'activo',         'SELECT'),
    ('rol_soporte',       'usuario', 'ultimo_acceso',  'SELECT'),
    ('rol_soporte',       'usuario', 'id_cliente',     'SELECT');

DROP TABLE IF EXISTS pg_temp.real_tabla;
CREATE TEMP TABLE real_tabla AS
SELECT g.grantee AS rol, g.table_name AS tabla, g.privilege_type AS privilegio
FROM information_schema.role_table_grants AS g
WHERE g.table_schema = 'public'
  AND g.grantee IN ('rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes',
                    'rol_auditoria','rol_etl','app_web','admin_datos','etl_job')
UNION
-- information_schema NO expone las vistas materializadas: se leen de pg_class.
SELECT pg_catalog.pg_get_userbyid(x.grantee) AS rol,
       c.relname                             AS tabla,
       x.privilege_type                      AS privilegio
FROM pg_catalog.pg_class     AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(c.relacl) AS x
WHERE n.nspname = 'public'
  AND c.relkind = 'm'
  AND pg_catalog.pg_get_userbyid(x.grantee) IN (
        'rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes',
        'rol_auditoria','rol_etl','app_web','admin_datos','etl_job');

DROP TABLE IF EXISTS pg_temp.real_columna;
CREATE TEMP TABLE real_columna AS
SELECT pg_catalog.pg_get_userbyid(x.grantee) AS rol,
       c.relname                             AS tabla,
       a.attname                             AS columna,
       x.privilege_type                      AS privilegio
FROM pg_catalog.pg_attribute AS a
JOIN pg_catalog.pg_class     AS c ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) AS x
WHERE n.nspname = 'public'
  AND a.attacl IS NOT NULL
  AND a.attnum > 0;

\echo ''
\echo '================================================================'
\echo '5a. DIFF A NIVEL DE TABLA  (OK / FALTANTE / SOBRANTE)'
\echo '================================================================'
SELECT coalesce(e.rol, r.rol)                 AS rol,
       coalesce(e.tabla, r.tabla)             AS objeto,
       coalesce(e.privilegio, r.privilegio)   AS privilegio,
       CASE WHEN r.rol IS NULL THEN 'FALTANTE'
            WHEN e.rol IS NULL THEN 'SOBRANTE'
            ELSE 'OK' END                     AS estado
FROM esperado_tabla AS e
FULL OUTER JOIN real_tabla AS r
  ON  e.rol        = r.rol
  AND e.tabla      = r.tabla
  AND e.privilegio = r.privilegio
ORDER BY estado DESC, 1, 2, 3;

\echo ''
\echo '================================================================'
\echo '5b. DIFF A NIVEL DE COLUMNA  (OK / FALTANTE / SOBRANTE)'
\echo '================================================================'
SELECT coalesce(e.rol, r.rol)                 AS rol,
       coalesce(e.tabla, r.tabla)             AS objeto,
       coalesce(e.columna, r.columna)         AS columna,
       coalesce(e.privilegio, r.privilegio)   AS privilegio,
       CASE WHEN r.rol IS NULL THEN 'FALTANTE'
            WHEN e.rol IS NULL THEN 'SOBRANTE'
            ELSE 'OK' END                     AS estado
FROM esperado_columna AS e
FULL OUTER JOIN real_columna AS r
  ON  e.rol        = r.rol
  AND e.tabla      = r.tabla
  AND e.columna    = r.columna
  AND e.privilegio = r.privilegio
ORDER BY estado DESC, 1, 2, 3, 4;

\echo ''
\echo '================================================================'
\echo '6. PRUEBAS NEGATIVAS — lo que DEBE fallar en la Parte C'
\echo '================================================================'
WITH casos(caso, esperado, obtenido) AS (
    SELECT 'app_web NO puede leer usuario.password_hash', FALSE,
           has_column_privilege('app_web',     'public.usuario', 'password_hash', 'SELECT')
    UNION ALL
    SELECT 'rol_soporte NO puede leer usuario.password_hash', FALSE,
           has_column_privilege('rol_soporte', 'public.usuario', 'password_hash', 'SELECT')
    UNION ALL
    SELECT 'rol_app_lectura NO puede leer cliente.email', FALSE,
           has_column_privilege('rol_app_lectura', 'public.cliente', 'email', 'SELECT')
    UNION ALL
    SELECT 'rol_app_lectura NO puede leer cliente.telefono', FALSE,
           has_column_privilege('rol_app_lectura', 'public.cliente', 'telefono', 'SELECT')
    UNION ALL
    SELECT 'rol_app_lectura SÍ puede leer cliente.nombre', TRUE,
           has_column_privilege('rol_app_lectura', 'public.cliente', 'nombre', 'SELECT')
    UNION ALL
    SELECT 'rol_app_escritura SÍ puede UPDATE producto.stock', TRUE,
           has_column_privilege('rol_app_escritura', 'public.producto', 'stock', 'UPDATE')
    UNION ALL
    SELECT 'rol_app_escritura NO puede UPDATE producto.precio_lista', FALSE,
           has_column_privilege('rol_app_escritura', 'public.producto', 'precio_lista', 'UPDATE')
    UNION ALL
    SELECT 'rol_app_escritura NO puede DELETE pedido', FALSE,
           has_table_privilege('rol_app_escritura', 'public.pedido', 'DELETE')
    UNION ALL
    SELECT 'rol_app_escritura NO puede INSERT en usuario', FALSE,
           has_table_privilege('rol_app_escritura', 'public.usuario', 'INSERT')
    UNION ALL
    SELECT 'rol_reportes NO puede SELECT usuario', FALSE,
           has_table_privilege('rol_reportes', 'public.usuario', 'SELECT')
    UNION ALL
    SELECT 'rol_auditoria SÍ puede SELECT login_intento', TRUE,
           has_table_privilege('rol_auditoria', 'public.login_intento', 'SELECT')
    UNION ALL
    SELECT 'rol_auditoria NO puede INSERT login_intento', FALSE,
           has_table_privilege('rol_auditoria', 'public.login_intento', 'INSERT')
    UNION ALL
    SELECT 'rol_auditoria NO puede DELETE usuario_auditoria', FALSE,
           has_table_privilege('rol_auditoria', 'public.usuario_auditoria', 'DELETE')
    UNION ALL
    SELECT 'rol_reportes SÍ puede SELECT mv_facturacion_categoria_mes', TRUE,
           has_table_privilege('rol_reportes', 'public.mv_facturacion_categoria_mes', 'SELECT')
    UNION ALL
    SELECT 'app_web es miembro de rol_app_lectura', TRUE,
           pg_has_role('app_web', 'rol_app_lectura', 'MEMBER')
    UNION ALL
    SELECT 'app_web NO es miembro de admin_datos', FALSE,
           pg_has_role('app_web', 'admin_datos', 'MEMBER')
    UNION ALL
    SELECT 'admin_datos NO es miembro de rol_auditoria', FALSE,
           pg_has_role('admin_datos', 'rol_auditoria', 'MEMBER')
    UNION ALL
    SELECT 'app_web NO tiene ADMIN OPTION sobre ningún rol', FALSE,
           coalesce((SELECT bool_or(m.admin_option)
                       FROM pg_catalog.pg_auth_members m
                      WHERE m.member = 'app_web'::regrole), FALSE)
    UNION ALL
    SELECT 'admin_datos NO tiene ADMIN OPTION sobre ningún rol', FALSE,
           coalesce((SELECT bool_or(m.admin_option)
                       FROM pg_catalog.pg_auth_members m
                      WHERE m.member = 'admin_datos'::regrole), FALSE)
    UNION ALL
    SELECT 'ningún rol de aplicación es superusuario', FALSE,
           EXISTS (SELECT 1 FROM pg_catalog.pg_roles r
                    WHERE r.rolname IN ('rol_app_lectura','rol_app_escritura','rol_soporte',
                                        'rol_reportes','rol_auditoria','rol_etl',
                                        'app_web','admin_datos','etl_job')
                      AND (r.rolsuper OR r.rolcreaterole OR r.rolcreatedb))
    UNION ALL
    SELECT 'ningún rol de aplicación puede CREATE en el esquema public', FALSE,
           EXISTS (SELECT 1 FROM unnest(ARRAY['rol_app_lectura','rol_app_escritura','rol_soporte',
                                              'rol_reportes','rol_auditoria','rol_etl',
                                              'app_web','admin_datos','etl_job']) AS x(rol)
                    WHERE has_schema_privilege(x.rol, 'public', 'CREATE'))
    UNION ALL
    SELECT 'PUBLIC NO puede CREATE en el esquema public', FALSE,
           coalesce((SELECT bool_or(a.privilege_type = 'CREATE' AND a.grantee = 0)
                       FROM pg_catalog.pg_namespace n,
                            LATERAL aclexplode(n.nspacl) AS a
                      WHERE n.nspname = 'public'), FALSE)
)
SELECT caso,
       esperado,
       obtenido,
       CASE WHEN esperado = obtenido THEN 'OK' ELSE 'FALLA' END AS resultado
FROM casos
ORDER BY CASE WHEN esperado = obtenido THEN 1 ELSE 0 END, caso;

\echo ''
\echo '================================================================'
\echo '7. VEREDICTO FINAL'
\echo '================================================================'
WITH faltantes_tabla AS (
    SELECT count(*) AS n FROM esperado_tabla e
     WHERE NOT EXISTS (SELECT 1 FROM real_tabla r
                        WHERE r.rol = e.rol AND r.tabla = e.tabla
                          AND r.privilegio = e.privilegio)
),
sobrantes_tabla AS (
    SELECT count(*) AS n FROM real_tabla r
     WHERE NOT EXISTS (SELECT 1 FROM esperado_tabla e
                        WHERE e.rol = r.rol AND e.tabla = r.tabla
                          AND e.privilegio = r.privilegio)
),
faltantes_columna AS (
    SELECT count(*) AS n FROM esperado_columna e
     WHERE NOT EXISTS (SELECT 1 FROM real_columna r
                        WHERE r.rol = e.rol AND r.tabla = e.tabla
                          AND r.columna = e.columna AND r.privilegio = e.privilegio)
),
sobrantes_columna AS (
    SELECT count(*) AS n FROM real_columna r
     WHERE NOT EXISTS (SELECT 1 FROM esperado_columna e
                        WHERE e.rol = r.rol AND e.tabla = r.tabla
                          AND e.columna = r.columna AND e.privilegio = r.privilegio)
)
SELECT ft.n AS faltantes_tabla,
       st.n AS sobrantes_tabla,
       fc.n AS faltantes_columna,
       sc.n AS sobrantes_columna,
       CASE WHEN ft.n + st.n + fc.n + sc.n = 0
            THEN 'APROBADO'
            ELSE 'REVISAR (el esquema no coincide con la spec de Kiro)' END AS veredicto
FROM faltantes_tabla ft, sobrantes_tabla st, faltantes_columna fc, sobrantes_columna sc;

\echo ''
\echo 'Recordatorio: los conteos de la sección 7 deben ser 0/0/0/0 y la sección 6'
\echo 'no debe tener ninguna fila FALLA. Esa salida es el entregable de la Parte A.'
\echo ''
