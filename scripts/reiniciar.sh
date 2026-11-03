#!/bin/bash
# ------------------------------------------------------------
# Script: reiniciar.sh
# Propósito:
#   Reiniciar el servidor (modo terminal) y, con --actualizar, aplicar la actualización
#   entre medias: copia de seguridad en caliente (scripts/copia.sh), apagar, actualizar.py --yes
#   y volver a lanzar. El servidor nuevo se lanza dentro de tmux (sesión "mc"):
#   su consola se ve con 'tmux attach -t mc' o con scripts/consola.
#   Lo lanza la app de control (app-movil/) por SSH; también se puede usar a mano.
# Uso: scripts/reiniciar.sh [--actualizar]
# ------------------------------------------------------------
source "$(dirname "$0")/lib/comun.sh"

apagar() {
    info "Guardando el mundo y apagando el servidor..."
    "$PYTHON" "$SCRIPTS_DIR/rcon.py" "save-all flush" >/dev/null
    "$PYTHON" "$SCRIPTS_DIR/rcon.py" stop >/dev/null
    for _ in $(seq 1 90); do servidor_terminal_activo || break; sleep 2; done
    if servidor_terminal_activo; then error "El servidor no se ha apagado."; return 1; fi
    # iniciar.sh limpia al salir (Geyser, IP, SSH); si su ventana se cerró de golpe, se hace aquí
    for _ in $(seq 1 20); do [ -f "$ESTADO" ] || break; sleep 1; done
    if [ -f "$ESTADO" ]; then
        detener_arbol "$(estado_get pid_geyser)"
        restaurar_ip
        rm -f "$ESTADO"
    fi
    ok "Servidor apagado."
}

lanzar() {
    local ram="$1"
    info "Lanzando el servidor en tmux (sesión mc, ${ram} GB)..."
    tmux kill-session -t mc 2>/dev/null   # restos de un lanzamiento anterior (el servidor ya está apagado)
    tmux new-session -d -s mc -x 200 -y 50 \
        "cd '$ROOT' && bash scripts/iniciar.sh --terminal --sin-sincronizar $ram; echo; echo 'Servidor detenido.'; exec bash"
    for _ in $(seq 1 120); do servidor_terminal_activo && break; sleep 3; done
    if servidor_terminal_activo; then
        ok "SERVIDOR EN MARCHA. Consola: tmux attach -t mc"
    else
        error "EL SERVIDOR NO HA ARRANCADO. Míralo con: tmux attach -t mc"
        return 1
    fi
}

main() {
    local actualizar=0 ram rc n
    [ "$1" = --actualizar ] && actualizar=1
    leer_env
    detectar_so
    buscar_python
    cd "$ROOT" || exit 1
    info "--- $([ $actualizar = 1 ] && echo Actualizar || echo Reiniciar) el servidor: $(date '+%Y-%m-%d %H:%M:%S') ---"

    detectar_modo_activo
    if [ "$MODO_ACTIVO" = docker ]; then
        if [ $actualizar = 1 ]; then error "Desde la app solo se actualiza en modo terminal: usa scripts/terminar y scripts/actualizar."; exit 1; fi
        docker exec mc-server rcon-cli "save-all flush" >/dev/null
        docker restart mc-server >/dev/null && ok "SERVIDOR REINICIADO (Docker)." || { error "No se pudo reiniciar."; exit 1; }
        return 0
    fi
    if ! command -v tmux >/dev/null 2>&1; then
        error "Hace falta tmux para volver a lanzar el servidor (en Termux: pkg install tmux)."
        exit 1
    fi
    ram="$(estado_get ram)"
    [ -z "$ram" ] && { ram=6; [ "$SO" = termux ] && ram=3; }
    n=2; [ $actualizar = 1 ] && n=5   # pasos que ve la app

    if [ $actualizar = 1 ]; then
        paso "1/$n" "Copia de seguridad"
        MLC_SIN_PASOS=1 bash "$SCRIPTS_DIR/copia.sh"
        rc=$?
        if [ $rc = 1 ]; then error "ACTUALIZACIÓN CANCELADA: no se pudo hacer la copia de seguridad."; exit 1; fi
        [ $rc = 2 ] && aviso "La copia está en un commit local pero no se pudo subir; se sigue (se puede volver atrás con git)."
    fi
    if [ $actualizar = 1 ]; then paso "2/$n" "Apagando el servidor"; else paso "1/$n" "Apagando el servidor"; fi
    if [ -n "$MODO_ACTIVO" ]; then apagar || exit 1; fi

    rc=0
    if [ $actualizar = 1 ]; then
        paso "3/$n" "Instalando la actualización"
        info "Aplicando la actualización..."
        "$PYTHON" "$SCRIPTS_DIR/actualizar.py" --yes
        rc=$?
        leer_env
        case $rc in
            0) ok "ACTUALIZACIÓN APLICADA." ;;
            3) ok "No había nada que actualizar." ;;
            *) error "LA ACTUALIZACIÓN NO SE HA PODIDO APLICAR (código $rc): se vuelve a lanzar la versión que había." ;;
        esac
    fi
    if [ $actualizar = 1 ]; then paso "4/$n" "Arrancando el servidor"; else paso "$n/$n" "Arrancando el servidor"; fi
    lanzar "$ram" || exit 1
    [ $rc = 0 ] || [ $rc = 3 ] || exit 1
    if [ $actualizar = 1 ] && [ $rc = 0 ]; then
        # Los jars nuevos, .env y plugins.json solo están aquí: se suben para que el resto los reciba al sincronizar
        paso "5/$n" "Subiendo la versión nueva a GitHub"
        MLC_SIN_PASOS=1 bash "$SCRIPTS_DIR/copia.sh"
        [ $? = 0 ] || aviso "La versión nueva queda en un commit local; se subirá con la próxima copia."
    fi
}

main "$@"; exit $?
