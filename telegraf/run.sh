#!/usr/bin/env bash
#
# /run.sh — Home Assistant app entrypoint wrapper for Telegraf.
#
# Responsibilities (in order):
#   1. Read the Supervisor options from /data/options.json (jq).
#   2. On first start, seed /config/telegraf.conf from the template (never
#      overwrite) and create /config/telegraf.conf.d/; log the config
#      fingerprint (bytes + md5) for "who overwrote my config?" forensics.
#   3. MQTT auto-wiring: GET http://supervisor/services/mqtt (mqtt:want) ->
#      export TELEGRAF_MQTT_{HOST,PORT,USERNAME,PASSWORD} (raw values — env
#      substitution happens at the TOML value level), with the manual mqtt_*
#      options as fallback. ALWAYS export all four (empty is fine) — strict
#      env handling since Telegraf 1.38 makes an undefined ${VAR} a startup
#      error.
#   4. Startup summary: telegraf version, config path + fingerprint, MQTT
#      target (host:port, user or 'anonymous', source: api/manual/none).
#   5. exec /entrypoint.sh "$@" (upstream: setcap, drop to 'telegraf', exec).
#
set -eu

OPTIONS_FILE="${OPTIONS_FILE:-/data/options.json}"
CONFIG_DIR="${CONFIG_DIR:-/config}"
CONFIG_FILE="${CONFIG_DIR}/telegraf.conf"
CONFIG_DROPIN_DIR="${CONFIG_DIR}/telegraf.conf.d"
SEED_FILE="${SEED_FILE:-/usr/src/templates/telegraf.conf.seed}"

log() { printf '[run.sh] %s\n' "$*"; }
warn() { printf '[run.sh] WARNING: %s\n' "$*" >&2; }

# opt <key> <default> — print the option value; booleans print as true/false.
opt() {
  jq -r --arg key "$1" --arg default "$2" '
    if has($key) and .[$key] != null
    then (if (.[$key] | type) == "boolean" then (if .[$key] then "true" else "false" end)
          else (.[$key] | tostring) end)
    else $default end
  ' "${OPTIONS_FILE}" 2>/dev/null || printf '%s' "$2"
}

#-----------------------------------------------------------------------------
# 1. Options.
#-----------------------------------------------------------------------------
MQTT_AUTOMATIC="$(opt mqtt_automatic true)"

#-----------------------------------------------------------------------------
# 2. First-start seeding + config fingerprint.
#-----------------------------------------------------------------------------
mkdir -p "${CONFIG_DROPIN_DIR}"

if [ -f "${CONFIG_FILE}" ]; then
  log "Config present: ${CONFIG_FILE} ($(wc -c < "${CONFIG_FILE}" | tr -d ' ') bytes, md5 $(md5sum "${CONFIG_FILE}" | cut -c1-8))"
else
  log "No config found: seeding ${CONFIG_FILE} from the template (this happens once; the file is yours afterwards)"
  cp "${SEED_FILE}" "${CONFIG_FILE}"
  log "Config seeded: ${CONFIG_FILE} ($(wc -c < "${CONFIG_FILE}" | tr -d ' ') bytes, md5 $(md5sum "${CONFIG_FILE}" | cut -c1-8))"
fi

# The upstream entrypoint drops to the non-root 'telegraf' user: give it the
# config folder so outputs (e.g. outputs.file) can write there. Root-capable
# editors (Samba, File editor, VS Code) keep working regardless of ownership.
chown -R telegraf:telegraf "${CONFIG_DIR}"

#-----------------------------------------------------------------------------
# 3. MQTT connection: Supervisor services API first (mqtt:want), then the
#    manual mqtt_* options. TOML-escaped, always all four exported.
#-----------------------------------------------------------------------------
MQTT_HOST=""
MQTT_PORT=""
MQTT_USER=""
MQTT_PASS=""
MQTT_SOURCE="none"

if [ "${MQTT_AUTOMATIC}" = "true" ] && [ -n "${SUPERVISOR_TOKEN:-}" ]; then
  if curl -fsS -m 10 -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
       "http://supervisor/services/mqtt" -o /tmp/mqtt-service.json 2>/dev/null; then
    MQTT_HOST="$(jq -r '(.data // .).host // empty' /tmp/mqtt-service.json 2>/dev/null || true)"
    MQTT_PORT="$(jq -r '(.data // .).port // empty' /tmp/mqtt-service.json 2>/dev/null || true)"
    MQTT_USER="$(jq -r '(.data // .).username // empty' /tmp/mqtt-service.json 2>/dev/null || true)"
    MQTT_PASS="$(jq -r '(.data // .).password // empty' /tmp/mqtt-service.json 2>/dev/null || true)"
    if [ -n "${MQTT_HOST}" ]; then
      MQTT_SOURCE="api"
      log "MQTT broker discovered via Supervisor services API (${MQTT_HOST}:${MQTT_PORT:-1883})"
    else
      log "Supervisor MQTT service returned no usable host — using manual mqtt_* options"
    fi
  else
    log "Supervisor MQTT service unavailable — using manual mqtt_* options"
  fi
elif [ "${MQTT_AUTOMATIC}" = "true" ]; then
  log "MQTT: automatic discovery requested but no Supervisor token — using manual mqtt_* options"
fi

# Manual options fill in whatever is still missing (complete fallback when
# mqtt_automatic is false or the API is unreachable).
if [ -z "${MQTT_HOST}" ]; then
  MQTT_HOST="$(opt mqtt_host '')"
  MQTT_PORT="$(opt mqtt_port 1883)"
  MQTT_USER="$(opt mqtt_user '')"
  MQTT_PASS="$(opt mqtt_password '')"
  [ -n "${MQTT_HOST}" ] && MQTT_SOURCE="manual"
fi

# ALWAYS export all four (empty ok) — Telegraf >= 1.38 fails on undefined
# ${VAR}. Defaults live in the seed's ${VAR:-default} forms.
# NOTE: values are exported RAW — Telegraf substitutes env vars at the TOML
# value level (verified with passwords containing " and \; TOML-escaping them
# produces a wrong literal password and breaks MQTT auth).
export TELEGRAF_MQTT_HOST="${MQTT_HOST:-core-mosquitto}"
export TELEGRAF_MQTT_PORT="${MQTT_PORT:-1883}"
export TELEGRAF_MQTT_USERNAME="${MQTT_USER:-}"
export TELEGRAF_MQTT_PASSWORD="${MQTT_PASS:-}"

#-----------------------------------------------------------------------------
# 4. Startup summary.
#-----------------------------------------------------------------------------
log "Telegraf $(telegraf --version 2>/dev/null | awk '{print $2}' || echo 'version unknown')"
if [ -n "${MQTT_HOST}" ]; then
  if [ -n "${MQTT_USER}" ]; then
    log "MQTT target: ${MQTT_HOST}:${MQTT_PORT:-1883} (user: ${MQTT_USER}, source: ${MQTT_SOURCE})"
  else
    log "MQTT target: ${MQTT_HOST}:${MQTT_PORT:-1883} (anonymous, source: ${MQTT_SOURCE})"
  fi
else
  warn "No MQTT broker configured (no Supervisor service, mqtt_host empty)."
  warn "The seed's mqtt_consumer input will fail to connect — set the mqtt_* options or install an MQTT broker app (e.g. Mosquitto)."
fi
log "Config: ${CONFIG_FILE} + drop-ins in ${CONFIG_DROPIN_DIR}/ (edit -> auto-reload via --watch-config)"
log "Handing over to Telegraf (/entrypoint.sh)"

#-----------------------------------------------------------------------------
# 5. Upstream entrypoint: setcap, drop to the 'telegraf' user, exec telegraf.
#-----------------------------------------------------------------------------
exec /entrypoint.sh "$@"
