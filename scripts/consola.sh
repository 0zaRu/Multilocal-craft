#!/bin/bash
# ------------------------------------------------------------
# Script: consola.sh
# Propósito:
#   Abrir la consola del servidor, vaya por Docker o por terminal.
# Uso: scripts/consola.sh
# ------------------------------------------------------------
source "$(dirname "$0")/lib/comun.sh"

main() {
    leer_env
    detectar_so
    buscar_python || { error "Hace falta Python 3. Ejecuta scripts/preparar."; exit 1; }
    detectar_modo_activo
    if [ -z "$MODO_ACTIVO" ]; then
        aviso "No hay ningún servidor en marcha en este equipo. Arráncalo con scripts/iniciar."
        exit 1
    fi
    [ -n "$(estado_get ip)" ] && mostrar_ip "$(estado_get ip)"
    if [ "$MODO_ACTIVO" = docker ]; then
        info "Consola (Docker). Escribe comandos sin '/'; Ctrl+C para salir."
        if [ ! -t 0 ]; then
            docker exec -i mc-server rcon-cli          # entrada redirigida (sin terminal)
        elif [ "$SO" = windows ] && command -v winpty >/dev/null 2>&1; then
            winpty docker exec -it mc-server rcon-cli
        else
            docker exec -it mc-server rcon-cli
        fi
    else
        "$PYTHON" -u "$SCRIPTS_DIR/rcon.py" --interactivo
    fi
}

main "$@"; exit $?
