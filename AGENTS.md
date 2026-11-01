# AGENTS.md

Project knowledge for contributors and AI agents. Conventions mirror
`~/hassio-fhem` (read its AGENTS.md for the general Home Assistant app
lessons). This file records what is Telegraf-specific — update it whenever
something non-obvious is learned.

## Repo map

```
tmtom/hassio-telegraf/
├── .github/workflows/      # CI: builder (change detection), build-app (multi-arch
│                           #   GHCR images), lint, bump-telegraf (upstream pin)
├── telegraf/               # the app
│   ├── config.yaml         # app manifest (version, schema, services, ports)
│   ├── Dockerfile          # FROM telegraf:<pinned> + jq + run.sh + HEALTHCHECK
│   ├── run.sh              # entrypoint wrapper: seed config, MQTT env, exec upstream
│   ├── rootfs/usr/src/templates/telegraf.conf.seed  # first-start config template
│   ├── README.md           # Info tab
│   ├── DOCS.md             # Documentation tab (short setup guide)
│   ├── USER_GUIDE.md       # full reference (GitHub only)
│   ├── CHANGELOG.md        # per-release entries (Supervisor requirement)
│   └── translations/en.yaml# Configuration-tab labels (keys must match schema)
├── repository.yaml         # Supervisor repository metadata
└── LICENSE README.md AGENTS.md
```

## Architecture (read before changing anything)

- The app **wraps the official `telegraf` Docker image** (Debian variant,
  pinned `BUILD_FROM=telegraf:X.Y.Z`). Upstream's entrypoint chain is kept:
  `tini` (PID 1) → `/run.sh` (ours) → `/entrypoint.sh` (upstream: setcap
  `cap_net_raw,cap_net_bind_service`, drop to the `telegraf` user) → `telegraf`.
  Never exec `telegraf` directly from run.sh — the user-drop/caps are upstream's.
- **Config lives in `app_config`** (container `/config` → host
  `/addon_configs/5f87e677_telegraf/`): `/config/telegraf.conf` +
  `/config/telegraf.conf.d/*.conf` (merged via `--config-directory`). Seeded
  **once** on first start from `telegraf.conf.seed`, never overwritten;
  run.sh logs a fingerprint (bytes + md5) at every start for forensics.
- **MQTT auto-wiring**: manifest `services: [mqtt:want]` + `GET
  http://supervisor/services/mqtt` with `SUPERVISOR_TOKEN` (no `hassio_api`
  needed) → export `TELEGRAF_MQTT_{HOST,PORT,USERNAME,PASSWORD}` → the seed
  consumes them via `${VAR:-default}` env substitution. Manual `mqtt_*`
  options are the fallback. The payload is wrapped in `{"result","data"}`.
- **Strict env handling**: Telegraf ≥1.38 fails startup on undefined `${VAR}`.
  run.sh MUST export every variable the config references (empty is fine).
- **Env substitution is at the TOML value level** (verified with passwords
  containing `"` and `\`): export values **RAW** — TOML-escaping them makes
  Telegraf use the escaped literal as the password and MQTT auth fails
  ("not Authorized"). Literal `"`/`\` in the *file text* still break TOML —
  only the env-injected values are safe.
- App ID hash: SHA-1 of the lowercased repo URL, first 8 chars. `tmtom/hassio-telegraf`
  → `5f87e677` → hostname `5f87e677-telegraf`, host folder
  `/addon_configs/5f87e677_telegraf/`. The VictoriaMetrics Community app
  (`VictoriaMetrics-Community/homeassistant-addon-victoriametrics`) →
  `1bd4a9fb` → hostname `1bd4a9fb-victoria-metrics`, InfluxDB line protocol
  endpoint `http://1bd4a9fb-victoria-metrics:8428/write`.
- Health: native Docker `HEALTHCHECK` = `pgrep -x telegraf` (procps is in the
  base image). No `watchdog` manifest key (obsolete, lint rejects it).
  `init: false` (image has tini). **The Supervisor derives the UI state chip
  from the healthcheck; the lag ≈ one check interval — keep it tight (3s,
  fhem lesson).** With a healthcheck, apps stay "starting" until the first
  check resolves. NB (on-HA finding): a *failing* healthcheck does NOT change
  the chip — it shows "running" even while the agent is down (resilience-loop
  retry window); the Log tab is the honest signal.
- **`map` entries default to `read_only: true`** — always set
  `read_only: false` on the `app_config` entry or `/config` mounts read-only
  and run.sh dies at the first mkdir (`Read-only file system`). "Omit keys at
  their defaults" bit us here: the default is the wrong direction.
- Version scheme: `0.x.y-telegraf<minor>` (e.g. `0.1.0-telegraf1.40`). HA only
  offers an update when `version` changes — bump it for **every** release.
  Telegraf bumps take a minor bump of our `0.x` (handled by the bump workflow).

## Hard-won Telegraf knowledge (do not re-learn these the hard way)

- Env substitution happens at the TOML **value** level (after parsing): an
  env-injected password may contain `"`/`\` safely (export raw!), but the same
  characters typed literally in the file break TOML. Verified with a real
  auth-required broker and a `p"a\ss` password — an anonymous test broker
  masked a credential bug in the fhem project for a whole release.
- **`json` parser drops string fields by default** — only numeric/bool keys
  become fields; strings need `json_string_fields` (globs ok) or `tag_keys`.
  Metric name = the input plugin name (`mqtt_consumer`), the MQTT topic is a
  `topic` tag; `name_override` renames. Verified on 1.40.2.
- `--watch-config=notify` is **NOT delivered on HAOS**: inotify events do not
  cross the Supervisor's `app_configs` mount — verified on hardware with
  touch, vi and Samba/Notepad++ saves (all silent). **`poll` is the shipped
  default** (`--watch-config=poll --watch-interval=10s
  --watch-debounce-interval=5s`); `notify` works in plain Docker (WSL2 rig)
  and is documented as an opt-in. Reload RESTARTS the agent: the MQTT
  subscription drops for ~2s (QoS-0 messages in that window are lost).
- A config with zero outputs may be rejected; the seed ships a placeholder
  `[[outputs.file]]` (stdout) so first start always has an output. "Enable at
  least one output" is documented.
- **Inputs fail the whole agent at start**: if `mqtt_consumer` cannot connect
  (e.g. no broker / DNS failure), telegraf exits 1 with
  `Error running agent: starting input inputs.mqtt_consumer: ...`. There is no
  retry-at-start option — so run.sh wraps telegraf in a **resilience loop**
  (retry every `RETRY_SECONDS`, default 30): a bad config/broker logs the
  error + retry warning, the healthcheck reports unhealthy, and a FIXED
  config self-heals without a manual app start (stop signals are trapped and
  forwarded so Telegraf flushes cleanly).
- `skip_processors_after_aggregators = false` is pinned in the seed's `[agent]`
  (Telegraf 1.40 warns about a future default change; pin = no surprise).
- The upstream entrypoint drops to the `telegraf` user: run.sh chowns
  `/config` to `telegraf:telegraf` at every start so outputs can write there
  (verified: `outputs.file` into `/config` fails without it); root-capable
  editors (Samba/File editor/VS Code run as root on HAOS) are unaffected.
- Container hostname on HAOS = the app's DNS name (`local-telegraf` for local
  installs, `5f87e677-telegraf` from the repo) — a meaningful `host` tag, not
  a random ID (verified on hardware).

## Development & testing (WSL2 with Docker)

- Debug locally first (Phase 2 test rig in `/tmp/opencode/telegraf-test/`:
  mock Supervisor API with `/services/mqtt`, a Mosquitto with **required**
  auth, a real `victoriametrics/victoria-metrics` sink queried via
  `/api/v1/export`); CI is validation, not a debugger.
- Smoke before every push: `bash -n telegraf/run.sh`; `docker build -t
  hassio-telegraf-test ./telegraf`; run with the rig.
- During development `image:` stays out of `telegraf/config.yaml` (Supervisor
  builds locally on HA); it is enabled when the GHCR pipeline exists.

## Release procedure (every user-visible change)

1. Bump `version` in `telegraf/config.yaml` (`0.x.y-telegraf1.40`).
2. Add a `telegraf/CHANGELOG.md` entry on top.
3. Rewrite doc links in `telegraf/{README,DOCS,USER_GUIDE}.md`
   (`blob/<old-tag>/` → `blob/<new-tag>/`).
4. Commit, tag `v<version>`, `git push origin main --tags`. CI publishes
   `ghcr.io/tmtom/hassio-telegraf:<version>` + `latest` (multi-arch) and the
   bump workflow's `tag-release` job backstops missing tags.

## Development flow

Branch + PR for app content; merge to `main` = release (with version bump).
Telegraf version bumps are automated (`.github/workflows/bump-telegraf.yaml`:
weekly probe → bump PR → tag on merge).

First-release sequence (0.1.0-telegraf1.40): DONE (2026-11-01) — workflows
merged from `release/workflows`, `image:` enabled, tagged `v0.1.0-telegraf1.40`.
On-HA acceptance (Phase 3) passed before the release: seeding/auto-wire,
JSON→VM round-trip, poll reload (vi + Notepad++/Samba), config-error
self-heal, backup/restore, icons.

## Roadmap / status

- v1 (current): MQTT → VictoriaMetrics/InfluxDB pipeline, one TOML config,
  manual editing, MQTT auto-wire, backups, multi-arch CI.
- Later: in-HA config editing (ingress), secret-store plugins, host-metrics
  mode (`/hostfs`), docker input (`docker_api` + protection mode), armv7,
  Renovate.

## User-facing principles (keep these!)

- The config file is the user's — seed once, never overwrite.
- Connection details (hostnames, ports, auth) belong in seed comments and
  env defaults: the examples teach the wiring, the user picks the output.
- Configuration tab stays minimal (MQTT fallback options only).
- Everything the user needs must be in `DOCS.md`/`USER_GUIDE.md`; doc links
  point at release tags (`blob/<tag>/`).
