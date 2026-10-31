#!/bin/bash
# ------------------------------------------------------------
# Script: actualizar.sh
# Propósito:
#   Actualizar Paper y los plugins a la última versión que soporten todos
#   (ver actualizar.py). Acepta las mismas opciones: --check, --yes, --rollback...
#   Sin Python en este equipo (modo Docker), se ejecuta dentro de la imagen de
#   Geyser, que ya trae Java y Python.
# ------------------------------------------------------------
source "$(dirname "$0")/lib/comun.sh"

main() {
    detectar_so
    if buscar_python; then
        "$PYTHON" "$SCRIPTS_DIR/actualizar.py" "$@"
        return
    fi
    if ! docker info >/dev/null 2>&1; then
        error "Hace falta Python 3 o Docker funcionando. Ejecuta scripts/preparar."
        exit 1
    fi
    info "Sin Python en este equipo: el actualizador se ejecuta dentro de Docker."
    # Nunca como root: lo que escriba (jars, backups) tiene que poder tocarlo el servidor (uid 1000 en Docker)
    local repo="$ROOT" tty=(-i) usuario="1000:1000"
    [ "$SO" = windows ] && repo="$(cd "$ROOT" && pwd -W)"
    [ "$SO" != windows ] && usuario="$(id -u):$(id -g)"
    [ -t 0 ] && tty=(-it)
    docker compose -f "$repo/docker-compose.yml" build -q geyser || exit 1
    MSYS_NO_PATHCONV=1 docker compose -f "$repo/docker-compose.yml" run --rm --no-deps "${tty[@]}" --user "$usuario" -e HOME=/tmp \
        -v "$repo:/repo" -w /repo --entrypoint python3 geyser /repo/scripts/actualizar.py "$@"
}

main "$@"; exit $?
