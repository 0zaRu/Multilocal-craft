#!/usr/bin/env python3
# ------------------------------------------------------------
# Script: panel.py
# Propósito:
#   Lo que pide la app de control (app-movil/) por SSH. Cada llamada es un proceso
#   corto: no queda nada en marcha cuando la app se cierra.
#
# Uso:
#   python panel.py estado          JSON con el estado del servidor, del dispositivo y de git
#   python panel.py log [--desde N] JSON con el log del servidor desde el byte N (-1 = el final)
#   python panel.py comando         ejecuta por RCON el comando que llega por la entrada estándar
#   python panel.py versiones       comprobación de actualizaciones (actualizar.py --json)
#   python panel.py lanzar <op>     copia | reiniciar | actualizar, en segundo plano
#                                   (log en logs/panel-operacion.log; el estado sale en "estado")
# ------------------------------------------------------------
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rcon  # noqa: E402  (mismo directorio)

for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

ROOT = rcon.ROOT
SERVER_DIR = rcon.SERVER_DIR
LOG = os.path.join(SERVER_DIR, "logs", "latest.log")
LOG_OP = os.path.join(SERVER_DIR, "logs", "panel-operacion.log")
PID_OP = os.path.join(SERVER_DIR, ".panel-operacion")
OPERACIONES = {"copia": ["scripts/copia.sh"], "reiniciar": ["scripts/reiniciar.sh"],
               "actualizar": ["scripts/reiniciar.sh", "--actualizar"]}
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
NUM = re.compile(r"\d+(?:\.\d+)?")


def leer(path, defecto=None):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return defecto


def salida(cmd, timeout=6):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=ROOT)
        return r.stdout.strip() if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def numero(texto):
    """'20,0' o '*20.0' -> 20.0 (el decimal depende del idioma del servidor)."""
    return float(NUM.search(texto.replace(",", ".")).group(0))


def vivo(pid):
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        return False


# --- Servidor (RCON) ---
def estado_servidor():
    try:
        c = rcon.conectar()
    except (OSError, PermissionError):
        return {"activo": False}
    s = {"activo": True}
    try:
        # "TPS from last 5s, 1m, 5m, 15m: 20.0, 20.0, 20.0, 20.0" (según el idioma de la JVM, "20,0")
        etiquetas, _, valores = c.command("tps").partition(":")
        s["tps"] = [numero(v) for v in valores.split(", ") if v.strip()]
        s["tps_periodos"] = re.findall(r"\d+[smh]", etiquetas)
        # "Server tick times (avg/min/max) from last 5s, 10s, 1m:\n◴ 12.1/3.0/40.2, ..."
        lineas = c.command("mspt").strip().splitlines()
        if len(lineas) >= 2:
            media, minimo, maximo = (numero(x) for x in lineas[1].split(", ")[0].split("/"))
            s["mspt"] = {"media": media, "min": minimo, "max": maximo}
        # "There are 2 of a max of 20 players online: Ana, Luis" (o traducido: "Hay 2 jugadores de un máximo de 20...")
        cabeza, _, nombres = c.command("list").partition(":")
        m = re.search(r"(\d+)\D+?(\d+)", cabeza)
        if m:
            s["online"], s["max"] = int(m.group(1)), int(m.group(2))
            s["jugadores"] = [n.strip() for n in nombres.split(",") if n.strip()]
    except (OSError, ConnectionError, ValueError):
        pass
    finally:
        c.close()
    return s


# --- Proceso Java del servidor (solo Linux / Termux, por /proc) ---
def pid_java():
    jar = ""
    for linea in (leer(os.path.join(ROOT, ".env"), "") or "").splitlines():
        if linea.startswith("PAPER_JAR="):
            jar = linea.split("=", 1)[1].strip()
    if not jar or not os.path.isdir("/proc"):
        return None
    for d in os.listdir("/proc"):
        if d.isdigit():
            cmd = leer(f"/proc/{d}/cmdline", "") or ""
            if "-jar\0" in cmd and jar in cmd:
                return int(d)
    return None


def ticks(pid):
    campos = (leer(f"/proc/{pid}/stat", "") or "").rsplit(")", 1)[-1].split()
    # tras el nombre: [11]=utime [12]=stime [19]=starttime
    return int(campos[11]) + int(campos[12]), int(campos[19])


def estado_java(pid):
    j = {}
    try:
        hz = os.sysconf("SC_CLK_TCK")
        t0, inicio = ticks(pid)
        time.sleep(0.5)
        t1, _ = ticks(pid)
        nucleos = os.cpu_count() or 1
        j["cpu"] = round((t1 - t0) / hz / 0.5 * 100 / nucleos, 1)   # % del total del dispositivo
        j["nucleos"] = nucleos
        uptime = leer("/proc/uptime")
        if uptime:
            j["encendido_s"] = int(float(uptime.split()[0]) - inicio / hz)
        elif os.path.exists(os.path.join(SERVER_DIR, ".estado-servidor")):
            # Android no deja leer /proc/uptime: vale la hora a la que iniciar creó su fichero de estado
            j["encendido_s"] = int(time.time() - os.path.getmtime(os.path.join(SERVER_DIR, ".estado-servidor")))
    except (OSError, ValueError, IndexError):
        pass
    for linea in (leer(f"/proc/{pid}/status", "") or "").splitlines():
        if linea.startswith("VmRSS:"):
            j["ram_mb"] = int(linea.split()[1]) // 1024
        elif linea.startswith("Threads:"):
            j["hilos"] = int(linea.split()[1])
    m = re.search(r"-Xmx(\d+)([GgMm])", (leer(f"/proc/{pid}/cmdline", "") or "").replace("\0", " "))
    if m:
        j["xmx_mb"] = int(m.group(1)) * (1024 if m.group(2) in "Gg" else 1)
    return j


# --- Dispositivo ---
CACHE_BATERIA = os.path.join(SERVER_DIR, ".panel-bateria")


def bateria():
    """termux-battery-status puede tardar o colgarse (Termux:API dormida): se pregunta en segundo
    plano y se usa lo último guardado (vale 5 min; si falló, no se reintenta en 10 min)."""
    if not shutil.which("termux-battery-status"):
        return None
    try:
        edad = time.time() - os.path.getmtime(CACHE_BATERIA)
        datos = json.loads(leer(CACHE_BATERIA, "{}") or "{}")
    except (OSError, ValueError):
        edad, datos = None, {}
    if edad is None or edad > (300 if datos else 600):
        with open(CACHE_BATERIA, "a"):
            os.utime(CACHE_BATERIA)   # marca la petición ya hecha para no lanzar otra
        subprocess.Popen(["sh", "-c", 'r=$(timeout 20 termux-battery-status) && printf "%s" "$r" > "$1" || : > "$1"',
                          "sh", CACHE_BATERIA], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    if datos.get("percentage") is None:
        return None
    return {"porcentaje": datos.get("percentage"), "estado": datos.get("status"),
            "enchufado": datos.get("plugged"), "temperatura": datos.get("temperature")}
def temperatura_cpu():
    maximo = None
    base = "/sys/class/thermal"
    try:
        zonas = os.listdir(base)
    except OSError:
        return None
    for z in zonas:
        tipo = (leer(f"{base}/{z}/type", "") or "").strip().lower()
        if not tipo or not any(k in tipo for k in ("cpu", "soc", "tsens", "mtktscpu")):
            continue
        try:
            t = int((leer(f"{base}/{z}/temp", "") or "").strip())
        except ValueError:
            continue
        t = t / 1000 if t > 1000 else float(t)
        if 0 < t < 150 and (maximo is None or t > maximo):
            maximo = t
    return maximo


def estado_dispositivo():
    d = {}
    if shutil.which("getprop"):
        d["modelo"] = " ".join(x for x in (salida(["getprop", "ro.product.manufacturer"]),
                                           salida(["getprop", "ro.product.model"])) if x)
        d["android"] = salida(["getprop", "ro.build.version.release"])
    else:
        import platform
        d["modelo"] = platform.node()
        d["sistema"] = f"{platform.system()} {platform.release()}"
    b = bateria()
    if b:
        d["bateria"] = b
    t = temperatura_cpu()
    if t is not None:
        d["temp_cpu"] = round(t, 1)
    mem = {}
    for linea in (leer("/proc/meminfo", "") or "").splitlines():
        k, _, v = linea.partition(":")
        if k in ("MemTotal", "MemAvailable"):
            mem[k] = int(v.split()[0]) // 1024
    if mem:
        d["ram_total_mb"], d["ram_libre_mb"] = mem.get("MemTotal"), mem.get("MemAvailable")
    try:
        d["carga"] = [round(x, 2) for x in os.getloadavg()]
    except (OSError, AttributeError):
        pass
    disco = shutil.disk_usage(ROOT)
    d["disco_total_gb"], d["disco_libre_gb"] = round(disco.total / 2**30, 1), round(disco.free / 2**30, 1)
    return d


# --- Git y copias ---
def estado_git():
    g = {"rama": salida(["git", "rev-parse", "--abbrev-ref", "HEAD"])}
    ultimo = salida(["git", "log", "-1", "--format=%ct|%h|%s"])
    if ultimo:
        fecha, h, asunto = ultimo.split("|", 2)
        g["ultimo_commit"] = {"fecha": int(fecha), "hash": h, "mensaje": asunto}
    if g["rama"]:
        sin_subir = salida(["git", "rev-list", "--count", f"origin/{g['rama']}..HEAD"])
        if sin_subir is not None:
            g["sin_subir"] = int(sin_subir)
    return g


def operacion_actual():
    """(pid, tipo) de la operación lanzada desde la app, o (None, tipo) si ya terminó."""
    pid, _, tipo = (leer(PID_OP, "") or "").strip().partition(" ")
    try:
        return (int(pid) if vivo(int(pid)) else None), tipo
    except ValueError:
        return None, tipo


def estado_operacion():
    pid, tipo = operacion_actual()
    o = {"tipo": tipo, "en_curso": pid is not None}
    texto = leer(LOG_OP)
    if texto is not None:
        o["log"] = ANSI.sub("", texto).strip().splitlines()[-30:]
        o["fecha"] = int(os.path.getmtime(LOG_OP))
    return o


# --- Subcomandos ---
def cmd_estado(_):
    e = {"servidor": estado_servidor(), "dispositivo": estado_dispositivo(),
         "git": estado_git(), "operacion": estado_operacion(), "hora": int(time.time())}
    pid = pid_java()
    if pid:
        e["servidor"]["proceso"] = estado_java(pid)
    print(json.dumps(e, ensure_ascii=False))
    return 0


def cmd_log(args):
    try:
        tam = os.path.getsize(LOG)
    except OSError:
        print(json.dumps({"pos": 0, "texto": ""}))
        return 0
    desde, reinicio = args.desde, False
    if desde < 0 or desde > tam:          # primera vez, o el log se ha rotado
        desde, reinicio = max(0, tam - 48 * 1024), True
    with open(LOG, "rb") as f:
        f.seek(desde)
        datos = f.read(64 * 1024)
    datos = datos[:datos.rfind(b"\n") + 1]    # solo líneas completas; el resto llega en la siguiente
    pos = desde + len(datos)
    if reinicio and desde > 0:                # empezar también en una línea completa
        datos = datos[datos.find(b"\n") + 1:]
    texto = ANSI.sub("", datos.decode("utf-8", "replace")).replace("\r", "")
    print(json.dumps({"pos": pos, "texto": texto, "reinicio": reinicio}, ensure_ascii=False))
    return 0


def cmd_comando(_):
    orden = sys.stdin.read().strip().lstrip("/")
    if not orden:
        return 1
    try:
        c = rcon.conectar()
    except (OSError, PermissionError) as e:
        print(f"No se puede conectar por RCON: {e}")
        return 1
    try:
        print(c.command(orden))
    except (OSError, ConnectionError):
        pass   # "stop" cierra la conexión antes de responder
    c.close()
    return 0


def cmd_versiones(_):
    r = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "actualizar.py"), "--json"],
                       capture_output=True, text=True, cwd=ROOT, timeout=240)
    print(r.stdout.strip() or json.dumps({"error": (r.stderr.strip() or "sin respuesta")[-500:]}, ensure_ascii=False))
    return 0


def cmd_lanzar(args):
    pid, tipo = operacion_actual()
    if pid:
        print(f"Ya hay una operación en curso ({tipo}).")
        return 1
    with open(LOG_OP, "w", encoding="utf-8") as log:
        # sesión propia: sigue aunque la app cierre la conexión o se reinicie sshd
        p = subprocess.Popen(["bash"] + OPERACIONES[args.op], cwd=ROOT, stdin=subprocess.DEVNULL,
                             stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    with open(PID_OP, "w") as f:
        f.write(f"{p.pid} {args.op}")
    print({"copia": "Copia iniciada.", "reiniciar": "Reinicio iniciado.", "actualizar": "Actualización iniciada."}[args.op])
    return 0


def main():
    ap = argparse.ArgumentParser(description="Datos para la app de control de Multilocal-craft")
    sub = ap.add_subparsers(dest="orden", required=True)
    sub.add_parser("estado").set_defaults(f=cmd_estado)
    lg = sub.add_parser("log")
    lg.add_argument("--desde", type=int, default=-1)
    lg.set_defaults(f=cmd_log)
    sub.add_parser("comando").set_defaults(f=cmd_comando)
    sub.add_parser("versiones").set_defaults(f=cmd_versiones)
    la = sub.add_parser("lanzar")
    la.add_argument("op", choices=sorted(OPERACIONES))
    la.set_defaults(f=cmd_lanzar)
    args = ap.parse_args()
    return args.f(args)


if __name__ == "__main__":
    sys.exit(main())
