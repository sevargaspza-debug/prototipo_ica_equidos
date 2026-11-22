-- ============================================================================
-- BASE DE DATOS — SISTEMA ICA DE BIENESTAR ANIMAL EN ÉQUIDOS
-- Modelo V3 · Norma ICA V2.0 (2023)
-- Motor: MariaDB 10.6+ / 11.x (compatible con MySQL 8.0.16+)
-- Codificación: utf8mb4 · Collation: utf8mb4_unicode_ci
-- ============================================================================
-- Contenido:
--   1. Creación de la base de datos y catálogos (libertades, categorías etarias)
--   2. Fincas, ubicaciones e inventario por grupos
--   3. Indicadores checklist C1 (43) y C2 (32) con ficha normativa
--   4. Evaluaciones por etapas EI–EIV, resultados, muestras y respuestas
--   5. Evidencias, documentos, plan de mejora y auditoría
--   6. Sesión de trabajo (finca activa por usuario)
--   7. Vistas de apoyo (muestra Tabla 1, avance, fichas, documentos)
--   8. Datos semilla: 5 libertades, 4 categorías, 75 indicadores, 7 documentos
--
-- Ejecución:
--   mariadb -u root -p < Script_BD_ICA_Equidos_V3_MariaDB.sql
--   mysql   -u root -p < Script_BD_ICA_Equidos_V3_MariaDB.sql
--
-- Si la base ya existe y desea conservar los datos, haga un respaldo y
-- compare el esquema antes de aplicar cambios. Este script está pensado
-- para una instalación limpia; CREATE TABLE IF NOT EXISTS no agrega
-- columnas nuevas a tablas que ya existen.
-- ============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

CREATE DATABASE IF NOT EXISTS ica_equidos
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE ica_equidos;

-- ============================================================================
-- 0. OPCIONAL: REINSTALACIÓN LIMPIA
-- Descomente este bloque si desea eliminar todas las tablas y recrearlas.
-- ¡ADVERTENCIA! Borra los datos existentes.
-- ============================================================================
-- SET FOREIGN_KEY_CHECKS = 0;
-- DROP TABLE IF EXISTS auditoria_trazabilidad;
-- DROP TABLE IF EXISTS plan_mejora;
-- DROP TABLE IF EXISTS documento_soporte;
-- DROP TABLE IF EXISTS catalogo_documento_indicador;
-- DROP TABLE IF EXISTS catalogo_documento;
-- DROP TABLE IF EXISTS evidencia_foto;
-- DROP TABLE IF EXISTS detalle_respuestas;
-- DROP TABLE IF EXISTS muestra_animal;
-- DROP TABLE IF EXISTS resultado_libertad;
-- DROP TABLE IF EXISTS evaluaciones;
-- DROP TABLE IF EXISTS indicadores_checklist;
-- DROP TABLE IF EXISTS inventario_equino;
-- DROP TABLE IF EXISTS catalogo_categoria_etaria;
-- DROP TABLE IF EXISTS libertades;
-- DROP TABLE IF EXISTS sesion_trabajo;
-- DROP TABLE IF EXISTS ubicaciones;
-- DROP TABLE IF EXISTS fincas;
-- SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================================
-- 1. FINCAS
-- ============================================================================
CREATE TABLE IF NOT EXISTS fincas (
  id_finca CHAR(36) NOT NULL DEFAULT (UUID()),
  nombre_finca VARCHAR(255) NOT NULL,
  propietario VARCHAR(255) NOT NULL,
  direccion VARCHAR(500) NOT NULL,
  municipio VARCHAR(150) NOT NULL,
  departamento VARCHAR(150) NOT NULL,
  msnm DECIMAL(8,2) NOT NULL,
  tipo ENUM('criadero','deporte','traspatio','trabajo') NOT NULL,
  sistema_productivo ENUM('pesebrera','potrero','mixto') NOT NULL,
  tipo_productor VARCHAR(150) NULL,
  telefono_contacto VARCHAR(30) NULL,
  correo_contacto VARCHAR(150) NULL,
  observaciones TEXT NULL,
  creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actualizado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id_finca),
  KEY idx_fincas_municipio (municipio, departamento),
  KEY idx_fincas_activo (activo),
  CONSTRAINT chk_fincas_msnm CHECK (msnm >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Fincas/equipamientos equinos evaluados según ICA V2 2023';

-- ============================================================================
-- 2. UBICACIONES (alojamientos/sitios evaluados en Etapa I)
-- ============================================================================
CREATE TABLE IF NOT EXISTS ubicaciones (
  id_ubicacion CHAR(36) NOT NULL DEFAULT (UUID()),
  id_finca CHAR(36) NOT NULL,
  nombre_ubicacion VARCHAR(150) NOT NULL,
  tipo_ubicacion VARCHAR(100) NULL,
  capacidad_maxima INT NULL,
  observaciones TEXT NULL,
  creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id_ubicacion),
  KEY idx_ubicaciones_finca (id_finca),
  CONSTRAINT fk_ubicaciones_finca FOREIGN KEY (id_finca)
    REFERENCES fincas(id_finca) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_ubicaciones_capacidad CHECK (capacidad_maxima IS NULL OR capacidad_maxima > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Alojamientos o sitios evaluados dentro de la finca';

-- ============================================================================
-- 3. LIBERTADES (5 libertades ICA V2 2023)
-- ============================================================================
CREATE TABLE IF NOT EXISTS libertades (
  id_libertad TINYINT UNSIGNED NOT NULL,
  nombre VARCHAR(150) NOT NULL,
  descripcion TEXT NOT NULL,
  peso DECIMAL(5,2) NOT NULL,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id_libertad),
  CONSTRAINT chk_libertades_peso CHECK (peso > 0 AND peso <= 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='5 libertades de bienestar animal según ICA V2 2023; pesos 20/15/30/15/20';

-- ============================================================================
-- 4. CATÁLOGO DE CATEGORÍAS ETARIAS (normalización del muestreo)
-- ============================================================================
CREATE TABLE IF NOT EXISTS catalogo_categoria_etaria (
  id_categoria CHAR(36) NOT NULL DEFAULT (UUID()),
  codigo VARCHAR(20) NOT NULL,
  nombre VARCHAR(100) NOT NULL,
  descripcion TEXT NULL,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id_categoria),
  UNIQUE KEY uq_categoria_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Categorías etarias usadas para desagregar el inventario y la muestra';

-- ============================================================================
-- 5. INVENTARIO EQUINO (por grupos: especie × categoría × sexo)
-- ============================================================================
CREATE TABLE IF NOT EXISTS inventario_equino (
  id_equino CHAR(36) NOT NULL DEFAULT (UUID()),
  id_finca CHAR(36) NOT NULL,
  id_categoria_etaria CHAR(36) NULL,
  especie ENUM('caballar','asnal','mular','burdegano','cebroide') NOT NULL,
  sexo ENUM('macho','hembra','indeterminado') NOT NULL,
  cantidad INT NOT NULL DEFAULT 1,
  nombre_identificacion VARCHAR(100) NULL,
  nro_identificacion VARCHAR(100) NULL,
  fecha_nacimiento DATE NULL,
  peso_aproximado DECIMAL(8,2) NULL,
  categoria_etaria VARCHAR(100) NULL,
  observaciones TEXT NULL,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_equino),
  KEY idx_equino_finca (id_finca),
  KEY idx_equino_especie (especie),
  KEY idx_equino_grupo (id_finca, especie, categoria_etaria, sexo),
  KEY idx_equino_categoria (id_categoria_etaria),
  CONSTRAINT fk_equino_finca FOREIGN KEY (id_finca)
    REFERENCES fincas(id_finca) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_equino_categoria FOREIGN KEY (id_categoria_etaria)
    REFERENCES catalogo_categoria_etaria(id_categoria) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_equino_cantidad CHECK (cantidad > 0),
  CONSTRAINT chk_equino_peso CHECK (peso_aproximado IS NULL OR peso_aproximado > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Inventario total de équidos por finca; cantidad alimenta la Tabla 1';

-- ============================================================================
-- 6. INDICADORES CHECKLIST (C1 = 43, C2 = 32) CON FICHA NORMATIVA
-- ============================================================================
CREATE TABLE IF NOT EXISTS indicadores_checklist (
  id_indicador CHAR(36) NOT NULL DEFAULT (UUID()),
  codigo VARCHAR(10) NOT NULL,
  capitulo ENUM('C1','C2') NOT NULL,
  id_libertad TINYINT UNSIGNED NOT NULL,
  descripcion TEXT NOT NULL,
  metodo ENUM('visual','documental') NULL,
  fase ENUM('campo','documental') NOT NULL DEFAULT 'campo',
  opciones_puntaje JSON NOT NULL DEFAULT ('[0,20,55,100]'),
  metodologia TEXT NULL,
  preguntas JSON NULL,
  escala_calificacion JSON NULL,
  version VARCHAR(20) NOT NULL DEFAULT 'ICA-V2-2023',
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_indicador),
  UNIQUE KEY uq_indicador_codigo (codigo),
  KEY idx_indicadores_capitulo (capitulo),
  KEY idx_indicadores_libertad (id_libertad),
  KEY idx_indicadores_fase (fase),
  KEY idx_indicadores_metodo (metodo),
  CONSTRAINT fk_indicadores_libertad FOREIGN KEY (id_libertad)
    REFERENCES libertades(id_libertad) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Catálogo ICA V2 2023: C1 (43) + C2 (32); ficha normativa para Etapas II y III';

-- ============================================================================
-- 7. EVALUACIONES (visita por etapas EI–EIV)
-- ============================================================================
CREATE TABLE IF NOT EXISTS evaluaciones (
  id_evaluacion CHAR(36) NOT NULL DEFAULT (UUID()),
  id_finca CHAR(36) NOT NULL,
  id_ubicacion CHAR(36) NULL,
  codigo_evaluacion VARCHAR(50) NOT NULL,
  fecha_evaluacion DATE NOT NULL,
  hora_inicio TIMESTAMP NULL DEFAULT NULL,
  hora_fin TIMESTAMP NULL DEFAULT NULL,
  evaluador_principal VARCHAR(255) NOT NULL,
  evaluadores_auxiliares VARCHAR(500) NULL,
  capitulo ENUM('C1','C2') NOT NULL,
  version_norma VARCHAR(20) NOT NULL DEFAULT 'ICA-V2-2023',
  tipo_finca_aplicado ENUM('criadero','deporte','traspatio','trabajo') NULL,
  sistema_productivo_aplicado ENUM('pesebrera','potrero','mixto') NULL,
  msnm_evaluacion DECIMAL(8,2) NULL,
  total_animales INT NULL,
  muestra_calculada INT NULL,
  muestra_ajustada INT NULL,
  justificacion_muestra TEXT NULL,
  porcentaje_total DECIMAL(6,2) NULL,
  clasificacion ENUM('Excelente','Alto','Medio','Bajo') NULL,
  estado ENUM('en_proceso','pendiente_revision','finalizada','anulada','suspendida')
    NOT NULL DEFAULT 'en_proceso',
  etapa_actual ENUM('EI','EII','EIII','EIV') NOT NULL DEFAULT 'EI',
  motivo_suspension TEXT NULL,
  fecha_suspension TIMESTAMP NULL DEFAULT NULL,
  observaciones_generales TEXT NULL,
  requiere_plan_mejora BOOLEAN NOT NULL DEFAULT FALSE,
  creado_por VARCHAR(150) NULL,
  creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actualizado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  finalizado_en TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (id_evaluacion),
  UNIQUE KEY uq_evaluacion_codigo (codigo_evaluacion),
  KEY idx_eval_finca (id_finca),
  KEY idx_eval_ubicacion (id_ubicacion),
  KEY idx_eval_fecha (fecha_evaluacion),
  KEY idx_eval_capitulo (capitulo),
  KEY idx_eval_estado (estado),
  KEY idx_eval_etapa (etapa_actual),
  CONSTRAINT fk_eval_finca FOREIGN KEY (id_finca)
    REFERENCES fincas(id_finca) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_eval_ubicacion FOREIGN KEY (id_ubicacion)
    REFERENCES ubicaciones(id_ubicacion) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_eval_msnm CHECK (msnm_evaluacion IS NULL OR msnm_evaluacion >= 0),
  CONSTRAINT chk_eval_total CHECK (total_animales IS NULL OR total_animales >= 0),
  CONSTRAINT chk_eval_muestra_calc CHECK (muestra_calculada IS NULL OR muestra_calculada >= 0),
  CONSTRAINT chk_eval_muestra_ajust CHECK (muestra_ajustada IS NULL OR muestra_ajustada >= 0),
  CONSTRAINT chk_eval_porcentaje CHECK (porcentaje_total IS NULL OR (porcentaje_total >= 0 AND porcentaje_total <= 100)),
  CONSTRAINT chk_eval_suspension CHECK (
    estado <> 'suspendida'
    OR (motivo_suspension IS NOT NULL AND CHAR_LENGTH(TRIM(motivo_suspension)) > 0)
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Evaluaciones ICA V2 2023 por finca/ubicación, con etapa vigente y suspensión';

-- ============================================================================
-- 8. RESULTADO POR LIBERTAD (5 registros por evaluación)
-- ============================================================================
CREATE TABLE IF NOT EXISTS resultado_libertad (
  id_resultado_libertad CHAR(36) NOT NULL DEFAULT (UUID()),
  id_evaluacion CHAR(36) NOT NULL,
  id_libertad TINYINT UNSIGNED NOT NULL,
  promedio DECIMAL(6,2) NULL,
  ponderado DECIMAL(6,2) NULL,
  puntaje_bruto DECIMAL(8,2) NULL,
  cumplido BOOLEAN NOT NULL DEFAULT FALSE,
  observacion TEXT NULL,
  calculado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_resultado_libertad),
  UNIQUE KEY uq_resultado_libertad_eval (id_evaluacion, id_libertad),
  KEY idx_reslib_eval (id_evaluacion),
  KEY idx_reslib_lib (id_libertad),
  CONSTRAINT fk_reslib_eval FOREIGN KEY (id_evaluacion)
    REFERENCES evaluaciones(id_evaluacion) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_reslib_libertad FOREIGN KEY (id_libertad)
    REFERENCES libertades(id_libertad) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_reslib_promedio CHECK (promedio IS NULL OR (promedio >= 0 AND promedio <= 100)),
  CONSTRAINT chk_reslib_ponderado CHECK (ponderado IS NULL OR (ponderado >= 0 AND ponderado <= 100)),
  CONSTRAINT chk_reslib_bruto CHECK (puntaje_bruto IS NULL OR puntaje_bruto >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Resultado por libertad: promedio y contribución ponderada (ICA V2 2023 §5.5)';

-- ============================================================================
-- 9. MUESTRA ANIMAL (animales seleccionados según Tabla 1)
-- ============================================================================
CREATE TABLE IF NOT EXISTS muestra_animal (
  id_muestra_animal CHAR(36) NOT NULL DEFAULT (UUID()),
  id_evaluacion CHAR(36) NOT NULL,
  id_equino CHAR(36) NULL,
  especie ENUM('caballar','asnal','mular','burdegano','cebroide') NOT NULL,
  sexo ENUM('macho','hembra','indeterminado') NOT NULL,
  grupo_etario VARCHAR(100) NULL,
  categoria_etaria VARCHAR(100) NULL,
  identificacion VARCHAR(100) NULL,
  ubicacion VARCHAR(150) NULL,
  muestreado BOOLEAN NOT NULL DEFAULT TRUE,
  observacion TEXT NULL,
  creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_muestra_animal),
  KEY idx_muestra_eval (id_evaluacion),
  KEY idx_muestra_equino (id_equino),
  CONSTRAINT fk_muestra_eval FOREIGN KEY (id_evaluacion)
    REFERENCES evaluaciones(id_evaluacion) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_muestra_equino FOREIGN KEY (id_equino)
    REFERENCES inventario_equino(id_equino) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Animales muestreados para verificación de BHS, identificación y condiciones individuales';

-- ============================================================================
-- 10. DETALLE DE RESPUESTAS
-- ============================================================================
CREATE TABLE IF NOT EXISTS detalle_respuestas (
  id_detalle CHAR(36) NOT NULL DEFAULT (UUID()),
  id_evaluacion CHAR(36) NOT NULL,
  id_indicador CHAR(36) NOT NULL,
  id_resultado_libertad CHAR(36) NULL,
  id_muestra_animal CHAR(36) NULL,
  puntaje_obtenido TINYINT UNSIGNED NOT NULL,
  observacion TEXT NULL,
  foto_url1 VARCHAR(500) NULL,
  foto_url2 VARCHAR(500) NULL,
  foto_url3 VARCHAR(500) NULL,
  numerador DECIMAL(12,4) NULL,
  denominador DECIMAL(12,4) NULL,
  requiere_tratamiento BOOLEAN NOT NULL DEFAULT FALSE,
  fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  registrado_por VARCHAR(150) NULL,
  PRIMARY KEY (id_detalle),
  KEY idx_det_eval (id_evaluacion),
  KEY idx_det_indic (id_indicador),
  KEY idx_det_reslib (id_resultado_libertad),
  KEY idx_det_muestra (id_muestra_animal),
  CONSTRAINT fk_det_eval FOREIGN KEY (id_evaluacion)
    REFERENCES evaluaciones(id_evaluacion) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_det_indicador FOREIGN KEY (id_indicador)
    REFERENCES indicadores_checklist(id_indicador) ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_det_reslib FOREIGN KEY (id_resultado_libertad)
    REFERENCES resultado_libertad(id_resultado_libertad) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_det_muestra FOREIGN KEY (id_muestra_animal)
    REFERENCES muestra_animal(id_muestra_animal) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_det_puntaje CHECK (puntaje_obtenido IN (0,20,55,100)),
  CONSTRAINT chk_det_denominador CHECK (denominador IS NULL OR denominador >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Respuestas por indicador con evidencias y trazabilidad';

-- ============================================================================
-- 11. EVIDENCIA FOTOGRÁFICA (máximo 3 por detalle)
-- ============================================================================
CREATE TABLE IF NOT EXISTS evidencia_foto (
  id_evidencia_foto CHAR(36) NOT NULL DEFAULT (UUID()),
  id_detalle CHAR(36) NOT NULL,
  orden TINYINT UNSIGNED NOT NULL,
  foto_url VARCHAR(500) NOT NULL,
  descripcion TEXT NULL,
  nombre_archivo VARCHAR(255) NULL,
  tipo_archivo VARCHAR(50) NULL,
  tamano_bytes BIGINT NULL,
  registrado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  registrado_por VARCHAR(150) NULL,
  PRIMARY KEY (id_evidencia_foto),
  UNIQUE KEY uq_evidencia_orden (id_detalle, orden),
  KEY idx_foto_detalle (id_detalle),
  CONSTRAINT fk_foto_detalle FOREIGN KEY (id_detalle)
    REFERENCES detalle_respuestas(id_detalle) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT chk_foto_orden CHECK (orden BETWEEN 1 AND 3),
  CONSTRAINT chk_foto_tamano CHECK (tamano_bytes IS NULL OR tamano_bytes >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Evidencias fotográficas (máximo 3 por detalle) con metadatos';

-- ============================================================================
-- 12. CATÁLOGO DE DOCUMENTOS DE LA ETAPA III (D1–D7)
-- ============================================================================
CREATE TABLE IF NOT EXISTS catalogo_documento (
  id_documento CHAR(36) NOT NULL DEFAULT (UUID()),
  codigo VARCHAR(10) NOT NULL,
  nombre VARCHAR(255) NOT NULL,
  descripcion TEXT NULL,
  obligatorio BOOLEAN NOT NULL DEFAULT TRUE,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id_documento),
  UNIQUE KEY uq_documento_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Catálogo de documentos y registros solicitados en la Etapa III';

-- ============================================================================
-- 13. RELACIÓN DOCUMENTO → INDICADOR(ES)
-- Un documento puede soportar el mismo indicador en C1 y C2; D7 no aplica en C2.
-- ============================================================================
CREATE TABLE IF NOT EXISTS catalogo_documento_indicador (
  codigo_documento VARCHAR(10) NOT NULL,
  codigo_indicador VARCHAR(10) NOT NULL,
  PRIMARY KEY (codigo_documento, codigo_indicador),
  KEY idx_docind_indicador (codigo_indicador),
  CONSTRAINT fk_docind_documento FOREIGN KEY (codigo_documento)
    REFERENCES catalogo_documento(codigo) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_docind_indicador FOREIGN KEY (codigo_indicador)
    REFERENCES indicadores_checklist(codigo) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Mapeo N:M entre documentos D1–D7 e indicadores documentales de C1/C2';

-- ============================================================================
-- 14. DOCUMENTO SOPORTE POR EVALUACIÓN
-- ============================================================================
CREATE TABLE IF NOT EXISTS documento_soporte (
  id_documento_soporte CHAR(36) NOT NULL DEFAULT (UUID()),
  id_evaluacion CHAR(36) NOT NULL,
  codigo_documento VARCHAR(10) NULL,
  tipo_documento VARCHAR(150) NOT NULL,
  presenta BOOLEAN NOT NULL DEFAULT FALSE,
  se_niega BOOLEAN NOT NULL DEFAULT FALSE,
  firmado BOOLEAN NOT NULL DEFAULT FALSE,
  matricula_comvezcol VARCHAR(100) NULL,
  nombre_firmante VARCHAR(255) NULL,
  cargo_firmante VARCHAR(150) NULL,
  fecha_presentacion DATE NULL,
  archivo_url VARCHAR(500) NULL,
  observacion TEXT NULL,
  creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  creado_por VARCHAR(150) NULL,
  PRIMARY KEY (id_documento_soporte),
  KEY idx_doc_eval (id_evaluacion),
  KEY idx_doc_tipo (tipo_documento),
  KEY idx_doc_catalogo (codigo_documento),
  CONSTRAINT fk_doc_eval FOREIGN KEY (id_evaluacion)
    REFERENCES evaluaciones(id_evaluacion) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_doc_catalogo FOREIGN KEY (codigo_documento)
    REFERENCES catalogo_documento(codigo) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_doc_presentacion CHECK (NOT (presenta AND se_niega))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Documentación soporte: legible, firmada por MV/MVZ, matrícula COMVEZCOL, presenta/se niega';

-- ============================================================================
-- 15. PLAN DE MEJORA
-- ============================================================================
CREATE TABLE IF NOT EXISTS plan_mejora (
  id_plan_mejora CHAR(36) NOT NULL DEFAULT (UUID()),
  id_evaluacion CHAR(36) NOT NULL,
  id_indicador CHAR(36) NULL,
  id_libertad TINYINT UNSIGNED NULL,
  titulo VARCHAR(255) NOT NULL,
  accion TEXT NOT NULL,
  responsable VARCHAR(255) NOT NULL,
  fecha_limite DATE NOT NULL,
  prioridad ENUM('baja','media','alta','critica') NOT NULL DEFAULT 'media',
  estado ENUM('pendiente','en_ejecucion','en_revision','cerrado','cancelado')
    NOT NULL DEFAULT 'pendiente',
  requiere_tratamiento BOOLEAN NOT NULL DEFAULT FALSE,
  fecha_inicio DATE NULL,
  fecha_cierre DATE NULL,
  evidencia_cierre TEXT NULL,
  observaciones TEXT NULL,
  creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  creado_por VARCHAR(150) NULL,
  actualizado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  actualizado_por VARCHAR(150) NULL,
  PRIMARY KEY (id_plan_mejora),
  KEY idx_plan_eval (id_evaluacion),
  KEY idx_plan_indic (id_indicador),
  KEY idx_plan_estado (estado),
  KEY idx_plan_prioridad (prioridad),
  CONSTRAINT fk_plan_eval FOREIGN KEY (id_evaluacion)
    REFERENCES evaluaciones(id_evaluacion) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_plan_indicador FOREIGN KEY (id_indicador)
    REFERENCES indicadores_checklist(id_indicador) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_plan_libertad FOREIGN KEY (id_libertad)
    REFERENCES libertades(id_libertad) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_plan_fechas CHECK (
    fecha_cierre IS NULL OR fecha_inicio IS NULL OR fecha_cierre >= fecha_inicio
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Plan de acción correctiva con seguimiento (RF27/HU-13)';

-- ============================================================================
-- 16. AUDITORÍA Y TRAZABILIDAD
-- ============================================================================
CREATE TABLE IF NOT EXISTS auditoria_trazabilidad (
  id_auditoria CHAR(36) NOT NULL DEFAULT (UUID()),
  tabla_afectada VARCHAR(100) NOT NULL,
  id_registro_afectado CHAR(36) NULL,
  accion ENUM('CREATE','UPDATE','DELETE','VIEW') NOT NULL,
  usuario VARCHAR(150) NOT NULL,
  fecha_accion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  direccion_ip VARCHAR(50) NULL,
  user_agent TEXT NULL,
  valor_anterior JSON NULL,
  valor_nuevo JSON NULL,
  motivo_eliminacion TEXT NULL,
  observacion TEXT NULL,
  PRIMARY KEY (id_auditoria),
  KEY idx_aud_tabla (tabla_afectada),
  KEY idx_aud_fecha (fecha_accion),
  KEY idx_aud_usuario (usuario)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Trazabilidad completa con valores anterior/nuevo y soft-delete con motivo (RF34)';

-- ============================================================================
-- 17. SESIÓN DE TRABAJO: FINCA ACTIVA POR USUARIO
-- ============================================================================
CREATE TABLE IF NOT EXISTS sesion_trabajo (
  id_sesion CHAR(36) NOT NULL DEFAULT (UUID()),
  usuario VARCHAR(150) NOT NULL,
  id_finca_activa CHAR(36) NULL,
  activa BOOLEAN NOT NULL DEFAULT TRUE,
  -- Columna generada para garantizar una sola sesión activa por usuario
  -- (MariaDB/MySQL no soportan índices únicos parciales como PostgreSQL).
  usuario_activo VARCHAR(150)
    GENERATED ALWAYS AS (IF(activa = TRUE, usuario, NULL)) STORED,
  creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actualizado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id_sesion),
  UNIQUE KEY uq_sesion_usuario_activa (usuario_activo),
  KEY idx_sesion_finca (id_finca_activa),
  CONSTRAINT fk_sesion_finca FOREIGN KEY (id_finca_activa)
    REFERENCES fincas(id_finca) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Finca activa por usuario: evita reseleccionar el predio en cada evaluación';

-- ============================================================================
-- 18. VISTAS DE APOYO
-- ============================================================================

-- Resumen de una evaluación con el puntaje total ponderado.
CREATE OR REPLACE VIEW vw_resumen_evaluacion AS
SELECT
  e.id_evaluacion,
  e.codigo_evaluacion,
  f.nombre_finca,
  e.fecha_evaluacion,
  e.capitulo,
  e.clasificacion,
  e.version_norma,
  ROUND(COALESCE(SUM(rl.ponderado), 0), 2) AS puntaje_total_ponderado,
  e.estado,
  e.etapa_actual
FROM evaluaciones e
JOIN fincas f ON f.id_finca = e.id_finca
LEFT JOIN resultado_libertad rl ON rl.id_evaluacion = e.id_evaluacion
GROUP BY
  e.id_evaluacion, e.codigo_evaluacion, f.nombre_finca, e.fecha_evaluacion,
  e.capitulo, e.clasificacion, e.version_norma, e.estado, e.etapa_actual;

-- Validación de los pesos de las 5 libertades (debe sumar 100).
CREATE OR REPLACE VIEW vw_validacion_pesos AS
SELECT
  id_libertad,
  nombre,
  peso,
  (SELECT SUM(peso) FROM libertades) AS suma_total
FROM libertades;

-- Tamaño del predio y muestra mínima según Tabla 1 (Capítulo I).
CREATE OR REPLACE VIEW vw_tamano_muestra_finca AS
SELECT
  f.id_finca,
  f.nombre_finca,
  CAST(COALESCE(SUM(i.cantidad), 0) AS SIGNED) AS total_equidos,
  CASE
    WHEN COALESCE(SUM(i.cantidad), 0) = 0 THEN 0
    WHEN COALESCE(SUM(i.cantidad), 0) < 10 THEN CAST(COALESCE(SUM(i.cantidad), 0) AS SIGNED)
    WHEN COALESCE(SUM(i.cantidad), 0) <= 20 THEN 10
    WHEN COALESCE(SUM(i.cantidad), 0) <= 99 THEN 20
    WHEN COALESCE(SUM(i.cantidad), 0) <= 499 THEN 30
    WHEN COALESCE(SUM(i.cantidad), 0) <= 999 THEN 40
    ELSE CAST(CEIL(COALESCE(SUM(i.cantidad), 0) * 0.05) AS SIGNED)
  END AS muestra_minima
FROM fincas f
LEFT JOIN inventario_equino i
  ON i.id_finca = f.id_finca AND i.activo = TRUE
GROUP BY f.id_finca, f.nombre_finca;

-- Ficha normativa completa de cada indicador (Etapas II y III).
CREATE OR REPLACE VIEW vw_indicadores_ficha AS
SELECT
  i.codigo,
  i.capitulo,
  i.id_libertad,
  l.nombre AS libertad,
  l.peso AS peso_libertad,
  i.descripcion,
  i.fase,
  i.metodo,
  i.metodologia,
  i.preguntas,
  i.escala_calificacion,
  i.opciones_puntaje,
  i.version,
  i.activo
FROM indicadores_checklist i
JOIN libertades l ON l.id_libertad = i.id_libertad;

-- Documentos D1–D7 y los indicadores que soportan en cada capítulo.
CREATE OR REPLACE VIEW vw_documentos_indicador AS
SELECT
  d.codigo AS codigo_documento,
  d.nombre AS documento,
  d.obligatorio,
  i.capitulo,
  i.codigo AS codigo_indicador,
  i.descripcion AS indicador,
  i.fase,
  i.metodo
FROM catalogo_documento d
JOIN catalogo_documento_indicador m ON m.codigo_documento = d.codigo
JOIN indicadores_checklist i ON i.codigo = m.codigo_indicador
WHERE d.activo = TRUE AND i.activo = TRUE;

-- Avance de una evaluación: indicadores respondidos sobre el total del capítulo.
CREATE OR REPLACE VIEW vw_avance_evaluacion AS
SELECT
  e.id_evaluacion,
  e.codigo_evaluacion,
  e.capitulo,
  e.etapa_actual,
  e.estado,
  COUNT(DISTINCT i.codigo) AS total_indicadores,
  COUNT(DISTINCT dr.id_indicador) AS indicadores_respondidos,
  ROUND(
    COUNT(DISTINCT dr.id_indicador) / NULLIF(COUNT(DISTINCT i.codigo), 0) * 100,
    2
  ) AS avance_pct
FROM evaluaciones e
JOIN indicadores_checklist i
  ON i.capitulo = e.capitulo AND i.activo = TRUE
LEFT JOIN detalle_respuestas dr
  ON dr.id_evaluacion = e.id_evaluacion AND dr.id_indicador = i.id_indicador
GROUP BY
  e.id_evaluacion, e.codigo_evaluacion, e.capitulo, e.etapa_actual, e.estado;

-- ============================================================================
-- 19. DATOS SEMILLA
-- ============================================================================

-- 19.1 Las 5 libertades (pesos fijos 20/15/30/15/20 = 100)
INSERT INTO libertades (id_libertad, nombre, descripcion, peso, activo) VALUES
  (1, 'Hambre, sed y malnutrición', 'Libre de hambre, sed y malnutrición', 20.00, TRUE),
  (2, 'Molestias físicas y térmicas', 'Libre de molestias físicas y térmicas', 15.00, TRUE),
  (3, 'Dolor, lesión y enfermedad', 'Libre de dolor, lesión y enfermedad', 30.00, TRUE),
  (4, 'Temor y angustia', 'Libre de temor y angustia', 15.00, TRUE),
  (5, 'Comportamiento natural', 'Libre para expresar comportamientos naturales', 20.00, TRUE)
ON DUPLICATE KEY UPDATE
  nombre = VALUES(nombre),
  descripcion = VALUES(descripcion),
  peso = VALUES(peso),
  activo = VALUES(activo);

-- 19.2 Categorías etarias (alineadas con el prototipo)
INSERT INTO catalogo_categoria_etaria (codigo, nombre, descripcion, activo) VALUES
  ('CRIA_LACTANTE', 'Cría lactante', 'Crías en periodo lactante', TRUE),
  ('JOVEN', 'Joven', 'Animales jóvenes poslactancia', TRUE),
  ('ADULTO', 'Adulto', 'Animales adultos', TRUE),
  ('GERONTE', 'Geronte', 'Animales geriátricos o seniles', TRUE)
ON DUPLICATE KEY UPDATE
  nombre = VALUES(nombre),
  descripcion = VALUES(descripcion),
  activo = VALUES(activo);

-- 19.3 Indicadores C1 (43) y C2 (32) con ficha normativa
INSERT INTO indicadores_checklist
  (codigo, capitulo, id_libertad, descripcion, metodo, fase,
   opciones_puntaje, metodologia, preguntas, escala_calificacion, version, activo)
VALUES
  ('I-01', 'C1', 1, 'Disponibilidad de agua', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación directa de bebederos, fuentes y conducta de bebida del grupo muestreado, en al menos dos momentos del día.', JSON_ARRAY('¿Todos los équidos tienen acceso permanente a agua limpia y fresca?', '¿Los bebederos o fuentes son suficientes y están bien ubicados para todo el grupo?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-02', 'C1', 1, 'Calidad del agua', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Verificación visual del agua y revisión documental del análisis de laboratorio vigente (pH, sólidos, coliformes).', JSON_ARRAY('¿El agua está limpia, sin olores, coloración ni residuos visibles?', '¿Se cuenta con un análisis de calidad del agua vigente y firmado?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-03', 'C1', 1, 'Acceso a alimento', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de comederos, pasturas y rutas de acceso; verificación de que ningún animal queda excluido.', JSON_ARRAY('¿Todos los animales pueden acceder al alimento sin competencia ni bloqueos?', '¿La ubicación y el número de comederos permiten el acceso de todo el grupo?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-04', 'C1', 1, 'Cantidad de alimento', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Estimación de la ración ofrecida frente a los requerimientos del grupo y observación del consumo y la saciedad.', JSON_ARRAY('¿La cantidad de alimento ofrecida cubre los requerimientos del grupo?', '¿Se observan signos de competencia, ansiedad o alimento insuficiente?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-05', 'C1', 1, 'Frecuencia de alimentación', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Entrevista al personal y revisión del registro o programación de alimentación, contrastados con la observación en campo.', JSON_ARRAY('¿La frecuencia de alimentación es constante y adecuada a la especie y categoría?', '¿Existe un registro o programación verificable de las raciones?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-06', 'C1', 2, 'Refugio / sombra', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de la sombra natural o artificial disponible y del uso que hacen los animales en las horas de mayor radiación.', JSON_ARRAY('¿Todos los animales disponen de sombra suficiente en las horas críticas?', '¿La sombra es accesible y no genera competencia ni hacinamiento?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-07', 'C1', 2, 'Protección contra lluvia', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección de techos, aleros y refugios; observación del comportamiento de los animales durante la lluvia.', JSON_ARRAY('¿Las instalaciones protegen a los animales de la lluvia directa?', '¿Existen áreas secas disponibles para todo el grupo?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-08', 'C1', 2, 'Ventilación', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Evaluación visual y sensorial de la ventilación (olores, humedad, condensación) y del diseño de aberturas.', JSON_ARRAY('¿El alojamiento tiene ventilación suficiente y sin corrientes fuertes?', '¿Se perciben olores intensos a amoníaco o humedad excesiva?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-09', 'C1', 2, 'Temperatura adecuada', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Medición de temperatura y observación de signos de estrés térmico (sudoración, jadeo, agrupamiento).', JSON_ARRAY('¿La temperatura del alojamiento es adecuada para la especie y categoría?', '¿Se observan signos de estrés por frío o por calor?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-10', 'C1', 2, 'Superficie de descanso', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Medición de la superficie de descanso y comparación con el número y tamaño de los animales.', JSON_ARRAY('¿Cada animal dispone de superficie suficiente para echarse y descansar?', '¿La superficie es cómoda, seca y de fácil acceso?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-11', 'C1', 2, 'Cama seca', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección de la cama: sequedad, limpieza, espesor y frecuencia de cambio.', JSON_ARRAY('¿La cama está seca y limpia?', '¿Se cambia o renueva con la frecuencia necesaria?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-12', 'C1', 2, 'Espacio por animal (Tabla 3)', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Medición de áreas y comparación con la Tabla 3 de la norma ICA para la categoría evaluada.', JSON_ARRAY('¿El espacio disponible cumple con la Tabla 3 de la norma ICA?', '¿Se respeta el espacio individual en comederos y zonas de descanso?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-13', 'C1', 2, 'Piso no resbaladizo', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección y prueba de tracción del piso en zonas de paso, descanso y alimentación.', JSON_ARRAY('¿El piso ofrece tracción segura y está libre de desniveles?', '¿Se observan resbalones o caídas atribuibles al piso?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-14', 'C1', 2, 'Drenajes', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Verificación de drenajes, pendientes y acumulación de agua o lodo en las instalaciones.', JSON_ARRAY('¿Los drenajes funcionan y evitan encharcamientos?', '¿Las zonas de paso y descanso permanecen secas?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-15', 'C1', 2, 'Limpieza de instalaciones', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección de limpieza general, presencia de residuos, polvo y acumulación de estiércol.', JSON_ARRAY('¿Las instalaciones se mantienen limpias y sin acumulación de estiércol?', '¿Existe una rutina o plan de limpieza verificable?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-16', 'C1', 2, 'Ausencia de objetos cortopunzantes', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Recorrido visual por instalaciones y potreros en busca de objetos que puedan lesionar a los animales.', JSON_ARRAY('¿Están ausentes clavos, alambres, vidrios o bordes cortantes?', '¿Las instalaciones y cercas están en buen estado y sin puntas expuestas?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-17', 'C1', 2, 'Área de ejercicio', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de la disponibilidad y uso de áreas de movimiento o ejercicio.', JSON_ARRAY('¿Los animales disponen de área suficiente para moverse y ejercitarse?', '¿El área es segura y accesible para todo el grupo?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-18', 'C1', 2, 'Transporte sin hacinamiento', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Revisión documental de la guía de movilización y del registro de transporte; verificación visual de la densidad de carga.', JSON_ARRAY('¿La densidad de animales en el transporte permite postura y ventilación adecuadas?', '¿Se cuenta con guía de movilización y registro del transporte?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-19', 'C1', 2, 'Aperos sin daño', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección de aperos, monturas y arreos en contacto con el animal.', JSON_ARRAY('¿Los aperos están en buen estado y ajustados sin causar lesiones?', '¿Se revisan y reemplazan los elementos desgastados?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-20', 'C1', 3, 'Inspección sanitaria general', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Examen visual general de los animales muestreados (ojos, mucosas, pelaje, postura, apetito).', JSON_ARRAY('¿Los animales muestran un estado sanitario general adecuado?', '¿Se identifican signos de enfermedad o decaimiento?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-21', 'C1', 3, 'Cojera / locomoción', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de la marcha y evaluación de la cojera en los animales muestreados.', JSON_ARRAY('¿Los animales caminan sin cojera ni dolor evidente?', '¿Se identifican alteraciones de la locomoción?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-22', 'C1', 3, 'Lesiones en piel', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección visual de la piel y del pelaje en todo el cuerpo del animal.', JSON_ARRAY('¿La piel y el pelaje están sanos, sin lesiones ni dermatitis?', '¿Se observan zonas de alopecia, costras o inflamación?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-23', 'C1', 3, 'Heridas abiertas', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección visual y registro de heridas abiertas o sangrantes.', JSON_ARRAY('¿Se observan heridas abiertas sin tratamiento?', '¿Las heridas existentes reciben atención oportuna?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-24', 'C1', 3, 'Parásitos externos', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección visual de piel, crin y orejas; revisión del registro de control de parásitos externos.', JSON_ARRAY('¿Se observan garrapatas, ácaros, piojos o moscas en cantidad relevante?', '¿Existe control y registro de parásitos externos?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-25', 'C1', 3, 'Parásitos internos', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Revisión documental del plan de desparasitación y de los resultados de coprológicos; verificación visual complementaria.', JSON_ARRAY('¿Se aplica un plan de desparasitación interna vigente?', '¿Se cuenta con registro o diagnóstico de parásitos internos?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-26', 'C1', 3, 'Vacunación vigente', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Revisión documental del certificado o registro de vacunación y contraste con el inventario del predio.', JSON_ARRAY('¿La vacunación está vigente según la especie y la zona?', '¿Existe certificado o registro firmado por el profesional?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-27', 'C1', 3, 'Cuidado de cascos', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación del estado de los cascos y revisión del registro de recorte o herrado.', JSON_ARRAY('¿Los cascos están en buen estado y con recorte oportuno?', '¿Se registra el mantenimiento de cascos?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-28', 'C1', 3, 'Cojinete plantar', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección del cojinete plantar y de la planta del casco.', JSON_ARRAY('¿El cojinete plantar está sano y sin lesiones?', '¿Se observan signos de dolor o inflamación en la planta?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-29', 'C1', 3, 'Ausencia de prácticas dolorosas', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Entrevista y observación de las prácticas de manejo; revisión de protocolos.', JSON_ARRAY('¿Se evitan prácticas dolorosas no justificadas (punciones, mutilaciones)?', '¿Las prácticas permitidas se realizan con analgesia y protocolo?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-30', 'C1', 3, 'No uso de bozal permanente', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación del uso de bozal y del tiempo que permanece puesto.', JSON_ARRAY('¿Se evita el bozal permanente o por periodos prolongados?', '¿El bozal, cuando se usa, permite respirar, beber y comer?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-31', 'C1', 3, 'No uso de fusta/espuelas que lesionan', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de los aperos de manejo y de las lesiones asociadas.', JSON_ARRAY('¿Se evita el uso de fusta o espuelas que causen lesiones?', '¿Los elementos de manejo están diseñados para no dañar al animal?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-32', 'C1', 3, 'Manejo veterinario', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Revisión documental del protocolo de manejo veterinario y de la atención de casos; verificación de la programación.', JSON_ARRAY('¿Existe un protocolo de manejo veterinario y plan de contingencia?', '¿Se cuenta con atención veterinaria oportuna y registrada?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-33', 'C1', 3, 'Medicamentos y tiempos de retiro', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Revisión documental de los registros de tratamientos, dosis, fechas y tiempos de retiro.', JSON_ARRAY('¿Los medicamentos se aplican con prescripción y registro?', '¿Se respetan los tiempos de retiro antes de faena o consumo?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-34', 'C1', 3, 'Registro de morbilidad', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Revisión documental de historias clínicas y del registro de morbilidad del predio.', JSON_ARRAY('¿Se registran los casos de enfermedad y su evolución?', '¿El registro permite trazabilidad de tratamientos y resultados?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-35', 'C1', 3, 'Nutrición y enfermedad', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Análisis de la relación entre la dieta y la presencia de enfermedades metabólicas o carenciales.', JSON_ARRAY('¿La nutrición se ajusta para prevenir enfermedades carenciales?', '¿Se identifican casos asociados a deficiencias o excesos alimenticios?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-36', 'C1', 4, 'Ausencia de miedo al personal', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de la reacción de los animales ante la presencia y el manejo del personal.', JSON_ARRAY('¿Los animales se acercan o permanecen tranquilos ante el personal?', '¿Se observan respuestas de huida, agresividad o estrés?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-37', 'C1', 4, 'Manejo sin violencia', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de las prácticas de manejo y entrevista al personal.', JSON_ARRAY('¿El manejo se realiza sin golpes, gritos ni tirones bruscos?', '¿El personal está capacitado en manejo de bajo estrés?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-38', 'C1', 4, 'Ruidos y sobresaltos', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación del entorno y de la reacción de los animales ante ruidos y estímulos repentinos.', JSON_ARRAY('¿El entorno está libre de ruidos repentinos o fuentes de sobresalto?', '¿Los animales muestran sobresaltos frecuentes?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-39', 'C1', 5, 'Expresión de conducta natural', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación del comportamiento en el hábitat y de la posibilidad de expresar conductas propias de la especie.', JSON_ARRAY('¿Los animales pueden expresar conductas naturales (pastar, revolcarse, socializar)?', '¿El manejo o las instalaciones impiden la expresión de esas conductas?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-40', 'C1', 5, 'Contacto social con otros équidos', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de la composición de los grupos y de las interacciones sociales.', JSON_ARRAY('¿Los animales se mantienen en grupos compatibles?', '¿Se evita el aislamiento social innecesario?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-41', 'C1', 5, 'Libertad de movimiento', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Medición del espacio disponible y observación de la movilidad de los animales.', JSON_ARRAY('¿Los animales pueden moverse, caminar y cambiar de postura libremente?', '¿El espacio o los amarres limitan el movimiento?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-42', 'C1', 5, 'Ausencia de estereotipias', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de conductas repetitivas (balanceo, morder barrotes, coprofagia) y de su frecuencia.', JSON_ARRAY('¿Se observan estereotipias o conductas repetitivas?', '¿Se investigan y corrigen sus causas?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('I-43', 'C1', 5, 'Acceso a pastoreo', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de la disponibilidad de pastoreo y del tiempo de acceso.', JSON_ARRAY('¿Los animales tienen acceso a pastoreo según su categoría?', '¿El tiempo de pastoreo es suficiente y seguro?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-01', 'C2', 1, 'Disponibilidad de agua', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación directa de bebederos, fuentes y conducta de bebida del grupo muestreado, en al menos dos momentos del día.', JSON_ARRAY('¿Todos los équidos tienen acceso permanente a agua limpia y fresca?', '¿Los bebederos o fuentes son suficientes y están bien ubicados para todo el grupo?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-02', 'C2', 1, 'Calidad del agua', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Verificación visual del agua y revisión documental del análisis de laboratorio vigente (pH, sólidos, coliformes).', JSON_ARRAY('¿El agua está limpia, sin olores, coloración ni residuos visibles?', '¿Se cuenta con un análisis de calidad del agua vigente y firmado?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-03', 'C2', 1, 'Acceso a alimento', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de comederos, pasturas y rutas de acceso; verificación de que ningún animal queda excluido.', JSON_ARRAY('¿Todos los animales pueden acceder al alimento sin competencia ni bloqueos?', '¿La ubicación y el número de comederos permiten el acceso de todo el grupo?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-04', 'C2', 1, 'Cantidad de alimento', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Estimación de la ración ofrecida frente a los requerimientos del grupo y observación del consumo y la saciedad.', JSON_ARRAY('¿La cantidad de alimento ofrecida cubre los requerimientos del grupo?', '¿Se observan signos de competencia, ansiedad o alimento insuficiente?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-05', 'C2', 1, 'Frecuencia de alimentación', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Entrevista al personal y revisión del registro o programación de alimentación, contrastados con la observación en campo.', JSON_ARRAY('¿La frecuencia de alimentación es constante y adecuada a la especie y categoría?', '¿Existe un registro o programación verificable de las raciones?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-06', 'C2', 2, 'Refugio / sombra', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de la sombra natural o artificial disponible y del uso que hacen los animales en las horas de mayor radiación.', JSON_ARRAY('¿Todos los animales disponen de sombra suficiente en las horas críticas?', '¿La sombra es accesible y no genera competencia ni hacinamiento?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-07', 'C2', 2, 'Protección contra lluvia', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección de techos, aleros y refugios; observación del comportamiento de los animales durante la lluvia.', JSON_ARRAY('¿Las instalaciones protegen a los animales de la lluvia directa?', '¿Existen áreas secas disponibles para todo el grupo?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-08', 'C2', 2, 'Ventilación', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Evaluación visual y sensorial de la ventilación (olores, humedad, condensación) y del diseño de aberturas.', JSON_ARRAY('¿El alojamiento tiene ventilación suficiente y sin corrientes fuertes?', '¿Se perciben olores intensos a amoníaco o humedad excesiva?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-09', 'C2', 2, 'Temperatura adecuada', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Medición de temperatura y observación de signos de estrés térmico (sudoración, jadeo, agrupamiento).', JSON_ARRAY('¿La temperatura del alojamiento es adecuada para la especie y categoría?', '¿Se observan signos de estrés por frío o por calor?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-10', 'C2', 3, 'Inspección sanitaria general', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Examen visual general de los animales muestreados (ojos, mucosas, pelaje, postura, apetito).', JSON_ARRAY('¿Los animales muestran un estado sanitario general adecuado?', '¿Se identifican signos de enfermedad o decaimiento?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-11', 'C2', 3, 'Cojera / locomoción', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de la marcha y evaluación de la cojera en los animales muestreados.', JSON_ARRAY('¿Los animales caminan sin cojera ni dolor evidente?', '¿Se identifican alteraciones de la locomoción?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-12', 'C2', 3, 'Lesiones en piel', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección visual de la piel y del pelaje en todo el cuerpo del animal.', JSON_ARRAY('¿La piel y el pelaje están sanos, sin lesiones ni dermatitis?', '¿Se observan zonas de alopecia, costras o inflamación?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-13', 'C2', 3, 'Heridas abiertas', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección visual y registro de heridas abiertas o sangrantes.', JSON_ARRAY('¿Se observan heridas abiertas sin tratamiento?', '¿Las heridas existentes reciben atención oportuna?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-14', 'C2', 3, 'Parásitos externos', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección visual de piel, crin y orejas; revisión del registro de control de parásitos externos.', JSON_ARRAY('¿Se observan garrapatas, ácaros, piojos o moscas en cantidad relevante?', '¿Existe control y registro de parásitos externos?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-15', 'C2', 3, 'Parásitos internos', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Revisión documental del plan de desparasitación y de los resultados de coprológicos; verificación visual complementaria.', JSON_ARRAY('¿Se aplica un plan de desparasitación interna vigente?', '¿Se cuenta con registro o diagnóstico de parásitos internos?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-16', 'C2', 3, 'Vacunación vigente', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Revisión documental del certificado o registro de vacunación y contraste con el inventario del predio.', JSON_ARRAY('¿La vacunación está vigente según la especie y la zona?', '¿Existe certificado o registro firmado por el profesional?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-17', 'C2', 3, 'Cuidado de cascos', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación del estado de los cascos y revisión del registro de recorte o herrado.', JSON_ARRAY('¿Los cascos están en buen estado y con recorte oportuno?', '¿Se registra el mantenimiento de cascos?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-18', 'C2', 3, 'Cojinete plantar', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección del cojinete plantar y de la planta del casco.', JSON_ARRAY('¿El cojinete plantar está sano y sin lesiones?', '¿Se observan signos de dolor o inflamación en la planta?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-19', 'C2', 3, 'Ausencia de prácticas dolorosas', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Entrevista y observación de las prácticas de manejo; revisión de protocolos.', JSON_ARRAY('¿Se evitan prácticas dolorosas no justificadas (punciones, mutilaciones)?', '¿Las prácticas permitidas se realizan con analgesia y protocolo?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-20', 'C2', 3, 'No uso de bozal permanente', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación del uso de bozal y del tiempo que permanece puesto.', JSON_ARRAY('¿Se evita el bozal permanente o por periodos prolongados?', '¿El bozal, cuando se usa, permite respirar, beber y comer?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-21', 'C2', 3, 'No uso de fusta/espuelas que lesionan', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de los aperos de manejo y de las lesiones asociadas.', JSON_ARRAY('¿Se evita el uso de fusta o espuelas que causen lesiones?', '¿Los elementos de manejo están diseñados para no dañar al animal?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-22', 'C2', 3, 'Manejo veterinario', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Revisión documental del protocolo de manejo veterinario y de la atención de casos; verificación de la programación.', JSON_ARRAY('¿Existe un protocolo de manejo veterinario y plan de contingencia?', '¿Se cuenta con atención veterinaria oportuna y registrada?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-23', 'C2', 3, 'Medicamentos y tiempos de retiro', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Revisión documental de los registros de tratamientos, dosis, fechas y tiempos de retiro.', JSON_ARRAY('¿Los medicamentos se aplican con prescripción y registro?', '¿Se respetan los tiempos de retiro antes de faena o consumo?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-24', 'C2', 3, 'Registro de morbilidad', 'documental', 'documental', JSON_ARRAY(0,20,55,100), 'Revisión documental de historias clínicas y del registro de morbilidad del predio.', JSON_ARRAY('¿Se registran los casos de enfermedad y su evolución?', '¿El registro permite trazabilidad de tratamientos y resultados?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-25', 'C2', 3, 'Nutrición y enfermedad', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Análisis de la relación entre la dieta y la presencia de enfermedades metabólicas o carenciales.', JSON_ARRAY('¿La nutrición se ajusta para prevenir enfermedades carenciales?', '¿Se identifican casos asociados a deficiencias o excesos alimenticios?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-26', 'C2', 3, 'Lesiones por aperos', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Inspección de las zonas de contacto con aperos y revisión de las lesiones presentes.', JSON_ARRAY('¿Se observan lesiones atribuibles a monturas o arreos?', '¿Se ajustan o cambian los aperos que generan daño?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-27', 'C2', 4, 'Ausencia de miedo al personal', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de la reacción de los animales ante la presencia y el manejo del personal.', JSON_ARRAY('¿Los animales se acercan o permanecen tranquilos ante el personal?', '¿Se observan respuestas de huida, agresividad o estrés?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-28', 'C2', 4, 'Manejo sin violencia', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de las prácticas de manejo y entrevista al personal.', JSON_ARRAY('¿El manejo se realiza sin golpes, gritos ni tirones bruscos?', '¿El personal está capacitado en manejo de bajo estrés?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-29', 'C2', 4, 'Ruidos y sobresaltos', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación del entorno y de la reacción de los animales ante ruidos y estímulos repentinos.', JSON_ARRAY('¿El entorno está libre de ruidos repentinos o fuentes de sobresalto?', '¿Los animales muestran sobresaltos frecuentes?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-30', 'C2', 5, 'Expresión de conducta natural', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación del comportamiento en el hábitat y de la posibilidad de expresar conductas propias de la especie.', JSON_ARRAY('¿Los animales pueden expresar conductas naturales (pastar, revolcarse, socializar)?', '¿El manejo o las instalaciones impiden la expresión de esas conductas?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-31', 'C2', 5, 'Contacto social con otros équidos', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Observación de la composición de los grupos y de las interacciones sociales.', JSON_ARRAY('¿Los animales se mantienen en grupos compatibles?', '¿Se evita el aislamiento social innecesario?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE),
  ('II-32', 'C2', 5, 'Libertad de movimiento', 'visual', 'campo', JSON_ARRAY(0,20,55,100), 'Medición del espacio disponible y observación de la movilidad de los animales.', JSON_ARRAY('¿Los animales pueden moverse, caminar y cambiar de postura libremente?', '¿El espacio o los amarres limitan el movimiento?'), '[{"score":100,"etiqueta":"Excelente","clasificacion":"Excelente","desc":"Cumple plenamente el indicador"},{"score":55,"etiqueta":"Medio","clasificacion":"Medio","desc":"Cumple parcialmente el indicador"},{"score":20,"etiqueta":"Bajo","clasificacion":"Bajo","desc":"Cumple mínimamente el indicador"},{"score":0,"etiqueta":"Bajo (no cumple)","clasificacion":"Bajo","desc":"No cumple / situación crítica"}]', 'ICA-V2-2023', TRUE)
ON DUPLICATE KEY UPDATE
  capitulo = VALUES(capitulo),
  id_libertad = VALUES(id_libertad),
  descripcion = VALUES(descripcion),
  metodo = VALUES(metodo),
  fase = VALUES(fase),
  opciones_puntaje = VALUES(opciones_puntaje),
  metodologia = VALUES(metodologia),
  preguntas = VALUES(preguntas),
  escala_calificacion = VALUES(escala_calificacion),
  version = VALUES(version),
  activo = VALUES(activo);

-- 19.4 Documentos de la Etapa III (D1–D7)
INSERT INTO catalogo_documento (codigo, nombre, descripcion, obligatorio, activo) VALUES
  ('D1', 'Certificado o registro de vacunación', NULL, TRUE, TRUE),
  ('D2', 'Registro de tratamientos veterinarios y tiempos de retiro', NULL, TRUE, TRUE),
  ('D3', 'Historias clínicas y registro de morbilidad', NULL, TRUE, TRUE),
  ('D4', 'Registro de desparasitación', NULL, TRUE, TRUE),
  ('D5', 'Análisis de calidad del agua', NULL, TRUE, TRUE),
  ('D6', 'Protocolo de manejo y bienestar / plan de contingencia', NULL, TRUE, TRUE),
  ('D7', 'Guía de movilización y registro de transporte', NULL, TRUE, TRUE)
ON DUPLICATE KEY UPDATE
  nombre = VALUES(nombre),
  descripcion = VALUES(descripcion),
  obligatorio = VALUES(obligatorio),
  activo = VALUES(activo);

-- 19.5 Mapeo documento → indicador(es) documentales
INSERT IGNORE INTO catalogo_documento_indicador (codigo_documento, codigo_indicador) VALUES
  ('D1', 'I-26'),
  ('D1', 'II-16'),
  ('D2', 'I-33'),
  ('D2', 'II-23'),
  ('D3', 'I-34'),
  ('D3', 'II-24'),
  ('D4', 'I-25'),
  ('D4', 'II-15'),
  ('D5', 'I-02'),
  ('D5', 'II-02'),
  ('D6', 'I-32'),
  ('D6', 'II-22'),
  ('D7', 'I-18');

-- ============================================================================
-- 20. VERIFICACIÓN RÁPIDA
-- Ejecute estas consultas después de crear la base para confirmar los datos.
-- ============================================================================
-- SELECT 'Libertades' AS entidad, COUNT(*) AS total, SUM(peso) AS detalle FROM libertades
-- UNION ALL
-- SELECT 'Indicadores C1', COUNT(*), NULL FROM indicadores_checklist WHERE capitulo = 'C1'
-- UNION ALL
-- SELECT 'Indicadores C2', COUNT(*), NULL FROM indicadores_checklist WHERE capitulo = 'C2'
-- UNION ALL
-- SELECT 'Documentos', COUNT(*), NULL FROM catalogo_documento;
--
-- SELECT * FROM vw_validacion_pesos;
-- SELECT * FROM vw_tamano_muestra_finca;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================
