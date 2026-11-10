#!/bin/bash
# ------------------------------------------------------------
# Script: copia.sh
# Propósito:
#   Copia de seguridad sin apagar el servidor: guarda el mundo (save-off + save-all flush),
#   hace commit y lo sube a GitHub (rama actual). Con el servidor apagado, sube lo que haya.
#   El MUNDO no va a GitHub (.gitignore): solo la configuración y los datos de plugins y del
#   servidor. El mundo lo copia el anfitrión en local (en central: ~/backups/minecraft cada noche).
#   Lo lanza la app de control (app-movil/) por SSH; también se puede usar a mano.
#   Sale con 0 si se sube, 1 si no se pudo hacer la copia y 2 si se hizo pero no se pudo subir.
# Uso: scripts/copia.sh
# ------------------------------------------------------------
source "$(dirname "$0")/lib/comun.sh"

rcon_cmd() {
    if [ "$MODO_ACTIVO" = docker ]; then docker exec mc-server rcon-cli "$1"
    else "$PYTHON" "$SCRIPTS_DIR/rcon.py" "$1"; fi
}

guardado_on() { [ -n "$MODO_ACTIVO" ] && rcon_cmd save-on >/dev/null; }

main() {
    local rama id=()
    leer_env
    detectar_so
    buscar_python
    cd "$ROOT" || exit 1
    rama="$(rama_actual)"
    info "--- Copia de seguridad: $(date '+%Y-%m-%d %H:%M:%S'), rama $rama ---"

    detectar_modo_activo
    paso 1/4 "Guardando el mundo"
    if [ -n "$MODO_ACTIVO" ]; then
        info "Servidor en marcha ($MODO_ACTIVO): se guarda el mundo sin apagarlo."
        rcon_cmd save-off >/dev/null || { error "El servidor no responde por RCON."; exit 1; }
        trap guardado_on EXIT
        rcon_cmd "save-all flush" >/dev/null
        sleep 3
    fi

    paso 2/4 "Preparando los cambios"
    git add -A
    # La IP del dispositivo nunca se sube: con el servidor en marcha, server.properties se queda fuera
    if git diff --cached -- "server 2025/server.properties" | grep -qE '^[+-]server-ip='; then
        git reset -q -- "server 2025/server.properties"
    fi
    paso 3/4 "Guardando la copia (commit)"
    if git diff --cached --quiet; then
        info "No hay cambios nuevos que subir."
    else
        info "Cambios: $(git diff --cached --shortstat)"
        # Termux suele no tener identidad de git: se usa la del último commit
        [ -z "$(git config user.email)" ] && \
            id=(-c "user.name=$(git log -1 --format=%an)" -c "user.email=$(git log -1 --format=%ae)")
        if ! git "${id[@]}" commit -q -m "Copia de seguridad automática: $(date '+%Y-%m-%d %H:%M:%S') (en caliente)"; then
            error "Falló el commit."
            exit 1
        fi
        ok "Commit $(git log -1 --format=%h) hecho."
    fi
    guardado_on
    trap - EXIT

    paso 4/4 "Subiendo a GitHub"
    info "Subiendo a GitHub ($REMOTO/$rama)..."
    # --progress: el porcentaje sale en el log aunque no haya terminal (la app lo enseña)
    if git push --progress "$REMOTO" "$rama" 2>&1; then
        ok "COPIA SUBIDA a GitHub ($rama)."
    else
        error "NO SE PUDO SUBIR (¿falta el token de GitHub en este dispositivo, o alguien subió antes?)."
        error "La copia queda en un commit local y se subirá con la próxima copia o con scripts/terminar."
        exit 2
    fi
}

main "$@"; exit $?
