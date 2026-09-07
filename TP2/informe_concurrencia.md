# Informe de Concurrency — Base de datos foodstore_test

Autor: Enzo Giaquinta
Comision: 4
Legajo: 53884
Fecha: 2026-08-31
Base de datos: foodstore_test (PostgreSQL 17, puerto 5433)
Tabla de prueba: test (id, nombre, monto, estado)
Datos iniciales: 3 filas (Producto A monto 100, Producto B monto 250, Producto C monto 75, todas con estado activo)

---

## Escenario 1: Lectura No Repetible

### Reproduccion con Read Committed

Sesion 1 abrio una transaccion y ejecuto SELECT sobre la fila id=1, obteniendo monto=100.00. Mientras la transaccion seguia abierta, Sesion 2 ejecuto un UPDATE que cambio el monto de esa misma fila a 999.99 y hizo COMMIT. Luego, Sesion 1 repitió exactamente la misma consulta SELECT sobre id=1. El resultado这一次 devolvio monto=999.99. Es decir, la misma consulta ejecutada dos veces dentro de la misma transaccion devolvio resultados distintos. Este fenomeno se conoce como lectura no repetible.

### Explicacion

Con Read Committed, que es el nivel de aislamiento por defecto en PostgreSQL, cada SELECT dentro de una transaccion lee el ultimo snapshot committeado en el momento exacto de ejecutarse. Cuando Sesion 2 ejecuta UPDATE y COMMIT mientras Sesion 1 sigue abierta, la segunda lectura de Sesion 1 ve los cambios que Sesion 2 ya confirmo. Por eso el monto cambio de 100.00 a 999.99. Para evitar este problema se debe usar REPEATABLE READ o SERIALIZABLE, que garantizan que todas las lecturas dentro de una transaccion vean el mismo snapshot del momento en que la transaccion comenzo.

### Verificacion con REPEATABLE READ

Se resetearon los datos (monto de vuelta a 100.00). Luego Sesion 1 abrio una transaccion con ISOLATION LEVEL REPEATABLE READ y ejecuto SELECT sobre id=1, obteniendo monto=100.00. Sesion 2 nuevamente hizo UPDATE a 999.99 y COMMIT. Cuando Sesion 1 repitio la misma consulta, el resultado siguio siendo monto=100.00. No cambio. Esto confirma que REPEATABLE READ resuelve el problema de lectura no repetible, porque todas las lecturas de la transaccion usan el mismo snapshot tomado al inicio.

---

## Escenario 2: Lectura Fantasma

### Reproduccion con Read Committed

Sesion 1 abrio una transaccion y ejecuto SELECT COUNT(*) WHERE estado='activo', obteniendo 3. Mientras la transaccion seguia abierta, Sesion 2 inserto una fila nueva (Producto D con estado activo) y hizo COMMIT. Cuando Sesion 1 repitio el mismo COUNT, el resultado devolvio 4. Aporto una fila que no existia cuando se hizo la primera lectura. Esta fila nueva se llama fila fantasma.

### Explicacion

Con Read Committed, la segunda ejecucion del COUNT ve las filas insertadas y committeadas por Sesion 2 despues de la primera lectura. La fila insertada por Sesion 2 es una fila fantasma: no existia cuando se hizo la primera consulta pero aparece en la segunda. Para evitar lecturas fantasma se debe usar REPEATABLE READ o SERIALIZABLE. En PostgreSQL con REPEATABLE READ, las consultas repetidas dentro de la misma transaccion usan el mismo snapshot, por lo que filas insertadas por otras transacciones no aparecen hasta que la transaccion actual termine.

### Verificacion con REPEATABLE READ

Se elimino la fila fantasma (Producto D). Sesion 1 abrio una transaccion con ISOLATION LEVEL REPEATABLE READ y ejecuto COUNT, obteniendo 3. Sesion 2 inserto Producto D con estado activo y hizo COMMIT. Cuando Sesion 1 repitio el COUNT, el resultado siguio siendo 3. No aparecio la fila fantasma. Esto confirma que REPEATABLE READ resuelve el problema de lectura fantasma.

---

## Escenario 3: Espera por Bloqueo (FOR UPDATE)

### Reproduccion

Sesion 1 abrio una transaccion y ejecuto SELECT FROM test WHERE id=1 FOR UPDATE. Esto le otorgo un bloqueo exclusivo sobre la fila id=1. Luego Sesion 2 abrio su propia transaccion e intento ejecutar el mismo comando SELECT FROM test WHERE id=1 FOR UPDATE sobre la misma fila. La sesion 2 quedo completamente bloqueada, sin devolver ningun resultado, con el cursor girando. No fue hasta que Sesion 1 ejecuto COMMIT, liberando el lock, que Sesion 2 se desbloqueo automaticamente y devolvio la fila.

### Explicacion

Cuando Sesion 1 ejecuta SELECT FOR UPDATE, adquiere un bloqueo a nivel de fila sobre la fila id=1. Si Sesion 2 intenta ejecutar el mismo SELECT FOR UPDATE sobre esa fila, PostgreSQL la pone en estado de espera hasta que Sesion 1 haga COMMIT o ROLLBACK, liberando el lock. Este es el mecanismo de bloqueo pesimista de PostgreSQL. Para evitar la espera, Sesion 2 podria usar SELECT FOR UPDATE NOWAIT, que lanza un error inmediatamente si no puede bloquear, o SELECT FOR UPDATE SKIP LOCKED, que omite las filas bloqueadas. Esto no es un problema de nivel de aislamiento sino del mecanismo de bloqueo selectivo.

### Conclusión

La explicacion se confirmo. Sesion 2 quedo efectivamente bloqueada esperando a que Sesion 1 liberara el lock con COMMIT. Los mecanismos que resuelven esto son FOR UPDATE NOWAIT (error inmediato) o FOR UPDATE SKIP LOCKED (omita la fila), no un nivel de aislamiento.
