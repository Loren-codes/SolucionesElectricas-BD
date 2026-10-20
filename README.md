# Sistema de Gestión de Ventas, Inventarios y Contabilidad
### Base de datos **SolucionesElectricas** · SQL Server

Proyecto final del curso de Base de Datos. Base de datos relacional para una empresa distribuidora de materiales eléctricos con **5 sitios**, bodegas y localizaciones. Integra **ventas, inventarios y contabilidad**: cada documento genera automáticamente su partida contable.

## El proyecto en números
| | |
|---|---|
| Tablas | 35 |
| Llaves foráneas | 65 |
| Reglas CHECK | 77 |
| Columnas calculadas | 20 |
| Procedimientos almacenados | 9 |
| Vistas / Función / Trigger | 6 / 1 / 1 |

## Proceso de ventas
`Cotización → Pedido → Factura → Cobro → Despacho`, y cada documento genera su **partida contable** (Debe = Haber).

## Scripts (ejecutar en orden)
| Script | Descripción |
|---|---|
| `00_verificar_avance.sql` | Cuenta los registros de todas las tablas |
| `01_crear_base.sql` | Crea la base de datos |
| `02_tablas_empresa.sql` | Tablas de empresa, sitios, bodegas y localizaciones |
| `03_datos_empresa.sql` | Datos de Guatemala, empresa y ubicaciones |
| `04_contabilidad.sql` | Monedas y catálogo de cuentas |
| `05_productos.sql` | Productos, categorías, inventario, trigger y vista |
| `06_clientes_vendedores.sql` | Usuarios, vendedores y clientes |
| `07_tablas_ventas.sql` | Tablas del proceso de ventas y partidas |
| `08_procedimientos.sql` | Procedimientos almacenados (reglas de negocio) |
| `09_historial_ventas.sql` | Historial de ventas julio–octubre |
| `09b_resumen_historial.sql` | Verificación del historial |
| `09c_corregir_fechas.sql` | Parche de corrección de fechas |
| `10_venta_en_vivo.sql` | Venta completa con 12 pruebas de reglas |
| `11_acid.sql` | Atomicidad, Consistencia, SAVEPOINT y Durabilidad |
| `12_aislamiento_usuario1.sql` / `12_aislamiento_usuario2.sql` | Aislamiento con dos usuarios |
| `13_consultas_avanzadas.sql` | Las 9 consultas avanzadas |
| `14_reportes_contables.sql` | Libro diario, balances y alertas |

## Herramientas
SQL Server Express 2025 · SQL Server Management Studio 22 · T-SQL
