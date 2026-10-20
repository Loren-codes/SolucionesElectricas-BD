-- =====================================================
-- Script 05: Productos, Categorías e Inventario (Grupo B)
-- =====================================================
USE SolucionesElectricas;
GO

-- -----------------------------------------------------
-- 0. LIMPIEZA
-- -----------------------------------------------------
DROP VIEW  IF EXISTS vw_Producto_Cuenta;
DROP TABLE IF EXISTS Movimiento_Inventario;
DROP TABLE IF EXISTS Inventario;
DROP TABLE IF EXISTS Producto;
DROP TABLE IF EXISTS Subcategoria;
DROP TABLE IF EXISTS Categoria;
DROP TABLE IF EXISTS Linea;
DROP TABLE IF EXISTS Marca;
DROP TABLE IF EXISTS Unidad_Medida;
DROP TABLE IF EXISTS Impuesto;
GO

-- -----------------------------------------------------
-- 1. IMPUESTO (código de IVA configurable)
-- -----------------------------------------------------
CREATE TABLE Impuesto (
    codigo_iva    VARCHAR(10)  PRIMARY KEY,          -- IVA12, IVA5, EXE
    descripcion   VARCHAR(100) NOT NULL,
    porcentaje    DECIMAL(5,2) NOT NULL,
    id_cuenta_iva INT          NULL,                 -- Cuenta "IVA por Pagar"
    activo        BIT          NOT NULL DEFAULT 1,
    CONSTRAINT FK_Impuesto_Cuenta
        FOREIGN KEY (id_cuenta_iva) REFERENCES Cuenta_Contable(id_cuenta),
    CONSTRAINT CK_Impuesto_Porcentaje CHECK (porcentaje BETWEEN 0 AND 100)
);

-- -----------------------------------------------------
-- 2. UNIDAD_MEDIDA
-- -----------------------------------------------------
CREATE TABLE Unidad_Medida (
    codigo            VARCHAR(5)  PRIMARY KEY,       -- MT, UN, RL...
    nombre            VARCHAR(30) NOT NULL UNIQUE,
    permite_decimales BIT         NOT NULL DEFAULT 0 -- 1 = se puede vender 2.5 metros
);

-- -----------------------------------------------------
-- 3. MARCA
-- -----------------------------------------------------
CREATE TABLE Marca (
    id_marca    INT IDENTITY(1,1) PRIMARY KEY,
    nombre      VARCHAR(60) NOT NULL UNIQUE,
    pais_origen VARCHAR(40) NULL,
    activo      BIT         NOT NULL DEFAULT 1
);

-- -----------------------------------------------------
-- 4. LINEA (cada línea pertenece a una marca)
-- -----------------------------------------------------
CREATE TABLE Linea (
    id_linea INT IDENTITY(1,1) PRIMARY KEY,
    id_marca INT         NOT NULL,
    nombre   VARCHAR(60) NOT NULL,
    activo   BIT         NOT NULL DEFAULT 1,
    CONSTRAINT FK_Linea_Marca FOREIGN KEY (id_marca) REFERENCES Marca(id_marca),
    CONSTRAINT UQ_Linea UNIQUE (id_marca, nombre)
);

-- -----------------------------------------------------
-- 5. CATEGORIA (con cuentas contables opcionales)
-- -----------------------------------------------------
CREATE TABLE Categoria (
    id_categoria         INT IDENTITY(1,1) PRIMARY KEY,
    codigo               CHAR(2)      NOT NULL UNIQUE,   -- CO, MA, AE, TF
    nombre               VARCHAR(80)  NOT NULL UNIQUE,
    descripcion          VARCHAR(200) NULL,
    id_cuenta_inventario INT          NULL,
    id_cuenta_venta      INT          NULL,
    id_cuenta_costo      INT          NULL,
    activo               BIT          NOT NULL DEFAULT 1,
    usuario_creador      VARCHAR(50)  NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion       DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Categoria_CtaInventario
        FOREIGN KEY (id_cuenta_inventario) REFERENCES Cuenta_Contable(id_cuenta),
    CONSTRAINT FK_Categoria_CtaVenta
        FOREIGN KEY (id_cuenta_venta) REFERENCES Cuenta_Contable(id_cuenta),
    CONSTRAINT FK_Categoria_CtaCosto
        FOREIGN KEY (id_cuenta_costo) REFERENCES Cuenta_Contable(id_cuenta),
    CONSTRAINT CK_Categoria_Codigo CHECK (codigo LIKE '[A-Z][A-Z]')
);

-- -----------------------------------------------------
-- 6. SUBCATEGORIA
-- -----------------------------------------------------
CREATE TABLE Subcategoria (
    id_subcategoria INT IDENTITY(1,1) PRIMARY KEY,
    id_categoria    INT          NOT NULL,
    codigo          CHAR(2)      NOT NULL,
    nombre          VARCHAR(80)  NOT NULL,
    descripcion     VARCHAR(200) NULL,
    activo          BIT          NOT NULL DEFAULT 1,
    CONSTRAINT FK_Subcategoria_Categoria
        FOREIGN KEY (id_categoria) REFERENCES Categoria(id_categoria),
    CONSTRAINT UQ_Subcategoria_Codigo UNIQUE (id_categoria, codigo),
    CONSTRAINT UQ_Subcategoria_Nombre UNIQUE (id_categoria, nombre)
);

-- -----------------------------------------------------
-- 7. PRODUCTO
-- -----------------------------------------------------
CREATE TABLE Producto (
    id_producto          INT IDENTITY(1,1) PRIMARY KEY,
    codigo               VARCHAR(15)   NOT NULL UNIQUE,   -- CO-BC-0001
    descripcion          VARCHAR(200)  NOT NULL,
    imagen_url           VARCHAR(255)  NULL,
    id_linea             INT           NOT NULL,          -- la marca se obtiene de la línea
    id_subcategoria      INT           NOT NULL,          -- la categoría se obtiene de la subcategoría
    codigo_um            VARCHAR(5)    NOT NULL,
    costo_unitario       DECIMAL(12,4) NOT NULL,
    precio_unitario      DECIMAL(12,2) NOT NULL,          -- IVA incluido
    codigo_iva           VARCHAR(10)   NOT NULL DEFAULT 'IVA12',
    id_cuenta_inventario INT           NULL,              -- se usan si la categoría no las define
    id_cuenta_venta      INT           NULL,
    id_cuenta_costo      INT           NULL,
    stock_minimo         DECIMAL(12,2) NOT NULL DEFAULT 0,
    activo               BIT           NOT NULL DEFAULT 1,
    usuario_creador      VARCHAR(50)   NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Producto_Linea        FOREIGN KEY (id_linea)        REFERENCES Linea(id_linea),
    CONSTRAINT FK_Producto_Subcategoria FOREIGN KEY (id_subcategoria) REFERENCES Subcategoria(id_subcategoria),
    CONSTRAINT FK_Producto_UM           FOREIGN KEY (codigo_um)       REFERENCES Unidad_Medida(codigo),
    CONSTRAINT FK_Producto_Impuesto     FOREIGN KEY (codigo_iva)      REFERENCES Impuesto(codigo_iva),
    CONSTRAINT FK_Producto_CtaInventario
        FOREIGN KEY (id_cuenta_inventario) REFERENCES Cuenta_Contable(id_cuenta),
    CONSTRAINT FK_Producto_CtaVenta
        FOREIGN KEY (id_cuenta_venta) REFERENCES Cuenta_Contable(id_cuenta),
    CONSTRAINT FK_Producto_CtaCosto
        FOREIGN KEY (id_cuenta_costo) REFERENCES Cuenta_Contable(id_cuenta),
    CONSTRAINT CK_Producto_Codigo
        CHECK (codigo LIKE '[A-Z][A-Z]-[A-Z][A-Z]-[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Producto_Costo       CHECK (costo_unitario >= 0),
    CONSTRAINT CK_Producto_Precio      CHECK (precio_unitario > 0),
    CONSTRAINT CK_Producto_Margen      CHECK (precio_unitario >= costo_unitario),
    CONSTRAINT CK_Producto_StockMinimo CHECK (stock_minimo >= 0)
);

-- -----------------------------------------------------
-- 8. INVENTARIO (relación N:M Producto - Localización)
-- -----------------------------------------------------
CREATE TABLE Inventario (
    id_inventario           INT IDENTITY(1,1) PRIMARY KEY,
    id_producto             INT           NOT NULL,
    id_localizacion         INT           NOT NULL,
    cantidad                DECIMAL(12,2) NOT NULL DEFAULT 0,
    fecha_ultimo_movimiento DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Inventario_Producto
        FOREIGN KEY (id_producto) REFERENCES Producto(id_producto),
    CONSTRAINT FK_Inventario_Localizacion
        FOREIGN KEY (id_localizacion) REFERENCES Localizacion(id_localizacion),
    CONSTRAINT UQ_Inventario UNIQUE (id_producto, id_localizacion),
    CONSTRAINT CK_Inventario_NoNegativo CHECK (cantidad >= 0)
);

-- -----------------------------------------------------
-- 9. MOVIMIENTO_INVENTARIO (Kardex)
-- -----------------------------------------------------
CREATE TABLE Movimiento_Inventario (
    id_movimiento    INT IDENTITY(1,1) PRIMARY KEY,
    fecha            DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    id_producto      INT           NOT NULL,
    id_localizacion  INT           NOT NULL,
    tipo_movimiento  VARCHAR(20)   NOT NULL,
    cantidad         DECIMAL(12,2) NOT NULL,     -- (+) entra, (-) sale
    costo_unitario   DECIMAL(12,4) NOT NULL,
    saldo_resultante DECIMAL(12,2) NOT NULL,
    documento_tipo   VARCHAR(20)   NULL,         -- FACTURA, DESPACHO, AJUSTE...
    documento_numero VARCHAR(30)   NULL,
    justificacion    VARCHAR(200)  NULL,
    usuario_creador  VARCHAR(50)   NOT NULL DEFAULT SUSER_SNAME(),
    CONSTRAINT FK_Movimiento_Producto
        FOREIGN KEY (id_producto) REFERENCES Producto(id_producto),
    CONSTRAINT FK_Movimiento_Localizacion
        FOREIGN KEY (id_localizacion) REFERENCES Localizacion(id_localizacion),
    CONSTRAINT CK_Movimiento_Tipo CHECK (tipo_movimiento IN
        ('Inventario Inicial', 'Entrada', 'Salida', 'Devolución', 'Ajuste', 'Traslado')),
    CONSTRAINT CK_Movimiento_Cantidad CHECK (cantidad <> 0),
    CONSTRAINT CK_Movimiento_Saldo    CHECK (saldo_resultante >= 0)
);
GO

-- -----------------------------------------------------
-- 10. TRIGGER: regla contable del producto
-- -----------------------------------------------------
CREATE TRIGGER trg_Producto_ValidarCuentas
ON Producto
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN Subcategoria s ON s.id_subcategoria = i.id_subcategoria
        INNER JOIN Categoria    c ON c.id_categoria    = s.id_categoria
        WHERE COALESCE(c.id_cuenta_inventario, i.id_cuenta_inventario) IS NULL
           OR COALESCE(c.id_cuenta_venta,      i.id_cuenta_venta)      IS NULL
           OR COALESCE(c.id_cuenta_costo,      i.id_cuenta_costo)      IS NULL
    )
    BEGIN
        ;THROW 50001, 'Regla contable: si la categoría no define cuentas contables, el producto debe definirlas.', 1;
    END
END;
GO

-- -----------------------------------------------------
-- 11. VISTA: la cuenta contable que realmente usa cada producto
-- -----------------------------------------------------
CREATE VIEW vw_Producto_Cuenta
AS
SELECT p.id_producto,
       p.codigo,
       p.descripcion,
       c.nombre AS categoria,
       CASE WHEN c.id_cuenta_venta IS NOT NULL
            THEN 'Categoría' ELSE 'Producto' END              AS origen_cuenta,
       ci.id_cuenta AS id_cuenta_inventario,
       ci.codigo + ' ' + ci.nombre                           AS cuenta_inventario,
       cv.id_cuenta AS id_cuenta_venta,
       cv.codigo + ' ' + cv.nombre                           AS cuenta_venta,
       cc.id_cuenta AS id_cuenta_costo,
       cc.codigo + ' ' + cc.nombre                           AS cuenta_costo
FROM Producto p
INNER JOIN Subcategoria    s  ON s.id_subcategoria = p.id_subcategoria
INNER JOIN Categoria       c  ON c.id_categoria    = s.id_categoria
INNER JOIN Cuenta_Contable ci ON ci.id_cuenta = COALESCE(c.id_cuenta_inventario, p.id_cuenta_inventario)
INNER JOIN Cuenta_Contable cv ON cv.id_cuenta = COALESCE(c.id_cuenta_venta,      p.id_cuenta_venta)
INNER JOIN Cuenta_Contable cc ON cc.id_cuenta = COALESCE(c.id_cuenta_costo,      p.id_cuenta_costo);
GO

-- =====================================================
-- DATOS
-- =====================================================

-- 12. IMPUESTOS
INSERT INTO Impuesto (codigo_iva, descripcion, porcentaje, id_cuenta_iva)
SELECT v.codigo, v.descripcion, v.porcentaje, cc.id_cuenta
FROM (VALUES
    ('IVA12', 'IVA tasa general 12%',          12.00, '2.1.02.01'),
    ('IVA5',  'IVA pequeño contribuyente 5%',   5.00, '2.1.02.01'),
    ('EXE',   'Exento de IVA',                  0.00, NULL)
) AS v(codigo, descripcion, porcentaje, cuenta)
LEFT JOIN Cuenta_Contable cc ON cc.codigo = v.cuenta;

-- 13. UNIDADES DE MEDIDA
INSERT INTO Unidad_Medida (codigo, nombre, permite_decimales) VALUES
('MT',  'Metro',     1),
('UN',  'Unidad',    0),
('RL',  'Rollo',     0),
('KIT', 'Kit',       0),
('PAQ', 'Paquete',   0),
('KG',  'Kilogramo', 1);

-- 14. MARCAS
INSERT INTO Marca (nombre, pais_origen) VALUES
('Condumex',           'México'),
('Viakon',             'México'),
('3M',                 'Estados Unidos'),
('Schneider Electric', 'Francia'),
('Legrand',            'Francia'),
('Durman',             'Costa Rica'),
('nVent ERICO',        'Estados Unidos'),
('Fluke',              'Estados Unidos'),
('Genérico',           NULL);

-- 15. LINEAS (se conectan a su marca por el nombre)
INSERT INTO Linea (id_marca, nombre)
SELECT m.id_marca, v.linea
FROM (VALUES
    ('Condumex', 'Vinanel XXI'),        ('Condumex', 'Vulcanel'),
    ('Viakon', 'THW-LS'),               ('Viakon', 'XLP 15kV'),
    ('Viakon', 'ACSR'),                 ('Viakon', 'Control'),
    ('3M', 'Scotch'),                   ('3M', 'Scotchcast'),
    ('3M', 'Scotchlok'),
    ('Schneider Electric', 'Easy9'),    ('Schneider Electric', 'Spacial'),
    ('Schneider Electric', 'Linergy'),  ('Schneider Electric', 'Mureva'),
    ('Legrand', 'DLP'),                 ('Legrand', 'Cablofil'),
    ('Durman', 'Conduit'),              ('Durman', 'Corrugado'),
    ('nVent ERICO', 'Eritech'),         ('nVent ERICO', 'Cadweld'),
    ('Fluke', 'GEO'),
    ('Genérico', 'General')
) AS v(marca, linea)
INNER JOIN Marca m ON m.nombre = v.marca;

-- 16. CATEGORIAS (Tierra Física NO define cuentas: las definirá cada producto)
INSERT INTO Categoria (codigo, nombre, descripcion,
                       id_cuenta_inventario, id_cuenta_venta, id_cuenta_costo)
SELECT v.codigo, v.nombre, v.descripcion, ci.id_cuenta, cv.id_cuenta, cc.id_cuenta
FROM (VALUES
    ('CO', 'Conductores',
           'Cables y conductores eléctricos',
           '1.1.03.01', '4.1.01.01', '5.1.01.01'),
    ('MA', 'Materiales Aislantes',
           'Materiales para aislamiento eléctrico',
           '1.1.03.02', '4.1.01.02', '5.1.01.02'),
    ('AE', 'Accesorios para Instalaciones Eléctricas',
           'Conducción, conexión y protección',
           '1.1.03.03', '4.1.01.03', '5.1.01.03'),
    ('TF', 'Accesorios para Instalaciones de Tierra Física',
           'Electrodos, conexión y medición de tierra',
           NULL, NULL, NULL)
) AS v(codigo, nombre, descripcion, cta_inv, cta_vta, cta_cos)
LEFT JOIN Cuenta_Contable ci ON ci.codigo = v.cta_inv
LEFT JOIN Cuenta_Contable cv ON cv.codigo = v.cta_vta
LEFT JOIN Cuenta_Contable cc ON cc.codigo = v.cta_cos;

-- 17. SUBCATEGORIAS (las 15 del enunciado)
INSERT INTO Subcategoria (id_categoria, codigo, nombre, descripcion)
SELECT c.id_categoria, v.codigo, v.nombre, v.descripcion
FROM (VALUES
    ('CO', 'BC', 'Baja corriente',   'Conductores para baja corriente'),
    ('CO', 'MC', 'Media corriente',  'Conductores para media corriente'),
    ('CO', 'AC', 'Alta corriente',   'Conductores para alta corriente'),
    ('MA', 'PV', 'PVC',              'Aislantes de policloruro de vinilo'),
    ('MA', 'PE', 'Polietileno',      'Aislantes de polietileno'),
    ('MA', 'GO', 'Goma',             'Aislantes de goma'),
    ('MA', 'RE', 'Resinas epóxicas', 'Resinas para empalmes y encapsulados'),
    ('MA', 'CE', 'Cerámicos',        'Aisladores cerámicos y de porcelana'),
    ('MA', 'FV', 'Fibra de vidrio',  'Aislantes de fibra de vidrio'),
    ('AE', 'CD', 'Conducción',       'Canaletas, tubos, bandejas, uniones, abrazaderas'),
    ('AE', 'CX', 'Conexión',         'Terminales, zapatas, conectores, bornes'),
    ('AE', 'PR', 'Protección',       'Cajas, gabinetes, aislantes, cubiertas'),
    ('TF', 'EL', 'Electrodos',       'Varillas, placas, mallas'),
    ('TF', 'CN', 'Conexión',         'Soldadura exotérmica, conectores mecánicos'),
    ('TF', 'ME', 'Medición',         'Terrómetros, pinzas')
) AS v(cat, codigo, nombre, descripcion)
INNER JOIN Categoria c ON c.codigo = v.cat;

-- 18. PRODUCTOS (código inteligente: CATEGORIA-SUBCATEGORIA-CORRELATIVO)
INSERT INTO Producto (codigo, descripcion, imagen_url, id_linea, id_subcategoria,
                      codigo_um, costo_unitario, precio_unitario, codigo_iva,
                      id_cuenta_inventario, id_cuenta_venta, id_cuenta_costo,
                      stock_minimo)
SELECT v.codigo, v.descripcion,
       'C:\Proyecto_BD\imagenes\' + v.codigo + '.jpg',
       li.id_linea, sc.id_subcategoria, v.um, v.costo, v.precio, v.iva,
       ci.id_cuenta, cv.id_cuenta, cc.id_cuenta,
       CASE WHEN v.precio >= 5000 THEN 2
            WHEN v.um = 'MT'      THEN 500
            ELSE 20 END
FROM (VALUES
 ('CO-BC-0001','Cable THHN 12 AWG cobre, color rojo',          'Condumex','Vinanel XXI','MT',    3.10,    5.25,'IVA12'),
 ('CO-BC-0002','Cable THHN 10 AWG cobre, color negro',         'Condumex','Vinanel XXI','MT',    4.80,    7.95,'IVA12'),
 ('CO-BC-0003','Cable THW-LS 8 AWG cobre, color verde',        'Viakon','THW-LS',       'MT',    7.40,   12.25,'IVA12'),
 ('CO-BC-0004','Cable de control 4x14 AWG',                    'Viakon','Control',      'MT',    9.50,   15.75,'IVA12'),
 ('CO-MC-0001','Cable XLP 2 AWG aluminio 15 kV',               'Viakon','XLP 15kV',     'MT',   38.00,   62.50,'IVA12'),
 ('CO-MC-0002','Cable XLP 1/0 AWG cobre 15 kV',                'Condumex','Vulcanel',   'MT',   52.00,   85.00,'IVA12'),
 ('CO-AC-0001','Cable ACSR 4/0 AWG desnudo',                   'Viakon','ACSR',         'MT',   24.00,   39.50,'IVA12'),
 ('CO-AC-0002','Cable XLP 500 MCM cobre 35 kV',                'Condumex','Vulcanel',   'MT',  210.00,  345.00,'IVA12'),
 ('MA-PV-0001','Tubo PVC eléctrico 3/4" x 3 m',                'Durman','Conduit',      'UN',    9.50,   16.50,'IVA12'),
 ('MA-PV-0002','Cinta aislante PVC Super 33+ 19 mm x 20 m',    '3M','Scotch',           'UN',   38.00,   62.00,'IVA12'),
 ('MA-PE-0001','Ducto corrugado de polietileno 1" (rollo 50 m)','Durman','Corrugado',   'RL',  210.00,  345.00,'IVA12'),
 ('MA-GO-0001','Cinta de goma autofundente 23, 19 mm x 9 m',   '3M','Scotch',           'UN',   85.00,  139.00,'IVA12'),
 ('MA-RE-0001','Kit de empalme de resina epóxica 82-A1',       '3M','Scotchcast',       'KIT', 165.00,  270.00,'IVA12'),
 ('MA-CE-0001','Aislador de porcelana tipo carrete 53-2',      'Genérico','General',    'UN',   12.00,   19.75,'IVA12'),
 ('MA-FV-0001','Manga de fibra de vidrio 1/4" (rollo 25 m)',   'Genérico','General',    'RL',   95.00,  155.00,'IVA12'),
 ('AE-CD-0001','Canaleta PVC 20x10 mm x 2 m',                  'Legrand','DLP',         'UN',   14.00,   23.50,'IVA12'),
 ('AE-CD-0002','Bandeja portacable tipo malla 300 mm x 3 m',   'Legrand','Cablofil',    'UN',  420.00,  690.00,'IVA12'),
 ('AE-CD-0003','Abrazadera para tubo conduit 3/4" (paquete 25)','Genérico','General',   'PAQ',  18.00,   29.50,'IVA12'),
 ('AE-CX-0001','Terminal de ojo 10 AWG (paquete 100)',         '3M','Scotchlok',        'PAQ',  75.00,  123.00,'IVA12'),
 ('AE-CX-0002','Zapata de compresión 2/0 AWG',                 'Genérico','General',    'UN',   22.00,   36.00,'IVA12'),
 ('AE-CX-0003','Borne de conexión para riel DIN 4 mm²',        'Schneider Electric','Linergy','UN', 9.80, 16.25,'IVA12'),
 ('AE-PR-0001','Caja de registro PVC 4" x 4"',                 'Schneider Electric','Mureva', 'UN', 7.50, 12.50,'IVA12'),
 ('AE-PR-0002','Gabinete metálico IP65 400x300x200 mm',        'Schneider Electric','Spacial','UN',780.00,1275.00,'IVA12'),
 ('AE-PR-0003','Centro de carga 8 circuitos',                  'Schneider Electric','Easy9',  'UN',310.00, 495.00,'IVA12'),
 ('TF-EL-0001','Varilla de tierra copperweld 5/8" x 8 pies',   'nVent ERICO','Eritech', 'UN',   95.00,  155.00,'IVA12'),
 ('TF-EL-0002','Placa de cobre para tierra 30 x 30 cm',        'nVent ERICO','Eritech', 'UN',  640.00, 1045.00,'IVA12'),
 ('TF-CN-0001','Carga de soldadura exotérmica #90',            'nVent ERICO','Cadweld', 'UN',   68.00,  112.00,'IVA12'),
 ('TF-CN-0002','Molde de grafito cable-varilla',               'nVent ERICO','Cadweld', 'UN',  890.00, 1450.00,'IVA12'),
 ('TF-CN-0003','Conector mecánico varilla-cable 5/8"',         'Genérico','General',    'UN',   15.00,   24.50,'IVA12'),
 ('TF-ME-0001','Telurómetro digital 1623-2',                   'Fluke','GEO',           'UN',18500.00,29500.00,'EXE'),
 ('TF-ME-0002','Pinza de medición de tierra 1630-2',           'Fluke','GEO',           'UN', 9800.00,15900.00,'IVA12')
) AS v(codigo, descripcion, marca, linea, um, costo, precio, iva)
INNER JOIN Marca        ma ON ma.nombre = v.marca
INNER JOIN Linea        li ON li.id_marca = ma.id_marca AND li.nombre = v.linea
INNER JOIN Categoria    ca ON ca.codigo = LEFT(v.codigo, 2)
INNER JOIN Subcategoria sc ON sc.id_categoria = ca.id_categoria
                          AND sc.codigo = SUBSTRING(v.codigo, 4, 2)
-- Solo los productos de Tierra Física definen sus propias cuentas:
LEFT JOIN Cuenta_Contable ci ON LEFT(v.codigo, 2) = 'TF' AND ci.codigo = '1.1.03.04'
LEFT JOIN Cuenta_Contable cv ON LEFT(v.codigo, 2) = 'TF' AND cv.codigo = '4.1.01.04'
LEFT JOIN Cuenta_Contable cc ON LEFT(v.codigo, 2) = 'TF' AND cc.codigo = '5.1.01.04';

-- 19. INVENTARIO INICIAL en los 5 sitios
--     Cables -> Bodega de Cables (carretes); lo demás -> Bodega General
WITH loc AS (
    SELECT l.id_localizacion, b.id_sitio, b.tipo_bodega,
           ROW_NUMBER() OVER (PARTITION BY b.id_bodega ORDER BY l.codigo) AS nro
    FROM Localizacion l
    INNER JOIN Bodega b ON b.id_bodega = l.id_bodega
    WHERE b.tipo_bodega IN ('General', 'Cables y Conductores')
),
prod AS (
    SELECT p.id_producto, p.codigo_um, p.precio_unitario,
           CASE WHEN c.codigo = 'CO' THEN 'Cables y Conductores' ELSE 'General' END AS tipo_bodega,
           ROW_NUMBER() OVER (
               PARTITION BY CASE WHEN c.codigo = 'CO' THEN 1 ELSE 0 END
               ORDER BY p.codigo) AS nro
    FROM Producto p
    INNER JOIN Subcategoria s ON s.id_subcategoria = p.id_subcategoria
    INNER JOIN Categoria    c ON c.id_categoria    = s.id_categoria
)
INSERT INTO Inventario (id_producto, id_localizacion, cantidad)
SELECT pr.id_producto, lo.id_localizacion,
       CASE WHEN pr.precio_unitario >= 5000
                 THEN 1   + ABS(CHECKSUM(pr.id_producto, lo.id_sitio)) % 4
            WHEN pr.codigo_um = 'MT'
                 THEN 300 + ABS(CHECKSUM(pr.id_producto, lo.id_sitio)) % 2700
            ELSE      5   + ABS(CHECKSUM(pr.id_producto, lo.id_sitio)) % 195
       END
FROM prod pr
INNER JOIN loc lo ON lo.tipo_bodega = pr.tipo_bodega
                 AND lo.nro = ((pr.nro - 1) % 12) + 1;

-- 20. KARDEX: registrar la carga inicial como primer movimiento
INSERT INTO Movimiento_Inventario (id_producto, id_localizacion, tipo_movimiento,
                                   cantidad, costo_unitario, saldo_resultante,
                                   documento_tipo, justificacion)
SELECT i.id_producto, i.id_localizacion, 'Inventario Inicial',
       i.cantidad, p.costo_unitario, i.cantidad,
       'CARGA', 'Carga inicial de inventario al implementar el sistema'
FROM Inventario i
INNER JOIN Producto p ON p.id_producto = i.id_producto;
GO

-- =====================================================
-- VERIFICACION
-- =====================================================

-- a) PRUEBA DEL TRIGGER: intentar guardar un producto de Tierra Física SIN cuentas
BEGIN TRY
    INSERT INTO Producto (codigo, descripcion, id_linea, id_subcategoria,
                          codigo_um, costo_unitario, precio_unitario)
    SELECT 'TF-EL-9999', 'Producto de prueba SIN cuenta contable',
           l.id_linea, s.id_subcategoria, 'UN', 10, 20
    FROM Linea l
    CROSS JOIN Subcategoria s
    INNER JOIN Categoria c ON c.id_categoria = s.id_categoria
    WHERE l.nombre = 'General' AND c.codigo = 'TF' AND s.codigo = 'EL';

    SELECT 'Prueba del trigger' AS Prueba, 'ERROR: el producto se guardó' AS Resultado;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SELECT 'Prueba del trigger' AS Prueba,
           'RECHAZADO correctamente: ' + ERROR_MESSAGE() AS Resultado;
END CATCH;

-- b) Conteo de registros
SELECT 'Impuesto' AS Tabla, COUNT(*) AS Registros FROM Impuesto              UNION ALL
SELECT 'Unidad_Medida',     COUNT(*)              FROM Unidad_Medida         UNION ALL
SELECT 'Marca',             COUNT(*)              FROM Marca                 UNION ALL
SELECT 'Linea',             COUNT(*)              FROM Linea                 UNION ALL
SELECT 'Categoria',         COUNT(*)              FROM Categoria             UNION ALL
SELECT 'Subcategoria',      COUNT(*)              FROM Subcategoria          UNION ALL
SELECT 'Producto',          COUNT(*)              FROM Producto              UNION ALL
SELECT 'Inventario',        COUNT(*)              FROM Inventario            UNION ALL
SELECT 'Movimiento_Inventario', COUNT(*)          FROM Movimiento_Inventario;

-- c) La regla contable funcionando (vista)
SELECT codigo, descripcion, categoria, origen_cuenta,
       cuenta_inventario, cuenta_venta, cuenta_costo
FROM vw_Producto_Cuenta
WHERE codigo IN ('CO-BC-0001', 'MA-PV-0002', 'AE-PR-0003', 'TF-EL-0001', 'TF-ME-0001');

-- d) Catálogo completo de productos
SELECT p.codigo, p.descripcion,
       ma.nombre AS marca, li.nombre AS linea,
       c.nombre  AS categoria, s.nombre AS subcategoria,
       p.codigo_um AS um, p.costo_unitario, p.precio_unitario,
       p.codigo_iva, i.porcentaje AS iva_pct
FROM Producto p
INNER JOIN Linea        li ON li.id_linea        = p.id_linea
INNER JOIN Marca        ma ON ma.id_marca        = li.id_marca
INNER JOIN Subcategoria s  ON s.id_subcategoria  = p.id_subcategoria
INNER JOIN Categoria    c  ON c.id_categoria     = s.id_categoria
INNER JOIN Impuesto     i  ON i.codigo_iva       = p.codigo_iva
ORDER BY p.codigo;