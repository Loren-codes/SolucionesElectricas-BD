-- =====================================================
-- Script 03: Datos de Empresa y Ubicaciones (Grupo A)
-- =====================================================
USE SolucionesElectricas;
GO

-- -----------------------------------------------------
-- 1. DEPARTAMENTOS (22, con código INE y región)
-- -----------------------------------------------------
INSERT INTO Departamento (codigo_ine, nombre, region) VALUES
('01', 'Guatemala',      'Metropolitana'),
('02', 'El Progreso',    'Nororiente'),
('03', 'Sacatepéquez',   'Central'),
('04', 'Chimaltenango',  'Central'),
('05', 'Escuintla',      'Central'),
('06', 'Santa Rosa',     'Suroriente'),
('07', 'Sololá',         'Suroccidente'),
('08', 'Totonicapán',    'Suroccidente'),
('09', 'Quetzaltenango', 'Suroccidente'),
('10', 'Suchitepéquez',  'Suroccidente'),
('11', 'Retalhuleu',     'Suroccidente'),
('12', 'San Marcos',     'Suroccidente'),
('13', 'Huehuetenango',  'Noroccidente'),
('14', 'Quiché',         'Noroccidente'),
('15', 'Baja Verapaz',   'Norte'),
('16', 'Alta Verapaz',   'Norte'),
('17', 'Petén',          'Petén'),
('18', 'Izabal',         'Nororiente'),
('19', 'Zacapa',         'Nororiente'),
('20', 'Chiquimula',     'Nororiente'),
('21', 'Jalapa',         'Suroriente'),
('22', 'Jutiapa',        'Suroriente');

-- -----------------------------------------------------
-- 2. MUNICIPIOS (el departamento se obtiene del código)
-- -----------------------------------------------------
INSERT INTO Municipio (codigo_ine, nombre, id_departamento)
SELECT v.codigo, v.nombre, d.id_departamento
FROM (VALUES
    ('0101','Guatemala'),        ('0102','Santa Catarina Pinula'),
    ('0103','San José Pinula'),  ('0104','San José del Golfo'),
    ('0105','Palencia'),         ('0106','Chinautla'),
    ('0107','San Pedro Ayampuc'),('0108','Mixco'),
    ('0109','San Pedro Sacatepéquez'), ('0110','San Juan Sacatepéquez'),
    ('0111','San Raymundo'),     ('0112','Chuarrancho'),
    ('0113','Fraijanes'),        ('0114','Amatitlán'),
    ('0115','Villa Nueva'),      ('0116','Villa Canales'),
    ('0117','San Miguel Petapa'),
    ('0201','Guastatoya'),       ('0301','Antigua Guatemala'),
    ('0401','Chimaltenango'),    ('0501','Escuintla'),
    ('0601','Cuilapa'),          ('0701','Sololá'),
    ('0801','Totonicapán'),      ('0901','Quetzaltenango'),
    ('1001','Mazatenango'),      ('1101','Retalhuleu'),
    ('1201','San Marcos'),       ('1301','Huehuetenango'),
    ('1401','Santa Cruz del Quiché'), ('1501','Salamá'),
    ('1601','Cobán'),            ('1701','Flores'),
    ('1801','Puerto Barrios'),   ('1901','Zacapa'),
    ('2001','Chiquimula'),       ('2101','Jalapa'),
    ('2201','Jutiapa')
) AS v(codigo, nombre)
INNER JOIN Departamento d ON d.codigo_ine = LEFT(v.codigo, 2);

-- -----------------------------------------------------
-- 3. EMPRESA
-- -----------------------------------------------------
INSERT INTO Empresa (nit, razon_social, nombre_comercial, regimen_iva,
                     direccion, zona, id_municipio, codigo_postal, correo,
                     sitio_web, representante_legal, fecha_fundacion, logo_url)
VALUES ('8754321-K',
        'Soluciones Eléctricas de Guatemala, Sociedad Anónima',
        'Soluciones Eléctricas GT',
        'General',
        '7a. Avenida 12-45, Edificio Torre Eléctrica',
        9,
        (SELECT id_municipio FROM Municipio WHERE codigo_ine = '0101'),
        '01009',
        'info@solucioneselectricas.com.gt',
        'www.solucioneselectricas.com.gt',
        'Ing. Roberto Castillo Morales',
        '2010-03-15',
        'C:\Proyecto_BD\imagenes\logo.png');

-- -----------------------------------------------------
-- 4. TELEFONOS DE LA EMPRESA (atributo multivaluado)
-- -----------------------------------------------------
INSERT INTO Empresa_Telefono (id_empresa, tipo, numero, extension, es_principal)
SELECT e.id_empresa, v.tipo, v.numero, v.ext, v.principal
FROM (VALUES
    ('PBX',      '2412-5000', NULL,  1),
    ('WhatsApp', '5512-3400', NULL,  0),
    ('Fijo',     '2412-5010', '101', 0),
    ('Celular',  '4021-7788', NULL,  0)
) AS v(tipo, numero, ext, principal)
CROSS JOIN Empresa e
WHERE e.nit = '8754321-K';

-- -----------------------------------------------------
-- 5. SITIOS (5 sedes con coordenadas GPS)
-- -----------------------------------------------------
INSERT INTO Sitio (id_empresa, codigo, nombre, tipo_sitio, direccion, zona,
                   id_municipio, telefono, correo, encargado,
                   hora_apertura, hora_cierre, latitud, longitud, fecha_apertura)
SELECT e.id_empresa, v.codigo, v.nombre, v.tipo, v.direccion, v.zona,
       m.id_municipio, v.tel, v.correo, v.encargado,
       v.abre, v.cierra, v.lat, v.lon, v.fecha
FROM (VALUES
    ('S01','Casa Matriz Zona 9','Casa Matriz',
     '7a. Avenida 12-45', 9, '0101', '2412-5001',
     'matriz@solucioneselectricas.com.gt', 'Carlos Méndez',
     '07:30','18:00', 14.600800, -90.513600, '2010-03-15'),
    ('S02','Sucursal Mixco','Sucursal',
     'Calzada San Juan 15-20', 4, '0108', '2412-5002',
     'mixco@solucioneselectricas.com.gt', 'Ana Lucía Pérez',
     '08:00','18:00', 14.630600, -90.607200, '2014-06-01'),
    ('S03','Sucursal Villa Nueva','Sucursal',
     'Km 17.5 Carretera al Pacífico', 4, '0115', '2412-5003',
     'villanueva@solucioneselectricas.com.gt', 'Jorge Ramírez',
     '08:00','18:00', 14.526900, -90.587500, '2017-02-20'),
    ('S04','Sucursal Quetzaltenango','Sucursal',
     '4a. Calle 15-30', 3, '0901', '7765-2004',
     'xela@solucioneselectricas.com.gt', 'María José López',
     '08:00','17:30', 14.834700, -91.518000, '2019-08-10'),
    ('S05','Centro de Distribución Escuintla','Centro de Distribución',
     'Km 58 Autopista Palín-Escuintla', NULL, '0501', '7888-2005',
     'cedi@solucioneselectricas.com.gt', 'Luis Fernando García',
     '06:00','20:00', 14.305000, -90.785000, '2021-11-05')
) AS v(codigo, nombre, tipo, direccion, zona, cod_mun, tel, correo,
       encargado, abre, cierra, lat, lon, fecha)
INNER JOIN Municipio m ON m.codigo_ine = v.cod_mun
CROSS JOIN Empresa e
WHERE e.nit = '8754321-K';

-- -----------------------------------------------------
-- 6. BODEGAS (2 por sitio + 1 de devoluciones en el CEDI)
-- -----------------------------------------------------
INSERT INTO Bodega (id_sitio, codigo, nombre, tipo_bodega, area_m2)
SELECT s.id_sitio, b.codigo, b.nombre, b.tipo, b.area
FROM Sitio s
CROSS JOIN (VALUES
    ('B01', 'Bodega General',   'General',              350.00),
    ('B02', 'Bodega de Cables', 'Cables y Conductores', 200.00)
) AS b(codigo, nombre, tipo, area);

INSERT INTO Bodega (id_sitio, codigo, nombre, tipo_bodega, area_m2)
SELECT id_sitio, 'B03', 'Bodega de Devoluciones', 'Devoluciones', 120.00
FROM Sitio
WHERE codigo = 'S05';

-- -----------------------------------------------------
-- 7. LOCALIZACIONES (generadas automáticamente)
--    Cada bodega: 2 pasillos x 2 estantes x 3 niveles = 12
-- -----------------------------------------------------
INSERT INTO Localizacion (id_bodega, pasillo, estante, nivel,
                          tipo_ubicacion, capacidad_max)
SELECT b.id_bodega, pa.n, es.n, ni.n,
       CASE b.tipo_bodega
            WHEN 'Cables y Conductores' THEN 'Carrete'
            WHEN 'Devoluciones'         THEN 'Jaula'
            ELSE 'Rack'
       END,
       CASE b.tipo_bodega
            WHEN 'Cables y Conductores' THEN 5000.00   -- metros de cable
            ELSE 500.00                                -- unidades
       END
FROM Bodega b
CROSS JOIN (VALUES (1),(2))     AS pa(n)   -- pasillos
CROSS JOIN (VALUES (1),(2))     AS es(n)   -- estantes
CROSS JOIN (VALUES (1),(2),(3)) AS ni(n);  -- niveles
GO

-- -----------------------------------------------------
-- 8. VERIFICACION: cuántos registros tiene cada tabla
-- -----------------------------------------------------
SELECT 'Departamento'     AS Tabla, COUNT(*) AS Registros FROM Departamento     UNION ALL
SELECT 'Municipio',                 COUNT(*)              FROM Municipio        UNION ALL
SELECT 'Empresa',                   COUNT(*)              FROM Empresa          UNION ALL
SELECT 'Empresa_Telefono',          COUNT(*)              FROM Empresa_Telefono UNION ALL
SELECT 'Sitio',                     COUNT(*)              FROM Sitio            UNION ALL
SELECT 'Bodega',                    COUNT(*)              FROM Bodega           UNION ALL
SELECT 'Localizacion',              COUNT(*)              FROM Localizacion;

-- La jerarquía completa: Sitio -> Bodega -> Localización
SELECT s.codigo AS Sitio, s.nombre AS Nombre_Sitio, m.nombre AS Municipio,
       d.nombre AS Departamento, b.codigo AS Bodega, b.nombre AS Nombre_Bodega,
       l.codigo AS Localizacion, l.tipo_ubicacion
FROM Sitio s
INNER JOIN Municipio    m ON m.id_municipio    = s.id_municipio
INNER JOIN Departamento d ON d.id_departamento = m.id_departamento
INNER JOIN Bodega       b ON b.id_sitio        = s.id_sitio
INNER JOIN Localizacion l ON l.id_bodega       = b.id_bodega
ORDER BY s.codigo, b.codigo, l.codigo;
