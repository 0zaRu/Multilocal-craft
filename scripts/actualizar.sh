#!/bin/bash
# ------------------------------------------------------------
# Script: actualizar.sh
# Propósito:
#   Actualizar Paper y los plugins a la última versión que soporten todos
#   (ver actualizar.py). Acepta las mismas opciones: --check, --yes, --rollback...
# ------------------------------------------------------------
source "$(dirname "$0")/lib/comun.sh"

main() {
    buscar_python || { error "Hace falta Python 3 (ejecuta scripts/preparar; en Termux: pkg install python)."; exit 1; }
    "$PYTHON" "$SCRIPTS_DIR/actualizar.py" "$@"
}

main "$@"; exit $?
