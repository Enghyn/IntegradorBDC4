# Verificación de equivalencia — Parte D: anonimización sin distorsión

> **TP — Unidad 5: Administración y seguridad de Food Store (PostgreSQL 17.11)**
> Entorno: clúster descartable en el puerto 5544, base `foodstore_test`, `TimeZone =
> America/Buenos_Aires`. **Nunca** producción.

Esta parte tiene una trampa que conviene nombrar antes de empezar: *anonimizar* y
*demostrar que anonimizar no distorsionó* son dos trabajos distintos, y el segundo es
el que se puede hacer mal sin que nadie lo note. Una copia con nombres falsos pero con
la distribución de altas destruida pasa cualquier revisión visual —tiene 12 filas,
roles válidos, fechas plausibles— y arruina todos los reportes que se hagan sobre ella.

Por eso el entregable no es sólo `usuario_anon`: es el par
`sql/usuario_anon.sql` + `docs/verificacion_equivalencia.sql`, donde el segundo es un
chequeo que **falla ruidosamente** si el primero miente. Y como un chequeo que nunca
falla no prueba nada, también incluye dos copias deliberadamente rotas en las que el
chequeo **sí** falla.

| Qué se verifica | Resultado |
|---|---|
| Autocontroles de la copia (PII, unicidad, formato, generalización, dimensiones) | 5/5 en verde |
| Determinismo (dos corridas del script) | `checksum_tabla` idéntico: `8e5339ae3a46cafa72b815674cb3c5f3` |
| Agregado por rol y mes, lado a lado | 12/12 combinaciones coinciden |
| Prueba del asistente (`DO` + `FULL OUTER JOIN` + `IS DISTINCT FROM`) | `NOTICE: OK` |
| Control independiente (`EXCEPT` simétrico) | 0 filas |
| Control negativo 1 (mes desplazado al azar) | **20 combinaciones distintas** → el chequeo falla |
| Control negativo 2 (copia truncada en UTC) | **12 filas** se corren de mes |
| Dominio de validez (¿local y UTC dan el mismo mes?) | 0 altas, 0 accesos cambian de mes |

---

## 1. Qué se le pidió al asistente

La consigna pide «especificarle a OpenCode, con precisión, una consulta de agregación
sobre `usuario_anon` y pedirle la equivalente sobre la tabla real». Se le pasó **el
esquema y nada más**: sin filas, sin resultados, sin el enunciado del TP. La restricción
importa porque el punto de esta parte es que un asistente puede ayudar con SQL sin ver
un solo dato personal — exactamente lo contrario de lo que hizo la Parte C.

**Prompt enviado** (texto íntegro):

```
Contexto: trabajo práctico de base de datos (PostgreSQL 17). Tengo una tabla con datos
personales y una copia anonimizada de esa tabla. Necesito dos consultas de agregación y
una forma de probar que son equivalentes.

Esquema real: [CREATE TABLE rol / usuario, sin datos]

La tabla anonimizada es una copia con el mismo id_usuario, la misma PK y la misma FK a
rol, y con estos reemplazos: email, nombre, apellido y telefono son sintéticos;
password_hash es un hash de una clave ficticia; fecha_alta está truncada al primer día
de su mes (se conserva la zona horaria); ultimo_acceso también truncado al mes;
id_cliente ya no es el original sino un surrogate que conserva la cardinalidad.
id_usuario, id_rol y activo quedan iguales.

Necesito, en SQL válido para PostgreSQL 17:
1. Una consulta de agregación sobre la tabla anonimizada (usuario_anon) que devuelva
   cantidad de usuarios por rol y por mes de alta. Usá el nombre del rol (no el id) y un
   formato de mes que se lea bien y ordene bien.
2. La consulta equivalente sobre la tabla real (usuario).
3. Una consulta que demuestre que los dos resultados agregados son idénticos, no sólo
   que "se parecen": que falle de forma visible si difieren.

Explicá en una o dos frases cada decisión que tomes (por qué ese join, por qué ese
formato de fecha, por qué esa forma de comparar). No inventes datos ni ejecutes nada.
```

**Lo que devolvió** está transcripto literal en §3 y §5, y sus decisiones resultaron
correctas en lo sustantivo. La más importante:

> «`date_trunc` sobre `timestamptz` depende del `TimeZone` de la sesión, así que el mismo
> dato podría caer en meses distintos según quién consulte; fijando UTC el agrupamiento es
> determinista.»

Eso es cierto y es la mitad del problema. La otra mitad la declaró como advertencia, casi
de paso, al final:

> «Si la copia se truncó al mes usando otra zona horaria, este mismo check lo va a marcar:
> en ese caso hay que alinear explícitamente la zona en las tres consultas.»

No lo dijo por decir: **eso es exactamente lo que pasa si uno guarda la medianoche UTC**
en lugar de la local, y está medido en §6.2 con 12 filas de diferencia. Es el tipo de
observación que hace que valga la pena leer la respuesta completa en vez de copiar la
primera consulta.

---

## 2. `usuario_anon`: qué conserva y qué reemplaza

La regla que ordena la tabla: **se conserva lo que no identifica a nadie y hace falta
para que un agregado siga diciendo la verdad; se reemplaza todo lo demás.**

| Columna | Destino | Motivo |
|---|---|---|
| `id_usuario` | igual | surrogate; no es PII y es la PK |
| `id_rol` | igual | es la dimensión del agregado |
| `activo` | igual | se filtra en los reportes |
| `fecha_alta` | 1.er día de su mes | generalización: el día no hace falta para «por mes» |
| `ultimo_acceso` | 1.er día de su mes (preserva `NULL`) | ídem, y es dato de conducta |
| `email` | `usuario00N@ejemplo.test` | PII directa |
| `nombre` / `apellido` | catálogo sintético por índice | PII directa |
| `telefono` | `+54 11 5555-NNNN` | PII directa; se conserva el formato para que el tipo siga sirviendo |
| `password_hash` | bcrypt de una clave ficticia | una credencial, aunque sea hash, no se copia |
| `id_cliente` | `id_cliente_anon` (surrogate) | conserva la cardinalidad, rompe el join con `cliente` |

Sobre el surrogate de cliente: **no es** `cliente.id_cliente`. Es un `dense_rank()` sobre
los clientes distintos, así que «cuántos usuarios comparten cliente» sigue siendo cierto y
«de qué cliente son» deja de serlo. Borrar la columna habría sido peor: rompe cualquier
agregado por cliente. Hoy los 12 registros tienen `id_cliente` en `NULL`, así que la regla
está escrita para el esquema que viene, no para el dato de hoy — y eso se declara (§8).

**Determinismo.** No hay `random()` en ningún lado: los nombres salen de un catálogo
indexado por `id_usuario` y el hash de un bcrypt con sal derivada de `md5('tp7-anon-'||id)`.
El script imprime un checksum de la tabla entera; dos corridas dan lo mismo:

```
 hashes_bcrypt_12 |          checksum_tabla
------------------+----------------------------------
               12 | 8e5339ae3a46cafa72b815674cb3c5f3
```

### 2.1 Autocontroles de la copia (salida real)

```
3.a) PII: ningún valor de la tabla original sobrevive en la copia.
     (los cuatro conteos deben dar 0)
 emails_reales | nombres_reales | apellidos_reales | telefonos_reales
---------------+----------------+------------------+------------------
             0 |              0 |                0 |                0

3.b) Unicidad: email único y un hash por fila (12 distintos).
 filas | emails_distintos | hashes_distintos
-------+------------------+------------------
    12 |               12 |               12

3.c) Formato y determinismo: todos los hashes son bcrypt costo 12 ...
 hashes_bcrypt_12 |          checksum_tabla
------------------+----------------------------------
               12 | 8e5339ae3a46cafa72b815674cb3c5f3

3.d) Generalización: toda fecha_alta está el día 1 de su mes.
 filas_con_dia_distinto_de_1
-----------------------------
                           0

3.e) Dimensiones conservadas (id_rol / activo / mes): 0 diferencias.
 diferencias_dimensiones
-------------------------
                       0
```

`3.a` es el control que evita el error más común de esta parte: anonimizar el email y
**olvidar** que el nombre ya está en la tabla de al lado. Compara contra la tabla real
fila por fila —no contra una lista de valores «prohibidos»— así que no depende de que a
alguien se le ocurra cuál mirar.

`3.e` es el que habilita todo lo demás: si las dimensiones se hubieran tocado, la
equivalencia de §3 sería una casualidad.

---

## 3. Las dos consultas (texto del asistente, sin retoques)

### 3.1 Sobre `usuario_anon`

```sql
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
```

### 3.2 La equivalente sobre `usuario`

```sql
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
```

Las dos son la misma consulta con una letra cambiada, y eso es correcto: si el SQL
tuviera que adaptarse a la copia, la comparación ya no mediría si la copia conserva la
información, mediría si alguien escribió dos consultas distintas.

---

## 4. Los dos resultados, lado a lado (consigna, paso 3)

```
        rol        | mes_alta | usuarios_anon | usuarios_real | coincide
-------------------+----------+---------------+---------------+----------
 rol_soporte       | 2024-02  |             1 |             1 | t
 rol_soporte       | 2024-03  |             1 |             1 | t
 rol_reportes      | 2024-05  |             1 |             1 | t
 rol_app_lectura   | 2024-07  |             1 |             1 | t
 rol_app_escritura | 2024-09  |             1 |             1 | t
 rol_etl           | 2024-11  |             1 |             1 | t
 rol_auditoria     | 2025-01  |             1 |             1 | t
 rol_soporte       | 2025-03  |             1 |             1 | t
 rol_reportes      | 2025-06  |             1 |             1 | t
 rol_app_lectura   | 2025-09  |             1 |             1 | t
 rol_app_escritura | 2026-01  |             1 |             1 | t
 rol_etl           | 2026-03  |             1 |             1 | t
(12 rows)
```

Y esto es una debilidad del conjunto de datos, no una virtud del método: **12 filas en 12
combinaciones significa que todos los conteos valen 1**, y «1 = 1» no ejercita nada. La
prueba quedaría reducida a comparar el conjunto de etiquetas. Se agrega el marginal por
rol, donde sí hay grupos de 3 y de 2:

```
        rol        | usuarios_anon | usuarios_real | coincide
-------------------+---------------+---------------+----------
 rol_soporte       |             3 |             3 | t
 rol_app_escritura |             2 |             2 | t
 rol_app_lectura   |             2 |             2 | t
 rol_etl           |             2 |             2 | t
 rol_reportes      |             2 |             2 | t
 rol_auditoria     |             1 |             1 | t
(6 rows)
```

---

## 5. La verificación, por tres caminos independientes

### 5.1 La prueba del asistente (falla si difieren)

```sql
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
        SELECT coalesce(a.rol, b.rol)     AS rol,
               coalesce(a.mes, b.mes)     AS mes,
               a.usuarios                 AS anon,
               b.usuarios                 AS real
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
```

Resultado:

```
NOTICE:  OK: los agregados rol-mes son identicos
DO
```

El acierto de diseño está en **reportar por excepción y no por tabla**: una tabla de
resultados hay que mirarla, una excepción hay que atenderla. Y como está pensada para
correr en un script, el asistente agregó la condición que la vuelve útil en CI: `psql -v
ON_ERROR_STOP=1`, sin la cual psql imprime el error y devuelve código 0 igual.

### 5.2 Control independiente: `EXCEPT` simétrico

```sql
WITH anon AS (...), real_ AS (...),
solo_anon AS (SELECT 'anon' AS origen, * FROM (SELECT * FROM anon EXCEPT ALL SELECT * FROM real_) x),
solo_real AS (SELECT 'real' AS origen, * FROM (SELECT * FROM real_ EXCEPT ALL SELECT * FROM anon) x)
SELECT origen, rol, mes, usuarios
FROM (SELECT * FROM solo_anon UNION ALL SELECT * FROM solo_real) d
ORDER BY origen, mes, rol;
```

```
 origen | rol | mes | usuarios
--------+-----+-----+----------
(0 rows)
```

Se corre porque es una forma de comparar **distinta** —conjuntos, no join— y dos métodos
independientes que coinciden valen más que uno solo. `EXCEPT ALL` compara filas completas,
así que cubre los tres modos de falla a la vez: una combinación que sólo está en un lado,
una que sobra, y la misma combinación con otro conteo.

### 5.3 Lado a lado con la marca de coincidencia

Está en §4 (`coincide = t` en las 12 filas). Es la misma información, pero es la que se
puede mostrar a alguien que no va a leer SQL: una columna que dice `t` doce veces no
necesita interpretación.

---

## 6. Los controles negativos: probar que el chequeo tiene dientes

Un verificador que devuelve «OK» siempre es un adorno. Para saber si este sirve hay que
romper la copia a propósito y ver si lo nota. Se rompe de dos maneras distintas, porque
son los dos errores que se cometen de verdad.

### 6.1 Copia con el mes desplazado «para que no se reconozca»

El error clásico: en vez de generalizar, se aplica un offset determinista a la fecha
porque «así el dato original no se puede recuperar». Se conservan las filas, los roles y
hasta los totales por rol; se destruye la serie temporal.

```
El mismo agrupamiento sobre la copia rota, contra la tabla real:
 combinaciones_distintas
-------------------------
                      20

        rol        | mes_alta | en_copia_rota | en_real
-------------------+----------+---------------+---------
 rol_soporte       | 2024-02  | falta         | 1
 rol_soporte       | 2024-03  | falta         | 1
 rol_reportes      | 2024-05  | falta         | 1
 rol_soporte       | 2024-05  | 1             | falta
 rol_soporte       | 2024-06  | 1             | falta
 rol_app_lectura   | 2024-07  | falta         | 1
 rol_reportes      | 2024-08  | 1             | falta
 rol_app_escritura | 2024-09  | falta         | 1
 rol_app_lectura   | 2024-11  | 1             | falta
 rol_etl           | 2024-11  | falta         | 1
 rol_app_escritura | 2024-12  | 1             | falta
 rol_etl           | 2025-03  | 1             | falta
 rol_reportes      | 2025-06  | falta         | 1
 rol_reportes      | 2025-07  | 1             | falta
 rol_app_lectura   | 2025-09  | falta         | 1
 rol_app_lectura   | 2025-11  | 1             | falta
 rol_app_escritura | 2026-01  | falta         | 1
 rol_app_escritura | 2026-02  | 1             | falta
 rol_etl           | 2026-03  | falta         | 1
 rol_etl           | 2026-05  | 1             | falta
(20 rows)
```

Veinte filas de diferencia. El chequeo **no** dijo «OK». Eso es lo que convierte el
resultado de §4 en una afirmación con contenido.

### 6.2 Copia truncada en la medianoche UTC

El error más sutil, y el que el asistente anticipó: guardar `00:00 UTC` en lugar de
`00:00` local parece más «internacional» y es más prolijo. En Buenos Aires (-03) esa
marca cae a las 21:00 del día anterior, así que una consulta que agrupa en hora local se
corre un mes entero.

```
Con la copia actual (medianoche local), las dos convenciones coinciden:
 filas_donde_difieren_local_vs_utc
-----------------------------------
                                 0

Con la copia guardada a medianoche UTC, la convención local se corre un mes:
 filas_donde_difieren_local_vs_utc
-----------------------------------
                                12
```

Y el agregado «ingenuo» —sin normalizar, agrupando en hora local— sobre esa copia da los
meses anteriores a los de §4: `2024-01` donde debería decir `2024-02`, `2024-12` donde
`2025-01`, y así las doce. **Todas las etiquetas corridas, ningún conteo mal**: el tipo de
error que no rompe nada y hace que el informe de gestión hable del mes equivocado.

De acá sale la decisión que quedó en el script: `usuario_anon` guarda el día 1 a las
`00:00` **de la zona del servidor**. Con esa convención, la medianoche local es `03:00 UTC`
del **mismo día**, y por lo tanto agrupar en local y normalizar a UTC dan el mismo mes.
No es una preferencia estética: es la única de las dos que hace que la equivalencia valga
para las dos convenciones, y está medido.

---

## 7. Dominio de validez: cuándo esto dejaría de valer

La equivalencia entre las dos convenciones no es incondicional. La condición exacta **no**
es «la hora está entre las 21:00 y las 00:00» —un 1.º de mes a las 22:00 se corre al día 2
pero sigue en el mismo mes—, sino que el corrimiento de +3 h **cruce el fin de mes**: la
marca tiene que caer el **último día del mes a partir de las 21:00** locales. Medido sobre
el dato real y probado en el borde:

```
Sobre el dato real (los dos conteos deben dar 0):
 altas_que_cambian_de_mes | accesos_que_cambian_de_mes
--------------------------+----------------------------
                        0 |                          0

                   caso                    |        local        |         utc         | mes_local | mes_utc | coincide
-------------------------------------------+---------------------+---------------------+-----------+---------+----------
 día 15, 22:30 (cruza el día, no el mes)   | 2026-11-15 22:30:00 | 2026-11-16 01:30:00 | 2026-11  | 2026-11 | t
 último día, 20:59 (antes del corrimiento) | 2026-11-30 20:59:59 | 2026-11-30 23:59:59 | 2026-11  | 2026-11 | t
 último día, 21:00 (cruza el mes)          | 2026-11-30 21:00:00 | 2026-12-01 00:00:00 | 2026-11  | 2026-12 | f
 31/12, 23:59 (cruza el año)               | 2026-12-31 23:59:59 | 2027-01-01 02:59:59 | 2026-12  | 2027-01 | f
```

Las cuatro filas desarman la intuición: **es una condición del día, no de la hora.** El caso
que parece peligroso —un día 15 a las 22:30— cambia el día y no el mes; el último día del
mes a las 20:59 todavía no cruza; recién a las 21:00 de ese último día se rompe. Con los
datos de hoy ninguna de las 12 altas ni de los 2 accesos cae ahí, y por eso la equivalencia
se sostiene con las dos convenciones. Si mañana entra un usuario el 31 de enero a las
22:00, `usuario_anon` seguiría siendo correcto —guarda la medianoche local del 1.º de
febrero— pero una consulta que normalice a UTC lo contaría en enero. Queda declarado porque
es el único punto donde el resultado depende del dato y no del método.

Un detalle que apareció midiendo: el `ultimo_acceso` de `u6` es
`2026-11-01 21:21:39.308851-03`, que es **exactamente** el instante del login exitoso del
simulacro de la Parte C (`fn_autenticar` actualiza esa columna). Es decir que la traza que
dejó el incidente es parte de lo que esta parte anonimiza. El ciclo del TP se cierra solo.

---

## 8. Qué **no** demuestra esta verificación

Declararlo es parte del trabajo, porque un «verificado» sin alcance se lee como «todo».

1. **Demuestra equivalencia de agregados, no fidelidad fila por fila.** Es por diseño: la
   copia existe para que las filas no se puedan aparear. Pero conviene ser explícito — si
   se intercambiaran los meses de dos usuarios del **mismo** rol, el conjunto de
   combinaciones rol-mes no cambiaría y este chequeo no lo vería. Lo que se prueba es que
   la copia sirve para agregar, no que sea una copia exacta.
2. **Nada dice sobre las columnas que reemplaza.** Que `email` y `nombre` sean sintéticos
   lo verifica `3.a`, no la equivalencia. Son dos pruebas distintas y hacen falta las dos.
3. **El surrogate `id_cliente_anon` no está ejercitado contra datos reales**: los 12
   registros tienen `id_cliente` en `NULL`. Se prueba la expresión con filas ficticias
   (`901/902 → 2`, `903 → 3`, `905/906 → 1`, `904 → NULL`), que es lo que se puede probar
   hoy. Queda pendiente para cuando la tabla tenga vínculos.
4. **La equivalencia vale para `id_rol`, `activo` y el mes de `fecha_alta`.** Agrupar por
   `email`, `telefono` o `id_cliente_anon` daría diferencias esperadas, no un bug: son las
   columnas que la anonimización rompe a propósito.
5. **`usuario_anon` no es una tabla de producción.** No tiene dueño propio ni permisos
   propios: se recrea desde cero en cada corrida. Si esto dejara de ser un TP, el
   `DROP TABLE` del encabezado tendría que ir detrás de la guarda de entorno que ya tiene
   —y detrás de un backup.

---

## 9. Qué información de Food Store no debería salir hacia una IA sin anonimizar

Hoy no deberían salir hacia un asistente los datos identificables de las cuentas de
`usuario` —`email`, `nombre`, `apellido`, `telefono`, `fecha_alta` y `ultimo_acceso`— ni
`password_hash`, aunque sea un hash: la combinación de nombre, teléfono y fecha de alta
reidentifica a personas reales, y el hash es una credencial que se puede atacar offline sin
dejar rastro en el servidor. Tampoco deberían salir los datos comerciales que cuelgan de
esas cuentas —`cliente` con su nombre, email y teléfono, y el historial de compras que se
vincula por `id_cliente`—, que es justo la parte del negocio que el atacante de la Parte C
no llegó a tocar y que por eso nadie está mirando. Lo que sí puede salir es lo que esta
parte demuestra que se puede compartir sin pérdida: consultas, esquema y agregados por rol
y por mes; la regla no es «no pasarle datos a la IA», es **no pasarle filas**.

---

## 10. Cómo reproducirlo

```bash
# 1. la copia anónima (idempotente; imprimen los 5 autocontroles y el checksum)
psql -U postgres -d foodstore_test -f TP7/sql/usuario_anon.sql

# 2. la verificación (sólo lee usuario y usuario_anon; las copias rotas son TEMP)
psql -U postgres -d foodstore_test -f TP7/docs/verificacion_equivalencia.sql
```

El script de verificación **no modifica** `usuario` ni `usuario_anon`: las dos copias
deliberadamente rotas son `TEMP` y desaparecen al cerrar la sesión. Se puede correr sobre
cualquier instancia con `usuario_anon` cargada, incluida una de producción, sin riesgo —
aunque por la regla del proyecto igual se corre sobre `test`/`dev`/`local`.
