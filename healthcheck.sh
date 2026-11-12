#!/bin/sh
# Healthy when every forwarded port accepts a connection and, with HEALTH_READ_BANNER=true, the target
# behind it answers with at least one byte (MySQL, SSH and SMTP servers speak first). The banner check
# goes through a new SSH channel each time, so it also catches "channel open failure" on a live connection.
set -u
for f in $(echo "$FORWARDS" | tr ',' ' '); do
  port=${f%%:*}
  if [ "${HEALTH_READ_BANNER:-false}" = "true" ]; then
    n=$(timeout "${HEALTH_TIMEOUT:-5}" socat -u -T3 "TCP:127.0.0.1:$port" STDOUT 2>/dev/null | head -c 1 | wc -c)
    [ "$n" -ge 1 ] || { echo "port $port: no banner"; exit 1; }
  else
    timeout "${HEALTH_TIMEOUT:-5}" socat -u /dev/null "TCP:127.0.0.1:$port" 2>/dev/null || { echo "port $port: closed"; exit 1; }
  fi
done
echo ok
