#!/usr/bin/env python3
# ------------------------------------------------------------
# Script: geyser-bajo-demanda.py
# Propósito:
#   Mantener Geyser (la conexión para móviles / Minecraft Bedrock) APAGADO
#   mientras nadie lo use, y encenderlo cuando un jugador de Bedrock intenta entrar.
#
#   - Con Geyser apagado, este script escucha en los puertos de Bedrock:
#       * responde al listado de servidores (ping RakNet) con un aviso,
#       * el primer intento de conexión (RakNet, señalización NetherNet o WebRTC)
#         arranca Geyser. Ese primer intento falla: hay que reintentar en ~30 s.
#   - Con Geyser encendido, lleva la lista de jugadores de Bedrock con los eventos
#     de conexión/desconexión de Geyser y lo apaga 3 minutos (--idle-min) después
#     de que salga el último. Cada 2 min comprueba con "geyser list" por si acaso.
#
# Uso (lo lanzan iniciar.sh / iniciar.bat y Docker; no hace falta a mano):
#   python geyser-bajo-demanda.py [--java java] [--idle-min 10]
# Solo usa la librería estándar de Python.
# ------------------------------------------------------------
import argparse
import os
import random
import re
import select
import shlex
import shutil
import signal
import socket
import struct
import subprocess
import sys
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # carpeta del repo (padre de scripts/)
MAGIC = bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")
GUID = random.getrandbits(63)


def log(msg):
    print(time.strftime("[%H:%M:%S] ") + msg, flush=True)


def read_ports(config):
    """Puerto de Bedrock (RakNet UDP + señalización TCP) y puerto WebRTC (UDP) del config.yml de Geyser."""
    port, webrtc = 19132, 0
    with open(config, encoding="utf-8") as f:
        txt = f.read()
    bedrock = re.search(r"(?ms)^bedrock:\n(.*?)^\S", txt)
    if bedrock:
        m = re.search(r"(?m)^  port:\s*(\d+)", bedrock.group(1))
        if m:
            port = int(m.group(1))
        m = re.search(r"(?m)^  webrtc-port:\s*(\d+)", bedrock.group(1))
        if m:
            webrtc = int(m.group(1))
    return port, webrtc


def pong(ping, port, line1, line2):
    """Respuesta RakNet 'unconnected pong' para que el móvil vea un texto en la lista de servidores."""
    t = ping[1:9] if len(ping) >= 9 else b"\0" * 8
    motd = f"MCPE;{line1};900;26.3;0;10;{GUID};{line2};Survival;1;{port};{port};0;".encode("utf-8")
    return b"\x1c" + t + struct.pack(">Q", GUID) + MAGIC + struct.pack(">H", len(motd)) + motd


def bind_all(host, port, webrtc):
    """Abre los sockets de escucha. Reintenta un rato por si Geyser aún no ha soltado los puertos."""
    for _ in range(30):
        socks = []
        try:
            u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            u.bind((host, port))
            socks.append(("raknet", u))
            t = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            t.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            t.bind((host, port))
            t.listen(8)
            socks.append(("signaling", t))
            if webrtc and webrtc != port:
                w = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                w.bind((host, webrtc))
                socks.append(("webrtc", w))
            return socks
        except OSError:
            for _, s in socks:
                s.close()
            time.sleep(2)
    raise SystemExit(f"No se pueden abrir los puertos {port}/{webrtc}: ¿hay otro Geyser encendido?")


def es_android():
    return os.path.exists("/system/bin/app_process") or "ANDROID_ROOT" in os.environ


def debian_proot_con_java():
    """¿Hay un Debian de proot-distro con Java dentro? (para Geyser con NetherNet en Android)"""
    raiz = os.path.join(os.environ.get("PREFIX", "/data/data/com.termux/files/usr"),
                        "var", "lib", "proot-distro", "installed-rootfs", "debian")
    return shutil.which("proot-distro") is not None and os.path.lexists(os.path.join(raiz, "usr", "bin", "java"))


def config_generada(workdir, java_address=None, escuchar=None, anunciar=None, transporte=None):
    """Copia de config.yml con la IP de este equipo y la dirección del servidor Java.

    - escuchar: IP en la que escucha Geyser (bedrock.address).
    - anunciar: IP que se envía a los clientes NetherNet (bedrock.signaling.advertise-addresses);
      sin ella Geyser anuncia la IP pública que da STUN, que no sirve por ZeroTier.
    - java_address: dónde está el servidor Java (en Docker: 'mc-server').
    El config.yml de git no se toca.
    """
    with open(os.path.join(workdir, "config.yml"), encoding="utf-8") as f:
        lines = f.readlines()
    section = None
    for i, line in enumerate(lines):
        if re.match(r"\S", line):                      # clave de primer nivel
            section = line.split(":")[0]
        elif section == "java" and java_address and re.match(r"  address:", line):
            lines[i] = f"  address: {java_address}\n"
        elif section == "bedrock" and escuchar and re.match(r"  address:", line):
            lines[i] = f"  address: {escuchar}\n"
        elif section == "bedrock" and transporte and re.match(r"  transport:", line):
            lines[i] = f"  transport: {transporte}\n"
        elif section == "bedrock" and anunciar and re.match(r"    advertise-addresses:", line):
            lines[i] = f'    advertise-addresses: ["{anunciar}"]\n'
    name = "config-generado.yml"
    with open(os.path.join(workdir, name), "w", encoding="utf-8") as f:
        f.writelines(lines)
    return name


def wait_for_player(host, port, webrtc):
    """Escucha hasta que alguien intenta conectarse de verdad. Los pings solo reciben el aviso."""
    socks = bind_all(host, port, webrtc)
    log(f"En espera: Geyser apagado. Escuchando en {host}:{port} (UDP+TCP)" + (f" y {webrtc} (UDP)" if webrtc else ""))
    try:
        while True:
            ready, _, _ = select.select([s for _, s in socks], [], [], 5)
            for kind, s in socks:
                if s not in ready:
                    continue
                if kind == "signaling":
                    conn, addr = s.accept()
                    try:
                        conn.settimeout(2)
                        conn.recv(4096)
                        body = "Arrancando la conexion para moviles. Vuelve a intentarlo en 30 segundos.".encode()
                        conn.sendall(b"HTTP/1.1 503 Service Unavailable\r\nRetry-After: 30\r\nContent-Type: text/plain\r\n"
                                     b"Content-Length: " + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)
                    except OSError:
                        pass
                    finally:
                        conn.close()
                    return f"señalización NetherNet desde {addr[0]}"
                data, addr = s.recvfrom(2048)
                if kind == "webrtc":
                    return f"WebRTC desde {addr[0]}"
                if data[:1] in (b"\x01", b"\x02"):
                    s.sendto(pong(data, port, "Movil en espera - conectate para activarlo",
                                  "Si falla, reintenta en 30 s"), addr)
                elif data[:1] == b"\x05":
                    return f"RakNet desde {addr[0]}"
    finally:
        for _, s in socks:
            s.close()


# Mensajes de Geyser (se arranca en inglés para que el formato no dependa del idioma del sistema)
# RakNet escribe las líneas por IP; NetherNet (el protocolo nuevo de Bedrock) solo las de nombre.
RE_ATTEMPT = re.compile(r"(\S+) tried to connect!")
RE_LEFT = re.compile(r"Bedrock user with ip: (\S+) has disconnected")
RE_JOINED = re.compile(r"\] (\S+) \(logged in as: (\S+)\) has connected")
RE_LEFT_NAME = re.compile(r"\] (\S+) has disconnected from (?:the|remote) Java server")
RE_LIST = re.compile(r"Online Players \((\d+)\)")


def addr_key(text):
    """'/1.2.3.4:5678' -> '1.2.3.4:5678' para emparejar conexión y desconexión."""
    return text.strip().lstrip("/")


def run_geyser(args, workdir):
    """Arranca Geyser y lo apaga args.idle_min minutos después de que se vaya el último jugador.

    Funciona por eventos: cada conexión ("tried to connect") entra en una lista y cada
    desconexión la saca. Cuando la lista se queda vacía empieza la cuenta atrás; si alguien
    entra antes, se cancela. Como red de seguridad, cada args.check_every segundos se pregunta
    a Geyser ("geyser list") por si se ha perdido algún evento.
    """
    jvm = [f"-Xmx{args.xmx}", "-Duser.language=en", "-Duser.country=US", "-jar", args.jar, "--nogui"]
    # NetherNet (el protocolo actual de Bedrock) usa una librería nativa (libdatachannel) que solo existe
    # para Linux con glibc. En Android (bionic) Geyser se ejecuta dentro de un Debian en proot si lo hay;
    # si no, solo RakNet (los clientes Bedrock actuales ya no se conectarán).
    proot = es_android() and debian_proot_con_java()
    if args.transporte == "auto":
        args.transporte = "raknet" if es_android() and not proot else None
        if args.transporte == "raknet":
            log("AVISO: sin Debian (proot) con Java no hay NetherNet: Bedrock actual no podrá entrar. Ejecuta scripts/preparar.")
    if args.java_address or args.escuchar or args.anunciar or args.transporte:
        jvm += ["-c", config_generada(workdir, args.java_address, args.escuchar, args.anunciar, args.transporte)]
    if proot:
        interno = "cd /geyser && exec java " + " ".join(shlex.quote(a) for a in jvm)
        cmd = ["proot-distro", "login", "debian", "--bind", f"{workdir}:/geyser", "--", "bash", "-c", interno]
    else:
        cmd = [args.java, *jvm]
    proc = subprocess.Popen(cmd, cwd=workdir, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    lock = threading.Lock()
    sessions = {}                       # dirección -> [nombre (o "?" hasta que inicia sesión), hora de entrada]
    state = {"empty_since": time.time(), "listed": None}

    def ask_list():
        """Pregunta a Geyser cuántos jugadores hay de verdad. None si no responde."""
        state["listed"] = None
        try:
            proc.stdin.write("geyser list\n")
            proc.stdin.flush()
        except OSError:
            return None
        for _ in range(50):
            time.sleep(0.1)
            if state["listed"] is not None:
                break
        return state["listed"]

    def update_empty():
        if sessions:
            state["empty_since"] = None
        elif state["empty_since"] is None:
            state["empty_since"] = time.time()
            log(f"No quedan jugadores de Bedrock: Geyser se apagará en {args.idle_min:g} min si nadie entra.")

    def reader():
        for line in proc.stdout:
            line = re.sub(r"\x1b\[[0-9;]*m", "", line.rstrip())
            print("  geyser| " + line, flush=True)
            with lock:
                if m := RE_ATTEMPT.search(line):
                    sessions[addr_key(m.group(1))] = ["?", time.time()]
                    log(f"Conexión de Bedrock ({len(sessions)} conectados).")
                elif m := RE_LEFT.search(line):
                    if sessions.pop(addr_key(m.group(1)), None):
                        log(f"Desconexión de Bedrock ({len(sessions)} conectados).")
                elif m := RE_JOINED.search(line):
                    # Pasa a contarse por nombre; la entrada por IP (si la hubo) sobra
                    pending = next((k for k, v in sessions.items() if v[0] == "?"), None)
                    if pending:
                        sessions.pop(pending)
                    sessions["jugador:" + m.group(1)] = [m.group(1), time.time()]
                    log(f"{m.group(1)} ha entrado desde Bedrock ({len(sessions)} conectados).")
                elif m := RE_LEFT_NAME.search(line):
                    if sessions.pop("jugador:" + m.group(1), None):
                        log(f"{m.group(1)} ha salido ({len(sessions)} conectados).")
                elif m := RE_LIST.search(line):
                    state["listed"] = int(m.group(1))
                update_empty()

    threading.Thread(target=reader, daemon=True).start()
    last_check = time.time()
    try:
        while proc.poll() is None:
            time.sleep(2)
            with lock:
                empty_since = None if args.siempre else state["empty_since"]
            if empty_since is not None and time.time() - empty_since >= args.idle_min * 60:
                # Antes de apagar, Geyser tiene que confirmar que no hay nadie
                listed = ask_list()
                if listed == 0:
                    log(f"{args.idle_min:g} min sin jugadores de Bedrock: apagando Geyser.")
                    break
                with lock:
                    state["empty_since"] = time.time()
                log(f"Geyser dice que hay {listed} jugador(es) aunque no se vio su conexión: sigue encendido.")
            if time.time() - last_check >= args.check_every:
                last_check = time.time()
                listed = ask_list()
                with lock:
                    if listed:
                        # Hay gente aunque se perdiera el evento de conexión: no apagar
                        state["empty_since"] = None
                    elif listed == 0:
                        # Red de seguridad: quitar solo entradas antiguas (un login a medias no sale en la lista)
                        stale = [k for k, v in sessions.items() if time.time() - v[1] > 300]
                        for k in stale:
                            sessions.pop(k)
                        if stale:
                            log(f"Quitadas {len(stale)} conexiones sin desconexión registrada.")
                        update_empty()
    finally:
        stop_geyser(proc)


def stop_geyser(proc):
    if proc.poll() is not None:
        return
    try:
        proc.stdin.write("geyser stop\n")
        proc.stdin.flush()
        proc.wait(30)
    except Exception:
        proc.kill()
        proc.wait()


def main():
    ap = argparse.ArgumentParser(description="Enciende Geyser solo cuando un jugador de Bedrock intenta entrar.")
    ap.add_argument("--dir", default=os.path.join(ROOT, "server 2025", "geyser"), help="carpeta de Geyser Standalone")
    ap.add_argument("--jar", default="Geyser-Standalone.jar")
    ap.add_argument("--key", default=os.path.join(ROOT, "server 2025", "plugins", "floodgate", "key.pem"),
                    help="clave de Floodgate (se copia a la carpeta de Geyser)")
    ap.add_argument("--java", default=os.environ.get("JAVA", "java"))
    ap.add_argument("--xmx", default="512M", help="memoria máxima de Geyser")
    ap.add_argument("--java-address", help="dirección del servidor Java si no es la de config.yml (Docker: mc-server)")
    ap.add_argument("--escuchar", help="IP de este equipo en la que escuchar (la de ZeroTier); por defecto todas")
    ap.add_argument("--anunciar", help="IP que se anuncia a los clientes NetherNet (la de ZeroTier)")
    ap.add_argument("--siempre", action="store_true", help="Geyser siempre encendido (sin bajo demanda)")
    ap.add_argument("--transporte", default="auto", help="raknet | nethernet | both | auto (raknet en Android)")
    ap.add_argument("--idle-min", type=float, default=3, help="minutos sin jugadores antes de apagar Geyser")
    ap.add_argument("--check-every", type=float, default=120,
                    help="segundos entre comprobaciones de seguridad ('geyser list')")
    args = ap.parse_args()

    workdir = os.path.abspath(args.dir)
    if not os.path.isfile(os.path.join(workdir, args.jar)):
        raise SystemExit(f"No está {args.jar} en {workdir}. Ejecuta actualizar.py.")
    port, webrtc = read_ports(os.path.join(workdir, "config.yml"))
    if os.path.isfile(args.key):
        shutil.copy2(args.key, os.path.join(workdir, "key.pem"))
    else:
        log(f"AVISO: no se encuentra la clave de Floodgate ({args.key}); arranca Paper una vez para generarla.")

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    while True:
        if args.siempre:
            log("Modo siempre encendido: arrancando Geyser.")
        else:
            who = wait_for_player(args.escuchar or "0.0.0.0", port, webrtc)
            log(f"Intento de conexión ({who}): arrancando Geyser. El jugador debe reintentar en ~30 s.")
        run_geyser(args, workdir)
        log("Geyser apagado.")
        if args.siempre:
            time.sleep(5)  # si se ha caído, se vuelve a arrancar


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
