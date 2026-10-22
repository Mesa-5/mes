#!/bin/bash

Firewall() {
clear
printf "\n\n\n"

read -p "DESEA CONFIGURAR EL FIREWALL [S/N] [   🤔   ] " SiNo
SiNo=${SiNo,,}

if [[ "$SiNo" == "s" ]];then 

iptables -P INPUT ACCEPT >/dev/null 2>&1;
sleep 2
iptables -P OUTPUT ACCEPT >/dev/null 2>&1;
sleep 2
iptables -P FORWARD ACCEPT >/dev/null 2>&1;
sleep 2
iptables -F >/dev/null 2>&1;
sleep 2
iptables -X >/dev/null 2>&1;
sleep 2
iptables -t nat -F >/dev/null 2>&1;
sleep 2
iptables -t nat -X >/dev/null 2>&1;
sleep 2
iptables -t mangle -F >/dev/null 2>&1;
sleep 2
iptables -t mangle -X >/dev/null 2>&1;
sleep 2
iptables -t raw -F >/dev/null 2>&1;
sleep 2
iptables -t raw -X >/dev/null 2>&1;
sleep 2
iptables -t security -F >/dev/null 2>&1;
sleep 2
iptables -t security -X >/dev/null 2>&1;

echo -e "LIMPIANDO COMPLETAMENTE LOS RESIDUOS [   ✅   ] " 
sleep 2 

iptables -P INPUT DROP >/dev/null 2>&1; 
sleep 1
iptables -P OUTPUT ACCEPT
sleep 1
iptables -P FORWARD DROP
sleep 1
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT >/dev/null 2>&1;
sleep 1
iptables -A INPUT -i lo -j ACCEPT >/dev/null 2>&1;
sleep 1
iptables -A INPUT -p tcp --dport 22 -j ACCEPT >/dev/null 2>&1;
sleep 1
iptables -A INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1;
sleep 1
iptables -A INPUT -p tcp --dport 443 -j ACCEPT >/dev/null 2>&1;
sleep 1
iptables -A INPUT -p tcp --dport 5666 -j ACCEPT >/dev/null 2>&1;
sleep 1
echo -e "FIREWALL IMPLEMENTADO CORRECTAMENTE  [   🔰   ]" 
sleep 2
clear
elif [[ "$SiNo" == "n" ]]; then 
echo -e "CANCELADO " 
sleep 2
clear
else
printf "\n\n"
echo -e "OCURRIO UN ERROR DURANTE LA EJECUCION DEL CODIGO [ ❌ ] " 
sleep 2
clear
fi

}


estado() {

clear
printf "\n\n"
sleep 1
read -p "DESEA VERIFICAR EL ESTADO DEL FIREWALL [S/N]" SiNo
SiNo=${SiNo,,}

if [[ "$SiNo" == "s" ]]; then
echo -e "OK MOSTRANDO ESTADO POR 10 SEGUNDOS [    🔓    ] " 
sudo iptables -L -v -n 
sleep 10
clear
sleep 2
elif [[ "$SiNo" == "n" ]]; then
sleep 1
echo -e "CANCELADO [    ❌    ]"
sleep 1
clear
else 
echo "error"
fi
}

while true 
do 
echo -e "⛩️  [1.] 🔰 IMPLEMENTACION COMPLETA DEL FIREWALL 🔰 "
echo -e "⛩️  [2.] 🔰 ESTADO DEL FIREWALL 🔰 "

read -p " ----> " seleccion 

case $seleccion in 

1) Firewall ;;
2) estado ;;

esac
done



























  
  
