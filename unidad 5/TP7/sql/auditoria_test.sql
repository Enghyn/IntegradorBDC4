-- ============================================================================
-- AUDITORIA_TEST.SQL
-- TP — Unidad 5: Administración y seguridad de Food Store
-- PARTE B — Prueba de la auditoría de servidor
--
-- QUÉ HACE ESTE ARCHIVO
--   1. Verifica que la configuración de auditoría esté efectivamente aplicada.
--   2. Ejecuta la secuencia de prueba exigida por la consigna: una LECTURA, una
--      INSERCIÓN, una ACTUALIZACIÓN y un INTENTO DE INICIO DE SESIÓN FALLIDO,
--      más dos operaciones denegadas que sirven de contraste.
--   3. Deja las consultas para leer la traza desde SQL.
--
-- QUÉ NO HACE
--   No cambia la configuración: los ALTER SYSTEM del punto 1 de la consigna se
--   aplican en una sesión de DBA y quedan documentados, con sus valores y su
--   justificación, en docs/informe_auditoria.md § 1. Un rol de aplicación no
--   puede (ni debe poder) reconfigurar el motor.
--
-- POR QUÉ SE EJECUTA COMO app_web Y NO COMO postgres
--   Si la sesión se abre como postgres y se usa SET ROLE, el log registra en %u
--   al usuario de la SESIÓN (postgres), no al rol efectivo: el fragmento
--   dejaría de responder "quién". Corriendo la secuencia con la identidad de la
--   aplicación, cada línea dice app_web@foodstore_test y el intento de
--   escalamiento se registra contra la identidad real que lo intentó.
--
-- PREPARACIÓN (una sola vez en la copia dev, fuera del repositorio)
--   -- a) contraseña sintética para la prueba. NO se versiona (requisito 9 de
--   --    la Parte A): se ejecuta a mano y se descarta. Acá va un marcador, no
--   --    la clave real.
--   ALTER ROLE app_web PASSWORD '<clave-sintetica-efimera>';
--
--   -- b) en pg_hba.conf, ANTES de las líneas "trust", para poder probar un
--   --    rechazo real del motor (punto 2 de la consigna):
--   host all app_web 127.0.0.1/32 scram-sha-256
--   host all app_web ::1/128        scram-sha-256
--   SELECT pg_reload_conf();
--
-- CÓMO SE EJECUTA
--   psql "host=localhost port=5544 dbname=foodstore_test user=app_web" \
--        -f TP7/sql/auditoria_test.sql
--
-- DÓNDE QUEDA EL LOG
--   Con logging_collector = on: <data_directory>/log/postgresql-<fecha>.log
--   (texto) y el .csv equivalente. El fragmento del informe se capturó rotando
--   el log antes y después de la prueba (SELECT pg_rotate_logfile()), de modo
--   que la ventana del archivo coincide exactamente con la secuencia.
-- ============================================================================

-- ============================================================================
-- 0. MODO DBA (opcional) — APLICACIÓN DE LA CONFIGURACIÓN
--    La activación del punto 1 de la consigna es una operación de
--    SUPERUSUARIO: escribe postgresql.auto.conf y logging_collector exige
--    reiniciar el motor. Por eso está en una sección GATEADA que sólo corre
--    si se pasa -v aplicar_config=si. Sin esa variable, el script hace
--    únicamente la verificación y la secuencia de prueba (ejecutable como
--    app_web).
--
--      psql "host=... user=postgres" -v aplicar_config=si -f auditoria_test.sql
--      -- reiniciar el servidor (logging_collector lo exige)
--      psql "host=... user=app_web" -f auditoria_test.sql
--
--    Los valores aplicados y su justificación están en
--    docs/informe_auditoria.md § 1.
-- ============================================================================
\if :{?aplicar_config}
ALTER SYSTEM SET logging_collector          = on;
ALTER SYSTEM SET log_destination            = 'csvlog,stderr';
ALTER SYSTEM SET log_directory              = 'log';
ALTER SYSTEM SET log_filename               = 'postgresql-%Y-%m-%d_%H%M%S.log';
ALTER SYSTEM SET log_rotation_age           = '1d';
ALTER SYSTEM SET log_rotation_size          = '10MB';
ALTER SYSTEM SET log_file_mode              = '0640';
ALTER SYSTEM SET log_line_prefix            = '%m [%p] %q%u@%d/%a host=%h ';
ALTER SYSTEM SET log_connections            = on;
ALTER SYSTEM SET log_disconnections         = on;
ALTER SYSTEM SET log_statement              = 'all';
ALTER SYSTEM SET log_min_duration_statement = -1;
ALTER SYSTEM SET log_error_verbosity        = 'default';
ALTER SYSTEM SET log_timezone               = 'America/Argentina/Buenos_Aires';
ALTER SYSTEM SET log_parameter_max_length   = 0;
\echo ''
\echo '>> Configuración escrita en postgresql.auto.conf.'
\echo '>> PASO SIGUIENTE: REINICIAR el servidor (logging_collector lo exige)'
\echo '>> y volver a ejecutar este script SIN -v aplicar_config, como app_web.'
\quit
\endif

-- ----------------------------------------------------------------------------
-- 1. VERIFICACIÓN DE LA CONFIGURACIÓN EFECTIVA
--    Si algún "source" sigue diciendo "default", el cambio no se aplicó.
--    OJO: pg_settings oculta a los roles que no son superusuario los
--    parámetros SUSET (acá: log_directory y log_filename). Por eso corriendo
--    como app_web se ven 12 de los 14 de esta lista; la verificación completa
--    (14/14) está en docs/informe_auditoria.md § 1.2.
-- ----------------------------------------------------------------------------
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('logging_collector','log_destination','log_directory',
               'log_filename','log_line_prefix','log_connections',
               'log_disconnections','log_statement','log_min_duration_statement',
               'log_rotation_age','log_rotation_size','log_timezone','log_file_mode',
               'log_parameter_max_length')
ORDER BY name;

-- ----------------------------------------------------------------------------
-- 2. SECUENCIA DE PRUEBA
--    application_name queda en cada línea del log vía %a: permite aislar esta
--    prueba del resto de la actividad sin depender de la hora.
-- ----------------------------------------------------------------------------
SET application_name = 'tp7_parte_b';

\echo ''
\echo '=== B1. LECTURA (catálogo servido a la aplicación) ==='
SELECT id_producto, nombre, stock
FROM producto
ORDER BY id_producto;

\echo ''
\echo '=== B2. INSERCIÓN (alta de pedido + detalle) ==='
INSERT INTO pedido (id_cliente, forma_pago)
VALUES (1, 'TARJETA')
RETURNING id_pedido \gset

INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_facturado)
VALUES (:id_pedido, 1, 2, 1500.00);

\echo ''
\echo '=== B3. ACTUALIZACIÓN (descuento de stock) ==='
UPDATE producto
   SET stock = stock - 2
 WHERE id_producto = 1;

\echo ''
\echo '=== B4. INICIO DE SESIÓN FALLIDO (capa de aplicación) ==='
\echo '    fn_autenticar con clave incorrecta: no debe revelar si el usuario existe.'
SELECT * FROM fn_autenticar('maria.gonzalez@foodstore.test', 'clave_incorrecta_auditoria');
SELECT * FROM fn_autenticar('maria.gonzalez@foodstore.test', 'segunda_clave_incorrecta');
SELECT * FROM fn_autenticar('maria.gonzalez@foodstore.test', 'tercera_clave_incorrecta');

\echo ''
\echo '=== B5. OPERACIÓN DENEGADA (lectura de PII fuera de alcance) ==='
\echo '    app_web NO debe poder leer usuario: el ERROR también es evidencia.'
SELECT * FROM usuario LIMIT 1;

\echo ''
\echo '=== B6. OPERACIÓN DENEGADA (intento de escalamiento) ==='
\echo '    app_web NO debe poder otorgarse admin_datos.'
GRANT admin_datos TO app_web;

\echo ''
\echo '=== B7. VERIFICACIÓN: la inserción y la actualización impactaron ==='
SELECT id_pedido, id_cliente, forma_pago, fecha_pedido
FROM pedido
ORDER BY id_pedido DESC
LIMIT 3;

SELECT id_producto, nombre, stock
FROM producto
ORDER BY id_producto;

-- ----------------------------------------------------------------------------
-- 3. TRAZAS CONSULTABLES DESDE SQL
--    Las corre el DBA / auditoría (rol_soporte o rol_auditoria), NO app_web:
--    el rol de la aplicación no puede leer las trazas. Se dejan acá para que el
--    equipo las ejecute al cerrar la prueba.
-- ----------------------------------------------------------------------------
\echo ''
\echo '=== B8. TRAZA EN TABLA (requiere rol_soporte o rol_auditoria) ==='
SELECT ocurrido_en, email_intentado, exito, motivo, origen
FROM login_intento
ORDER BY id_intento DESC
LIMIT 10;

\echo ''
\echo '=== B9. DETECCIÓN DE FUERZA BRUTA (>= 3 fallos en 15 minutos) ==='
SELECT * FROM vw_intentos_login_sospechosos;

-- ============================================================================
-- RESULTADO ESPERADO
--   B1  -> 2 filas de producto
--   B2  -> INSERT 0 1 (pedido) + INSERT 0 1 (detalle)
--   B3  -> UPDATE 1
--   B4  -> 3 filas (f, NULL, NULL): la función no distingue la causa
--   B5  -> ERROR: permission denied for table usuario
--   B6  -> ERROR: permission denied to grant role "admin_datos"
--   B7  -> el pedido nuevo y el stock descontado
--   B8  -> 3 filas con motivo 'credenciales_invalidas'  (sólo con rol_soporte)
--   B9  -> 1 fila: maria.gonzalez@foodstore.test, 3 fallos  (sólo con rol_auditoria)
-- En el log: las 9 operaciones con usuario, base, aplicación, IP y timestamp;
-- las dos denegadas además con su ERROR.
-- ============================================================================
