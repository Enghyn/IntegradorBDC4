-- ============================================================================
-- 3.2 Consulta con Subconsulta: Productos con precio superior al promedio de su categoría
-- Spec: Detectar productos cuyo precio de lista supera el promedio de su categoría.
-- Tablas: producto, categoria
-- Filtros: categoria.activo = TRUE, producto.activo = TRUE
-- Columnas: id_producto, nombre_producto, categoria, precio_lista, precio_promedio_categoria
-- Orden: categoria ASC, precio_lista DESC
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Versión A: Subconsulta correlacionada (Generada con IA)
-- ----------------------------------------------------------------------------
SELECT 
    p.id_producto,
    p.nombre AS nombre_producto,
    cat.nombre AS categoria,
    p.precio_lista,
    ROUND((
        SELECT AVG(p2.precio_lista)
        FROM producto p2
        WHERE p2.id_categoria = p.id_categoria
          AND p2.activo = TRUE
    ), 2) AS precio_promedio_categoria
FROM producto p
JOIN categoria cat ON p.id_categoria = cat.id_categoria
WHERE cat.activo = TRUE
  AND p.activo = TRUE
  AND p.precio_lista > (
        SELECT AVG(p3.precio_lista)
        FROM producto p3
        WHERE p3.id_categoria = p.id_categoria
          AND p3.activo = TRUE
  )
ORDER BY cat.nombre ASC, p.precio_lista DESC;

-- ----------------------------------------------------------------------------
-- Versión B: Alternativa propia con Window Functions / OVER PARTITION
-- ----------------------------------------------------------------------------
WITH productos_con_promedio AS (
    SELECT 
        p.id_producto,
        p.nombre AS nombre_producto,
        cat.nombre AS categoria,
        p.precio_lista,
        ROUND(AVG(p.precio_lista) OVER(PARTITION BY p.id_categoria), 2) AS precio_promedio_categoria
    FROM producto p
    JOIN categoria cat ON p.id_categoria = cat.id_categoria
    WHERE cat.activo = TRUE
      AND p.activo = TRUE
)
SELECT 
    id_producto,
    nombre_producto,
    categoria,
    precio_lista,
    precio_promedio_categoria
FROM productos_con_promedio
WHERE precio_lista > precio_promedio_categoria
ORDER BY categoria ASC, precio_lista DESC;

-- ----------------------------------------------------------------------------
-- Verificación de equivalencia (EXCEPT bidireccional)
-- Ambos EXCEPT deben devolver 0 filas para considerarlas equivalentes.
-- ----------------------------------------------------------------------------
(
  SELECT p.id_producto, p.nombre, cat.nombre, p.precio_lista,
         ROUND((SELECT AVG(p2.precio_lista) FROM producto p2
                WHERE p2.id_categoria = p.id_categoria AND p2.activo = TRUE), 2)
  FROM producto p
  JOIN categoria cat ON p.id_categoria = cat.id_categoria
  WHERE cat.activo = TRUE AND p.activo = TRUE
    AND p.precio_lista > (SELECT AVG(p3.precio_lista) FROM producto p3
                          WHERE p3.id_categoria = p.id_categoria AND p3.activo = TRUE)
  ORDER BY cat.nombre ASC, p.precio_lista DESC
)
EXCEPT
(
  WITH productos_con_promedio AS (
      SELECT p.id_producto, p.nombre, cat.nombre, p.precio_lista,
             ROUND(AVG(p.precio_lista) OVER(PARTITION BY p.id_categoria), 2) AS precio_promedio_categoria
      FROM producto p
      JOIN categoria cat ON p.id_categoria = cat.id_categoria
      WHERE cat.activo = TRUE AND p.activo = TRUE
  )
  SELECT id_producto, nombre, nombre, precio_lista, precio_promedio_categoria
  FROM productos_con_promedio
  WHERE precio_lista > precio_promedio_categoria
  ORDER BY nombre ASC, precio_lista DESC
);

-- (Versión invertida)
(
  WITH productos_con_promedio AS (
      SELECT p.id_producto, p.nombre, cat.nombre, p.precio_lista,
             ROUND(AVG(p.precio_lista) OVER(PARTITION BY p.id_categoria), 2) AS precio_promedio_categoria
      FROM producto p
      JOIN categoria cat ON p.id_categoria = cat.id_categoria
      WHERE cat.activo = TRUE AND p.activo = TRUE
  )
  SELECT id_producto, nombre, nombre, precio_lista, precio_promedio_categoria
  FROM productos_con_promedio
  WHERE precio_lista > precio_promedio_categoria
  ORDER BY nombre ASC, precio_lista DESC
)
EXCEPT
(
  SELECT p.id_producto, p.nombre, cat.nombre, p.precio_lista,
         ROUND((SELECT AVG(p2.precio_lista) FROM producto p2
                WHERE p2.id_categoria = p.id_categoria AND p2.activo = TRUE), 2)
  FROM producto p
  JOIN categoria cat ON p.id_categoria = cat.id_categoria
  WHERE cat.activo = TRUE AND p.activo = TRUE
    AND p.precio_lista > (SELECT AVG(p3.precio_lista) FROM producto p3
                          WHERE p3.id_categoria = p.id_categoria AND p3.activo = TRUE)
  ORDER BY cat.nombre ASC, p.precio_lista DESC
);
