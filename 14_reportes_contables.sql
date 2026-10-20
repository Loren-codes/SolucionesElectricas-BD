-- =====================================================
-- Script 14: Reportes Contables (Vistas)
-- Libro Diario, Balance de Comprobación, Estado de
-- Resultados, Balance General y Alertas de Inventario
-- =====================================================
USE SolucionesElectricas;
GO

DROP VIEW IF EXISTS vw_Alerta_Inventario;
DROP VIEW IF EXISTS vw_Balance_General;
DROP VIEW IF EXISTS vw_Estado_Resultados;
DROP VIEW IF EXISTS vw_Saldos_Cuenta;
DROP VIEW IF EXISTS vw_Libro_Diario;
GO

-- -----------------------------------------------------
-- 1. LIBRO DIARIO
-- -----------------------------------------------------
CREATE VIEW vw_Libro_Diario
AS
SELECT pc.id_partida,
       pc.numero           AS Partida,
       pc.fecha_contable   AS Fecha,
       pc.tipo_documento   AS Tipo_Documento,
       pc.documento_numero AS Documento,
       pc.descripcion      AS Concepto,
       pd.linea            AS Linea,
       cc.codigo           AS Cuenta,
       cc.nombre           AS Nombre_Cuenta,
       pd.debe             AS Debe,
       pd.haber            AS Haber,
       cl.nombre_comercial AS Cliente
FROM Partida_Contable pc
INNER JOIN Partida_Detalle pd ON pd.id_partida = pc.id_partida
INNER JOIN Cuenta_Contable cc ON cc.id_cuenta  = pd.id_cuenta
LEFT  JOIN Cliente         cl ON cl.id_cliente = pd.id_cliente;
GO

-- -----------------------------------------------------
-- 2. SALDOS POR CUENTA
-- -----------------------------------------------------
CREATE VIEW vw_Saldos_Cuenta
AS
SELECT cc.id_cuenta, cc.codigo, cc.nombre, cc.tipo, cc.clasificacion, cc.naturaleza,
       ISNULL(SUM(pd.debe),  0) AS Total_Debe,
       ISNULL(SUM(pd.haber), 0) AS Total_Haber,
       -- Saldo según el tipo de cuenta (Activo/Costo/Gasto aumentan por el Debe)
       CASE WHEN cc.tipo IN ('Activo', 'Costo', 'Gasto')
            THEN ISNULL(SUM(pd.debe), 0) - ISNULL(SUM(pd.haber), 0)
            ELSE ISNULL(SUM(pd.haber), 0) - ISNULL(SUM(pd.debe), 0)
       END AS Saldo
FROM Cuenta_Contable cc
LEFT JOIN Partida_Detalle pd ON pd.id_cuenta = cc.id_cuenta
WHERE cc.acepta_movimiento = 1
GROUP BY cc.id_cuenta, cc.codigo, cc.nombre, cc.tipo, cc.clasificacion, cc.naturaleza;
GO

-- -----------------------------------------------------
-- 3. ESTADO DE RESULTADOS
-- -----------------------------------------------------
CREATE VIEW vw_Estado_Resultados
AS
SELECT x.Ventas_Netas,
       x.Costo_de_Ventas,
       x.Ventas_Netas - x.Costo_de_Ventas                      AS Utilidad_Bruta,
       x.Gastos_de_Operacion,
       x.Ventas_Netas - x.Costo_de_Ventas - x.Gastos_de_Operacion AS Utilidad_Neta,
       CAST(100.0 * (x.Ventas_Netas - x.Costo_de_Ventas)
            / NULLIF(x.Ventas_Netas, 0) AS DECIMAL(5,2))       AS Margen_Bruto_pct
FROM (SELECT SUM(CASE WHEN tipo = 'Ingreso' THEN Saldo ELSE 0 END) AS Ventas_Netas,
             SUM(CASE WHEN tipo = 'Costo'   THEN Saldo ELSE 0 END) AS Costo_de_Ventas,
             SUM(CASE WHEN tipo = 'Gasto'   THEN Saldo ELSE 0 END) AS Gastos_de_Operacion
      FROM vw_Saldos_Cuenta) x;
GO

-- -----------------------------------------------------
-- 4. BALANCE GENERAL (resumen)
-- -----------------------------------------------------
CREATE VIEW vw_Balance_General
AS
SELECT x.Total_Activo,
       x.Total_Pasivo,
       x.Total_Patrimonio,
       er.Utilidad_Neta                                         AS Utilidad_del_Ejercicio,
       x.Total_Pasivo + x.Total_Patrimonio + er.Utilidad_Neta  AS Pasivo_mas_Patrimonio,
       CASE WHEN x.Total_Activo = x.Total_Pasivo + x.Total_Patrimonio + er.Utilidad_Neta
            THEN 'CUADRADO' ELSE 'DESCUADRADO' END              AS Estado
FROM (SELECT SUM(CASE WHEN tipo = 'Activo'     THEN Saldo ELSE 0 END) AS Total_Activo,
             SUM(CASE WHEN tipo = 'Pasivo'     THEN Saldo ELSE 0 END) AS Total_Pasivo,
             SUM(CASE WHEN tipo = 'Patrimonio' THEN Saldo ELSE 0 END) AS Total_Patrimonio
      FROM vw_Saldos_Cuenta) x
CROSS JOIN vw_Estado_Resultados er;
GO

-- -----------------------------------------------------
-- 5. ALERTA DE INVENTARIO BAJO EL MÍNIMO (por sitio)
-- -----------------------------------------------------
CREATE VIEW vw_Alerta_Inventario
AS
SELECT s.codigo AS Sitio, s.nombre AS Nombre_Sitio,
       p.codigo AS Producto, p.descripcion,
       SUM(i.cantidad_disponible) AS Disponible,
       p.stock_minimo             AS Stock_Minimo,
       CASE WHEN SUM(i.cantidad_disponible) = 0 THEN 'AGOTADO'
            ELSE 'BAJO EL MÍNIMO' END AS Alerta
FROM Inventario i
INNER JOIN Producto     p ON p.id_producto     = i.id_producto
INNER JOIN Localizacion l ON l.id_localizacion = i.id_localizacion
INNER JOIN Bodega       b ON b.id_bodega       = l.id_bodega
INNER JOIN Sitio        s ON s.id_sitio        = b.id_sitio
GROUP BY s.codigo, s.nombre, p.codigo, p.descripcion, p.stock_minimo
HAVING SUM(i.cantidad_disponible) < p.stock_minimo;
GO

-- =====================================================
-- REPORTES
-- =====================================================
SET NOCOUNT ON;

-- a) LIBRO DIARIO (las primeras partidas)
SELECT TOP 40 Partida, Fecha, Tipo_Documento, Documento, Concepto,
       Cuenta, Nombre_Cuenta, Debe, Haber
FROM vw_Libro_Diario
ORDER BY id_partida, Linea;

-- b) BALANCE DE COMPROBACIÓN
SELECT Cuenta, Nombre, Debe, Haber, Saldo_Deudor, Saldo_Acreedor
FROM (
    SELECT 1 AS orden, codigo AS Cuenta, nombre AS Nombre,
           Total_Debe AS Debe, Total_Haber AS Haber,
           CASE WHEN Total_Debe > Total_Haber THEN Total_Debe - Total_Haber ELSE 0 END AS Saldo_Deudor,
           CASE WHEN Total_Haber > Total_Debe THEN Total_Haber - Total_Debe ELSE 0 END AS Saldo_Acreedor
    FROM vw_Saldos_Cuenta
    WHERE Total_Debe + Total_Haber > 0
    UNION ALL
    SELECT 2, '', '*** TOTALES ***', SUM(Total_Debe), SUM(Total_Haber),
           SUM(CASE WHEN Total_Debe > Total_Haber THEN Total_Debe - Total_Haber ELSE 0 END),
           SUM(CASE WHEN Total_Haber > Total_Debe THEN Total_Haber - Total_Debe ELSE 0 END)
    FROM vw_Saldos_Cuenta
) x
ORDER BY orden, Cuenta;

-- c) ESTADO DE RESULTADOS (formato de reporte)
SELECT v.Concepto, v.Monto_Q
FROM vw_Estado_Resultados er
CROSS APPLY (VALUES
    (1, 'Ventas netas',              er.Ventas_Netas),
    (2, '(-) Costo de ventas',       er.Costo_de_Ventas),
    (3, '(=) UTILIDAD BRUTA',        er.Utilidad_Bruta),
    (4, '(-) Gastos de operación',   er.Gastos_de_Operacion),
    (5, '(=) UTILIDAD NETA',         er.Utilidad_Neta),
    (6, 'Margen bruto (%)',          er.Margen_Bruto_pct)
) AS v(orden, Concepto, Monto_Q)
ORDER BY v.orden;

-- d) BALANCE GENERAL (detalle)
SELECT Seccion, Cuenta, Nombre, Saldo_Q
FROM (
    SELECT 1 AS o, 'ACTIVO' AS Seccion, codigo AS Cuenta, nombre AS Nombre, Saldo AS Saldo_Q
    FROM vw_Saldos_Cuenta WHERE tipo = 'Activo' AND Saldo <> 0
    UNION ALL
    SELECT 2, 'ACTIVO', '', '>>> TOTAL ACTIVO', Total_Activo FROM vw_Balance_General
    UNION ALL
    SELECT 3, 'PASIVO', codigo, nombre, Saldo
    FROM vw_Saldos_Cuenta WHERE tipo = 'Pasivo' AND Saldo <> 0
    UNION ALL
    SELECT 4, 'PASIVO', '', '>>> TOTAL PASIVO', Total_Pasivo FROM vw_Balance_General
    UNION ALL
    SELECT 5, 'PATRIMONIO', codigo, nombre, Saldo
    FROM vw_Saldos_Cuenta WHERE tipo = 'Patrimonio' AND Saldo <> 0
    UNION ALL
    SELECT 6, 'PATRIMONIO', '', 'Utilidad del ejercicio', Utilidad_del_Ejercicio FROM vw_Balance_General
    UNION ALL
    SELECT 7, 'PATRIMONIO', '', '>>> TOTAL PATRIMONIO', Total_Patrimonio + Utilidad_del_Ejercicio
    FROM vw_Balance_General
    UNION ALL
    SELECT 8, '', '', '>>> TOTAL PASIVO + PATRIMONIO', Pasivo_mas_Patrimonio FROM vw_Balance_General
) x
ORDER BY o, Cuenta;

-- e) ¿CUADRA EL BALANCE?  Activo = Pasivo + Patrimonio
SELECT * FROM vw_Balance_General;

-- f) ALERTAS DE INVENTARIO
SELECT * FROM vw_Alerta_Inventario ORDER BY Sitio, Producto;
