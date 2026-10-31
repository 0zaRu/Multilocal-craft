# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Not a software project: it is a **shared Minecraft server whose world is synced through git**. Each player deploys the server on their own machine in turns, plays, then commits and pushes the world back. Only one deployment may run at a time; players connect over a ZeroTier network. There is no build or lint step. Project text (README, scripts, commit messages) is in Spanish.

- Server: **Paper 26.3**, **Java 25**. No Fabric/mods. spark is built into Paper.
- Plugins (`server 2025/plugins/`): EssentialsX (dev build: no stable release supports 26.3 yet), Floodgate, LuckPerms, SkinsRestorer, ChunkLoader. Geyser runs **outside** Paper as Geyser Standalone (`server 2025/geyser/`), see below. `LoginSecurity/` and `Updater/` are leftover data folders with no `.jar`.
- `server 2025/server.jar` is an older vanilla/legacy jar kept in the repo; the Paper jar is the one launched.
- Branches: `main` (PC deployments), `mobile-version` (Android/Termux deployment), `try-update` (test branch). Work goes on a new branch, not directly on `main`/`mobile-version`.
- Must keep working in both Docker and plain terminal (Windows, Linux, Termux on Android).

## Versions: `server 2025/plugins.json` + `.env`

`actualizar.py` (wrappers `actualizar.sh` / `actualizar.bat`) is the only thing that should change the Paper/plugin jars:

- It reads the plugin list from `server 2025/plugins.json` (source: `modrinth` or `geysermc`; `dev_fallback` = Jenkins dev builds when no release supports the version) and records what is installed there.
- It picks the **highest stable Paper version that every plugin declares support for** (Fill v3 API + Modrinth `game_versions`), reports which plugin blocks any newer version, then smoke-tests the new jars by booting Paper in a temp dir without the world (local Java, or `eclipse-temurin` via Docker if local Java is too old). Smoke-test log: `server 2025/logs/actualizar-prueba.log`.
- Old jars go to `server 2025/.upgrade-backup/<timestamp>/` (gitignored); `--rollback` restores them.
- It writes the root `.env` (committed, no secrets): `MC_VERSION`, `PAPER_JAR`, `JAVA_VERSION`, `GEYSER_MODE`, `COMPOSE_PROFILES`. Both `iniciar.*` scripts and `docker-compose.yml` read it.
- Options: `--check` (no changes; exit 3 = a newer MC exists but is blocked), `--yes`, `--no-smoke`, `--rollback`.
- To add a plugin: add an entry with `"installed": null` and run `actualizar.py`.

## Running the server

| Mode | Start | Stop / backup |
|---|---|---|
| Windows local | `iniciar.bat [GB]` (as admin; optionally `git reset --hard origin/main` to pull the world) | `terminar.bat` → option 1 |
| Docker | `docker compose up -d --build` | `terminar.bat` → option 2 |
| Linux/Mac/Termux | `./iniciar.sh [GB]` | `./terminar.sh` |

- Java: the scripts use `$JAVA` (or `java` on PATH) and refuse to start if it is older than `JAVA_VERSION`.
- Docker: `TYPE: CUSTOM` with `CUSTOM_SERVER=/data/${PAPER_JAR}`, so Docker runs exactly the jar `actualizar.py` installed (itzg does not download Paper). Console: `consola.bat` (`docker exec -it mc-server rcon-cli`). LuckPerms command output does not come back over RCON; use `lp export <name>` and read `plugins/LuckPerms/<name>.json.gz` to inspect permissions.
- Ports: 60068 Java; 60069 UDP (Bedrock RakNet) + TCP (NetherNet signaling); 60070 UDP (NetherNet/WebRTC).
- The `.paper.env`, `.papermc-manifest.json` and `.rcon-cli.*` files in `server 2025/` are written by the itzg Docker image, not by hand.
- `server 2025/start.sh` and `pebblehost.yml` are leftovers from PebbleHost hosting.

## Geyser on demand (Bedrock / mobile players)

`GEYSER_MODE=ondemand` in `.env` (default). `geyser-bajo-demanda.py` (stdlib-only Python) keeps Geyser Standalone **off** until a Bedrock client tries to connect:

- While off it binds the Bedrock ports itself: it answers RakNet pings with a "móvil en espera" MOTD and treats a RakNet `0x05`, any NetherNet signaling TCP connection or any WebRTC UDP packet as a join attempt. It then frees the ports and starts Geyser; that first attempt fails and the player retries in ~30 s.
- While on, it tracks players from Geyser's console events (`tried to connect!` / `Bedrock user with ip: … has disconnected`; Geyser is started with `-Duser.language=en` so these are stable). When the list is empty it starts a 3 min countdown (`--idle-min`), and before stopping it asks `geyser list` and stops only if it reports 0. Every 2 min `geyser list` is used as a safety net (it only drops entries older than 5 min, because a login in progress is not listed yet).
- Floodgate stays as a Paper plugin; the watcher copies `plugins/floodgate/key.pem` into `server 2025/geyser/`. Geyser config: `server 2025/geyser/config.yml` (`transport: both`, Java at 127.0.0.1:60068).
- Terminal: `iniciar.sh` runs it in the background, and `iniciar.bat` in a minimized window that gets killed with `taskkill /T` when the server stops. Docker: the `geyser` service (`geyser/Dockerfile`, profile `geyser-ondemand`) uses `network_mode: service:mc-server`, so it shares mc-server's ports and reaches Java on 127.0.0.1.
- `GEYSER_MODE=plugin` makes `actualizar.py` install Geyser-Spigot in `plugins/` instead (always on).

## Gameplay config decisions

- Homes: 1 per player (`sethome-multiple` all 1 in `plugins/Essentials/config.yml`, and `essentials.sethome.multiple` removed from LuckPerms group `default`). Existing extra homes in `userdata/` were kept.
- ChunkLoader: players get the block by **crafting** (obsidian/diamonds/ender eye, in `plugins/ChunkLoader/config.yml`). `chunkloader.admin` is op-only, and the limit is 5 per player (`player-chunk-limit`). The plugin uses Paper chunk tickets, so removing it leaves the world intact.

## Sync workflow (what `terminar.*` does)

1. `git checkout main` + `git pull origin main` (hard-coded to `main`, even when on another branch — do not run it from test branches).
2. `git checkout -- "server 2025/server.properties"` to discard the local `server-ip` (each player sets their ZeroTier IP there before launching). Never commit a ZeroTier IP in `server.properties`.
3. `git add -A`, commit `Copia de seguridad automática: <timestamp>`, `git push origin main`.

`terminar.bat` additionally manages a floating ZeroTier IP (`172.25.254.254`) on the local interface and, in Docker mode, runs `rcon-cli save-all flush` and checks the logs for "Saved the game" before stopping the container.

Because the whole server directory (worlds ~5 GB, logs, plugin caches, `.paper-remapped`) is committed, almost every play session produces a large diff.

## Known issues

- A world opened with a newer Minecraft version cannot be opened with an older one: everyone must update together.
- On a Windows host, Paper sometimes logs `Could not save spigot.yml/bukkit.yml/commands.yml` (file is mapped by another Windows process). The first write succeeds; this does not happen on Linux/Termux.
- The README mentions a `mobile` argument for `iniciar.bat` that is not implemented.
- `online-mode=false` and no login plugin jar: anyone on the network can join as an op username (see `ops.json`).
- `rcon.password` is committed in `server.properties`, `docker-compose.yml` and `.rcon-cli.*`.
- Performance config is untuned: `view-distance=32`, `sync-chunk-writes=true`, no JVM flags beyond `-Xms/-Xmx`, `player-max-chunk-generate-rate: -1` in `config/paper-global.yml`. Tuning lives in `server.properties`, `bukkit.yml`, `spigot.yml` and `config/paper-*.yml`.

## Measuring performance

`/spark tps`, `/spark profiler start` … `/spark profiler stop`. Target: stable 20 TPS, MSPT under 50.
