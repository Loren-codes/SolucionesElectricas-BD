-- =====================================================
-- Script 12a: AISLAMIENTO - USUARIO 1 (Gerente)
-- Ejecutar POR BLOQUES (seleccionar el bloque + F5)
-- =====================================================
USE SolucionesElectricas;

-- ===== BLOQUE 1: el gerente empieza a cambiar el precio (SIN confirmar) =====
BEGIN TRANSACTION;
UPDATE Producto SET precio_unitario = 9.99 WHERE codigo = 'CO-BC-0001';
SELECT codigo, precio_unitario AS Precio_que_ve_el_Gerente,
       @@TRANCOUNT AS Transacciones_abiertas
FROM Producto WHERE codigo = 'CO-BC-0001';

-- ===== BLOQUE 2: ¿quién está esperando a quién? =====
SELECT r.session_id          AS Sesion_que_espera,
       r.blocking_session_id AS Bloqueada_por_la_sesion,
       r.wait_type           AS Tipo_de_espera,
       r.wait_time / 1000    AS Segundos_esperando
FROM sys.dm_exec_requests r
WHERE r.blocking_session_id <> 0;

-- ===== BLOQUE 3: el gerente se arrepiente y CANCELA =====
ROLLBACK TRANSACTION;

-- ===== BLOQUE 4: segunda prueba - vuelve a cambiar el precio sin confirmar =====
BEGIN TRANSACTION;
UPDATE Producto SET precio_unitario = 9.99 WHERE codigo = 'CO-BC-0001';

-- ===== BLOQUE 5: cancela otra vez =====
ROLLBACK TRANSACTION;
