-- =====================================================
-- Script 06: Usuarios, Vendedores y Clientes (Grupo D)
-- =====================================================
USE SolucionesElectricas;
GO

-- -----------------------------------------------------
-- 0. LIMPIEZA
-- -----------------------------------------------------
DROP TABLE IF EXISTS Cliente;
DROP TABLE IF EXISTS Vendedor;
DROP TABLE IF EXISTS Usuario;
GO

-- -----------------------------------------------------
-- 1. USUARIO (quién usa el sistema)
-- -----------------------------------------------------
CREATE TABLE Usuario (
    id_usuario      INT IDENTITY(1,1) PRIMARY KEY,
    username        VARCHAR(30)    NOT NULL UNIQUE,
    nombre_completo VARCHAR(100)   NOT NULL,
    correo          VARCHAR(100)   NOT NULL UNIQUE,
    rol             VARCHAR(20)    NOT NULL,
    id_sitio        INT            NOT NULL,          -- dónde trabaja
    password_hash   VARBINARY(32)  NOT NULL,          -- contraseña cifrada
    ultimo_acceso   DATETIME2(0)   NULL,
    activo          BIT            NOT NULL DEFAULT 1,
    usuario_creador VARCHAR(50)    NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion  DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Usuario_Sitio FOREIGN KEY (id_sitio) REFERENCES Sitio(id_sitio),
    CONSTRAINT CK_Usuario_Rol CHECK (rol IN
        ('Administrador', 'Gerente', 'Vendedor', 'Cajero', 'Bodeguero', 'Contador')),
    CONSTRAINT CK_Usuario_Correo CHECK (correo LIKE '%_@_%._%')
);

-- -----------------------------------------------------
-- 2. VENDEDOR (relación 1:1 con Usuario)
-- -----------------------------------------------------
CREATE TABLE Vendedor (
    id_vendedor         INT IDENTITY(1,1) PRIMARY KEY,
    codigo              VARCHAR(10)   NOT NULL UNIQUE,     -- V001
    id_usuario          INT           NOT NULL UNIQUE,     -- UNIQUE = 1:1
    id_sitio            INT           NOT NULL,
    porcentaje_comision DECIMAL(5,2)  NOT NULL DEFAULT 2.00,
    meta_mensual        DECIMAL(12,2) NOT NULL DEFAULT 0,
    fecha_ingreso       DATE          NOT NULL,
    activo              BIT           NOT NULL DEFAULT 1,
    usuario_creador     VARCHAR(50)   NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion      DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Vendedor_Usuario FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario),
    CONSTRAINT FK_Vendedor_Sitio   FOREIGN KEY (id_sitio)   REFERENCES Sitio(id_sitio),
    CONSTRAINT CK_Vendedor_Codigo   CHECK (codigo LIKE 'V[0-9][0-9][0-9]'),
    CONSTRAINT CK_Vendedor_Comision CHECK (porcentaje_comision BETWEEN 0 AND 20),
    CONSTRAINT CK_Vendedor_Meta     CHECK (meta_mensual >= 0)
);

-- -----------------------------------------------------
-- 3. CLIENTE
-- -----------------------------------------------------
CREATE TABLE Cliente (
    id_cliente         INT IDENTITY(1,1) PRIMARY KEY,
    codigo             VARCHAR(10)   NOT NULL UNIQUE,      -- C0001
    nit                VARCHAR(15)   NOT NULL,             -- 'CF' = consumidor final
    nombre_comercial   VARCHAR(150)  NOT NULL,
    razon_social       VARCHAR(150)  NULL,
    tipo_cliente       VARCHAR(20)   NOT NULL DEFAULT 'Empresa',
    -- Dirección completa (atributo compuesto)
    direccion          VARCHAR(150)  NOT NULL,
    zona               TINYINT       NULL,
    id_municipio       INT           NOT NULL,
    telefono           VARCHAR(20)   NULL,
    correo             VARCHAR(100)  NULL,
    -- Contacto principal (atributo compuesto)
    contacto_nombre    VARCHAR(100)  NOT NULL,
    contacto_telefono  VARCHAR(20)   NULL,
    contacto_correo    VARCHAR(100)  NULL,
    -- Contabilidad y ventas
    id_cuenta_contable INT           NOT NULL,             -- cuenta asociada
    id_vendedor        INT           NOT NULL,             -- vendedor que lo consiguió
    limite_credito     DECIMAL(12,2) NOT NULL DEFAULT 0,
    dias_credito       TINYINT       NOT NULL DEFAULT 0,
    activo             BIT           NOT NULL DEFAULT 1,
    usuario_creador    VARCHAR(50)   NOT NULL DEFAULT SUSER_SNAME(),
    fecha_creacion     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Cliente_Municipio FOREIGN KEY (id_municipio)       REFERENCES Municipio(id_municipio),
    CONSTRAINT FK_Cliente_Cuenta    FOREIGN KEY (id_cuenta_contable) REFERENCES Cuenta_Contable(id_cuenta),
    CONSTRAINT FK_Cliente_Vendedor  FOREIGN KEY (id_vendedor)        REFERENCES Vendedor(id_vendedor),
    -- Prepara la regla "un vendedor solo vende a SUS clientes":
    CONSTRAINT UQ_Cliente_Vendedor UNIQUE (id_cliente, id_vendedor),
    CONSTRAINT CK_Cliente_Codigo  CHECK (codigo LIKE 'C[0-9][0-9][0-9][0-9]'),
    CONSTRAINT CK_Cliente_NIT     CHECK (nit = 'CF' OR nit NOT LIKE '%[^0-9K-]%'),
    CONSTRAINT CK_Cliente_Tipo    CHECK (tipo_cliente IN
        ('Empresa', 'Contratista', 'Persona Individual', 'Gobierno')),
    CONSTRAINT CK_Cliente_Zona    CHECK (zona BETWEEN 1 AND 25),
    CONSTRAINT CK_Cliente_Correo  CHECK (correo LIKE '%_@_%._%'),
    CONSTRAINT CK_Cliente_Credito CHECK (limite_credito >= 0 AND dias_credito BETWEEN 0 AND 90),
    -- Regla: consumidor final (CF) no tiene crédito
    CONSTRAINT CK_Cliente_CF_SinCredito CHECK (nit <> 'CF' OR limite_credito = 0)
);

-- Índice único FILTRADO: el NIT no se repite, excepto 'CF'
CREATE UNIQUE INDEX UX_Cliente_NIT ON Cliente(nit) WHERE nit <> 'CF';
GO

-- =====================================================
-- DATOS
-- =====================================================

-- 4. USUARIOS (contraseña de prueba cifrada con SHA-256)
INSERT INTO Usuario (username, nombre_completo, correo, rol, id_sitio, password_hash)
SELECT v.username, v.nombre, v.correo, v.rol, s.id_sitio,
       HASHBYTES('SHA2_256', 'Clave2026!')
FROM (VALUES
    ('admin',      'Administrador del Sistema', 'admin@solucioneselectricas.com.gt',      'Administrador', 'S01'),
    ('rcastillo',  'Roberto Castillo Morales',  'rcastillo@solucioneselectricas.com.gt',  'Gerente',       'S01'),
    ('cmendez',    'Carlos Méndez',             'cmendez@solucioneselectricas.com.gt',    'Vendedor',      'S01'),
    ('slopez',     'Sofía López Herrera',       'slopez@solucioneselectricas.com.gt',     'Vendedor',      'S01'),
    ('aperez',     'Ana Lucía Pérez',           'aperez@solucioneselectricas.com.gt',     'Vendedor',      'S02'),
    ('jramirez',   'Jorge Ramírez',             'jramirez@solucioneselectricas.com.gt',   'Vendedor',      'S03'),
    ('mjlopez',    'María José López',          'mjlopez@solucioneselectricas.com.gt',    'Vendedor',      'S04'),
    ('lgarcia',    'Luis Fernando García',      'lgarcia@solucioneselectricas.com.gt',    'Vendedor',      'S05'),
    ('krodriguez', 'Karla Rodríguez',           'krodriguez@solucioneselectricas.com.gt', 'Cajero',        'S01'),
    ('dmorales',   'Diego Morales',             'dmorales@solucioneselectricas.com.gt',   'Cajero',        'S02'),
    ('pxicara',    'Pedro Xicará',              'pxicara@solucioneselectricas.com.gt',    'Bodeguero',     'S01'),
    ('echavez',    'Elena Chávez',              'echavez@solucioneselectricas.com.gt',    'Contador',      'S01')
) AS v(username, nombre, correo, rol, sitio)
INNER JOIN Sitio s ON s.codigo = v.sitio;

-- 5. VENDEDORES (cada uno ligado a su usuario)
INSERT INTO Vendedor (codigo, id_usuario, id_sitio, porcentaje_comision,
                      meta_mensual, fecha_ingreso)
SELECT v.codigo, u.id_usuario, u.id_sitio, v.comision, v.meta, v.ingreso
FROM (VALUES
    ('V001', 'cmendez',  3.00, 150000.00, '2015-01-10'),
    ('V002', 'slopez',   2.50, 120000.00, '2018-05-02'),
    ('V003', 'aperez',   2.50, 100000.00, '2014-06-01'),
    ('V004', 'jramirez', 2.50, 100000.00, '2017-02-20'),
    ('V005', 'mjlopez',  3.00,  90000.00, '2019-08-10'),
    ('V006', 'lgarcia',  2.00, 200000.00, '2021-11-05')
) AS v(codigo, username, comision, meta, ingreso)
INNER JOIN Usuario u ON u.username = v.username;

-- 6. CLIENTES (todos usan la cuenta 1.1.02.01 Clientes)
INSERT INTO Cliente (codigo, nit, nombre_comercial, razon_social, tipo_cliente,
                     direccion, zona, id_municipio, telefono, correo,
                     contacto_nombre, contacto_telefono, contacto_correo,
                     id_cuenta_contable, id_vendedor, limite_credito, dias_credito)
SELECT v.codigo, v.nit, v.nombre, v.razon, v.tipo,
       v.direccion, v.zona, m.id_municipio, v.tel, v.correo,
       v.contacto, v.contacto_tel, v.contacto_correo,
       cc.id_cuenta, ve.id_vendedor, v.limite, v.dias
FROM (VALUES
 ('C0001','4567891-2','Constructora Los Altos','Constructora Los Altos, S.A.','Empresa',
  '12 Calle 5-40',10,'0101','2367-1100','compras@constructoralosaltos.com.gt',
  'Ing. Marco Tulio Reyes','5541-2200','mreyes@constructoralosaltos.com.gt','V001',150000.00,30),
 ('C0002','2345678-9','Instalaciones Eléctricas Méndez',NULL,'Contratista',
  '3a. Avenida 8-15',1,'0108','2435-6677','iemendez@correo.com.gt',
  'José Méndez','5512-8890',NULL,'V001',25000.00,15),
 ('C0003','7788990-1','Electro Proyectos del Sur','Electro Proyectos del Sur, S.A.','Empresa',
  'Km 16 Carretera al Pacífico',NULL,'0115','6630-4455','ventas@electroproyectos.com.gt',
  'Ing. Luisa Fernanda Ortiz','5578-3321','lortiz@electroproyectos.com.gt','V004',80000.00,30),
 ('C0004','1122334-K','Hotel Vista Volcán','Inversiones Turísticas Vista Volcán, S.A.','Empresa',
  '5a. Avenida Norte 20',NULL,'0301','7832-5500','mantenimiento@vistavolcan.com.gt',
  'Ricardo Solís','5590-1122',NULL,'V002',40000.00,30),
 ('C0005','9988776-5','Industrias Plásticas del Norte','Industrias Plásticas del Norte, S.A.','Empresa',
  '32 Calle 18-60',12,'0101','2479-8800','compras@plasticasnorte.com.gt',
  'Ing. Héctor Monzón','5523-7788','hmonzon@plasticasnorte.com.gt','V002',60000.00,30),
 ('C0006','CF','Juan Pérez García',NULL,'Persona Individual',
  '4a. Calle 3-21',6,'0108','5544-3210',NULL,
  'Juan Pérez García','5544-3210',NULL,'V003',0.00,0),
 ('C0007','5566778-3','Montajes Industriales Xela','Montajes Industriales Xela, S.A.','Empresa',
  '15 Avenida 4-50',3,'0901','7761-2233','info@montajesxela.com.gt',
  'Ing. Byron Fuentes','5501-6677','bfuentes@montajesxela.com.gt','V005',70000.00,30),
 ('C0008','3344556-7','Ingeniería Eléctrica Quetzalteca',NULL,'Contratista',
  '7a. Calle 12-08',1,'0901','7765-9090','ieq@correo.com.gt',
  'Mario Coyoy','5498-1100',NULL,'V005',30000.00,15),
 ('C0009','6677889-0','Agroindustrias La Ceiba','Agroindustrias La Ceiba, S.A.','Empresa',
  'Km 62 Ruta a Puerto Quetzal',NULL,'0501','7888-6600','compras@laceiba.com.gt',
  'Lic. Sandra Barrios','5530-4545','sbarrios@laceiba.com.gt','V006',120000.00,45),
 ('C0010','8899001-4','Beneficio San Rafael','Beneficio de Café San Rafael, S.A.','Empresa',
  'Finca San Rafael, Km 70',NULL,'0501','7880-1234','admin@beneficiosanrafael.com.gt',
  'Ing. Óscar Pineda','5567-8899',NULL,'V006',200000.00,45),
 ('C0011','2233445-6','Electricidad y Servicios Mixco',NULL,'Contratista',
  'Calzada San Juan 30-12',7,'0108','2431-5566','esmixco@correo.com.gt',
  'Fernando Ajú','5520-3344',NULL,'V003',20000.00,15),
 ('C0012','4455667-8','Centro Comercial Plaza Villa','Plaza Villa Nueva, S.A.','Empresa',
  'Boulevard Villa Nueva 5-00',1,'0115','6631-7700','mantenimiento@plazavilla.com.gt',
  'Lic. Patricia Gómez','5588-2211','pgomez@plazavilla.com.gt','V004',50000.00,30),
 ('C0013','CF','María Elena Cifuentes',NULL,'Persona Individual',
  '20 Calle 10-35',11,'0101','5432-1098',NULL,
  'María Elena Cifuentes','5432-1098',NULL,'V001',0.00,0),
 ('C0014','1357924-6','Colegio Bilingüe Nueva Esperanza','Asociación Educativa Nueva Esperanza','Empresa',
  'Km 18.5 Carretera a El Salvador',NULL,'0102','6637-4400','administracion@nuevaesperanza.edu.gt',
  'Licda. Carmen Arriaga','5599-0011',NULL,'V002',35000.00,30),
 ('C0015','2468013-5','Telecomunicaciones Andinas','Telecomunicaciones Andinas, S.A.','Empresa',
  'Avenida La Reforma 9-55',10,'0101','2385-6000','proveeduria@telandinas.com.gt',
  'Ing. Walter Samayoa','5511-9988','wsamayoa@telandinas.com.gt','V001',90000.00,30)
) AS v(codigo, nit, nombre, razon, tipo, direccion, zona, mun, tel, correo,
       contacto, contacto_tel, contacto_correo, vendedor, limite, dias)
INNER JOIN Municipio m  ON m.codigo_ine = v.mun
INNER JOIN Vendedor  ve ON ve.codigo    = v.vendedor
CROSS JOIN Cuenta_Contable cc
WHERE cc.codigo = '1.1.02.01';
GO

-- =====================================================
-- VERIFICACION
-- =====================================================

-- a) PRUEBA: un consumidor final (CF) con crédito debe ser RECHAZADO
BEGIN TRY
    INSERT INTO Cliente (codigo, nit, nombre_comercial, direccion, id_municipio,
                         contacto_nombre, id_cuenta_contable, id_vendedor, limite_credito)
    SELECT 'C9999', 'CF', 'Cliente de prueba', 'Ciudad', 1,
           'Prueba', cc.id_cuenta, 1, 5000
    FROM Cuenta_Contable cc WHERE cc.codigo = '1.1.02.01';
    SELECT 'Prueba CF con crédito' AS Prueba, 'ERROR: se guardó' AS Resultado;
END TRY
BEGIN CATCH
    SELECT 'Prueba CF con crédito' AS Prueba,
           'RECHAZADO correctamente: ' + ERROR_MESSAGE() AS Resultado;
END CATCH;

-- b) Conteo
SELECT 'Usuario' AS Tabla, COUNT(*) AS Registros FROM Usuario  UNION ALL
SELECT 'Vendedor',         COUNT(*)              FROM Vendedor UNION ALL
SELECT 'Cliente',          COUNT(*)              FROM Cliente;

-- c) Vendedores (1:1 con Usuario) y cuántos clientes consiguió cada uno
SELECT v.codigo AS Vendedor, u.nombre_completo, u.username,
       s.nombre AS Sitio, v.porcentaje_comision AS Comision_pct,
       COUNT(c.id_cliente) AS Clientes
FROM Vendedor v
INNER JOIN Usuario u ON u.id_usuario = v.id_usuario
INNER JOIN Sitio   s ON s.id_sitio   = v.id_sitio
LEFT  JOIN Cliente c ON c.id_vendedor = v.id_vendedor
GROUP BY v.codigo, u.nombre_completo, u.username, s.nombre, v.porcentaje_comision
ORDER BY v.codigo;

-- d) HAVING: vendedores con MÁS de 2 clientes
SELECT v.codigo AS Vendedor, u.nombre_completo, COUNT(*) AS Clientes
FROM Cliente c
INNER JOIN Vendedor v ON v.id_vendedor = c.id_vendedor
INNER JOIN Usuario  u ON u.id_usuario  = v.id_usuario
GROUP BY v.codigo, u.nombre_completo
HAVING COUNT(*) > 2;

-- e) Clientes con su dirección completa, vendedor y cuenta contable
SELECT c.codigo, c.nit, c.nombre_comercial, c.tipo_cliente,
       c.direccion + ISNULL(', zona ' + CAST(c.zona AS VARCHAR(2)), '')
                   + ', ' + m.nombre + ', ' + d.nombre        AS Direccion_Completa,
       c.contacto_nombre, v.codigo AS Vendedor,
       cc.codigo + ' ' + cc.nombre                              AS Cuenta_Contable,
       c.limite_credito, c.dias_credito
FROM Cliente c
INNER JOIN Municipio       m  ON m.id_municipio    = c.id_municipio
INNER JOIN Departamento    d  ON d.id_departamento = m.id_departamento
INNER JOIN Vendedor        v  ON v.id_vendedor     = c.id_vendedor
INNER JOIN Cuenta_Contable cc ON cc.id_cuenta      = c.id_cuenta_contable
ORDER BY c.codigo;
