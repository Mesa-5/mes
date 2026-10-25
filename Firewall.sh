#!/bin/bash
# 02-firewall.sh

if [ "$EUID" -ne 0 ]; then
    echo "Ejecuta este script como root"
    exit 1
fi

mapfile -t WIFI_IFACES < <(ip -o link show | awk -F': ' '{print $2}' | grep -E '^wl|^wlan')
mapfile -t ETH_IFACES  < <(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth')

RED="192.168.50.0/24"
DNS="8.8.8.8"

echo "Interfaces detectadas:"
echo "  WiFi : ${WIFI_IFACES[*]:-Ninguna}"
echo "  Ethernet: ${ETH_IFACES[*]:-Ninguna}"
echo ""

if [ ${#WIFI_IFACES[@]} -eq 0 ] && [ ${#ETH_IFACES[@]} -eq 0 ]; then
    echo "No se encontró ninguna interfaz válida."
    exit 1
fi

WAN="${WIFI_IFACES[0]}"
LAN="${ETH_IFACES[0]}"

Firewall() {
   
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
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p tcp --dport 5666 -j ACCEPT
    
    iptables -A INPUT -p udp --dport 5060 -j ACCEPT
    iptables -A INPUT -p tcp --dport 5060 -j ACCEPT
    iptables -A INPUT -p tcp --dport 5061 -j ACCEPT
    iptables -A INPUT -p udp --dport 10000:20000 -j ACCEPT

    if [ ${#ETH_IFACES[@]} -gt 0 ]; then
        echo "Puertos DHCP..."
        for IFACE in "${ETH_IFACES[@]}"; do
            iptables -A INPUT -i "$IFACE" -p udp --dport 67 -j ACCEPT
            iptables -A INPUT -i "$IFACE" -p udp --dport 68 -j ACCEPT
        done
    fi
    
    if [ ${#WIFI_IFACES[@]} -gt 0 ] && [ ${#ETH_IFACES[@]} -gt 0 ]; then
        echo "NAT y reenvío (pasarela)..."
        for W in "${WIFI_IFACES[@]}"; do
            for E in "${ETH_IFACES[@]}"; do
                iptables -t nat -A POSTROUTING -s "$RED" -o "$W" -j MASQUERADE
                iptables -A FORWARD -i "$E" -o "$W" -j ACCEPT
                iptables -A FORWARD -i "$W" -o "$E" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
            done
        done

        echo "Redirección DNS..."
        for E in "${ETH_IFACES[@]}"; do
            iptables -t nat -A PREROUTING -i "$E" -p udp --dport 53 -j DNAT --to-destination ${DNS}:53
            iptables -t nat -A PREROUTING -i "$E" -p tcp --dport 53 -j DNAT --to-destination ${DNS}:53
        done
        iptables -t nat -A POSTROUTING -p udp -d "$DNS" --dport 53 -j MASQUERADE
        iptables -t nat -A POSTROUTING -p tcp -d "$DNS" --dport 53 -j MASQUERADE

        echo "Activando IP forwarding..."
        echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-pasarela.conf
        sysctl -p /etc/sysctl.d/99-pasarela.conf
    else
        echo "Falta WiFi o Ethernet. Se aplicaron solo reglas básicas."
    fi

    if ! dpkg -l | grep -q iptables-persistent; then
        DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
    fi

    netfilter-persistent save
    netfilter-persistent reload

    echo "Firewall implementado correctamente."
    sleep 2
}

Estado() {
    echo "Estado actual del firewall:"
    echo "--------------------------------"
    iptables -L -v -n
    echo ""
    echo "Reglas NAT:"
    echo "--------------------------------"
    iptables -t nat -L -v -n
    echo ""
    read -p "Presiona Enter para continuar..."
}

while true; do
    clear
    printf "\n\n"
    echo "1) Implementar firewall"
    echo "2) Ver estado del firewall"
    echo "3) Salir"
    echo ""
    read -p "Selecciona una opción: " opcion

    case $opcion in
        1) Firewall ;;
        2) Estado ;;
        3) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción no válida"; sleep 1 ;;
    esac
done
