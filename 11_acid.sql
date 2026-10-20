-- =====================================================
-- Script 11: Demostración de Transacciones ACID
-- COMMIT, ROLLBACK, SAVEPOINT
-- =====================================================
USE SolucionesElectricas;
GO

-- =====================================================
-- A) ATOMICIDAD: "todo o nada"
--    Igual al ejemplo del enunciado: se descuenta inventario
--    y se inserta el detalle de factura. Si el detalle falla,
--    el descuento de inventario TAMBIÉN se deshace.
-- =====================================================
SET NOCOUNT ON;
DECLARE @inv INT, @antes DECIMAL(12,2), @durante DECIMAL(12,2),
        @despues DECIMAL(12,2), @error NVARCHAR(400);

SELECT TOP 1 @inv = i.id_inventario, @antes = i.cantidad
FROM Inventario i
INNER JOIN Producto     p ON p.id_producto     = i.id_producto
INNER JOIN Localizacion l ON l.id_localizacion = i.id_localizacion
INNER JOIN Bodega       b ON b.id_bodega       = l.id_bodega
INNER JOIN Sitio        s ON s.id_sitio        = b.id_sitio
WHERE p.codigo = 'CO-BC-0003' AND s.codigo = 'S01';

BEGIN TRY
    BEGIN TRANSACTION;

        -- Paso 1: descontar 10 metros del inventario
        UPDATE Inventario SET cantidad = cantidad - 10 WHERE id_inventario = @inv;
        SELECT @durante = cantidad FROM Inventario WHERE id_inventario = @inv;

        -- Paso 2: insertar el detalle en una factura que NO existe (falla a propósito)
        INSERT INTO Factura_Detalle (id_factura, id_producto, cantidad, precio_unitario,
                                     codigo_iva, porcentaje_iva, costo_unitario)
        VALUES (999999, 3, 10, 12.25, 'IVA12', 12, 7.40);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;     -- se deshace TODO
    SET @error = ERROR_MESSAGE();
END CATCH

SELECT @despues = cantidad FROM Inventario WHERE id_inventario = @inv;

SELECT 'A - ATOMICIDAD'        AS Propiedad,
       'CO-BC-0003 en S01'     AS Inventario,
       @antes                  AS Antes,
       @durante                AS Durante_la_transaccion,
       @despues                AS Despues_del_ROLLBACK,
       CASE WHEN @antes = @despues THEN 'OK: el descuento se deshizo'
            ELSE 'ERROR' END   AS Resultado,
       LEFT(@error, 150)       AS Error_que_provoco_el_ROLLBACK;
GO

-- =====================================================
-- B) CONSISTENCIA: la base nunca queda en un estado inválido
-- =====================================================
SET NOCOUNT ON;
DECLARE @pruebas TABLE (Prueba VARCHAR(80), Resultado NVARCHAR(400));
DECLARE @inv INT, @caja INT, @ventas INT, @idp INT, @l tt_LineaPartida;

SELECT TOP 1 @inv = id_inventario FROM Inventario ORDER BY id_inventario;
SELECT @caja   = id_cuenta FROM Cuenta_Contable WHERE codigo = '1.1.01.01';
SELECT @ventas = id_cuenta FROM Cuenta_Contable WHERE codigo = '4.1.01.01';

-- B1: inventario negativo
BEGIN TRY
    UPDATE Inventario SET cantidad = -5 WHERE id_inventario = @inv;
    INSERT INTO @pruebas VALUES ('B1: inventario negativo', 'ERROR: se aceptó');
END TRY
BEGIN CATCH
    INSERT INTO @pruebas VALUES ('B1: inventario negativo', 'RECHAZADO: ' + ERROR_MESSAGE());
END CATCH

-- B2: partida contable descuadrada (Debe 100 / Haber 90)
INSERT INTO @l (id_cuenta, tipo_monto, monto, id_cliente, descripcion) VALUES
    (@caja,   'D', 100, NULL, 'Prueba'),
    (@ventas, 'H',  90, NULL, 'Prueba');
BEGIN TRY
    EXEC sp_RegistrarPartida @tipo_documento = 'Ajuste', @id_documento = 0,
         @documento_numero = 'PRUEBA', @descripcion = 'Partida descuadrada de prueba',
         @lineas = @l, @id_partida = @idp OUTPUT;
    INSERT INTO @pruebas VALUES ('B2: partida descuadrada', 'ERROR: se aceptó');
END TRY
BEGIN CATCH
    INSERT INTO @pruebas VALUES ('B2: partida descuadrada', 'RECHAZADO: ' + ERROR_MESSAGE());
END CATCH

-- B3: vender por debajo del costo (cable XLP: costo Q38, precio Q1)
BEGIN TRY
    UPDATE Producto SET precio_unitario = 1 WHERE codigo = 'CO-MC-0001';
    INSERT INTO @pruebas VALUES ('B3: precio menor al costo', 'ERROR: se aceptó');
END TRY
BEGIN CATCH
    INSERT INTO @pruebas VALUES ('B3: precio menor al costo', 'RECHAZADO: ' + ERROR_MESSAGE());
END CATCH

-- B4: la contabilidad completa sigue cuadrada
INSERT INTO @pruebas
SELECT 'B4: Debe = Haber en toda la contabilidad',
       CONCAT('Debe Q', SUM(debe), ' = Haber Q', SUM(haber),
              CASE WHEN SUM(debe) = SUM(haber) THEN '  -> CUADRADA' ELSE '  -> ERROR' END)
FROM Partida_Detalle;

SELECT 'B - CONSISTENCIA' AS Propiedad, Prueba, Resultado FROM @pruebas;
GO

-- =====================================================
-- E) SAVEPOINT: deshacer SOLO una parte de la transacción
--    Ajuste de inventario por conteo físico con 3 líneas.
--    La línea 2 tiene un error -> se deshace solo esa línea.
-- =====================================================
SET NOCOUNT ON;
IF EXISTS (SELECT 1 FROM Movimiento_Inventario WHERE documento_numero = 'AJ-2026-001')
BEGIN
    SELECT 'E - SAVEPOINT' AS Propiedad, 'Ya se ejecutó antes (ajuste AJ-2026-001).' AS Resultado;
    RETURN;
END

DECLARE @i1 INT, @i2 INT, @i3 INT, @a1 DECIMAL(12,2), @a2 DECIMAL(12,2), @a3 DECIMAL(12,2);
DECLARE @log TABLE (paso INT IDENTITY(1,1), accion NVARCHAR(400));

SELECT TOP 1 @i1 = i.id_inventario, @a1 = i.cantidad
FROM Inventario i
INNER JOIN Producto p ON p.id_producto = i.id_producto
INNER JOIN Localizacion l ON l.id_localizacion = i.id_localizacion
INNER JOIN Bodega b ON b.id_bodega = l.id_bodega
INNER JOIN Sitio s ON s.id_sitio = b.id_sitio
WHERE p.codigo = 'MA-PV-0001' AND s.codigo = 'S01';

SELECT TOP 1 @i2 = i.id_inventario, @a2 = i.cantidad
FROM Inventario i
INNER JOIN Producto p ON p.id_producto = i.id_producto
INNER JOIN Localizacion l ON l.id_localizacion = i.id_localizacion
INNER JOIN Bodega b ON b.id_bodega = l.id_bodega
INNER JOIN Sitio s ON s.id_sitio = b.id_sitio
WHERE p.codigo = 'AE-CD-0001' AND s.codigo = 'S01';

SELECT TOP 1 @i3 = i.id_inventario, @a3 = i.cantidad
FROM Inventario i
INNER JOIN Producto p ON p.id_producto = i.id_producto
INNER JOIN Localizacion l ON l.id_localizacion = i.id_localizacion
INNER JOIN Bodega b ON b.id_bodega = l.id_bodega
INNER JOIN Sitio s ON s.id_sitio = b.id_sitio
WHERE p.codigo = 'MA-CE-0001' AND s.codigo = 'S01';

BEGIN TRANSACTION;

    -- Línea 1: sobrante de 2 tubos PVC
    UPDATE Inventario SET cantidad = cantidad + 2, fecha_ultimo_movimiento = SYSDATETIME()
    WHERE id_inventario = @i1;
    INSERT INTO Movimiento_Inventario (id_producto, id_localizacion, tipo_movimiento, cantidad,
                                       costo_unitario, saldo_resultante, documento_tipo,
                                       documento_numero, justificacion)
    SELECT i.id_producto, i.id_localizacion, 'Ajuste', 2, p.costo_unitario, i.cantidad,
           'AJUSTE', 'AJ-2026-001', 'Conteo físico: sobrante de 2 unidades'
    FROM Inventario i INNER JOIN Producto p ON p.id_producto = i.id_producto
    WHERE i.id_inventario = @i1;
    INSERT INTO @log VALUES ('Línea 1 aplicada: MA-PV-0001 +2');

    SAVE TRANSACTION punto_linea1;          -- <<< SAVEPOINT
    INSERT INTO @log VALUES ('SAVEPOINT "punto_linea1" creado');

    -- Línea 2: ERROR de digitación (faltante imposible de 999,999)
    BEGIN TRY
        UPDATE Inventario SET cantidad = cantidad - 999999 WHERE id_inventario = @i2;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION punto_linea1;   -- <<< regresa al SAVEPOINT
            INSERT INTO @log VALUES ('Línea 2 FALLÓ -> ROLLBACK al SAVEPOINT (solo se deshizo la línea 2): '
                                     + LEFT(ERROR_MESSAGE(), 120));
        END
    END CATCH

    -- Línea 3: faltante de 1 aislador
    UPDATE Inventario SET cantidad = cantidad - 1, fecha_ultimo_movimiento = SYSDATETIME()
    WHERE id_inventario = @i3;
    INSERT INTO Movimiento_Inventario (id_producto, id_localizacion, tipo_movimiento, cantidad,
                                       costo_unitario, saldo_resultante, documento_tipo,
                                       documento_numero, justificacion)
    SELECT i.id_producto, i.id_localizacion, 'Ajuste', -1, p.costo_unitario, i.cantidad,
           'AJUSTE', 'AJ-2026-001', 'Conteo físico: faltante de 1 unidad'
    FROM Inventario i INNER JOIN Producto p ON p.id_producto = i.id_producto
    WHERE i.id_inventario = @i3;
    INSERT INTO @log VALUES ('Línea 3 aplicada: MA-CE-0001 -1');

COMMIT TRANSACTION;                         -- <<< se confirman líneas 1 y 3
INSERT INTO @log VALUES ('COMMIT: se confirmaron las líneas 1 y 3');

SELECT 'E - SAVEPOINT' AS Propiedad, paso, accion FROM @log ORDER BY paso;

SELECT p.codigo, x.Antes, i.cantidad AS Despues, x.Esperado,
       CASE WHEN i.cantidad = x.Antes + x.Esperado THEN 'OK' ELSE 'ERROR' END AS Resultado
FROM (VALUES (@i1, @a1, 2), (@i2, @a2, 0), (@i3, @a3, -1)) AS x(id_inventario, Antes, Esperado)
INNER JOIN Inventario i ON i.id_inventario = x.id_inventario
INNER JOIN Producto   p ON p.id_producto   = i.id_producto;
GO

-- =====================================================
-- D) DURABILIDAD: lo confirmado con COMMIT no se pierde
-- =====================================================
SET NOCOUNT ON;
BEGIN TRANSACTION;
    INSERT INTO Bitacora (tabla, id_registro, accion, detalle)
    VALUES ('Prueba ACID', 0, 'Durabilidad',
            'Registro confirmado con COMMIT: debe seguir aquí aunque se cierre SSMS o se reinicie el servidor');
COMMIT TRANSACTION;

SELECT TOP 1 'D - DURABILIDAD' AS Propiedad, id_bitacora, fecha, accion, detalle, usuario
FROM Bitacora WHERE accion = 'Durabilidad' ORDER BY id_bitacora DESC;

-- El registro de transacciones (log) garantiza la durabilidad
SELECT name AS Base_de_datos, recovery_model_desc AS Modelo_de_recuperacion,
       log_reuse_wait_desc AS Estado_del_log
FROM sys.databases WHERE name = 'SolucionesElectricas';

-- Respaldo completo de la base (copia de seguridad)
BACKUP DATABASE SolucionesElectricas
TO DISK = N'SolucionesElectricas_ACID.bak'
WITH INIT, NAME = N'Respaldo - prueba de durabilidad';

SELECT TOP 1 bs.backup_finish_date AS Fecha_Respaldo,
       bmf.physical_device_name   AS Archivo_de_Respaldo,
       CAST(bs.backup_size / 1048576.0 AS DECIMAL(10,2)) AS Tamano_MB
FROM msdb.dbo.backupset bs
INNER JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = 'SolucionesElectricas'
ORDER BY bs.backup_finish_date DESC;
GO
