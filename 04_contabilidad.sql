-- =====================================================
-- Script 04: Monedas y Catálogo Contable (Grupo C)
-- Moneda, Tipo_Cambio, Cuenta_Contable
-- =====================================================
USE SolucionesElectricas;
GO

-- -----------------------------------------------------
-- 0. LIMPIEZA (permite volver a ejecutar el script)
-- -----------------------------------------------------
ALTER TABLE Empresa DROP CONSTRAINT IF EXISTS FK_Empresa_Moneda;
DROP TABLE IF EXISTS Tipo_Cambio;
DROP TABLE IF EXISTS Moneda;
DROP TABLE IF EXISTS Cuenta_Contable;
GO

-- -----------------------------------------------------
-- 1. MONEDA (llave primaria natural: código ISO)
-- -----------------------------------------------------
CREATE TABLE Moneda (
    codigo    CHAR(3)     PRIMARY KEY,           -- GTQ, USD, EUR
    nombre    VARCHAR(50) NOT NULL UNIQUE,
    simbolo   VARCHAR(5)  NOT NULL,
    decimales TINYINT     NOT NULL DEFAULT 2,
    es_local  BIT         NOT NULL DEFAULT 0,    -- 1 = moneda del país
    activo    BIT         NOT NULL DEFAULT 1,
    CONSTRAINT CK_Moneda_Codigo CHECK (codigo LIKE '[A-Z][A-Z][A-Z]')
);

-- -----------------------------------------------------
-- 2. TIPO_CAMBIO (historial diario)
-- -----------------------------------------------------
CREATE TABLE Tipo_Cambio (
    id_tipo_cambio  INT IDENTITY(1,1) PRIMARY KEY,
    codigo_moneda   CHAR(3)       NOT NULL,
    fecha           DATE          NOT NULL,
    tasa            DECIMAL(12,6) NOT NULL,      -- Quetzales por 1 unidad
    fuente          VARCHAR(50)   NOT NULL DEFAULT 'Banco de Guatemala',
    usuario_creador VARCHAR(50)   NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion  DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_TipoCambio_Moneda
        FOREIGN KEY (codigo_moneda) REFERENCES Moneda(codigo),
    CONSTRAINT UQ_TipoCambio UNIQUE (codigo_moneda, fecha),
    CONSTRAINT CK_TipoCambio_Tasa CHECK (tasa > 0)
);

-- -----------------------------------------------------
-- 3. CUENTA_CONTABLE (catálogo en forma de árbol)
-- -----------------------------------------------------
CREATE TABLE Cuenta_Contable (
    id_cuenta         INT IDENTITY(1,1) PRIMARY KEY,
    codigo            VARCHAR(20)  NOT NULL UNIQUE,   -- 1.1.01.01
    nombre            VARCHAR(100) NOT NULL,
    tipo              VARCHAR(20)  NOT NULL,          -- Activo, Pasivo...
    naturaleza        CHAR(1)      NOT NULL,          -- D = Deudora, A = Acreedora
    -- Atributo DERIVADO: Balance o Resultados según el tipo
    clasificacion AS (CASE WHEN tipo IN ('Activo', 'Pasivo', 'Patrimonio')
                           THEN 'Balance' ELSE 'Resultados' END) PERSISTED,
    -- Atributo DERIVADO: nivel = cantidad de puntos + 1
    nivel AS (CAST(LEN(codigo) - LEN(REPLACE(codigo, '.', '')) + 1 AS TINYINT)) PERSISTED,
    id_cuenta_padre   INT          NULL,              -- Relación recursiva
    acepta_movimiento BIT          NOT NULL DEFAULT 0,
    activo            BIT          NOT NULL DEFAULT 1,
    usuario_creador   VARCHAR(50)  NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion    DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Cuenta_Padre
        FOREIGN KEY (id_cuenta_padre) REFERENCES Cuenta_Contable(id_cuenta),
    CONSTRAINT CK_Cuenta_Codigo     CHECK (codigo NOT LIKE '%[^0-9.]%'),
    CONSTRAINT CK_Cuenta_Tipo       CHECK (tipo IN
        ('Activo', 'Pasivo', 'Patrimonio', 'Ingreso', 'Costo', 'Gasto')),
    CONSTRAINT CK_Cuenta_Naturaleza CHECK (naturaleza IN ('D', 'A')),
    CONSTRAINT CK_Cuenta_NoAutoPadre CHECK (id_cuenta_padre <> id_cuenta)
);
GO

-- -----------------------------------------------------
-- 4. DATOS: MONEDAS
-- -----------------------------------------------------
INSERT INTO Moneda (codigo, nombre, simbolo, decimales, es_local) VALUES
('GTQ', 'Quetzal',              'Q',  2, 1),
('USD', 'Dólar estadounidense', '$',  2, 0),
('EUR', 'Euro',                 '€',  2, 0);

-- -----------------------------------------------------
-- 5. ALTER TABLE: conectar Empresa con Moneda
-- -----------------------------------------------------
ALTER TABLE Empresa
    ADD CONSTRAINT FK_Empresa_Moneda
    FOREIGN KEY (moneda_base) REFERENCES Moneda(codigo);

-- -----------------------------------------------------
-- 6. DATOS: TIPO DE CAMBIO (valores ilustrativos)
-- -----------------------------------------------------
INSERT INTO Tipo_Cambio (codigo_moneda, fecha, tasa) VALUES
('USD', '2026-09-28', 7.68250), ('EUR', '2026-09-28', 8.95410),
('USD', '2026-09-29', 7.68010), ('EUR', '2026-09-29', 8.96120),
('USD', '2026-09-30', 7.67890), ('EUR', '2026-09-30', 8.94870),
('USD', '2026-10-01', 7.68120), ('EUR', '2026-10-01', 8.95530),
('USD', '2026-10-02', 7.67950), ('EUR', '2026-10-02', 8.95060);

-- -----------------------------------------------------
-- 7. DATOS: CATÁLOGO DE CUENTAS
--    El tipo y la naturaleza se deducen del 1er dígito
-- -----------------------------------------------------
INSERT INTO Cuenta_Contable (codigo, nombre, tipo, naturaleza)
SELECT v.codigo, v.nombre,
       CASE LEFT(v.codigo, 1)
            WHEN '1' THEN 'Activo'
            WHEN '2' THEN 'Pasivo'
            WHEN '3' THEN 'Patrimonio'
            WHEN '4' THEN 'Ingreso'
            WHEN '5' THEN 'Costo'
            ELSE          'Gasto'
       END,
       CASE WHEN LEFT(v.codigo, 1) IN ('1', '5', '6') THEN 'D' ELSE 'A' END
FROM (VALUES
    -- ===== 1 ACTIVO =====
    ('1',         'ACTIVO'),
    ('1.1',       'Activo Corriente'),
    ('1.1.01',    'Efectivo y Equivalentes'),
    ('1.1.01.01', 'Caja General'),
    ('1.1.01.02', 'Caja Chica'),
    ('1.1.01.03', 'Bancos - Banco Industrial'),
    ('1.1.01.04', 'Bancos - Banrural'),
    ('1.1.02',    'Cuentas por Cobrar'),
    ('1.1.02.01', 'Clientes'),
    ('1.1.02.02', 'Estimación para Cuentas Incobrables'),
    ('1.1.03',    'Inventarios'),
    ('1.1.03.01', 'Inventario de Conductores'),
    ('1.1.03.02', 'Inventario de Materiales Aislantes'),
    ('1.1.03.03', 'Inventario de Accesorios para Instalaciones Eléctricas'),
    ('1.1.03.04', 'Inventario de Accesorios para Tierra Física'),
    ('1.1.04',    'Impuestos por Cobrar'),
    ('1.1.04.01', 'IVA por Cobrar (Crédito Fiscal)'),
    ('1.2',       'Activo No Corriente'),
    ('1.2.01',    'Propiedad, Planta y Equipo'),
    ('1.2.01.01', 'Mobiliario y Equipo'),
    ('1.2.01.02', 'Vehículos'),
    ('1.2.01.03', 'Depreciación Acumulada'),
    -- ===== 2 PASIVO =====
    ('2',         'PASIVO'),
    ('2.1',       'Pasivo Corriente'),
    ('2.1.01',    'Proveedores'),
    ('2.1.01.01', 'Proveedores Locales'),
    ('2.1.02',    'Impuestos por Pagar'),
    ('2.1.02.01', 'IVA por Pagar (Débito Fiscal)'),
    ('2.1.02.02', 'ISR por Pagar'),
    ('2.1.03',    'Anticipos de Clientes'),
    ('2.1.03.01', 'Anticipos Recibidos de Clientes'),
    -- ===== 3 PATRIMONIO =====
    ('3',         'PATRIMONIO'),
    ('3.1',       'Capital'),
    ('3.1.01',    'Capital Social'),
    ('3.1.01.01', 'Capital Pagado'),
    ('3.2',       'Resultados Acumulados'),
    ('3.2.01',    'Utilidades Retenidas'),
    ('3.2.01.01', 'Utilidades de Ejercicios Anteriores'),
    -- ===== 4 INGRESOS =====
    ('4',         'INGRESOS'),
    ('4.1',       'Ingresos de Operación'),
    ('4.1.01',    'Ventas'),
    ('4.1.01.01', 'Ventas de Conductores'),
    ('4.1.01.02', 'Ventas de Materiales Aislantes'),
    ('4.1.01.03', 'Ventas de Accesorios para Instalaciones Eléctricas'),
    ('4.1.01.04', 'Ventas de Accesorios para Tierra Física'),
    ('4.1.02',    'Rebajas sobre Ventas'),
    ('4.1.02.01', 'Descuentos sobre Ventas'),
    ('4.1.02.02', 'Devoluciones sobre Ventas'),
    -- ===== 5 COSTOS =====
    ('5',         'COSTOS'),
    ('5.1',       'Costo de Ventas'),
    ('5.1.01',    'Costo de Mercadería Vendida'),
    ('5.1.01.01', 'Costo de Conductores'),
    ('5.1.01.02', 'Costo de Materiales Aislantes'),
    ('5.1.01.03', 'Costo de Accesorios para Instalaciones Eléctricas'),
    ('5.1.01.04', 'Costo de Accesorios para Tierra Física'),
    -- ===== 6 GASTOS =====
    ('6',         'GASTOS'),
    ('6.1',       'Gastos de Operación'),
    ('6.1.01',    'Gastos de Venta'),
    ('6.1.01.01', 'Comisiones sobre Ventas'),
    ('6.1.01.02', 'Fletes y Despachos'),
    ('6.1.02',    'Gastos de Administración'),
    ('6.1.02.01', 'Sueldos y Salarios'),
    ('6.1.02.02', 'Energía Eléctrica'),
    ('6.1.02.03', 'Diferencial Cambiario')
) AS v(codigo, nombre);

-- -----------------------------------------------------
-- 8. UPDATE: conectar cada cuenta con su cuenta padre
--    (el padre es el código sin su último segmento)
-- -----------------------------------------------------
UPDATE hijo
SET    hijo.id_cuenta_padre = padre.id_cuenta
FROM   Cuenta_Contable hijo
INNER JOIN Cuenta_Contable padre
       ON padre.codigo = LEFT(hijo.codigo,
                              LEN(hijo.codigo) - CHARINDEX('.', REVERSE(hijo.codigo)))
WHERE  hijo.codigo LIKE '%.%';

-- -----------------------------------------------------
-- 9. UPDATE: solo las cuentas de nivel 4 reciben movimientos
-- -----------------------------------------------------
UPDATE Cuenta_Contable
SET    acepta_movimiento = 1
WHERE  nivel = 4;

-- -----------------------------------------------------
-- 10. UPDATE: cuentas "correctoras" (naturaleza contraria)
-- -----------------------------------------------------
UPDATE Cuenta_Contable SET naturaleza = 'A'
WHERE  codigo IN ('1.1.02.02', '1.2.01.03');   -- Estimación y Depreciación

UPDATE Cuenta_Contable SET naturaleza = 'D'
WHERE  codigo IN ('4.1.02.01', '4.1.02.02');   -- Descuentos y Devoluciones
GO

-- -----------------------------------------------------
-- 11. VERIFICACION
-- -----------------------------------------------------
-- a) Conteo de registros
SELECT 'Moneda' AS Tabla, COUNT(*) AS Registros FROM Moneda UNION ALL
SELECT 'Tipo_Cambio',      COUNT(*)              FROM Tipo_Cambio UNION ALL
SELECT 'Cuenta_Contable',  COUNT(*)              FROM Cuenta_Contable;

-- b) Cuentas de Balance vs Resultados (GROUP BY)
SELECT clasificacion,
       COUNT(*)                                          AS Total_Cuentas,
       SUM(CASE WHEN acepta_movimiento = 1 THEN 1 ELSE 0 END) AS De_Movimiento
FROM   Cuenta_Contable
GROUP BY clasificacion;

-- c) El catálogo dibujado como árbol
SELECT REPLICATE('      ', nivel - 1) + codigo + '  ' + nombre AS Catalogo_Contable,
       tipo, clasificacion, naturaleza, nivel,
       CASE acepta_movimiento WHEN 1 THEN 'Sí' ELSE 'No' END AS Movimiento,
       (SELECT p.codigo FROM Cuenta_Contable p
        WHERE  p.id_cuenta = c.id_cuenta_padre)               AS Cuenta_Padre
FROM   Cuenta_Contable c
ORDER BY codigo;
