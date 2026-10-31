#!/bin/bash
# ------------------------------------------------------------
# Script: terminar.sh
# Propósito:
#   Apagar el servidor (detecta si va por Docker o por terminal), guardando el mundo,
#   parar Geyser, devolver server-ip a su valor original y, si se quiere, subir el
#   mundo a GitHub (rama actual).
# Uso: scripts/terminar.sh
# ------------------------------------------------------------
source "$(dirname "$0")/lib/comun.sh"

terminar_docker() {
    info "Guardando el mundo..."
    docker exec mc-server rcon-cli save-all flush >/dev/null 2>&1
    local guardado=1
    for _ in $(seq 1 20); do
        docker logs --since 1m mc-server 2>&1 | grep -q "Saved the game" && { guardado=0; break; }
        sleep 2
    done
    if [ $guardado -ne 0 ]; then
        error "No se pudo confirmar el guardado del mundo. Se cancela para no perder datos; revisa scripts/consola."
        exit 1
    fi
    ok "Mundo guardado."
    info "Apagando servidor y Geyser..."
    docker exec mc-server rcon-cli stop >/dev/null 2>&1
    for _ in $(seq 1 30); do servidor_docker_activo || break; sleep 2; done
    docker compose -f "$ROOT/docker-compose.yml" down >/dev/null 2>&1
    ok "Contenedores parados."
}

terminar_terminal() {
    info "Guardando el mundo y apagando el servidor..."
    "$PYTHON" "$SCRIPTS_DIR/rcon.py" "save-all flush" >/dev/null && ok "Mundo guardado."
    "$PYTHON" "$SCRIPTS_DIR/rcon.py" "stop" >/dev/null
    for _ in $(seq 1 60); do servidor_terminal_activo || break; sleep 2; done
    if servidor_terminal_activo; then
        error "El servidor no se ha apagado. Escribe 'stop' en su ventana y vuelve a ejecutar esto."
        exit 1
    fi
    ok "Servidor apagado."
    # iniciar.sh limpia al salir (Geyser, IP); si su ventana se cerró de golpe, se hace aquí
    for _ in $(seq 1 15); do [ -f "$ESTADO" ] || break; sleep 1; done
    if [ -f "$ESTADO" ]; then
        detener_arbol "$(estado_get pid_geyser)"
        restaurar_ip
        rm -f "$ESTADO"
    fi
}

main() {
    leer_env
    detectar_so
    buscar_python || { error "Hace falta Python 3. Ejecuta scripts/preparar."; exit 1; }
    echo -e "${CYAN}${BOLD}--- Terminar servidor Multilocal-craft ---${NC}"

    detectar_modo_activo
    if [ -n "$MODO_ACTIVO" ]; then
        info "Servidor en marcha en modo: $MODO_ACTIVO"
        [ -n "$(estado_get ip)" ] && mostrar_ip "$(estado_get ip)"
        if [ "$MODO_ACTIVO" = docker ]; then terminar_docker; else terminar_terminal; fi
    else
        info "No hay ningún servidor en marcha en este equipo."
        # Restos de un cierre brusco (Geyser suelto, IP sin restaurar)
        [ -f "$ESTADO" ] && detener_arbol "$(estado_get pid_geyser)"
        if command -v docker >/dev/null 2>&1 && [ -n "$(docker ps -aq --filter name=^mc-geyser$ 2>/dev/null)" ]; then
            docker compose -f "$ROOT/docker-compose.yml" down >/dev/null 2>&1
        fi
    fi
    restaurar_ip
    rm -f "$ESTADO"
    printf '\033]0;Multilocal-craft\007'

    echo
    if preguntar_sn "¿Subir el mundo a GitHub (rama $(rama_actual))?"; then
        subir
    else
        info "No se ha subido nada. Puedes subirlo luego ejecutando scripts/terminar otra vez."
    fi
}

main "$@"; exit $?
