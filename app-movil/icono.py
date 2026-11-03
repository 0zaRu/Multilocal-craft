#!/usr/bin/env python3
# ------------------------------------------------------------
# icono.py: genera el icono adaptable de la app (bloque de hierba isométrico sobre cielo),
# pixel art propio dibujado por código. Solo librería estándar.
# Uso: python icono.py <carpeta res de salida>
# ------------------------------------------------------------
import os
import random
import struct
import sys
import zlib

N = 54                     # rejilla lógica (108 dp = 54 "píxeles" de 2 dp)
DENSIDADES = {"mdpi": 2, "hdpi": 3, "xhdpi": 4, "xxhdpi": 6, "xxxhdpi": 8}
HIERBA = [0x5FA83A, 0x6CBF45, 0x4E9A2E, 0x7AC74F, 0x589F35]
TIERRA = [0x866043, 0x79553A, 0x966C4A, 0x6C4A32, 0x8B6545]


def png(path, pix, escala):
    w = h = N * escala
    filas = bytearray()
    for y in range(h):
        filas.append(0)
        for x in range(w):
            filas += pix[y // escala][x // escala].to_bytes(4, "big")
    def trozo(tipo, datos):
        return struct.pack(">I", len(datos)) + tipo + datos + struct.pack(">I", zlib.crc32(tipo + datos))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + trozo(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + trozo(b"IDAT", zlib.compress(bytes(filas), 9)) + trozo(b"IEND", b""))


def rgba(c, luz=1.0, a=255):
    r, g, b = (c >> 16) & 255, (c >> 8) & 255, c & 255
    return (int(r * luz) << 24) | (int(g * luz) << 16) | (int(b * luz) << 8) | a


def tono(paleta, cara, u, v):
    return random.Random(f"{cara}{u},{v}").choice(paleta)


def bloque():
    """Primer plano: cubo de 28 de ancho, dentro de la zona segura del icono adaptable."""
    x0, yt, mitad, alto = 27, 12, 14, 15
    pix = [[0] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            px, py = x + 0.5, y + 0.5
            dx, dy = px - x0, py - (yt + mitad / 2)
            if abs(dx) / mitad + abs(dy) / (mitad / 2) <= 1:                       # cara de arriba
                a, b = dx / mitad + dy / (mitad / 2), -dx / mitad + dy / (mitad / 2)
                u, v = min(7, int((a + 1) / 2 * 8)), min(7, int((b + 1) / 2 * 8))
                pix[y][x] = rgba(tono(HIERBA, "t", u, v))
                continue
            if x0 - mitad <= px < x0:                                               # cara izquierda
                borde, cara, luz, u = yt + mitad / 2 + (px - (x0 - mitad)) / 2, "i", 0.82, int((px - (x0 - mitad)) / mitad * 8)
            elif x0 <= px <= x0 + mitad:                                            # cara derecha
                borde, cara, luz, u = yt + mitad - (px - x0) / 2, "d", 0.62, int((px - x0) / mitad * 8)
            else:
                continue
            if borde <= py < borde + alto:
                v = int((py - borde) / alto * 8)
                gotea = v == 2 and random.Random(f"g{cara}{u}").random() < 0.4      # la hierba cuelga un poco
                c = tono(HIERBA, cara, u, v) if v < 2 or gotea else tono(TIERRA, cara, u, v)
                pix[y][x] = rgba(c, luz)
    # contorno oscuro de un píxel
    borde = [[0] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            if pix[y][x] == 0 and any(0 <= y + j < N and 0 <= x + i < N and pix[y + j][x + i]
                                      for i, j in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                borde[y][x] = rgba(0x1B140F)
    return [[pix[y][x] or borde[y][x] for x in range(N)] for y in range(N)]


def cielo():
    """Fondo: cielo en franjas y un par de nubes."""
    arriba, abajo = (0x5E, 0x9B, 0xF5), (0xA8, 0xCD, 0xFF)
    pix = []
    for y in range(N):
        t = min(1.0, (y // 6) / (N // 6 - 1))
        c = tuple(int(arriba[i] + (abajo[i] - arriba[i]) * t) for i in range(3))
        pix.append([(c[0] << 24) | (c[1] << 16) | (c[2] << 8) | 255] * N)
    for nx, ny, w in ((4, 8, 12), (36, 14, 10), (24, 44, 14)):
        for y in range(ny, ny + 3):
            for x in range(nx + (1 if y == ny else 0), nx + w - (2 if y == ny else 0)):
                if 0 <= x < N:
                    pix[y][x] = rgba(0xFFFFFF, 1, 235) if y < ny + 2 else rgba(0xE4EEFF, 1, 235)
    return pix


def main():
    salida = sys.argv[1]
    frente, fondo = bloque(), cielo()
    for dens, esc in DENSIDADES.items():
        d = os.path.join(salida, f"mipmap-{dens}")
        os.makedirs(d, exist_ok=True)
        png(os.path.join(d, "ic_launcher_frente.png"), frente, esc)
        png(os.path.join(d, "ic_launcher_fondo.png"), fondo, esc)


if __name__ == "__main__":
    main()
