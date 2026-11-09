# Changelog

All notable changes to the Telegraf app are documented here. The `version` in
`telegraf/config.yaml` is the source of truth; the baked Telegraf version is
tracked in `telegraf/Dockerfile` (`ARG BUILD_FROM`) and, since `1.40.3.1`,
embedded in the version itself.

## 1.40.3.1 (2026-11-09)

- Version scheme is now **Telegraf-first**: `1.40.3.1` = Telegraf 1.40.3,
  app build 1. The last segment is the app build counter (bumped for
  app-only releases); a Telegraf bump resets it to 1. The old
  `0.x.y-telegraf1.40` style hid which Telegraf patch was baked in — the
  1.40.2 → 1.40.3 change was invisible in the version string. No functional
  change: still wraps Telegraf 1.40.3.
- Docs: troubleshooting note that the update tile can show "Preparing" for a
  few minutes after an update has actually finished (Home Assistant display
  lag, resolves by itself).

## 0.1.1-telegraf1.40 (2026-11-09)

- Automated bump: Telegraf 1.40.2 → 1.40.3.

## 0.1.0-telegraf1.40 (2026-11-01)

- Initial release: wraps the official Telegraf image (pinned 1.40.2).
- MQTT consumer input (JSON) seeded on first start, with the connection
  auto-wired from the Supervisor's MQTT service (manual `mqtt_*` options as
  fallback) — credentials are injected as environment variables and never
  need to live in the config file.
- One user-owned TOML config (`telegraf.conf` + `telegraf.conf.d/` drop-ins)
  in the app config folder — seeded once, never overwritten, included in
  Home Assistant backups, auto-reloaded on save (poll every 10 s —
  inotify is not delivered on the HAOS config mount, see USER_GUIDE).
- Commented output examples with connection details (VictoriaMetrics,
  InfluxDB 1.x/2.x, prometheus_client, MQTT), stdout placeholder output for
  proof-of-life.
- Health monitoring (3 s healthcheck — drives the UI state chip), pre-built
  multi-arch images (amd64, aarch64).
- Resilience: a fatal agent error (bad config, broker down) is retried every
  30 s — fix the config and the agent self-heals without a manual restart.
