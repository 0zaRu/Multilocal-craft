#!/bin/bash
# ------------------------------------------------------------
# Script: compilar.sh
# Propósito:
#   Compilar la app de control (APK) sin Gradle: aapt2 + javac + d8 + apksigner.
#   Necesita el SDK de Android (build-tools y una plataforma), un JDK 17+ y Python 3.
#   Firma con la clave de depuración de Android (~/.android/debug.keystore; se crea si no existe):
#   para instalar una versión nueva encima de la anterior hay que firmar con la misma clave.
# Uso: app-movil/compilar.sh   -> app-movil/build/Multilocal.apk
# ------------------------------------------------------------
source "$(dirname "$0")/../scripts/lib/comun.sh"

APP="$ROOT/app-movil"
B="$APP/build"

# herramienta <nombre> : ruta del ejecutable en build-tools (.exe/.bat en Windows)
herramienta() {
    local e
    for e in "$BT/$1" "$BT/$1.exe" "$BT/$1.bat"; do [ -f "$e" ] && { echo "$e"; return; }; done
    error "No se encuentra $1 en $BT"; exit 1
}
# ruta <path> : en Windows, la ruta en formato Windows (para javac y las herramientas del SDK)
ruta() { if [ "$SO" = windows ]; then cygpath -w "$1"; else echo "$1"; fi; }

main() {
    detectar_so
    buscar_python || { error "Hace falta Python 3."; exit 1; }
    local sdk sep
    for sdk in "$ANDROID_HOME" "$ANDROID_SDK_ROOT" "$LOCALAPPDATA/Android/Sdk" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
        [ -n "$sdk" ] && [ -d "$sdk/build-tools" ] && break
    done
    [ -d "$sdk/build-tools" ] || { error "No se encuentra el SDK de Android (define ANDROID_HOME)."; exit 1; }
    [ "$SO" = windows ] && sdk="$(cygpath -u "$sdk")"
    BT="$(ls -d "$sdk"/build-tools/* | sort -V | tail -n1)"
    local plataforma
    plataforma="$(ls -d "$sdk"/platforms/android-* | sort -V | tail -n1)/android.jar"
    sep=":"; [ "$SO" = windows ] && sep=";"
    info "SDK: $sdk  |  build-tools: ${BT##*/}  |  plataforma: $(basename "$(dirname "$plataforma")")"

    rm -rf "$B" && mkdir -p "$B/gen" "$B/clases" "$B/dex" || exit 1
    set -e
    info "Icono..."
    "$PYTHON" "$APP/icono.py" "$B/icono"

    info "Recursos (aapt2)..."
    "$(herramienta aapt2)" compile --dir "$(ruta "$APP/res")" -o "$(ruta "$B/res.zip")"
    "$(herramienta aapt2)" compile --dir "$(ruta "$B/icono")" -o "$(ruta "$B/icono.zip")"
    "$(herramienta aapt2)" link -o "$(ruta "$B/base.apk")" -I "$(ruta "$plataforma")" \
        --manifest "$(ruta "$APP/AndroidManifest.xml")" --java "$(ruta "$B/gen")" \
        --min-sdk-version 26 --target-sdk-version 34 "$(ruta "$B/res.zip")" "$(ruta "$B/icono.zip")"

    info "Java (javac)..."
    local fuentes=()
    while IFS= read -r f; do fuentes+=("$(ruta "$f")"); done < <(find "$APP/src" "$B/gen" -name '*.java')
    javac -nowarn --release 11 -encoding UTF-8 -d "$(ruta "$B/clases")" \
        -cp "$(ruta "$plataforma")$sep$(ruta "$APP/libs/jsch.jar")" "${fuentes[@]}"
    "$PYTHON" - "$B/clases" "$B/clases.jar" <<'EOF'
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[2], "w", zipfile.ZIP_DEFLATED) as z:
    for d, _, fs in os.walk(sys.argv[1]):
        for f in fs:
            z.write(os.path.join(d, f), os.path.relpath(os.path.join(d, f), sys.argv[1]).replace(os.sep, "/"))
EOF

    info "Dex (d8)..."
    # JSch trae clases para Java 9+ en META-INF/versions: d8 solo necesita las base (Java 8)
    "$PYTHON" - "$APP/libs/jsch.jar" "$B/jsch-base.jar" <<'EOF'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as a, zipfile.ZipFile(sys.argv[2], "w", zipfile.ZIP_DEFLATED) as b:
    for i in a.infolist():
        if i.filename.endswith(".class") and not i.filename.startswith("META-INF/"):
            b.writestr(i, a.read(i))
EOF
    "$(herramienta d8)" --release --min-api 26 --lib "$(ruta "$plataforma")" --output "$(ruta "$B/dex")" \
        "$(ruta "$B/clases.jar")" "$(ruta "$B/jsch-base.jar")" 2>&1 | grep -v -E "^(Warning|Missing class|  )" || true

    info "APK (zipalign + apksigner)..."
    "$PYTHON" - "$B/base.apk" "$B/dex/classes.dex" "$B/sin-firmar.apk" <<'EOF'
import shutil, sys, zipfile
shutil.copy(sys.argv[1], sys.argv[3])
with zipfile.ZipFile(sys.argv[3], "a", zipfile.ZIP_DEFLATED) as z:
    z.write(sys.argv[2], "classes.dex")
EOF
    "$(herramienta zipalign)" -f -p 4 "$(ruta "$B/sin-firmar.apk")" "$(ruta "$B/alineada.apk")"
    local ks="$HOME/.android/debug.keystore"
    if [ ! -f "$ks" ]; then
        local keytool
        keytool="$(command -v keytool || ls "${JAVA_HOME:-/nonexistent}"/bin/keytool* "/c/Program Files/Java"/jdk-*/bin/keytool.exe 2>/dev/null | head -n1)"
        mkdir -p "$HOME/.android"
        "$keytool" -genkeypair -keystore "$(ruta "$ks")" -storepass android -keypass android -alias androiddebugkey \
            -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
    fi
    "$(herramienta apksigner)" sign --ks "$(ruta "$ks")" --ks-pass pass:android --ks-key-alias androiddebugkey \
        --out "$(ruta "$B/Multilocal.apk")" "$(ruta "$B/alineada.apk")"
    "$(herramienta apksigner)" verify "$(ruta "$B/Multilocal.apk")"
    set +e
    ok "APK lista: app-movil/build/Multilocal.apk ($(du -k "$B/Multilocal.apk" | cut -f1) KB)"
}

main "$@"; exit $?
