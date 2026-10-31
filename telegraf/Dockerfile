ARG BUILD_FROM=telegraf:1.40.2
FROM ${BUILD_FROM}

# jq: parse /data/options.json and the Supervisor services payload in run.sh.
# (The base image has curl, wget, git, procps and tini already.)
RUN apt-get update \
 && apt-get install -y --no-install-recommends jq \
 && rm -rf /var/lib/apt/lists/*

# Seed configuration template (see rootfs/usr/src/templates/telegraf.conf.seed).
COPY rootfs/ /
COPY run.sh /run.sh
RUN chmod +x /run.sh

# Health = the agent process is alive. Short interval so the Supervisor's
# "starting" -> "running" UI flip is quick (procps' pgrep is in the base image).
HEALTHCHECK --interval=5s --timeout=10s --start-period=30s --retries=3 \
  CMD pgrep -x telegraf >/dev/null || exit 1

# Keep the upstream chain: tini (PID 1) -> run.sh (seed + MQTT env) ->
# /entrypoint.sh (setcap + drop to the telegraf user) -> telegraf "$@".
ENTRYPOINT ["/usr/bin/tini", "--", "/run.sh"]
CMD ["--config", "/config/telegraf.conf", \
     "--config-directory", "/config/telegraf.conf.d", \
     "--watch-config=notify", "--watch-debounce-interval=5s"]
