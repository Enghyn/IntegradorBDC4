# AGENTS.md

> Base de datos FoodStore — PostgreSQL  
> Estructura y normas para scripts, cargas masivas y seguridad

---

## Estructura y ownership de carpetas

- **db/schema.sql:** Única fuente estructural. Prohibido agregar datos aquí o cambiar estructura sin criterios explícitos.
- **db/backups/**: Solo backups (`pg_dump`) antes de cualquier ALTER o carga masiva. No versionar.
- **db/seeds/**: Solo scripts de carga de datos sintéticos (testing o benchmarks), nunca datos productivos.
- **.kiro/specs/**: Especificaciones técnicas y requisitos por feature. Consultar antes de cambios estructurales o automatizaciones.
- **.kiro/steering/**: Normas duras del proyecto. En especial, seguir `security-standards.md` y protocolos de backup/rollback.
- **src/**, **docs/**: Código fuente (si lo hay) y documentación propia/diagrama (sin relevancia estructural para DB ops).

---

## Normas de seguridad y manejo de datos

- Nunca hardcodear contraseñas, tokens ni claves de API en el código. Todo secreto va en `.env`, siempre gitignoreado.
- Prohibido ejecutar código DDL/DML en producción o sobre cualquier base que no sea *test/dev/local*.  
  - Antes de ejecutar cualquier script, validar que el nombre de la base contiene `test`, `dev` o `local`.
- Todo input del usuario debe ser validado y sanitizado — nunca concatenar strings en SQL, siempre usar parámetros/preparadas.
- Contraseñas de usuario siempre hasheadas (bcrypt/argon2), nunca en texto plano.
- Mensajes de error SQL JAMÁS deben exponerse directo al usuario final.
- Prohibido modificar los archivos de `db/backups/` o `db/seeds/` con datos reales. Solo usar datos sintéticos generados via scripts verificados.
- Antes de alterar la estructura o cargar datos masivos:
  - Respaldar obligatoriamente la base actual (`pg_dump ... > db/backups/…`)
  - Repasar las specs en `.kiro/specs` y normas en `.kiro/steering/security-standards.md`

---

### Protocolo estricto para operaciones seguras sobre la base de datos (obligatorio en desarrollo y cambios estructurales)

1. **Trabajo siempre sobre una copia de desarrollo, nunca sobre producción o datos valiosos.**
   - La copia debe crearse con: `createdb -T plantilla_base copia_trabajo`
   - Verificar explícitamente sobre qué base se correrá cada script.

2. **Prueba de scripts en transacción con rollback antes de confirmar cambios.**
   - TODO script que escriba/afecte datos o estructura se debe ejecutar primero en:
     ```
     BEGIN;
     -- operaciones
     ROLLBACK;
     ```
   - Solo si el resultado es correcto, volver a ejecutar usando COMMIT.

3. **Backup previo a cambios estructurales mediante pg_dump.**
   - Antes de cada ALTER, DROP o migración:
     `pg_dump -U usuario -d copia_trabajo > db/backups/backup_PRECAMBIO.sql`
   - Para poder revertir incluso si el ROLLBACK no basta.

---

## Carga masiva de datos: protocolo seguro y validaciones

- Usar solo scripts autocontenidos generados según los specs de `.kiro/specs/carga-datos/`.
  - Validar antes los scripts: **prohibidos comandos `DROP`, `TRUNCATE`, `ALTER` o afectando otras DBs**.
  - Validar que la base activa es de test/dev/local antes de toda secuencia.
- Ejecución recomendada de carga masiva:
  1. Repasar línea x línea (NO ejecutar scripts "a ciegas").
  2. Realizar backup (`pg_dump`) previo obligatorio.
  3. Ejecutar dentro de una transacción completa.
  4. Rollback automático al primer error grave.
  5. Ejecutar `ANALYZE` post-carga en las tablas afectadas.
  6. Verificar los logs/resultados y rechazar ejecuciones con warnings o errores.
- Para cualquier error grave (estructura, conexión, backup fallido, comandos prohibidos detectados): abortar el pipeline y reportar detalle.
- Ver ejemplos y criterios en los métodos y scripts sugeridos en `.kiro/specs/carga-datos/error-handling.md` y `.kiro/specs/carga-datos/design.md`.

---

## Reglas específicas extraídas de las especificaciones

- Generar solo datos sintéticos que cumplan exactamente todos los constraints y relaciones del esquema.
- Validaciones exhaustivas antes de cargar datos:
  - Chequear unicidad explícita (ejemplo: emails únicos al cargar clientes).
  - Respetar las restricciones y tipos exactos por columna.
- Jamás modificar/agregar tipos, constraints, ni cambiar claves en el schema fuera del flujo validado.

---

## Gotchas comunes / Trampas de agente

- Pueden convivir muchas copias de la DB en el entorno (test/dev). Siempre operar SOLO sobre la copia marcada para pruebas.
- No existen migraciones incrementales ni orquestadores automáticos de upgrades. Toda la evolución manual y controlada.
- Si el script fue editado a mano, nunca asumir que pasó validaciones: SIEMPRE revalidar antes de ejecutar.
- Prohibido usar dumps o seeds con datos históricos o que violen el alcance test/dev definido en specs.

---

## Comandos y ejemplos a mano

- Crear backup(test):  
  `pg_dump -U usuario -d foodstore_test > db/backups/foodstore_backup_$(date +%Y%m%d_%H%M%S).sql`
- Cargar schema:  
  `psql -U usuario -d foodstore_test -f db/schema.sql`
- Cargar datos masivos:  
  `psql -U usuario -d foodstore_test -f db/seeds/load_massive_data.sql`
- Post-analizar:  
  `psql -U usuario -d foodstore_test -c "ANALYZE cliente, producto, pedido, detalle_pedido;"`

---

## Prioridad de fuentes de verdad

1. **.kiro/steering/security-standards.md** (siempre prioritaria para temas de safety y secretos)
2. **.kiro/specs/carga-datos/** (para testing, cargas, validaciones)
3. **db/schema.sql** (estructura efectiva)
4. **README.md, .env.example** (convenciones superficiales y referencia)
5. Todo lo no explicitado aquí o en esas fuentes PREVAILS según el código ejecutable — no la documentación.

---
