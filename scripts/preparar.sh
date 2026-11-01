#!/bin/bash
# ------------------------------------------------------------
# Script: preparar.sh
# Propósito:
#   Comprobar qué herramientas hacen falta para lanzar el servidor (en Docker o en
#   terminal) en este sistema, e instalar las que falten. En Termux solo existe el modo terminal.
# Uso: scripts/preparar.sh [--docker|--terminal] [--check]
#   --check  solo comprobar y mostrar cómo se instalaría lo que falta
# Sistemas: Windows (Git Bash + winget), Termux, Debian/Ubuntu, Fedora, Arch, Mac (brew)
# ------------------------------------------------------------
source "$(dirname "$0")/lib/comun.sh"

SUDO=""
[ "$(id -u 2>/dev/null)" != "0" ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"

# --- Comprobaciones: cada una devuelve 0 si está bien ---
check_git()    { command -v git >/dev/null 2>&1; }
check_python() { buscar_python; }
check_java()   { buscar_java; }
check_docker() { command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; }
check_dockerd(){ docker info >/dev/null 2>&1; }
check_termuxapi() { command -v termux-wake-lock >/dev/null 2>&1; }
# Geyser necesita NetherNet (librería nativa solo para glibc): en Android corre dentro de un Debian (proot)
check_geyserdebian() {
    local r
    command -v proot-distro >/dev/null 2>&1 || return 1
    for r in "$PREFIX/var/lib/proot-distro/containers/debian/rootfs" "$PREFIX/var/lib/proot-distro/installed-rootfs/debian"; do
        [ -L "$r/usr/bin/java" ] || [ -e "$r/usr/bin/java" ] && return 0
    done
    return 1
}
zerotier_instalado() {
    command -v zerotier-cli >/dev/null 2>&1 && return 0
    [ "$SO" = windows ] && { [ -d "/c/ProgramData/ZeroTier" ] || [ -d "/c/Program Files (x86)/ZeroTier" ]; } && return 0
    [ "$SO" = mac ] && [ -d "/Library/Application Support/ZeroTier" ] && return 0
    return 1
}

# --- Cómo se instala cada cosa en cada sistema (vacío = no se puede automáticamente) ---
cmd_instalar() {
    local v="$JAVA_VERSION"
    case "$SO:$1" in
        windows:git)      echo "winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements" ;;
        windows:python)   echo "winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements" ;;
        windows:java)     echo "winget install -e --id EclipseAdoptium.Temurin.$v.JRE --accept-package-agreements --accept-source-agreements" ;;
        windows:docker)   echo "winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements" ;;
        windows:zerotier) echo "winget install -e --id ZeroTier.ZeroTierOne --accept-package-agreements --accept-source-agreements" ;;
        termux:git)       echo "pkg install -y git" ;;
        termux:python)    echo "pkg install -y python" ;;
        termux:java)      echo "pkg install -y openjdk-$v" ;;
        termux:termuxapi) echo "pkg install -y termux-api" ;;
        termux:geyserdebian) echo "pkg install -y proot-distro libandroid-shmem proot && { proot-distro list 2>/dev/null | grep -q '\* debian' || proot-distro install debian; } && proot-distro login debian -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-$v-jre-headless'" ;;
        debian:git)       echo "$SUDO apt-get update && $SUDO apt-get install -y git" ;;
        debian:python)    echo "$SUDO apt-get update && $SUDO apt-get install -y python3" ;;
        debian:java)      echo "$SUDO apt-get update && $SUDO apt-get install -y openjdk-$v-jre-headless" ;;
        debian:docker)    echo "$SUDO apt-get update && $SUDO apt-get install -y docker.io docker-compose-v2" ;;
        debian:zerotier)  echo "$SUDO apt-get install -y curl gnupg && curl -s https://install.zerotier.com | $SUDO bash" ;;
        fedora:zerotier)  echo "curl -s https://install.zerotier.com | $SUDO bash" ;;
        fedora:git)       echo "$SUDO dnf install -y git" ;;
        fedora:python)    echo "$SUDO dnf install -y python3" ;;
        fedora:java)      echo "$SUDO dnf install -y java-$v-openjdk-headless" ;;
        fedora:docker)    echo "$SUDO dnf install -y moby-engine docker-compose" ;;
        arch:git)         echo "$SUDO pacman -S --noconfirm git" ;;
        arch:python)      echo "$SUDO pacman -S --noconfirm python" ;;
        arch:java)        echo "$SUDO pacman -S --noconfirm jre$v-openjdk-headless" ;;
        arch:docker)      echo "$SUDO pacman -S --noconfirm docker docker-compose" ;;
        arch:zerotier)    echo "$SUDO pacman -S --noconfirm zerotier-one" ;;
        mac:git)          echo "brew install git" ;;
        mac:python)       echo "brew install python" ;;
        mac:java)         echo "brew install openjdk@$v" ;;
        mac:docker)       echo "brew install --cask docker" ;;
        mac:zerotier)     echo "brew install --cask zerotier-one" ;;
    esac
}

FALTAN=()   # lo que se puede instalar automáticamente
FALLOS=0    # todo lo que no está bien (incluido lo que hay que hacer a mano)
fila() {  # fila <clave> <nombre> <0|1 resultado> [nota]
    if [ "$3" = 0 ]; then
        printf "  ${GREEN}%-8s${NC} %-28s %s\n" "OK" "$2" "$4"
    else
        printf "  ${RED}%-8s${NC} %-28s %s\n" "FALTA" "$2" "$4"
        FALLOS=$((FALLOS + 1))
        [ -n "$1" ] && FALTAN+=("$1")
    fi
}

# Lo que se comprueba depende del modo:
#   terminal: Git, Python, Java, ZeroTier (+ termux-api en Termux)  -> todo corre en este equipo
#   docker:   Git, Docker, ZeroTier                                 -> Java y Python van dentro de los contenedores
comprobar() {
    FALTAN=()
    FALLOS=0
    PYTHON=""
    echo
    echo -e "${BOLD}Comprobando ($SO, modo $MODO):${NC}"
    check_git; fila git "Git" $?
    if [ "$MODO" = terminal ]; then
        check_python; fila python "Python 3.8+" $? "${PYTHON:+($PYTHON)}"
        check_java;   fila java "Java $JAVA_VERSION+" $? "(encontrado: ${JAVA_MAJOR:-ninguno})"
        [ "$SO" = termux ] && { check_termuxapi; fila termuxapi "termux-api (wake-lock)" $? "(instala también la app Termux:API)"; }
        [ "$SO" = termux ] && { check_geyserdebian; fila geyserdebian "Debian (proot) para Geyser" $? "(Bedrock actual usa NetherNet: necesita glibc)"; }
    else
        check_docker; fila docker "Docker + docker compose" $?
        if check_docker; then
            if check_dockerd; then fila "" "Docker funcionando" 0
            else fila "" "Docker funcionando" 1 "(abre Docker Desktop / arranca el servicio)"; fi
        fi
    fi
    local ip_zt
    ip_zt="$(ip_en_red "$ZEROTIER_RED")"
    if [ -n "$ip_zt" ]; then
        fila "" "ZeroTier en $ZEROTIER_RED" 0 "(IP: $ip_zt)"
    elif zerotier_instalado; then
        fila "" "ZeroTier en $ZEROTIER_RED" 1 "(instalado; únete a la red: zerotier-cli join $ZEROTIER_ID)"
    elif [ "$SO" = termux ]; then
        fila "" "ZeroTier en $ZEROTIER_RED" 1 "(instala la app ZeroTier One y únete a la red $ZEROTIER_ID)"
    else
        fila zerotier "ZeroTier" 1
    fi
}

main() {
    local solo_check=0 modo_arg=""
    for a in "$@"; do
        case "$a" in
            --check) solo_check=1 ;;
            --docker|--terminal) modo_arg="$a" ;;
        esac
    done
    leer_env
    detectar_so
    echo -e "${CYAN}${BOLD}--- Preparar el entorno para Multilocal-craft ---${NC}"
    preguntar_modo "$modo_arg"
    comprobar

    if [ "$FALLOS" -eq 0 ]; then
        echo; ok "Todo listo para lanzar en modo $MODO."
        return 0
    fi
    if [ ${#FALTAN[@]} -eq 0 ]; then
        echo; aviso "Lo que falta hay que hacerlo a mano (ver arriba)."
        return 1
    fi

    echo; aviso "Para instalar lo que falta se ejecutará:"
    local k c
    for k in "${FALTAN[@]}"; do
        c="$(cmd_instalar "$k")"
        if [ -n "$c" ]; then echo "  $c"; else echo "  ($k: no se puede instalar automáticamente en $SO)"; fi
    done
    [ $solo_check = 1 ] && return 1
    echo
    preguntar_sn "¿Instalar ahora?" || return 1
    for k in "${FALTAN[@]}"; do
        c="$(cmd_instalar "$k")"
        [ -z "$c" ] && continue
        info "> $c"
        bash -c "$c" || error "Falló la instalación de $k."
    done
    [ "$SO" = windows ] && aviso "En Windows, cierra y vuelve a abrir la ventana para que se vean los programas nuevos."
    comprobar
    if [ "$FALLOS" -eq 0 ]; then echo; ok "Todo listo para lanzar en modo $MODO."
    else echo; aviso "Aún falta algo (ver arriba)."; return 1; fi
}

main "$@"; exit $?
