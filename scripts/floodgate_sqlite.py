#!/usr/bin/env python3
# ------------------------------------------------------------
# Script: floodgate_sqlite.py
# Propósito:
#   Montar server 2025/plugins/floodgate/floodgate-sqlite-database.jar, la extensión con la que
#   Floodgate guarda la vinculación local de cuentas Bedrock -> Java (linked-players.db).
#
#   El jar oficial de GeyserMC trae sqlite-jdbc 3.36, que en Termux (Android) intenta cargar la
#   librería nativa de Linux con glibc y falla ("libc.so.6 not found"). Aquí se toma el jar oficial
#   y se cambia su sqlite-jdbc por la 3.51.3.0, que detecta Termux y trae la nativa de Android
#   (la última versión que la incluye). Floodgate solo usa JDBC estándar ("org.sqlite.JDBC").
#   Las dos descargas se comprueban con su suma oficial.
#
# Uso: python floodgate_sqlite.py   (rehacerlo si se actualiza Floodgate a otra versión mayor)
# ------------------------------------------------------------
import hashlib
import io
import os
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESTINO = os.path.join(ROOT, "server 2025", "plugins", "floodgate", "floodgate-sqlite-database.jar")
UA = {"User-Agent": "Multilocal-craft floodgate_sqlite.py"}

FLOODGATE_DB = ("https://download.geysermc.org/v2/projects/floodgatedb/versions/2.2.5/builds/138/downloads/sqlite",
                "sha256", "df4ae91e452f7124f11b97d625357b00b13208c056e68c5473e1599b1e443317")
SQLITE_JDBC = ("https://repo1.maven.org/maven2/org/xerial/sqlite-jdbc/3.51.3.0/sqlite-jdbc-3.51.3.0.jar",
               "sha1", "a6a5177ff8d35028a8943129aa4a18e850fe1387")


def descargar(url, algoritmo, suma):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r:
        datos = r.read()
    if hashlib.new(algoritmo, datos).hexdigest() != suma:
        sys.exit(f"La descarga no coincide con su {algoritmo} oficial: {url}")
    return zipfile.ZipFile(io.BytesIO(datos))


def main():
    print("Descargando la extensión SQLite de Floodgate y sqlite-jdbc...")
    fg, sq = descargar(*FLOODGATE_DB), descargar(*SQLITE_JDBC)
    os.makedirs(os.path.dirname(DESTINO), exist_ok=True)
    tmp = DESTINO + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        # De Floodgate: su código, init.json y el manifiesto
        for i in fg.infolist():
            if i.filename.startswith("org/geysermc/") or i.filename in ("init.json", "META-INF/MANIFEST.MF"):
                z.writestr(i, fg.read(i))
        # De sqlite-jdbc: todo menos su manifiesto y module-info (Floodgate lo carga como jar normal)
        for i in sq.infolist():
            if i.filename in ("META-INF/MANIFEST.MF", "module-info.class") or i.filename.startswith("META-INF/versions/"):
                continue
            z.writestr(i, sq.read(i))
    os.replace(tmp, DESTINO)
    print(f"Listo: {os.path.relpath(DESTINO, ROOT)} (Floodgate DB 2.2.5 b138 + sqlite-jdbc 3.51.3.0)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
