-- ============================================================================
-- ROLES.SQL
-- TP — Unidad 5, Parte A: diseño e implementación de roles y permisos de
-- mínimo privilegio sobre Food Store.
--
-- Diseño: docs/kiro_roles_spec/design.md
-- Verificación: docs/verificacion_permisos.sql (debe devolver todo OK)
--
-- PRINCIPIOS APLICADOS
--   1. Ningún rol de aplicación es SUPERUSER, CREATEROLE ni CREATEDB.
--   2. Ningún GRANT incluye WITH ADMIN OPTION: no se delega la capacidad de
--      otorgar privilegios (es lo que la Parte C intenta explotar y debe fallar).
--   3. Cada rol recibe lo mínimo: lectura por columna donde hay PII, escritura
--      acotada a las columnas de negocio, y nada de DELETE.
--   4. Separación de funciones: admin_datos NO hereda rol_auditoria y NO es
--      propietario de los objetos (si fuera dueño tendría todos los privilegios).
--   5. Ejecutar este archivo CONVERGE el estado: primero REVOKE de todo para los
--      roles de aplicación y después los GRANT explícitos. Así una corrida
--      anterior no deja privilegios sobrantes ("ni más, ni menos").
--
-- REQUISITOS
--   - Haber ejecutado 00_reconstruccion_parte0.sql.
--   - Ejecutar como postgres (o rol dueño del esquema) con CREATEROLE.
--   - Contraseñas de los roles de login FUERA del repositorio:
--         \password app_web
--         \password admin_datos
--         \password etl_job
--     Nunca usar ALTER ROLE ... PASSWORD 'texto' dentro de un archivo versionado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. GUARDA DE ENTORNO (norma dura de AGENTS.md)
-- ----------------------------------------------------------------------------
DO $guard$
BEGIN
    IF current_database() !~* '(test|dev|local)'
       AND coalesce(current_setting('tp7.entorno_confirmado', true), '') <> 'si' THEN
        RAISE EXCEPTION
            'La base "%" no parece de desarrollo (debe contener test, dev o local). '
            'Si el equipo confirma que es una copia de trabajo, ejecutar antes: '
            'SET tp7.entorno_confirmado = ''si'';',
            current_database();
    END IF;
END
$guard$;

-- ----------------------------------------------------------------------------
-- 1. PRECONDICIÓN: la Parte 0 tiene que existir
-- ----------------------------------------------------------------------------
DO $pre$
BEGIN
    IF to_regclass('public.usuario') IS NULL THEN
        RAISE EXCEPTION
            'No existe la tabla usuario. Ejecutar primero: '
            'TP7/sql/00_reconstruccion_parte0.sql';
    END IF;
END
$pre$;

-- ----------------------------------------------------------------------------
-- 2. ROLES (creación idempotente; CREATE ROLE no soporta IF NOT EXISTS)
--    Grupo  -> NOLOGIN (no se conectan, sólo agrupan privilegios)
--    Login  -> LOGIN, con todos los atributos peligrosos explícitamente en NO
-- ----------------------------------------------------------------------------
DO $roles$
DECLARE
    v_rol TEXT;
BEGIN
    FOREACH v_rol IN ARRAY ARRAY[
        'rol_app_lectura',
        'rol_app_escritura',
        'rol_soporte',
        'rol_reportes',
        'rol_auditoria',
        'rol_etl'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = v_rol) THEN
            EXECUTE format(
                'CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
                v_rol);
        END IF;
    END LOOP;

    FOREACH v_rol IN ARRAY ARRAY['app_web', 'admin_datos', 'etl_job'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = v_rol) THEN
            EXECUTE format(
                'CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
                v_rol);
        END IF;
    END LOOP;
END
$roles$;

-- ----------------------------------------------------------------------------
-- 3. ENDURECIMIENTO DEL ESQUEMA PUBLIC
--    Sin CREATE ni USAGE implícitos para PUBLIC: un CREATE residual permitiría
--    crear objetos que secuestren el search_path de una función SECURITY DEFINER.
-- ----------------------------------------------------------------------------
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO
    rol_app_lectura,
    rol_app_escritura,
    rol_soporte,
    rol_reportes,
    rol_auditoria,
    rol_etl,
    app_web,
    admin_datos,
    etl_job;

-- ----------------------------------------------------------------------------
-- 4. LIMPIEZA DE PRIVILEGIOS DIRECTOS (idempotencia y "ni más, ni menos")
--    Se revoca todo lo otorgado antes a los roles de grupo; a partir de acá sólo
--    vale lo que este archivo vuelve a otorgar explícitamente.
-- ----------------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM
    rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, rol_auditoria, rol_etl;

REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM
    rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, rol_auditoria, rol_etl;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM
    rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, rol_auditoria, rol_etl;

-- Los roles de login NO reciben privilegios directos: heredan de su grupo.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM app_web, admin_datos, etl_job;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM app_web, admin_datos, etl_job;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM app_web, admin_datos, etl_job;

-- ----------------------------------------------------------------------------
-- 5. ROL_APP_LECTURA
--    Lee catálogo y pedidos. Sobre cliente, LECTURA A NIVEL DE COLUMNA:
--    sin email ni telefono (PII que la app no necesita para mostrar un pedido).
-- ----------------------------------------------------------------------------
GRANT SELECT (id_cliente, nombre, activo, fecha_creacion)
    ON cliente
    TO rol_app_lectura;

GRANT SELECT ON categoria, producto, pedido, detalle_pedido
    TO rol_app_lectura;

-- ----------------------------------------------------------------------------
-- 6. ROL_APP_ESCRITURA
--    Registra pedidos y descuenta stock. No borra, no cambia precios.
--    UPDATE a nivel de columna: sólo producto.stock.
-- ----------------------------------------------------------------------------
GRANT INSERT ON pedido, detalle_pedido TO rol_app_escritura;
GRANT UPDATE (stock) ON producto          TO rol_app_escritura;

-- Un UPDATE necesita identificar la fila que modifica y leer el valor actual:
-- sin SELECT sobre (id_producto, stock) la sentencia falla aunque el UPDATE esté
-- concedido. Es lo mínimo para que la operación exista; el resto de producto
-- (nombre, precio_lista, id_categoria) sigue fuera de su alcance.
GRANT SELECT (id_producto, stock) ON producto TO rol_app_escritura;

-- La secuencia de la columna IDENTITY se resuelve dinámicamente: así el script no
-- depende de un nombre de secuencia escrito a mano.
DO $seq_escritura$
DECLARE
    v_seq TEXT;
BEGIN
    v_seq := pg_get_serial_sequence('public.pedido', 'id_pedido');
    IF v_seq IS NOT NULL THEN
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO rol_app_escritura', v_seq);
    END IF;
END
$seq_escritura$;

-- ----------------------------------------------------------------------------
-- 7. ROL_SOPORTE
--    Atención al usuario. LECTURA A NIVEL DE COLUMNA sobre usuario:
--    todo menos password_hash. Por eso SELECT * FROM usuario DEBE fallar.
--    Sólo puede resetear contraseñas a través de la función, no escribiendo el hash.
-- ----------------------------------------------------------------------------
GRANT SELECT (
        id_usuario,
        email,
        nombre,
        apellido,
        telefono,
        id_rol,
        fecha_alta,
        activo,
        ultimo_acceso,
        id_cliente
    )
    ON usuario
    TO rol_soporte;

GRANT SELECT ON rol            TO rol_soporte;
GRANT SELECT ON login_intento  TO rol_soporte;

-- ----------------------------------------------------------------------------
-- 8. ROL_REPORTES
--    Sólo vistas y la vista materializada: nunca tablas base con PII.
--    (Los GRANT sobre vistas se aplican más abajo, condicionados a su existencia.)
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- 9. ROL_AUDITORIA
--    Lectura de trazas. Sin INSERT/UPDATE/DELETE: la evidencia no se toca.
-- ----------------------------------------------------------------------------
GRANT SELECT ON login_intento, usuario_auditoria TO rol_auditoria;

-- ----------------------------------------------------------------------------
-- 10. ROL_ETL
--     Carga masiva aislada del tráfico de la aplicación. Misma escritura que la
--     app, pero sin acceso a producto (no ajusta stock) y sin UPDATE/DELETE.
-- ----------------------------------------------------------------------------
GRANT INSERT ON pedido, detalle_pedido TO rol_etl;

DO $seq_etl$
DECLARE
    v_seq TEXT;
BEGIN
    v_seq := pg_get_serial_sequence('public.pedido', 'id_pedido');
    IF v_seq IS NOT NULL THEN
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO rol_etl', v_seq);
    END IF;
END
$seq_etl$;

-- ----------------------------------------------------------------------------
-- 11. VISTAS Y VISTA MATERIALIZADA (condicionado a que existan)
--     vista_pedidos_usuario ya oculta email y telefono del cliente: por eso es la
--     vía correcta para que reportes vea pedidos sin PII.
-- ----------------------------------------------------------------------------
DO $vistas$
BEGIN
    IF to_regclass('public.vista_productos_vigentes_categoria') IS NOT NULL THEN
        GRANT SELECT ON public.vista_productos_vigentes_categoria
            TO rol_app_lectura, rol_reportes;
    END IF;

    IF to_regclass('public.vista_pedidos_usuario') IS NOT NULL THEN
        GRANT SELECT ON public.vista_pedidos_usuario
            TO rol_app_lectura, rol_reportes;
    END IF;

    IF to_regclass('public.vista_detalle_pedido_producto') IS NOT NULL THEN
        GRANT SELECT ON public.vista_detalle_pedido_producto
            TO rol_app_lectura, rol_reportes;
    END IF;

    IF to_regclass('public.mv_facturacion_categoria_mes') IS NOT NULL THEN
        GRANT SELECT ON public.mv_facturacion_categoria_mes
            TO rol_reportes;
    END IF;

    IF to_regclass('public.vw_intentos_login_sospechosos') IS NOT NULL THEN
        GRANT SELECT ON public.vw_intentos_login_sospechosos
            TO rol_auditoria;
    END IF;
END
$vistas$;

-- ----------------------------------------------------------------------------
-- 12. FUNCIONES: quitar el EXECUTE implícito de PUBLIC
--     PostgreSQL otorga EXECUTE a PUBLIC por defecto. En una función
--     SECURITY DEFINER eso es un escalamiento de privilegios: cualquiera podría
--     resetear la contraseña de otro usuario sin autenticarse.
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION fn_autenticar(TEXT, TEXT)            FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_resetear_password(TEXT, TEXT, TEXT) FROM PUBLIC;

-- Quién autentica: la app (vía rol_app_lectura) y administración (vía rol_soporte).
GRANT EXECUTE ON FUNCTION fn_autenticar(TEXT, TEXT)
    TO rol_app_lectura, rol_soporte;

-- Sólo soporte resetea contraseñas.
GRANT EXECUTE ON FUNCTION fn_resetear_password(TEXT, TEXT, TEXT)
    TO rol_soporte;

-- ----------------------------------------------------------------------------
-- 13. MEMBRESÍAS (sin WITH ADMIN OPTION)
--     app_web      -> lectura + escritura (operación de la aplicación)
--     admin_datos  -> soporte + reportes (administración de datos)
--                    NO hereda rol_auditoria: separación de funciones (D7)
--     etl_job      -> ETL (carga masiva aislada)
-- ----------------------------------------------------------------------------
GRANT rol_app_lectura   TO app_web;
GRANT rol_app_escritura TO app_web;

GRANT rol_soporte       TO admin_datos;
GRANT rol_reportes      TO admin_datos;

GRANT rol_etl           TO etl_job;

-- Refuerzo explícito: ninguna de estas membresías puede delegarse.
REVOKE ADMIN OPTION FOR rol_app_lectura, rol_app_escritura FROM app_web;
REVOKE ADMIN OPTION FOR rol_soporte, rol_reportes       FROM admin_datos;
REVOKE ADMIN OPTION FOR rol_etl                         FROM etl_job;

-- Refuerzo de separación de funciones: auditoría no se hereda desde ninguna
-- identidad operativa (aunque una corrida anterior lo hubiera otorgado).
-- Se consulta la membresía directa antes de revocar para no generar WARNINGs
-- cuando no hay nada que quitar.
DO $separacion$
DECLARE
    v_rol TEXT;
BEGIN
    FOREACH v_rol IN ARRAY ARRAY['app_web', 'admin_datos', 'etl_job'] LOOP
        IF EXISTS (
            SELECT 1
              FROM pg_catalog.pg_auth_members AS m
              JOIN pg_catalog.pg_roles AS objetivo ON objetivo.oid = m.roleid
              JOIN pg_catalog.pg_roles AS miembro  ON miembro.oid  = m.member
             WHERE objetivo.rolname = 'rol_auditoria'
               AND miembro.rolname  = v_rol
        ) THEN
            EXECUTE format('REVOKE rol_auditoria FROM %I', v_rol);
        END IF;
    END LOOP;
END
$separacion$;

-- ----------------------------------------------------------------------------
-- 14. ALTER DEFAULT PRIVILEGES — la política es "nada por defecto" (D8)
--
--     Se usa current_user para que la política aplique al rol que crea los
--     objetos en esta base (normalmente postgres). Ajustar si el dueño es otro.
--
--     ¿Por qué no "GRANT SELECT ON TABLES TO rol_app_lectura"?
--     Porque toda tabla futura heredaría SELECT, incluida una tabla con tokens o
--     datos sensibles. La política correcta es: sin acceso implícito y GRANT
--     explícito (a nivel de columna cuando hay PII) al crear cada objeto.
-- ----------------------------------------------------------------------------
DO $adp$
BEGIN
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC',
        current_user);

    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC',
        current_user);

    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM PUBLIC',
        current_user);

    -- Las secuencias no son datos sensibles: quien escribe necesita USAGE.
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public GRANT USAGE ON SEQUENCES TO rol_app_escritura, rol_etl',
        current_user);
END
$adp$;

-- ----------------------------------------------------------------------------
-- 15. RESUMEN DE LA CORRIDA
-- ----------------------------------------------------------------------------
SELECT r.rolname                     AS rol,
       r.rolcanlogin                 AS puede_conectarse,
       r.rolsuper                    AS superusuario,
       r.rolcreaterole               AS crea_roles,
       (SELECT count(*) FROM pg_catalog.pg_auth_members m
         WHERE m.roleid = r.oid)     AS otorga_a,
       (SELECT count(*) FROM pg_catalog.pg_auth_members m
         WHERE m.member = r.oid)     AS hereda_de
FROM pg_catalog.pg_roles AS r
WHERE r.rolname IN (
        'rol_app_lectura', 'rol_app_escritura', 'rol_soporte', 'rol_reportes',
        'rol_auditoria', 'rol_etl', 'app_web', 'admin_datos', 'etl_job')
ORDER BY r.rolname;

-- ============================================================================
-- ESTADO ESPERADO AL FINAL
--   rol_app_lectura    | puede_conectarse f | superusuario f | crea_roles f | hereda_de 0
--   rol_app_escritura  | f | f | f | 0
--   rol_soporte        | f | f | f | 0
--   rol_reportes       | f | f | f | 0
--   rol_auditoria      | f | f | f | 0
--   rol_etl            | f | f | f | 0
--   app_web            | t | f | f | 2   (rol_app_lectura + rol_app_escritura)
--   admin_datos        | t | f | f | 2   (rol_soporte + rol_reportes)
--   etl_job            | t | f | f | 1   (rol_etl)
--
-- Ninguno debe tener superusuario = t ni crea_roles = t.
-- Verificación completa: TP7/docs/verificacion_permisos.sql
-- ============================================================================
