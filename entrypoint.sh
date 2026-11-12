#!/bin/sh
# Builds the autossh command from the environment and keeps it running.
set -eu
die() { echo "ssh-tunnel: $*" >&2; exit 1; }

: "${SSH_HOST:?SSH_HOST is required}"
: "${SSH_USER:?SSH_USER is required}"
: "${FORWARDS:?FORWARDS is required (listen_port:target_host:target_port[,...])}"
SSH_PORT=${SSH_PORT:-22}
SSH_KEY_FILE=${SSH_KEY_FILE:-/ssh/id_ed25519}
SSH_KNOWN_HOSTS_FILE=${SSH_KNOWN_HOSTS_FILE:-/ssh/known_hosts}
SSH_ALIVE_INTERVAL=${SSH_ALIVE_INTERVAL:-15}
SSH_ALIVE_COUNT=${SSH_ALIVE_COUNT:-3}
WATCHDOG_INTERVAL=${WATCHDOG_INTERVAL:-30}
WATCHDOG_FAILURES=${WATCHDOG_FAILURES:-3}

[ -r "$SSH_KEY_FILE" ] || die "key file $SSH_KEY_FILE not readable"
[ -r "$SSH_KNOWN_HOSTS_FILE" ] || die "known_hosts file $SSH_KNOWN_HOSTS_FILE not readable (host keys are always checked)"

# ssh refuses keys readable by others, and bind mounts keep the host's permissions: use private copies.
run=/run/tunnel; mkdir -p "$run"
cp "$SSH_KEY_FILE" "$run/key"; cp "$SSH_KNOWN_HOSTS_FILE" "$run/known_hosts"
chown -R tunnel:tunnel "$run"; chmod 0700 "$run"; chmod 0600 "$run/key" "$run/known_hosts"

set --
for f in $(echo "$FORWARDS" | tr ',' ' '); do
  echo "$f" | grep -Eq '^[0-9]+:[^:]+:[0-9]+$' || die "bad forward '$f' (expected listen_port:target_host:target_port)"
  set -- "$@" -L "0.0.0.0:$f"
done

# Watchdog: if the forwards stop working while ssh is still connected (keepalives pass but new channels
# are refused), kill ssh after WATCHDOG_FAILURES consecutive failed checks; autossh then reconnects.
if [ "$WATCHDOG_INTERVAL" -gt 0 ]; then
  (
    sleep 20; fails=0
    while sleep "$WATCHDOG_INTERVAL"; do
      if /usr/local/bin/healthcheck.sh >/dev/null 2>&1; then fails=0; else
        fails=$((fails + 1)); echo "ssh-tunnel: check failed ($fails/$WATCHDOG_FAILURES)" >&2
        if [ "$fails" -ge "$WATCHDOG_FAILURES" ]; then echo "ssh-tunnel: restarting ssh" >&2; pkill -x ssh || true; fails=0; fi
      fi
    done
  ) &
fi

echo "ssh-tunnel: ${SSH_USER}@${SSH_HOST}:${SSH_PORT} forwarding ${FORWARDS}"
export AUTOSSH_GATETIME=0 AUTOSSH_POLL=${AUTOSSH_POLL:-30}
# shellcheck disable=SC2086
exec su-exec tunnel autossh -M 0 -N -T \
  -p "$SSH_PORT" -i "$run/key" \
  -o IdentitiesOnly=yes -o BatchMode=yes \
  -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$run/known_hosts" \
  -o ServerAliveInterval="$SSH_ALIVE_INTERVAL" -o ServerAliveCountMax="$SSH_ALIVE_COUNT" \
  -o ExitOnForwardFailure=yes -o ConnectTimeout=15 \
  ${SSH_EXTRA_OPTS:-} "$@" "${SSH_USER}@${SSH_HOST}"
