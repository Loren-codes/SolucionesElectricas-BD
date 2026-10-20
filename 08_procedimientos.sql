-- =====================================================
-- Script 08: Procedimientos Almacenados del Proceso de Ventas
-- =====================================================
USE SolucionesElectricas;
GO

-- -----------------------------------------------------
-- 0. LIMPIEZA
-- -----------------------------------------------------
DROP PROCEDURE IF EXISTS sp_AnularFactura, sp_Despachar, sp_RegistrarCobro,
                         sp_Facturar, sp_AutorizarDescuento, sp_GenerarPedido,
                         sp_CambiarEstadoCotizacion, sp_CrearCotizacion,
                         sp_RegistrarPartida;
DROP FUNCTION IF EXISTS fn_StockDisponible;
DROP TYPE IF EXISTS tt_LineaPartida;
GO

-- -----------------------------------------------------
-- 1. TIPO DE TABLA para las líneas de una partida
-- -----------------------------------------------------
CREATE TYPE tt_LineaPartida AS TABLE (
    id_cuenta   INT           NOT NULL,
    tipo_monto  CHAR(1)       NOT NULL,      -- D o H
    monto       DECIMAL(14,2) NOT NULL,
    id_cliente  INT           NULL,
    descripcion VARCHAR(200)  NULL
);
GO

-- -----------------------------------------------------
-- 2. FUNCION: stock disponible de un producto en un sitio
-- -----------------------------------------------------
CREATE FUNCTION fn_StockDisponible (@codigo_producto VARCHAR(15), @codigo_sitio VARCHAR(10))
RETURNS DECIMAL(12,2)
AS
BEGIN
    DECLARE @resultado DECIMAL(12,2);
    SELECT @resultado = SUM(i.cantidad_disponible)
    FROM Inventario i
    INNER JOIN Producto     p ON p.id_producto     = i.id_producto
    INNER JOIN Localizacion l ON l.id_localizacion = i.id_localizacion
    INNER JOIN Bodega       b ON b.id_bodega       = l.id_bodega
    INNER JOIN Sitio        s ON s.id_sitio        = b.id_sitio
    WHERE p.codigo = @codigo_producto AND s.codigo = @codigo_sitio;
    RETURN ISNULL(@resultado, 0);
END;
GO

-- -----------------------------------------------------
-- 3. sp_RegistrarPartida: guarda una partida SOLO si cuadra
-- -----------------------------------------------------
CREATE PROCEDURE sp_RegistrarPartida
    @tipo_documento   VARCHAR(15),
    @id_documento     INT,
    @documento_numero VARCHAR(30),
    @descripcion      VARCHAR(200),
    @lineas           tt_LineaPartida READONLY,
    @id_partida       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @debe DECIMAL(14,2), @haber DECIMAL(14,2), @msg NVARCHAR(400);

    SELECT @debe  = ISNULL(SUM(CASE WHEN tipo_monto = 'D' THEN monto END), 0),
           @haber = ISNULL(SUM(CASE WHEN tipo_monto = 'H' THEN monto END), 0)
    FROM @lineas
    WHERE monto > 0;

    IF @debe <> @haber OR @debe = 0
    BEGIN
        SET @msg = CONCAT(N'Partida descuadrada: Debe = ', @debe, N', Haber = ', @haber, N'.');
        ;THROW 50100, @msg, 1;
    END

    INSERT INTO Partida_Contable (tipo_documento, id_documento, documento_numero,
                                  descripcion, total_debe, total_haber)
    VALUES (@tipo_documento, @id_documento, @documento_numero,
            LEFT(@descripcion, 200), @debe, @haber);

    SET @id_partida = SCOPE_IDENTITY();

    INSERT INTO Partida_Detalle (id_partida, linea, id_cuenta, tipo_monto, monto, id_cliente, descripcion)
    SELECT @id_partida,
           ROW_NUMBER() OVER (ORDER BY tipo_monto, id_cuenta),
           id_cuenta, tipo_monto, SUM(monto), id_cliente, MAX(descripcion)
    FROM @lineas
    WHERE monto > 0
    GROUP BY id_cuenta, tipo_monto, id_cliente;
END;
GO

-- -----------------------------------------------------
-- 4. sp_CrearCotizacion  (ETAPA 1)
--    @productos = 'CO-BC-0001:100;MA-PV-0002:5'  (código:cantidad)
-- -----------------------------------------------------
CREATE PROCEDURE sp_CrearCotizacion
    @codigo_cliente  VARCHAR(10),
    @codigo_vendedor VARCHAR(10),
    @productos       VARCHAR(MAX),
    @codigo_moneda   CHAR(3)      = 'GTQ',
    @fecha_tentativa DATE         = NULL,
    @observaciones   VARCHAR(300) = NULL,
    @id_cotizacion   INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @id_cliente INT, @id_vendedor INT, @id_vendedor_cliente INT,
            @id_sitio INT, @tc DECIMAL(12,6) = 1, @msg NVARCHAR(400);
    DECLARE @items TABLE (codigo VARCHAR(15), cantidad DECIMAL(12,2));

    BEGIN TRY
        -- a) Validar cliente
        SELECT @id_cliente = id_cliente, @id_vendedor_cliente = id_vendedor
        FROM Cliente WHERE codigo = @codigo_cliente AND activo = 1;
        IF @id_cliente IS NULL
        BEGIN
            SET @msg = CONCAT(N'El cliente ', @codigo_cliente, N' no existe o está inactivo.');
            ;THROW 50101, @msg, 1;
        END

        -- b) Validar vendedor
        SELECT @id_vendedor = id_vendedor, @id_sitio = id_sitio
        FROM Vendedor WHERE codigo = @codigo_vendedor AND activo = 1;
        IF @id_vendedor IS NULL
        BEGIN
            SET @msg = CONCAT(N'El vendedor ', @codigo_vendedor, N' no existe o está inactivo.');
            ;THROW 50102, @msg, 1;
        END

        -- c) REGLA: un vendedor solo vende a los clientes que él consiguió
        IF @id_vendedor <> @id_vendedor_cliente
        BEGIN
            SELECT @msg = CONCAT(N'Regla de negocio: el vendedor ', @codigo_vendedor,
                                 N' no puede venderle al cliente ', @codigo_cliente,
                                 N', porque ese cliente lo consiguió el vendedor ', v.codigo, N'.')
            FROM Vendedor v WHERE v.id_vendedor = @id_vendedor_cliente;
            ;THROW 50103, @msg, 1;
        END

        -- d) Tipo de cambio (si no es quetzales)
        IF @codigo_moneda <> 'GTQ'
        BEGIN
            SET @tc = NULL;
            SELECT TOP 1 @tc = tasa FROM Tipo_Cambio
            WHERE codigo_moneda = @codigo_moneda AND fecha <= CAST(GETDATE() AS DATE)
            ORDER BY fecha DESC;
            IF @tc IS NULL
            BEGIN
                SET @msg = CONCAT(N'No hay tipo de cambio registrado para ', @codigo_moneda, N'.');
                ;THROW 50104, @msg, 1;
            END
        END

        -- e) Leer la lista de productos 'codigo:cantidad;codigo:cantidad'
        INSERT INTO @items (codigo, cantidad)
        SELECT LTRIM(RTRIM(LEFT(value, CASE WHEN CHARINDEX(':', value) > 0
                                            THEN CHARINDEX(':', value) - 1 ELSE 0 END))),
               TRY_CAST(SUBSTRING(value, CHARINDEX(':', value) + 1, 30) AS DECIMAL(12,2))
        FROM STRING_SPLIT(@productos, ';')
        WHERE LTRIM(RTRIM(value)) <> '';

        IF NOT EXISTS (SELECT 1 FROM @items)
            THROW 50105, N'La cotización debe tener al menos un producto.', 1;
        IF EXISTS (SELECT 1 FROM @items WHERE codigo = '' OR cantidad IS NULL OR cantidad <= 0)
            THROW 50106, N'Formato inválido. Use código:cantidad separados por punto y coma.', 1;

        SELECT TOP 1 @msg = CONCAT(N'El producto ', i.codigo, N' no existe o está inactivo.')
        FROM @items i
        LEFT JOIN Producto p ON p.codigo = i.codigo AND p.activo = 1
        WHERE p.id_producto IS NULL;
        IF @msg IS NOT NULL THROW 50107, @msg, 1;

        -- f) Unidades que no aceptan decimales (no se vende media unidad)
        SELECT TOP 1 @msg = CONCAT(N'El producto ', i.codigo, N' se vende por ', um.nombre,
                                   N' y no acepta cantidades con decimales.')
        FROM @items i
        INNER JOIN Producto      p  ON p.codigo  = i.codigo
        INNER JOIN Unidad_Medida um ON um.codigo = p.codigo_um
        WHERE um.permite_decimales = 0 AND i.cantidad <> FLOOR(i.cantidad);
        IF @msg IS NOT NULL THROW 50108, @msg, 1;

        -- g) Guardar (TODO o NADA)
        BEGIN TRANSACTION;

            INSERT INTO Cotizacion (id_cliente, id_vendedor, id_sitio, codigo_moneda,
                                    tipo_cambio, fecha_tentativa_compra, observaciones)
            VALUES (@id_cliente, @id_vendedor, @id_sitio, @codigo_moneda,
                    @tc, @fecha_tentativa, @observaciones);

            SET @id_cotizacion = SCOPE_IDENTITY();

            INSERT INTO Cotizacion_Detalle (id_cotizacion, id_producto, cantidad, precio_unitario)
            SELECT @id_cotizacion, p.id_producto, SUM(i.cantidad),
                   CAST(p.precio_unitario / @tc AS DECIMAL(12,2))   -- precio con IVA incluido
            FROM @items i
            INNER JOIN Producto p ON p.codigo = i.codigo
            GROUP BY p.id_producto, p.precio_unitario;

            UPDATE Cotizacion
            SET total = (SELECT SUM(total_linea) FROM Cotizacion_Detalle
                         WHERE id_cotizacion = @id_cotizacion)
            WHERE id_cotizacion = @id_cotizacion;

        COMMIT TRANSACTION;

        SELECT c.numero AS Cotizacion, cl.nombre_comercial AS Cliente, v.codigo AS Vendedor,
               c.estado, c.codigo_moneda, c.total
        FROM Cotizacion c
        INNER JOIN Cliente  cl ON cl.id_cliente = c.id_cliente
        INNER JOIN Vendedor v  ON v.id_vendedor = c.id_vendedor
        WHERE c.id_cotizacion = @id_cotizacion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- -----------------------------------------------------
-- 5. sp_CambiarEstadoCotizacion
--    En proceso -> Firme -> Confirmada   (o Anulada)
-- -----------------------------------------------------
CREATE PROCEDURE sp_CambiarEstadoCotizacion
    @id_cotizacion INT,
    @nuevo_estado  VARCHAR(15)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @estado_actual VARCHAR(15), @msg NVARCHAR(400);

    BEGIN TRY
        SELECT @estado_actual = estado FROM Cotizacion WHERE id_cotizacion = @id_cotizacion;
        IF @estado_actual IS NULL
            THROW 50110, N'La cotización no existe.', 1;

        IF NOT (   (@estado_actual = 'En proceso' AND @nuevo_estado IN ('Firme', 'Anulada'))
                OR (@estado_actual = 'Firme'      AND @nuevo_estado IN ('Confirmada', 'Anulada'))
                OR (@estado_actual = 'Confirmada' AND @nuevo_estado = 'Anulada'
                    AND NOT EXISTS (SELECT 1 FROM Pedido WHERE id_cotizacion = @id_cotizacion)))
        BEGIN
            SET @msg = CONCAT(N'Cambio de estado no permitido: ', @estado_actual, N' -> ', @nuevo_estado, N'.');
            ;THROW 50111, @msg, 1;
        END

        BEGIN TRANSACTION;
            UPDATE Cotizacion SET estado = @nuevo_estado WHERE id_cotizacion = @id_cotizacion;

            INSERT INTO Bitacora (tabla, id_registro, accion, detalle)
            VALUES ('Cotizacion', @id_cotizacion, 'Cambio de estado',
                    CONCAT(@estado_actual, ' -> ', @nuevo_estado));
        COMMIT TRANSACTION;

        SELECT numero AS Cotizacion, @estado_actual AS Estado_Anterior, estado AS Estado_Nuevo
        FROM Cotizacion WHERE id_cotizacion = @id_cotizacion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- -----------------------------------------------------
-- 6. sp_GenerarPedido  (ETAPA 2)
--    @descuentos = 'CO-BC-0001:5;MA-PV-0002:10'  (código:porcentaje)
-- -----------------------------------------------------
CREATE PROCEDURE sp_GenerarPedido
    @id_cotizacion INT,
    @descuentos    VARCHAR(MAX) = NULL,
    @id_pedido     INT          = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @estado VARCHAR(15), @msg NVARCHAR(400);
    DECLARE @desc TABLE (codigo VARCHAR(15), pct DECIMAL(5,2));

    BEGIN TRY
        SELECT @estado = estado FROM Cotizacion WHERE id_cotizacion = @id_cotizacion;
        IF @estado IS NULL
            THROW 50120, N'La cotización no existe.', 1;
        IF @estado <> 'Confirmada'
        BEGIN
            SET @msg = CONCAT(N'Solo se genera pedido de una cotización Confirmada. Estado actual: ', @estado, N'.');
            ;THROW 50121, @msg, 1;
        END
        IF EXISTS (SELECT 1 FROM Pedido WHERE id_cotizacion = @id_cotizacion)
            THROW 50122, N'Esta cotización ya tiene un pedido.', 1;

        -- Leer descuentos solicitados por el cliente
        INSERT INTO @desc (codigo, pct)
        SELECT LTRIM(RTRIM(LEFT(value, CASE WHEN CHARINDEX(':', value) > 0
                                            THEN CHARINDEX(':', value) - 1 ELSE 0 END))),
               TRY_CAST(SUBSTRING(value, CHARINDEX(':', value) + 1, 30) AS DECIMAL(5,2))
        FROM STRING_SPLIT(ISNULL(@descuentos, ''), ';')
        WHERE LTRIM(RTRIM(value)) <> '';

        IF EXISTS (SELECT 1 FROM @desc WHERE codigo = '' OR pct IS NULL OR pct < 0 OR pct > 50)
            THROW 50123, N'Descuento inválido: use código:porcentaje y máximo 50%.', 1;

        SELECT TOP 1 @msg = CONCAT(N'El producto ', d.codigo, N' no está en la cotización.')
        FROM @desc d
        WHERE NOT EXISTS (SELECT 1 FROM Cotizacion_Detalle cd
                          INNER JOIN Producto p ON p.id_producto = cd.id_producto
                          WHERE cd.id_cotizacion = @id_cotizacion AND p.codigo = d.codigo);
        IF @msg IS NOT NULL THROW 50124, @msg, 1;

        BEGIN TRANSACTION;

            INSERT INTO Pedido (id_cotizacion, id_cliente, id_vendedor, id_sitio,
                                codigo_moneda, tipo_cambio)
            SELECT id_cotizacion, id_cliente, id_vendedor, id_sitio, codigo_moneda, tipo_cambio
            FROM Cotizacion WHERE id_cotizacion = @id_cotizacion;

            SET @id_pedido = SCOPE_IDENTITY();

            -- Detalle: el IVA, la base imponible y el total se calculan solos
            INSERT INTO Pedido_Detalle (id_pedido, id_producto, cantidad, precio_lista,
                                        descuento_pct, precio_unitario, codigo_iva, porcentaje_iva)
            SELECT @id_pedido, cd.id_producto, cd.cantidad, cd.precio_unitario,
                   ISNULL(d.pct, 0),
                   CAST(cd.precio_unitario * (1 - ISNULL(d.pct, 0) / 100) AS DECIMAL(12,2)),
                   p.codigo_iva, imp.porcentaje
            FROM Cotizacion_Detalle cd
            INNER JOIN Producto p   ON p.id_producto  = cd.id_producto
            INNER JOIN Impuesto imp ON imp.codigo_iva = p.codigo_iva
            LEFT  JOIN @desc d      ON d.codigo       = p.codigo
            WHERE cd.id_cotizacion = @id_cotizacion;

            -- Totales del encabezado = suma de las líneas
            UPDATE pe
            SET base_imponible = t.base, iva = t.iva, total = t.total,
                estado = CASE WHEN t.con_descuento > 0
                              THEN 'Pendiente Autorización' ELSE 'Pendiente' END
            FROM Pedido pe
            CROSS APPLY (SELECT SUM(base_imponible) AS base, SUM(iva) AS iva,
                                SUM(total_linea) AS total,
                                SUM(CASE WHEN descuento_pct > 0 THEN 1 ELSE 0 END) AS con_descuento
                         FROM Pedido_Detalle WHERE id_pedido = pe.id_pedido) t
            WHERE pe.id_pedido = @id_pedido;

            -- Validación del enunciado: IVA del encabezado = suma del IVA de las líneas
            IF EXISTS (SELECT 1 FROM Pedido pe
                       WHERE pe.id_pedido = @id_pedido
                         AND pe.iva <> (SELECT SUM(iva) FROM Pedido_Detalle
                                        WHERE id_pedido = @id_pedido))
                THROW 50125, N'El IVA del encabezado no coincide con la suma de las líneas.', 1;

            IF EXISTS (SELECT 1 FROM @desc WHERE pct > 0)
                INSERT INTO Bitacora (tabla, id_registro, accion, detalle)
                VALUES ('Pedido', @id_pedido, 'Descuento solicitado',
                        CONCAT('Descuentos: ', @descuentos, ' - requiere autorización'));

        COMMIT TRANSACTION;

        SELECT pe.numero AS Pedido, pe.estado, pr.codigo AS Producto, pd.cantidad,
               pd.precio_lista, pd.descuento_pct, pd.precio_unitario,
               pd.base_imponible, pd.iva, pd.total_linea,
               pe.base_imponible AS Base_Total, pe.iva AS IVA_Total, pe.total AS Total_Pedido
        FROM Pedido pe
        INNER JOIN Pedido_Detalle pd ON pd.id_pedido   = pe.id_pedido
        INNER JOIN Producto       pr ON pr.id_producto = pd.id_producto
        WHERE pe.id_pedido = @id_pedido;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- -----------------------------------------------------
-- 7. sp_AutorizarDescuento
--    Solo un Gerente o Administrador puede autorizar
-- -----------------------------------------------------
CREATE PROCEDURE sp_AutorizarDescuento
    @id_pedido INT,
    @username  VARCHAR(30),
    @aprobar   BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @estado VARCHAR(25), @rol VARCHAR(20), @msg NVARCHAR(400);

    BEGIN TRY
        SELECT @estado = estado FROM Pedido WHERE id_pedido = @id_pedido;
        IF @estado IS NULL
            THROW 50130, N'El pedido no existe.', 1;
        IF @estado <> 'Pendiente Autorización'
        BEGIN
            SET @msg = CONCAT(N'El pedido no está pendiente de autorización. Estado: ', @estado, N'.');
            ;THROW 50131, @msg, 1;
        END

        SELECT @rol = rol FROM Usuario WHERE username = @username AND activo = 1;
        IF @rol IS NULL OR @rol NOT IN ('Gerente', 'Administrador')
        BEGIN
            SET @msg = CONCAT(N'El usuario ', @username,
                              N' no tiene permiso: solo un Gerente o Administrador autoriza descuentos.');
            ;THROW 50132, @msg, 1;
        END

        BEGIN TRANSACTION;

            IF @aprobar = 1
                UPDATE Pedido
                SET estado = 'Autorizado', autorizado_por = @username,
                    fecha_autorizacion = SYSDATETIME()
                WHERE id_pedido = @id_pedido;
            ELSE
            BEGIN
                -- Rechazado: se quitan los descuentos
                UPDATE Pedido_Detalle
                SET descuento_pct = 0, precio_unitario = precio_lista
                WHERE id_pedido = @id_pedido AND descuento_pct > 0;

                UPDATE Pedido SET estado = 'Pendiente' WHERE id_pedido = @id_pedido;
            END

            -- Recalcular totales
            UPDATE pe
            SET base_imponible = t.base, iva = t.iva, total = t.total
            FROM Pedido pe
            CROSS APPLY (SELECT SUM(base_imponible) AS base, SUM(iva) AS iva, SUM(total_linea) AS total
                         FROM Pedido_Detalle WHERE id_pedido = pe.id_pedido) t
            WHERE pe.id_pedido = @id_pedido;

            INSERT INTO Bitacora (tabla, id_registro, accion, detalle)
            VALUES ('Pedido', @id_pedido,
                    CASE WHEN @aprobar = 1 THEN 'Descuento autorizado' ELSE 'Descuento rechazado' END,
                    CONCAT('Por: ', @username));

        COMMIT TRANSACTION;

        SELECT numero AS Pedido, estado, autorizado_por, base_imponible, iva, total
        FROM Pedido WHERE id_pedido = @id_pedido;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- -----------------------------------------------------
-- 8. sp_Facturar  (ETAPA 3)
-- -----------------------------------------------------
CREATE PROCEDURE sp_Facturar
    @id_pedido  INT,
    @id_factura INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @estado VARCHAR(25), @id_sitio INT, @id_cliente INT, @serie VARCHAR(10),
            @numero INT, @tc DECIMAL(12,6), @num_doc VARCHAR(30), @descripcion VARCHAR(200),
            @total_haber DECIMAL(14,2), @id_partida INT, @msg NVARCHAR(400);
    DECLARE @lineas tt_LineaPartida;

    BEGIN TRY
        SELECT @estado = pe.estado, @id_sitio = pe.id_sitio, @id_cliente = pe.id_cliente,
               @tc = pe.tipo_cambio, @serie = s.codigo
        FROM Pedido pe
        INNER JOIN Sitio s ON s.id_sitio = pe.id_sitio
        WHERE pe.id_pedido = @id_pedido;

        IF @estado IS NULL
            THROW 50140, N'El pedido no existe.', 1;
        IF @estado = 'Pendiente Autorización'
            THROW 50141, N'No se puede facturar: el pedido tiene descuentos pendientes de autorización.', 1;
        IF @estado NOT IN ('Pendiente', 'Autorizado')
        BEGIN
            SET @msg = CONCAT(N'No se puede facturar un pedido en estado ', @estado, N'.');
            ;THROW 50142, @msg, 1;
        END

        BEGIN TRANSACTION;

            -- REGLA: debe existir inventario suficiente en el sitio
            -- (UPDLOCK, HOLDLOCK = AISLAMIENTO: nadie más toma ese inventario mientras facturamos)
            SELECT TOP 1 @msg = CONCAT(N'Inventario insuficiente de ', p.codigo, N': se requieren ',
                                       pd.cantidad, N' y hay disponibles ', ISNULL(x.disponible, 0), N'.')
            FROM Pedido_Detalle pd
            INNER JOIN Producto p ON p.id_producto = pd.id_producto
            OUTER APPLY (SELECT SUM(i.cantidad_disponible) AS disponible
                         FROM Inventario i WITH (UPDLOCK, HOLDLOCK)
                         INNER JOIN Localizacion l ON l.id_localizacion = i.id_localizacion
                         INNER JOIN Bodega       b ON b.id_bodega       = l.id_bodega
                         WHERE i.id_producto = pd.id_producto AND b.id_sitio = @id_sitio) x
            WHERE pd.id_pedido = @id_pedido AND ISNULL(x.disponible, 0) < pd.cantidad;
            IF @msg IS NOT NULL THROW 50143, @msg, 1;

            -- Correlativo de la serie (serie = código del sitio)
            SELECT @numero = ISNULL(MAX(numero), 0) + 1
            FROM Factura WITH (UPDLOCK, HOLDLOCK) WHERE serie = @serie;

            INSERT INTO Factura (serie, numero, id_pedido, fecha_vencimiento, id_cliente,
                                 id_vendedor, id_sitio, codigo_moneda, tipo_cambio,
                                 base_imponible, iva, total, saldo_pendiente)
            SELECT @serie, @numero, pe.id_pedido,
                   DATEADD(DAY, c.dias_credito, CAST(GETDATE() AS DATE)),
                   pe.id_cliente, pe.id_vendedor, pe.id_sitio, pe.codigo_moneda, pe.tipo_cambio,
                   pe.base_imponible, pe.iva, pe.total, pe.total
            FROM Pedido pe
            INNER JOIN Cliente c ON c.id_cliente = pe.id_cliente
            WHERE pe.id_pedido = @id_pedido;

            SET @id_factura = SCOPE_IDENTITY();

            INSERT INTO Factura_Detalle (id_factura, id_producto, cantidad, precio_unitario,
                                         codigo_iva, porcentaje_iva, costo_unitario)
            SELECT @id_factura, pd.id_producto, pd.cantidad, pd.precio_unitario,
                   pd.codigo_iva, pd.porcentaje_iva, p.costo_unitario
            FROM Pedido_Detalle pd
            INNER JOIN Producto p ON p.id_producto = pd.id_producto
            WHERE pd.id_pedido = @id_pedido;

            -- RESERVAR inventario en las localizaciones del sitio
            ;WITH inv AS (
                SELECT i.id_inventario, i.cantidad_disponible AS disp, fd.cantidad AS requerida,
                       SUM(i.cantidad_disponible) OVER (PARTITION BY i.id_producto
                           ORDER BY i.cantidad_disponible DESC, i.id_inventario
                           ROWS UNBOUNDED PRECEDING) AS acumulado
                FROM Inventario i
                INNER JOIN Localizacion    l  ON l.id_localizacion = i.id_localizacion
                INNER JOIN Bodega          b  ON b.id_bodega       = l.id_bodega
                INNER JOIN Factura_Detalle fd ON fd.id_producto    = i.id_producto
                WHERE fd.id_factura = @id_factura AND b.id_sitio = @id_sitio
                  AND i.cantidad_disponible > 0
            )
            UPDATE i
            SET i.cantidad_reservada      = i.cantidad_reservada + r.reservar,
                i.fecha_ultimo_movimiento = SYSDATETIME()
            FROM Inventario i
            INNER JOIN (SELECT id_inventario,
                               CASE WHEN acumulado <= requerida THEN disp
                                    WHEN acumulado - disp < requerida THEN requerida - (acumulado - disp)
                                    ELSE 0 END AS reservar
                        FROM inv) r ON r.id_inventario = i.id_inventario
            WHERE r.reservar > 0;

            -- PARTIDA CONTABLE DE LA FACTURA
            --   Debe:  Clientes            (total)
            --   Haber: Ventas por cuenta   (base imponible)
            --   Haber: IVA por Pagar       (IVA)
            INSERT INTO @lineas (id_cuenta, tipo_monto, monto, id_cliente, descripcion)
            SELECT vc.id_cuenta_venta, 'H', CAST(SUM(fd.base_imponible) * @tc AS DECIMAL(14,2)),
                   NULL, 'Venta de mercadería'
            FROM Factura_Detalle fd
            INNER JOIN vw_Producto_Cuenta vc ON vc.id_producto = fd.id_producto
            WHERE fd.id_factura = @id_factura
            GROUP BY vc.id_cuenta_venta;

            INSERT INTO @lineas (id_cuenta, tipo_monto, monto, id_cliente, descripcion)
            SELECT imp.id_cuenta_iva, 'H', CAST(SUM(fd.iva) * @tc AS DECIMAL(14,2)),
                   NULL, 'IVA débito fiscal'
            FROM Factura_Detalle fd
            INNER JOIN Impuesto imp ON imp.codigo_iva = fd.codigo_iva
            WHERE fd.id_factura = @id_factura AND fd.iva > 0
            GROUP BY imp.id_cuenta_iva;

            SELECT @total_haber = SUM(monto) FROM @lineas;

            INSERT INTO @lineas (id_cuenta, tipo_monto, monto, id_cliente, descripcion)
            SELECT c.id_cuenta_contable, 'D', @total_haber, c.id_cliente, 'Cuenta por cobrar al cliente'
            FROM Cliente c WHERE c.id_cliente = @id_cliente;

            SELECT @num_doc = f.numero_documento,
                   @descripcion = LEFT(CONCAT('Venta según factura ', f.numero_documento,
                                              ' - ', c.nombre_comercial), 200)
            FROM Factura f
            INNER JOIN Cliente c ON c.id_cliente = f.id_cliente
            WHERE f.id_factura = @id_factura;

            EXEC sp_RegistrarPartida @tipo_documento = 'Factura', @id_documento = @id_factura,
                 @documento_numero = @num_doc, @descripcion = @descripcion,
                 @lineas = @lineas, @id_partida = @id_partida OUTPUT;

            UPDATE Pedido SET estado = 'Facturado' WHERE id_pedido = @id_pedido;

        COMMIT TRANSACTION;

        SELECT f.numero_documento AS Factura, c.nombre_comercial AS Cliente, f.fecha_factura,
               f.fecha_vencimiento, f.base_imponible, f.iva, f.total, f.estado, f.estado_pago,
               pc.numero AS Partida
        FROM Factura f
        INNER JOIN Cliente          c  ON c.id_cliente = f.id_cliente
        INNER JOIN Partida_Contable pc ON pc.id_partida = @id_partida
        WHERE f.id_factura = @id_factura;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- -----------------------------------------------------
-- 9. sp_RegistrarCobro  (ETAPA 4)
-- -----------------------------------------------------
CREATE PROCEDURE sp_RegistrarCobro
    @id_factura             INT,
    @monto                  DECIMAL(14,2),
    @metodo_pago            VARCHAR(15) = 'Efectivo',
    @numero_cuenta_bancaria VARCHAR(30) = NULL,
    @referencia             VARCHAR(50) = NULL,
    @id_cobro               INT         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @estado VARCHAR(10), @saldo DECIMAL(14,2), @tc DECIMAL(12,6), @id_cliente INT,
            @id_cta_cliente INT, @id_cta_destino INT, @id_cuenta_bancaria INT,
            @num_fac VARCHAR(30), @num_cobro VARCHAR(15), @descripcion VARCHAR(200),
            @monto_gtq DECIMAL(14,2), @id_partida INT, @msg NVARCHAR(400);
    DECLARE @lineas tt_LineaPartida;

    BEGIN TRY
        SELECT @estado = f.estado, @saldo = f.saldo_pendiente, @tc = f.tipo_cambio,
               @id_cliente = f.id_cliente, @id_cta_cliente = c.id_cuenta_contable,
               @num_fac = f.numero_documento
        FROM Factura f
        INNER JOIN Cliente c ON c.id_cliente = f.id_cliente
        WHERE f.id_factura = @id_factura;

        IF @estado IS NULL       THROW 50150, N'La factura no existe.', 1;
        IF @estado = 'Anulada'   THROW 50151, N'No se puede cobrar una factura anulada.', 1;
        IF @saldo = 0            THROW 50152, N'La factura ya está pagada.', 1;
        IF @monto IS NULL OR @monto <= 0 THROW 50153, N'El monto debe ser mayor a cero.', 1;
        IF @monto > @saldo
        BEGIN
            SET @msg = CONCAT(N'El monto (', @monto, N') es mayor al saldo pendiente (', @saldo, N').');
            ;THROW 50154, @msg, 1;
        END

        -- ¿A dónde entra el dinero? Efectivo -> Caja General; otro -> Banco
        IF @metodo_pago = 'Efectivo'
            SELECT @id_cta_destino = id_cuenta FROM Cuenta_Contable WHERE codigo = '1.1.01.01';
        ELSE
        BEGIN
            SELECT @id_cuenta_bancaria = id_cuenta_bancaria, @id_cta_destino = id_cuenta_contable
            FROM Cuenta_Bancaria WHERE numero_cuenta = @numero_cuenta_bancaria AND activo = 1;
            IF @id_cuenta_bancaria IS NULL
                THROW 50155, N'Para pagos que no son en efectivo debe indicar una cuenta bancaria válida.', 1;
        END

        SET @monto_gtq = CAST(@monto * @tc AS DECIMAL(14,2));

        BEGIN TRANSACTION;

            INSERT INTO Cobro (id_factura, monto, metodo_pago, id_cuenta_bancaria, referencia)
            VALUES (@id_factura, @monto, @metodo_pago, @id_cuenta_bancaria, @referencia);

            SET @id_cobro = SCOPE_IDENTITY();

            UPDATE Factura SET saldo_pendiente = saldo_pendiente - @monto
            WHERE id_factura = @id_factura;

            -- PARTIDA DEL COBRO
            --   Debe:  Caja o Bancos
            --   Haber: Clientes
            INSERT INTO @lineas (id_cuenta, tipo_monto, monto, id_cliente, descripcion) VALUES
                (@id_cta_destino, 'D', @monto_gtq, NULL,        CONCAT('Ingreso por ', @metodo_pago)),
                (@id_cta_cliente, 'H', @monto_gtq, @id_cliente, 'Abono a cuenta del cliente');

            SELECT @num_cobro = numero FROM Cobro WHERE id_cobro = @id_cobro;
            SET @descripcion = CONCAT('Cobro ', @num_cobro, ' de factura ', @num_fac);

            EXEC sp_RegistrarPartida @tipo_documento = 'Cobro', @id_documento = @id_cobro,
                 @documento_numero = @num_cobro, @descripcion = @descripcion,
                 @lineas = @lineas, @id_partida = @id_partida OUTPUT;

        COMMIT TRANSACTION;

        SELECT co.numero AS Cobro, f.numero_documento AS Factura, co.metodo_pago, co.monto,
               f.saldo_pendiente AS Saldo_Pendiente, f.estado_pago, pc.numero AS Partida
        FROM Cobro co
        INNER JOIN Factura          f  ON f.id_factura  = co.id_factura
        INNER JOIN Partida_Contable pc ON pc.id_partida = @id_partida
        WHERE co.id_cobro = @id_cobro;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- -----------------------------------------------------
-- 10. sp_Despachar  (ETAPA 5)
-- -----------------------------------------------------
CREATE PROCEDURE sp_Despachar
    @id_factura   INT,
    @recibido_por VARCHAR(100),
    @id_despacho  INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @estado VARCHAR(10), @estado_pago VARCHAR(10), @saldo DECIMAL(14,2),
            @id_sitio INT, @num_fac VARCHAR(30), @num_des VARCHAR(15),
            @descripcion VARCHAR(200), @id_partida INT, @msg NVARCHAR(400);
    DECLARE @lineas tt_LineaPartida;
    DECLARE @salidas TABLE (id_inventario INT, id_producto INT, id_localizacion INT,
                            cantidad DECIMAL(12,2), costo DECIMAL(12,4));

    BEGIN TRY
        SELECT @estado = estado, @estado_pago = estado_pago, @saldo = saldo_pendiente,
               @id_sitio = id_sitio, @num_fac = numero_documento
        FROM Factura WHERE id_factura = @id_factura;

        IF @estado IS NULL     THROW 50160, N'La factura no existe.', 1;
        IF @estado = 'Anulada' THROW 50161, N'No se puede despachar una factura anulada.', 1;

        -- REGLA: solo se despacha una factura PAGADA
        IF @estado_pago <> 'Pagada'
        BEGIN
            SET @msg = CONCAT(N'Regla de negocio: no se puede despachar la factura ', @num_fac,
                              N' porque no está pagada. Saldo pendiente: ', @saldo, N'.');
            ;THROW 50162, @msg, 1;
        END

        IF EXISTS (SELECT 1 FROM Despacho WHERE id_factura = @id_factura AND estado = 'Completado')
            THROW 50163, N'Esta factura ya fue despachada.', 1;

        BEGIN TRANSACTION;

            INSERT INTO Despacho (id_factura, id_sitio, recibido_por)
            VALUES (@id_factura, @id_sitio, @recibido_por);

            SET @id_despacho = SCOPE_IDENTITY();
            SELECT @num_des = numero FROM Despacho WHERE id_despacho = @id_despacho;

            -- ¿De qué localizaciones sale? De donde se reservó en el sitio
            ;WITH inv AS (
                SELECT i.id_inventario, i.id_producto, i.id_localizacion,
                       i.cantidad_reservada AS res, fd.cantidad AS requerida, fd.costo_unitario,
                       SUM(i.cantidad_reservada) OVER (PARTITION BY i.id_producto
                           ORDER BY i.cantidad_reservada DESC, i.id_inventario
                           ROWS UNBOUNDED PRECEDING) AS acumulado
                FROM Inventario i WITH (UPDLOCK)
                INNER JOIN Localizacion    l  ON l.id_localizacion = i.id_localizacion
                INNER JOIN Bodega          b  ON b.id_bodega       = l.id_bodega
                INNER JOIN Factura_Detalle fd ON fd.id_producto    = i.id_producto
                WHERE fd.id_factura = @id_factura AND b.id_sitio = @id_sitio
                  AND i.cantidad_reservada > 0
            )
            INSERT INTO @salidas (id_inventario, id_producto, id_localizacion, cantidad, costo)
            SELECT id_inventario, id_producto, id_localizacion,
                   CASE WHEN acumulado <= requerida THEN res
                        WHEN acumulado - res < requerida THEN requerida - (acumulado - res)
                        ELSE 0 END,
                   costo_unitario
            FROM inv;

            DELETE FROM @salidas WHERE cantidad <= 0;

            IF EXISTS (SELECT 1
                       FROM Factura_Detalle fd
                       LEFT JOIN (SELECT id_producto, SUM(cantidad) AS cant
                                  FROM @salidas GROUP BY id_producto) s
                              ON s.id_producto = fd.id_producto
                       WHERE fd.id_factura = @id_factura AND ISNULL(s.cant, 0) < fd.cantidad)
                THROW 50164, N'No hay suficiente producto reservado en el sitio para despachar.', 1;

            INSERT INTO Despacho_Detalle (id_despacho, id_producto, id_localizacion, cantidad)
            SELECT @id_despacho, id_producto, id_localizacion, cantidad FROM @salidas;

            -- Descontar FÍSICAMENTE de la localización
            UPDATE i
            SET i.cantidad                = i.cantidad - s.cantidad,
                i.cantidad_reservada      = i.cantidad_reservada - s.cantidad,
                i.fecha_ultimo_movimiento = SYSDATETIME()
            FROM Inventario i
            INNER JOIN @salidas s ON s.id_inventario = i.id_inventario;

            -- KARDEX: registrar la salida
            INSERT INTO Movimiento_Inventario (id_producto, id_localizacion, tipo_movimiento,
                                               cantidad, costo_unitario, saldo_resultante,
                                               documento_tipo, documento_numero, justificacion)
            SELECT s.id_producto, s.id_localizacion, 'Salida', -s.cantidad, s.costo,
                   i.cantidad, 'DESPACHO', @num_des, CONCAT('Despacho de factura ', @num_fac)
            FROM @salidas s
            INNER JOIN Inventario i ON i.id_inventario = s.id_inventario;

            -- PARTIDA DEL DESPACHO
            --   Debe:  Costo de Ventas
            --   Haber: Inventario
            INSERT INTO @lineas (id_cuenta, tipo_monto, monto, id_cliente, descripcion)
            SELECT vc.id_cuenta_costo, 'D', CAST(SUM(s.cantidad * s.costo) AS DECIMAL(14,2)),
                   NULL, 'Costo de la mercadería despachada'
            FROM @salidas s
            INNER JOIN vw_Producto_Cuenta vc ON vc.id_producto = s.id_producto
            GROUP BY vc.id_cuenta_costo;

            INSERT INTO @lineas (id_cuenta, tipo_monto, monto, id_cliente, descripcion)
            SELECT vc.id_cuenta_inventario, 'H', CAST(SUM(s.cantidad * s.costo) AS DECIMAL(14,2)),
                   NULL, 'Salida de inventario'
            FROM @salidas s
            INNER JOIN vw_Producto_Cuenta vc ON vc.id_producto = s.id_producto
            GROUP BY vc.id_cuenta_inventario;

            SET @descripcion = CONCAT('Despacho ', @num_des, ' de factura ', @num_fac);

            EXEC sp_RegistrarPartida @tipo_documento = 'Despacho', @id_documento = @id_despacho,
                 @documento_numero = @num_des, @descripcion = @descripcion,
                 @lineas = @lineas, @id_partida = @id_partida OUTPUT;

        COMMIT TRANSACTION;

        SELECT d.numero AS Despacho, @num_fac AS Factura, p.codigo AS Producto,
               s.nombre AS Sitio, b.codigo AS Bodega, l.codigo AS Localizacion,
               dd.cantidad, d.recibido_por
        FROM Despacho d
        INNER JOIN Despacho_Detalle dd ON dd.id_despacho     = d.id_despacho
        INNER JOIN Producto         p  ON p.id_producto      = dd.id_producto
        INNER JOIN Localizacion     l  ON l.id_localizacion  = dd.id_localizacion
        INNER JOIN Bodega           b  ON b.id_bodega        = l.id_bodega
        INNER JOIN Sitio            s  ON s.id_sitio         = b.id_sitio
        WHERE d.id_despacho = @id_despacho;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- -----------------------------------------------------
-- 11. sp_AnularFactura
-- -----------------------------------------------------
CREATE PROCEDURE sp_AnularFactura
    @id_factura INT,
    @motivo     VARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @estado VARCHAR(10), @id_sitio INT, @id_pedido INT, @num_fac VARCHAR(30),
            @descripcion VARCHAR(200), @id_partida INT;
    DECLARE @lineas tt_LineaPartida;

    BEGIN TRY
        SELECT @estado = estado, @id_sitio = id_sitio, @id_pedido = id_pedido,
               @num_fac = numero_documento
        FROM Factura WHERE id_factura = @id_factura;

        IF @estado IS NULL       THROW 50170, N'La factura no existe.', 1;
        IF @estado = 'Anulada'   THROW 50171, N'La factura ya está anulada.', 1;
        IF ISNULL(LTRIM(RTRIM(@motivo)), '') = ''
            THROW 50172, N'Debe indicar el motivo de la anulación.', 1;
        IF EXISTS (SELECT 1 FROM Cobro WHERE id_factura = @id_factura AND estado = 'Aplicado')
            THROW 50173, N'No se puede anular: la factura tiene cobros aplicados.', 1;
        IF EXISTS (SELECT 1 FROM Despacho WHERE id_factura = @id_factura AND estado = 'Completado')
            THROW 50174, N'No se puede anular: la factura ya fue despachada.', 1;

        BEGIN TRANSACTION;

            -- Liberar el inventario reservado
            ;WITH inv AS (
                SELECT i.id_inventario, i.cantidad_reservada AS res, fd.cantidad AS requerida,
                       SUM(i.cantidad_reservada) OVER (PARTITION BY i.id_producto
                           ORDER BY i.cantidad_reservada DESC, i.id_inventario
                           ROWS UNBOUNDED PRECEDING) AS acumulado
                FROM Inventario i
                INNER JOIN Localizacion    l  ON l.id_localizacion = i.id_localizacion
                INNER JOIN Bodega          b  ON b.id_bodega       = l.id_bodega
                INNER JOIN Factura_Detalle fd ON fd.id_producto    = i.id_producto
                WHERE fd.id_factura = @id_factura AND b.id_sitio = @id_sitio
                  AND i.cantidad_reservada > 0
            )
            UPDATE i
            SET i.cantidad_reservada = i.cantidad_reservada - r.liberar
            FROM Inventario i
            INNER JOIN (SELECT id_inventario,
                               CASE WHEN acumulado <= requerida THEN res
                                    WHEN acumulado - res < requerida THEN requerida - (acumulado - res)
                                    ELSE 0 END AS liberar
                        FROM inv) r ON r.id_inventario = i.id_inventario
            WHERE r.liberar > 0;

            UPDATE Factura SET estado = 'Anulada', motivo_anulacion = @motivo
            WHERE id_factura = @id_factura;

            UPDATE Pedido SET estado = 'Anulado' WHERE id_pedido = @id_pedido;

            -- PARTIDA DE REVERSIÓN: la misma partida de la factura, al revés
            INSERT INTO @lineas (id_cuenta, tipo_monto, monto, id_cliente, descripcion)
            SELECT pd.id_cuenta, CASE pd.tipo_monto WHEN 'D' THEN 'H' ELSE 'D' END,
                   pd.monto, pd.id_cliente, 'Reversión por anulación'
            FROM Partida_Detalle pd
            INNER JOIN Partida_Contable pc ON pc.id_partida = pd.id_partida
            WHERE pc.tipo_documento = 'Factura' AND pc.id_documento = @id_factura;

            SET @descripcion = LEFT(CONCAT('Anulación de factura ', @num_fac, ': ', @motivo), 200);

            EXEC sp_RegistrarPartida @tipo_documento = 'Anulación', @id_documento = @id_factura,
                 @documento_numero = @num_fac, @descripcion = @descripcion,
                 @lineas = @lineas, @id_partida = @id_partida OUTPUT;

            INSERT INTO Bitacora (tabla, id_registro, accion, detalle)
            VALUES ('Factura', @id_factura, 'Anulación', @motivo);

        COMMIT TRANSACTION;

        SELECT numero_documento AS Factura, estado, motivo_anulacion
        FROM Factura WHERE id_factura = @id_factura;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- =====================================================
-- VERIFICACION
-- =====================================================
-- a) Objetos programados en la base de datos
SELECT name AS Objeto,
       CASE type WHEN 'P'  THEN 'Procedimiento almacenado'
                 WHEN 'FN' THEN 'Función'
                 WHEN 'TR' THEN 'Trigger'
                 WHEN 'V'  THEN 'Vista' END AS Tipo
FROM sys.objects
WHERE type IN ('P', 'FN', 'TR', 'V')
ORDER BY type, name;

-- b) Probar la función: stock disponible de cable THHN 12 en la Casa Matriz
SELECT 'CO-BC-0001' AS Producto, 'S01' AS Sitio,
       dbo.fn_StockDisponible('CO-BC-0001', 'S01') AS Disponible;
