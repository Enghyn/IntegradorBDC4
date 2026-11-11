-- ============================================================================
-- SIMULACRO_INCIDENTE.SQL
-- TP — Unidad 5: Administración y seguridad de Food Store
-- PARTE C — Laboratorio: simulacro de incidente de acceso indebido
--
-- QUÉ ES ESTO
--   Reproduce, de forma controlada y SÓLO contra el entorno de desarrollo, una
--   secuencia de incidente completa en el orden que pide la consigna:
--
--     (1) varios intentos fallidos de inicio de sesión contra fn_autenticar
--     (2) un inicio de sesión exitoso
--     (3) una lectura masiva de la tabla usuario
--     (4) un intento de otorgarle a un rol de bajo privilegio membresía en
--         admin_datos, más tres operaciones reservadas de contraste
--
--   No "simula" el ataque con texto: lo ejecuta. Los errores que se ven son
--   del motor, y el fragmento de log es la evidencia real de lo que pasó.
--
-- ESCENARIO (por qué esta identidad y no otra)
--   El atacante ya tiene la credencial de la CONSOLA DE SOPORTE, que en el
--   esquema de la Parte A es el login admin_datos (hereda rol_soporte y
--   rol_reportes). No tiene credenciales de usuario final, así que las
--   consigue dentro de la misma sesión: fuerza bruta contra fn_autenticar
--   hasta acertar una. Con eso puede leer PII de todos los usuarios.
--
--   Después intenta PERSISTIR: si logra otorgarle admin_datos (o rol_soporte)
--   a app_web, el rol de bajo privilegio de la aplicación, conserva el acceso
--   aunque el equipo revoque la consola de soporte durante la contención.
--   Ese es el motivo realista del intento de escalamiento vertical y lateral.
--
--   Que las cuatro operaciones de (4) FALLEN es el resultado que se espera:
--   la Parte A revocó ADMIN OPTION de todas las membresías y admin_datos es
--   NOSUPERUSER / NOCREATEROLE. Si alguna funcionara, sería un defecto del
--   esquema y hay que reportarlo como hallazgo (ver § 2 de este archivo).
--
-- IDs QUE PARTICIPAN
--   login de sesión ..... admin_datos   (consola de soporte comprometida)
--   rol víctima ......... usuario, 12 filas con nombre, email, teléfono
--   rol de bajo privilegio app_web      (rol_app_lectura + rol_app_escritura)
--   rol objetivo ........ admin_datos   (escalamiento vertical)
--   rol objetivo 2 ...... rol_soporte   (escalamiento lateral: leer PII)
--
-- PREPARACIÓN (una sola vez, en la copia dev, fuera del repositorio)
--   -- a) contraseña sintética para la consola de soporte. NO se versiona:
--   --    acá va un marcador, no la clave real.
--   ALTER ROLE admin_datos PASSWORD '<clave-sintetica-efimera>';
--
--   -- b) en pg_hba.conf, ANTES de las líneas "trust", para que el login de
--   --    soporte pida contraseña como en un entorno real:
--   host all admin_datos 127.0.0.1/32 scram-sha-256
--   host all admin_datos ::1/128        scram-sha-256
--   SELECT pg_reload_conf();
--
-- CÓMO SE EJECUTA (dos invocaciones: ataque y constancia)
--   -- 1) el ataque, con la identidad comprometida
--   psql "host=localhost port=5544 dbname=foodstore_test user=admin_datos" \
--        -v clave_objetivo='<clave-del-usuario-victima>' \
--        -f TP7/sql/simulacro_incidente.sql
--
--   -- 2) la constancia de que el escalamiento falló (superusuario)
--   psql "host=localhost port=5544 dbname=foodstore_test user=postgres" \
--        -v verificar=si -f TP7/sql/simulacro_incidente.sql
--
--   La clave de la víctima se pasa como variable de psql para que no quede
--   escrita en el archivo. Ojo: log_statement = 'all' la va a escribir en el
--   log igual — eso es el hallazgo H1 de la Parte B, y es la razón concreta
--   por la que el fragmento de este simulacro se anonimiza antes de compartirlo.
--
-- DÓNDE QUEDA EL LOG
--   <data_directory>/log/postgresql-<fecha>.log. La ventana se delimita con
--   dos rotaciones, igual que en la Parte B:
--     SELECT pg_rotate_logfile();  -- abre
--     ... este script ...
--     SELECT pg_rotate_logfile();  -- cierra
-- ============================================================================

-- ----------------------------------------------------------------------------
-- GUARDA DE ENTORNO
--   Mismo criterio que roles.sql: nada de esto corre sobre una base cuyo
--   nombre no delate test/dev/local. Override manual:
--     SET tp7.entorno_confirmado = 'si';
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
-- MODO VERIFICACIÓN (paso 2 de la consigna)
--   Se corre como superusuario y sólo imprime el estado de las membresías:
--   es la constancia de que el escalamiento NO ocurrió. No modifica nada.
-- ----------------------------------------------------------------------------
\if :{?verificar}
\echo ''
\echo '=============================================================='
\echo ' CONSTANCIA: ¿el escalamiento de la Parte C efectivamente falló?'
\echo '=============================================================='
\echo ''
\echo '1) Membresías de app_web. Las dos columnas deben dar f (false):'
SELECT 'app_web' AS miembro,
       pg_has_role('app_web', 'admin_datos', 'MEMBER') AS es_admin_datos,
       pg_has_role('app_web', 'rol_soporte',  'MEMBER') AS es_rol_soporte;
\echo ''
\echo '2) Atributos de app_web. Todo debe ser f salvo canlogin:'
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin
FROM pg_roles WHERE rolname = 'app_web';
\echo ''
\echo '3) ¿Existe el rol que el atacante intentó crear? Debe devolver 0:'
SELECT count(*) AS existe_backdoor FROM pg_roles WHERE rolname = 'backdoor';
\echo ''
\echo '3b) Roles de login existentes. Deben ser exactamente los cuatro previstos:'
SELECT string_agg(rolname, ', ' ORDER BY rolname) AS logins
FROM pg_roles WHERE rolcanlogin AND rolname !~ '^pg_';
\echo ''
\echo '4) Membresías completas (para leer el estado final de un vistazo):'
SELECT r.rolname AS rol, m.rolname AS miembro, am.admin_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
ORDER BY r.rolname, m.rolname;
\echo ''
\echo 'VEREDICTO: si (1) da f/f, (2) da f/f/f/f/t y (3) da 0, el esquema de la'
\echo 'Parte A resistió: el atacante pudo leer PII pero NO pudo escalar ni'
\echo 'persistir. Cualquier otro valor es un defecto que hay que corregir.'
\quit
\endif

-- ----------------------------------------------------------------------------
-- SECUENCIA DEL INCIDENTE
--   application_name queda en cada línea del log vía %a y permite aislar el
--   simulacro del resto de la actividad.
-- ----------------------------------------------------------------------------
SET application_name = 'simulacro_parte_c';

\echo ''
\echo '=== S0. CONTEXTO: con qué identidad está corriendo el atacante ==='
SELECT current_user AS login_de_sesion,
       current_database() AS base,
       inet_client_addr() IS NULL AS conexion_local_sin_ip,
       current_setting('application_name') AS app,
       (SELECT string_agg(r.rolname, ', ' ORDER BY r.rolname)
          FROM pg_roles r
         WHERE pg_has_role(current_user, r.oid, 'MEMBER')
           AND r.rolname LIKE 'rol\_%') AS roles_heredados;

-- ============================================================================
-- (1) INTENTOS FALLIDOS DE INICIO DE SESIÓN CONTRA fn_autenticar
--     Cinco intentos, cada uno con una contraseña distinta y equivocada.
--     Es fuerza bruta / password spraying a nivel de aplicación: la función
--     registra cada intento en login_intento y devuelve siempre lo mismo.
-- ============================================================================
\echo ''
\echo '=== S1-S5. FUERZA BRUTA CONTRA fn_autenticar (5 intentos) ==='
\echo '    Todos deben devolver (f, NULL, NULL): no se distingue si el usuario existe.'
SELECT * FROM fn_autenticar('juan.perez@foodstore.test', 'FoodStore2024');
SELECT * FROM fn_autenticar('juan.perez@foodstore.test', 'foodstore');
SELECT * FROM fn_autenticar('juan.perez@foodstore.test', 'FoodStore2026!');
SELECT * FROM fn_autenticar('juan.perez@foodstore.test', 'FoodStore.Dev#2025');
SELECT * FROM fn_autenticar('juan.perez@foodstore.test', 'admin123');

-- ============================================================================
-- (2) INICIO DE SESIÓN EXITOSO
--     La sexta es la buena. Se pasa como variable de psql (:'clave_objetivo')
--     para que la contraseña no esté escrita en el repositorio.
-- ============================================================================
\echo ''
\echo '=== S6. INICIO DE SESIÓN EXITOSO (la sexta contraseña es la correcta) ==='
SELECT * FROM fn_autenticar('juan.perez@foodstore.test', :'clave_objetivo');

-- ============================================================================
-- (3) LECTURA MASIVA DE LA TABLA usuario
--     Primero el atacante pide todo con SELECT * y el motor lo frena en
--     password_hash (permiso por columna de la Parte A). Entonces enumera las
--     columnas permitidas y se lleva la PII completa.
-- ============================================================================
\echo ''
\echo '=== S7. PRIMER INTENTO: SELECT * FROM usuario (debe fallar por password_hash) ==='
SELECT * FROM usuario LIMIT 1;

\echo ''
\echo '=== S8. ENUMERACIÓN: las columnas permitidas, todas las filas ==='
SELECT id_usuario, email, nombre, apellido, telefono, fecha_alta
FROM usuario
ORDER BY id_usuario;

\echo ''
\echo '=== S9. EXFILTRACIÓN: la misma lectura, volcada fuera de la base ==='
\echo '    COPY no necesita más permiso que SELECT. El log registra la sentencia,'
\echo '    NO cuántas filas salieron: esa es la limitación que documenta el informe.'
COPY (
    SELECT id_usuario, email, nombre, apellido, telefono, fecha_alta
    FROM usuario
    ORDER BY id_usuario
) TO STDOUT WITH (FORMAT csv, HEADER true);

-- ============================================================================
-- (4) INTENTO DE ESCALAMIENTO
--     Objetivo: que el rol de bajo privilegio de la aplicación herede
--     admin_datos (vertical) o rol_soporte (lateral, para seguir leyendo PII).
--     Los cuatro deben fallar. Si alguno pasa, es un hallazgo contra la Parte A.
-- ============================================================================
\echo ''
\echo '=== S10. ESCALAMIENTO VERTICAL: GRANT admin_datos TO app_web ==='
GRANT admin_datos TO app_web;

\echo ''
\echo '=== S11. ESCALAMIENTO LATERAL: GRANT rol_soporte TO app_web ==='
GRANT rol_soporte TO app_web;

\echo ''
\echo '=== S12. OPERACIÓN RESERVADA: ALTER ROLE app_web SUPERUSER ==='
ALTER ROLE app_web SUPERUSER;

\echo ''
\echo '=== S13. PERSISTENCIA: CREATE ROLE backdoor LOGIN ==='
CREATE ROLE backdoor LOGIN;

-- ============================================================================
-- RESULTADO ESPERADO
--   S0  -> 1 fila: login_de_sesion = admin_datos, roles_heredados =
--          rol_reportes, rol_soporte
--   S1-S5 -> 5 filas (f, NULL, NULL) y 5 filas nuevas en login_intento
--   S6  -> 1 fila (t, 6, rol_soporte): el atacante ya tiene identidad de usuario
--   S7  -> ERROR: permission denied for table usuario   (por password_hash)
--   S8  -> 12 filas con la PII completa
--   S9  -> COPY 12 (la salida va al cliente, no al log)
--   S10 -> ERROR: permission denied to grant role "admin_datos"
--   S11 -> ERROR: permission denied to grant role "rol_soporte"
--   S12 -> ERROR: must be superuser to alter superuser roles or change
--          superuser attribute
--   S13 -> ERROR: permission denied to create role
--
--   En el log: intentos, éxito, lectura, exfiltración y los cuatro rechazos,
--   cada línea con usuario de sesión, base, aplicación, host y timestamp.
--   La constancia de que nada se otorgó se obtiene con -v verificar=si.
-- ============================================================================
