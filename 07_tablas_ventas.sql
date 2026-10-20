-- =====================================================
-- Script 07: Tablas del Proceso de Ventas (Grupo E)
-- Cotización -> Pedido -> Factura -> Cobro -> Despacho
-- + Partidas Contables
-- =====================================================
USE SolucionesElectricas;
GO

-- -----------------------------------------------------
-- 0. LIMPIEZA (orden inverso: primero hijos)
-- -----------------------------------------------------
DROP TABLE IF EXISTS Partida_Detalle;
DROP TABLE IF EXISTS Partida_Contable;
DROP TABLE IF EXISTS Despacho_Detalle;
DROP TABLE IF EXISTS Despacho;
DROP TABLE IF EXISTS Cobro;
DROP TABLE IF EXISTS Factura_Detalle;
DROP TABLE IF EXISTS Factura;
DROP TABLE IF EXISTS Pedido_Detalle;
DROP TABLE IF EXISTS Pedido;
DROP TABLE IF EXISTS Cotizacion_Detalle;
DROP TABLE IF EXISTS Cotizacion;
DROP TABLE IF EXISTS Cuenta_Bancaria;
DROP TABLE IF EXISTS Bitacora;
GO

-- -----------------------------------------------------
-- 1. ALTER TABLE Inventario: cantidad reservada y disponible
--    (la FACTURA reserva; el DESPACHO saca físicamente)
-- -----------------------------------------------------
IF COL_LENGTH('Inventario', 'cantidad_reservada') IS NULL
    ALTER TABLE Inventario
        ADD cantidad_reservada DECIMAL(12,2) NOT NULL
            CONSTRAINT DF_Inventario_Reservada DEFAULT 0;
GO
IF COL_LENGTH('Inventario', 'cantidad_disponible') IS NULL
    ALTER TABLE Inventario
        ADD cantidad_disponible AS (cantidad - cantidad_reservada) PERSISTED;
GO
IF OBJECT_ID('CK_Inventario_Reservada') IS NULL
    ALTER TABLE Inventario
        ADD CONSTRAINT CK_Inventario_Reservada
            CHECK (cantidad_reservada >= 0 AND cantidad_reservada <= cantidad);
GO

-- -----------------------------------------------------
-- 2. CUENTA_BANCARIA
-- -----------------------------------------------------
CREATE TABLE Cuenta_Bancaria (
    id_cuenta_bancaria INT IDENTITY(1,1) PRIMARY KEY,
    banco              VARCHAR(60) NOT NULL,
    numero_cuenta      VARCHAR(30) NOT NULL UNIQUE,
    tipo_cuenta        VARCHAR(20) NOT NULL DEFAULT 'Monetaria',
    codigo_moneda      CHAR(3)     NOT NULL DEFAULT 'GTQ',
    id_cuenta_contable INT         NOT NULL,
    activo             BIT         NOT NULL DEFAULT 1,
    CONSTRAINT FK_CtaBancaria_Moneda FOREIGN KEY (codigo_moneda)      REFERENCES Moneda(codigo),
    CONSTRAINT FK_CtaBancaria_Cuenta FOREIGN KEY (id_cuenta_contable) REFERENCES Cuenta_Contable(id_cuenta),
    CONSTRAINT CK_CtaBancaria_Tipo   CHECK (tipo_cuenta IN ('Monetaria', 'Ahorro'))
);

-- -----------------------------------------------------
-- 3. BITACORA (registro de acciones importantes)
-- -----------------------------------------------------
CREATE TABLE Bitacora (
    id_bitacora INT IDENTITY(1,1) PRIMARY KEY,
    fecha       DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    tabla       VARCHAR(50)  NOT NULL,
    id_registro INT          NOT NULL,
    accion      VARCHAR(30)  NOT NULL,
    detalle     VARCHAR(400) NULL,
    usuario     VARCHAR(50)  NOT NULL DEFAULT SUSER_SNAME()
);

-- -----------------------------------------------------
-- 4. COTIZACION (Etapa 1)
-- -----------------------------------------------------
CREATE TABLE Cotizacion (
    id_cotizacion          INT IDENTITY(1,1) PRIMARY KEY,
    numero AS ('COT-' + RIGHT('000000' + CAST(id_cotizacion AS VARCHAR(6)), 6)) PERSISTED,
    fecha_solicitud        DATE          NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    id_cliente             INT           NOT NULL,
    id_vendedor            INT           NOT NULL,
    id_sitio               INT           NOT NULL,
    codigo_moneda          CHAR(3)       NOT NULL DEFAULT 'GTQ',
    tipo_cambio            DECIMAL(12,6) NOT NULL DEFAULT 1,
    fecha_tentativa_compra DATE          NULL,
    estado                 VARCHAR(15)   NOT NULL DEFAULT 'En proceso',
    total                  DECIMAL(14,2) NOT NULL DEFAULT 0,     -- IVA incluido
    observaciones          VARCHAR(300)  NULL,
    usuario_creador        VARCHAR(50)   NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion         DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_Cotizacion_Numero UNIQUE (numero),
    -- REGLA: un vendedor solo puede cotizar a SUS clientes (FK compuesta)
    CONSTRAINT FK_Cotizacion_ClienteVendedor
        FOREIGN KEY (id_cliente, id_vendedor) REFERENCES Cliente(id_cliente, id_vendedor),
    CONSTRAINT FK_Cotizacion_Sitio  FOREIGN KEY (id_sitio)      REFERENCES Sitio(id_sitio),
    CONSTRAINT FK_Cotizacion_Moneda FOREIGN KEY (codigo_moneda) REFERENCES Moneda(codigo),
    CONSTRAINT CK_Cotizacion_Estado CHECK (estado IN ('En proceso', 'Firme', 'Confirmada', 'Anulada')),
    CONSTRAINT CK_Cotizacion_Fechas CHECK (fecha_tentativa_compra IS NULL
                                           OR fecha_tentativa_compra >= fecha_solicitud),
    CONSTRAINT CK_Cotizacion_Total  CHECK (total >= 0),
    CONSTRAINT CK_Cotizacion_TC     CHECK (tipo_cambio > 0)
);

CREATE TABLE Cotizacion_Detalle (
    id_detalle      INT IDENTITY(1,1) PRIMARY KEY,
    id_cotizacion   INT           NOT NULL,
    id_producto     INT           NOT NULL,
    cantidad        DECIMAL(12,2) NOT NULL,
    precio_unitario DECIMAL(12,2) NOT NULL,                 -- IVA incluido por ley
    total_linea AS (CAST(cantidad * precio_unitario AS DECIMAL(14,2))) PERSISTED,
    CONSTRAINT FK_CotDet_Cotizacion FOREIGN KEY (id_cotizacion)
        REFERENCES Cotizacion(id_cotizacion) ON DELETE CASCADE,
    CONSTRAINT FK_CotDet_Producto   FOREIGN KEY (id_producto) REFERENCES Producto(id_producto),
    CONSTRAINT UQ_CotDet UNIQUE (id_cotizacion, id_producto),
    CONSTRAINT CK_CotDet_Cantidad CHECK (cantidad > 0),
    CONSTRAINT CK_CotDet_Precio   CHECK (precio_unitario > 0)
);

-- -----------------------------------------------------
-- 5. PEDIDO (Etapa 2: se genera de una cotización confirmada)
-- -----------------------------------------------------
CREATE TABLE Pedido (
    id_pedido          INT IDENTITY(1,1) PRIMARY KEY,
    numero AS ('PED-' + RIGHT('000000' + CAST(id_pedido AS VARCHAR(6)), 6)) PERSISTED,
    id_cotizacion      INT           NOT NULL UNIQUE,      -- 1:1 con Cotización
    fecha_pedido       DATE          NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    id_cliente         INT           NOT NULL,
    id_vendedor        INT           NOT NULL,
    id_sitio           INT           NOT NULL,
    codigo_moneda      CHAR(3)       NOT NULL DEFAULT 'GTQ',
    tipo_cambio        DECIMAL(12,6) NOT NULL DEFAULT 1,
    estado             VARCHAR(25)   NOT NULL DEFAULT 'Pendiente',
    base_imponible     DECIMAL(14,2) NOT NULL DEFAULT 0,
    iva                DECIMAL(14,2) NOT NULL DEFAULT 0,
    total              DECIMAL(14,2) NOT NULL DEFAULT 0,
    autorizado_por     VARCHAR(50)   NULL,
    fecha_autorizacion DATETIME2(0)  NULL,
    usuario_creador    VARCHAR(50)   NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_Pedido_Numero UNIQUE (numero),
    CONSTRAINT FK_Pedido_Cotizacion FOREIGN KEY (id_cotizacion) REFERENCES Cotizacion(id_cotizacion),
    CONSTRAINT FK_Pedido_ClienteVendedor
        FOREIGN KEY (id_cliente, id_vendedor) REFERENCES Cliente(id_cliente, id_vendedor),
    CONSTRAINT FK_Pedido_Sitio  FOREIGN KEY (id_sitio)      REFERENCES Sitio(id_sitio),
    CONSTRAINT FK_Pedido_Moneda FOREIGN KEY (codigo_moneda) REFERENCES Moneda(codigo),
    CONSTRAINT CK_Pedido_Estado CHECK (estado IN
        ('Pendiente', 'Pendiente Autorización', 'Autorizado', 'Facturado', 'Anulado')),
    CONSTRAINT CK_Pedido_Totales CHECK (total = base_imponible + iva)
);

CREATE TABLE Pedido_Detalle (
    id_detalle      INT IDENTITY(1,1) PRIMARY KEY,
    id_pedido       INT           NOT NULL,
    id_producto     INT           NOT NULL,
    cantidad        DECIMAL(12,2) NOT NULL,
    precio_lista    DECIMAL(12,2) NOT NULL,                -- precio original (IVA incl.)
    descuento_pct   DECIMAL(5,2)  NOT NULL DEFAULT 0,
    precio_unitario DECIMAL(12,2) NOT NULL,                -- precio final (IVA incl.)
    codigo_iva      VARCHAR(10)   NOT NULL,
    porcentaje_iva  DECIMAL(5,2)  NOT NULL,
    -- Desglose automático (atributos DERIVADOS)
    total_linea    AS (CAST(cantidad * precio_unitario AS DECIMAL(14,2))) PERSISTED,
    base_imponible AS (CAST(cantidad * precio_unitario / (1 + porcentaje_iva / 100) AS DECIMAL(14,2))) PERSISTED,
    iva            AS (CAST(cantidad * precio_unitario AS DECIMAL(14,2))
                     - CAST(cantidad * precio_unitario / (1 + porcentaje_iva / 100) AS DECIMAL(14,2))) PERSISTED,
    CONSTRAINT FK_PedDet_Pedido   FOREIGN KEY (id_pedido)   REFERENCES Pedido(id_pedido) ON DELETE CASCADE,
    CONSTRAINT FK_PedDet_Producto FOREIGN KEY (id_producto) REFERENCES Producto(id_producto),
    CONSTRAINT FK_PedDet_Impuesto FOREIGN KEY (codigo_iva)  REFERENCES Impuesto(codigo_iva),
    CONSTRAINT UQ_PedDet UNIQUE (id_pedido, id_producto),
    CONSTRAINT CK_PedDet_Cantidad  CHECK (cantidad > 0),
    CONSTRAINT CK_PedDet_Descuento CHECK (descuento_pct BETWEEN 0 AND 50),
    CONSTRAINT CK_PedDet_Precio
        CHECK (precio_unitario = CAST(precio_lista * (1 - descuento_pct / 100) AS DECIMAL(12,2)))
);

-- -----------------------------------------------------
-- 6. FACTURA (Etapa 3)
-- -----------------------------------------------------
CREATE TABLE Factura (
    id_factura        INT IDENTITY(1,1) PRIMARY KEY,
    tipo_documento    VARCHAR(10)   NOT NULL DEFAULT 'Factura',
    serie             VARCHAR(10)   NOT NULL,
    numero            INT           NOT NULL,
    numero_documento AS (serie + '-' + RIGHT('00000000' + CAST(numero AS VARCHAR(8)), 8)) PERSISTED,
    id_pedido         INT           NOT NULL UNIQUE,       -- 1:1 con Pedido
    fecha_factura     DATE          NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    fecha_vencimiento DATE          NOT NULL,
    id_cliente        INT           NOT NULL,
    id_vendedor       INT           NOT NULL,
    id_sitio          INT           NOT NULL,
    codigo_moneda     CHAR(3)       NOT NULL DEFAULT 'GTQ',
    tipo_cambio       DECIMAL(12,6) NOT NULL DEFAULT 1,
    base_imponible    DECIMAL(14,2) NOT NULL,
    iva               DECIMAL(14,2) NOT NULL,
    total             DECIMAL(14,2) NOT NULL,
    saldo_pendiente   DECIMAL(14,2) NOT NULL,
    estado            VARCHAR(10)   NOT NULL DEFAULT 'Activa',
    -- Estado de pago DERIVADO del saldo
    estado_pago AS (CASE WHEN saldo_pendiente = 0     THEN 'Pagada'
                         WHEN saldo_pendiente < total THEN 'Parcial'
                         ELSE 'Pendiente' END) PERSISTED,
    motivo_anulacion  VARCHAR(200)  NULL,
    usuario_creador   VARCHAR(50)   NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_Factura_SerieNumero UNIQUE (serie, numero),
    CONSTRAINT FK_Factura_Pedido FOREIGN KEY (id_pedido) REFERENCES Pedido(id_pedido),
    CONSTRAINT FK_Factura_ClienteVendedor
        FOREIGN KEY (id_cliente, id_vendedor) REFERENCES Cliente(id_cliente, id_vendedor),
    CONSTRAINT FK_Factura_Sitio  FOREIGN KEY (id_sitio)      REFERENCES Sitio(id_sitio),
    CONSTRAINT FK_Factura_Moneda FOREIGN KEY (codigo_moneda) REFERENCES Moneda(codigo),
    CONSTRAINT CK_Factura_Tipo    CHECK (tipo_documento = 'Factura'),
    CONSTRAINT CK_Factura_Estado  CHECK (estado IN ('Activa', 'Anulada')),
    CONSTRAINT CK_Factura_Totales CHECK (total = base_imponible + iva),
    CONSTRAINT CK_Factura_Saldo   CHECK (saldo_pendiente BETWEEN 0 AND total),
    CONSTRAINT CK_Factura_Fechas  CHECK (fecha_vencimiento >= fecha_factura),
    CONSTRAINT CK_Factura_Anulacion CHECK (estado = 'Activa' OR motivo_anulacion IS NOT NULL)
);

CREATE TABLE Factura_Detalle (
    id_detalle      INT IDENTITY(1,1) PRIMARY KEY,
    id_factura      INT           NOT NULL,
    id_producto     INT           NOT NULL,
    cantidad        DECIMAL(12,2) NOT NULL,
    precio_unitario DECIMAL(12,2) NOT NULL,
    codigo_iva      VARCHAR(10)   NOT NULL,
    porcentaje_iva  DECIMAL(5,2)  NOT NULL,
    costo_unitario  DECIMAL(12,4) NOT NULL,                 -- para el costo de ventas
    total_linea    AS (CAST(cantidad * precio_unitario AS DECIMAL(14,2))) PERSISTED,
    base_imponible AS (CAST(cantidad * precio_unitario / (1 + porcentaje_iva / 100) AS DECIMAL(14,2))) PERSISTED,
    iva            AS (CAST(cantidad * precio_unitario AS DECIMAL(14,2))
                     - CAST(cantidad * precio_unitario / (1 + porcentaje_iva / 100) AS DECIMAL(14,2))) PERSISTED,
    CONSTRAINT FK_FacDet_Factura  FOREIGN KEY (id_factura)  REFERENCES Factura(id_factura),
    CONSTRAINT FK_FacDet_Producto FOREIGN KEY (id_producto) REFERENCES Producto(id_producto),
    CONSTRAINT FK_FacDet_Impuesto FOREIGN KEY (codigo_iva)  REFERENCES Impuesto(codigo_iva),
    CONSTRAINT UQ_FacDet UNIQUE (id_factura, id_producto),
    CONSTRAINT CK_FacDet_Cantidad CHECK (cantidad > 0),
    CONSTRAINT CK_FacDet_Precio   CHECK (precio_unitario > 0)
);

-- -----------------------------------------------------
-- 7. COBRO (Etapa 4)
-- -----------------------------------------------------
CREATE TABLE Cobro (
    id_cobro           INT IDENTITY(1,1) PRIMARY KEY,
    numero AS ('REC-' + RIGHT('000000' + CAST(id_cobro AS VARCHAR(6)), 6)) PERSISTED,
    fecha_cobro        DATE          NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    id_factura         INT           NOT NULL,             -- el cliente se obtiene de la factura
    monto              DECIMAL(14,2) NOT NULL,
    metodo_pago        VARCHAR(15)   NOT NULL,
    id_cuenta_bancaria INT           NULL,
    referencia         VARCHAR(50)   NULL,                 -- No. de boleta, cheque, voucher
    estado             VARCHAR(10)   NOT NULL DEFAULT 'Aplicado',
    usuario_creador    VARCHAR(50)   NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_Cobro_Numero UNIQUE (numero),
    CONSTRAINT FK_Cobro_Factura FOREIGN KEY (id_factura) REFERENCES Factura(id_factura),
    CONSTRAINT FK_Cobro_CtaBancaria
        FOREIGN KEY (id_cuenta_bancaria) REFERENCES Cuenta_Bancaria(id_cuenta_bancaria),
    CONSTRAINT CK_Cobro_Monto  CHECK (monto > 0),
    CONSTRAINT CK_Cobro_Metodo CHECK (metodo_pago IN ('Efectivo', 'Transferencia', 'Cheque', 'Tarjeta')),
    CONSTRAINT CK_Cobro_Banco  CHECK (metodo_pago = 'Efectivo' OR id_cuenta_bancaria IS NOT NULL),
    CONSTRAINT CK_Cobro_Estado CHECK (estado IN ('Aplicado', 'Anulado'))
);

-- -----------------------------------------------------
-- 8. DESPACHO (Etapa 5)
-- -----------------------------------------------------
CREATE TABLE Despacho (
    id_despacho     INT IDENTITY(1,1) PRIMARY KEY,
    numero AS ('DES-' + RIGHT('000000' + CAST(id_despacho AS VARCHAR(6)), 6)) PERSISTED,
    id_factura      INT          NOT NULL,
    fecha_despacho  DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    id_sitio        INT          NOT NULL,
    recibido_por    VARCHAR(100) NOT NULL,
    estado          VARCHAR(12)  NOT NULL DEFAULT 'Completado',
    usuario_creador VARCHAR(50)  NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion  DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_Despacho_Numero UNIQUE (numero),
    CONSTRAINT FK_Despacho_Factura FOREIGN KEY (id_factura) REFERENCES Factura(id_factura),
    CONSTRAINT FK_Despacho_Sitio   FOREIGN KEY (id_sitio)   REFERENCES Sitio(id_sitio),
    CONSTRAINT CK_Despacho_Estado  CHECK (estado IN ('Completado', 'Anulado'))
);

CREATE TABLE Despacho_Detalle (
    id_detalle      INT IDENTITY(1,1) PRIMARY KEY,
    id_despacho     INT           NOT NULL,
    id_producto     INT           NOT NULL,
    id_localizacion INT           NOT NULL,                -- de dónde salió físicamente
    cantidad        DECIMAL(12,2) NOT NULL,
    CONSTRAINT FK_DesDet_Despacho FOREIGN KEY (id_despacho)
        REFERENCES Despacho(id_despacho) ON DELETE CASCADE,
    CONSTRAINT FK_DesDet_Producto     FOREIGN KEY (id_producto)     REFERENCES Producto(id_producto),
    CONSTRAINT FK_DesDet_Localizacion FOREIGN KEY (id_localizacion) REFERENCES Localizacion(id_localizacion),
    CONSTRAINT UQ_DesDet UNIQUE (id_despacho, id_producto, id_localizacion),
    CONSTRAINT CK_DesDet_Cantidad CHECK (cantidad > 0)
);

-- -----------------------------------------------------
-- 9. PARTIDA CONTABLE (encabezado + detalle Debe/Haber)
-- -----------------------------------------------------
CREATE TABLE Partida_Contable (
    id_partida       INT IDENTITY(1,1) PRIMARY KEY,
    numero AS ('PDA-' + RIGHT('000000' + CAST(id_partida AS VARCHAR(6)), 6)) PERSISTED,
    fecha_contable   DATE          NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    tipo_documento   VARCHAR(15)   NOT NULL,
    id_documento     INT           NOT NULL,
    documento_numero VARCHAR(30)   NOT NULL,
    descripcion      VARCHAR(200)  NOT NULL,
    codigo_moneda    CHAR(3)       NOT NULL DEFAULT 'GTQ',
    total_debe       DECIMAL(14,2) NOT NULL,
    total_haber      DECIMAL(14,2) NOT NULL,
    usuario_creador  VARCHAR(50)   NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_Partida_Numero UNIQUE (numero),
    CONSTRAINT FK_Partida_Moneda FOREIGN KEY (codigo_moneda) REFERENCES Moneda(codigo),
    CONSTRAINT CK_Partida_Tipo CHECK (tipo_documento IN
        ('Factura', 'Cobro', 'Despacho', 'Anulación', 'Ajuste')),
    -- REGLA DE ORO DE LA CONTABILIDAD: Debe = Haber
    CONSTRAINT CK_Partida_Cuadrada CHECK (total_debe = total_haber AND total_debe > 0)
);

CREATE TABLE Partida_Detalle (
    id_detalle  INT IDENTITY(1,1) PRIMARY KEY,
    id_partida  INT           NOT NULL,
    linea       SMALLINT      NOT NULL,
    id_cuenta   INT           NOT NULL,
    tipo_monto  CHAR(1)       NOT NULL,                     -- D = Debe, H = Haber
    monto       DECIMAL(14,2) NOT NULL,
    debe  AS (CASE WHEN tipo_monto = 'D' THEN monto ELSE 0 END) PERSISTED,
    haber AS (CASE WHEN tipo_monto = 'H' THEN monto ELSE 0 END) PERSISTED,
    id_cliente  INT           NULL,                         -- auxiliar de clientes
    descripcion VARCHAR(200)  NULL,
    CONSTRAINT FK_PdaDet_Partida FOREIGN KEY (id_partida)
        REFERENCES Partida_Contable(id_partida) ON DELETE CASCADE,
    CONSTRAINT FK_PdaDet_Cuenta  FOREIGN KEY (id_cuenta)  REFERENCES Cuenta_Contable(id_cuenta),
    CONSTRAINT FK_PdaDet_Cliente FOREIGN KEY (id_cliente) REFERENCES Cliente(id_cliente),
    CONSTRAINT UQ_PdaDet_Linea UNIQUE (id_partida, linea),
    CONSTRAINT CK_PdaDet_Tipo  CHECK (tipo_monto IN ('D', 'H')),
    CONSTRAINT CK_PdaDet_Monto CHECK (monto > 0)
);
GO

-- -----------------------------------------------------
-- 10. DATOS: cuentas bancarias de la empresa
-- -----------------------------------------------------
INSERT INTO Cuenta_Bancaria (banco, numero_cuenta, tipo_cuenta, codigo_moneda, id_cuenta_contable)
SELECT v.banco, v.numero, v.tipo, v.moneda, cc.id_cuenta
FROM (VALUES
    ('Banco Industrial', '000-123456-7', 'Monetaria', 'GTQ', '1.1.01.03'),
    ('Banco Industrial', '000-765432-1', 'Monetaria', 'USD', '1.1.01.03'),
    ('Banrural',         '3-045-12345-6','Monetaria', 'GTQ', '1.1.01.04')
) AS v(banco, numero, tipo, moneda, cuenta)
INNER JOIN Cuenta_Contable cc ON cc.codigo = v.cuenta;
GO

-- =====================================================
-- VERIFICACION: resumen de TODA la base de datos
-- =====================================================
SELECT t.name AS Tabla,
       (SELECT COUNT(*) FROM sys.columns c
         WHERE c.object_id = t.object_id)                   AS Columnas,
       (SELECT COUNT(*) FROM sys.columns c
         WHERE c.object_id = t.object_id AND c.is_computed = 1) AS Calculadas,
       (SELECT COUNT(*) FROM sys.foreign_keys f
         WHERE f.parent_object_id = t.object_id)            AS Llaves_Foraneas,
       (SELECT COUNT(*) FROM sys.check_constraints k
         WHERE k.parent_object_id = t.object_id)            AS Reglas_CHECK
FROM sys.tables t
ORDER BY t.name;

-- Totales generales
SELECT (SELECT COUNT(*) FROM sys.tables)            AS Total_Tablas,
       (SELECT COUNT(*) FROM sys.foreign_keys)      AS Total_Llaves_Foraneas,
       (SELECT COUNT(*) FROM sys.check_constraints) AS Total_Reglas_CHECK,
       (SELECT COUNT(*) FROM sys.columns c
          INNER JOIN sys.tables t ON t.object_id = c.object_id
         WHERE c.is_computed = 1)                   AS Total_Columnas_Calculadas;

-- Inventario con sus nuevas columnas
SELECT TOP 5 i.id_inventario, p.codigo, i.cantidad,
       i.cantidad_reservada, i.cantidad_disponible
FROM Inventario i
INNER JOIN Producto p ON p.id_producto = i.id_producto;

-- Cuentas bancarias
SELECT cb.banco, cb.numero_cuenta, cb.codigo_moneda,
       cc.codigo + ' ' + cc.nombre AS Cuenta_Contable
FROM Cuenta_Bancaria cb
INNER JOIN Cuenta_Contable cc ON cc.id_cuenta = cb.id_cuenta_contable;
