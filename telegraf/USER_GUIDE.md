# Telegraf app — user guide

This is the full reference for the Telegraf app. The Documentation tab shows
the short [setup guide](https://github.com/tmtom/hassio-telegraf/blob/v0.1.0-telegraf1.40/telegraf/DOCS.md).

- [Options reference](#options-reference)
- [Where the configuration lives](#where-the-configuration-lives)
- [Editing the configuration](#editing-the-configuration)
- [The seed configuration](#the-seed-configuration)
- [Environment variables](#environment-variables)
- [Outputs cookbook](#outputs-cookbook)
- [Inputs beyond MQTT](#inputs-beyond-mqtt)
- [Backups, uninstall, updates](#backups-uninstall-updates)
- [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

## Options reference

The Configuration tab is deliberately minimal — everything else is file
editing.

| Option | Default | Meaning |
|---|---|---|
| `mqtt_automatic` | `true` | Discover the MQTT broker via the Supervisor `mqtt` service (recommended with the Mosquitto app). Refreshed on every app start. |
| `mqtt_host` | *(empty)* | Manual broker host, used when automatic discovery is off or fails. The official Mosquitto app is `core-mosquitto`. |
| `mqtt_port` | `1883` | Manual broker port. |
| `mqtt_user` | *(empty)* | Manual broker user (empty = anonymous). |
| `mqtt_password` | *(empty)* | Manual broker password. |

Optional network ports (disabled by default; enable on the app's Network
panel when a plugin needs them):

| Port | Used by |
|---|---|
| `8125/udp` | `[[inputs.statsd]]` |
| `8092/udp` | `[[inputs.socket_listener]]` (UDP) |
| `8094/tcp` | `[[inputs.socket_listener]]` (TCP) |
| `9273/tcp` | `[[outputs.prometheus_client]]` |

## Where the configuration lives

| | Path |
|---|---|
| Inside the app | `/config/telegraf.conf` (+ `/config/telegraf.conf.d/*.conf`) |
| On the HAOS host | `/mnt/data/supervisor/app_configs/<repo>_telegraf/telegraf.conf` |

The host folder is the app's **config folder** (the `addon_configs` Samba
share — on current HAOS the folder is `app_configs`, historically
`addon_configs`; the share exposes it as `\\<ha>\addon_configs\<repo>_telegraf\`).
The name contains the repository ID (`5f87e677`, or `local` for a local
install) — yours is shown on the app's Info page. All `*.conf` files in
`telegraf.conf.d/` are merged with the main file (Telegraf's
`--config-directory`) — use drop-ins for extra inputs/outputs without
touching the main file.

The seed is installed **once** on first start and never overwritten. Every
start logs a fingerprint (`bytes, md5`) of your file — if you ever wonder
"who changed my config", the Log tab tells you what the app saw.

## Editing the configuration

Any editor that can reach `/addon_configs` works:

- **Samba** app — mount the `addon_configs` share and use your desktop editor.
- **VS Code** or **File editor** app — open
  `/addon_configs/5f87e677_telegraf/telegraf.conf`.
- **Terminal/SSH** app — `nano /addon_configs/5f87e677_telegraf/telegraf.conf`.

**Saved changes apply automatically** — Telegraf polls the config every 10 s
and restarts itself a moment after a change: no app restart needed.

- The reload briefly (~2 s) restarts the agent: MQTT messages arriving in that
  window can be missed (QoS 0). Save deliberately, not per keystroke.
- Polling is editor-agnostic (Samba saves, atomic write+rename saves, vi, …)
  and takes effect within ~15 s. If you prefer instant inotify-based reloads
  and your editor delivers file events reliably, switch the app `CMD` to
  `--watch-config=notify --watch-debounce-interval=5s` (Dockerfile `CMD`) —
  note that this was **not** delivered for Samba/desktop-editor saves on a
  standard HAOS install (why poll is the default).

## The seed configuration

The seed is meant to be edited. What matters:

### The MQTT input

```toml
[[inputs.mqtt_consumer]]
  servers = ["tcp://${TELEGRAF_MQTT_HOST:-core-mosquitto}:${TELEGRAF_MQTT_PORT:-1883}"]
  username = "${TELEGRAF_MQTT_USERNAME}"
  password = "${TELEGRAF_MQTT_PASSWORD}"
  topics = ["telegraf/#"]
  data_format = "json"
```

- The connection is **auto-wired** from the Supervisor's MQTT service and
  refreshed on every app start. To hardcode instead, replace the `${...}`
  references with literals (see [Environment variables](#environment-variables)).
- Set `topics` to your senders' topics. `#` subscribes to everything the
  broker allows. Watch your broker first to see what is out there:
  `mosquitto_sub -h <broker> -t '#' -v` (Terminal/SSH app) or MQTT Explorer.
- `data_format = "json"` for JSON payloads; use `"influx"` when the sender
  already emits InfluxDB line protocol.

### JSON parsing gotchas (read this once!)

- **String fields are dropped by default** — only numeric/bool JSON keys
  become metric fields. Declare strings explicitly:
  `json_string_fields = ["status", "message"]` (globs allowed) or turn keys
  into tags with `tag_keys = ["device", "room"]`.
- **Metric naming:** metrics are named after the input plugin
  (`mqtt_consumer`); the MQTT topic arrives as the `topic` tag. Use
  `name_override = "mysensors"` to rename.
- Timestamps: without `json_time_key` the receive time is used. To use a
  payload timestamp: `json_time_key = "timestamp"` +
  `json_time_format = "2006-01-02T15:04:05Z"` (Go reference time layout, e.g.
  `unix_ms` for epoch milliseconds).

A realistic example (sensor gateways on separate topic families, one input
block each):

```toml
[[inputs.mqtt_consumer]]
  servers = ["tcp://${TELEGRAF_MQTT_HOST:-core-mosquitto}:${TELEGRAF_MQTT_PORT:-1883}"]
  username = "${TELEGRAF_MQTT_USERNAME}"
  password = "${TELEGRAF_MQTT_PASSWORD}"
  topics = ["wmbusmeters/+", "tele/+/SENSOR"]
  data_format = "json"
  tag_keys = ["location", "sentype"]
  json_time_key = "timestamp"
  json_time_format = "2006-01-02T15:04:05Z"
```

(Use separate `[[inputs.mqtt_consumer]]` blocks when topic families need
different parser settings.)

### Outputs

The seed ships a placeholder `[[outputs.file]]` (stdout) so every metric shows
up in the **Log** tab — proof-of-life while you pick a real output. Remove it
once an output is enabled (or keep it — it only costs log lines).

## Environment variables

`run.sh` exports four variables on every app start, consumed by the seed via
`${VAR}` references:

| Variable | Content |
|---|---|
| `TELEGRAF_MQTT_HOST` | broker host (default fallback: `core-mosquitto`) |
| `TELEGRAF_MQTT_PORT` | broker port (default fallback: `1883`) |
| `TELEGRAF_MQTT_USERNAME` | broker user (empty = anonymous) |
| `TELEGRAF_MQTT_PASSWORD` | broker password |

Notes:

- Values come from the Supervisor `mqtt` service (when `mqtt_automatic` is on)
  or from the manual `mqtt_*` options; the manual option fills in when the API
  is unavailable.
- They are exported **raw**: passwords may contain any character (verified
  with `"` and `\`). The same characters typed literally into the file must be
  valid TOML string escapes — prefer the variables for credentials.
- Telegraf ≥ 1.38 refuses to start on an **undefined** `${VAR}` — use
  `${VAR:-default}` for your own variables and make sure they exist.
- The variables are ordinary environment variables: reference them from any
  plugin, e.g. also in `[[outputs.mqtt]]` or external brokers:

```toml
# External broker (e.g. a cloud broker) with a fixed token:
[[inputs.mqtt_consumer]]
  servers = ["ssl://mqtt.example.com:8883"]
  username = "my-token"
  topics = ["zigbee2mqtt/+"]
  data_format = "json"
```

## Outputs cookbook

### VictoriaMetrics (recommended)

The [VictoriaMetrics Community app](https://github.com/VictoriaMetrics-Community/homeassistant-addon-victoriametrics)
accepts InfluxDB line protocol — Telegraf's `outputs.influxdb` works as-is:

```toml
[[outputs.influxdb]]
  urls = ["http://1bd4a9fb-victoria-metrics:8428"]
  database = "telegraf"        # ignored by VictoriaMetrics, kept for InfluxDB
  # Only if the VM app's HTTP auth is enabled (enableHTTPAuth):
  # username = "..."
  # password = "..."
```

- `1bd4a9fb-victoria-metrics` is the VM app's internal DNS name (its
  "hostname" on the Info page — derived from *its* repository URL, so it
  differs if you added that repository under a different address).
- If the VM app's port 8428 is published to your HA host, your own name works
  too, e.g. `urls = ["http://homeassistant.local.lan:8428"]`.
- Naming in VM: a metric with multiple fields is stored as one series per
  field, `<metric>_<field>` (e.g. `mqtt_consumer_marker`,
  `mqtt_consumer_temperature`) with the tags attached.
- If writes fail with 401/403: check `enableHTTPAuth` in the VM app and set
  `username`/`password` here. If the connection is refused: check the VM
  app's **Network** section has port 8428 mapped.
- Verify in VM's UI (`http://<ha>:8428/vmui`): query
  `mqtt_consumer_marker` or `count({__name__!=""})` or look for your metric
  names.

### InfluxDB 1.x / 2.x

```toml
[[outputs.influxdb]]           # 1.x
  urls = ["http://influxdb.local:8086"]
  database = "telegraf"
  username = "..."
  password = "..."

[[outputs.influxdb_v2]]        # 2.x / 3.x
  urls = ["http://influxdb.local:8086"]
  token = "..."
  organization = "..."
  bucket = "telegraf"
```

### Prometheus scrape endpoint

```toml
[[outputs.prometheus_client]]
  listen = ":9273"
```

Enable port `9273/tcp` on the app's Network panel first; scrape
`http://<ha>:9273/metrics` (or the app's internal DNS name).

### MQTT output

Forward (or mirror) metrics to a broker — uses the same auto-wired variables
as the input:

```toml
[[outputs.mqtt]]
  servers = ["tcp://${TELEGRAF_MQTT_HOST:-core-mosquitto}:${TELEGRAF_MQTT_PORT:-1883}"]
  username = "${TELEGRAF_MQTT_USERNAME}"
  password = "${TELEGRAF_MQTT_PASSWORD}"
  topic_prefix = "telegraf"
  data_format = "json"
```

## Inputs beyond MQTT

- **statsd / socket listeners:** enable the matching port on the Network
  panel, then use `[[inputs.statsd]]` or `[[inputs.socket_listener]]`
  (`service_address = "udp://:8092"` etc.). The seed has commented examples.
- **Container-level system inputs** (`[[inputs.cpu]]`, `[[inputs.mem]]`,
  `[[inputs.disk]]`): report the **app container**, not the HAOS host. That is
  rarely what you want. Host metrics need the `/hostfs` mount trick —
  roadmap item, not shipped in v1.
- **Docker input** (`[[inputs.docker]]`): needs `docker_api` and protection
  mode off — roadmap item (deliberately not enabled in v1).

## Backups, uninstall, updates

- **Backups** are hot (default): the agent is stateless, the config folder is
  the payload. It is included in standard Home Assistant backups — restore
  brings your `telegraf.conf` back exactly.
- **Uninstall** keeps the config folder (`/addon_configs/..._telegraf`); a
  reinstall picks your config up where you left it.
- **App updates** never touch your config (seeded once). They bump the pinned
  Telegraf version (the app version `0.x.y-telegraf1.40` tracks it). In-flight
  metrics in memory can be lost on stop/update — Telegraf's design; the loss
  is bounded by one flush interval (10 s by default).

## Security notes

- MQTT credentials are injected via environment variables and never need to
  appear in the config file or options (the options are visible in the
  Supervisor API). Hardcoding in the file works but stores them in backups too.
- The optional ports are disabled by default; enable only what you use.
- The app runs Telegraf as the non-root `telegraf` user (upstream default)
  with `cap_net_raw`/`cap_net_bind_service` on the binary only. Protection
  mode stays on; the default AppArmor profile is used.

## Troubleshooting

- **Bad config or broker down.** The Log tab is authoritative:
  - `Error running agent: loading config file ... failed: error parsing
    data: line N: invalid TOML syntax` — your file has a syntax error
    (typical: an unescaped `"` or `\` in a literal value).
  - `Error running agent: starting input inputs.mqtt_consumer: ...` — the
    broker is unreachable or credentials are wrong (Telegraf fails the whole
    agent when an input cannot start; it does not retry at start).
  - `environment variable "X" not found` — a `${X}` reference without a
    defined variable; use `${X:-default}`.
  - The app **retries every 30 seconds** and logs
    `Telegraf exited (code N) — retrying in 30s` — fix the config/broker and
    the agent comes back **by itself** (no restart needed). While broken, the
    app reports *unhealthy* and the Log shows the error on every retry.
- **Metrics seem to flow but nothing arrives in the database.** Keep the
  seed's `outputs.file` (stdout) enabled while debugging: if the Log tab
  shows metric lines, the input side is fine and the problem is the output
  (URL, auth, network). If not, check topics (`mosquitto_sub`) and the JSON
  parser settings (strings dropped by default!).
- **Validating a config without the pipeline:** temporarily comment all
  inputs and outputs except `outputs.file` — Telegraf logs every parsed
  metric on the Log tab. (On a dev machine: `telegraf --config telegraf.conf
  --test`.)
- **Edits not picked up:** see [Editing the configuration](#editing-the-configuration)
  for the `poll` fallback.
- **"Who overwrote my config?":** every start logs the config fingerprint
  (bytes + md5). Compare with your own `md5sum` to see what the app saw.

## FAQ

**Why is my metric called `mqtt_consumer`?**
Metrics are named after the input plugin; the MQTT topic is a `topic` tag.
Set `name_override` to rename, `tag_keys`/`global_tags` to shape tags.

**Why are my string values missing?**
The `json` parser only extracts numeric/bool fields by default — declare
strings via `json_string_fields` or `tag_keys`.

**Can I split the config across files?**
Yes — every `*.conf` in `/config/telegraf.conf.d/` is merged with the main
file. Do not repeat `[[inputs.mqtt_consumer]]` blocks you already have in the
main file (you would double-subscribe).

**How do I point at VictoriaMetrics under a different name?**
Use whatever hostname reaches it: the app's internal DNS name (Info page) or
your LAN name for the published port. See the
[outputs cookbook](#outputs-cookbook).

**Does this monitor Home Assistant itself?**
No — it is a metrics agent for *your* pipelines. The HA OS metrics most
people want come from MQTT senders (e.g. zigbee2mqtt, wmbusmeters, Tasmota)
or the system inputs (container-level — see above).
