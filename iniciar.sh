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

# --- Trabajar siempre desde la carpeta del script ---
cd "$(dirname "$0")" || exit 1

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

# --- Leer .env (versión de Paper, Java necesario, modo de Geyser) ---
if [ -f ".env" ]; then
    PAPER_JAR=$(grep -E '^PAPER_JAR=' .env | cut -d= -f2 | tr -d '\r')
    JAVA_VERSION=$(grep -E '^JAVA_VERSION=' .env | cut -d= -f2 | tr -d '\r')
    GEYSER_MODE=$(grep -E '^GEYSER_MODE=' .env | cut -d= -f2 | tr -d '\r')
fi
JAVA_VERSION="${JAVA_VERSION:-21}"
GEYSER_MODE="${GEYSER_MODE:-ondemand}"

# --- Verificar archivo JAR (el de .env o el paper-*.jar más reciente) ---
if [ -z "$PAPER_JAR" ] || [ ! -f "server 2025/$PAPER_JAR" ]; then
    PAPER_JAR=$(ls -t "server 2025"/paper-*.jar 2>/dev/null | head -n1 | xargs -r -d '\n' basename)
fi
if [ -z "$PAPER_JAR" ]; then
    echo -e "${RED}ERROR: No se encuentra el jar de Paper en 'server 2025/'. Ejecuta ./actualizar.sh${NC}"
    exit 1
fi

# --- Verificar Java (usa $JAVA si está definido) ---
JAVA="${JAVA:-java}"
JAVA_MAJOR=$("$JAVA" -version 2>&1 | grep -oE 'version "[0-9]+' | grep -oE '[0-9]+$')
if [ -z "$JAVA_MAJOR" ] || [ "$JAVA_MAJOR" -lt "$JAVA_VERSION" ]; then
    echo -e "${RED}ERROR: Hace falta Java ${JAVA_VERSION} o superior (encontrado: ${JAVA_MAJOR:-ninguno}).${NC}"
    if [ -n "$TERMUX_VERSION" ]; then
        echo -e "${YELLOW}En Termux: pkg install openjdk-${JAVA_VERSION}${NC}"
    else
        echo -e "${YELLOW}Descárgalo de https://adoptium.net o indica uno con: JAVA=/ruta/a/java ./iniciar.sh${NC}"
    fi
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
echo -e "${YELLOW}  server-ip=192.0.2.1${NC}"
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

# --- Geyser bajo demanda (conexión para móviles / Bedrock) ---
GEYSER_PID=""
if [ "$GEYSER_MODE" = "ondemand" ] && [ -f "server 2025/geyser/Geyser-Standalone.jar" ]; then
    # En Windows "python3" puede ser el acceso directo a la Microsoft Store: probar que funciona
    PYTHON=""
    for p in python3 python; do
        if command -v "$p" >/dev/null && "$p" -c "import sys" >/dev/null 2>&1; then PYTHON="$p"; break; fi
    done
    if [ -n "$PYTHON" ]; then
        "$PYTHON" geyser-bajo-demanda.py --java "$JAVA" > "server 2025/logs/geyser-bajo-demanda.log" 2>&1 &
        GEYSER_PID=$!
        echo -e "${CYAN}Geyser bajo demanda activo (log: server 2025/logs/geyser-bajo-demanda.log)${NC}"
    else
        echo -e "${YELLOW}AVISO: sin Python no hay conexión para móviles (Bedrock). Instálalo para usarla.${NC}"
    fi
fi
trap '[ -n "$GEYSER_PID" ] && kill "$GEYSER_PID" 2>/dev/null' EXIT

cd "server 2025" || exit 1
"$JAVA" -Xms1G -Xmx${MEMORIA_XMX}G -jar "$PAPER_JAR" nogui

# Al cerrar el servidor, volver al directorio anterior
cd ..

echo ""
echo -e "${CYAN}Servidor detenido.${NC}"
echo -e "${YELLOW}Recuerda ejecutar './terminar.sh' para hacer backup.${NC}"
