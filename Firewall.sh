#!/bin/bash
set -o pipefail

if [ "$EUID" -ne 0 ]; then
echo "Ejecuta como root: sudo bash menu-proyecto.sh"
exit 1
fi

Pausa() {
echo ""
read -r -p "Presiona Enter para continuar..."
}

DetectarInterfaces() {
mapfile -t WIFI_IFACES < <(ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -E '^(wl|wlan)' || true)
mapfile -t ETH_IFACES < <(ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -E '^(en|eth)' || true)
}

CrearBaseDatos() {
clear
echo "======================================"
echo "     CREAR BASE DE DATOS MARIADB"
echo "======================================"
apt update
apt install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb
mysql <<'EOF'
CREATE DATABASE IF NOT EXISTS datacenter CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
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
Pausa
}

ActivarAntena() {
clear
echo "=========================================="
echo " INSTALADOR RTL8852BU"
echo "=========================================="
INTERFAZ_USB="wlxc83a35b1136d"
MODULO="8852bu"
DIRECTORIO="/usr/local/src/rtl8852bu"
apt update
apt install -y build-essential dkms git bc iw rfkill libelf-dev "linux-headers-$(uname -r)" linux-headers-generic
mkdir -p /usr/local/src
if [ -d "$DIRECTORIO/.git" ]; then
git -C "$DIRECTORIO" pull --ff-only || true
else
rm -rf "$DIRECTORIO"
git clone --depth 1 https://github.com/oe-alliance-drivers/rtl8852bu.git "$DIRECTORIO"
fi
cd "$DIRECTORIO" || return 1
bash ./install-driver.sh || { echo "Falló la instalación del driver"; Pausa; return 1; }
depmod -a
modprobe "$MODULO" || true
sleep 3
if ip link show "$INTERFAZ_USB" >/dev/null 2>&1; then
ip link set "$INTERFAZ_USB" up || true
echo "Antena USB activada."
ip -br link show "$INTERFAZ_USB"
else
echo "Módulo cargado, pero no aparece $INTERFAZ_USB"
ip -br link
fi
Pausa
}

Pasarela() {
clear
echo "======================================"
echo "       CONFIGURAR PASARELA"
echo "======================================"
DetectarInterfaces
echo "WiFi: ${WIFI_IFACES[*]:-Ninguna}"
echo "Ethernet: ${ETH_IFACES[*]:-Ninguna}"
if [ "${#WIFI_IFACES[@]}" -lt 1 ] || [ "${#ETH_IFACES[@]}" -lt 1 ]; then
echo "Faltan interfaces."
Pausa
return
fi
select LAN in "${ETH_IFACES[@]}"; do [ -n "$LAN" ] && break; done
select WAN1 in "${WIFI_IFACES[@]}"; do [ -n "$WAN1" ] && break; done
WAN2=""
if [ "${#WIFI_IFACES[@]}" -ge 2 ]; then
select OPCION_WAN2 in "${WIFI_IFACES[@]}" "Ninguno"; do
if [ "$OPCION_WAN2" = "Ninguno" ]; then WAN2=""; break
elif [ -n "$OPCION_WAN2" ] && [ "$OPCION_WAN2" != "$WAN1" ]; then WAN2="$OPCION_WAN2"; break
fi
done
fi
LAN_IP="192.168.50.1"
RED="192.168.50.0/24"
read -r -p "SSID proveedor 1: " SSID1
read -r -s -p "Pass proveedor 1: " PASS1; echo
SSID2=""; PASS2=""
if [ -n "$WAN2" ]; then
read -r -p "SSID proveedor 2: " SSID2
read -r -s -p "Pass proveedor 2: " PASS2; echo
fi
apt update
apt install -y kea-dhcp4-server iptables-persistent
cat > /etc/netplan/99-pasarela.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $LAN:
      dhcp4: false
      addresses: [$LAN_IP/24]
  wifis:
    $WAN1:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 100
      access-points:
        "$SSID1":
          password: "$PASS1"
EOF
if [ -n "$WAN2" ]; then
cat >> /etc/netplan/99-pasarela.yaml <<EOF
    $WAN2:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 200
      access-points:
        "$SSID2":
          password: "$PASS2"
EOF
fi
chmod 600 /etc/netplan/99-pasarela.yaml
netplan generate && netplan apply
sleep 5
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-pasarela.conf
sysctl -p /etc/sysctl.d/99-pasarela.conf
cat > /etc/kea/kea-dhcp4.conf <<EOF
{
  "Dhcp4": {
    "interfaces-config": { "interfaces": ["$LAN"] },
    "lease-database": { "type": "memfile", "persist": true, "name": "/var/lib/kea/kea-leases4.csv" },
    "valid-lifetime": 3600,
    "subnet4": [{
      "id": 1,
      "subnet": "$RED",
      "pools": [{ "pool": "192.168.50.100 - 192.168.50.200" }],
      "option-data": [
        { "name": "routers", "data": "$LAN_IP" },
        { "name": "domain-name-servers", "data": "8.8.8.8, 1.1.1.1" }
      ]
    }]
  }
}
EOF
kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
systemctl enable kea-dhcp4-server
systemctl restart kea-dhcp4-server
echo "Pasarela configurada."
ip -br address
Pausa
}

Firewall() {
clear
echo "======================================"
echo "         APLICAR FIREWALL"
echo "======================================"
DetectarInterfaces
RED="192.168.50.0/24"
DNS="8.8.8.8"
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X
iptables -P INPUT DROP
iptables -P OUTPUT ACCEPT
iptables -P FORWARD DROP
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A OUTPUT -p tcp --sport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 5666 -j ACCEPT
iptables -A INPUT -p udp --dport 5060 -j ACCEPT
iptables -A INPUT -p tcp --dport 5060 -j ACCEPT
iptables -A INPUT -p tcp --dport 5061 -j ACCEPT
iptables -A INPUT -p udp --dport 10000:20000 -j ACCEPT
iptables -A OUTPUT -p udp --dport 5060 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 5060 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 5061 -j ACCEPT
iptables -A OUTPUT -p udp --dport 10000:20000 -j ACCEPT
for E in "${ETH_IFACES[@]}"; do
iptables -A INPUT -i "$E" -p udp --dport 67 -j ACCEPT
iptables -A INPUT -i "$E" -p udp --dport 68 -j ACCEPT
done
for W in "${WIFI_IFACES[@]}"; do
for E in "${ETH_IFACES[@]}"; do
iptables -t nat -A POSTROUTING -s "$RED" -o "$W" -j MASQUERADE
iptables -A FORWARD -i "$E" -o "$W" -s "$RED" -j ACCEPT
iptables -A FORWARD -i "$W" -o "$E" -d "$RED" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
done
done
for E in "${ETH_IFACES[@]}"; do
iptables -t nat -A PREROUTING -i "$E" -s "$RED" -p udp --dport 53 -j DNAT --to-destination ${DNS}:53
iptables -t nat -A PREROUTING -i "$E" -s "$RED" -p tcp --dport 53 -j DNAT --to-destination ${DNS}:53
done
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-pasarela.conf
sysctl -p /etc/sysctl.d/99-pasarela.conf
apt install -y iptables-persistent >/dev/null 2>&1 || true
netfilter-persistent save
echo "Firewall aplicado."
Pausa
}

PrepararBackup() {
clear
echo "======================================"
echo "     PREPARAR RESPALDOS"
echo "======================================"
read -p "IP del servidor a respaldar: " IP_ORIGEN
read -p "Usuario SSH con sudo (ej: pasarela1): " USUARIO_ORIGEN
CARPETA_BACKUPS="/srv/backups/servidor1"
CARPETA_EXCL="/etc/rsync-backup"
LLAVE_SSH="/root/.ssh/rsync_backup"
mkdir -p "${CARPETA_BACKUPS}" "${CARPETA_EXCL}" /root/.ssh
chmod 700 /root/.ssh
cat > "${CARPETA_EXCL}/excluir.txt" <<EOF
*.tmp
*.cache
*.log
/proc
/sys
/dev
/run
/tmp
/var/tmp
/lost+found
EOF
if [ ! -f "${LLAVE_SSH}" ]; then
ssh-keygen -t ed25519 -f "${LLAVE_SSH}" -N "" -C "backup-automatico"
fi
chmod 600 "${LLAVE_SSH}"
chmod 644 "${LLAVE_SSH}.pub"
echo "Se pedirá la contraseña de ${USUARIO_ORIGEN}@${IP_ORIGEN}..."
ssh-copy-id -i "${LLAVE_SSH}.pub" "${USUARIO_ORIGEN}@${IP_ORIGEN}"
echo "Configurando SSH en el servidor origen con sudo..."
ssh -i "${LLAVE_SSH}" -o StrictHostKeyChecking=no "${USUARIO_ORIGEN}@${IP_ORIGEN}" "sudo -n bash -s" <<EOF
sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config
grep -q '^PubkeyAuthentication' /etc/ssh/sshd_config || echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
EOF
cat "${LLAVE_SSH}.pub" | ssh -i "${LLAVE_SSH}" -o StrictHostKeyChecking=no "${USUARIO_ORIGEN}@${IP_ORIGEN}" "sudo -n tee -a /root/.ssh/authorized_keys > /dev/null"
ssh -i "${LLAVE_SSH}" -o StrictHostKeyChecking=no "${USUARIO_ORIGEN}@${IP_ORIGEN}" "sudo -n systemctl restart ssh || sudo -n systemctl restart sshd"
sleep 2
echo "Probando acceso root..."
if ssh -i "${LLAVE_SSH}" -o BatchMode=yes -o StrictHostKeyChecking=no "root@${IP_ORIGEN}" "echo 'Conexion SSH root OK'"; then
echo "Preparación lista. Usa root@${IP_ORIGEN} en el respaldo."
else
echo "Root aún no entra. Prueba: ssh -i ${LLAVE_SSH} root@${IP_ORIGEN}"
fi
Pausa
}

EjecutarBackup() {
clear
echo "======================================"
echo "       RESPALDO INCREMENTAL"
echo "======================================"

read -r -p "Servidor origen (ej: root@192.168.50.1): " SERVIDOR_ORIGEN

if [ -z "$SERVIDOR_ORIGEN" ]; then
echo "Error: debes indicar el servidor origen."
Pausa
return 1
fi

RUTAS=(/etc /home /root /var/backups)

CARPETA_BACKUPS="/srv/backups/servidor1"
ARCHIVO_EXCLUSIONES="/etc/rsync-backup/excluir.txt"
LLAVE_SSH="/root/.ssh/rsync_backup"

CONSERVAR=24
FECHA=$(date +%Y-%m-%d_%H%M%S)

TEMPORAL="${CARPETA_BACKUPS}/en_progreso"
ULTIMO="${CARPETA_BACKUPS}/ultimo"
DESTINO="${CARPETA_BACKUPS}/${FECHA}"

mkdir -p "$CARPETA_BACKUPS"

exec 9>/run/lock/backup-mesa5.lock

if ! flock -n 9; then
echo "Ya existe un respaldo en ejecución."
Pausa
return 1
fi

if [ ! -f "$LLAVE_SSH" ]; then
echo "Error: no existe la llave SSH."
Pausa
return 1
fi

if [ ! -f "$ARCHIVO_EXCLUSIONES" ]; then
echo "Error: no existe el archivo de exclusiones."
Pausa
return 1
fi

echo "Comprobando conexión SSH..."

if ! ssh -i "$LLAVE_SSH" \
-o BatchMode=yes \
-o StrictHostKeyChecking=accept-new \
"$SERVIDOR_ORIGEN" "true"; then

Pausa
return 1
fi

if ! ssh -i "$LLAVE_SSH" \
-o BatchMode=yes \
"$SERVIDOR_ORIGEN" "command -v rsync >/dev/null"; then
echo "Error: RSYNC no está instalado en el servidor origen."
Pausa
return 1
fi

echo "Generando respaldo de MariaDB en el servidor origen..."
if ! ssh -i "$LLAVE_SSH" -o BatchMode=yes "$SERVIDOR_ORIGEN" 'set -e; command -v mariadb-dump >/dev/null; mkdir -p /var/backups/mariadb; chmod 700 /var/backups/mariadb; FECHA=$(date +%Y-%m-%d_%H%M%S); ARCHIVO="/var/backups/mariadb/datacenter_${FECHA}.sql"; mariadb-dump --single-transaction --routines --triggers datacenter > "$ARCHIVO"; test -s "$ARCHIVO"; mapfile -t LISTA < <(ls -1t /var/backups/mariadb/datacenter_*.sql 2>/dev/null || true); for ((i=24; i<${#LISTA[@]}; i++)); do rm -f -- "${LISTA[i]}"; done'; then
echo "Error: no se pudo respaldar la base de datos datacenter."
Pausa
return 1
fi

rm -rf "$TEMPORAL"
mkdir -p "$TEMPORAL"

echo ""
echo "Iniciando respaldo incremental..."
echo ""

for RUTA in "${RUTAS[@]}"; do

echo "Verificando: $RUTA"

if ! ssh -i "$LLAVE_SSH" \
-o BatchMode=yes \
"$SERVIDOR_ORIGEN" "test -d '$RUTA'"; then

echo "Error: no existe el directorio $RUTA en el origen."
rm -rf "$TEMPORAL"
Pausa
return 1
fi

echo "Copiando: $RUTA"

ENLACE=()

if [ -d "${ULTIMO}${RUTA}" ]; then
ENLACE=(--link-dest="${ULTIMO}${RUTA}")
fi

mkdir -p "${TEMPORAL}${RUTA}"

rsync -aHAX --numeric-ids --delete \
--exclude-from="$ARCHIVO_EXCLUSIONES" \
"${ENLACE[@]}" \
-e "ssh -i ${LLAVE_SSH} -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
"${SERVIDOR_ORIGEN}:${RUTA}/" \
"${TEMPORAL}${RUTA}/"

CODIGO=$?

if [ "$CODIGO" -ne 0 ]; then
echo ""
echo "ERROR en $RUTA. Código: $CODIGO"
echo "El respaldo no se guardará como completo."

rm -rf "$TEMPORAL"

Pausa
return 1
fi

done

if [ -e "$DESTINO" ]; then
echo "Error: ya existe un respaldo con esa fecha."
rm -rf "$TEMPORAL"
Pausa
return 1
fi

mv "$TEMPORAL" "$DESTINO"

ln -sfn "$FECHA" "$ULTIMO"

mapfile -t LISTA < <(
find "$CARPETA_BACKUPS" \
-mindepth 1 -maxdepth 1 \
-type d -name '20[0-9][0-9]-*' | sort
)

SOBRAN=$(( ${#LISTA[@]} - CONSERVAR ))

if [ "$SOBRAN" -gt 0 ]; then
for ((i=0; i<SOBRAN; i++)); do
rm -rf -- "${LISTA[i]}"
done
fi

echo ""
echo "======================================"
echo "   RESPALDO COMPLETADO CORRECTAMENTE"
echo "======================================"
echo "Ubicación: $DESTINO"
echo "Respaldos conservados: $CONSERVAR"
echo "Método: Incremental con hard links"

Pausa
}

ProgramarBackupHora() {
clear
echo "======================================"
echo "   PROGRAMAR RESPALDO CADA HORA"
echo "======================================"

SCRIPT_PATH="/root/backup-horario.sh"

cat > "$SCRIPT_PATH" <<'EOS'
#!/bin/bash

set -o pipefail

SERVIDOR_ORIGEN="root@192.168.50.1"

RUTAS=(/etc /home /root /var/backups)

CARPETA_BACKUPS="/srv/backups/servidor1"
ARCHIVO_EXCLUSIONES="/etc/rsync-backup/excluir.txt"
LLAVE_SSH="/root/.ssh/rsync_backup"

CONSERVAR=24

FECHA=$(date +%Y-%m-%d_%H%M%S)

TEMPORAL="${CARPETA_BACKUPS}/en_progreso"
ULTIMO="${CARPETA_BACKUPS}/ultimo"
DESTINO="${CARPETA_BACKUPS}/${FECHA}"

mkdir -p "$CARPETA_BACKUPS"

exec 9>/run/lock/backup-mesa5.lock

if ! flock -n 9; then
echo "Ya existe otro respaldo en ejecución."
exit 0
fi

if [ ! -f "$LLAVE_SSH" ]; then
echo "ERROR: No existe la llave SSH."
exit 1
fi

if [ ! -f "$ARCHIVO_EXCLUSIONES" ]; then
echo "ERROR: No existe el archivo de exclusiones."
exit 1
fi

if ! ssh -i "$LLAVE_SSH" \
-o BatchMode=yes \
-o StrictHostKeyChecking=accept-new \
"$SERVIDOR_ORIGEN" "true"; then

echo "ERROR: No hay conexión SSH."
exit 1
fi

if ! ssh -i "$LLAVE_SSH" \
-o BatchMode=yes \
"$SERVIDOR_ORIGEN" "command -v rsync >/dev/null"; then
echo "ERROR: RSYNC no está instalado."
exit 1
fi

echo "Generando respaldo de MariaDB en el servidor origen..."
if ! ssh -i "$LLAVE_SSH" -o BatchMode=yes "$SERVIDOR_ORIGEN" 'set -e; command -v mariadb-dump >/dev/null; mkdir -p /var/backups/mariadb; chmod 700 /var/backups/mariadb; FECHA=$(date +%Y-%m-%d_%H%M%S); ARCHIVO="/var/backups/mariadb/datacenter_${FECHA}.sql"; mariadb-dump --single-transaction --routines --triggers datacenter > "$ARCHIVO"; test -s "$ARCHIVO"; mapfile -t LISTA < <(ls -1t /var/backups/mariadb/datacenter_*.sql 2>/dev/null || true); for ((i=24; i<${#LISTA[@]}; i++)); do rm -f -- "${LISTA[i]}"; done'; then
echo "ERROR: No se pudo respaldar la base de datos datacenter."
exit 1
fi

rm -rf "$TEMPORAL"
mkdir -p "$TEMPORAL"

for RUTA in "${RUTAS[@]}"; do

echo "Verificando: $RUTA"

if ! ssh -i "$LLAVE_SSH" \
-o BatchMode=yes \
"$SERVIDOR_ORIGEN" "test -d '$RUTA'"; then

echo "ERROR: No existe $RUTA en el origen."
rm -rf "$TEMPORAL"
exit 1
fi

echo "Copiando: $RUTA"

ENLACE=()

if [ -d "${ULTIMO}${RUTA}" ]; then
ENLACE=(--link-dest="${ULTIMO}${RUTA}")
fi

mkdir -p "${TEMPORAL}${RUTA}"

rsync -aHAX --numeric-ids --delete \
--exclude-from="$ARCHIVO_EXCLUSIONES" \
"${ENLACE[@]}" \
-e "ssh -i ${LLAVE_SSH} -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
"${SERVIDOR_ORIGEN}:${RUTA}/" \
"${TEMPORAL}${RUTA}/"

CODIGO=$?

if [ "$CODIGO" -ne 0 ]; then
echo "ERROR en $RUTA. Código: $CODIGO"
rm -rf "$TEMPORAL"
exit 1
fi

done

if [ -e "$DESTINO" ]; then
echo "ERROR: El respaldo ya existe."
rm -rf "$TEMPORAL"
exit 1
fi

mv "$TEMPORAL" "$DESTINO"

ln -sfn "$FECHA" "$ULTIMO"


mapfile -t LISTA < <(
find "$CARPETA_BACKUPS" \
-mindepth 1 -maxdepth 1 \
-type d -name '20[0-9][0-9]-*' | sort
)

SOBRAN=$(( ${#LISTA[@]} - CONSERVAR ))

if [ "$SOBRAN" -gt 0 ]; then
for ((i=0; i<SOBRAN; i++)); do
rm -rf -- "${LISTA[i]}"
done
fi

echo "RESPALDO COMPLETADO: $DESTINO"

EOS

chmod 700 "$SCRIPT_PATH"

(crontab -l 2>/dev/null | grep -vF "$SCRIPT_PATH"
echo "0 * * * * $SCRIPT_PATH >> /var/log/backup-horario.log 2>&1") | crontab -

echo ""
echo "======================================"
echo " RESPALDO AUTOMATICO CONFIGURADO"
echo "======================================"
echo "Script: $SCRIPT_PATH"
echo "Frecuencia: Cada hora"
echo "Retención: 24 respaldos"
echo "Log: /var/log/backup-horario.log"

systemctl enable cron
systemctl restart cron

Pausa
}

InstalarNagios() {
clear
echo "======================================"
echo "     INSTALAR NAGIOS"
echo "======================================"
echo "1) Servidor Nagios Core"
echo "2) Nodo agente (NRPE)"
read -p "Opción: " TIPO_ROLE
case "$TIPO_ROLE" in
1)
apt update
DEBIAN_FRONTEND=noninteractive apt install -y wget build-essential apache2 php libgd-dev libapache2-mod-php libssl-dev bc gawk dc snmp libnet-snmp-perl gettext monitoring-plugins-common nagios-nrpe-plugin
id -u nagios >/dev/null 2>&1 || useradd nagios
getent group nagcmd >/dev/null 2>&1 || groupadd nagcmd
usermod -aG nagcmd nagios
usermod -aG nagcmd www-data
if [ ! -f /usr/local/nagios/bin/nagios ]; then
cd /tmp
wget -q https://assets.nagios.com/downloads/nagioscore/releases/nagios-4.4.14.tar.gz -O nagios-core.tar.gz
tar zxf nagios-core.tar.gz
cd nagios-4.4.14
./configure --with-command-group=nagcmd
make all
make install
make install-init
make install-commandmode
make install-config
make install-webconf
fi
a2enmod rewrite cgi
htpasswd -b -c /usr/local/nagios/etc/htpasswd.users nagiosadmin Admin2026*
systemctl restart apache2
systemctl enable nagios
systemctl restart nagios
echo "Nagios Core listo. Usuario web: nagiosadmin"
;;
2)
read -p "IP del servidor Nagios: " NAGIOS_SERVER_IP
apt update
apt install -y nagios-nrpe-server nagios-plugins
if ! grep -q "$NAGIOS_SERVER_IP" /etc/nagios/nrpe.cfg; then
sed -i "s/^allowed_hosts=.*/&,$NAGIOS_SERVER_IP/" /etc/nagios/nrpe.cfg
fi
systemctl enable nagios-nrpe-server
systemctl restart nagios-nrpe-server
echo "Agente NRPE listo."
;;
*)
echo "Opción inválida."
;;
esac
Pausa
}

AgregarHostsNagios() {
clear
echo "======================================"
echo "     AÑADIR HOSTS A NAGIOS"
echo "======================================"
NAGIOS_OBJECTS_DIR="/usr/local/nagios/etc/objects"
CONTINUAR="s"
HOSTS_CREADOS=0
while [ "$CONTINUAR" = "s" ] || [ "$CONTINUAR" = "S" ]; do
read -p "Nombre del equipo: " HOST_NAME
read -p "IP del equipo: " HOST_IP
[ -z "$HOST_NAME" ] || [ -z "$HOST_IP" ] && continue
FILE_PATH="$NAGIOS_OBJECTS_DIR/${HOST_NAME}.cfg"
echo "1) NRPE (Linux)"
echo "2) Solo host básico"
read -p "Opción: " AGENT_OPTION
case "$AGENT_OPTION" in
1)
cat > "$FILE_PATH" <<EOF
define host {
    use         linux-server
    host_name   $HOST_NAME
    alias       Equipo Linux NRPE
    address     $HOST_IP
}
define service {
    use                 generic-service
    host_name           $HOST_NAME
    service_description Carga CPU
    check_command       check_nrpe!check_load
}
define service {
    use                 generic-service
    host_name           $HOST_NAME
    service_description Disco
    check_command       check_nrpe!check_disk
}
EOF
;;
2)
cat > "$FILE_PATH" <<EOF
define host {
    use         generic-host
    host_name   $HOST_NAME
    alias       Host básico
    address     $HOST_IP
}
EOF
;;
*)
echo "Opción no válida"
continue
;;
esac
HOSTS_CREADOS=$((HOSTS_CREADOS + 1))
read -p "¿Añadir otro? (s/n): " CONTINUAR
done
if [ "$HOSTS_CREADOS" -gt 0 ]; then
if /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg >/dev/null 2>&1; then
systemctl restart nagios
echo "Hosts cargados: $HOSTS_CREADOS"
else
echo "Error de sintaxis en Nagios."
fi
fi
Pausa
}

Estado() {
clear
echo "======================================"
echo "        ESTADO GENERAL"
echo "======================================"
echo ""
echo "--- Interfaces ---"
ip -br address
echo ""
echo "--- Rutas ---"
ip route show
echo ""
echo "--- Kea DHCP ---"
systemctl --no-pager --full status kea-dhcp4-server 2>/dev/null | head -n 8 || echo "No instalado"
echo ""
echo "--- Nagios ---"
systemctl --no-pager --full status nagios 2>/dev/null | head -n 8 || echo "No instalado"
echo ""
echo "--- MariaDB ---"
systemctl --no-pager --full status mariadb 2>/dev/null | head -n 8 || echo "No instalado"
echo ""
echo "--- iptables INPUT ---"
iptables -L INPUT -n -v | head -n 25
Pausa
}

while true; do
clear
echo "======================================"
echo "     MENÚ PROYECTO MESA-5"
echo "======================================"
echo "1) Crear base de datos"
echo "2) Activar antena USB WiFi"
echo "3) Configurar pasarela"
echo "4) Aplicar firewall"
echo "5) Preparar respaldos (SSH)"
echo "6) Ejecutar respaldo ahora"
echo "7) Programar respaldo cada hora"
echo "8) Instalar Nagios (servidor/agente)"
echo "9) Añadir hosts a Nagios"
echo "10) Ver estado"
echo "11) Salir"
echo ""
read -r -p "Selecciona una opción: " OPCION
case "$OPCION" in
1) CrearBaseDatos ;;
2) ActivarAntena ;;
3) Pasarela ;;
4) Firewall ;;
5) PrepararBackup ;;
6) EjecutarBackup ;;
7) ProgramarBackupHora ;;
8) InstalarNagios ;;
9) AgregarHostsNagios ;;
10) Estado ;;
11) echo "Saliendo..."; exit 0 ;;
*) echo "Opción no válida"; sleep 1 ;;
esac
done
