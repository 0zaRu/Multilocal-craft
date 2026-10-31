#!/usr/bin/env python3
# ------------------------------------------------------------
# Script: convertir_mundo.py
# Propósito:
#   Convertir TODOS los chunks existentes del mundo al formato de la versión instalada,
#   de una vez (Paper/Leaf 26.x no tienen --forceUpgrade). Así el servidor no tiene que
#   convertirlos al vuelo la primera vez que alguien los visita (caro en el móvil).
#
#   Cómo: arranca el servidor sin jugadores y, región a región (.mca que existan), usa el
#   comando del juego /forceload para cargar del todo sus 32x32 chunks; al soltarlos se
#   guardan en el formato nuevo. Al final comprueba el DataVersion de cada chunk y repite
#   las regiones que queden antiguas. No usa plugins y no sale de las regiones que existen
#   (los chunks que falten dentro de una región sí se generan).
#
# Uso: python convertir_mundo.py   (con el servidor APAGADO; necesita Java de la versión de .env)
# Lo ofrece actualizar.py tras cambiar de versión de Minecraft.
# ------------------------------------------------------------
import collections
import os
import re
import struct
import subprocess
import sys
import threading
import time
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import actualizar as act  # noqa: E402  (reutiliza .env, colores y búsqueda de Java)

DIM_DIR = os.path.join(act.SERVER_DIR, "world", "dimensions", "minecraft")
DIMENSIONES = ("overworld", "the_nether", "the_end")
POR_TANDA = 3          # regiones cargadas a la vez
ESPERA = 25            # segundos para que carguen y se conviertan


def data_versions(path):
    """Counter de DataVersion de los chunks de un .mca."""
    c = collections.Counter()
    data = open(path, "rb").read()
    for k in range(1024):
        off = int.from_bytes(data[k * 4:k * 4 + 3], "big")
        if not off:
            continue
        p = off * 4096
        ln, comp = struct.unpack(">iB", data[p:p + 5])
        raw = data[p + 5:p + 4 + ln]
        try:
            body = zlib.decompress(raw) if comp == 2 else raw
        except Exception:
            continue
        i = body.find(b"\x03\x00\x0bDataVersion")
        if i >= 0:
            c[struct.unpack(">i", body[i + 14:i + 18])[0]] += 1
    return c


def regiones():
    """{(dimensión, rx, rz): Counter de DataVersion} de cada región que existe."""
    out = {}
    for dim in DIMENSIONES:
        d = os.path.join(DIM_DIR, dim, "region")
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            m = re.fullmatch(r"r\.(-?\d+)\.(-?\d+)\.mca", f)
            if m and os.path.getsize(os.path.join(d, f)) > 0:
                out[(dim, int(m.group(1)), int(m.group(2)))] = data_versions(os.path.join(d, f))
    return out


def ficheros_mca():
    """Todos los .mca de región, entidades y POI que existen ahora."""
    out = set()
    for dim in DIMENSIONES:
        for sub in ("region", "entities", "poi"):
            d = os.path.join(DIM_DIR, dim, sub)
            if os.path.isdir(d):
                out |= {os.path.join(d, f) for f in os.listdir(d) if f.endswith(".mca")}
    return out


def pendientes(regs):
    """Regiones con algún chunk en una versión anterior a la más alta del mundo."""
    actual = max((v for c in regs.values() for v in c), default=0)
    return [r for r, c in regs.items() if any(v < actual for v in c)], actual


def main():
    env = act.read_env()
    java_min = int(env.get("JAVA_VERSION", "25"))
    java, major = act.find_java()
    if not java or major < java_min:
        act.say("r", f"Hace falta Java {java_min} (encontrado: {major or 'ninguno'}). Ejecuta scripts/preparar.")
        return 1
    regs = regiones()
    existentes = ficheros_mca()   # para quitar luego los bordes a medio generar que crea /forceload
    falta, actual = pendientes(regs)
    antiguos = sum(n for c in regs.values() for v, n in c.items() if v < actual)
    act.say("c", f"Regiones: {len(regs)} | con chunks antiguos: {len(falta)} ({antiguos} chunks)")
    if not falta:
        act.say("g", "Todo el mundo está ya en el formato actual.")
        return 0

    opts = env.get("JAVA_OPTS", "").split()
    p = subprocess.Popen([java, "-Xms3G", "-Xmx3G", *opts, "-jar", env["PAPER_JAR"], "nogui"],
                         cwd=act.SERVER_DIR, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    listo = threading.Event()

    def leer():
        for l in p.stdout:
            if re.search(r"Done \(\d", l):
                listo.set()
        listo.set()

    def enviar(c):
        p.stdin.write(c + "\n"); p.stdin.flush()

    threading.Thread(target=leer, daemon=True).start()
    try:
        listo.wait(600)
        if p.poll() is not None:
            act.say("r", "El servidor no arrancó (¿está ya en marcha?).")
            return 1
        for intento in (1, 2):
            for i in range(0, len(falta), POR_TANDA):
                tanda = falta[i:i + POR_TANDA]
                for dim, rx, rz in tanda:
                    x0, z0 = rx * 512, rz * 512
                    for qx in (0, 256):
                        for qz in (0, 256):
                            enviar(f"execute in minecraft:{dim} run forceload add "
                                   f"{x0 + qx} {z0 + qz} {x0 + qx + 255} {z0 + qz + 255}")
                time.sleep(ESPERA)
                for dim in {t[0] for t in tanda}:
                    enviar(f"execute in minecraft:{dim} run forceload remove all")
                enviar("save-all flush")
                print(f"  [{min(i + POR_TANDA, len(falta))}/{len(falta)}] " +
                      ", ".join(f"{d} r.{x}.{z}" for d, x, z in tanda), flush=True)
                time.sleep(5)
            # Comprobar lo que quede (los ficheros ya están guardados tras save-all flush)
            time.sleep(10)
            regs = regiones()
            falta, _ = pendientes(regs)
            if not falta:
                break
            act.say("y", f"Quedan {len(falta)} regiones con chunks antiguos; reintento ({intento})...")
    finally:
        try:
            enviar("stop")
            p.wait(300)
        except Exception:
            p.kill()
    # Al cargar una región, el juego prepara a medias los chunks vecinos y los guarda en regiones
    # que no existían: se quitan para no hacer crecer el mundo (se generarán si alguien llega).
    nuevos = ficheros_mca() - existentes
    for f in nuevos:
        os.remove(f)
    if nuevos:
        print(f"  Retirados {len(nuevos)} ficheros de bordes a medio generar.")
    regs = regiones()
    falta, actual = pendientes(regs)
    total = sum(sum(c.values()) for c in regs.values())
    if falta:
        act.say("y", f"Quedan {len(falta)} regiones con chunks antiguos de {len(regs)}.")
        return 1
    act.say("g", f"Mundo convertido: {total} chunks en {len(regs)} regiones, todos en el formato {actual}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
