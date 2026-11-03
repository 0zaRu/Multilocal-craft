# shellcheck shell=bash
# ------------------------------------------------------------
# lib/comun.sh: funciones compartidas por los scripts de Multilocal-craft.
# Se carga con: source "$(dirname "$0")/lib/comun.sh"
# ------------------------------------------------------------

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
SERVER_DIR="$ROOT/server 2025"
PROPS="$SERVER_DIR/server.properties"
ESTADO="$SERVER_DIR/.estado-servidor"
REMOTO="${MLC_REMOTO:-origin}"   # MLC_REMOTO solo se usa en las pruebas

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}$*${NC}"; }
ok()    { echo -e "${GREEN}$*${NC}"; }
aviso() { echo -e "${YELLOW}$*${NC}"; }
error() { echo -e "${RED}$*${NC}" >&2; }
# paso "2/4" "texto": marca de progreso que la app de control lee del log (scripts/panel.py)
paso()  { [ -n "$MLC_SIN_PASOS" ] || info "PASO $1: $2"; }

# preguntar_sn "¿Pregunta?"  -> 0 si responde S/s
preguntar_sn() {
    local r
    read -r -p "$1 (S/N): " r
    [[ "$r" =~ ^[SsYy] ]]
}

# preguntar_modo [argumento]  -> deja MODO=docker|terminal (necesita detectar_so antes)
preguntar_modo() {
    if [ "$SO" = termux ]; then
        [ "$1" = --docker ] && aviso "Docker no existe en Android: se usa el modo terminal."
        MODO=terminal; return
    fi
    case "$1" in
        --docker) MODO=docker; return ;;
        --terminal) MODO=terminal; return ;;
    esac
    echo -e "${YELLOW}¿Cómo quieres lanzar el servidor?${NC}"
    echo "  1) Terminal (Java directamente en este equipo / móvil)"
    echo "  2) Docker"
    local r
    read -r -p "Opción (1/2): " r
    case "$r" in
        1) MODO=terminal ;;
        2) MODO=docker ;;
        *) error "Opción no válida."; exit 1 ;;
    esac
}

# --- .env (versiones y ajustes comunes) ---
leer_env() {
    PAPER_JAR=""; JAVA_VERSION=25; GEYSER_MODE=ondemand; ZEROTIER_RED=172.25.0.0/16; ZEROTIER_ID=""; JAVA_OPTS=""
    if [ -f "$ROOT/.env" ]; then
        local k v
        while IFS='=' read -r k v; do
            v="${v%$'\r'}"
            case "$k" in
                PAPER_JAR) PAPER_JAR="$v" ;;
                JAVA_VERSION) JAVA_VERSION="$v" ;;
                GEYSER_MODE) GEYSER_MODE="$v" ;;
                ZEROTIER_RED) ZEROTIER_RED="$v" ;;
                ZEROTIER_ID) ZEROTIER_ID="$v" ;;
                JAVA_OPTS) JAVA_OPTS="$v" ;;
            esac
        done < <(grep -E '^[A-Z_]+=' "$ROOT/.env")
    fi
}

# --- Sistema operativo: windows | termux | mac | debian | fedora | arch | linux ---
detectar_so() {
    if [ -n "$TERMUX_VERSION" ] || [[ "$PREFIX" == *com.termux* ]]; then SO=termux; return; fi
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) SO=windows; return ;;
        Darwin) SO=mac; return ;;
    esac
    SO=linux
    if [ -f /etc/os-release ]; then
        local ids
        ids="$(. /etc/os-release; echo "$ID $ID_LIKE")"
        case "$ids" in
            *debian*|*ubuntu*) SO=debian ;;
            *fedora*|*rhel*|*centos*) SO=fedora ;;
            *arch*) SO=arch ;;
        esac
    fi
}

# --- Python >= 3.8 (descarta el acceso directo de la Microsoft Store) ---
buscar_python() {
    PYTHON=""
    local p
    for p in python3 python; do
        if command -v "$p" >/dev/null 2>&1 && \
           "$p" -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" >/dev/null 2>&1; then
            PYTHON="$p"; return 0
        fi
    done
    return 1
}

# --- Java: usa $JAVA, el del PATH o, si es antiguo, uno instalado de la versión necesaria
#     (Termux y Linux pueden tener varios: java-21, java-25...). Deja JAVA y JAVA_MAJOR ---
_java_mayor() { "$1" -version 2>&1 | grep -oE 'version "[0-9]+' | grep -oE '[0-9]+$'; }
buscar_java() {
    local c
    for c in "${JAVA:-java}" \
             "$PREFIX"/lib/jvm/java-"$JAVA_VERSION"*/bin/java \
             /usr/lib/jvm/*-"$JAVA_VERSION"*/bin/java /usr/lib/jvm/java-"$JAVA_VERSION"*/bin/java \
             /opt/homebrew/opt/openjdk@"$JAVA_VERSION"/bin/java /usr/local/opt/openjdk@"$JAVA_VERSION"/bin/java; do
        command -v "$c" >/dev/null 2>&1 || [ -x "$c" ] || continue
        JAVA_MAJOR="$(_java_mayor "$c")"
        if [ -n "$JAVA_MAJOR" ] && [ "$JAVA_MAJOR" -ge "$JAVA_VERSION" ]; then JAVA="$c"; return 0; fi
    done
    JAVA="${JAVA:-java}"; JAVA_MAJOR="$(_java_mayor "$JAVA")"
    return 1
}

# --- Estado del servidor en marcha (server 2025/.estado-servidor) ---
estado_get() { [ -f "$ESTADO" ] && grep -E "^$1=" "$ESTADO" | head -n1 | cut -d= -f2-; }
estado_set() {
    local tmp
    tmp="$(grep -vE "^$1=" "$ESTADO" 2>/dev/null)"
    { [ -n "$tmp" ] && echo "$tmp"; echo "$1=$2"; } > "$ESTADO"
}

servidor_docker_activo() {
    command -v docker >/dev/null 2>&1 && \
        [ -n "$(docker ps -q --filter name=^mc-server$ --filter status=running 2>/dev/null)" ]
}
servidor_terminal_activo() {
    [ -n "$PYTHON" ] && "$PYTHON" "$SCRIPTS_DIR/rcon.py" --comprobar
}

# Deja MODO_ACTIVO=docker|terminal|"" según lo que esté en marcha ahora
detectar_modo_activo() {
    MODO_ACTIVO=""
    if servidor_docker_activo; then MODO_ACTIVO=docker
    elif servidor_terminal_activo; then MODO_ACTIVO=terminal
    fi
}

# --- IP del dispositivo en la red ZeroTier del servidor ---
_ip_a_num() { local IFS=.; set -- $1; echo $(( ($1 << 24) + ($2 << 16) + ($3 << 8) + $4 )); }
# ip_en_red <red/prefijo>: imprime la IP de este dispositivo dentro de esa red (vacío si no está)
ip_en_red() {
    if [ -n "$PYTHON" ]; then
        # Con Python: truco del socket UDP (también funciona en Termux, donde 'ip addr' suele estar bloqueado)
        "$PYTHON" "$SCRIPTS_DIR/lib/ip_zerotier.py" "$1" 2>/dev/null
        return
    fi
    # Sin Python (modo Docker): listar las IPv4 del sistema y quedarse con la de la red
    local red="${1%/*}" bits="${1#*/}" mascara ip lista
    mascara=$(( (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
    case "$SO" in
        windows) lista="$(powershell.exe -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4).IPAddress" 2>/dev/null | tr -d '\r')" ;;
        mac)     lista="$(ifconfig 2>/dev/null | awk '/inet /{print $2}')" ;;
        *)       lista="$(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1)"
                 [ -z "$lista" ] && lista="$(hostname -I 2>/dev/null | tr ' ' '\n')" ;;
    esac
    for ip in $lista; do
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        if [ $(( $(_ip_a_num "$ip") & mascara )) -eq $(( $(_ip_a_num "$red") & mascara )) ]; then
            echo "$ip"; return
        fi
    done
}

# Deja IP=<ip de ZeroTier> o IP=0.0.0.0 si se decide seguir sin ZeroTier
detectar_ip() {
    IP="$(ip_en_red "$ZEROTIER_RED")"
    if [ -z "$IP" ]; then
        echo
        echo -e "${RED}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}${BOLD}   ESTE DISPOSITIVO NO ESTÁ EN LA RED ZEROTIER ($ZEROTIER_RED)${NC}"
        echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
        aviso "Conecta ZeroTier (red del servidor) y vuelve a lanzar, o sigue solo en red local."
        if preguntar_sn "¿Seguir sin ZeroTier (escuchando en todas las interfaces)?"; then
            IP=0.0.0.0
        else
            exit 1
        fi
    fi
}

puerto_java()    { grep -E '^server-port=' "$PROPS" | cut -d= -f2 | tr -d '\r'; }
puerto_bedrock() { grep -m1 -E '^  port:' "$SERVER_DIR/geyser/config.yml" | grep -oE '[0-9]+'; }

# mostrar_ip <ip> : recuadro con la dirección a la que conectarse (y título de la ventana)
mostrar_ip() {
    local ip="$1" texto
    texto="$ip"
    [ "$ip" = "0.0.0.0" ] && texto="todas las interfaces (SIN ZeroTier)"
    printf '\033]0;Multilocal-craft — %s:%s\007' "$ip" "$(puerto_java)"
    echo
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}   SERVIDOR EN:   $texto${NC}"
    echo -e "${GREEN}${BOLD}   Java .......   $ip:$(puerto_java)${NC}"
    echo -e "${GREEN}${BOLD}   Bedrock ....   $ip:$(puerto_bedrock)  (Geyser: $GEYSER_MODE)${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# --- server-ip en server.properties (solo modo terminal) ---
# Escribe server-ip y comprueba que se ha guardado (en Windows otro proceso puede tener el
# fichero bloqueado un momento: se reintenta). Devuelve 1 si no se pudo.
_poner_server_ip() {
    local tmp="$PROPS.tmp" _
    for _ in $(seq 1 30); do
        awk -v ip="$1" '/^server-ip=/{print "server-ip=" ip; next} {print}' "$PROPS" > "$tmp" && \
            { cat "$tmp" > "$PROPS"; } 2>/dev/null
        if grep -qxF "server-ip=$1" <(tr -d '\r' < "$PROPS"); then rm -f "$tmp"; return 0; fi
        sleep 1
    done
    rm -f "$tmp"
    error "No se pudo escribir server-ip=$1 en server.properties (fichero bloqueado por otro programa)."
    return 1
}
aplicar_ip() {
    local orig
    orig="$(grep -E '^server-ip=' "$PROPS" | cut -d= -f2- | tr -d '\r')"
    [ -z "$(estado_get server_ip_original)" ] && estado_set server_ip_original "$orig"
    [ "$orig" = "$1" ] && return 0
    _poner_server_ip "$1" || return 1
    info "server-ip: $orig → $1 (se restaura al terminar)"
}
restaurar_ip() {
    local orig actual
    orig="$(estado_get server_ip_original)"
    if [ -z "$orig" ]; then
        orig="$(git -C "$ROOT" show "HEAD:server 2025/server.properties" 2>/dev/null | grep -E '^server-ip=' | cut -d= -f2- | tr -d '\r')"
    fi
    actual="$(grep -E '^server-ip=' "$PROPS" | cut -d= -f2- | tr -d '\r')"
    if [ "$actual" != "$orig" ]; then
        _poner_server_ip "$orig" && info "server-ip: $actual → $orig (original)"
    fi
}

# --- Procesos ---
# detener_arbol <pid de Windows o POSIX> : para un proceso y sus hijos (Geyser va como hijo del vigilante)
detener_arbol() {
    [ -z "$1" ] && return
    if [ "$SO" = windows ]; then
        taskkill //T //F //PID "$1" >/dev/null 2>&1
    else
        kill -TERM "$1" 2>/dev/null
        for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$1" 2>/dev/null || return; sleep 1; done
        kill -KILL "$1" 2>/dev/null
    fi
}
# pid_nativo <pid de bash> : en Windows, el PID real del proceso (para taskkill)
pid_nativo() {
    if [ "$SO" = windows ] && [ -r "/proc/$1/winpid" ]; then cat "/proc/$1/winpid"; else echo "$1"; fi
}

# --- SSH para la app de control (app-movil/), solo en Termux y solo mientras el servidor está en marcha ---
arrancar_sshd() {
    if ! command -v sshd >/dev/null 2>&1; then
        aviso "Sin openssh: la app de control no podrá conectarse (pkg install openssh)."
        return
    fi
    pgrep -x sshd >/dev/null 2>&1 && return   # ya estaba en marcha antes: no es nuestro y no se para
    sshd && estado_set sshd_propio 1 && info "App de control: SSH en el puerto 8022 mientras el servidor esté en marcha."
}
parar_sshd() {
    [ "$(estado_get sshd_propio)" = 1 ] || return
    # Solo el proceso que escucha: las sesiones abiertas (sshd-session) siguen hasta que se cierren
    kill "$(cat "$PREFIX/var/run/sshd.pid" 2>/dev/null)" 2>/dev/null
}

# --- Git (siempre la rama actual) ---
rama_actual() { git -C "$ROOT" rev-parse --abbrev-ref HEAD; }

sincronizar() {
    local rama
    rama="$(rama_actual)"
    aviso "Se descargará la última versión de '$rama' desde '$REMOTO'."
    aviso "ATENCIÓN: los cambios locales que no hayas subido se perderán."
    preguntar_sn "¿Seguro?" || { info "Se usan los datos locales."; return 0; }
    if git -C "$ROOT" fetch "$REMOTO" "$rama" && git -C "$ROOT" reset --hard "$REMOTO/$rama"; then
        ok "Mundo actualizado desde GitHub ($rama)."
    else
        error "No se pudo sincronizar. Se continúa con los datos locales."
    fi
}

subir() {
    local rama cambios_mundo
    rama="$(rama_actual)"
    restaurar_ip
    cd "$ROOT" || return 1
    git add -A
    if git diff --cached --quiet; then
        info "No hay cambios que subir."
        return 0
    fi
    # Seguridad: nunca subir la IP de un dispositivo en server.properties
    if git diff --cached -- "server 2025/server.properties" | grep -qE '^[+-]server-ip='; then
        git reset -q
        error "server.properties tiene una IP distinta de la original. NO se sube nada; revisa 'server-ip='."
        return 1
    fi
    cambios_mundo="$(git diff --cached --name-only -- "server 2025/world" "server 2025/world_nether" "server 2025/world_the_end" | wc -l)"
    if [ "$cambios_mundo" -gt 500 ]; then
        aviso "Hay $cambios_mundo ficheros del mundo cambiados. Suele ser la conversión del mundo a una versión"
        aviso "nueva de Minecraft (se sube una sola vez; git solo envía lo que de verdad cambia)."
        if ! preguntar_sn "¿Subirlo?"; then git reset -q; info "No se ha subido nada."; return 0; fi
    fi
    git commit -q -m "Copia de seguridad automática: $(date '+%Y-%m-%d %H:%M:%S')" || { error "Falló el commit."; return 1; }
    if git ls-remote --exit-code --heads "$REMOTO" "$rama" >/dev/null 2>&1 && \
       ! git pull -q --no-rebase --no-edit "$REMOTO" "$rama"; then
        error "No se pudo integrar lo que hay en GitHub (¿alguien más subió cambios?). Tu copia está guardada en un commit local; avisa para resolverlo."
        return 1
    fi
    if git push -q "$REMOTO" "$rama"; then
        ok "Copia de seguridad subida a GitHub ($rama)."
    else
        error "Falló la subida a GitHub (git push)."
        return 1
    fi
}
