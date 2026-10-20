-- =====================================================
-- Script 09: Historial de Ventas (julio - octubre 2026)
-- Apertura + Compra + ~49 ventas completas usando los
-- procedimientos almacenados
-- =====================================================
USE SolucionesElectricas;
SET NOCOUNT ON;

-- Protección: este script se ejecuta UNA sola vez
IF EXISTS (SELECT 1 FROM Factura)
BEGIN
    PRINT 'Ya existen facturas: el historial ya fue cargado. No se hizo nada.';
    RETURN;
END

DECLARE @lineas tt_LineaPartida, @id_partida INT, @total DECIMAL(14,2), @desc VARCHAR(200);

-- -----------------------------------------------------
-- 1. PARTIDA DE APERTURA (30-jun-2026)
--    El inventario inicial se registra como aporte de capital
-- -----------------------------------------------------
UPDATE Movimiento_Inventario
SET fecha = '2026-06-30T07:00:00'
WHERE tipo_movimiento = 'Inventario Inicial';

INSERT INTO @lineas (id_cuenta, tipo_monto, monto, id_cliente, descripcion)
SELECT vc.id_cuenta_inventario, 'D',
       CAST(SUM(i.cantidad * p.costo_unitario) AS DECIMAL(14,2)), NULL, 'Inventario inicial'
FROM Inventario i
INNER JOIN Producto           p  ON p.id_producto  = i.id_producto
INNER JOIN vw_Producto_Cuenta vc ON vc.id_producto = i.id_producto
GROUP BY vc.id_cuenta_inventario;

SELECT @total = SUM(monto) FROM @lineas;

INSERT INTO @lineas (id_cuenta, tipo_monto, monto, id_cliente, descripcion)
SELECT id_cuenta, 'H', @total, NULL, 'Aporte de capital en mercadería'
FROM Cuenta_Contable WHERE codigo = '3.1.01.01';

SET @desc = 'Partida de apertura: inventario inicial aportado como capital';
EXEC sp_RegistrarPartida @tipo_documento = 'Ajuste', @id_documento = 1,
     @documento_numero = 'APERTURA-2026', @descripcion = @desc,
     @lineas = @lineas, @id_partida = @id_partida OUTPUT;
UPDATE Partida_Contable SET fecha_contable = '2026-06-30' WHERE id_partida = @id_partida;
PRINT CONCAT('Partida de apertura registrada por Q', @total);

-- -----------------------------------------------------
-- 2. COMPRA DE MERCADERÍA (reabastecimiento, 30-jun-2026)
-- -----------------------------------------------------
DELETE FROM @lineas;
DECLARE @compra TABLE (id_inventario INT PRIMARY KEY, id_producto INT, id_localizacion INT,
                       cantidad DECIMAL(12,2), costo DECIMAL(12,4));

INSERT INTO @compra (id_inventario, id_producto, id_localizacion, cantidad, costo)
SELECT i.id_inventario, i.id_producto, i.id_localizacion,
       CASE WHEN p.codigo_um = 'MT' THEN 2000 ELSE 100 END, p.costo_unitario
FROM Inventario i
INNER JOIN Producto p ON p.id_producto = i.id_producto
WHERE p.precio_unitario < 5000;             -- los equipos caros no se reabastecen

-- Kardex: entrada de mercadería
INSERT INTO Movimiento_Inventario (fecha, id_producto, id_localizacion, tipo_movimiento, cantidad,
                                   costo_unitario, saldo_resultante, documento_tipo,
                                   documento_numero, justificacion)
SELECT '2026-06-30T15:00:00', c.id_producto, c.id_localizacion, 'Entrada', c.cantidad, c.costo,
       i.cantidad + c.cantidad, 'COMPRA', 'OC-2026-0001', 'Reabastecimiento de mercadería'
FROM @compra c
INNER JOIN Inventario i ON i.id_inventario = c.id_inventario;

UPDATE i SET cantidad = i.cantidad + c.cantidad
FROM Inventario i
INNER JOIN @compra c ON c.id_inventario = i.id_inventario;

-- Partida: Debe Inventario / Haber Proveedores
INSERT INTO @lineas (id_cuenta, tipo_monto, monto, id_cliente, descripcion)
SELECT vc.id_cuenta_inventario, 'D', CAST(SUM(c.cantidad * c.costo) AS DECIMAL(14,2)),
       NULL, 'Compra de mercadería'
FROM @compra c
INNER JOIN vw_Producto_Cuenta vc ON vc.id_producto = c.id_producto
GROUP BY vc.id_cuenta_inventario;

SELECT @total = SUM(monto) FROM @lineas;

INSERT INTO @lineas (id_cuenta, tipo_monto, monto, id_cliente, descripcion)
SELECT id_cuenta, 'H', @total, NULL, 'Cuenta por pagar a proveedores'
FROM Cuenta_Contable WHERE codigo = '2.1.01.01';

SET @desc = 'Compra de mercadería según orden OC-2026-0001';
EXEC sp_RegistrarPartida @tipo_documento = 'Ajuste', @id_documento = 2,
     @documento_numero = 'OC-2026-0001', @descripcion = @desc,
     @lineas = @lineas, @id_partida = @id_partida OUTPUT;
UPDATE Partida_Contable SET fecha_contable = '2026-06-30' WHERE id_partida = @id_partida;
PRINT CONCAT('Compra de mercadería registrada por Q', @total);

-- -----------------------------------------------------
-- 3. PLAN DE VENTAS
--    36 ventas al azar + 7 de Constructora Los Altos en septiembre
--    + 6 de Agroindustrias La Ceiba en agosto (para la consulta
--    "clientes con más de 5 facturas al mes")
-- -----------------------------------------------------
DECLARE @temp TABLE (fecha DATE, cliente VARCHAR(10));
DECLARE @plan TABLE (nro INT IDENTITY(1,1), fecha DATE, cliente VARCHAR(10));

INSERT INTO @temp (fecha, cliente)
SELECT TOP (36) DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 110, '20260701'), c.codigo
FROM Cliente c
CROSS JOIN (VALUES (1), (2), (3)) AS x(n)
ORDER BY NEWID();

INSERT INTO @temp (fecha, cliente) VALUES
('2026-09-02','C0001'), ('2026-09-05','C0001'), ('2026-09-09','C0001'), ('2026-09-14','C0001'),
('2026-09-18','C0001'), ('2026-09-23','C0001'), ('2026-09-28','C0001'),
('2026-08-03','C0009'), ('2026-08-07','C0009'), ('2026-08-12','C0009'),
('2026-08-17','C0009'), ('2026-08-21','C0009'), ('2026-08-26','C0009');

INSERT INTO @plan (fecha, cliente)
SELECT fecha, cliente FROM @temp ORDER BY fecha;      -- en orden cronológico

-- -----------------------------------------------------
-- 4. CICLO: cada venta recorre TODO el flujo
-- -----------------------------------------------------
DECLARE @i INT = 1, @n INT, @fecha DATE, @cli VARCHAR(10), @vend VARCHAR(10),
        @prod VARCHAR(MAX), @descuento VARCHAR(50), @metodo VARCHAR(15), @cuenta VARCHAR(30),
        @cot INT, @ped INT, @fac INT, @monto DECIMAL(14,2), @info VARCHAR(200),
        @hoy DATE = CAST(GETDATE() AS DATE), @ok INT = 0, @fallidas INT = 0;
DECLARE @errores TABLE (nro INT, mensaje NVARCHAR(400));

SELECT @n = COUNT(*) FROM @plan;

WHILE @i <= @n
BEGIN
    SELECT @fecha = fecha, @cli = cliente FROM @plan WHERE nro = @i;

    SELECT @vend = v.codigo
    FROM Cliente c INNER JOIN Vendedor v ON v.id_vendedor = c.id_vendedor
    WHERE c.codigo = @cli;

    -- 2 a 4 productos al azar (metros: 20-100; unidades: 1-4)
    SELECT @prod = STRING_AGG(CONCAT(x.codigo, ':', x.cant), ';')
    FROM (SELECT TOP (2 + ABS(CHECKSUM(NEWID())) % 3) p.codigo,
                 CASE WHEN p.codigo_um = 'MT' THEN 20 + ABS(CHECKSUM(NEWID())) % 81
                      ELSE 1 + ABS(CHECKSUM(NEWID())) % 4 END AS cant
          FROM Producto p
          WHERE p.precio_unitario < 5000
          ORDER BY NEWID()) x;

    -- Forma de pago: efectivo, transferencia o cheque
    SET @metodo = CASE @i % 3 WHEN 0 THEN 'Efectivo' WHEN 1 THEN 'Transferencia' ELSE 'Cheque' END;
    SET @cuenta = CASE @i % 3 WHEN 0 THEN NULL WHEN 1 THEN '000-123456-7' ELSE '3-045-12345-6' END;

    SELECT @cot = NULL, @ped = NULL, @fac = NULL, @info = NULL;

    BEGIN TRY
        -- ETAPA 1: Cotización -> Firme -> Confirmada
        EXEC sp_CrearCotizacion @codigo_cliente = @cli, @codigo_vendedor = @vend,
             @productos = @prod, @id_cotizacion = @cot OUTPUT;
        EXEC sp_CambiarEstadoCotizacion @cot, 'Firme';
        EXEC sp_CambiarEstadoCotizacion @cot, 'Confirmada';

        -- ETAPA 2: Pedido (1 de cada 5 con descuento del 5% autorizado por el gerente)
        IF @i % 5 = 0
        BEGIN
            SET @descuento = CONCAT(LEFT(@prod, CHARINDEX(':', @prod) - 1), ':5');
            EXEC sp_GenerarPedido @id_cotizacion = @cot, @descuentos = @descuento,
                 @id_pedido = @ped OUTPUT;
            EXEC sp_AutorizarDescuento @id_pedido = @ped, @username = 'rcastillo';
        END
        ELSE
            EXEC sp_GenerarPedido @id_cotizacion = @cot, @id_pedido = @ped OUTPUT;

        -- ETAPA 3: Factura
        EXEC sp_Facturar @id_pedido = @ped, @id_factura = @fac OUTPUT;
        SELECT @total = total FROM Factura WHERE id_factura = @fac;

        -- ETAPAS 4 y 5: Cobro y Despacho
        IF @i % 7 = 1                                   -- pago PARCIAL (sin despacho)
        BEGIN
            SET @monto = CAST(@total / 2 AS DECIMAL(14,2));
            EXEC sp_RegistrarCobro @id_factura = @fac, @monto = @monto, @metodo_pago = @metodo,
                 @numero_cuenta_bancaria = @cuenta, @referencia = 'Abono';
        END
        ELSE IF @i % 7 <> 0                             -- pago TOTAL (y despacho)
        BEGIN
            EXEC sp_RegistrarCobro @id_factura = @fac, @monto = @total, @metodo_pago = @metodo,
                 @numero_cuenta_bancaria = @cuenta, @referencia = 'Pago total';
            IF @i % 9 <> 0                              -- algunos aún no recogen
                EXEC sp_Despachar @id_factura = @fac, @recibido_por = 'Representante del cliente';
        END
        -- (@i % 7 = 0): factura SIN pagar -> queda pendiente de cobro

        -- Mover las fechas al día de la venta (simulación de historial)
        UPDATE Cotizacion SET fecha_solicitud = @fecha, fecha_tentativa_compra = DATEADD(DAY, 3, @fecha)
        WHERE id_cotizacion = @cot;
        UPDATE Pedido SET fecha_pedido = @fecha WHERE id_pedido = @ped;
        UPDATE f SET fecha_factura = @fecha, fecha_vencimiento = DATEADD(DAY, c.dias_credito, @fecha)
        FROM Factura f INNER JOIN Cliente c ON c.id_cliente = f.id_cliente
        WHERE f.id_factura = @fac;
        UPDATE Cobro
        SET fecha_cobro = CASE WHEN DATEADD(DAY, 2, @fecha) > @hoy THEN @hoy ELSE DATEADD(DAY, 2, @fecha) END
        WHERE id_factura = @fac;
        UPDATE Despacho
        SET fecha_despacho = CASE WHEN DATEADD(DAY, 3, CAST(@fecha AS DATETIME2(0))) > SYSDATETIME()
                                  THEN SYSDATETIME()
                                  ELSE DATEADD(DAY, 3, CAST(@fecha AS DATETIME2(0))) END
        WHERE id_factura = @fac;
        UPDATE pc SET fecha_contable = @fecha
        FROM Partida_Contable pc
        WHERE pc.tipo_documento = 'Factura' AND pc.id_documento = @fac;
        UPDATE pc SET fecha_contable = co.fecha_cobro
        FROM Partida_Contable pc INNER JOIN Cobro co ON co.id_cobro = pc.id_documento
        WHERE pc.tipo_documento = 'Cobro' AND co.id_factura = @fac;
        UPDATE pc SET fecha_contable = CAST(d.fecha_despacho AS DATE)
        FROM Partida_Contable pc INNER JOIN Despacho d ON d.id_despacho = pc.id_documento
        WHERE pc.tipo_documento = 'Despacho' AND d.id_factura = @fac;
        UPDATE m SET fecha = d.fecha_despacho
        FROM Movimiento_Inventario m INNER JOIN Despacho d ON d.numero = m.documento_numero
        WHERE m.documento_tipo = 'DESPACHO' AND d.id_factura = @fac;

        SET @ok += 1;

        -- Primero se guarda en una variable, luego se imprime
        SELECT @info = numero_documento + ' | Q' + CAST(total AS VARCHAR(20)) + ' | ' + estado_pago
        FROM Factura WHERE id_factura = @fac;
        PRINT CONCAT('OK  Venta ', @i, ' | ', @fecha, ' | ', @cli, ' | ', @info);
    END TRY
    BEGIN CATCH
        SET @fallidas += 1;
        INSERT INTO @errores VALUES (@i, ERROR_MESSAGE());
        PRINT CONCAT('--  Venta ', @i, ' no completada: ', ERROR_MESSAGE());
    END CATCH

    SET @i += 1;
END

-- -----------------------------------------------------
-- 5. RESUMEN (primero en variables, luego PRINT)
-- -----------------------------------------------------
DECLARE @c_cot INT, @c_ped INT, @c_fac INT, @c_cob INT, @c_des INT, @c_pda INT,
        @t_debe DECIMAL(14,2), @t_haber DECIMAL(14,2);

SELECT @c_cot = COUNT(*) FROM Cotizacion;
SELECT @c_ped = COUNT(*) FROM Pedido;
SELECT @c_fac = COUNT(*) FROM Factura;
SELECT @c_cob = COUNT(*) FROM Cobro;
SELECT @c_des = COUNT(*) FROM Despacho;
SELECT @c_pda = COUNT(*) FROM Partida_Contable;
SELECT @t_debe = SUM(debe), @t_haber = SUM(haber) FROM Partida_Detalle;

PRINT '==================================================';
PRINT CONCAT('Ventas completadas: ', @ok, '   |   No completadas: ', @fallidas);
PRINT CONCAT('Cotizaciones: ', @c_cot, ' | Pedidos: ', @c_ped, ' | Facturas: ', @c_fac,
             ' | Cobros: ', @c_cob, ' | Despachos: ', @c_des, ' | Partidas: ', @c_pda);
PRINT CONCAT('Total Debe: Q', @t_debe, '  =  Total Haber: Q', @t_haber);
PRINT '==================================================';
