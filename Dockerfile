# Generic SSH tunnel sidecar: forwards ports from this container to targets reachable from an SSH server.
# Everything is configured with environment variables (see tunnel.env.example).
FROM alpine:3.20
LABEL org.opencontainers.image.title="ssh-tunnel" \
      org.opencontainers.image.description="Generic SSH tunnel sidecar (autossh + channel watchdog), configured by environment variables" \
      org.opencontainers.image.version="1.0.0"
RUN apk add --no-cache openssh-client autossh socat su-exec \
 && adduser -D -H -s /sbin/nologin tunnel
COPY entrypoint.sh healthcheck.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
