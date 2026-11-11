# Ejercicio de Lectura Critica

Autor: Enzo Giaquinta
Comision: 4
Legajo: 53884

---

## Script 1

### Script original

-- Generado para: dar de baja las funciones de peliculas retiradas de cartel
UPDATE funcion
SET activa = FALSE;

### Analisis linea por linea

La primera linea es un comentario que indica la intencion del script: desactivar unicamente las funciones de peliculas que fueron retiradas de cartel. Es decir, solo deberian afectarse las filas de la tabla funcion donde la pelicula asociada ya no esta en cartel.

La segunda linea es la sentencia UPDATE sobre la tabla funcion. Indica que se va a modificar la columna activa.

La tercera linea establece que el nuevo valor de activa sera FALSE para todas las filas seleccionadas.

### Que hace realmente

El problema esta en que no hay clausula WHERE. Sin un WHERE, el UPDATE afecta absolutamente todas las filas de la tabla funcion. No importa si la funcion corresponde a una pelicula que sigue en cartel o no. El resultado es que todas las funciones, sin excepcion, quedan con activa = FALSE. Esto es un error grave porque desactiva funciones que deberian seguir activas.

### Por que no coincide con la consigna

La consigna dice "dar de baja las funciones de peliculas retiradas de cartel". Esto implica que solo deben desactivarse las funciones cuya pelicula asociada esta retirada. El script original desactiva todas las funciones, incluidas las de peliculas que siguen en cartel. No hay ninguna condicion que filtre por peliculas retiradas.

### Script corregido

-- Generado para: dar de baja las funciones de peliculas retiradas de cartel
UPDATE funcion
SET activa = FALSE
WHERE pelicula_id IN (
    SELECT id FROM pelicula
    WHERE retirada_de_cartel = TRUE
);

La clausula WHERE filtra solo las filas de funcion cuyo pelicula_id corresponda a una pelicula que tenga retirada_de_cartel en TRUE. De esta forma solo se desactivan las funciones de peliculas retiradas, tal como pide la consigna.

---

## Script 2

### Script original

-- Generado para: limpiar las categorias sin productos asociados
DELETE FROM categoria
WHERE id NOT IN (SELECT categoria_id FROM producto);

### Analisis linea por linea

La primera linea es un comentario que indica la intencion: eliminar las categorias que no tengan ningun producto asociado.

La segunda linea es la sentencia DELETE sobre la tabla categoria, indicando que se van a eliminar filas segun una condicion.

La tercera linea contiene la clausula WHERE con una subconsulta. La subconsulta SELECT categoria_id FROM producto obtiene todos los valores de la columna categoria_id de la tabla producto. La condicion NOT IN verifica que el id de la categoria no aparezca en esa lista. Es decir, elimina las categorias que no tienen ningun producto asociado.

### Que hace realmente

Si la tabla producto tiene valores NULL en la columna categoria_id, la subconsulta devuelve una lista que contiene NULL. Cuando PostgreSQL evalua NOT IN con una lista que contiene NULL, el resultado es que no se elimina ninguna fila. Esto se debe a que cualquier comparacion con NULL en SQL devuelve UNKNOWN, y NOT IN con un NULL en la lista nunca puede ser TRUE para ninguna fila. El DELETE termina sin afectar ninguna categoria, incluso las que realmente estan vacias.

Si la tabla producto no tiene NULLs en categoria_id, el script funciona correctamente y elimina las categorias sin productos.

### Por que no coincide con la consigna

La consigna dice "limpiar las categorias sin productos asociados". El script deberia eliminar todas las categorias que no tengan productos, sin excepciones. Pero si hay algun NULL en categoria_id de la tabla producto, el script no elimina nada. Es un error silencioso porque no tira ningun error, simplemente no hace lo que se espera.

### Script corregido

DELETE FROM categoria
WHERE NOT EXISTS (
    SELECT 1 FROM producto
    WHERE producto.categoria_id = categoria.id
);

Usar NOT EXISTS en lugar de NOT IN resuelve el problema porque NOT EXISTS no se ve afectado por valores NULL. La subconsulta busca si existe al menos un producto asociado a la categoria. Si no existe ninguno, la condicion NOT EXISTS es TRUE y la categoria se elimina. Esto funciona correctamente independientemente de si hay NULLs en categoria_id.

