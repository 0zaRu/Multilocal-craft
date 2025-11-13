#!/bin/bash

# ------------------------------------------------------------
# Script: iniciar.sh
# Propósito:
#   Asistente para iniciar el servidor de Minecraft en modo LOCAL
#   para sistemas Linux/Mac.
#   Verifica Git, Java 21 y lanza servidor.
# ------------------------------------------------------------

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Configuración ---
MEMORIA_XMX="${1:-6}"  # Primer argumento o 6 por defecto

echo -e "${CYAN}--- Asistente para iniciar el Servidor de Minecraft (LOCAL) ---${NC}"

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
if [ ! -f "server 2025/paper-1.21.10.jar" ]; then
    echo -e "${RED}ERROR: No se encuentra el archivo del servidor: server 2025/paper-1.21.10.jar${NC}"
    exit 1
fi

# --- Advertencia sobre configuración de IP en server.properties ---
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║                    CONFIGURACIÓN IMPORTANTE                    ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${RED}ANTES DE CONTINUAR:${NC}"
echo -e "${CYAN}Debes configurar manualmente la IP de ZeroTier en el archivo:${NC}"
echo -e "${GREEN}  server 2025/server.properties${NC}"
echo ""
echo -e "${CYAN}Busca la línea que dice:${NC}"
echo -e "${YELLOW}  server-ip=${NC}"
echo ""
echo -e "${CYAN}Y cámbiala por tu IP de ZeroTier, por ejemplo:${NC}"
echo -e "${YELLOW}  server-ip=172.25.254.254${NC}"
echo ""
echo -e "${RED}Si no has configurado esto, el servidor NO será accesible por otros jugadores.${NC}"
echo ""
read -p "Presiona ENTER cuando hayas configurado la IP en server.properties..."

# --- Lanzar servidor ---
echo ""
echo -e "${GREEN}Iniciando servidor de Minecraft en modo LOCAL...${NC}"
echo -e "${YELLOW}IMPORTANTE: Mantén esta terminal abierta mientras el servidor esté funcionando.${NC}"
echo -e "${YELLOW}Para detener el servidor, escribe 'stop' en la consola.${NC}"
echo ""

cd "server 2025" || exit 1
java -Xms1G -Xmx${MEMORIA_XMX}G -jar paper-1.21.10.jar nogui

# Al cerrar el servidor, volver al directorio anterior
cd ..

echo ""
echo -e "${CYAN}Servidor detenido.${NC}"
echo -e "${YELLOW}Recuerda ejecutar './terminar.sh' para hacer backup.${NC}"
