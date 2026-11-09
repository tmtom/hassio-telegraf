# Telegraf

[Telegraf](https://github.com/influxdata/telegraf) is the plugin-driven metrics
agent from InfluxData: 244+ **inputs**, 68+ **outputs**. This app runs the
official Telegraf image inside Home Assistant, configured through **one TOML
file** you control. The primary use case is consuming **MQTT** data (JSON
payloads) and writing it as **InfluxDB line protocol** to
**[VictoriaMetrics](https://github.com/VictoriaMetrics-Community/homeassistant-addon-victoriametrics)**
(or InfluxDB) — but any Telegraf input/output works.

- The configuration file lives in the app's config folder, is seeded with a
  working MQTT setup on first start, and is included in Home Assistant
  backups. It is **never overwritten** by the app.
- MQTT broker credentials are picked up automatically from the Supervisor
  (e.g. the Mosquitto app) — they are injected as environment variables and
  never need to live in your file.
- Edits apply automatically: save the file and Telegraf reloads itself.

## Installation

1. Install the **Mosquitto** app (or any MQTT broker). For the primary setup
   also install the
   **[VictoriaMetrics](https://github.com/VictoriaMetrics-Community/homeassistant-addon-victoriametrics)**
   app.
2. Add this repository (**Settings → Apps → ⋮ → Repositories**):
   `https://github.com/tmtom/hassio-telegraf`
3. Install **Telegraf** and start it. MQTT is discovered automatically.

> **Architectures:** `amd64` and `aarch64` only. armv7/armhf are not built.

## The configuration file

- **On the HAOS host:** `/addon_configs/5f87e677_telegraf/telegraf.conf`
  (via the `addon_configs` Samba share, the VS Code / File editor apps, or
  Terminal/SSH).
- **Inside the app:** `/config/telegraf.conf`. Extra `*.conf` files in
  `/config/telegraf.conf.d/` are loaded as well.

On first start a commented seed configuration is installed there: an active
**MQTT consumer** input (JSON payloads, topic `telegraf/#`) and a stdout
placeholder output so you see metrics in the **Log** tab immediately. Edit it
for your topics and enable a real output — the commented examples carry the
connection details for VictoriaMetrics, InfluxDB and Prometheus. **Save the
file and Telegraf reloads itself** — no restart needed.

If the MQTT broker or the config is wrong, the app stops with a clear error in
the Log tab; fix the file and restart.

## Backups

The configuration lives in the app config folder and is part of standard Home
Assistant backups (hot — the agent is stateless besides it). The folder also
survives uninstalling the app.

## Licensing

- The app's own files (scripts, config templates, docs) are **MIT** (see
  `LICENSE`).
- **Telegraf** itself is **MIT** (© InfluxData), redistributed inside the
  image via the official [`telegraf`](https://hub.docker.com/_/telegraf) Docker
  base image. The icon/logo is the official Telegraf mark (via
  [homarr-labs/dashboard-icons](https://github.com/homarr-labs/dashboard-icons),
  MIT).

## Full documentation

Options reference, config editing, MQTT setup, output cookbook
(VictoriaMetrics, InfluxDB, Prometheus), troubleshooting and more — in
**[USER_GUIDE.md](https://github.com/tmtom/hassio-telegraf/blob/v1.40.3.1/telegraf/USER_GUIDE.md)**.
