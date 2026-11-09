# Telegraf

Telegraf metrics agent for Home Assistant — collect, process and forward
metrics. Primary setup: **MQTT** data (JSON payloads) → **InfluxDB line
protocol** → **VictoriaMetrics** (or InfluxDB). Generally usable: any Telegraf
input/output, configured through one TOML file.

Full documentation:
[USER_GUIDE.md](https://github.com/tmtom/hassio-telegraf/blob/v1.40.3.1/telegraf/USER_GUIDE.md)
(the Documentation tab shows the short
[setup guide](https://github.com/tmtom/hassio-telegraf/blob/v1.40.3.1/telegraf/DOCS.md)).

Repository: https://github.com/tmtom/hassio-telegraf
