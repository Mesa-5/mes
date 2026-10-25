#!/bin/bash
# 02-firewall.sh

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Ejecuta este script como root"
    exit 1
fi

WAN="wlp0s20f3"
LAN="enp0s31f6"
RED="192.168.50.0/24"
LAN_IP="192.168.50.1"
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
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 5666 -j ACCEPT

iptables -A INPUT -i "$LAN" -p udp --dport 67 -j ACCEPT
iptables -A INPUT -i "$LAN" -p udp --dport 68 -j ACCEPT

iptables -A INPUT -p udp --dport 5060 -j ACCEPT
iptables -A INPUT -p tcp --dport 5060 -j ACCEPT
iptables -A INPUT -p tcp --dport 5061 -j ACCEPT
iptables -A INPUT -p udp --dport 10000:20000 -j ACCEPT

iptables -t nat -A POSTROUTING -s "$RED" -o "$WAN" -j MASQUERADE
iptables -A FORWARD -i "$LAN" -o "$WAN" -j ACCEPT
iptables -A FORWARD -i "$WAN" -o "$LAN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

iptables -t nat -A PREROUTING -i "$LAN" -p udp --dport 53 -j DNAT --to-destination ${DNS}:53
iptables -t nat -A PREROUTING -i "$LAN" -p tcp --dport 53 -j DNAT --to-destination ${DNS}:53
iptables -t nat -A POSTROUTING -p udp -d "$DNS" --dport 53 -j MASQUERADE
iptables -t nat -A POSTROUTING -p tcp -d "$DNS" --dport 53 -j MASQUERADE

echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-pasarela.conf
sysctl -p /etc/sysctl.d/99-pasarela.conf

if ! dpkg -l | grep -q iptables-persistent; then
    DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
fi

netfilter-persistent save
netfilter-persistent reload

echo "Firewall configurado correctamente."
