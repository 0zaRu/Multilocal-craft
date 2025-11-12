#!/bin/bash

# ------------------------------------------------------------
# Script: iniciar.sh
# Propósito:
#   Asistente para iniciar el servidor de Minecraft en modo LOCAL
#   para sistemas Linux/Mac.
#   Verifica ZeroTier, Git, Java 21, activa IP flotante y lanza servidor.
# ------------------------------------------------------------

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Configuración ---
IPFLOTANTE="172.25.254.254"
MEMORIA_XMX="${1:-6}"  # Primer argumento o 6 por defecto
ZEROTIER_NETWORK_ID="your_network_id"  # Ajustar según tu red

echo -e "${CYAN}--- Asistente para iniciar el Servidor de Minecraft (LOCAL) ---${NC}"

# --- Verificar ejecución con sudo ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Este script debe ejecutarse con sudo.${NC}"
    echo -e "${RED}Ejecuta: sudo ./iniciar.sh${NC}"
    exit 1
fi

# --- Verificar ZeroTier instalado y funcionando ---
echo -e "${YELLOW}Verificando ZeroTier...${NC}"
if ! command -v zerotier-cli &> /dev/null; then
    echo -e "${RED}ERROR: ZeroTier no está instalado en el sistema.${NC}"
    echo -e "${RED}Instala ZeroTier antes de continuar: https://www.zerotier.com/download/${NC}"
    exit 1
fi

if ! systemctl is-active --quiet zerotier-one 2>/dev/null && ! pgrep -x "zerotier-one" > /dev/null; then
    echo -e "${RED}ERROR: El servicio ZeroTier no está en ejecución.${NC}"
    echo -e "${YELLOW}Intenta iniciarlo con: sudo systemctl start zerotier-one${NC}"
    exit 1
fi

echo -e "${GREEN}ZeroTier detectado y funcionando.${NC}"

# --- Verificar Git instalado ---
echo -e "${YELLOW}Verificando Git...${NC}"
if ! command -v git &> /dev/null; then
    echo -e "${RED}ERROR: Git no está instalado en el sistema.${NC}"
    echo -e "${RED}Instala Git antes de continuar.${NC}"
    exit 1
fi
echo -e "${GREEN}Git detectado correctamente.${NC}"

# --- Verificar Java 21 ---
echo -e "${YELLOW}Verificando Java (JDK 21)...${NC}"
if ! command -v java &> /dev/null; then
    echo -e "${RED}ERROR: Java no está instalado en el sistema.${NC}"
    echo -e "${RED}Instala JDK 21 antes de continuar.${NC}"
    exit 1
fi

JAVA_VERSION=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2 | cut -d'.' -f1)
if [ "$JAVA_VERSION" != "21" ]; then
    echo -e "${RED}ERROR: Se requiere Java 21, pero se detectó Java $JAVA_VERSION.${NC}"
    echo -e "${RED}Instala JDK 21 antes de continuar.${NC}"
    exit 1
fi
echo -e "${GREEN}Java 21 detectado correctamente.${NC}"

# --- Preguntar memoria si no se pasó como argumento ---
if [ -z "$1" ]; then
    echo -e "${YELLOW}Memoria RAM para el servidor (Xmx):${NC}"
    read -p "Ingresa la cantidad en GB (por defecto 6, presiona Enter para mantener): " MEMORIA_INPUT
    if [ -n "$MEMORIA_INPUT" ]; then
        MEMORIA_XMX="$MEMORIA_INPUT"
    fi
fi

echo -e "${CYAN}Configurando servidor con Xmx${MEMORIA_XMX}G de RAM...${NC}"

# --- Verificar archivo JAR ---
if [ ! -f "server 2025/paper-1.21.1.jar" ]; then
    echo -e "${RED}ERROR: No se encuentra el archivo del servidor: server 2025/paper-1.21.1.jar${NC}"
    exit 1
fi

# --- Obtener interfaz ZeroTier ---
ZT_INTERFACE=$(ip addr show | grep -B 2 "zt" | grep "^[0-9]" | awk '{print $2}' | tr -d ':' | head -n 1)
if [ -z "$ZT_INTERFACE" ]; then
    echo -e "${RED}ERROR: No se encontró una interfaz de ZeroTier activa.${NC}"
    exit 1
fi

echo -e "${CYAN}Interfaz ZeroTier detectada: $ZT_INTERFACE${NC}"

# --- Verificar si la IP ya está asignada ---
if ip addr show "$ZT_INTERFACE" | grep -q "$IPFLOTANTE"; then
    echo -e "${CYAN}INFORMACION: La IP flotante ($IPFLOTANTE) ya está configurada.${NC}"
else
    # --- Verificar si la IP está en uso por otro PC ---
    if ping -c 1 -W 1 "$IPFLOTANTE" &> /dev/null; then
        echo -e "${RED}ERROR: La IP $IPFLOTANTE está siendo usada por OTRO ordenador.${NC}"
        echo -e "${YELLOW}Apaga el otro servidor antes de continuar.${NC}"
        exit 1
    fi

    # --- Activar IP flotante ---
    echo -e "${YELLOW}Activando la configuración de red (IP: $IPFLOTANTE)...${NC}"
    if ! ip addr add "$IPFLOTANTE/16" dev "$ZT_INTERFACE" 2>/dev/null; then
        echo -e "${RED}ERROR: No se pudo activar la IP flotante.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Configuración de red (IP: $IPFLOTANTE) activada correctamente.${NC}"
fi

# --- Lanzar servidor ---
echo ""
echo -e "${GREEN}Iniciando servidor de Minecraft en modo LOCAL...${NC}"
echo -e "${YELLOW}IMPORTANTE: Mantén esta terminal abierta mientras el servidor esté funcionando.${NC}"
echo -e "${YELLOW}Para detener el servidor, escribe 'stop' en la consola.${NC}"
echo ""

cd "server 2025" || exit 1
java -Xms1G -Xmx${MEMORIA_XMX}G -jar paper-1.21.1.jar nogui

# Al cerrar el servidor, volver al directorio anterior
cd ..

echo ""
echo -e "${CYAN}Servidor detenido.${NC}"
echo -e "${YELLOW}Recuerda ejecutar './terminar.sh' para desactivar la IP y hacer backup.${NC}"
