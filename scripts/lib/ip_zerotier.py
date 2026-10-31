#!/usr/bin/env python3
# ------------------------------------------------------------
# Script: lib/ip_zerotier.py
# Propósito:
#   Imprimir la IP de este dispositivo dentro de la red ZeroTier del servidor
#   (por ejemplo 172.25.0.0/16). Sale con código 1 si el dispositivo no está en esa red.
#
#   Truco portable: un socket UDP "conectado" a una dirección de la red no envía nada,
#   pero el sistema elige la IP local con la que llegaría. Funciona en Windows, Linux,
#   Mac y Termux sin permisos de administrador, aunque haya varias redes ZeroTier.
#
# Uso: python ip_zerotier.py 172.25.0.0/16
# ------------------------------------------------------------
import ipaddress
import socket
import sys


def ip_en_red(red):
    net = ipaddress.ip_network(red, strict=False)
    destino = str(net.network_address + 1)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((destino, 9))
        ip = s.getsockname()[0]
    except OSError:
        return None
    finally:
        s.close()
    return ip if ipaddress.ip_address(ip) in net else None


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Uso: ip_zerotier.py <red, p. ej. 172.25.0.0/16>")
    ip = ip_en_red(sys.argv[1])
    if not ip:
        sys.exit(1)
    print(ip)
