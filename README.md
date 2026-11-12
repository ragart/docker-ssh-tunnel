# ssh-tunnel — generic SSH tunnel sidecar

A small container that keeps an SSH tunnel open (autossh) and exposes the forwarded ports to the other
containers of its compose network. n8n then uses a plain MySQL credential (host = the service name,
SSH off) instead of n8n's built-in SSH tunnel.

## Setup (one tunnel)

1. Use the image `ragart/ssh-tunnel:1.0.0` (build and publish: see the end of this file).
2. Create the key folder, e.g. `./tunnel-server1-ssh/`, with:
   - `id_ed25519`: a key dedicated to the tunnel. Permissions don't matter; the container copies it to a private path.
   - `known_hosts`: the server's host key. Host keys are always checked. Get it with
     `ssh-keyscan -p 22 server1.example.com > known_hosts`, then compare its fingerprint
     (`ssh-keygen -lf known_hosts`) with one you trust.
3. Copy `tunnel.env.example` to `tunnel-server1.env` and set `SSH_HOST`, `SSH_USER` and `FORWARDS`.
4. Add the service from `compose.example.yml`, then run `docker compose up -d tunnel-server1`.
5. Check it: `docker compose ps tunnel-server1` should report `healthy`, and `docker compose logs tunnel-server1` shows the forwards.
6. In n8n, set the MySQL credential's host to `tunnel-server1` and its port to the listen port, with SSH tunnel off.

More tunnels: one more service with its own `.env` and key folder (same image).

## Settings

| Variable | Default | |
|---|---|---|
| `SSH_HOST`, `SSH_USER` | required | SSH server and account |
| `FORWARDS` | required | `listen_port:target_host:target_port`, comma-separated. `target_host` is resolved by the SSH server (`127.0.0.1` = the server itself). |
| `SSH_PORT` | 22 | |
| `SSH_KEY_FILE`, `SSH_KNOWN_HOSTS_FILE` | `/ssh/id_ed25519`, `/ssh/known_hosts` | |
| `HEALTH_READ_BANNER` | false | `true` when every target speaks first (MySQL does): each check opens a new SSH channel and reads the greeting. |
| `SSH_ALIVE_INTERVAL`, `SSH_ALIVE_COUNT` | 15, 3 | A dead connection is noticed in about 45 s; autossh reconnects. |
| `WATCHDOG_INTERVAL`, `WATCHDOG_FAILURES` | 30, 3 | Restarts ssh after N failed checks in a row. This catches channels refused on a live connection, which keepalives don't detect. `0` disables it. |
| `SSH_EXTRA_OPTS` | | Extra `ssh` options |

## Behaviour

- ssh runs as an unprivileged user. Bad settings stop the container with a clear message, and a changed host key refuses the connection.
- Ports are not published to the host unless you add `ports:`. Don't add it for databases.
- Hardening on the SSH server, if you can edit `authorized_keys`: restrict the key to the forward, e.g.
  `restrict,port-forwarding,permitopen="127.0.0.1:3306" ssh-ed25519 AAAA... n8n-tunnel`.
- Tested 2026-11-12 against a throwaway sshd and a fake MySQL:
  - forwards work from another container;
  - with the target down while ssh stayed connected, the watchdog restarted ssh and the tunnel recovered when the target came back;
  - an sshd restart was reconnected by autossh;
  - a bad forward, a missing key and a wrong host key all fail clearly.

## Build and publish

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ragart/ssh-tunnel:1.0.0 -t ragart/ssh-tunnel:latest --push .
```
Bump `org.opencontainers.image.version` in the Dockerfile and the tag together. Compose files should
reference the exact version, never `latest`.
