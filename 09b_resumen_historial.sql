-- =====================================================
-- Script 09b: Resumen del historial de ventas
-- (se puede ejecutar cuantas veces quieras)
-- =====================================================
USE SolucionesElectricas;
GO

-- a) Cuántos documentos genera el sistema
SELECT 'Cotizaciones' AS Documento, COUNT(*) AS Cantidad FROM Cotizacion       UNION ALL
SELECT 'Pedidos',                   COUNT(*)             FROM Pedido           UNION ALL
SELECT 'Facturas',                  COUNT(*)             FROM Factura          UNION ALL
SELECT 'Cobros',                    COUNT(*)             FROM Cobro            UNION ALL
SELECT 'Despachos',                 COUNT(*)             FROM Despacho         UNION ALL
SELECT 'Partidas contables',        COUNT(*)             FROM Partida_Contable UNION ALL
SELECT 'Movimientos de kardex',     COUNT(*)             FROM Movimiento_Inventario;

-- b) La contabilidad cuadra: Total Debe = Total Haber
SELECT SUM(debe)  AS Total_Debe,
       SUM(haber) AS Total_Haber,
       CASE WHEN SUM(debe) = SUM(haber) THEN 'CUADRADA' ELSE 'DESCUADRADA' END AS Estado
FROM Partida_Detalle;

-- c) Ventas por mes
SELECT FORMAT(fecha_factura, 'yyyy-MM')                         AS Mes,
       COUNT(*)                                                 AS Facturas,
       SUM(total)                                               AS Total_Vendido,
       SUM(CASE WHEN estado_pago = 'Pagada'    THEN 1 ELSE 0 END) AS Pagadas,
       SUM(CASE WHEN estado_pago = 'Parcial'   THEN 1 ELSE 0 END) AS Parciales,
       SUM(CASE WHEN estado_pago = 'Pendiente' THEN 1 ELSE 0 END) AS Pendientes
FROM Factura
GROUP BY FORMAT(fecha_factura, 'yyyy-MM')
ORDER BY Mes;
