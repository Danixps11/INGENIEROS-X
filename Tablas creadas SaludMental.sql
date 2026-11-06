CREATE TABLE dbo.salud_mental_atendidos (
    anio         SMALLINT      NOT NULL,
    nro_mes      TINYINT       NOT NULL,
    ubigeo       CHAR(6)       NOT NULL,
    departamento NVARCHAR(50)  NOT NULL,
    provincia    NVARCHAR(60)  NOT NULL,
    distrito     NVARCHAR(80)  NOT NULL,
    sexo         CHAR(1)       NOT NULL,
    etapa        VARCHAR(10)   NOT NULL,
    diagnostico  NVARCHAR(100) NOT NULL,
    atendidos    INT           NOT NULL,
    atenciones   INT           NOT NULL
);

SELECT * FROM dbo.salud_mental_atendidos

--INSERTAR CSV
BULK INSERT dbo.salud_mental_atendidos
FROM 'D:\Ciclo4\Dat_salud_mental_atendidos.csv'
WITH (
    FORMAT          = 'CSV',      -- respeta las comillas (diagnosticos con comas)
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '0x0a',
    CODEPAGE        = '65001',    -- UTF-8
    TABLOCK
);
GO


--CREAR TABLAS
--TABLA UBIGEO
CREATE TABLE dbo.dim_ubigeo (
    ubigeo           CHAR(6)       NOT NULL PRIMARY KEY,   -- llave natural (INEI)
    cod_departamento CHAR(2)       NOT NULL,
    cod_provincia    CHAR(4)       NOT NULL,
    departamento     NVARCHAR(50)  NOT NULL,
    provincia        NVARCHAR(60)  NOT NULL,
    distrito         NVARCHAR(80)  NOT NULL
);
SELECT * FROM dbo.dim_ubigeo
--INSERTAR
INSERT INTO dbo.dim_ubigeo (ubigeo, cod_departamento, cod_provincia, departamento, provincia, distrito)
SELECT DISTINCT ubigeo, LEFT(ubigeo,2), LEFT(ubigeo,4), departamento, provincia, distrito
FROM dbo.salud_mental_atendidos;


--TABLA SEXO
CREATE TABLE dbo.dim_sexo (
    id_sexo     TINYINT     IDENTITY(1,1) PRIMARY KEY,
    sexo        CHAR(1)     NOT NULL UNIQUE,
    descripcion VARCHAR(10) NOT NULL
);
SELECT * FROM dbo.dim_sexo
--INSERTAR
INSERT INTO dbo.dim_sexo (sexo, descripcion)
SELECT DISTINCT sexo,
       CASE sexo WHEN 'F' THEN 'Femenino' WHEN 'M' THEN 'Masculino' ELSE 'Otro' END
FROM dbo.salud_mental_atendidos
ORDER BY sexo;


--TABLA ETAPA
CREATE TABLE dbo.dim_etapa (
    id_etapa    TINYINT     NOT NULL PRIMARY KEY,
    etapa       VARCHAR(10) NOT NULL UNIQUE,    -- texto original del archivo
    edad_min    TINYINT     NOT NULL,
    edad_max    TINYINT     NULL,               -- NULL = sin limite superior (80 +)
    grupo_etapa VARCHAR(25) NOT NULL            -- etapa de vida (grupos MINSA)
);
SELECT * FROM dbo.dim_etapa
--INSERTAR
INSERT INTO dbo.dim_etapa (id_etapa, etapa, edad_min, edad_max, grupo_etapa) VALUES
 ( 1, '< 1',     0,  0,    'Infante (0-4)'),
 ( 2, '01 - 04', 1,  4,    'Infante (0-4)'),
 ( 3, '05 - 09', 5,  9,    'Nino (5-11)'),
 ( 4, '10 - 11', 10, 11,   'Nino (5-11)'),
 ( 5, '12 - 14', 12, 14,   'Adolescente (12-17)'),
 ( 6, '15 - 17', 15, 17,   'Adolescente (12-17)'),
 ( 7, '18 - 24', 18, 24,   'Joven (18-29)'),
 ( 8, '25 - 29', 25, 29,   'Joven (18-29)'),
 ( 9, '30 - 39', 30, 39,   'Adulto (30-59)'),
 (10, '40 - 59', 40, 59,   'Adulto (30-59)'),
 (11, '60 - 79', 60, 79,   'Adulto mayor (60+)'),
 (12, '80 +',    80, NULL, 'Adulto mayor (60+)');


--TABLA DIAGNOSTICO
CREATE TABLE dbo.dim_diagnostico (
    id_diagnostico TINYINT       IDENTITY(1,1) PRIMARY KEY,
    diagnostico    NVARCHAR(100) NOT NULL UNIQUE,
    categoria      VARCHAR(30)   NOT NULL       -- agrupacion propuesta, editable
);
SELECT * FROM dbo.dim_diagnostico
--INSERTAR
INSERT INTO dbo.dim_diagnostico (diagnostico, categoria)
SELECT d.diagnostico,
       CASE
           WHEN d.diagnostico LIKE 'VIOLENCIA%'         THEN 'Violencia'
           WHEN d.diagnostico LIKE '%CONSUMO%'          THEN 'Consumo de sustancias'
           WHEN d.diagnostico LIKE '%SUICIDIO%'         THEN 'Conducta suicida'
           WHEN d.diagnostico IN ('ANSIEDAD','TRASTORNO DEPRESIVO') THEN 'Animo y ansiedad'
           ELSE 'Otros trastornos'
       END
FROM (SELECT DISTINCT diagnostico FROM dbo.salud_mental_atendidos) d
ORDER BY d.diagnostico;


--TABLA  PERIODO AÑO
CREATE TABLE dbo.dim_periodo (
    id_periodo   INT         NOT NULL PRIMARY KEY,   -- YYYYMM
    anio         SMALLINT    NOT NULL,
    nro_mes      TINYINT     NOT NULL,
    nombre_mes   VARCHAR(15) NOT NULL,
    trimestre    TINYINT     NOT NULL,
    fecha_inicio DATE        NOT NULL
);
SELECT * FROM dbo.dim_periodo
--INSERTAR
SET LANGUAGE Spanish;   -- nombres de mes en espanol
INSERT INTO dbo.dim_periodo (id_periodo, anio, nro_mes, nombre_mes, trimestre, fecha_inicio)
SELECT p.anio * 100 + p.nro_mes,
       p.anio,
       p.nro_mes,
       DATENAME(MONTH, DATEFROMPARTS(p.anio, p.nro_mes, 1)),
       DATEPART(QUARTER, DATEFROMPARTS(p.anio, p.nro_mes, 1)),
       DATEFROMPARTS(p.anio, p.nro_mes, 1)
FROM (SELECT DISTINCT anio, nro_mes FROM dbo.salud_mental_atendidos) p;


--TABLA PERIODO + DISTRITO + SEXO + ETAPA + DIAGNOSTICO
CREATE TABLE dbo.fact_salud_mental (
    id_registro    BIGINT  IDENTITY(1,1) PRIMARY KEY,
    id_periodo     INT     NOT NULL REFERENCES dbo.dim_periodo(id_periodo),
    ubigeo         CHAR(6) NOT NULL REFERENCES dbo.dim_ubigeo(ubigeo),
    id_sexo        TINYINT NOT NULL REFERENCES dbo.dim_sexo(id_sexo),
    id_etapa       TINYINT NOT NULL REFERENCES dbo.dim_etapa(id_etapa),
    id_diagnostico TINYINT NOT NULL REFERENCES dbo.dim_diagnostico(id_diagnostico),
    atendidos      INT     NOT NULL,
    atenciones     INT     NOT NULL,
    CONSTRAINT UQ_fact_salud_mental UNIQUE (id_periodo, ubigeo, id_sexo, id_etapa, id_diagnostico)
);
GO
SELECT * FROM dbo.fact_salud_mental
 --INSERTAR
INSERT INTO dbo.fact_salud_mental
       (id_periodo, ubigeo, id_sexo, id_etapa, id_diagnostico, atendidos, atenciones)
SELECT s.anio * 100 + s.nro_mes,
       s.ubigeo,
       x.id_sexo,
       e.id_etapa,
       d.id_diagnostico,
       s.atendidos,
       s.atenciones
FROM dbo.salud_mental_atendidos s
JOIN dbo.dim_sexo        x ON x.sexo        = s.sexo
JOIN dbo.dim_etapa       e ON e.etapa       = s.etapa
JOIN dbo.dim_diagnostico d ON d.diagnostico = s.diagnostico;
GO


-- ESTA TABLA ES PARA CORROBORAR QUE LOS DATOS SE HAYAN INSERTADO CORRECTAMENTE
CREATE VIEW dbo.vw_salud_mental_completa AS
SELECT f.id_registro,
       p.anio, p.nro_mes, p.nombre_mes, p.trimestre,
       u.ubigeo, u.departamento, u.provincia, u.distrito,
       x.sexo, x.descripcion AS sexo_desc,
       e.etapa, e.grupo_etapa,
       d.diagnostico, d.categoria AS categoria_diagnostico,
       f.atendidos, f.atenciones
FROM dbo.fact_salud_mental f
JOIN dbo.dim_periodo     p ON p.id_periodo     = f.id_periodo
JOIN dbo.dim_ubigeo      u ON u.ubigeo         = f.ubigeo
JOIN dbo.dim_sexo        x ON x.id_sexo        = f.id_sexo
JOIN dbo.dim_etapa       e ON e.id_etapa       = f.id_etapa
JOIN dbo.dim_diagnostico d ON d.id_diagnostico = f.id_diagnostico;
GO


SELECT (SELECT COUNT(*) FROM dbo.salud_mental_atendidos)   AS filas_origen,
       (SELECT COUNT(*) FROM dbo.fact_salud_mental)        AS filas_hechos,
       (SELECT COUNT(*) FROM dbo.vw_salud_mental_completa) AS filas_vista;


--EJEMPLOS DE PRUEBA DE LA BASE
-- Atenciones por departamento (de mayor a menor)
SELECT departamento, SUM(atenciones) AS atenciones
FROM dbo.vw_salud_mental_completa
GROUP BY departamento
ORDER BY atenciones DESC;
 
-- Evolucion mensual por categoria de diagnostico
SELECT nro_mes, nombre_mes, categoria_diagnostico, SUM(atenciones) AS atenciones
FROM dbo.vw_salud_mental_completa
GROUP BY nro_mes, nombre_mes, categoria_diagnostico
ORDER BY nro_mes, atenciones DESC;
 
-- Diagnosticos por etapa de vida y sexo
SELECT grupo_etapa, sexo_desc, diagnostico, SUM(atenciones) AS atenciones
FROM dbo.vw_salud_mental_completa
GROUP BY grupo_etapa, sexo_desc, diagnostico
ORDER BY grupo_etapa, sexo_desc, atenciones DESC;
 
-- Solo Tacna: top distritos por atenciones
SELECT TOP 10 departamento, provincia, distrito, SUM(atenciones) AS atenciones
FROM dbo.vw_salud_mental_completa
WHERE departamento = 'TACNA'
GROUP BY departamento, provincia, distrito
ORDER BY atenciones DESC;