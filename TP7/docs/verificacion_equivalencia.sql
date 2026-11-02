-- ============================================================================
-- VERIFICACION_EQUIVALENCIA.SQL
-- TP — Unidad 5: Administración y seguridad de Food Store
-- PARTE D — paso 3: ejecutar las dos consultas y verificar que los agregados
--           coinciden, con un control que falle si no coinciden.
--
-- QUÉ HACE ESTE ARCHIVO
--   §1 y §2  Las dos consultas que devolvió el asistente, **literalmente**, sin
--            retoques: una sobre usuario_anon, otra sobre usuario. Se imprimen
--            una después de la otra para poder leerlas lado a lado.
--   §3       La comparación lado a lado en un solo resultado (la que va al
--            informe como "ambos resultados uno junto al otro").
--   §3b      El mismo agregado marginal por rol, sin el mes: es el único lugar
--            donde los conteos no valen todos 1, así que es donde la prueba
--            compara números y no etiquetas.
--   §4       La prueba del asistente (DO con FULL OUTER JOIN + IS DISTINCT
--            FROM): falla ruidosamente si los agregados difieren.
--   §5       Un control independiente del anterior (EXCEPT simétrico = 0), para
--            no depender de una sola forma de comparar.
--   §6       Control negativo 1: una copia mal anonimizada (mes desplazado al
--            azar) y la constancia de que el chequeo **sí** la detecta. Un
--            chequeo que nunca falla no prueba nada.
--   §7       Control negativo 2: por qué la copia guarda la medianoche *local*
--            y no la medianoche UTC. Con UTC, la misma consulta agrupando en
--            hora local se corre un mes.
--   §8       Dominio de validez: la condición exacta bajo la cual agrupar en
--            hora local y normalizar a UTC dan el mismo mes, medida sobre el
--            dato real y probada en el borde con marcas sintéticas.
--   §9       El surrogate id_cliente_anon (la decisión que no toca el agregado
--            pero que hay que poder defender).
--
-- USO
--   psql -U postgres -d foodstore_test -f TP7/docs/verificacion_equivalencia.sql
--   Requiere que sql/usuario_anon.sql se haya corrido antes.
--   No modifica usuario ni usuario_anon: las copias del control negativo son
--   TEMP y desaparecen al cerrar la sesión.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

-- ----------------------------------------------------------------------------
-- 0. CONTEXTO
--    La zona de la sesión es una variable del entorno de verificación, no un
--    detalle: si el servidor estuviera en UTC, este archivo probaría otra cosa.
-- ----------------------------------------------------------------------------
\echo ''
\echo '================================================================'
\echo ' 0. CONTEXTO DE LA VERIFICACIÓN'
\echo '================================================================'

SELECT current_database()                       AS base,
       current_setting('TimeZone')              AS zona_sesion,
       (SELECT count(*) FROM usuario)           AS filas_usuario,
       (SELECT count(*) FROM usuario_anon)      AS filas_anon,
       (SELECT count(*) FROM usuario_anon a
          JOIN usuario u USING (id_usuario))    AS ids_en_comun;

\echo ''
\echo 'Si ids_en_comun no es igual a filas_usuario, la copia está incompleta y'
\echo 'todo lo que sigue mide otra cosa.'

-- ----------------------------------------------------------------------------
-- 1. CONSULTA DEL ASISTENTE SOBRE LA TABLA ANONIMIZADA
--    Texto original. Nota de la decisión central: normaliza a UTC con
--    "fecha_alta AT TIME ZONE 'UTC'" para que date_trunc no dependa del
--    TimeZone de quien consulta.
-- ----------------------------------------------------------------------------
\echo ''
\echo '================================================================'
\echo ' 1. AGREGADO SOBRE usuario_anon  (consulta del asistente)'
\echo '================================================================'

WITH base AS (
    SELECT r.nombre                                                  AS rol,
           date_trunc('month', a.fecha_alta AT TIME ZONE 'UTC')::date AS mes
    FROM usuario_anon a
    JOIN rol r ON r.id_rol = a.id_rol
)
SELECT rol,
       to_char(mes, 'YYYY-MM') AS mes_alta,
       count(*)                AS usuarios
FROM base
GROUP BY rol, mes
ORDER BY mes, rol;

-- ----------------------------------------------------------------------------
-- 2. CONSULTA EQUIVALENTE SOBRE LA TABLA REAL
-- ----------------------------------------------------------------------------
\echo ''
\echo '================================================================'
\echo ' 2. AGREGADO SOBRE usuario  (consulta equivalente del asistente)'
\echo '================================================================'

WITH base AS (
    SELECT r.nombre                                                  AS rol,
           date_trunc('month', u.fecha_alta AT TIME ZONE 'UTC')::date AS mes
    FROM usuario u
    JOIN rol r ON r.id_rol = u.id_rol
)
SELECT rol,
       to_char(mes, 'YYYY-MM') AS mes_alta,
       count(*)                AS usuarios
FROM base
GROUP BY rol, mes
ORDER BY mes, rol;

-- ----------------------------------------------------------------------------
-- 3. LADO A LADO
--    El paso 3 de la consigna pide "adjuntar ambos resultados uno junto al
--    otro". Dos tablas seguidas se pueden leer en paralelo; una sola con las
--    dos columnas y la marca de coincidencia no se puede leer mal.
--    Además del conteo se compara el nombre del rol, que es la etiqueta del
--    agrupamiento: si la copia hubiera perdido o cambiado un id_rol, aparecería
--    acá como una fila de un solo lado.
-- ----------------------------------------------------------------------------
\echo ''
\echo '================================================================'
\echo ' 3. LADO A LADO: cada combinación rol-mes con sus dos conteos'
\echo '================================================================'

WITH anon AS (
    SELECT r.nombre AS rol,
           to_char(date_trunc('month', a.fecha_alta AT TIME ZONE 'UTC'), 'YYYY-MM') AS mes_alta,
           count(*) AS usuarios
    FROM usuario_anon a JOIN rol r ON r.id_rol = a.id_rol
    GROUP BY 1, 2
), real_ AS (
    SELECT r.nombre AS rol,
           to_char(date_trunc('month', u.fecha_alta AT TIME ZONE 'UTC'), 'YYYY-MM') AS mes_alta,
           count(*) AS usuarios
    FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
    GROUP BY 1, 2
)
SELECT coalesce(a.rol, b.rol)            AS rol,
       coalesce(a.mes_alta, b.mes_alta)  AS mes_alta,
       a.usuarios                        AS usuarios_anon,
       b.usuarios                        AS usuarios_real,
       (a.usuarios IS NOT DISTINCT FROM b.usuarios) AS coincide
FROM anon a
FULL OUTER JOIN real_ b ON b.rol = a.rol AND b.mes_alta = a.mes_alta
ORDER BY mes_alta, rol;

\echo ''
\echo 'Las 12 filas deben tener usuarios_anon = usuarios_real y coincide = t.'
\echo 'Una fila con un solo lado (NULL en la otra columna) sería un agrupamiento'
\echo 'que existe en una tabla y no en la otra: tan grave como un conteo distinto.'

-- ----------------------------------------------------------------------------
-- 3b. AGREGADO MARGINAL (por rol, sin el mes)
--    Con 12 filas en 12 combinaciones rol-mes, todos los conteos de §3 valen 1,
--    y "1 = 1" no ejercita nada: la prueba quedaría reducida a comparar
--    conjuntos de etiquetas. Agrupando sólo por rol aparecen grupos de 3 y de 2,
--    y ahí sí se comparan números. No reemplaza a la consulta de la consigna:
--    la complementa para que la verificación no sea trivial.
-- ----------------------------------------------------------------------------
\echo ''
\echo '================================================================'
\echo ' 3b. MARGINAL POR ROL: donde los conteos no son todos 1'
\echo '================================================================'

WITH anon AS (
    SELECT r.nombre AS rol, count(*) AS usuarios
    FROM usuario_anon a JOIN rol r ON r.id_rol = a.id_rol
    GROUP BY 1
), real_ AS (
    SELECT r.nombre AS rol, count(*) AS usuarios
    FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
    GROUP BY 1
)
SELECT coalesce(a.rol, b.rol)                  AS rol,
       coalesce(a.usuarios, 0)                 AS usuarios_anon,
       coalesce(b.usuarios, 0)                 AS usuarios_real,
       (a.usuarios = b.usuarios)               AS coincide
FROM anon a
FULL OUTER JOIN real_ b ON b.rol = a.rol
ORDER BY usuarios_real DESC, rol;

-- ----------------------------------------------------------------------------
-- 4. LA PRUEBA DEL ASISTENTE
--    Texto original, sin cambios. Reporta por excepción: si hay una sola
--    diferencia, aborta la transacción en lugar de imprimir una tabla que hay
--    que mirar a ojo.
-- ----------------------------------------------------------------------------
\echo ''
\echo '================================================================'
\echo ' 4. PRUEBA DE EQUIVALENCIA DEL ASISTENTE (falla si difieren)'
\echo '================================================================'

DO $$
DECLARE
    v_dif     bigint;
    v_detalle text;
BEGIN
    WITH anon AS (
        SELECT r.nombre AS rol,
               date_trunc('month', a.fecha_alta AT TIME ZONE 'UTC')::date AS mes,
               count(*) AS usuarios
        FROM usuario_anon a JOIN rol r ON r.id_rol = a.id_rol
        GROUP BY 1, 2
    ), real_ AS (
        SELECT r.nombre AS rol,
               date_trunc('month', u.fecha_alta AT TIME ZONE 'UTC')::date AS mes,
               count(*) AS usuarios
        FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
        GROUP BY 1, 2
    ), dif AS (
        SELECT coalesce(a.rol, b.rol)                                  AS rol,
               coalesce(a.mes, b.mes)                                  AS mes,
               a.usuarios                                              AS anon,
               b.usuarios                                              AS real
        FROM anon a
        FULL OUTER JOIN real_ b ON b.rol = a.rol AND b.mes = a.mes
        WHERE a.usuarios IS DISTINCT FROM b.usuarios
    )
    SELECT count(*),
           string_agg(format('%s / %s -> anon=%s, real=%s',
                             rol, mes, coalesce(anon::text, 'falta'),
                             coalesce(real::text, 'falta')), ' | ')
      INTO v_dif, v_detalle
    FROM dif;

    IF v_dif > 0 THEN
        RAISE EXCEPTION 'Agregados NO equivalentes (% combinaciones rol-mes distintas): %',
                        v_dif, v_detalle;
    END IF;

    RAISE NOTICE 'OK: los agregados rol-mes son identicos';
END
$$;

-- ----------------------------------------------------------------------------
-- 5. CONTROL INDEPENDIENTE: EXCEPT SIMÉTRICO
--    El asistente eligió FULL OUTER JOIN + IS DISTINCT FROM, y da una
--    alternativa equivalente (EXCEPT ALL en los dos sentidos). Se corren las
--    dos: si dos formas distintas de comparar dan lo mismo, el resultado no es
--    un artefacto del método. Ambas deben dar 0 filas.
-- ----------------------------------------------------------------------------
\echo ''
\echo '================================================================'
\echo ' 5. CONTROL INDEPENDIENTE: EXCEPT simétrico (0 y 0 filas)'
\echo '================================================================'

WITH anon AS (
    SELECT r.nombre AS rol,
           date_trunc('month', a.fecha_alta AT TIME ZONE 'UTC')::date AS mes,
           count(*) AS usuarios
    FROM usuario_anon a JOIN rol r ON r.id_rol = a.id_rol
    GROUP BY 1, 2
), real_ AS (
    SELECT r.nombre AS rol,
           date_trunc('month', u.fecha_alta AT TIME ZONE 'UTC')::date AS mes,
           count(*) AS usuarios
    FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
    GROUP BY 1, 2
), solo_anon AS (
    SELECT 'anon' AS origen, * FROM (SELECT * FROM anon EXCEPT ALL SELECT * FROM real_) x
), solo_real AS (
    SELECT 'real' AS origen, * FROM (SELECT * FROM real_ EXCEPT ALL SELECT * FROM anon) x
)
SELECT origen, rol, mes, usuarios
FROM (SELECT * FROM solo_anon UNION ALL SELECT * FROM solo_real) d
ORDER BY origen, mes, rol;

\echo ''
\echo 'Cero filas arriba = los dos agregados son conjuntos idénticos, no sólo'
\echo 'parecidos. (Nota: EXCEPT ALL compara filas completas, así que cubre los'
\echo 'tres casos: falta a la izquierda, falta a la derecha y conteo distinto.)'

-- ----------------------------------------------------------------------------
-- 6. CONTROL NEGATIVO 1: una copia mal anonimizada
--    "Verificar que coinciden" no vale nada si el chequeo no puede fallar. Se
--    construye una copia donde el mes de alta se desplazó de forma determinista
--    pero arbitraria (el error típico: anonimizar la fecha con un offset "para
--    que no se reconozca") y se corre el mismo control.
--    Es TEMP: no queda nada en la base.
-- ----------------------------------------------------------------------------
\echo ''
\echo '================================================================'
\echo ' 6. CONTROL NEGATIVO 1: copia con el mes desplazado -> el chequeo falla'
\echo '================================================================'

CREATE TEMP TABLE usuario_anon_rota AS
SELECT a.id_usuario,
       a.id_rol,
       a.activo,
       -- Desplazamiento determinista de 0 a 4 meses, distinto por fila.
       date_trunc('month', a.fecha_alta) + (interval '1 month' * ((a.id_usuario * 7) % 5)) AS fecha_alta
FROM usuario_anon a;

\echo 'Desplazamiento aplicado por fila (0 a 4 meses):'
SELECT id_usuario,
       to_char(fecha_alta, 'YYYY-MM') AS mes_en_copia_rota
FROM usuario_anon_rota
ORDER BY id_usuario;

\echo ''
\echo 'El mismo agrupamiento sobre la copia rota, contra la tabla real:'
WITH anon AS (
    SELECT r.nombre AS rol,
           date_trunc('month', a.fecha_alta AT TIME ZONE 'UTC')::date AS mes,
           count(*) AS usuarios
    FROM usuario_anon_rota a JOIN rol r ON r.id_rol = a.id_rol
    GROUP BY 1, 2
), real_ AS (
    SELECT r.nombre AS rol,
           date_trunc('month', u.fecha_alta AT TIME ZONE 'UTC')::date AS mes,
           count(*) AS usuarios
    FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
    GROUP BY 1, 2
), dif AS (
    SELECT coalesce(a.rol, b.rol)     AS rol,
           coalesce(a.mes, b.mes)     AS mes,
           a.usuarios                 AS anon,
           b.usuarios                 AS real
    FROM anon a
    FULL OUTER JOIN real_ b ON b.rol = a.rol AND b.mes = a.mes
    WHERE a.usuarios IS DISTINCT FROM b.usuarios
)
SELECT count(*) AS combinaciones_distintas
FROM dif;

\echo ''
\echo 'Y el detalle: "falta" es un agrupamiento que existe en una tabla y no en la'
\echo 'otra; un par de números distintos sería la misma combinación con otro conteo.'
WITH anon AS (
    SELECT r.nombre AS rol,
           date_trunc('month', a.fecha_alta AT TIME ZONE 'UTC')::date AS mes,
           count(*) AS usuarios
    FROM usuario_anon_rota a JOIN rol r ON r.id_rol = a.id_rol
    GROUP BY 1, 2
), real_ AS (
    SELECT r.nombre AS rol,
           date_trunc('month', u.fecha_alta AT TIME ZONE 'UTC')::date AS mes,
           count(*) AS usuarios
    FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
    GROUP BY 1, 2
)
SELECT coalesce(a.rol, b.rol)                 AS rol,
       to_char(coalesce(a.mes, b.mes), 'YYYY-MM') AS mes_alta,
       coalesce(a.usuarios::text, 'falta')    AS en_copia_rota,
       coalesce(b.usuarios::text, 'falta')    AS en_real
FROM anon a
FULL OUTER JOIN real_ b ON b.rol = a.rol AND b.mes = a.mes
WHERE a.usuarios IS DISTINCT FROM b.usuarios
ORDER BY mes_alta, rol;

\echo ''
\echo 'combinaciones_distintas > 0: el chequeo detectó una copia que conserva las'
\echo 'filas, los roles y hasta los totales por rol, pero destruyó la distribución'
\echo 'temporal. Es exactamente lo que este paso de la consigna tiene que poder'
\echo 'demostrar que NO pasa con usuario_anon.'

-- ----------------------------------------------------------------------------
-- 7. CONTROL NEGATIVO 2: por qué la medianoche es LOCAL y no UTC
--    usuario_anon guarda el día 1 a las 00:00 de la zona del servidor
--    (America/Buenos_Aires, -03). Se construye la alternativa "obvia" — guardar
--    00:00 UTC — y se mide qué le pasa a la MISMA consulta cuando agrupa en
--    hora local: a las 00:00 UTC en Buenos Aires todavía es el día anterior a
--    las 21:00, así que date_trunc se va al mes anterior.
--    Esta es la decisión que hace que la equivalencia funcione, y por eso hay
--    que mostrarla y no sólo afirmarla.
-- ----------------------------------------------------------------------------
\echo ''
\echo '================================================================'
\echo ' 7. CONTROL NEGATIVO 2: copia truncada en UTC vs. agrupamiento local'
\echo '================================================================'

CREATE TEMP TABLE usuario_anon_utc AS
SELECT a.id_usuario,
       a.id_rol,
       -- El "error natural": normalizar a UTC y guardar esa medianoche.
       (date_trunc('month', a.fecha_alta AT TIME ZONE 'UTC') AT TIME ZONE 'UTC') AS fecha_alta
FROM usuario_anon a;

\echo 'Con la copia actual (medianoche local), las dos convenciones coinciden:'
SELECT count(*) FILTER (
           WHERE date_trunc('month', a.fecha_alta)
              <> date_trunc('month', a.fecha_alta AT TIME ZONE 'UTC')::timestamp
       ) AS filas_donde_difieren_local_vs_utc
FROM usuario_anon a;

\echo ''
\echo 'Con la copia guardada a medianoche UTC, la convención local se corre un mes:'
SELECT count(*) FILTER (
           WHERE date_trunc('month', a.fecha_alta)
              <> date_trunc('month', a.fecha_alta AT TIME ZONE 'UTC')::timestamp
       ) AS filas_donde_difieren_local_vs_utc
FROM usuario_anon_utc a;

\echo ''
\echo 'Y estos son los meses del agregado sobre la copia UTC si alguien agrupa'
\echo 'en hora local (la consulta "ingenua", sin normalizar):'
WITH base AS (
    SELECT r.nombre                                     AS rol,
           date_trunc('month', a.fecha_alta)::date      AS mes
    FROM usuario_anon_utc a
    JOIN rol r ON r.id_rol = a.id_rol
)
SELECT rol, to_char(mes, 'YYYY-MM') AS mes_alta, count(*) AS usuarios
FROM base
GROUP BY rol, mes
ORDER BY mes, rol;

\echo ''
\echo 'Comparar esos meses con los de §1: son los anteriores. Esa es la razón por'
\echo 'la que el script guarda la medianoche en la zona del servidor y no en UTC,'
\echo 'y la razón por la que la equivalencia se sostiene con las dos convenciones.'

-- ----------------------------------------------------------------------------
-- 8. DOMINIO DE VALIDEZ
--    La equivalencia no es incondicional: depende de que agrupar en hora local
--    y normalizar a UTC den el mismo mes. La condición exacta NO es "la hora
--    está entre las 21:00 y las 00:00" (un 1.º de mes a las 22:00 se corre al
--    día 2 pero sigue en el mismo mes): es que el corrimiento de +3 h cruce el
--    fin de mes, es decir, que la marca caiga el ÚLTIMO día del mes a partir de
--    las 21:00 locales.
--    Se mide la condición exacta sobre el dato real, y se prueba el borde con
--    cuatro marcas sintéticas.
-- ----------------------------------------------------------------------------
\echo ''
\echo '================================================================'
\echo ' 8. DOMINIO DE VALIDEZ: ¿local y UTC dan el mismo mes?'
\echo '================================================================'

\echo 'Sobre el dato real (los dos conteos deben dar 0):'
SELECT count(*) FILTER (
           WHERE date_trunc('month', fecha_alta)
              <> date_trunc('month', fecha_alta AT TIME ZONE 'UTC')::timestamp
       ) AS altas_que_cambian_de_mes,
       count(*) FILTER (
           WHERE date_trunc('month', ultimo_acceso)
              <> date_trunc('month', ultimo_acceso AT TIME ZONE 'UTC')::timestamp
       ) AS accesos_que_cambian_de_mes
FROM usuario;

\echo ''
\echo 'El borde exacto, con cuatro marcas sintéticas (la condición se cumple o no'
\echo 'según el día, no sólo según la hora):'
WITH probe (caso, momento) AS (
    VALUES ('último día, 20:59 (antes del corrimiento)', timestamptz '2026-11-30 20:59:59-03'),
           ('último día, 21:00 (cruza el mes)',          timestamptz '2026-11-30 21:00:00-03'),
           ('día 15, 22:30 (cruza el día, no el mes)',   timestamptz '2026-11-15 22:30:00-03'),
           ('31/12, 23:59 (cruza el año)',               timestamptz '2026-12-31 23:59:59-03')
)
SELECT caso,
       to_char(momento, 'YYYY-MM-DD HH24:MI:SS')                    AS local,
       to_char(momento AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS')  AS utc,
       to_char(date_trunc('month', momento), 'YYYY-MM')              AS mes_local,
       to_char(date_trunc('month', momento AT TIME ZONE 'UTC'), 'YYYY-MM') AS mes_utc,
       (date_trunc('month', momento)
        = date_trunc('month', momento AT TIME ZONE 'UTC')::timestamp) AS coincide
FROM probe
ORDER BY momento;

\echo ''
\echo 'Queda a la vista el error que este chequeo evita: "un día 15 a las 22:30"'
\echo 'parece el caso peligroso y no lo es (cambia el día, no el mes); el caso que'
\echo 'rompe la equivalencia es el último día del mes después de las 21:00. Con el'
\echo 'dato de hoy ninguno de los 12 usuarios cae ahí, y por eso la equivalencia'
\echo 'vale con las DOS convenciones. Es una condición del DATO, no del script.'
\echo ''
\echo 'Dato al pasar, verificable: el ultimo_acceso de u6 es el instante del login'
\echo 'exitoso del simulacro de la Parte C (S6). O sea que la traza que ese script'
\echo 'dejó en la tabla es parte de lo que se está anonimizando acá.'

-- ----------------------------------------------------------------------------
-- 9. EL SURROGATE id_cliente_anon
--    Se prueba con filas ficticias en lugar de tocar usuario: interesa la
--    expresión de ventana, y las 12 filas reales tienen id_cliente en NULL, así
--    que sobre ellas no probaría nada.
--    Lo que tiene que cumplirse: mismo cliente -> mismo número, clientes
--    distintos -> números distintos, sin cliente -> NULL, y ningún número
--    igual a un cliente.id_cliente que exista.
-- ----------------------------------------------------------------------------
\echo ''
\echo '================================================================'
\echo ' 9. SURROGATE id_cliente_anon (filas ficticias, sin tocar usuario)'
\echo '================================================================'

WITH ficticio (id_usuario, id_cliente) AS (
    VALUES (901::bigint, 7::bigint), (902, 7), (903, 9),
           (904, NULL), (905, 3), (906, 3)
)
SELECT id_usuario,
       id_cliente,
       CASE WHEN id_cliente IS NULL THEN NULL
            ELSE dense_rank() OVER (ORDER BY id_cliente)
       END AS id_cliente_anon
FROM ficticio
ORDER BY id_usuario;

\echo ''
\echo 'Esperado: 901 y 902 comparten número (mismo cliente 7); 903 recibe otro;'
\echo '905 y 906 comparten otro (cliente 3); 904 queda NULL. La cantidad de'
\echo 'números distintos es la cantidad de clientes distintos: la cardinalidad se'
\echo 'conserva y el valor original no aparece en ningún lado.'

\echo ''
\echo '================================================================'
\echo ' FIN: si §4 dio NOTICE OK, §5 devolvió 0 filas, §6 dio diferencias y §7 y'
\echo ' §8 dieron 0, la equivalencia está demostrada y el chequeo tiene dientes.'
\echo '================================================================'
