#!/bin/bash

# ------------------------------------------------------------
# Script: terminar.sh
# Propósito:
#   Asistente para apagar el servidor de Minecraft en modo LOCAL
#   para sistemas Linux/Mac.
#   Verifica que el servidor esté cerrado, descarta cambios en server.properties
#   y realiza backup en Git.
# ------------------------------------------------------------

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}--- Asistente para apagar el Servidor de Minecraft (LOCAL) ---${NC}"

# --- Verificar ejecución con sudo ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Este script debe ejecutarse con sudo.${NC}"
    echo -e "${RED}Ejecuta: sudo ./terminar.sh${NC}"
    exit 1
fi

# --- Verificar Git instalado ---
echo -e "${YELLOW}Verificando Git...${NC}"
if ! command -v git &> /dev/null; then
    echo -e "${RED}ERROR: Git no está instalado en el sistema.${NC}"
    exit 1
fi
echo -e "${GREEN}Git detectado.${NC}"

# --- Preguntar si el terminal se cerró ---
echo ""
echo -e "${YELLOW}¿Se cerró ya el terminal del servidor?${NC}"
echo -e "${YELLOW}IMPORTANTE: Debes haber detenido el servidor (comando 'stop') antes de continuar.${NC}"
read -p "¿Ya se cerró el terminal? (S/N): " TERMINAL_CERRADO

if [ "${TERMINAL_CERRADO^^}" != "S" ]; then
    echo -e "${RED}Por favor, cierra primero el terminal del servidor (escribe 'stop' en la consola del servidor).${NC}"
    echo -e "${YELLOW}Luego vuelve a ejecutar este script.${NC}"
    exit 1
fi

echo -e "${CYAN}Procediendo a hacer backup de los archivos del servidor...${NC}"

# --- Realizar backup Git ---
echo -e "${YELLOW}Iniciando copia de seguridad en GitHub...${NC}"

if [ ! -d ".git" ]; then
    echo -e "${RED}ERROR: No se encuentra la configuración de Git en esta carpeta.${NC}"
    echo -e "${RED}No se puede realizar la copia de seguridad.${NC}"
    exit 1
fi

echo -e "${CYAN}Preparando para la copia de seguridad: actualizando con la última versión de internet...${NC}"
git checkout main > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}ADVERTENCIA: No se pudo cambiar a la rama principal (main).${NC}"
fi

git pull origin main > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}ADVERTENCIA: Falló la actualización desde internet (git pull origin main).${NC}"
fi

# --- Descartar cambios en server.properties (evitar subir IP local) ---
echo -e "${CYAN}Descartando cambios en server.properties (para evitar subir la IP local)...${NC}"
if [ -f "server 2025/server.properties" ]; then
    git checkout -- "server 2025/server.properties" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Cambios en server.properties descartados correctamente.${NC}"
    else
        echo -e "${YELLOW}ADVERTENCIA: No se pudieron descartar cambios en server.properties (puede que no haya cambios).${NC}"
    fi
else
    echo -e "${YELLOW}ADVERTENCIA: No se encontró el archivo server.properties en la ruta esperada.${NC}"
fi

echo -e "${CYAN}Revisando si hay cambios en los archivos del mundo para guardar...${NC}"
git add -A > /dev/null 2>&1

if git status --porcelain | grep -q .; then
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${CYAN}Guardando los cambios detectados con fecha: $TIMESTAMP${NC}"
    
    git commit -m "Copia de seguridad automática: $TIMESTAMP" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: Falló al guardar los cambios localmente (git commit).${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Subiendo la copia de seguridad a internet (GitHub)...${NC}"
    git push origin main > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Copia de seguridad subida correctamente a GitHub.${NC}"
    else
        echo -e "${RED}ERROR: Falló la subida de la copia de seguridad a GitHub (git push).${NC}"
    fi
else
    echo -e "${CYAN}No hay cambios nuevos en los archivos del mundo para subir a la copia de seguridad.${NC}"
fi

echo ""
echo -e "${GREEN}--- Proceso de apagado LOCAL completado. ---${NC}"
