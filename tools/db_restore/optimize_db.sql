-- Proceso de optimización y limpieza de las tablas (MySQL)

-- Limpieza de campos de texto
UPDATE cxc_facturaelectronica
SET texto_cs_facturacion = '',
    texto_xml_debug = '',
    texto_xml = '';

UPDATE cxc_ingreso
SET texto_xml = '',
    xml_acuse_cancelacion = '';

-- Ajustes de empresa
UPDATE cat_empresa
SET cs_facturacion_password = 'MIN181018TM6',
    multifacturas_produccion = 'NO';

-- Limpieza de logs de timbrado
TRUNCATE TABLE cat_timbradolog;

-- Mantenimiento de tablas
FLUSH TABLE `cxc_facturaelectronica`;
OPTIMIZE TABLE `cxc_facturaelectronica`;
OPTIMIZE TABLE `cxc_ingreso`;

-- Tabla wms_globalwmsuuid (se recrea)
DROP TABLE IF EXISTS `wms_globalwmsuuid`;

CREATE TABLE `wms_globalwmsuuid` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `wms_uuid` CHAR(36) NOT NULL,
  `lote` VARCHAR(50) NOT NULL,
  `empresa` INT NOT NULL,
  `articulo_id` INT NOT NULL,
  `unidad_medida` VARCHAR(50) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ux_lote_emp_art_um` (`lote`, `empresa`, `articulo_id`, `unidad_medida`),
  UNIQUE KEY `ux_wms_uuid_emp` (`wms_uuid`, `empresa`)
) ENGINE=InnoDB;

CREATE INDEX `ix_wms_globalwmsuuid_empresa`
  ON `wms_globalwmsuuid` (`empresa`);

CREATE INDEX `ix_wms_globalwmsuuid_lote`
  ON `wms_globalwmsuuid` (`lote`);

CREATE INDEX `ix_wms_globalwmsuuid_articulo_id`
  ON `wms_globalwmsuuid` (`articulo_id`);

-- Actualizaciones de QA
-- Password para todos los usuarios (hash de ejemplo)
UPDATE auth_user au
SET au.password = 'pbkdf2_sha256$30000$OLsxEa86TSHt$X8sQMyivIiJF2TkU2CQ8oQUlnfzTDkpL6+yedzAeU50='
WHERE au.id > 0;
DELETE FROM cat_userhashpassword WHERE id > 0;

-- URLs de interfaces externas para QA
UPDATE cat_interfazexterna ci
SET ci.url = CASE
  WHEN ci.nombre LIKE 'Insumos Inc' THEN 'url'
  WHEN ci.nombre LIKE 'Insumos' THEN 'url'
  WHEN ci.nombre LIKE 'MSC Inc' THEN 'http://127.0.0.1:8080'
  WHEN ci.nombre LIKE 'MSC Mx' THEN 'http://127.0.0.1:8000'
  ELSE ci.url
END;

-- Parámetros de empresa para pruebas de facturación
UPDATE cat_empresa ce
SET
  ce.multifacturas_produccion = 'NO',
  ce.multifacturas_pass = 'sR@$QV6J'
WHERE ce.id > 0;

-- Correos de prueba en todas las entidades
UPDATE auth_user au SET au.email = 'achavira@mscdirect.com.mx' WHERE au.id > 0;
UPDATE cat_profile cp SET cp.correo_electronico = 'achavira@mscdirect.com.mx' WHERE cp.id > 0;
UPDATE rel_persona rp SET rp.email = 'achavira@mscdirect.com.mx' WHERE rp.id > 0;
UPDATE rel_personaemail rp SET rp.email = 'achavira@mscdirect.com.mx' WHERE rp.id > 0;
UPDATE cxc_cliente cc SET cc.email_contacto_pagos = 'achavira@mscdirect.com.mx' WHERE cc.id > 0;

-- Tabla de logs generales (se recrea)
DROP TABLE IF EXISTS `log_optimizacion`;

CREATE TABLE `log_optimizacion` (
  `id`                  INT NOT NULL AUTO_INCREMENT,
  `mensaje`             VARCHAR(255) NOT NULL,
  `nombre_backup`       VARCHAR(255) DEFAULT NULL,
  `ref_backup`          VARCHAR(100) DEFAULT NULL,
  `fecha_optimizacion`  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;

-- @backup_nombre y @ref_backup se inyectan desde restore_db.sh vía --init-command
INSERT INTO `log_optimizacion` (`mensaje`, `nombre_backup`, `ref_backup`)
VALUES (
  'Base de datos actualizada',
  NULLIF(@backup_nombre, ''),
  NULLIF(@ref_backup, '')
);