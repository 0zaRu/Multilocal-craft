#!/bin/bash
# ------------------------------------------------------------
# Script: actualizar.sh
# Propósito:
#   Actualizar Paper y los plugins a la última versión que soporten todos
#   (ver actualizar.py). Acepta las mismas opciones: --check, --yes, --rollback...
# ------------------------------------------------------------
cd "$(dirname "$0")" || exit 1

# En Windows "python3" puede ser el acceso directo a la Microsoft Store: probar que funciona
PYTHON=""
for p in python3 python; do
    if command -v "$p" >/dev/null && "$p" -c "import sys" >/dev/null 2>&1; then PYTHON="$p"; break; fi
done
if [ -z "$PYTHON" ]; then
    echo "ERROR: hace falta Python 3 (en Termux: pkg install python)."
    exit 1
fi

"$PYTHON" actualizar.py "$@"
