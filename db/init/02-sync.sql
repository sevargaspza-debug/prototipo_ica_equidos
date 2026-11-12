-- ============================================================================
-- CAPA DE SINCRONIZACIÓN — PROTOTIPO ↔ MARIADB
-- Sistema ICA de Bienestar Animal en Équidos · Modelo V3
-- Motor: MariaDB 10.6+ / 11.x / 13.x
-- ============================================================================
-- Este script es ADITIVO: no elimina ni modifica las tablas del modelo V3.
-- Agrega:
--   1. Tabla estado_aplicacion: respaldo JSON exacto del estado del prototipo.
--   2. Usuario de aplicación ica_app con permisos mínimos sobre ica_equidos.
--
-- Ejecución:
--   mariadb -u root -p < Script_BD_ICA_Equidos_V3_MariaDB_Sync.sql
-- ============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

USE ica_equidos;

-- ----------------------------------------------------------------------------
-- 1. ESTADO DE LA APLICACIÓN
-- Una fila por usuario. Guarda el estado completo del prototipo para que la
-- interfaz pueda restaurarse exactamente (incluye finca activa, evaluación
-- actual, respuestas, documentos y plan de mejora).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS estado_aplicacion (
  usuario VARCHAR(150) NOT NULL,
  estado_json JSON NOT NULL,
  version INT UNSIGNED NOT NULL DEFAULT 1,
  actualizado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (usuario)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Respaldo JSON del estado del prototipo para sincronización';

-- ----------------------------------------------------------------------------
-- 2. USUARIO DE APLICACIÓN
-- La contraseña es local y debe cambiarse antes de exponer el servicio fuera
-- del equipo. Si ya existe, CREATE USER IF NOT EXISTS no la modifica.
-- ----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'ica_app'@'127.0.0.1' IDENTIFIED BY 'IcaApp2026!';
CREATE USER IF NOT EXISTS 'ica_app'@'localhost' IDENTIFIED BY 'IcaApp2026!';

GRANT SELECT, INSERT, UPDATE, DELETE
  ON ica_equidos.* TO 'ica_app'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE, DELETE
  ON ica_equidos.* TO 'ica_app'@'localhost';

FLUSH PRIVILEGES;
