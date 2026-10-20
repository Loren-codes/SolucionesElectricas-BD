-- =====================================================
-- Script 12b: AISLAMIENTO - USUARIO 2 (Vendedor)
-- Ejecutar POR BLOQUES (seleccionar el bloque + F5)
-- =====================================================
USE SolucionesElectricas;

-- ===== BLOQUE 1: lectura NORMAL (READ COMMITTED) =====
SELECT codigo, descripcion, precio_unitario AS Precio_que_ve_el_Vendedor
FROM Producto WHERE codigo = 'CO-BC-0001';

-- ===== BLOQUE 2: lectura SUCIA (READ UNCOMMITTED) =====
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT codigo, precio_unitario AS Precio_lectura_SUCIA
FROM Producto WHERE codigo = 'CO-BC-0001';

-- ===== BLOQUE 3: volver a la normalidad y leer otra vez =====
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT codigo, precio_unitario AS Precio_REAL
FROM Producto WHERE codigo = 'CO-BC-0001';
