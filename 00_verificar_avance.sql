-- =====================================================
-- Script 00: Verificar el avance del proyecto
-- (se puede ejecutar cuantas veces quieras)
-- =====================================================
USE SolucionesElectricas;
GO

SELECT t.name      AS Tabla,
       SUM(p.rows) AS Registros
FROM   sys.tables t
INNER JOIN sys.partitions p
       ON p.object_id = t.object_id
      AND p.index_id IN (0, 1)
GROUP BY t.name
ORDER BY t.name;
