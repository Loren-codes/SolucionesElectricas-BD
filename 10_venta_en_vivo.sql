-- =====================================================
-- Script 10: Venta en vivo + pruebas de reglas de negocio
-- =====================================================
USE SolucionesElectricas;
SET NOCOUNT ON;

-- Protección: solo una vez
IF EXISTS (SELECT 1 FROM Cotizacion WHERE observaciones = 'Venta demostración en vivo')
BEGIN
    PRINT 'La venta en vivo ya fue realizada. No se hizo nada.';
    RETURN;
END

DECLARE @cot INT, @ped INT, @fac INT, @total DECIMAL(14,2), @monto DECIMAL(14,2),
        @cot2 INT, @ped2 INT, @fac2 INT, @cot3 INT, @ped3 INT,
        @tentativa DATE = DATEADD(DAY, 7, CAST(GETDATE() AS DATE)),
        @stock_antes DECIMAL(12,2) = dbo.fn_StockDisponible('CO-BC-0001', 'S01');

-- =====================================================
-- ETAPA 1: COTIZACIÓN
-- =====================================================
-- PRUEBA 1: un vendedor que NO consiguió al cliente
BEGIN TRY
    EXEC sp_CrearCotizacion @codigo_cliente = 'C0001', @codigo_vendedor = 'V003',
         @productos = 'CO-BC-0001:100';
END TRY
BEGIN CATCH
    SELECT 'Prueba 1: vendedor ajeno' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- PRUEBA 2: cantidad con decimales en un producto que se vende por unidad
BEGIN TRY
    EXEC sp_CrearCotizacion @codigo_cliente = 'C0001', @codigo_vendedor = 'V001',
         @productos = 'MA-PV-0002:2.5';
END TRY
BEGIN CATCH
    SELECT 'Prueba 2: media unidad' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- PASO A: la cotización CORRECTA
EXEC sp_CrearCotizacion
     @codigo_cliente  = 'C0001',
     @codigo_vendedor = 'V001',
     @productos       = 'CO-BC-0001:250;CO-BC-0002:150;MA-PV-0002:5;AE-PR-0003:4;TF-EL-0001:5',
     @fecha_tentativa = @tentativa,
     @observaciones   = 'Venta demostración en vivo',
     @id_cotizacion   = @cot OUTPUT;

-- PRUEBA 3: generar pedido de una cotización que aún está "En proceso"
BEGIN TRY
    EXEC sp_GenerarPedido @id_cotizacion = @cot;
END TRY
BEGIN CATCH
    SELECT 'Prueba 3: pedido sin confirmar' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- PRUEBA 4: saltarse un estado (En proceso -> Confirmada)
BEGIN TRY
    EXEC sp_CambiarEstadoCotizacion @cot, 'Confirmada';
END TRY
BEGIN CATCH
    SELECT 'Prueba 4: saltar estado' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- PASO B: los estados en orden
EXEC sp_CambiarEstadoCotizacion @cot, 'Firme';
EXEC sp_CambiarEstadoCotizacion @cot, 'Confirmada';

-- =====================================================
-- ETAPA 2: PEDIDO (el cliente pide descuento)
-- =====================================================
-- PASO C: pedido con 5% en el cable y 10% en el centro de carga
EXEC sp_GenerarPedido @id_cotizacion = @cot,
     @descuentos = 'CO-BC-0001:5;AE-PR-0003:10',
     @id_pedido  = @ped OUTPUT;

-- PRUEBA 5: facturar sin que el descuento esté autorizado
BEGIN TRY
    EXEC sp_Facturar @id_pedido = @ped;
END TRY
BEGIN CATCH
    SELECT 'Prueba 5: factura sin autorización' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- PRUEBA 6: el propio vendedor intenta autorizar su descuento
BEGIN TRY
    EXEC sp_AutorizarDescuento @id_pedido = @ped, @username = 'cmendez';
END TRY
BEGIN CATCH
    SELECT 'Prueba 6: vendedor autoriza' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- PASO D: el GERENTE autoriza
EXEC sp_AutorizarDescuento @id_pedido = @ped, @username = 'rcastillo';

-- =====================================================
-- ETAPA 3: FACTURA
-- =====================================================
-- PASO E
EXEC sp_Facturar @id_pedido = @ped, @id_factura = @fac OUTPUT;
SELECT @total = total FROM Factura WHERE id_factura = @fac;

-- PRUEBA 7: despachar una factura que NO está pagada
BEGIN TRY
    EXEC sp_Despachar @id_factura = @fac, @recibido_por = 'Ing. Marco Tulio Reyes';
END TRY
BEGIN CATCH
    SELECT 'Prueba 7: despacho sin pago' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- =====================================================
-- ETAPA 4: COBRO
-- =====================================================
-- PRUEBA 8: cobrar más de lo que se debe
SET @monto = @total + 100;
BEGIN TRY
    EXEC sp_RegistrarCobro @id_factura = @fac, @monto = @monto;
END TRY
BEGIN CATCH
    SELECT 'Prueba 8: cobro mayor al saldo' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- PASO F: abono del 50% en efectivo
SET @monto = CAST(@total / 2 AS DECIMAL(14,2));
EXEC sp_RegistrarCobro @id_factura = @fac, @monto = @monto, @metodo_pago = 'Efectivo',
     @referencia = 'Anticipo 50%';

-- PRUEBA 9: despachar con pago parcial
BEGIN TRY
    EXEC sp_Despachar @id_factura = @fac, @recibido_por = 'Ing. Marco Tulio Reyes';
END TRY
BEGIN CATCH
    SELECT 'Prueba 9: despacho con pago parcial' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- PASO G: el resto por transferencia bancaria
SELECT @monto = saldo_pendiente FROM Factura WHERE id_factura = @fac;
EXEC sp_RegistrarCobro @id_factura = @fac, @monto = @monto, @metodo_pago = 'Transferencia',
     @numero_cuenta_bancaria = '000-123456-7', @referencia = 'TRF-884512';

-- =====================================================
-- ETAPA 5: DESPACHO
-- =====================================================
-- PASO H
EXEC sp_Despachar @id_factura = @fac, @recibido_por = 'Ing. Marco Tulio Reyes';

-- PRUEBA 10: despachar dos veces
BEGIN TRY
    EXEC sp_Despachar @id_factura = @fac, @recibido_por = 'Otra persona';
END TRY
BEGIN CATCH
    SELECT 'Prueba 10: doble despacho' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- =====================================================
-- PRUEBA 11: INVENTARIO INSUFICIENTE (50 telurómetros)
-- =====================================================
EXEC sp_CrearCotizacion @codigo_cliente = 'C0004', @codigo_vendedor = 'V002',
     @productos = 'TF-ME-0001:50', @observaciones = 'Prueba de inventario insuficiente',
     @id_cotizacion = @cot3 OUTPUT;
EXEC sp_CambiarEstadoCotizacion @cot3, 'Firme';
EXEC sp_CambiarEstadoCotizacion @cot3, 'Confirmada';
EXEC sp_GenerarPedido @id_cotizacion = @cot3, @id_pedido = @ped3 OUTPUT;
BEGIN TRY
    EXEC sp_Facturar @id_pedido = @ped3;
END TRY
BEGIN CATCH
    SELECT 'Prueba 11: inventario insuficiente' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- =====================================================
-- ANULACIÓN DE FACTURA (consumidor final que se arrepiente)
-- =====================================================
EXEC sp_CrearCotizacion @codigo_cliente = 'C0013', @codigo_vendedor = 'V001',
     @productos = 'MA-PV-0001:2', @observaciones = 'Venta que será anulada',
     @id_cotizacion = @cot2 OUTPUT;
EXEC sp_CambiarEstadoCotizacion @cot2, 'Firme';
EXEC sp_CambiarEstadoCotizacion @cot2, 'Confirmada';
EXEC sp_GenerarPedido @id_cotizacion = @cot2, @id_pedido = @ped2 OUTPUT;
EXEC sp_Facturar @id_pedido = @ped2, @id_factura = @fac2 OUTPUT;
EXEC sp_AnularFactura @id_factura = @fac2, @motivo = 'El cliente desistió de la compra';

-- PRUEBA 12: cobrar una factura anulada
BEGIN TRY
    EXEC sp_RegistrarCobro @id_factura = @fac2, @monto = 10;
END TRY
BEGIN CATCH
    SELECT 'Prueba 12: cobrar factura anulada' AS Prueba, 'RECHAZADO: ' + ERROR_MESSAGE() AS Resultado;
END CATCH

-- =====================================================
-- RESUMEN FINAL DE LA VENTA EN VIVO
-- =====================================================
-- a) Trazabilidad: toda la cadena de documentos
SELECT c.numero AS Cotizacion, c.estado AS Estado_Cotizacion,
       p.numero AS Pedido, p.estado AS Estado_Pedido, p.autorizado_por,
       f.numero_documento AS Factura, f.total, f.estado AS Estado_Factura, f.estado_pago,
       (SELECT STRING_AGG(numero, ', ') FROM Cobro WHERE id_factura = f.id_factura)    AS Cobros,
       (SELECT STRING_AGG(numero, ', ') FROM Despacho WHERE id_factura = f.id_factura) AS Despacho
FROM Cotizacion c
INNER JOIN Pedido  p ON p.id_cotizacion = c.id_cotizacion
INNER JOIN Factura f ON f.id_pedido     = p.id_pedido
WHERE c.id_cotizacion IN (@cot, @cot2);

-- b) Libro diario: las partidas que generó la venta (factura, 2 cobros, despacho)
SELECT pc.numero AS Partida, pc.tipo_documento, pc.documento_numero,
       cc.codigo AS Cuenta, cc.nombre AS Nombre_Cuenta, pd.debe, pd.haber
FROM Partida_Contable pc
INNER JOIN Partida_Detalle pd ON pd.id_partida = pc.id_partida
INNER JOIN Cuenta_Contable cc ON cc.id_cuenta  = pd.id_cuenta
WHERE (pc.tipo_documento = 'Factura'  AND pc.id_documento = @fac)
   OR (pc.tipo_documento = 'Cobro'    AND pc.id_documento IN (SELECT id_cobro FROM Cobro WHERE id_factura = @fac))
   OR (pc.tipo_documento = 'Despacho' AND pc.id_documento IN (SELECT id_despacho FROM Despacho WHERE id_factura = @fac))
ORDER BY pc.id_partida, pd.linea;

-- c) La factura anulada y su partida de reversión
SELECT pc.numero AS Partida, pc.tipo_documento, pc.documento_numero,
       cc.codigo AS Cuenta, cc.nombre AS Nombre_Cuenta, pd.debe, pd.haber
FROM Partida_Contable pc
INNER JOIN Partida_Detalle pd ON pd.id_partida = pc.id_partida
INNER JOIN Cuenta_Contable cc ON cc.id_cuenta  = pd.id_cuenta
WHERE pc.tipo_documento IN ('Factura', 'Anulación') AND pc.id_documento = @fac2
ORDER BY pc.id_partida, pd.linea;

-- d) Inventario del cable THHN 12 en la Casa Matriz: antes y después
SELECT 'CO-BC-0001' AS Producto, @stock_antes AS Disponible_Antes,
       dbo.fn_StockDisponible('CO-BC-0001', 'S01') AS Disponible_Despues,
       @stock_antes - dbo.fn_StockDisponible('CO-BC-0001', 'S01') AS Vendido;

-- e) Kardex: la salida registrada por el despacho
SELECT m.fecha, p.codigo, l.codigo AS Localizacion, m.tipo_movimiento,
       m.cantidad, m.saldo_resultante, m.documento_tipo, m.documento_numero
FROM Movimiento_Inventario m
INNER JOIN Producto     p ON p.id_producto     = m.id_producto
INNER JOIN Localizacion l ON l.id_localizacion = m.id_localizacion
WHERE m.documento_numero IN (SELECT numero FROM Despacho WHERE id_factura = @fac);

-- f) Bitácora: quién hizo qué
SELECT TOP 8 fecha, tabla, id_registro, accion, detalle, usuario
FROM Bitacora ORDER BY id_bitacora DESC;
