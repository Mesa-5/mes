#!/bin/bash
# 01-pasarela-menu.sh
# Ubuntu Server 24.04
# Antena USB + Pasarela doble WiFi + Firewall + Estado

set -o pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Ejecuta este script como root:"
    echo "sudo bash 01-pasarela-menu.sh"
    exit 1
fi

# =========================================================
# FUNCION AUXILIAR: DETECTAR INTERFACES
# =========================================================

DetectarInterfaces() {
    mapfile -t WIFI_IFACES < <(
        ip -o link show |
        awk -F': ' '{print $2}' |
        sed 's/@.*//' |
        grep -E '^(wl|wlan)' || true
    )

    mapfile -t ETH_IFACES < <(
        ip -o link show |
        awk -F': ' '{print $2}' |
        sed 's/@.*//' |
        grep -E '^(en|eth)' || true
    )
}

Pausa() {
    echo ""
    read -r -p "Presiona Enter para continuar..."
}

# =========================================================
# FUNCION 1: ACTIVAR ANTENA USB
# =========================================================

ActivarAntena() {
    clear
    echo "======================================"
    echo "       ACTIVAR ANTENA USB WIFI"
    echo "======================================"

    echo ""
    echo "Interfaces WiFi detectadas:"
    DetectarInterfaces

    printf '%s\n' "${WIFI_IFACES[@]:-Ninguna}"

    echo ""
    echo "Preparando el controlador RTL8852BU..."

    if modprobe 8852bu 2>/dev/null; then
        echo "El controlador 8852bu ya está disponible."
    else
        echo "Instalando dependencias..."

        if ! apt update ||
           ! apt install -y build-essential dkms \
             "linux-headers-$(uname -r)" bc unzip curl; then
            echo "Error instalando las dependencias."
            Pausa
            return
        fi

        URL="https://github.com/Mesa-5/PROYECTO_FINAL_MESA-5/archive/refs/heads/main.zip"
        ZIP="/tmp/mesa5-controlador.zip"

        echo "Descargando el ZIP desde GitHub..."

        if ! curl -fL "$URL" -o "$ZIP"; then
            echo "No se pudo descargar el ZIP."
            Pausa
            return
        fi

        mkdir -p /tmp/mesa5-controlador
        rm -rf /tmp/mesa5-controlador/*
        
        if ! unzip -oq "$ZIP" -d /tmp/mesa5-controlador; then
            echo "No se pudo extraer el ZIP."
            Pausa
            return
        fi

        INSTALLER="$(find /tmp/mesa5-controlador \
            -type f -name install-driver.sh -print -quit)"

        if [ -z "$INSTALLER" ]; then
            echo "No se encontró install-driver.sh dentro del ZIP."
            echo "Comprueba la estructura del repositorio."
            Pausa
            return
        fi

        DRIVER_DIR="$(dirname "$INSTALLER")"

        echo "Instalador encontrado en:"
        echo "$DRIVER_DIR"

        cd "$DRIVER_DIR" || {
            echo "No se pudo entrar en la carpeta del controlador."
            Pausa
            return
        }

        echo "Ejecutando instalador..."

        if ! bash ./install-driver.sh; then
            echo "Falló la instalación del controlador."
            Pausa
            return
        fi

        if ! modprobe 8852bu; then
            echo "No se pudo cargar el módulo 8852bu."
            echo "Comprueba los mensajes con: dmesg | tail -50"
            Pausa
            return
        fi
    fi

    sleep 3

    DetectarInterfaces

    echo ""
    echo "Interfaces WiFi disponibles:"
    printf '%s\n' "${WIFI_IFACES[@]:-Ninguna}"

    echo ""
    echo "Controlador de antena USB:"
    lsmod | grep 8852bu || true

    echo ""
    echo "Si aparece una interfaz nueva, la antena está reconocida."
    Pausa
}

# =========================================================
# FUNCION 2: CONFIGURAR PASARELA DOBLE WIFI
# =========================================================

Pasarela() {
    clear
    echo "======================================"
    echo "       CONFIGURAR PASARELA"
    echo "======================================"

    DetectarInterfaces

    echo ""
    echo "Interfaces WiFi: ${WIFI_IFACES[*]:-Ninguna}"
    echo "Interfaces Ethernet: ${ETH_IFACES[*]:-Ninguna}"
    echo ""

    if [ "${#WIFI_IFACES[@]}" -lt 1 ]; then
        echo "No se encontró ninguna interfaz WiFi."
        echo "Activa primero la antena USB."
        Pausa
        return
    fi

    if [ "${#ETH_IFACES[@]}" -lt 1 ]; then
        echo "No se encontró ninguna interfaz Ethernet."
        Pausa
        return
    fi

    echo "Selecciona las interfaces:"
    echo ""

    select LAN in "${ETH_IFACES[@]}"; do
        if [ -n "$LAN" ]; then
            break
        fi
        echo "Selecciona una interfaz válida."
    done

    select WAN1 in "${WIFI_IFACES[@]}"; do
        if [ -n "$WAN1" ]; then
            break
        fi
        echo "Selecciona una interfaz válida."
    done

    WAN2=""

    if [ "${#WIFI_IFACES[@]}" -ge 2 ]; then
        echo ""
        echo "Selecciona el segundo proveedor WiFi."
        echo "Si no deseas utilizarlo, escribe 0."

        select OPCION_WAN2 in "${WIFI_IFACES[@]}" "Ninguno"; do
            if [ "$OPCION_WAN2" = "Ninguno" ]; then
                WAN2=""
                break
            elif [ -n "$OPCION_WAN2" ] && [ "$OPCION_WAN2" != "$WAN1" ]; then
                WAN2="$OPCION_WAN2"
                break
            else
                echo "Selecciona otra interfaz WiFi."
            fi
        done
    fi

    LAN_IP="192.168.50.1"
    RED="192.168.50.0/24"

    echo ""
    echo "Interfaz LAN: $LAN"
    echo "Proveedor WiFi 1: $WAN1"
    echo "Proveedor WiFi 2: ${WAN2:-No utilizado}"
    echo "IP de la pasarela: $LAN_IP"
    echo ""

    read -r -p "SSID del proveedor 1: " SSID1
    read -r -s -p "Contraseña del proveedor 1: " PASS1
    echo ""

    SSID2=""
    PASS2=""

    if [ -n "$WAN2" ]; then
        read -r -p "SSID del proveedor 2: " SSID2
        read -r -s -p "Contraseña del proveedor 2: " PASS2
        echo ""
    fi

    echo ""
    echo "Se instalarán los paquetes necesarios."

    if ! apt update ||
       ! apt install -y kea-dhcp4-server iptables-persistent; then
        echo "Error instalando los paquetes."
        Pausa
        return
    fi

    mkdir -p /etc/netplan
    mkdir -p /etc/kea

    # Crear configuración de Netplan.
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

    echo ""
    echo "Validando configuración de Netplan..."

    if ! netplan generate; then
        echo "La configuración de Netplan contiene errores."
        Pausa
        return
    fi

    echo "Aplicando configuración..."
    netplan apply
    sleep 8

    # Activar reenvío IPv4.
    cat > /etc/sysctl.d/99-pasarela.conf <<EOF
net.ipv4.ip_forward=1
EOF

    sysctl -p /etc/sysctl.d/99-pasarela.conf

    # Configurar servidor DHCP Kea.
    cat > /etc/kea/kea-dhcp4.conf <<EOF
{
  "Dhcp4": {
    "interfaces-config": {
      "interfaces": ["$LAN"]
    },
    "lease-database": {
      "type": "memfile",
      "persist": true,
      "name": "/var/lib/kea/kea-leases4.csv"
    },
    "valid-lifetime": 3600,
    "subnet4": [{
      "id": 1,
      "subnet": "$RED",
      "pools": [{
        "pool": "192.168.50.100 - 192.168.50.200"
      }],
      "option-data": [
        {
          "name": "routers",
          "data": "$LAN_IP"
        },
        {
          "name": "domain-name-servers",
          "data": "8.8.8.8, 1.1.1.1"
        }
      ]
    }]
  }
}
EOF

    echo ""
    echo "Comprobando configuración DHCP..."

    if ! kea-dhcp4 -t /etc/kea/kea-dhcp4.conf; then
        echo "La configuración de Kea contiene errores."
        Pausa
        return
    fi

    systemctl enable kea-dhcp4-server

    if ! systemctl restart kea-dhcp4-server; then
        echo "Error iniciando Kea DHCP."
        systemctl status kea-dhcp4-server --no-pager
        Pausa
        return
    fi

    echo ""
    echo "Pasarela configurada."
    echo "Ahora aplica la opción 3 para configurar el firewall."
    echo ""
    ip -br address
    ip route show

    Pausa
}

# =========================================================
# FUNCION 3: APLICAR FIREWALL
# =========================================================

Firewall() {
    clear
    echo "======================================"
    echo "         APLICAR FIREWALL"
    echo "======================================"

    DetectarInterfaces

    if [ "${#WIFI_IFACES[@]}" -eq 0 ] ||
       [ "${#ETH_IFACES[@]}" -eq 0 ]; then
        echo "Advertencia: falta una interfaz WiFi o Ethernet."
        echo "Se recomienda configurar primero la pasarela."
        Pausa
        return
    fi

    echo "WiFi: ${WIFI_IFACES[*]}"
    echo "Ethernet: ${ETH_IFACES[*]}"
    echo ""

    read -r -p "¿Aplicar las reglas del firewall? [S/N]: " RESPUESTA

    case "$RESPUESTA" in
        [sS]|[sS][iI])
            ;;
        *)
            echo "Operación cancelada."
            Pausa
            return
            ;;
    esac

    # ADVERTENCIA:
    # Estas reglas sustituyen las reglas actuales de iptables.
    # Se permite SSH desde cualquier interfaz.
    # Ajusta las reglas si necesitas otras políticas.

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
    iptables -A INPUT -m conntrack \
        --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p icmp -j ACCEPT

    # Servicios permitidos.
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p tcp --dport 5666 -j ACCEPT

    iptables -A INPUT -p udp --dport 5060 -j ACCEPT
    iptables -A INPUT -p tcp --dport 5060 -j ACCEPT
    iptables -A INPUT -p tcp --dport 5061 -j ACCEPT
    iptables -A INPUT -p udp --dport 10000:20000 -j ACCEPT

    # Permitir DHCP en la interfaz LAN.
    for E in "${ETH_IFACES[@]}"; do
        iptables -A INPUT -i "$E" \
            -p udp --dport 67 -j ACCEPT
        iptables -A INPUT -i "$E" \
            -p udp --dport 68 -j ACCEPT
    done

    RED="192.168.50.0/24"
    DNS="8.8.8.8"

    echo ""
    echo "Configurando NAT y reenvío..."

    for W in "${WIFI_IFACES[@]}"; do
        for E in "${ETH_IFACES[@]}"; do
            iptables -t nat -A POSTROUTING \
                -s "$RED" -o "$W" -j MASQUERADE

            iptables -A FORWARD \
                -i "$E" -o "$W" -s "$RED" -j ACCEPT

            iptables -A FORWARD \
                -i "$W" -o "$E" \
                -d "$RED" \
                -m conntrack \
                --ctstate ESTABLISHED,RELATED -j ACCEPT
        done
    done

    # Redirección DNS de clientes LAN.
    for E in "${ETH_IFACES[@]}"; do
        iptables -t nat -A PREROUTING \
            -i "$E" -s "$RED" \
            -p udp --dport 53 \
            -j DNAT --to-destination "$DNS":53

        iptables -t nat -A PREROUTING \
            -i "$E" -s "$RED" \
            -p tcp --dport 53 \
            -j DNAT --to-destination "$DNS":53
    done

    # Guardar configuración de reenvío IPv4.
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-pasarela.conf
    sysctl -p /etc/sysctl.d/99-pasarela.conf

    # Guardar reglas persistentes.
    if ! systemctl is-active --quiet netfilter-persistent; then
        systemctl enable netfilter-persistent
    fi

    if ! netfilter-persistent save; then
        echo "No se pudieron guardar las reglas persistentes."
        Pausa
        return
    fi

    echo ""
    echo "Firewall implementado correctamente."
    echo "Recuerda que el segundo proveedor no se suma al primero:"
    echo "las métricas de ruta determinan cuál tiene prioridad."

    Pausa
}

# =========================================================
# FUNCION 4: VER ESTADO
# =========================================================

Estado() {
    clear

    echo "======================================"
    echo "        ESTADO DE LA PASARELA"
    echo "======================================"

    echo ""
    echo "1. Interfaces de red"
    echo "--------------------------------------"
    ip -br address

    echo ""
    echo "2. Rutas de red"
    echo "--------------------------------------"
    ip route show

    echo ""
    echo "3. Controlador RTL8852BU"
    echo "--------------------------------------"
    lsmod | grep 8852bu || echo "Módulo no cargado."

    echo ""
    echo "4. Estado del DHCP Kea"
    echo "--------------------------------------"
    systemctl --no-pager --full status kea-dhcp4-server 2>/dev/null |
        head -n 12

    echo ""
    echo "5. Reenvío IPv4"
    echo "--------------------------------------"
    sysctl net.ipv4.ip_forward

    echo ""
    echo "6. Reglas INPUT y FORWARD"
    echo "--------------------------------------"
    iptables -L -n -v

    echo ""
    echo "7. Reglas NAT"
    echo "--------------------------------------"
    iptables -t nat -L -n -v

    Pausa
}

# =========================================================
# MENU PRINCIPAL
# =========================================================

while true; do
    clear

    echo "======================================"
    echo "     PASARELA DOBLE PROVEEDOR WIFI"
    echo "           UBUNTU SERVER 24.04"
    echo "======================================"
    echo ""
    echo "1) Activar antena USB WiFi"
    echo "2) Configurar pasarela"
    echo "3) Aplicar firewall"
    echo "4) Ver estado"
    echo "5) Salir"
    echo ""

    read -r -p "Selecciona una opción: " OPCION

    case "$OPCION" in
        1) ActivarAntena ;;
        2) Pasarela ;;
        3) Firewall ;;
        4) Estado ;;
        5)
            echo "Saliendo del programa..."
            exit 0
            ;;
        *)
            echo "Opción no válida."
            sleep 2
            ;;
    esac
done
