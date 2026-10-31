# Pruebas del servidor en el móvil (Redmi Note 12 Pro+, Termux)

Objetivo: **32 de visión y 20 de simulación sin caídas (tirones)**, sin tocar la jugabilidad ni las granjas.

- **Móvil:** Dimensity 1080 (2 núcleos A78 a 2,6 GHz y 6 A55 a 2,0 GHz), **7,7 GB de RAM** (más 6 GB de "memoria extendida" en disco), Android 14 / HyperOS 2.
- **Cómo se midió:** bots de Minecraft (mineflayer a través de ViaProxy) con 32 de visión, entrando por ZeroTier. El bot registra el hueco entre actualizaciones del servidor: **más de 1,5 s es un tirón** visible para el jugador. A la vez se registraron el MSPT/TPS del servidor (RCON), el ping, y la CPU, la temperatura y la memoria del móvil (adb).
- **Partida de referencia:** 4 jugadores, **2 explorando terreno nuevo** a unos 8 bloques/s y **2 en la base** (spawn, con las granjas), con el servidor ya en marcha.

## Resultado

| Configuración | Tirones | MSPT medio | TPS mín | Notas |
|---|---|---|---|---|
| Paper, Java por defecto | **29 en 10 min**, repartidos | 50–67 ms (por encima del límite de 50) | 17,6 | sobrecarga continua |
| **Leaf** + G1 de Aikar (4 GB) | 5 en 45 min (un único episodio) | 42 ms | 17,4 | memoria del móvil al límite |
| **Leaf + G1 para móvil (3 GB)** | **0 en 10 min y 0 en 30 min** | **38–39 ms** | **19,3** | **configuración elegida** |

Ping por ZeroTier durante las pruebas: 9 ms de media, máximo 54–72 ms, 1 paquete perdido de más de 8.000.

## Qué causaba los tirones

Perfil del hilo principal con Paper en la partida de referencia: **ocupado el 96,5 %** del tiempo.
- 50 % IA de entidades (84 aldeanos, 136 vacas, ovejas, gallinas... de las granjas);
- 28 % ticks de bloques (sobre todo la hierba extendiéndose en los ~6.700 chunks simulados a 20);
- solo 8 % carga y generación de chunks, 5 % aparición de mobs y 0,5 % red.

Con Paper no había margen sin tocar la jugabilidad. **Leaf** (fork de Paper, mismos plugins y mismo mundo) reparte parte de ese trabajo entre los núcleos libres. Los tirones que quedaban eran **pausas del recolector de basura** (G1) de 150–450 ms, que se corrigieron con el G1 ajustado al móvil.

## Configuración elegida

- **Servidor:** Leaf (`server 2025/plugins.json` → `"proyecto": "leaf"`). En `config/leaf-global.yml` están activados `async-pathfinding`, `async-entity-tracker`, `async-mob-spawning` y `async-playerdata-save`. **No cambian las reglas del juego.**
- **Java** (`JAVA_OPTS` en `.env`): G1 con:
  - memoria fija (`-Xms` = `-Xmx`; 3 GB en el móvil);
  - `-XX:-ClassUnloadingWithConcurrentMark` (pausas "Remark" más cortas);
  - 4 hilos de GC en lugar de 8 (que no esperen a los núcleos lentos);
  - `InitiatingHeapOccupancyPercent=30`.
- **Paper:** `grass-spread: 4` (la hierba se extiende cada 4 ticks; no afecta a granjas).

## Descartado (medido)

| Idea | Resultado |
|---|---|
| Android capa la CPU de Termux | **No**: misma velocidad que `adb shell` en primer plano, segundo plano y con la pantalla apagada (con los ajustes de batería y de procesos en segundo plano aplicados). |
| El hilo principal cae en núcleos pequeños | **No**: siempre en los grandes (cpu6/7). |
| Red / ZeroTier | **No** en las pruebas (el corte que hubo era que el PC no estaba autorizado en la red). |
| Ritmos de carga y envío de chunks, más hilos de chunks | Sin efecto. |
| ZGC / Shenandoah (pausas cortas) | **No funcionan en Termux** (Android bloquea una llamada al sistema que usan). |
| Rangos de activación y aldeanos inactivos | Ayudaban, pero **descartados por afectar a granjas**. |
| Java Flight Recorder | Tumba la JVM de Termux: no usarlo. |

## Notas

- **Primera carga de chunks antiguos:** la conversión al formato nuevo es cara. Por eso todo el mundo se convierte de antemano en el PC (`--forceUpgrade`).
- **Recién arrancado**, el servidor da algún tirón con la primera ráfaga de jugadores (Java aún no ha optimizado el código). Después desaparecen.
- **Memoria (3 GB frente a 4 GB, mismos ajustes de Java, misma partida de 10 min):** rendimiento igual (0 tirones en ambos; MSPT 37,8 / 37,1 ms; TPS mín 19,2 / 19,3). Con 4 GB el recolector salta la mitad de veces, pero Java ocupa 4,7 GB reales y **al móvil le quedan 0,45 GB libres** (frente a 1,2 GB con 3 GB) y usa más memoria extendida. Eso es riesgo de que Android mate procesos o tire de disco en sesiones largas, sobre todo si Geyser se enciende (hasta 512 MB más). **Se queda en 3 GB.**
- **Temperatura:** 53 °C estables (cargando), con limitación térmica ligera (nivel 1).
