# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Not a software project: it is a **shared Minecraft server whose world is synced through git**. Each player deploys the server on their own device in turns (PC with Docker or plain Java, or an Android phone with Termux), plays, then commits and pushes the world back. Players connect over a ZeroTier network; there is no lock or "someone is already hosting" check, so players coordinate who hosts. There is no build step. Project text (README, scripts, commit messages) is in Spanish.

- Server: **Paper 26.3**, **Java 25**. spark is built into Paper.
- Plugins (`server 2025/plugins/`): EssentialsX (dev build: no stable release supports 26.3 yet), Floodgate, LuckPerms, SkinsRestorer, ChunkLoader. Geyser runs **outside** Paper as Geyser Standalone (`server 2025/geyser/`).
- Branches: `main`, `mobile-version`, `try-update` (test branch). Work goes on a new branch.
- Everything must keep working in both Docker and plain terminal (Windows via Git Bash, Linux, Termux).

## Layout and conventions

- All scripts live in `scripts/`. Logic is written **once in bash** (`scripts/*.sh`); each `scripts/*.bat` only finds Git for Windows' `bash.exe` and runs the `.sh`. Shared functions are in `scripts/lib/comun.sh` (`ROOT` = parent of `scripts/`; env, OS detection, Python/Java lookup, state file, IP handling, git sync/upload).
- Requirements depend on the mode, and `preparar` checks only those: **terminal** = Git, Python ≥3.8 (stdlib only), Java `JAVA_VERSION`, ZeroTier (+ `termux-api` on Termux); **Docker** = Git, Docker, ZeroTier, with **no local Python**. Keep Docker mode Python-free on the host:
  - `ip_en_red` falls back to listing interface IPs (PowerShell, `ip`, `ifconfig`) when there is no Python;
  - `actualizar.sh` falls back to running `actualizar.py` inside the `geyser` image (it has Java and Python) as uid 1000 (or the host user on Linux);
  - the Geyser watcher runs inside its container.
- Termux is terminal-only: `preguntar_modo` forces `MODO=terminal` when `SO=termux`.
- Each bash script defines `main` and ends with `main "$@"; exit $?`, so bash has parsed the whole file before `git reset --hard` (sync) can rewrite it.
- `.gitattributes` forces LF for `*.sh`/`*.py`/Dockerfiles and CRLF for `*.bat`. Keep it, or the scripts break on Linux and Termux.
- On this Windows machine, another process sometimes maps freshly written files ("Invalid argument" / "user-mapped section"). Write to a temp file and `os.replace` if an in-place write fails. The same cause makes Paper log `Could not save spigot.yml` on Windows hosts; it is harmless.

## Running / testing

| | Command |
|---|---|
| Check tools | `bash scripts/preparar.sh --check --terminal` (or `--docker`) |
| Start | `bash scripts/iniciar.sh --docker` or `--terminal [GB]` (asks whether to sync with GitHub first) |
| Console | `bash scripts/consola.sh` |
| Stop (+ optional upload) | `bash scripts/terminar.sh` |
| Update versions | `bash scripts/actualizar.sh --check` |

- Local Java on the dev PC is 24; run terminal mode with `JAVA=/path/to/java25`.
- **Never run a container as root on the shared repo folder.** Files it creates get Linux 0644 root ownership, and the itzg server (uid 1000) then crash-loops on `logs/latest.log: Permission denied`. Use `--user 1000:1000`. If it happens, fix it with `chmod a+rwX` from a container.
- `_poner_server_ip` retries for up to 30 s and verifies the write, because Windows can briefly lock `server.properties` after the previous server stops. `iniciar` aborts if the write fails, rather than starting on the wrong IP.
- **Never answer "yes" to upload in tests.** `MLC_REMOTO=<remote>` points sync/upload at another remote (e.g. a local `git init --bare`).
- RCON: Docker uses `docker exec mc-server rcon-cli`; terminal mode uses `scripts/rcon.py` (reads host/port/password from `server.properties`). LuckPerms output doesn't return over RCON; use `lp export <name>` and read the `.json.gz`.
- Bedrock probe for tests: send RakNet `0x01` pings / `0x05` or an HTTP request to TCP 60069. When probing a service bound to the ZeroTier IP from the same host, bind the probe's source to that IP, or the reply never arrives.

## Versions: `server 2025/plugins.json` + `.env`

- `scripts/actualizar.py` picks the highest stable Paper version that every plugin in `plugins.json` declares support for (Fill v3 + Modrinth `game_versions`, Jenkins dev builds as fallback), reports blockers, and smoke-tests the new jars without the world. Then it backs up the old jars to `server 2025/.upgrade-backup/` and installs.
- It writes `MC_VERSION`, `PAPER_JAR` and `JAVA_VERSION` into the committed root `.env`. `.env` also holds `GEYSER_MODE` (`ondemand`|`siempre`), `ZEROTIER_RED` and `ZEROTIER_ID`.
- Docker uses `TYPE: CUSTOM` + `CUSTOM_SERVER=/data/${PAPER_JAR}`, so it runs exactly the jar `actualizar.py` installed.
- Upgrading Minecraft to 26.x reorganizes the world folders (`world/dimensions/...`, `world/players/`), so git sees ~5k delete/add pairs once (mostly identical content). `subir` warns above 500 changed world files.

## IP handling (no floating IP)

- `iniciar` gets this device's IP in `ZEROTIER_RED` via `lib/ip_zerotier.py` (a UDP socket "connected" to the network picks the local IP; works without admin and with several ZeroTier networks). If the device isn't in the network, it offers to continue with `0.0.0.0`.
- Terminal mode: `aplicar_ip` sets `server-ip=<IP>` in `server.properties` and saves the original in `server 2025/.estado-servidor` (gitignored, also stores `modo`, `ip` and the Geyser watcher's PID). Java then listens only on that IP, so Geyser gets `--java-address <IP>`. `restaurar_ip` runs in `iniciar`'s exit trap and in `terminar`; `subir` refuses to commit a changed `server-ip`.
- Docker mode: `server-ip` is untouched. `iniciar` passes `MLC_IP` to compose, which binds the published ports to it; Geyser gets `--anunciar $MLC_IP`.

## Geyser on demand

`scripts/geyser-bajo-demanda.py`:
- **While off**, it binds the Bedrock ports itself. It answers RakNet pings with a "Movil en espera" MOTD and treats a RakNet `0x05`, any NetherNet signaling TCP connection or any WebRTC UDP packet as a join attempt. Then it starts Geyser Standalone. New Bedrock clients hit the signaling port just by opening the server list, so Geyser is usually up before they press join.
- **While on**, it tracks players from Geyser's console. It starts Geyser with `-Duser.language=en` so the lines are stable:
  - NetherNet only logs `X (logged in as: Y) has connected …` / `X has disconnected from … Java server …`;
  - RakNet also logs `… tried to connect!` / `Bedrock user with ip: … has disconnected`.
  - When the list empties, a 3-minute countdown starts. Before stopping, it requires `geyser list` to report 0. A safety check every 2 minutes only drops entries older than 5 minutes.
- It writes `server 2025/geyser/config-generado.yml` (gitignored) from `config.yml` with `--escuchar` (bind IP), `--anunciar` (NetherNet `advertise-addresses`, otherwise STUN advertises the public IP) and `--java-address`.
- `--siempre` keeps Geyser on and restarts it if it dies.
- Docker: service `geyser` (`scripts/docker/geyser.Dockerfile`) is its own container with its own published ports and reaches Java as `mc-server`. Never use `network_mode: service:mc-server`: after `mc-server` restarts, Geyser would be stuck in the old network namespace.

## Gameplay config decisions

- Homes: 1 per player (`sethome-multiple` all 1 in `plugins/Essentials/config.yml`; `essentials.sethome.multiple` removed from LuckPerms group `default`). Existing extra homes were kept.
- ChunkLoader: players craft the block (obsidian, diamonds and an ender eye, in `plugins/ChunkLoader/config.yml`). `chunkloader.admin` is op-only, with a limit of 5 per player. It uses Paper chunk tickets, so removing the plugin leaves the world intact.

## Known issues

- `online-mode=false` and no login plugin jar: anyone on the network can join as an op username (see `ops.json`).
- `rcon.password` is committed in `server.properties` and `docker-compose.yml`.
- Performance config is untuned (`view-distance=32`, `sync-chunk-writes=true`, no JVM flags, `player-max-chunk-generate-rate: -1`). This is the next phase: mobile/Termux optimization.
