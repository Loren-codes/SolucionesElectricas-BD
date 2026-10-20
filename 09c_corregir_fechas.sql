-- =====================================================
-- Script 09c: Corrección de fechas del historial
-- Las ventas que quedaron en ene-abr se mueven 175 días
-- (de 07-ene a 01-jul), en TODA su cadena de documentos
-- =====================================================
USE SolucionesElectricas;
GO

DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
DECLARE @afectadas TABLE (id_factura INT PRIMARY KEY, id_pedido INT, id_cotizacion INT);

-- Las facturas con fecha anterior a la apertura (formato seguro AAAAMMDD)
INSERT INTO @afectadas (id_factura, id_pedido, id_cotizacion)
SELECT f.id_factura, f.id_pedido, p.id_cotizacion
FROM Factura f
INNER JOIN Pedido p ON p.id_pedido = f.id_pedido
WHERE f.fecha_factura < '20260630';

SELECT COUNT(*) AS Facturas_a_corregir FROM @afectadas;

BEGIN TRANSACTION;      -- todo o nada

    UPDATE c
    SET fecha_solicitud        = DATEADD(DAY, 175, c.fecha_solicitud),
        fecha_tentativa_compra = DATEADD(DAY, 175, c.fecha_tentativa_compra)
    FROM Cotizacion c
    INNER JOIN @afectadas a ON a.id_cotizacion = c.id_cotizacion;

    UPDATE p
    SET fecha_pedido = DATEADD(DAY, 175, p.fecha_pedido)
    FROM Pedido p
    INNER JOIN @afectadas a ON a.id_pedido = p.id_pedido;

    UPDATE f
    SET fecha_factura     = DATEADD(DAY, 175, f.fecha_factura),
        fecha_vencimiento = DATEADD(DAY, 175, f.fecha_vencimiento)
    FROM Factura f
    INNER JOIN @afectadas a ON a.id_factura = f.id_factura;

    UPDATE co
    SET fecha_cobro = CASE WHEN DATEADD(DAY, 175, co.fecha_cobro) > @hoy THEN @hoy
                           ELSE DATEADD(DAY, 175, co.fecha_cobro) END
    FROM Cobro co
    INNER JOIN @afectadas a ON a.id_factura = co.id_factura;

    UPDATE d
    SET fecha_despacho = CASE WHEN DATEADD(DAY, 175, d.fecha_despacho) > SYSDATETIME()
                              THEN SYSDATETIME()
                              ELSE DATEADD(DAY, 175, d.fecha_despacho) END
    FROM Despacho d
    INNER JOIN @afectadas a ON a.id_factura = d.id_factura;

    -- Partidas contables: misma fecha que su documento
    UPDATE pc SET fecha_contable = f.fecha_factura
    FROM Partida_Contable pc
    INNER JOIN Factura    f ON pc.tipo_documento = 'Factura' AND pc.id_documento = f.id_factura
    INNER JOIN @afectadas a ON a.id_factura = f.id_factura;

    UPDATE pc SET fecha_contable = co.fecha_cobro
    FROM Partida_Contable pc
    INNER JOIN Cobro      co ON pc.tipo_documento = 'Cobro' AND pc.id_documento = co.id_cobro
    INNER JOIN @afectadas a  ON a.id_factura = co.id_factura;

    UPDATE pc SET fecha_contable = CAST(d.fecha_despacho AS DATE)
    FROM Partida_Contable pc
    INNER JOIN Despacho   d ON pc.tipo_documento = 'Despacho' AND pc.id_documento = d.id_despacho
    INNER JOIN @afectadas a ON a.id_factura = d.id_factura;

    -- Kardex: fecha de las salidas por despacho
    UPDATE m SET fecha = d.fecha_despacho
    FROM Movimiento_Inventario m
    INNER JOIN Despacho   d ON m.documento_tipo = 'DESPACHO' AND m.documento_numero = d.numero
    INNER JOIN @afectadas a ON a.id_factura = d.id_factura;

COMMIT TRANSACTION;
GO

-- Verificación: ahora todas las facturas deben estar entre julio y octubre
SELECT MIN(fecha_factura) AS Primera_Factura,
       MAX(fecha_factura) AS Ultima_Factura,
       COUNT(*)           AS Total_Facturas
FROM Factura;
