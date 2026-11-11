# Multilocal-craft
Un servidor de minecraft que permite la disponibilidad de mundo con despliegues individuales por parte de cada usuario compartiendo datos, asociados por zerotier para permitir solo un depsliegue a la vez y que siempre que alguien quiera usar el mundo, pueda desplegarlo o unirse, asegurando versiones de datos actualizadas del mundo.

Solo puede haber **un servidor a la vez**: acordad quién lo lanza.

## Scripts (`scripts/`)

Cada script existe como `.sh` (Linux, Mac, Termux y Git Bash) y como `.bat` (Windows, doble clic). Los `.bat` solo lanzan el `.sh` con el bash de Git para Windows.

| Script | Para qué |
|---|---|
| `preparar` | Pregunta si vas a usar Docker o terminal, comprueba **solo lo que necesita ese modo** y lo instala (winget, pkg, apt, dnf, pacman o brew). `--check` solo comprueba. |
| `iniciar` | Pregunta **Docker o terminal** y si **sincronizar antes con GitHub**. Arranca el servidor y Geyser con la IP de ZeroTier de este dispositivo. |
| `consola` | Abre la consola del servidor, vaya por Docker o por terminal. |
| `terminar` | Detecta cómo se lanzó, guarda el mundo, apaga el servidor y Geyser, deja la configuración como estaba y pregunta si **subir el mundo a GitHub**. |
| `actualizar` | Actualiza Minecraft y los plugins (ver abajo). |

Primera vez en un equipo nuevo: `scripts/preparar` y después `scripts/iniciar`.

| Modo | Qué hace falta en el equipo |
|---|---|
| **Docker** (PC) | Git, Docker y ZeroTier. Java y Python van dentro de los contenedores. |
| **Terminal** (PC o móvil) | Git, Python 3, Java 25 y ZeroTier; en Termux, además, `termux-api`. |

En **Termux (Android)** solo existe el modo terminal: Docker no funciona allí, así que los scripts ni lo preguntan.

- Sincronizar y subir usan siempre **la rama en la que estés** (normalmente `main`, la única).
- Sincronizar descarta los cambios locales que no hayas subido; el script avisa antes.
- En modo terminal, la ventana de `iniciar` es la consola del servidor; `consola` y `terminar` funcionan desde otra ventana.

## La IP del servidor (ZeroTier)

No hay que tocar ningún fichero a mano:

- `iniciar` detecta la IP de **este dispositivo** en la red ZeroTier del servidor (`ZEROTIER_RED` y `ZEROTIER_ID` en `.env`) y la usa para el servidor y Geyser.
- La IP se ve siempre: en un recuadro al arrancar, en el título de la ventana (modo terminal), en `consola` y en `terminar`. **Es la que tenéis que poner en Minecraft**, y cambia según quién lance el servidor.
- `terminar` devuelve `server-ip` a su valor original **antes de subir nada** a GitHub. Además, si detecta una IP de dispositivo en `server.properties`, no sube nada.
- Si el dispositivo no está en la red ZeroTier, `iniciar` lo avisa y deja elegir entre seguir solo en red local o cancelar.

## Servidor: Leaf (rendimiento en el móvil)

El servidor es **Leaf**, un derivado de Paper con los **mismos plugins y el mismo mundo**, que reparte trabajo entre los núcleos libres. En el móvil, con 4 jugadores a 32 de visión / 20 de simulación, quita los tirones que daba Paper (resultados en [docs/pruebas-movil.md](docs/pruebas-movil.md)). Para volver a Paper: en `server 2025/plugins.json` pon `"proyecto": "paper"` y ejecuta el actualizador.

- `JAVA_OPTS` en `.env`: ajustes de Java (recolector de basura afinado para el móvil). Los usan `iniciar` en terminal y Docker.
- Memoria: `iniciar` propone **3 GB en el móvil y 6 GB en PC** (fija: mínimo = máximo).

## Plugins para jugar

- **Shulkers:** clic derecho sobre una shulker en el inventario para abrirla sin colocarla (OpenShulk).
- **Ordenar inventario y cofres:** cada jugador lo activa una vez con `/chestsort` y elige el atajo (Shift + clic o doble clic en un hueco vacío). Ahí también están la ordenación automática y la transferencia rápida (Chestsort+).
- **Cargador de chunks:** se fabrica con obsidiana, diamantes y un ojo de Ender; máximo 5 por jugador (ChunkLoader).

## App de control (otro móvil)

`app-movil/` es una app Android para ver y manejar el servidor desde **otro móvil** de la red ZeroTier:

- **Estado:** servidor (TPS, MSPT, RAM, tiempo encendido), móvil host (batería, temperatura, RAM, almacenamiento) y copias en GitHub.
- **Jugadores** conectados.
- **Consola:** el log con colores y para enviar comandos.
- **Versiones:** lo mismo que `actualizar --check` (versión instalada, última, máxima con todos los plugins y qué plugins bloquean las más nuevas), con el botón **Actualizar servidor**.
- Botones **Copia de seguridad** (guarda sin apagar y sube a GitHub) y **Reiniciar**. Mientras duran, en su sitio sale el progreso: tiempo, paso actual (por ejemplo "4/4 Subiendo a GitHub · 45 %") y barra.

Funciona por SSH, sin procesos fijos en el host:

- `iniciar` arranca el `sshd` de Termux (puerto 8022) solo mientras el servidor está en marcha.
- La app lanza comandos cortos (`scripts/panel.py`) solo mientras está abierta.
- Para reiniciar o actualizar, el servidor se relanza dentro de `tmux` (sesión `mc`).

Puesta en marcha:

1. Compilar: `bash app-movil/compilar.sh` (SDK de Android + JDK 17+). Sale `app-movil/build/Multilocal.apk`.
2. En la app: ⚙ → IP del host → **Copiar comando**, y pegarlo una vez en Termux del host (autoriza la clave de esa app).
3. En el host hace falta `pkg install openssh tmux` (`preparar` lo comprueba). Para que suba a GitHub, el host necesita sus credenciales de git.

### Cuentas Bedrock → Java

En la pestaña **Jugadores** de la app, cualquier cuenta que entra desde Bedrock (las que empiezan por `.`) puede **jugar con el personaje de una cuenta Java**: su inventario, posición, homes y permisos. Por ejemplo, `.Ozaru33` → `OzaRu_`.

- Se elige con **Vincular…** y se quita con **Quitar**. Vale desde la próxima vez que esa persona entre.
- Vincular no toca los datos de nadie. Antes guarda una copia de los ficheros de las dos cuentas en `server 2025/copias-cuentas/`, que se sube con la siguiente copia.
- Los datos propios de la cuenta Bedrock se quedan guardados: al quitar el vínculo vuelve a tenerlos tal cual.
- Si la misma cuenta Java ya está dentro desde Java, uno de los dos se desconecta.
- Solo se puede vincular una cuenta que entre **por Bedrock**. Asociar en directo una cuenta Java con otra Java necesitaría un plugin dentro del servidor.

Usa la vinculación local de Floodgate: los vínculos están en `server 2025/plugins/floodgate/linked-players.db`, que viaja con el mundo, y la extensión es `floodgate-sqlite-database.jar`, en esa misma carpeta. Para quitar la función basta con borrar ese jar y reiniciar: el servidor sigue igual y cada cuenta Bedrock vuelve a la suya.

## Actualizar el servidor y los plugins

```bash
scripts/actualizar.sh          # Linux / Mac / Termux
scripts\actualizar.bat         # Windows (doble clic)
```

Busca la versión de Minecraft **más nueva que soporten todos los plugins** y actualiza el servidor (Leaf o Paper) y los plugins a ella. Si un plugin todavía no soporta la última versión, te dice cuál es y se queda en la más alta compatible (o no cambia nada). Así puedes volver a probar más adelante, cuando el plugin se haya actualizado.

Antes de instalar:
1. Te enseña una tabla con lo que hay instalado y lo que se va a poner, y pide confirmación.
2. Hace una **prueba de arranque** en una carpeta aparte, sin el mundo. Si algún plugin da error, no instala nada (el log queda en `server 2025/logs/actualizar-prueba.log`).
3. Guarda los jars viejos en `server 2025/.upgrade-backup/<fecha>/`.

| Opción | Para qué |
|---|---|
| `--check` | Solo comprobar; no cambia nada |
| `--yes` | Instalar sin preguntar |
| `--rollback` | Volver a los jars de antes de la última actualización |
| `--no-smoke` | Saltar la prueba de arranque (no recomendado) |

> **Importante:** al arrancar con una versión de Minecraft más nueva, el mundo se convierte y **ya no se puede abrir con la versión anterior**. Cuando se actualice, todos tenéis que actualizar a la vez. La primera subida tras una conversión cambia miles de ficheros del mundo (Minecraft los reorganiza en carpetas nuevas); `terminar` lo avisa y git solo sube lo que de verdad ha cambiado.

Para **añadir un plugin**, añádelo a `server 2025/plugins.json` con `"installed": null` (copia una entrada de Modrinth como ejemplo) y ejecuta el actualizador.

## Nota: Geyser (jugadores de Bedrock / móvil)

Geyser va aparte del servidor y, con `GEYSER_MODE=ondemand` en `.env` (por defecto), **solo se enciende cuando un jugador de Bedrock intenta entrar**. Se apaga solo **3 minutos después de que salga el último**.

- Con las versiones nuevas de Bedrock basta con abrir la lista de servidores para que Geyser se encienda; en unos segundos ya se puede entrar.
- Con las antiguas aparece *"Movil en espera - conectate para activarlo"*: el primer intento falla y a los ~30 s se entra.
- Ojo: cualquiera que tenga el servidor guardado y abra la lista lo enciende durante esos 3 minutos.
- Puertos: 60069 (UDP y TCP) y 60070 (UDP).
- Log: en terminal, `server 2025/logs/geyser-bajo-demanda.log`; en Docker, `docker logs mc-geyser`.
- Para tener Geyser **siempre encendido**, pon `GEYSER_MODE=siempre` en `.env`.
- En modo terminal necesita Python, que `preparar` instala (en Termux: `pkg install python`). En Docker va dentro de su contenedor.

### Convertir el mundo tras cambiar de versión

Al subir de versión de Minecraft, los chunks antiguos se convierten la primera vez que alguien los visita, y en el móvil eso provoca tirones. El actualizador ofrece convertir **todo el mundo de una vez** en ese momento; también se puede hacer a mano, con el servidor apagado y en un equipo con Java:

```bash
python scripts/convertir_mundo.py
```

Carga región a región las que existan (comando `/forceload`), comprueba que todos los chunks queden en el formato nuevo y retira los bordes a medio generar que crea. No necesita plugins.
