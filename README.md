# Telegraf app for Home Assistant

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/configure_start_repository/?repository_url=https://github.com/tmtom/hassio-telegraf)

A maintained Home Assistant [app (add-on)](https://contributors.home-assistant.io/apps/)
that runs [Telegraf](https://github.com/influxdata/telegraf) — the plugin-driven
metrics agent. Primary use case: consume **MQTT** data (JSON payloads) and write
it as **InfluxDB line protocol** to **VictoriaMetrics** (or InfluxDB) — but the
app is general: any Telegraf input/output works, configured through **one
TOML file** you edit yourself.

## Features

- **MQTT consumer** with automatic broker credential discovery from the
  Supervisor (Mosquitto app), manual fallback options included — connection
  details never need to live in your config file.
- **VictoriaMetrics-ready**: commented output example with the exact
  connection details for the
  [VictoriaMetrics Community app](https://github.com/VictoriaMetrics-Community/homeassistant-addon-victoriametrics)
  (InfluxDB line protocol on port 8428).
- **One TOML file** (`telegraf.conf`) in the app config folder — seeded once on
  first start with a working MQTT input and commented examples, never
  overwritten afterwards. Extra `*.conf` files are picked up from
  `telegraf.conf.d/`.
- **Auto-reload on save** (`--watch-config`) — edit the config, and Telegraf
  restarts itself; no app restart needed.
- **Pre-built multi-arch images** from GitHub Actions — installs and updates
  pull from GHCR in seconds, no build on the device.
- **Persistent configuration** in the app config folder
  (`/addon_configs/<repo>_telegraf`), included in Home Assistant backups.
- Pinned Telegraf release (official Docker image), health monitoring,
  options with readable labels and hints in the Configuration tab.

## Supported architectures

`amd64` and `aarch64`. armv7/armhf are **not** built (deprecated in Home
Assistant app configs).

## Installation & documentation

Add this repository in **Settings → Apps → ⋮ → Repositories**
(`https://github.com/tmtom/hassio-telegraf`), install **Telegraf** and see the
Documentation tab, or read [`telegraf/DOCS.md`](telegraf/DOCS.md). The full
reference — config file location, environment variables, MQTT setup, output
cookbook (VictoriaMetrics, InfluxDB, prometheus_client), backup/restore,
troubleshooting — is in [`telegraf/USER_GUIDE.md`](telegraf/USER_GUIDE.md).

## Repository layout

- `telegraf/` — the app: manifest, Dockerfile, entrypoint, seed config, docs
  (`README`, `DOCS`, `USER_GUIDE`, `CHANGELOG`), translations
- `AGENTS.md` — project knowledge for contributors (and AI agents): architecture,
  hard-won facts, testing, release procedure
- `.github/workflows/` — CI: multi-arch image builds to GHCR, lint, automated
  Telegraf version bumps
- `repository.yaml` — repository metadata for the Supervisor

## Development

Pre-built multi-arch images (`ghcr.io/tmtom/hassio-telegraf`) are built by
GitHub Actions on every release. During development the `image:` key is kept
out of `telegraf/config.yaml` so the Supervisor builds locally. See
[`AGENTS.md`](AGENTS.md) for the development flow and test rigs.

## Licensing

MIT for the files in this repository (see [`LICENSE`](LICENSE)).

Third-party components:

- **Telegraf** — MIT, © InfluxData. Redistributed inside the container image
  via the official [`telegraf`](https://hub.docker.com/_/telegraf) Docker base
  image; the app adds only an entrypoint wrapper and a seed configuration.

Notable mentions: the (unmaintained) [Sabuto/hassio-repo](https://github.com/Sabuto/hassio-repo)
Telegraf add-on inspired the "point at your own config file" idea; this project
is a fresh implementation and carries no code from it.
