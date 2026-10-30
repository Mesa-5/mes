sudo apt update
sudo apt install -y mariadb-server
  
CREATE DATABASE IF NOT EXISTS DataCenter
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_general_ci;

USE datacenter;

-- =========================
-- TABLAS
-- =========================

CREATE TABLE usuarios (
  id INT AUTO_INCREMENT PRIMARY KEY,
  usuario VARCHAR(50) NOT NULL,
  password VARCHAR(50) NOT NULL,
  rol ENUM(
    'admin_pasarela',
    'admin_backup',
    'admin_monitoreo',
    'admin_telefonia'
  ) NOT NULL
);

CREATE TABLE personal (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  usuario VARCHAR(50) NOT NULL,
  area VARCHAR(50) NOT NULL,
  telefono VARCHAR(20),
  password VARCHAR(100)
);

-- =========================
-- DATOS
-- =========================

INSERT INTO usuarios (usuario, password, rol) VALUES
('AdminNJ', '#Nelson47124712.', 'admin_pasarela'),
('AdminKV', '#Kevin47124712.',  'admin_backup'),
('AdminKV', '#Kevin47124712.',  'admin_monitoreo'),
('AdminBG', '#Brayan47124712.', 'admin_telefonia');

INSERT INTO personal (nombre, usuario, area, telefono, password) VALUES
('Administrador Pasarela', 'AdminNJ', 'Pasarela / Red', '7218-0346', '#Nelson47124712.'),
('Kevin Mejía',            'AdminKV', 'Respaldos',      '6190-1999', '#Kevin47124712.'),
('Kevin Mejía',            'AdminKV', 'Monitoreo',      '6190-1999', '#Kevin47124712.'),
('Bryan Steven',           'AdminBG', 'Telefonía',      '6080-6244', '#Brayan47124712.');
