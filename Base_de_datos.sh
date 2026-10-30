#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Ejecuta como root"
  exit 1
fi

apt update
apt install -y mariadb-server

systemctl enable mariadb
systemctl start mariadb

mysql <<'EOF'
CREATE DATABASE IF NOT EXISTS datacenter
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_general_ci;

USE datacenter;

CREATE TABLE IF NOT EXISTS Usuarios (
  id INT AUTO_INCREMENT PRIMARY KEY,
  usuario VARCHAR(50) NOT NULL,
  password VARCHAR(50) NOT NULL,
  rol ENUM('Admin_pasarela','Admin_backup','Admin_monitoreo','Admin_telefonia') NOT NULL
);

CREATE TABLE IF NOT EXISTS Personal (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  usuario VARCHAR(50) NOT NULL,
  area VARCHAR(50) NOT NULL,
  telefono VARCHAR(20),
  password VARCHAR(100)
);

INSERT INTO Usuarios (usuario, password, rol) VALUES
('AdminNJC', '#Nelson47124712.', 'Admin_pasarela'),
('AdminKVA', '#Kevin47124712.', 'Admin_backup'),
('AdminKVA', '#Kevin47124712.', 'Admin_monitoreo'),
('AdminBGS', '#Brayan47124712.', 'Admin_telefonia');

INSERT INTO Personal (nombre, usuario, area, telefono, password) VALUES
('Administrador Pasarela', 'AdminNJC', 'Pasarela / Red', '7218-0346', '#Nelson47124712.'),
('Kevin Mejía', 'AdminKVA', 'Respaldos', '6190-1999', '#Kevin47124712.'),
('Kevin Mejía', 'AdminKVA', 'Monitoreo', '6190-1999', '#Kevin47124712.'),
('Bryan Steven', 'AdminBGS', 'Telefonía', '6080-6244', '#Brayan47124712.');
EOF

echo "Base de datos creada correctamente."
