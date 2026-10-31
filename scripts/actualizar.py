#!/usr/bin/env python3
# ------------------------------------------------------------
# Script: actualizar.py
# Propósito:
#   Actualiza Paper y los plugins a la versión de Minecraft más alta
#   que soporten TODOS los plugins de "server 2025/plugins.json".
#   Si un plugin todavía no soporta la versión nueva, avisa de cuál es
#   y se queda en la última versión compatible (o no toca nada).
#   Antes de instalar, arranca el servidor en una carpeta temporal
#   (sin el mundo) para comprobar que todo carga sin errores.
#
# Uso:
#   python actualizar.py            comprobar y, si se confirma, aplicar
#   python actualizar.py --check    solo comprobar (no cambia nada)
#   python actualizar.py --yes      aplicar sin preguntar
#   python actualizar.py --no-smoke saltar la prueba de arranque
#   python actualizar.py --rollback restaurar los jars del último backup
#
# Funciona en Windows, Linux, Mac y Termux. Solo usa la librería estándar.
# Java: usa $JAVA, $JAVA_HOME o el "java" del PATH; si no llega a la versión
# que pide Paper y hay Docker, hace la prueba con eclipse-temurin.
# ------------------------------------------------------------
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request
import zipfile

for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # carpeta del repo (padre de scripts/)
SERVER_DIR = os.path.join(ROOT, "server 2025")
PLUGINS_DIR = os.path.join(SERVER_DIR, "plugins")
GEYSER_DIR = os.path.join(SERVER_DIR, "geyser")
CONFIG_FILE = os.path.join(SERVER_DIR, "plugins.json")
ENV_FILE = os.path.join(ROOT, ".env")
BACKUP_DIR = os.path.join(SERVER_DIR, ".upgrade-backup")

UA = "0zaRu/Multilocal-craft actualizar.py"
FILL = "https://fill.papermc.io/v3/projects/paper"
LEAF = "https://api.leafmc.one/v2/projects/leaf"
MODRINTH = "https://api.modrinth.com/v2"
GEYSERMC = "https://download.geysermc.org/v2/projects"
SMOKE_TIMEOUT = 600

C = {"r": "\033[31m", "g": "\033[32m", "y": "\033[33m", "c": "\033[36m", "b": "\033[1m", "n": "\033[0m"}
if os.name == "nt":
    os.system("")  # activa los colores ANSI en la consola de Windows


def say(color, msg):
    print(f"{C[color]}{msg}{C['n']}", flush=True)


# ------------------------------------------------------------ utilidades

def http_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def download(url, dest, sha256=None, sha512=None):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    tmp = dest + ".part"
    h256, h512 = hashlib.sha256(), hashlib.sha512()
    with urllib.request.urlopen(req, timeout=300) as r, open(tmp, "wb") as f:
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            f.write(chunk)
            h256.update(chunk)
            h512.update(chunk)
    if sha256 and h256.hexdigest() != sha256.lower():
        os.remove(tmp)
        raise RuntimeError(f"sha256 incorrecto al descargar {url}")
    if sha512 and h512.hexdigest() != sha512.lower():
        os.remove(tmp)
        raise RuntimeError(f"sha512 incorrecto al descargar {url}")
    os.replace(tmp, dest)


def vkey(v):
    """Clave para ordenar versiones de MC: '26.3' > '1.21.10'."""
    return tuple(int(x) for x in re.findall(r"\d+", v))


def q(lst):
    return urllib.parse.quote(json.dumps(lst))


def read_env():
    env = {}
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip()
    return env


def write_env(values):
    env = read_env()
    env.update(values)
    env = {k: v for k, v in env.items() if v is not None}  # None = quitar la clave
    lines = [
        "# Lo actualiza scripts/actualizar.py (versiones). Lo leen los scripts y Docker Compose.",
        "# GEYSER_MODE: ondemand (Geyser solo se enciende cuando un jugador de Bedrock se conecta) o siempre.",
        "# ZEROTIER_RED / ZEROTIER_ID: red ZeroTier del servidor; iniciar usa la IP de este dispositivo dentro de ella.",
    ]
    lines += [f"{k}={v}" for k, v in env.items()]
    with open(ENV_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def geyser_mode():
    return read_env().get("GEYSER_MODE", "ondemand")


def plugin_dir_for(p):
    """Dónde vive el jar: Geyser va aparte (Geyser Standalone), fuera de plugins/."""
    return GEYSER_DIR if p["name"] == "Geyser" else PLUGINS_DIR


def notify(title, text):
    """Aviso extra en Termux (además de la consola)."""
    if shutil.which("termux-notification"):
        subprocess.run(["termux-notification", "--title", title, "--content", text], check=False)


# ------------------------------------------------------------ Paper

def server_candidates(srv, current):
    """Candidatas del servidor elegido en plugins.json ("proyecto": paper | leaf)."""
    if srv.get("proyecto", "paper") == "leaf":
        return leaf_candidates(current, srv.get("canales", ["default"]))
    return paper_candidates(current)


def leaf_candidates(current, canales):
    """Versiones de Leaf (fork de Paper, mismos plugins) >= la actual, de la más nueva a la más vieja.
    Para 26.x Leaf solo publica builds 'experimental': se aceptan si están en `canales`."""
    data = http_json(LEAF)
    versions = sorted({v for v in data["versions"] if "-" not in v and vkey(v) >= vkey(current)}, key=vkey, reverse=True)
    out = []
    for v in versions:
        try:
            builds = http_json(f"{LEAF}/versions/{v}/builds")["builds"]
        except Exception:
            continue
        builds = [b for b in builds if b.get("channel", "default").lower() in canales]
        if not builds:
            continue
        b = builds[-1]
        dl = b["downloads"]["primary"]
        try:  # Leaf no publica el Java mínimo: el de Paper para la misma versión
            java = http_json(f"{FILL}/versions/{v}")["version"]["java"]["version"]["minimum"]
        except Exception:
            java = 25
        out.append({
            "version": v, "build": b["build"], "status": b.get("channel", "?"), "java": java,
            "file": dl["name"], "url": f"{LEAF}/versions/{v}/builds/{b['build']}/downloads/{dl['name']}",
            "sha256": dl["sha256"],
        })
    return out


def paper_candidates(current):
    """Versiones estables de Paper >= la actual, de la más nueva a la más vieja."""
    data = http_json(FILL)
    versions = [v for group in data["versions"].values() for v in group if "-" not in v]
    versions = sorted({v for v in versions if vkey(v) >= vkey(current)}, key=vkey, reverse=True)
    out = []
    for v in versions:
        try:
            info = http_json(f"{FILL}/versions/{v}")["version"]
            build = http_json(f"{FILL}/versions/{v}/builds/latest")
        except Exception:
            continue
        if build.get("channel") != "STABLE":
            continue
        dl = build["downloads"]["server:default"]
        out.append({
            "version": v,
            "build": build["id"],
            "status": info.get("support", {}).get("status", "?"),
            "java": info.get("java", {}).get("version", {}).get("minimum", 21),
            "file": dl["name"],
            "url": dl["url"],
            "sha256": dl["checksums"]["sha256"],
        })
    return out


# ------------------------------------------------------------ plugins

def modrinth_versions(project, mc, loaders):
    url = f"{MODRINTH}/project/{project}/version?game_versions={q([mc])}"
    if loaders:
        url += f"&loaders={q(loaders)}"
    return http_json(url)


def resolve_modrinth(p, mc):
    vers = modrinth_versions(p["project"], mc, p.get("loaders"))
    rel = [v for v in vers if v["version_type"] == "release"]
    if not rel and p.get("allow_beta"):
        rel = vers
    if rel:
        v = rel[0]
        f = next((x for x in v["files"] if x.get("primary")), v["files"][0])
        return {"status": "ok", "version": v["version_number"], "file": f["filename"],
                "url": f["url"], "sha512": f["hashes"].get("sha512"), "note": ""}
    dev = p.get("dev_fallback")
    if dev:
        b = http_json(dev["jenkins"].rstrip("/") + "/lastSuccessfulBuild/api/json?tree=number,url,artifacts[fileName,relativePath]")
        art = next((a for a in b["artifacts"] if re.match(dev["artifact"], a["fileName"])), None)
        if art:
            ver = re.sub(r"^[A-Za-z]+-|\.jar$", "", art["fileName"])
            return {"status": "dev", "version": ver, "file": art["fileName"],
                    "url": b["url"] + "artifact/" + art["relativePath"],
                    "note": f"sin versión estable para {mc}; build de desarrollo #{b['number']} (se verifica arrancando)"}
    return {"status": "bloquea", "note": f"no hay versión para Minecraft {mc}"}


def resolve_geysermc(p, mc):
    # GeyserMC no publica qué versiones de MC soporta cada build; Modrinth sí.
    if not modrinth_versions(p["compat_modrinth"], mc, p.get("compat_loaders")):
        return {"status": "bloquea", "note": f"no hay versión para Minecraft {mc}"}
    platform = "standalone" if p["name"] == "Geyser" else p.get("platform")
    b = http_json(f"{GEYSERMC}/{p['project']}/versions/latest/builds/latest")
    dl = b["downloads"][platform]
    return {"status": "ok", "version": f"{b['version']}-b{b['build']}", "file": dl["name"],
            "url": f"{GEYSERMC}/{p['project']}/versions/{b['version']}/builds/{b['build']}/downloads/{platform}",
            "sha256": dl["sha256"], "note": ""}


def resolve(p, mc):
    try:
        if p["source"] == "geysermc":
            return resolve_geysermc(p, mc)
        return resolve_modrinth(p, mc)
    except Exception as e:
        return {"status": "error", "note": f"no se pudo consultar ({e})"}


# ------------------------------------------------------------ Java

def java_major(java):
    try:
        out = subprocess.run([java, "-version"], capture_output=True, text=True, timeout=60).stderr
    except Exception:
        return 0
    m = re.search(r'version "(\d+)(?:\.(\d+))?', out)
    if not m:
        return 0
    major = int(m.group(1))
    return int(m.group(2)) if major == 1 else major


def find_java():
    cands = [os.environ.get("JAVA")]
    if os.environ.get("JAVA_HOME"):
        cands.append(os.path.join(os.environ["JAVA_HOME"], "bin", "java"))
    cands.append(shutil.which("java"))
    for c in cands:
        if c and (os.path.exists(c) or os.path.exists(c + ".exe")):
            return c, java_major(c)
    return None, 0


# ------------------------------------------------------------ prueba de arranque

def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


SMOKE_ERR = re.compile(
    r"(Could not load plugin|Error occurred while enabling|unsupported server version|"
    r"is not compatible|UnsupportedClassVersionError|Could not load '|Exception in thread)", re.I)


def plugin_name_in_jar(path):
    try:
        with zipfile.ZipFile(path) as z:
            for n in ("paper-plugin.yml", "plugin.yml"):
                if n in z.namelist():
                    m = re.search(r"^name:\s*['\"]?([^'\"\r\n]+)", z.read(n).decode("utf-8", "replace"), re.M)
                    if m:
                        return m.group(1).strip()
    except Exception:
        pass
    return None


def smoke_test(paper, jars, java_min):
    """Arranca Paper con los jars nuevos en una carpeta temporal sin el mundo.
    jars: lista de rutas a jars de plugins (ya descargados)."""
    tmp = tempfile.mkdtemp(prefix="mlc-smoke-")
    try:
        shutil.copy2(paper, os.path.join(tmp, "server.jar"))
        for f in ("bukkit.yml", "spigot.yml", "commands.yml", "help.yml", "permissions.yml", "ops.json", "whitelist.json"):
            src = os.path.join(SERVER_DIR, f)
            if os.path.exists(src):
                shutil.copy2(src, tmp)
        if os.path.isdir(os.path.join(SERVER_DIR, "config")):
            shutil.copytree(os.path.join(SERVER_DIR, "config"), os.path.join(tmp, "config"))
        with open(os.path.join(tmp, "eula.txt"), "w") as f:
            f.write("eula=true\n")
        port = free_port()
        props = {}
        sp = os.path.join(SERVER_DIR, "server.properties")
        if os.path.exists(sp):
            with open(sp, encoding="utf-8") as f:
                for line in f:
                    if "=" in line and not line.startswith("#"):
                        k, v = line.rstrip("\n").split("=", 1)
                        props[k] = v
        props.update({"server-port": str(port), "server-ip": "", "level-name": "smoke-world",
                      "generate-structures": "false", "enable-rcon": "false",
                      "enable-query": "false", "management-server-enabled": "false", "view-distance": "4",
                      "simulation-distance": "4"})
        with open(os.path.join(tmp, "server.properties"), "w", encoding="utf-8") as f:
            f.writelines(f"{k}={v}\n" for k, v in props.items())

        # Configuración de los plugins (sin cachés ni datos de jugadores)
        ign = shutil.ignore_patterns("*.jar", ".paper-remapped", "cache", "userdata", "logs", "tmp*", "*.mv.db", "*.db")
        os.makedirs(os.path.join(tmp, "plugins"))
        for entry in os.listdir(PLUGINS_DIR):
            src = os.path.join(PLUGINS_DIR, entry)
            if os.path.isdir(src) and entry != ".paper-remapped":
                shutil.copytree(src, os.path.join(tmp, "plugins", entry), ignore=ign)
        expected = []
        for j in jars:
            shutil.copy2(j, os.path.join(tmp, "plugins"))
            name = plugin_name_in_jar(j)
            if name:
                expected.append(name)
        java, major = find_java()
        if java and major >= java_min:
            cmd = [java, "-Xms1G", "-Xmx2G", "-jar", "server.jar", "--nogui"]
            say("c", f"  Prueba de arranque con Java {major} (puede tardar 1-3 minutos)...")
        elif shutil.which("docker"):
            cmd = ["docker", "run", "--rm", "-i", "-v", f"{tmp}:/srv", "-w", "/srv",
                   f"eclipse-temurin:{java_min}-jre", "java", "-Xms1G", "-Xmx2G", "-jar", "server.jar", "--nogui"]
            say("c", f"  No hay Java {java_min} local (tienes {major or 'ninguno'}); prueba de arranque con Docker...")
        else:
            return False, [f"Hace falta Java {java_min} (tienes {major or 'ninguno'}) o Docker para la prueba de arranque."]

        proc = subprocess.Popen(cmd, cwd=tmp, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        lines, done = [], threading.Event()

        def reader():
            for line in proc.stdout:
                lines.append(line.rstrip())
                if re.search(r"Done \(\d", line):
                    done.set()
            done.set()

        threading.Thread(target=reader, daemon=True).start()
        done.wait(SMOKE_TIMEOUT)
        finished = any(re.search(r"Done \(\d", l) for l in lines)
        if finished:
            time.sleep(20)  # deja correr las tareas asíncronas del arranque (comprobaciones, cachés...)
        try:
            proc.stdin.write("stop\n")
            proc.stdin.flush()
            proc.wait(120)
        except Exception:
            proc.kill()

        problems = []
        if not finished:
            problems.append("El servidor no llegó a arrancar ('Done') en la prueba.")
        # Lo que pase durante el apagado (tareas cortadas a medias) no cuenta
        stop_at = next((i for i, l in enumerate(lines) if "Stopping server" in l), len(lines))
        for l in lines[:stop_at]:
            if SMOKE_ERR.search(l) or "generated an exception" in l or ("/ERROR]" in l and "[Server thread/ERROR]: [" in l):
                problems.append(l.strip())
        for name in expected:
            if not any(f"Enabling {name}" in l for l in lines):
                problems.append(f"El plugin {name} no se llegó a activar.")
        with open(os.path.join(SERVER_DIR, "logs", "actualizar-prueba.log"), "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        return not problems, problems
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ------------------------------------------------------------ comandos

def load_cfg():
    with open(CONFIG_FILE, encoding="utf-8") as f:
        return json.load(f)


def save_cfg(cfg):
    with open(CONFIG_FILE, "w", encoding="utf-8", newline="\n") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")


def rollback():
    if not os.path.isdir(BACKUP_DIR) or not os.listdir(BACKUP_DIR):
        say("r", "No hay ningún backup en " + BACKUP_DIR)
        return 1
    last = os.path.join(BACKUP_DIR, sorted(os.listdir(BACKUP_DIR))[-1])
    with open(os.path.join(last, "plugins.json"), encoding="utf-8") as f:
        old = json.load(f)
    cur = load_cfg()
    # Quitar los jars actuales y devolver los del backup
    current = [os.path.join(SERVER_DIR, cur["paper"]["installed"]["file"])]
    for p in cur["plugins"]:
        if p.get("installed"):
            d = GEYSER_DIR if p["installed"].get("location") == "geyser" else PLUGINS_DIR
            current.append(os.path.join(d, p["installed"]["file"]))
    for path in current:
        if os.path.isfile(path):
            os.remove(path)
    with open(os.path.join(last, "ubicaciones.json"), encoding="utf-8") as f:
        where = json.load(f)
    for name, dest in where.items():
        shutil.copy2(os.path.join(last, name), os.path.join(ROOT, dest))
    save_cfg(old)
    inst = old["paper"]["installed"]
    write_env({"MC_VERSION": inst["version"], "PAPER_JAR": inst["file"], "JAVA_VERSION": str(inst["java"])})
    say("g", f"Restaurado el backup {os.path.basename(last)} (servidor {inst['version']}).")
    say("y", "OJO: si el mundo ya se abrió con la versión nueva, NO se puede abrir con la vieja.")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Actualiza el servidor (Paper o Leaf) y los plugins de Multilocal-craft.")
    ap.add_argument("--check", action="store_true", help="solo comprobar, no cambia nada")
    ap.add_argument("--yes", action="store_true", help="aplicar sin preguntar")
    ap.add_argument("--no-smoke", action="store_true", help="saltar la prueba de arranque")
    ap.add_argument("--rollback", action="store_true", help="restaurar los jars del último backup")
    args = ap.parse_args()

    if args.rollback:
        return rollback()

    cfg = load_cfg()
    cur = cfg["paper"]["installed"]
    say("c", f"{C['b']}--- Actualizador de Multilocal-craft ---")
    srv = cfg["paper"].get("proyecto", "paper").capitalize()
    say("c", f"Instalado: {srv} {cur['version']} build {cur['build']} | Geyser en modo '{geyser_mode()}'")
    say("c", f"Buscando versiones de {srv} y comprobando plugins...")

    try:
        cands = server_candidates(cfg["paper"], cur["version"])
    except Exception as e:
        say("r", f"No se pudo consultar las versiones de {srv}: {e}")
        return 2
    if not cands:
        say("r", "PaperMC no devolvió ninguna versión estable.")
        return 2

    blocked = []          # (versión, [motivos]) de versiones más nuevas que no se pueden usar
    target = None
    for c in cands:
        res = {p["name"]: resolve(p, c["version"]) for p in cfg["plugins"]}
        bad = [f"{n}: {r['note']}" for n, r in res.items() if r["status"] in ("bloquea", "error")]
        if bad:
            blocked.append((c, bad))
            continue
        target, target_res = c, res
        break

    for c, bad in blocked:
        say("y", f"\nMinecraft {c['version']} ({srv} build {c['build']}) disponible, pero BLOQUEADO por:")
        for b in bad:
            say("y", f"   - {b}")
    if not target:
        msg = "Ninguna versión nueva es compatible con todos los plugins. No se cambia nada."
        say("r", "\n" + msg)
        notify("Multilocal-craft", msg)
        return 1

    # Informe
    print()
    say("b", f"Versión elegida: Minecraft {target['version']} ({srv} build {target['build']}, "
             f"{target['status']}, Java {target['java']}+)")
    print(f"  {'Componente':<15} {'Instalado':<28} {'Nuevo':<28} Estado")
    same_paper = target["file"] == cur["file"]
    print(f"  {srv:<15} {cur['version'] + '-' + str(cur['build']):<28} "
          f"{target['version'] + '-' + str(target['build']):<28} {'igual' if same_paper else 'actualizar'}")
    changes = 0 if same_paper else 1
    for p in cfg["plugins"]:
        r = target_res[p["name"]]
        old = (p.get("installed") or {}).get("version", "-")
        moved = (p.get("installed") or {}).get("location") == "plugin" and plugin_dir_for(p) == GEYSER_DIR
        same = p.get("installed") and p["installed"]["file"] == r["file"] and old == r["version"] and not moved
        state = "igual" if same else ("nuevo" if not p.get("installed") else "actualizar")
        if r["status"] == "dev":
            state += " (dev)"
        if not same:
            changes += 1
        print(f"  {p['name']:<15} {old:<28} {r['version']:<28} {state}")
        if r["note"]:
            say("y", f"  {'':<15} {r['note']}")

    if changes == 0:
        say("g", "\nTodo está al día. No hay nada que hacer.")
        if blocked:
            notify("Multilocal-craft", f"Hay Minecraft {blocked[0][0]['version']} pero algún plugin aún no lo soporta.")
        return 3 if blocked else 0

    if args.check:
        say("c", "\n--check: no se ha cambiado nada.")
        return 3 if blocked else 0

    if target["version"] != cur["version"]:
        say("r", f"\nAVISO: al arrancar con {target['version']} el mundo se convierte y NO podrá volver a abrirse "
                 f"con {cur['version']}. Todos los jugadores tienen que actualizar a la vez (git pull).")
    if not args.yes:
        if input("\n¿Aplicar la actualización? (S/N): ").strip().upper() != "S":
            say("y", "Cancelado. No se ha cambiado nada.")
            return 1

    # Descarga a una carpeta temporal
    staging = tempfile.mkdtemp(prefix="mlc-dl-")
    try:
        say("c", "\nDescargando...")
        paper_path = os.path.join(staging, target["file"])
        download(target["url"], paper_path, sha256=target["sha256"])
        jar_paths = {}
        for p in cfg["plugins"]:
            r = target_res[p["name"]]
            path = os.path.join(staging, r["file"])
            download(r["url"], path, sha256=r.get("sha256"), sha512=r.get("sha512"))
            jar_paths[p["name"]] = path
            print(f"  {r['file']}")

        if not args.no_smoke:
            # Geyser Standalone no es un plugin: no entra en la prueba de Paper
            test_jars = [jar_paths[p["name"]] for p in cfg["plugins"] if plugin_dir_for(p) == PLUGINS_DIR]
            ok, problems = smoke_test(paper_path, test_jars, target["java"])
            if not ok:
                say("r", "\nLa prueba de arranque ha FALLADO. No se ha cambiado nada:")
                for pr in problems[:30]:
                    say("r", "   " + pr)
                say("y", "Log completo: server 2025/logs/actualizar-prueba.log")
                notify("Multilocal-craft", "La actualización falló en la prueba de arranque.")
                return 1
            say("g", "  Prueba de arranque correcta: todos los plugins se activan sin errores.")

        # Backup de los jars actuales
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        bdir = os.path.join(BACKUP_DIR, stamp)
        os.makedirs(bdir)
        shutil.copy2(CONFIG_FILE, os.path.join(bdir, "plugins.json"))
        where = {}
        old_files = [(SERVER_DIR, cur["file"])]
        for p in cfg["plugins"]:
            if p.get("installed"):
                loc = PLUGINS_DIR if p["installed"].get("location", "plugin") == "plugin" else GEYSER_DIR
                old_files.append((loc, p["installed"]["file"]))
        for d, f in old_files:
            src = os.path.join(d, f)
            if os.path.isfile(src):
                shutil.move(src, os.path.join(bdir, f))
                where[f] = os.path.relpath(src, ROOT)
        with open(os.path.join(bdir, "ubicaciones.json"), "w", encoding="utf-8") as fh:
            json.dump(where, fh, indent=2)

        # Instalar
        shutil.move(paper_path, os.path.join(SERVER_DIR, target["file"]))
        cfg["paper"]["installed"] = {k: target[k] for k in ("version", "build", "file", "java")}
        for p in cfg["plugins"]:
            r = target_res[p["name"]]
            d = plugin_dir_for(p)
            os.makedirs(d, exist_ok=True)
            shutil.move(jar_paths[p["name"]], os.path.join(d, r["file"]))
            p["installed"] = {"version": r["version"], "file": r["file"],
                              "location": "plugin" if d == PLUGINS_DIR else "geyser"}
        save_cfg(cfg)
        write_env({"MC_VERSION": target["version"], "PAPER_JAR": target["file"],
                   "JAVA_VERSION": str(target["java"]), "GEYSER_MODE": geyser_mode()})
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    say("g", f"\nActualizado a Minecraft {target['version']}. Backup de los jars en server 2025/.upgrade-backup/{stamp}")
    java, major = find_java()
    if major < target["java"]:
        say("y", f"Para arrancar en terminal necesitas Java {target['java']} (tienes {major or 'ninguno'}).")
    if blocked:
        msg = f"Hay Minecraft {blocked[0][0]['version']}, pero algún plugin aún no lo soporta. Vuelve a probar más adelante."
        say("y", msg)
        notify("Multilocal-craft", msg)
    # Con versión nueva de Minecraft, los chunks antiguos se convierten al cargarse (caro en el móvil):
    # mejor convertir todo el mundo ahora, en este equipo.
    if target["version"] != cur["version"]:
        print()
        if args.yes or input("¿Convertir ahora todos los chunks del mundo al formato nuevo? "
                             "(recomendado antes de jugar desde el móvil) (S/N): ").strip().upper() == "S":
            import convertir_mundo
            return convertir_mundo.main()
        say("c", "Puedes hacerlo luego con: python scripts/convertir_mundo.py (con el servidor apagado)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        say("y", "\nCancelado.")
        sys.exit(1)
