# Deploying the Porch relay

The relay is one static Go binary, Redis 7, and Caddy for TLS. Nothing else.
The BUILD-SPEC target is a small Hetzner Finland VM; any Linux box with a
public IP and a domain works identically. **Local `docker-compose up`
reproduces prod exactly** — same images, same flags, same Caddyfile.

The privacy posture you are deploying (worth knowing before you type):
the relay stores only opaque, TTL-expiring ciphertext keyed by
random-looking capabilities; it holds no accounts, no member lists, no
plaintext, and writes no logs — structurally (the serving packages contain
no logging calls; CI greps for them). What a compromised box CAN see is
live traffic metadata: which IPs poll which channel ids. That residual is
accepted and documented; do not promise users otherwise.

## Option A — compose (recommended)

```sh
# on the server, as any user in the docker/podman group
git clone <this repo> porch && cd porch
PORCH_DOMAIN=relay.example.org docker compose up -d --build
curl -fsS https://relay.example.org/v1/healthz   # → 200
```

- `PORCH_DOMAIN` unset ⇒ Caddy serves `localhost` with a self-signed cert
  (local smoke). Set it to your DNS name for real Let's Encrypt TLS.
- Rootless podman note: the compose file publishes 80/443, which rootless
  setups can't bind by default — override the ports or
  `sysctl net.ipv4.ip_unprivileged_port_start=80`.
- Redis persists to the `redis-data` volume with AOF everysec. Total loss
  degrades gracefully (undelivered mail + live statuses vanish; groups
  self-heal via REKEY_REQUEST) — do NOT build a backup pipeline that copies
  user ciphertext around; the spec deliberately avoids one.

## Option B — bare metal (systemd)

1. Build and install the binary (on the server or cross-compiled):

   ```sh
   cd relay && CGO_ENABLED=0 go build -trimpath \
     -ldflags "-X main.version=$(git describe --tags --always)" \
     -o /usr/local/bin/relayd ./cmd/relayd
   relayd --version    # confirms what you installed
   ```

2. Install Redis 7 (`apt install redis-server`), set in `redis.conf`:

   ```
   appendonly yes
   appendfsync everysec
   bind 127.0.0.1
   ```

3. Install the unit and start:

   ```sh
   cp ops/porchd.service /etc/systemd/system/
   systemctl daemon-reload && systemctl enable --now porchd
   curl -fsS http://127.0.0.1:8080/v1/healthz   # → 200
   ```

4. Install Caddy (distro package) and point it at the relay with this
   repo's `ops/Caddyfile` (edit `reverse_proxy relayd:8080` →
   `reverse_proxy 127.0.0.1:8080`, set your domain). The Caddyfile is part
   of the audited surface: access-log output is explicitly `discard`.

## Flags

| Flag | Meaning |
|---|---|
| `-addr` | listen address (`127.0.0.1:8080` behind Caddy; never expose raw) |
| `-store` | `memory` (dev/tests) or `redis` (prod) |
| `-redis-url` | `redis://host:port` when `-store=redis` |
| `-trust-forwarded` | rate-limit by the **last** `X-Forwarded-For` hop (the one your terminator appended) — ONLY behind exactly one trusted TLS terminator you control; earlier hops are client-forgeable |
| `-version` | print the version and exit |
| `-h`, `--help` | print usage to stdout and exit |

relayd takes no positional arguments: a bare word (e.g. `relayd redis`
instead of `relayd -store=redis`) is refused rather than silently ignoring
the flags after it.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | clean shutdown on SIGTERM/SIGINT, or `-h` / `--version` |
| 1 | startup failure: Redis unreachable or port in use (check the dependency), or an unknown `-store` value (check the command line) |
| 2 | bad invocation: unknown flag or stray positional argument — fix the command line, restarting will not help |

## What to check after any deploy

- `curl https://$DOMAIN/v1/healthz` → 200.
- `docker logs relayd` (or `journalctl -u porchd`) is **empty**. If anything
  request-shaped ever appears there, that is a sev-1 privacy bug, not noise.
- Rate limits are per-IP and in-memory: a restart resets buckets. Fine for
  one instance; this relay is not designed to scale horizontally (and at
  presence timescales, one small VM serves thousands of households).

## Updating

The relay is stateless apart from Redis: `docker compose up -d --build`
(or replace the binary + `systemctl restart porchd`). In-flight requests
get 10 s of graceful shutdown. Clients treat any outage as ordinary
offline: statuses queue in outboxes, feeds render last-known with an
honest "as of N min ago" line.
