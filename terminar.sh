#!/bin/bash

# ------------------------------------------------------------
# Script: terminar.sh
# Propósito:
#   Asistente para apagar el servidor de Minecraft en modo LOCAL
#   para sistemas Linux/Mac.
#   Verifica que el servidor esté cerrado, desactiva IP flotante
#   y realiza backup en Git.
# ------------------------------------------------------------

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Configuración ---
IPFLOTANTE="172.25.254.254"

echo -e "${CYAN}--- Asistente para apagar el Servidor de Minecraft (LOCAL) ---${NC}"

# --- Verificar ejecución con sudo ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Este script debe ejecutarse con sudo.${NC}"
    echo -e "${RED}Ejecuta: sudo ./terminar.sh${NC}"
    exit 1
fi

# --- Verificar ZeroTier instalado ---
echo -e "${YELLOW}Verificando ZeroTier...${NC}"
if ! command -v zerotier-cli &> /dev/null; then
    echo -e "${RED}ERROR: ZeroTier no está instalado en el sistema.${NC}"
    exit 1
fi
echo -e "${GREEN}ZeroTier detectado.${NC}"

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

echo -e "${CYAN}Procediendo a desactivar IP y hacer backup...${NC}"

# --- Obtener interfaz ZeroTier ---
ZT_INTERFACE=$(ip addr show | grep -B 2 "zt" | grep "^[0-9]" | awk '{print $2}' | tr -d ':' | head -n 1)
if [ -z "$ZT_INTERFACE" ]; then
    echo -e "${YELLOW}ADVERTENCIA: No se encontró una interfaz de ZeroTier activa.${NC}"
else
    # --- Desactivar IP flotante ---
    echo -e "${YELLOW}Intentando desactivar la configuración de red (IP: $IPFLOTANTE)...${NC}"
    if ip addr show "$ZT_INTERFACE" | grep -q "$IPFLOTANTE"; then
        if ip addr del "$IPFLOTANTE/16" dev "$ZT_INTERFACE" 2>/dev/null; then
            echo -e "${GREEN}Configuración de red (IP: $IPFLOTANTE) desactivada correctamente.${NC}"
        else
            echo -e "${YELLOW}ADVERTENCIA: No se pudo desactivar la IP flotante.${NC}"
        fi
    else
        echo -e "${CYAN}INFORMACION: La IP flotante ($IPFLOTANTE) no estaba activa en este ordenador.${NC}"
    fi
fi

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
