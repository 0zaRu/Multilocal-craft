#!/usr/bin/env python3
# ------------------------------------------------------------
# Script: rcon.py
# Propósito:
#   Cliente RCON (solo librería estándar) para el servidor en modo terminal.
#   Lee host, puerto y contraseña de "server 2025/server.properties".
#
# Uso:
#   python rcon.py "save-all flush"   envía un comando e imprime la respuesta
#   python rcon.py --comprobar        sale con 0 si el servidor responde por RCON
#   python rcon.py --interactivo      consola: muestra el log en directo y envía lo que escribas
# ------------------------------------------------------------
import argparse
import os
import re
import socket
import struct
import sys
import threading
import time

for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER_DIR = os.path.join(ROOT, "server 2025")


def leer_properties():
    props = {}
    with open(os.path.join(SERVER_DIR, "server.properties"), encoding="utf-8") as f:
        for line in f:
            if "=" in line and not line.startswith("#"):
                k, v = line.rstrip("\r\n").split("=", 1)
                props[k] = v
    return props


class Rcon:
    def __init__(self, host, port, password, timeout=5):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.req = 0
        self._send(3, password)
        rid, _, _ = self._recv()
        if rid == -1:
            raise PermissionError("contraseña de RCON incorrecta")

    def _send(self, kind, body):
        self.req += 1
        data = struct.pack("<ii", self.req, kind) + body.encode("utf-8") + b"\0\0"
        self.sock.sendall(struct.pack("<i", len(data)) + data)

    def _recv_exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("el servidor cerró la conexión")
            buf += chunk
        return buf

    def _recv(self):
        (length,) = struct.unpack("<i", self._recv_exact(4))
        data = self._recv_exact(length)
        rid, kind = struct.unpack("<ii", data[:8])
        return rid, kind, data[8:-2].decode("utf-8", "replace")

    def command(self, cmd):
        self._send(2, cmd)
        _, _, body = self._recv()
        return re.sub(r"§.", "", body)  # quitar códigos de color de Minecraft

    def close(self):
        self.sock.close()


def conectar():
    p = leer_properties()
    host = p.get("server-ip") or "127.0.0.1"
    if host == "0.0.0.0":
        host = "127.0.0.1"
    return Rcon(host, int(p.get("rcon.port", "25575")), p.get("rcon.password", ""))


def seguir_log(parar):
    """Muestra las últimas líneas de latest.log y luego las nuevas según llegan."""
    path = os.path.join(SERVER_DIR, "logs", "latest.log")
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f.readlines()[-20:]:
                print(line.rstrip())
            while not parar.is_set():
                line = f.readline()
                if line:
                    print(line.rstrip(), flush=True)
                else:
                    time.sleep(0.3)
    except FileNotFoundError:
        print("(no hay logs/latest.log)")


def main():
    ap = argparse.ArgumentParser(description="Cliente RCON de Multilocal-craft")
    ap.add_argument("comando", nargs="*", help="comando a enviar")
    ap.add_argument("--comprobar", action="store_true", help="solo comprobar si responde")
    ap.add_argument("--interactivo", action="store_true", help="consola interactiva con log en directo")
    args = ap.parse_args()

    try:
        rcon = conectar()
    except (OSError, PermissionError) as e:
        if not args.comprobar:
            print(f"No se puede conectar por RCON: {e}", file=sys.stderr)
        return 1
    if args.comprobar:
        rcon.close()
        return 0

    if args.comando:
        try:
            print(rcon.command(" ".join(args.comando)))
        except (OSError, ConnectionError):
            pass  # "stop" cierra la conexión antes de responder
        rcon.close()
        return 0

    if args.interactivo:
        parar = threading.Event()
        threading.Thread(target=seguir_log, args=(parar,), daemon=True).start()
        time.sleep(0.5)
        print("--- Escribe comandos del servidor (sin '/'). 'salir' o Ctrl+C para cerrar la consola. ---")
        try:
            for line in sys.stdin:
                cmd = line.strip()
                if cmd in ("salir", "exit", "quit"):
                    break
                if cmd:
                    respuesta = rcon.command(cmd)
                    if respuesta:
                        print(respuesta)
                    if cmd == "stop":
                        break
        except (KeyboardInterrupt, ConnectionError):
            pass
        parar.set()
        rcon.close()
        return 0

    ap.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
