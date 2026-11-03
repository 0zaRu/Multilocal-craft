#!/bin/bash
# ------------------------------------------------------------
# Script: iniciar.sh
# Propósito:
#   Arrancar el servidor (Docker o terminal) con Geyser y la IP de ZeroTier
#   de este dispositivo. Opcionalmente sincroniza antes el mundo con GitHub.
# Uso: scripts/iniciar.sh [--docker|--terminal] [--sin-sincronizar] [GB_RAM]
# ------------------------------------------------------------
source "$(dirname "$0")/lib/comun.sh"

limpiar_terminal() {
    detener_arbol "$(estado_get pid_geyser)"
    parar_sshd
    restaurar_ip
    rm -f "$ESTADO"
    [ "$SO" = termux ] && command -v termux-wake-unlock >/dev/null && termux-wake-unlock
}

iniciar_docker() {
    if ! docker info >/dev/null 2>&1; then
        error "Docker no está funcionando (abre Docker Desktop o arranca el servicio). Ejecuta scripts/preparar."
        exit 1
    fi
    info "Arrancando contenedores (servidor + Geyser)..."
    MLC_IP="$IP" GEYSER_MODE="$GEYSER_MODE" docker compose -f "$ROOT/docker-compose.yml" up -d --build || exit 1
    estado_set modo docker
    estado_set ip "$IP"
    info "Esperando a que el servidor termine de arrancar..."
    for _ in $(seq 1 120); do
        docker logs --since 10m mc-server 2>&1 | grep -q "Done (" && break
        sleep 3
    done
    if docker logs --since 10m mc-server 2>&1 | grep -q "Done ("; then
        ok "Servidor listo."
    else
        aviso "El servidor tarda en arrancar; míralo con scripts/consola o 'docker logs -f mc-server'."
    fi
    mostrar_ip "$IP"
    info "Consola: scripts/consola   |   Apagar y guardar: scripts/terminar"
}

iniciar_terminal() {
    local ram="$1"
    if ! buscar_java; then
        error "Hace falta Java $JAVA_VERSION o superior (encontrado: ${JAVA_MAJOR:-ninguno}). Ejecuta scripts/preparar."
        exit 1
    fi
    if [ -z "$PAPER_JAR" ] || [ ! -f "$SERVER_DIR/$PAPER_JAR" ]; then
        PAPER_JAR=$(ls -t "$SERVER_DIR"/paper-*.jar 2>/dev/null | head -n1)
        PAPER_JAR="${PAPER_JAR##*/}"
    fi
    [ -z "$PAPER_JAR" ] && { error "No se encuentra el jar de Paper. Ejecuta scripts/actualizar."; exit 1; }
    if [ -z "$ram" ]; then
        # En el móvil (7-8 GB de RAM) 3 GB es lo que mejor funcionó en las pruebas; en PC, 6
        local def=6; [ "$SO" = termux ] && def=3
        read -r -p "Memoria RAM para el servidor en GB (Enter = $def): " ram
        ram="${ram:-$def}"
    fi

    estado_set modo terminal
    estado_set ip "$IP"
    estado_set ram "$ram"   # para relanzar igual desde la app (scripts/reiniciar.sh)
    trap limpiar_terminal EXIT
    trap 'exit 130' INT TERM HUP
    aplicar_ip "$IP" || exit 1

    # Geyser (conexión para Bedrock / móviles)
    if [ -f "$SERVER_DIR/geyser/Geyser-Standalone.jar" ]; then
        local extra=()
        [ "$GEYSER_MODE" = siempre ] && extra+=(--siempre)
        # Con server-ip fijado, Java solo escucha en esa IP (no en 127.0.0.1): Geyser va también por ella
        [ "$IP" != "0.0.0.0" ] && extra+=(--escuchar "$IP" --anunciar "$IP" --java-address "$IP")
        "$PYTHON" -u "$SCRIPTS_DIR/geyser-bajo-demanda.py" --java "$JAVA" "${extra[@]}" \
            > "$SERVER_DIR/logs/geyser-bajo-demanda.log" 2>&1 &
        estado_set pid_geyser "$(pid_nativo $!)"
        info "Geyser ($GEYSER_MODE) en marcha. Log: server 2025/logs/geyser-bajo-demanda.log"
    else
        aviso "No está Geyser-Standalone.jar: sin conexión para Bedrock. Ejecuta scripts/actualizar."
    fi

    [ "$SO" = termux ] && command -v termux-wake-lock >/dev/null && termux-wake-lock
    [ "$SO" = termux ] && arrancar_sshd
    mostrar_ip "$IP"
    aviso "Esta ventana es la consola del servidor: no la cierres. Para apagar: 'stop' aquí o scripts/terminar."
    echo
    cd "$SERVER_DIR" || exit 1
    # Memoria fija (Xms = Xmx) y JAVA_OPTS de .env (recolector de basura ajustado; ver docs/pruebas-movil.md)
    # shellcheck disable=SC2086
    "$JAVA" -Xms"${ram}"G -Xmx"${ram}"G $JAVA_OPTS -jar "$PAPER_JAR" nogui
    cd "$ROOT" || exit 1
    echo
    info "Servidor detenido. Para guardar el mundo en GitHub: scripts/terminar"
}

main() {
    local modo_arg="" ram="" sincronizar=1
    for a in "$@"; do
        case "$a" in
            --docker|--terminal) modo_arg="$a" ;;
            --sin-sincronizar) sincronizar=0 ;;
            *) ram="$a" ;;
        esac
    done
    leer_env
    detectar_so
    buscar_python   # solo obligatorio en modo terminal (en Docker, Geyser lleva su propio Python)
    echo -e "${CYAN}${BOLD}--- Iniciar servidor Multilocal-craft ---${NC}"

    detectar_modo_activo
    if [ -n "$MODO_ACTIVO" ]; then
        aviso "El servidor ya está en marcha en este equipo (modo $MODO_ACTIVO)."
        [ -n "$(estado_get ip)" ] && mostrar_ip "$(estado_get ip)"
        exit 0
    fi
    rm -f "$ESTADO"

    preguntar_modo "$modo_arg"
    if [ "$MODO" = terminal ] && [ -z "$PYTHON" ]; then
        error "El modo terminal necesita Python 3. Ejecuta scripts/preparar."
        exit 1
    fi
    if [ $sincronizar = 1 ] && preguntar_sn "¿Sincronizar el mundo con GitHub antes de empezar (rama $(rama_actual))?"; then
        sincronizar
        leer_env   # .env puede haber cambiado (versión nueva)
    fi
    detectar_ip
    mostrar_ip "$IP"

    if [ "$MODO" = docker ]; then iniciar_docker; else iniciar_terminal "$ram"; fi
}

main "$@"; exit $?
