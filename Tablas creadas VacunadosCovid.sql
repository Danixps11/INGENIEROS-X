--TABLA GENERO
CREATE TABLE dbo.dim_genero (
    id_genero   TINYINT      IDENTITY(1,1) PRIMARY KEY,
    genero      VARCHAR(10)  NOT NULL UNIQUE
);

SELECT * FROM dbo.dim_genero
--INSERTAR:
INSERT INTO dbo.dim_genero (genero)
SELECT DISTINCT desc_genero FROM dbo.padron_vacunados_covid ORDER BY desc_genero;



--TABLA DOSIS
CREATE TABLE dbo.dim_dosis (
    id_dosis        TINYINT      IDENTITY(1,1) PRIMARY KEY,
    dosis_aplicada  VARCHAR(30)  NOT NULL UNIQUE,   -- texto original
    numero_dosis    TINYINT      NULL,              -- 1-4; NULL si no aplica (única, revacunado)
    tipo_dosis      VARCHAR(20)  NOT NULL,          -- Esquema primario / Refuerzo / Única / Revacunado
    es_refuerzo     BIT          NOT NULL,
    orden           TINYINT      NOT NULL,          -- para ordenar reportes
    CONSTRAINT CK_dim_dosis_tipo CHECK
        (tipo_dosis IN ('Esquema primario','Refuerzo','Única','Revacunado'))
);

SELECT * FROM dbo.dim_dosis
--INSERTAR:
INSERT INTO dbo.dim_dosis (dosis_aplicada, numero_dosis, tipo_dosis, es_refuerzo, orden)
SELECT x.dosis_aplicada,
       x.numero_dosis,
       x.tipo_dosis,
       CASE WHEN x.tipo_dosis = 'Refuerzo' THEN 1 ELSE 0 END,
       -- orden: esquema primario (1-4), refuerzos (5-6), única (7), revacunado (8)
       CASE
           WHEN x.tipo_dosis = 'Esquema primario' THEN x.numero_dosis
           WHEN x.tipo_dosis = 'Refuerzo'         THEN 4 + x.numero_dosis
           WHEN x.tipo_dosis = 'Única'            THEN 7
           ELSE 8
       END
FROM (
    SELECT d.dosis_aplicada,
           TRY_CAST(CASE WHEN LEFT(d.dosis_aplicada,1) LIKE '[0-9]'
                         THEN LEFT(d.dosis_aplicada,1) END AS TINYINT) AS numero_dosis,
           CASE
               WHEN d.dosis_aplicada LIKE '%refuerzo%'   THEN 'Refuerzo'
               WHEN d.dosis_aplicada LIKE '%nica%'       THEN 'Única'
               WHEN d.dosis_aplicada LIKE '%revacunado%' THEN 'Revacunado'
               ELSE 'Esquema primario'
           END AS tipo_dosis
    FROM (SELECT DISTINCT dosis_aplicada FROM dbo.padron_vacunados_covid) d
) x;
GO



--TABLA GRUPORIESGO
CREATE TABLE dbo.dim_grupo_riesgo (
    id_grupo_riesgo INT          IDENTITY(1,1) PRIMARY KEY,
    grupo_riesgo    VARCHAR(255) NOT NULL UNIQUE
);

SELECT * FROM dbo.dim_grupo_riesgo
--INSERTAR:
INSERT INTO dbo.dim_grupo_riesgo (grupo_riesgo)
SELECT DISTINCT gruporiesgo FROM dbo.padron_vacunados_covid ORDER BY gruporiesgo;



--TABLA ESTABLECIMIENTO
CREATE TABLE dbo.dim_establecimiento (
    id_establecimiento INT          IDENTITY(1,1) PRIMARY KEY,
    establecimiento    VARCHAR(100) NOT NULL UNIQUE
);

SELECT * FROM dbo.dim_establecimiento
--INSERTAR:
INSERT INTO dbo.dim_establecimiento (establecimiento)
SELECT DISTINCT establecimiento FROM dbo.padron_vacunados_covid ORDER BY establecimiento;



--TABLA FABRICANTE
CREATE TABLE dbo.dim_fabricante (
    id_fabricante TINYINT     IDENTITY(1,1) PRIMARY KEY,
    fabricante    VARCHAR(30) NOT NULL UNIQUE
);

SELECT * FROM dbo.dim_fabricante
--INSERTAR:
INSERT INTO dbo.dim_fabricante (fabricante)
SELECT DISTINCT fabricante FROM dbo.padron_vacunados_covid ORDER BY fabricante;



--TABLA FECHA
CREATE TABLE dbo.dim_fecha (
    id_fecha     INT         NOT NULL PRIMARY KEY,   -- formato YYYYMMDD
    fecha        DATE        NOT NULL UNIQUE,
    anio         SMALLINT    NOT NULL,
    trimestre    TINYINT     NOT NULL,
    mes          TINYINT     NOT NULL,
    nombre_mes   VARCHAR(15) NOT NULL,
    dia          TINYINT     NOT NULL,
    dia_semana   VARCHAR(15) NOT NULL
);

SELECT * FROM dbo.dim_fecha
--INSERTAR:
SET LANGUAGE Spanish;   -- nombres de mes y dia en espanol
INSERT INTO dbo.dim_fecha (id_fecha, fecha, anio, trimestre, mes, nombre_mes, dia, dia_semana)
SELECT CONVERT(INT, FORMAT(f.fecha_vacunacion,'yyyyMMdd')),
       f.fecha_vacunacion,
       YEAR(f.fecha_vacunacion),
       DATEPART(QUARTER, f.fecha_vacunacion),
       MONTH(f.fecha_vacunacion),
       DATENAME(MONTH,   f.fecha_vacunacion),
       DAY(f.fecha_vacunacion),
       DATENAME(WEEKDAY, f.fecha_vacunacion)
FROM (SELECT DISTINCT fecha_vacunacion FROM dbo.padron_vacunados_covid) f;



--TABLA CENTRAL DE HECHOS
CREATE TABLE dbo.fact_vacunacion (
    id_vacunacion      BIGINT   IDENTITY(1,1) PRIMARY KEY,
    id_fecha           INT      NOT NULL REFERENCES dbo.dim_fecha(id_fecha),
    id_genero          TINYINT  NOT NULL REFERENCES dbo.dim_genero(id_genero),
    edad               SMALLINT NOT NULL,
    id_dosis           TINYINT  NOT NULL REFERENCES dbo.dim_dosis(id_dosis),
    id_grupo_riesgo    INT      NOT NULL REFERENCES dbo.dim_grupo_riesgo(id_grupo_riesgo),
    id_establecimiento INT      NOT NULL REFERENCES dbo.dim_establecimiento(id_establecimiento),
    id_fabricante      TINYINT  NOT NULL REFERENCES dbo.dim_fabricante(id_fabricante)
);

SELECT * FROM dbo.fact_vacunacion
--INSERTAR:
INSERT INTO dbo.fact_vacunacion
       (id_fecha, id_genero, edad, id_dosis, id_grupo_riesgo, id_establecimiento, id_fabricante)
SELECT CONVERT(INT, FORMAT(p.fecha_vacunacion,'yyyyMMdd')),
       g.id_genero,
       p.edad,
       d.id_dosis,
       r.id_grupo_riesgo,
       e.id_establecimiento,
       f.id_fabricante
FROM dbo.padron_vacunados_covid p
JOIN dbo.dim_genero          g ON g.genero          = p.desc_genero
JOIN dbo.dim_dosis           d ON d.dosis_aplicada  = p.dosis_aplicada
JOIN dbo.dim_grupo_riesgo    r ON r.grupo_riesgo    = p.gruporiesgo
JOIN dbo.dim_establecimiento e ON e.establecimiento = p.establecimiento
JOIN dbo.dim_fabricante      f ON f.fabricante      = p.fabricante;




--EJEMPLOS DE CONSULTAS

-- Vacunados por mes y fabricante
SELECT fe.anio, fe.mes, f.fabricante, COUNT(*) AS total
FROM dbo.fact_vacunacion v
JOIN dbo.dim_fecha fe ON fe.id_fecha = v.id_fecha
JOIN dbo.dim_fabricante f ON f.id_fabricante = v.id_fabricante
GROUP BY fe.anio, fe.mes, f.fabricante
ORDER BY fe.anio, fe.mes, total DESC;
 
-- Top 10 establecimientos con mas dosis aplicadas
SELECT TOP 10 e.establecimiento, COUNT(*) AS total
FROM dbo.fact_vacunacion v
JOIN dbo.dim_establecimiento e ON e.id_establecimiento = v.id_establecimiento
GROUP BY e.establecimiento
ORDER BY total DESC;
 
-- Distribucion por genero y numero de dosis (usando la vista)
SELECT genero, numero_dosis, COUNT(*) AS total
FROM dbo.vw_vacunacion_completa
GROUP BY genero, numero_dosis
ORDER BY genero, numero_dosis;
 