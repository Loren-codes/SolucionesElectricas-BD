-- =====================================================
-- Script 13: Consultas Avanzadas (DQL)
-- Las 9 consultas del enunciado + subconsultas, EXISTS
-- y operaciones de conjuntos
-- =====================================================
USE SolucionesElectricas;
SET NOCOUNT ON;
DECLARE @hoy DATE = CAST(GETDATE() AS DATE);

-- =====================================================
-- CONSULTA 1: PRODUCTOS MÁS VENDIDOS (Top 10)
-- =====================================================
SELECT TOP 10
       RANK() OVER (ORDER BY SUM(fd.total_linea) DESC) AS Ranking,
       p.codigo                     AS Codigo,
       p.descripcion                AS Producto,
       c.nombre                     AS Categoria,
       SUM(fd.cantidad)             AS Cantidad_Vendida,
       p.codigo_um                  AS Unidad,
       COUNT(DISTINCT f.id_factura) AS Facturas,
       SUM(fd.total_linea)          AS Total_Vendido_Q
FROM Factura_Detalle fd
INNER JOIN Factura      f ON f.id_factura      = fd.id_factura
INNER JOIN Producto     p ON p.id_producto     = fd.id_producto
INNER JOIN Subcategoria s ON s.id_subcategoria = p.id_subcategoria
INNER JOIN Categoria    c ON c.id_categoria    = s.id_categoria
WHERE f.estado = 'Activa'
GROUP BY p.codigo, p.descripcion, c.nombre, p.codigo_um
ORDER BY Total_Vendido_Q DESC;

-- =====================================================
-- CONSULTA 2: LOS 5 PRODUCTOS MÁS COMPRADOS POR CADA CLIENTE
-- =====================================================
;WITH compras AS (
    SELECT cl.codigo           AS Codigo_Cliente,
           cl.nombre_comercial AS Cliente,
           p.codigo            AS Codigo_Producto,
           p.descripcion       AS Producto,
           SUM(fd.cantidad)    AS Cantidad,
           p.codigo_um         AS Unidad,
           SUM(fd.total_linea) AS Total_Q,
           ROW_NUMBER() OVER (PARTITION BY cl.id_cliente
                              ORDER BY SUM(fd.total_linea) DESC) AS Posicion
    FROM Factura f
    INNER JOIN Factura_Detalle fd ON fd.id_factura = f.id_factura
    INNER JOIN Cliente         cl ON cl.id_cliente = f.id_cliente
    INNER JOIN Producto        p  ON p.id_producto = fd.id_producto
    WHERE f.estado = 'Activa'
    GROUP BY cl.id_cliente, cl.codigo, cl.nombre_comercial,
             p.codigo, p.descripcion, p.codigo_um
)
SELECT Codigo_Cliente, Cliente, Posicion, Codigo_Producto, Producto,
       Cantidad, Unidad, Total_Q
FROM compras
WHERE Posicion <= 5
ORDER BY Codigo_Cliente, Posicion;

-- =====================================================
-- CONSULTA 3a: INVENTARIO POR SITIO, BODEGA Y LOCALIZACIÓN (detalle)
-- =====================================================
SELECT s.codigo  AS Sitio,      s.nombre AS Nombre_Sitio,
       b.codigo  AS Bodega,     b.nombre AS Nombre_Bodega,
       l.codigo  AS Localizacion,
       p.codigo  AS Producto,   p.descripcion,
       i.cantidad AS Existencia, i.cantidad_reservada AS Reservado,
       i.cantidad_disponible AS Disponible, p.codigo_um AS Unidad,
       CAST(i.cantidad * p.costo_unitario AS DECIMAL(14,2)) AS Valor_al_Costo_Q
FROM Inventario i
INNER JOIN Localizacion l ON l.id_localizacion = i.id_localizacion
INNER JOIN Bodega       b ON b.id_bodega       = l.id_bodega
INNER JOIN Sitio        s ON s.id_sitio        = b.id_sitio
INNER JOIN Producto     p ON p.id_producto     = i.id_producto
WHERE i.cantidad > 0
ORDER BY s.codigo, b.codigo, l.codigo, p.codigo;

-- =====================================================
-- CONSULTA 3b: INVENTARIO - TOTALES POR SITIO Y BODEGA (ROLLUP)
-- =====================================================
SELECT CASE WHEN GROUPING(s.nombre) = 1 THEN '*** TOTAL EMPRESA ***'
            ELSE s.nombre END                                       AS Sitio,
       CASE WHEN GROUPING(s.nombre) = 1 THEN ''
            WHEN GROUPING(b.nombre) = 1 THEN '--- Total del sitio ---'
            ELSE b.nombre END                                       AS Bodega,
       COUNT(DISTINCT i.id_producto)                                AS Productos_Distintos,
       COUNT(*)                                                     AS Ubicaciones_con_Producto,
       CAST(SUM(i.cantidad * p.costo_unitario) AS DECIMAL(14,2))    AS Valor_Inventario_Q
FROM Inventario i
INNER JOIN Localizacion l ON l.id_localizacion = i.id_localizacion
INNER JOIN Bodega       b ON b.id_bodega       = l.id_bodega
INNER JOIN Sitio        s ON s.id_sitio        = b.id_sitio
INNER JOIN Producto     p ON p.id_producto     = i.id_producto
WHERE i.cantidad > 0
GROUP BY ROLLUP (s.nombre, b.nombre)
ORDER BY GROUPING(s.nombre), s.nombre, GROUPING(b.nombre), b.nombre;

-- =====================================================
-- CONSULTA 4: VENTAS POR CATEGORÍA
-- =====================================================
SELECT c.nombre                     AS Categoria,
       COUNT(DISTINCT f.id_factura) AS Facturas,
       SUM(fd.base_imponible)       AS Base_Imponible_Q,
       SUM(fd.iva)                  AS IVA_Q,
       SUM(fd.total_linea)          AS Total_Q,
       CAST(100.0 * SUM(fd.total_linea) / SUM(SUM(fd.total_linea)) OVER ()
            AS DECIMAL(5,2))        AS Porcentaje_de_Ventas
FROM Factura_Detalle fd
INNER JOIN Factura      f ON f.id_factura      = fd.id_factura
INNER JOIN Producto     p ON p.id_producto     = fd.id_producto
INNER JOIN Subcategoria s ON s.id_subcategoria = p.id_subcategoria
INNER JOIN Categoria    c ON c.id_categoria    = s.id_categoria
WHERE f.estado = 'Activa'
GROUP BY c.nombre
ORDER BY Total_Q DESC;

-- =====================================================
-- CONSULTA 5: VENTAS POR VENDEDOR (con comisión)
-- =====================================================
SELECT v.codigo                                   AS Vendedor,
       u.nombre_completo                          AS Nombre,
       s.nombre                                   AS Sitio,
       COUNT(f.id_factura)                        AS Facturas,
       ISNULL(SUM(f.total), 0)                    AS Total_Vendido_Q,
       CAST(ISNULL(AVG(f.total), 0) AS DECIMAL(14,2)) AS Ticket_Promedio_Q,
       v.porcentaje_comision                      AS Comision_pct,
       CAST(ISNULL(SUM(f.base_imponible), 0) * v.porcentaje_comision / 100
            AS DECIMAL(14,2))                     AS Comision_Ganada_Q
FROM Vendedor v
INNER JOIN Usuario u ON u.id_usuario = v.id_usuario
INNER JOIN Sitio   s ON s.id_sitio   = v.id_sitio
LEFT  JOIN Factura f ON f.id_vendedor = v.id_vendedor AND f.estado = 'Activa'
GROUP BY v.codigo, u.nombre_completo, s.nombre, v.porcentaje_comision
ORDER BY Total_Vendido_Q DESC;

-- =====================================================
-- CONSULTA 6: CLIENTES CON MAYOR VOLUMEN DE COMPRA (Top 10)
-- =====================================================
SELECT TOP 10
       DENSE_RANK() OVER (ORDER BY SUM(f.total) DESC) AS Ranking,
       cl.codigo             AS Codigo,
       cl.nombre_comercial   AS Cliente,
       cl.tipo_cliente       AS Tipo,
       v.codigo              AS Vendedor,
       COUNT(*)              AS Facturas,
       SUM(f.total)          AS Total_Comprado_Q,
       MAX(f.fecha_factura)  AS Ultima_Compra,
       SUM(f.saldo_pendiente) AS Saldo_Pendiente_Q
FROM Factura f
INNER JOIN Cliente  cl ON cl.id_cliente = f.id_cliente
INNER JOIN Vendedor v  ON v.id_vendedor = cl.id_vendedor
WHERE f.estado = 'Activa'
GROUP BY cl.codigo, cl.nombre_comercial, cl.tipo_cliente, v.codigo
ORDER BY Total_Comprado_Q DESC;

-- =====================================================
-- CONSULTA 7: FACTURAS PENDIENTES DE COBRO (antigüedad de saldos)
-- =====================================================
SELECT f.numero_documento                AS Factura,
       f.fecha_factura                   AS Fecha,
       f.fecha_vencimiento               AS Vence,
       cl.nombre_comercial               AS Cliente,
       v.codigo                          AS Vendedor,
       f.total                           AS Total_Q,
       f.total - f.saldo_pendiente       AS Pagado_Q,
       f.saldo_pendiente                 AS Saldo_Q,
       f.estado_pago                     AS Estado_Pago,
       CASE WHEN f.fecha_vencimiento >= @hoy THEN 'Al día'
            ELSE CONCAT('Vencida hace ', DATEDIFF(DAY, f.fecha_vencimiento, @hoy), ' días')
       END                               AS Situacion,
       CASE WHEN DATEDIFF(DAY, f.fecha_vencimiento, @hoy) <= 0  THEN '0. No vencida'
            WHEN DATEDIFF(DAY, f.fecha_vencimiento, @hoy) <= 30 THEN '1. De 1 a 30 días'
            WHEN DATEDIFF(DAY, f.fecha_vencimiento, @hoy) <= 60 THEN '2. De 31 a 60 días'
            ELSE '3. Más de 60 días' END AS Antiguedad
FROM Factura f
INNER JOIN Cliente  cl ON cl.id_cliente  = f.id_cliente
INNER JOIN Vendedor v  ON v.id_vendedor  = f.id_vendedor
WHERE f.estado = 'Activa' AND f.saldo_pendiente > 0
ORDER BY f.fecha_vencimiento;

-- =====================================================
-- CONSULTA 8: CLIENTES CON MÁS DE 5 FACTURAS EN UN MES
-- =====================================================
SELECT cl.codigo                               AS Codigo,
       cl.nombre_comercial                     AS Cliente,
       YEAR(f.fecha_factura)                   AS Anio,
       FORMAT(f.fecha_factura, 'MMMM', 'es-GT') AS Mes,
       COUNT(*)                                AS Facturas_en_el_Mes,
       SUM(f.total)                            AS Total_del_Mes_Q
FROM Factura f
INNER JOIN Cliente cl ON cl.id_cliente = f.id_cliente
WHERE f.estado = 'Activa'
GROUP BY cl.codigo, cl.nombre_comercial, YEAR(f.fecha_factura),
         MONTH(f.fecha_factura), FORMAT(f.fecha_factura, 'MMMM', 'es-GT')
HAVING COUNT(*) > 5
ORDER BY Facturas_en_el_Mes DESC;

-- =====================================================
-- CONSULTA 9a: REPORTE DE IVA POR PERÍODO (mensual + total)
-- =====================================================
SELECT CASE WHEN GROUPING(DATEFROMPARTS(YEAR(f.fecha_factura), MONTH(f.fecha_factura), 1)) = 1
            THEN '*** TOTAL ***'
            ELSE FORMAT(DATEFROMPARTS(YEAR(f.fecha_factura), MONTH(f.fecha_factura), 1),
                        'MMMM yyyy', 'es-GT') END AS Periodo,
       COUNT(*)              AS Facturas,
       SUM(f.base_imponible) AS Base_Imponible_Q,
       SUM(f.iva)            AS IVA_Debito_Fiscal_Q,
       SUM(f.total)          AS Total_Facturado_Q
FROM Factura f
WHERE f.estado = 'Activa'
GROUP BY ROLLUP (DATEFROMPARTS(YEAR(f.fecha_factura), MONTH(f.fecha_factura), 1))
ORDER BY GROUPING(DATEFROMPARTS(YEAR(f.fecha_factura), MONTH(f.fecha_factura), 1)),
         DATEFROMPARTS(YEAR(f.fecha_factura), MONTH(f.fecha_factura), 1);

-- =====================================================
-- CONSULTA 9b: EL IVA DE LAS FACTURAS = EL IVA DE LA CONTABILIDAD
-- =====================================================
SELECT (SELECT SUM(iva) FROM Factura WHERE estado = 'Activa') AS IVA_segun_Facturas_Q,
       (SELECT SUM(pd.haber) - SUM(pd.debe)
        FROM Partida_Detalle pd
        INNER JOIN Cuenta_Contable cc ON cc.id_cuenta = pd.id_cuenta
        WHERE cc.codigo = '2.1.02.01')                         AS IVA_segun_Contabilidad_Q;

-- =====================================================
-- CONSULTA 10: SUBCONSULTA CORRELACIONADA
-- Productos con precio MAYOR al promedio de su categoría
-- =====================================================
SELECT p.codigo, p.descripcion, c.nombre AS Categoria, p.precio_unitario,
       (SELECT CAST(AVG(p2.precio_unitario) AS DECIMAL(12,2))
        FROM Producto p2
        INNER JOIN Subcategoria s2 ON s2.id_subcategoria = p2.id_subcategoria
        WHERE s2.id_categoria = s.id_categoria) AS Promedio_de_su_Categoria
FROM Producto p
INNER JOIN Subcategoria s ON s.id_subcategoria = p.id_subcategoria
INNER JOIN Categoria    c ON c.id_categoria    = s.id_categoria
WHERE p.precio_unitario > (SELECT AVG(p2.precio_unitario)
                           FROM Producto p2
                           INNER JOIN Subcategoria s2 ON s2.id_subcategoria = p2.id_subcategoria
                           WHERE s2.id_categoria = s.id_categoria)
ORDER BY c.nombre, p.precio_unitario DESC;

-- =====================================================
-- CONSULTA 11a: EXISTS - Clientes que tienen al menos una factura pendiente
-- =====================================================
SELECT cl.codigo, cl.nombre_comercial, cl.limite_credito, cl.dias_credito
FROM Cliente cl
WHERE EXISTS (SELECT 1 FROM Factura f
              WHERE f.id_cliente = cl.id_cliente
                AND f.estado = 'Activa' AND f.saldo_pendiente > 0)
ORDER BY cl.codigo;

-- =====================================================
-- CONSULTA 11b: NOT EXISTS - Productos que NUNCA se han vendido
-- =====================================================
SELECT p.codigo, p.descripcion, p.precio_unitario
FROM Producto p
WHERE NOT EXISTS (SELECT 1
                  FROM Factura_Detalle fd
                  INNER JOIN Factura f ON f.id_factura = fd.id_factura
                  WHERE fd.id_producto = p.id_producto AND f.estado = 'Activa')
ORDER BY p.codigo;

-- =====================================================
-- CONSULTA 12a: UNION - Directorio de contactos (clientes + empleados)
-- =====================================================
SELECT 'Cliente' AS Tipo, nombre_comercial AS Nombre, correo, telefono
FROM Cliente WHERE correo IS NOT NULL
UNION
SELECT 'Empleado', nombre_completo, correo, NULL
FROM Usuario
ORDER BY Tipo, Nombre;

-- =====================================================
-- CONSULTA 12b: INTERSECT - Clientes que compraron en agosto Y en septiembre
-- =====================================================
SELECT cl.codigo, cl.nombre_comercial
FROM Factura f INNER JOIN Cliente cl ON cl.id_cliente = f.id_cliente
WHERE f.estado = 'Activa' AND f.fecha_factura >= '20260801' AND f.fecha_factura < '20260901'
INTERSECT
SELECT cl.codigo, cl.nombre_comercial
FROM Factura f INNER JOIN Cliente cl ON cl.id_cliente = f.id_cliente
WHERE f.estado = 'Activa' AND f.fecha_factura >= '20260901' AND f.fecha_factura < '20261001';

-- =====================================================
-- CONSULTA 12c: EXCEPT - Clientes que compraron en julio pero NO en octubre
--               ("clientes por recuperar")
-- =====================================================
SELECT cl.codigo, cl.nombre_comercial
FROM Factura f INNER JOIN Cliente cl ON cl.id_cliente = f.id_cliente
WHERE f.estado = 'Activa' AND f.fecha_factura >= '20260701' AND f.fecha_factura < '20260801'
EXCEPT
SELECT cl.codigo, cl.nombre_comercial
FROM Factura f INNER JOIN Cliente cl ON cl.id_cliente = f.id_cliente
WHERE f.estado = 'Activa' AND f.fecha_factura >= '20261001' AND f.fecha_factura < '20261101';
