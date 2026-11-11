# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Not a software project: it is a **shared Minecraft server** (scripts, config and plugin data in git). Players connect over a ZeroTier network. There is no build step. Project text (README, scripts, commit messages) is in Spanish.

- **Host since 2026-11-10: the home server "central"** (Debian, Docker mode, repo at `~/minecraft/Multilocal-craft`, branch `main`; its ZeroTier IP is NOT written in the repo on purpose). Before, each player hosted in turns (PC with Docker or plain Java, or an Android phone with Termux) and the world travelled through git; the scripts still support that, but there is no lock or "someone is already hosting" check.
- **The world is NOT in git any more** (`server 2025/world*/` in `.gitignore`; GitHub's terms don't allow using the repo as game storage). `copia.sh` pushes everything else. The world is backed up locally by the host: on central, `~/central/copias/trabajos/minecraft.sh` (nightly, hot save-off/flush, levels daily/weekly/monthly in `~/backups/minecraft`). Older commits still contain worlds; rewriting history was deliberately not done. A new host must get the world from those local backups, not from git.

- Server: **Leaf 26.3** (Paper fork, same plugins/world; `server 2025/plugins.json` → `paper.proyecto: leaf`, accepting `experimental` builds since that's all Leaf ships for 26.x), **Java 25**. Chosen from phone load tests: see `docs/pruebas-movil.md`. spark is built in.
- Plugins (`server 2025/plugins/`): EssentialsX (dev build: no stable release supports 26.3 yet), Floodgate, LuckPerms, SkinsRestorer, ChunkLoader, OpenShulk, Chestsort+. Geyser runs **outside** Paper as Geyser Standalone (`server 2025/geyser/`).
- **Only branch: `main`** (since 2026-11-11 `mobile-version`, `try-update` and `central-host` were merged into it and deleted). The host pushes its backups there. For experiments, a short-lived branch merged back into `main`.
- Fixed host setup: copy `docker-compose.central.ejemplo.yml` to `docker-compose.central.yml` (gitignored) and start with `MLC_IP=<ZeroTier IP> docker compose -f docker-compose.yml -f docker-compose.central.yml up -d --build`. The host's IP is never committed (not in the app either: the app asks for it in ⚙ the first time).
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

- `scripts/actualizar.py` picks the highest server version that every plugin in `plugins.json` declares support for (server = Paper via Fill v3, or Leaf via api.leafmc.one with the build channels listed in `plugins.json`; plugins via Modrinth `game_versions`, Jenkins dev builds as fallback), reports blockers, and smoke-tests the new jars without the world. Then it backs up the old jars to `server 2025/.upgrade-backup/` and installs.
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

## Control app (`app-movil/`)

- Android app (plain Java, no Gradle: `app-movil/compilar.sh` runs aapt2/javac/d8/apksigner, signs with `~/.android/debug.keystore`). It is used from a phone that is **not** the host. Its only dependency is `libs/jsch.jar` (mwiede JSch 2.28.8, Maven Central). The icon is generated by `icono.py`.
- The user's rule: **no always-running processes on the host, and nothing inside the Minecraft server** (no plugin). So:
  - status, version and players come from Server List Ping;
  - everything else goes over SSH to Termux `sshd` (port 8022, user ignored, app's RSA key in `~/.ssh/authorized_keys`);
  - `iniciar` starts `sshd` on Termux only if it was not running (`sshd_propio` in the state file), and `iniciar`'s trap / `terminar` stop it.
- `scripts/panel.py` (short-lived per call):
  - `estado`: JSON; server via RCON `tps`/`mspt`/`list`, parsed locale-independently because the JVM may print `20,0` or Spanish text;
  - `log --desde N`, `comando` (stdin), `versiones` (`actualizar.py --json`);
  - `lanzar copia|reiniciar|actualizar`: detached; log in `logs/panel-operacion.log`, pid in `.panel-operacion`.
- `copia.sh`: hot backup (save-off / save-all flush / commit without `server.properties` if `server-ip` changed / save-on / push). Exits 0 if pushed, 1 if failed, 2 if committed but not pushed.
- `reiniciar.sh [--actualizar]`:
  - optional `copia.sh`, then stop;
  - optional `actualizar.py --yes`, and after a successful update a second `copia.sh` once the server is up, because new jars, `.env` and `plugins.json` exist only on the host until then;
  - relaunch with `tmux new-session -d -s mc ... iniciar.sh --terminal --sin-sincronizar <ram>`; RAM comes from the state file.
- Progress:
  - `copia.sh` and `reiniciar.sh` print `PASO n/m: text` via `paso` in `comun.sh` (`MLC_SIN_PASOS=1` silences them when `reiniciar --actualizar` nests `copia.sh`);
  - the push uses `git push --progress`;
  - `estado_operacion` returns `paso`/`pasos`/`paso_texto`/`porcentaje`/`inicio` and collapses repeated git progress lines;
  - the app swaps the bottom buttons for a progress card while an operation runs.
- The app hides its own RCON noise in the console (`Thread RCON Client`, `/list|/tps|/mspt`). The status poll runs every 10 s, the log poll every 2 s and only on the Consola tab.

## Bedrock → Java account links (Floodgate local linking)

- **How it works:**
  - Floodgate's own local linking: `player-link.enable-own-linking: true`, `type: sqlite`.
  - A linked Bedrock player logs in with the Java account's UUID and name, so it gets that account's inventory, position, Essentials data and permissions.
  - Local links take priority over global linking. There is no cache: every login queries the DB.
- **Table:** `plugins/floodgate/linked-players.db`, `LinkedPlayers(bedrockId string, javaUniqueId string, javaUsername string)`. UUIDs are stored as text, there is no primary key, and the Bedrock UUID is `UUID(0, xuid)` (`00000000-0000-0000-…`). The DB is committed, so links travel between hosts.
- **The app writes the DB through `panel.py`:**
  - `vincular`: snapshots both accounts' files into `server 2025/copias-cuentas/<date>_<name>/`, then deletes any previous row of that Bedrock or Java account and inserts the new row in one transaction;
  - `desvincular`;
  - `cuentas`: accounts from `usercache.json` and `world/players/data`, plus whether linking is loaded.
- **Linking never modifies player files.** Tested on a copy of the real world: after a Bedrock session as `OzaRu_`, the NBT inventory, ender chest, position and XP were identical, and `.Ozaru33`'s files were untouched. Unlinking gives the Bedrock account its own data back.
- **The extension jar:**
  - `floodgate-sqlite-database.jar` is built by `scripts/floodgate_sqlite.py` from the official GeyserMC `floodgatedb` 2.2.5 b138 jar, with its bundled sqlite-jdbc 3.36 replaced by 3.51.3.0.
  - Why: sqlite-jdbc 3.36 loads the glibc native on Termux ("libc.so.6 not found"). 3.51.3.0 is the last release that both detects Termux and ships `Linux-Android/aarch64`.
  - In practice Leaf's own `libraries/org/xerial/sqlite-jdbc/3.49.1.0` wins (parent-first class loading), and it also works on Termux. Both were checked on the phone with an isolated probe.
- **Removing it is safe:** delete the jar (or set `enable-own-linking: false`) and restart. The server starts normally and Bedrock players use their own UUIDs again.
- **Limit:** only Bedrock → Java. Java → Java aliasing would need a plugin inside the server, which the user rules out.

## Gameplay config decisions

- Homes: 1 per player (`sethome-multiple` all 1 in `plugins/Essentials/config.yml`; `essentials.sethome.multiple` removed from LuckPerms group `default`). Existing extra homes were kept.
- ChunkLoader: players craft the block (obsidian, diamonds and an ender eye, in `plugins/ChunkLoader/config.yml`). `chunkloader.admin` is op-only, with a limit of 5 per player. It uses Paper chunk tickets, so removing the plugin leaves the world intact.
- OpenShulk: right-click a shulker in the inventory opens it (contents stay in the item's vanilla `container` component; no database).
- Chestsort+: off by default for each player; each enables it and picks the shortcut in `/chestsort`. Needs `chestsort.use`, granted to LuckPerms group `default`. Settings live in each player's data (ignored if the plugin is removed).

## Known issues

- `online-mode=false` and no login plugin jar: anyone on the network can join as an op username (see `ops.json`).
- `rcon.password` is committed in `server.properties` and `docker-compose.yml`.
- Performance config is untuned (`view-distance=32`, `sync-chunk-writes=true`, no JVM flags, `player-max-chunk-generate-rate: -1`). This is the next phase: mobile/Termux optimization.

## Phone performance findings (keep in mind before changing tuning)

- Main-thread time on the phone at 32/20 goes to entity AI and block ticking of the bases' farms, not to networking or chunk generation. Do **not** reduce entity activation ranges or make villagers inactive: that breaks farms (the user's hard requirement). Distances stay 32/20.
- Leaf `config/leaf-global.yml`: async-pathfinding, async-entity-tracker, async-mob-spawning, async-playerdata-save enabled (no gameplay change).
- `JAVA_OPTS` (.env): G1 tuned for the phone (`-XX:-ClassUnloadingWithConcurrentMark`, 4 GC threads, IHOP 30, MaxGCPauseMillis 50); `iniciar` runs with `-Xms = -Xmx` (default 3 GB on Termux, 6 GB elsewhere).
- Termux JDK: ZGC/Shenandoah fail ("Bad system call", blocked by Android seccomp); Java Flight Recorder crashes the JVM. Only G1/Parallel/Serial work.
- Paper/Leaf 26.x do not implement `--forceUpgrade` ("World upgrade ... not yet implemented in Paper 26.1"). Old-format chunks convert lazily on first load, which is expensive on the phone. `scripts/convertir_mundo.py` converts every existing region with `/forceload` (Chunky does NOT work: it skips existing chunks), verifies each chunk's DataVersion, and deletes the half-generated border region files `/forceload` creates. `actualizar.py` offers it after a Minecraft version change.
