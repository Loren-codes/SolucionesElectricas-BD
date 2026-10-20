-- =====================================================
-- Script 02: Tablas de Empresa y Ubicaciones (Grupo A)
-- Departamento, Municipio, Empresa, Empresa_Telefono,
-- Sitio, Bodega, Localizacion
-- =====================================================
USE SolucionesElectricas;
GO

-- -----------------------------------------------------
-- 0. LIMPIEZA: borrar tablas si ya existen
--    (orden inverso: primero hijos, luego papás)
-- -----------------------------------------------------
DROP TABLE IF EXISTS Localizacion;
DROP TABLE IF EXISTS Bodega;
DROP TABLE IF EXISTS Sitio;
DROP TABLE IF EXISTS Empresa_Telefono;
DROP TABLE IF EXISTS Empresa;
DROP TABLE IF EXISTS Municipio;
DROP TABLE IF EXISTS Departamento;
GO

-- -----------------------------------------------------
-- 1. DEPARTAMENTO (22 departamentos de Guatemala)
-- -----------------------------------------------------
CREATE TABLE Departamento (
    id_departamento INT IDENTITY(1,1) PRIMARY KEY,
    codigo_ine      CHAR(2)     NOT NULL UNIQUE,    -- Código oficial INE: 01 = Guatemala
    nombre          VARCHAR(50) NOT NULL UNIQUE,
    region          VARCHAR(30) NOT NULL,            -- Metropolitana, Central, Norte...
    CONSTRAINT CK_Departamento_Codigo CHECK (codigo_ine LIKE '[0-9][0-9]')
);

-- -----------------------------------------------------
-- 2. MUNICIPIO
-- -----------------------------------------------------
CREATE TABLE Municipio (
    id_municipio    INT IDENTITY(1,1) PRIMARY KEY,
    codigo_ine      CHAR(4)     NOT NULL UNIQUE,    -- 0101 = Guatemala, 0108 = Mixco
    nombre          VARCHAR(60) NOT NULL,
    id_departamento INT         NOT NULL,
    CONSTRAINT FK_Municipio_Departamento
        FOREIGN KEY (id_departamento) REFERENCES Departamento(id_departamento),
    CONSTRAINT UQ_Municipio_Nombre UNIQUE (id_departamento, nombre),
    CONSTRAINT CK_Municipio_Codigo CHECK (codigo_ine LIKE '[0-9][0-9][0-9][0-9]')
);

-- -----------------------------------------------------
-- 3. EMPRESA
-- -----------------------------------------------------
CREATE TABLE Empresa (
    id_empresa          INT IDENTITY(1,1) PRIMARY KEY,
    nit                 VARCHAR(15)  NOT NULL UNIQUE,
    razon_social        VARCHAR(150) NOT NULL,          -- Nombre legal ante la SAT
    nombre_comercial    VARCHAR(100) NOT NULL,          -- Nombre que ve el público
    regimen_iva         VARCHAR(30)  NOT NULL DEFAULT 'General',
    direccion           VARCHAR(150) NOT NULL,          -- Calle, avenida, número
    zona                TINYINT      NULL,
    id_municipio        INT          NOT NULL,
    codigo_postal       CHAR(5)      NULL,
    correo              VARCHAR(100) NOT NULL,
    sitio_web           VARCHAR(100) NULL,
    industria           VARCHAR(100) NOT NULL DEFAULT 'Distribución de materiales eléctricos',
    representante_legal VARCHAR(100) NOT NULL,
    fecha_fundacion     DATE         NULL,
    logo_url            VARCHAR(255) NULL,              -- Ruta de la imagen del logo
    moneda_base         CHAR(3)      NOT NULL DEFAULT 'GTQ',
    activo              BIT          NOT NULL DEFAULT 1,
    usuario_creador     VARCHAR(50)  NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion      DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Empresa_Municipio
        FOREIGN KEY (id_municipio) REFERENCES Municipio(id_municipio),
    CONSTRAINT CK_Empresa_NIT     CHECK (nit NOT LIKE '%[^0-9K-]%'),
    CONSTRAINT CK_Empresa_Correo  CHECK (correo LIKE '%_@_%._%'),
    CONSTRAINT CK_Empresa_Zona    CHECK (zona BETWEEN 1 AND 25),
    CONSTRAINT CK_Empresa_Regimen CHECK (regimen_iva IN ('General', 'Pequeño Contribuyente'))
);

-- -----------------------------------------------------
-- 4. EMPRESA_TELEFONO (atributo multivaluado)
-- -----------------------------------------------------
CREATE TABLE Empresa_Telefono (
    id_telefono  INT IDENTITY(1,1) PRIMARY KEY,
    id_empresa   INT         NOT NULL,
    tipo         VARCHAR(20) NOT NULL,
    numero       VARCHAR(20) NOT NULL,
    extension    VARCHAR(6)  NULL,
    es_principal BIT         NOT NULL DEFAULT 0,
    CONSTRAINT FK_Telefono_Empresa
        FOREIGN KEY (id_empresa) REFERENCES Empresa(id_empresa),
    CONSTRAINT CK_Telefono_Tipo
        CHECK (tipo IN ('PBX', 'WhatsApp', 'Fijo', 'Celular', 'Fax')),
    CONSTRAINT UQ_Telefono UNIQUE (id_empresa, numero)
);

-- -----------------------------------------------------
-- 5. SITIO (las 5 sucursales)
-- -----------------------------------------------------
CREATE TABLE Sitio (
    id_sitio        INT IDENTITY(1,1) PRIMARY KEY,
    id_empresa      INT          NOT NULL,
    codigo          VARCHAR(10)  NOT NULL UNIQUE,      -- S01, S02...
    nombre          VARCHAR(80)  NOT NULL,
    tipo_sitio      VARCHAR(30)  NOT NULL DEFAULT 'Sucursal',
    direccion       VARCHAR(150) NOT NULL,
    zona            TINYINT      NULL,
    id_municipio    INT          NOT NULL,
    telefono        VARCHAR(20)  NULL,
    correo          VARCHAR(100) NULL,
    encargado       VARCHAR(100) NULL,
    hora_apertura   TIME(0)      NOT NULL DEFAULT '08:00',
    hora_cierre     TIME(0)      NOT NULL DEFAULT '18:00',
    latitud         DECIMAL(9,6) NULL,                 -- Coordenadas GPS
    longitud        DECIMAL(9,6) NULL,
    fecha_apertura  DATE         NULL,
    activo          BIT          NOT NULL DEFAULT 1,
    usuario_creador VARCHAR(50)  NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion  DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Sitio_Empresa
        FOREIGN KEY (id_empresa) REFERENCES Empresa(id_empresa),
    CONSTRAINT FK_Sitio_Municipio
        FOREIGN KEY (id_municipio) REFERENCES Municipio(id_municipio),
    CONSTRAINT CK_Sitio_Tipo
        CHECK (tipo_sitio IN ('Casa Matriz', 'Sucursal', 'Centro de Distribución')),
    CONSTRAINT CK_Sitio_Horario CHECK (hora_cierre > hora_apertura),
    CONSTRAINT CK_Sitio_Latitud  CHECK (latitud  BETWEEN -90  AND 90),
    CONSTRAINT CK_Sitio_Longitud CHECK (longitud BETWEEN -180 AND 180),
    CONSTRAINT CK_Sitio_Correo   CHECK (correo LIKE '%_@_%._%'),
    CONSTRAINT CK_Sitio_Zona     CHECK (zona BETWEEN 1 AND 25)
);

-- -----------------------------------------------------
-- 6. BODEGA (entidad débil: depende del sitio)
-- -----------------------------------------------------
CREATE TABLE Bodega (
    id_bodega       INT IDENTITY(1,1) PRIMARY KEY,
    id_sitio        INT          NOT NULL,
    codigo          VARCHAR(10)  NOT NULL,             -- B01, B02...
    nombre          VARCHAR(80)  NOT NULL,
    tipo_bodega     VARCHAR(30)  NOT NULL DEFAULT 'General',
    area_m2         DECIMAL(8,2) NULL,
    responsable     VARCHAR(100) NULL,
    activo          BIT          NOT NULL DEFAULT 1,
    usuario_creador VARCHAR(50)  NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion  DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Bodega_Sitio
        FOREIGN KEY (id_sitio) REFERENCES Sitio(id_sitio),
    CONSTRAINT UQ_Bodega_Codigo UNIQUE (id_sitio, codigo),
    CONSTRAINT CK_Bodega_Tipo CHECK (tipo_bodega IN
        ('General', 'Cables y Conductores', 'Materiales Peligrosos', 'Devoluciones', 'Tránsito')),
    CONSTRAINT CK_Bodega_Area CHECK (area_m2 > 0)
);

-- -----------------------------------------------------
-- 7. LOCALIZACION (entidad débil: depende de la bodega)
-- -----------------------------------------------------
CREATE TABLE Localizacion (
    id_localizacion INT IDENTITY(1,1) PRIMARY KEY,
    id_bodega       INT           NOT NULL,
    pasillo         TINYINT       NOT NULL,
    estante         TINYINT       NOT NULL,
    nivel           TINYINT       NOT NULL,
    -- Código calculado automáticamente (atributo DERIVADO): P01-E02-N03
    codigo AS ('P'  + RIGHT('0' + CAST(pasillo AS VARCHAR(2)), 2) +
               '-E' + RIGHT('0' + CAST(estante AS VARCHAR(2)), 2) +
               '-N' + RIGHT('0' + CAST(nivel   AS VARCHAR(2)), 2)) PERSISTED,
    tipo_ubicacion  VARCHAR(20)   NOT NULL DEFAULT 'Rack',
    capacidad_max   DECIMAL(10,2) NULL,
    descripcion     VARCHAR(100)  NULL,
    activo          BIT           NOT NULL DEFAULT 1,
    usuario_creador VARCHAR(50)   NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion  DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Localizacion_Bodega
        FOREIGN KEY (id_bodega) REFERENCES Bodega(id_bodega),
    CONSTRAINT UQ_Localizacion UNIQUE (id_bodega, pasillo, estante, nivel),
    CONSTRAINT CK_Localizacion_Rango CHECK (pasillo BETWEEN 1 AND 99
                                        AND estante BETWEEN 1 AND 99
                                        AND nivel   BETWEEN 1 AND 99),
    CONSTRAINT CK_Localizacion_Tipo CHECK (tipo_ubicacion IN
        ('Rack', 'Piso', 'Carrete', 'Estantería', 'Jaula'))
);
GO
