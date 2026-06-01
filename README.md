<p align="center">
  <img src="docs/assets/datainteg-chromium-fleet-logo.svg" alt="Datainteg Chromium Fleet" width="200" />
</p>

<h1 align="center">Chromium Fleet</h1>

<p align="center">
  Open-source infrastructure for persistent, remotely accessible Chromium workspaces on your own VM.
</p>

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-0ea5e9?style=for-the-badge" />
  <img alt="Platform" src="https://img.shields.io/badge/platform-Linux-22c55e?style=for-the-badge" />
  <img alt="Stack" src="https://img.shields.io/badge/stack-Docker%20%7C%20Nginx-f97316?style=for-the-badge" />
  <img alt="API" src="https://img.shields.io/badge/api-REST-14b8a6?style=for-the-badge" />
</p>

## Architecture

```text
┌─────────────────────────── Linux VM ─────────────────────────────────┐
│                                                                        │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │  Nginx (host-based — recommended)                               │  │
│  │   • Basic auth (htpasswd, chmod 640 root:www-data)              │  │
│  │   • Reverse proxy to Chrome containers (WebSocket)              │  │
│  │   • /api/* proxy to Node.js API (:8787, localhost only)         │  │
│  │   • Optional HTTPS via Let's Encrypt / certbot                  │  │
│  └──────────┬──────────────────────────────────┬───────────────────┘  │
│             │                                  │                       │
│    ┌────────┴───────┐  ┌────────────┐  ┌──────┴─────────────────┐    │
│    │ seller1-chrome │  │ seller2..  │  │ fleet-api (Docker)      │    │
│    │ Docker :3000   │  │ Docker :.. │  │ :8787 (127.0.0.1 only)  │    │
│    │ profile ───────┤  │ profile ───┤  │ Mounts:                 │    │
│    │ (bind-mount)   │  │ (bind-mount│  │  /var/run/docker.sock   │    │
│    │ proxy.env      │  │ proxy.env  │  │  /opt  (seller dirs)    │    │
│    └────────────────┘  └────────────┘  │  /fleet (repo scripts)  │    │
│                                         └────────────────────────┘    │
│                                                                        │
│  /opt/<seller>-browser/                                               │
│    profile/    ← session data (cookies, logins, tabs, extensions)     │
│    proxy.env   ← proxy credentials (chmod 600, never in YAML)        │
│    proxy/      ← proxies.conf, active.conf                           │
│    backups/    ← daily profile tar.gz (keeps last 3)                  │
│    *.sh        ← start, stop, restart, recreate, update, status       │
└────────────────────────────────────────────────────────────────────────┘
```

**Key design points:**
- **Nginx runs on the host** — required for certbot SSL and WebSocket compatibility.
- **API runs in Docker** (recommended) via `docker-compose.fleet.yml`, or via systemd.
- **Proxy is optional** — no-proxy, single-proxy, and multi-proxy modes all work.
- **Session persistence** — `./profile` bind-mount keeps Chrome logged in across VM stop/start.

## Why This Is Useful
- Run full Chromium browser workspaces in the cloud with persistent login sessions.
- Open from anywhere through your domain with optional HTTPS and basic auth.
- Install Chrome extensions once and keep them across restart/redeploy cycles.
- Scale to many isolated browser instances on one VM.
- Integrate dashboards, admin panels, or frontend apps using the REST API.

## Not Seller-Only
`chromium-fleet` is generic and open source.  
The `--seller` flag is only an instance ID (`qa-team-1`, `automation-us`, `support-browser-2`, etc.).

## Easy Chrome Setup
1. Run the installer.
2. Open your subdomain in a browser.
3. Log into your target website and install required extensions.
4. Restart VM/container whenever needed. Browser profile remains intact.

## Quick Start

### No Proxy
```bash
curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/install.sh \
  | bash -s -- \
      --seller qa-team-1 \
      --port 3000 \
      --user admin \
      --pass "StrongPass!" \
      --subdomain chrome1.yourdomain.com
```

### With One Proxy
```bash
curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/install.sh \
  | bash -s -- \
      --seller qa-team-2 \
      --port 3001 \
      --user admin \
      --pass "StrongPass!" \
      --subdomain chrome2.yourdomain.com \
      --proxy "1.2.3.4:8080:proxyuser:proxypass"
```

### With Multi-Proxy Auto Failover
```bash
curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/install.sh \
  | bash -s -- \
      --seller qa-team-3 \
      --port 3002 \
      --user admin \
      --pass "StrongPass!" \
      --subdomain chrome3.yourdomain.com \
      --proxy "1.2.3.4:8080:user1:pass1" \
      --proxy "5.6.7.8:8080:user2:pass2"
```

## Parameters
| Flag | Default | Required | Description |
|---|---|---|---|
| `--seller` | `seller1` | No | Instance name/ID |
| `--port` | `3000` | No | Host port for Chromium |
| `--user` | `admin` | No | Nginx basic auth username |
| `--pass` | - | Yes | Nginx basic auth password |
| `--subdomain` | - | Yes | Full domain, e.g. `chrome1.example.com` |
| `--tz` | `Asia/Kolkata` | No | Container timezone |
| `--mem` | `2g` | No | Docker memory limit (4GB-VM optimized default) |
| `--cpu` | `1.0` | No | Docker CPU limit |
| `--shm` | `1gb` | No | `/dev/shm` size |
| `--swap` | `2G` | No | Swap file size |
| `--api-port` | `8787` | No | Local API upstream port for Nginx `/api` proxy |
| `--proxy` | - | No | `host:port:user:pass` (repeatable) |

## API For Frontend Integration
API docs: [`api/README.md`](./api/README.md)
Service installer (Docker or systemd): `api/install-service.sh`

Key endpoints:
- `POST /api/v1/auth/login` — username/password → JWT token pair
- `POST /api/v1/auth/refresh` — rotate refresh token
- `POST /api/v1/auth/logout` — revoke session
- `GET /api/v1/monitor/overview` — VM + fleet health (frontend dashboard)
- `GET /api/v1/monitor/stream` — live SSE status stream
- `GET /api/v1/sellers` — list all sellers with Docker state
- `GET /api/v1/sellers/:seller/proxies` — proxy pool (passwords masked)
- `POST /api/v1/sellers/:seller/proxies` — add proxy to pool
- `DELETE /api/v1/sellers/:seller/proxies/:index` — remove proxy
- `POST /api/v1/sellers/:seller/actions/proxy-rotate` — rotate active proxy
- `POST /api/v1/sellers/:seller/actions/:action` — start/stop/restart/recreate/update
- `POST /api/v1/sellers/:seller/resume` — start if stopped
- `POST /api/v1/sellers/resume-all`
- `DELETE /api/v1/sellers/:seller`
- `GET /api/v1/sellers/:seller/events` — crash/recovery event log
- `POST /api/v1/sellers/actions/:action` — fleet-wide bulk action
- `GET /api/v1/sellers/:seller/extensions` — list installed extensions
- `GET /api/v1/sellers/:seller/backups` — list profile backups
- `POST /api/v1/sellers/:seller/restore/:filename` — restore session from backup

API calls require JWT auth (`Bearer <token>`) from `/api/v1/auth/login`.
If accessed through Nginx, also requires Nginx basic auth.

## Docker API Deployment
The API runs as a Docker container for easy management:

```bash
cp api/.env.example api/.env  # fill in secrets
sudo bash api/install-service.sh --docker
```

Logs: `docker compose -f docker-compose.fleet.yml logs -f api`

### Install and Remove are disabled by default

`ALLOW_INSTALL` and `ALLOW_UNINSTALL` default to `false`. API-based provisioning is opt-in.

**Recommended workflow:**
- Provision sellers by running `install.sh` directly on the host VM.
- Remove sellers by running `uninstall.sh` directly on the host VM.
- In Docker API mode, `POST /api/v1/sellers` returns `501` regardless of the flag (`install.sh` cannot run inside a container).
- Set `ALLOW_INSTALL=true` only in trusted host/systemd deployments where API-based provisioning is intentionally needed.

For production, keep defaults in `api/.env`:
```env
ALLOW_INSTALL=false
ALLOW_UNINSTALL=false
ALLOW_DESTRUCTIVE_ACTIONS=false
```

Lifecycle actions (`start`, `stop`, `restart`, `status`, `proxy-rotate`) are never affected by these flags.

## Security Warning — Docker Socket

The API container mounts `/var/run/docker.sock` (see `docker-compose.fleet.yml`). This grants the API container **host-level Docker control**, equivalent to root access on the VM.

**Required mitigations before production:**
- Keep the API private: always behind Nginx basic auth and API JWT auth.
- Do not expose port `8787` directly to the internet — access only through Nginx.
- Set `ALLOW_INSTALL=false` and `ALLOW_UNINSTALL=false` in `api/.env` once sellers are provisioned.
- Restrict VM SSH access and Docker group membership.
- Consider firewall rules: block port `8787` from external access.

## Crash Alerts via Webhook

Set `WEBHOOK_URL` in `api/.env` to get notified when a Chrome instance crashes or recovers (Discord, Slack, or any HTTP endpoint).

```env
WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN
```

## Repository Structure
```text
chromium-fleet/
|- install.sh
|- setup.sh
|- nginx.sh
|- proxy.sh
|- uninstall.sh
|- list-sellers.sh
|- update-all.sh
|- health-all.sh
`- api/
```

## Cron Jobs and VM Schedule

Each installed seller automatically creates cron jobs (visible via `crontab -l -u root`):

| Schedule | Job |
|---|---|
| `@reboot` | Resume Chrome container 90s after VM boot |
| `*/5 * * * *` | Container health check |
| `30 1 UTC daily` | Log cleanup |
| `45 1 UTC daily` | `docker system prune -f` |
| `02 2 UTC daily` | Profile backup (tar.gz, keeps last 3) |
| `02 2 UTC Sun` | Weekly image update + recreate |

To edit cron: `crontab -e -u root`

## Requirements
- Debian 12 or Ubuntu 22.04/24.04 (64-bit)
- Root access
- Open firewall ports: `80`, `443`, and your Chromium ports
- DNS A record pointing subdomain to VM IP

## Support
- Author: `Datainteg`
- Support Email: `support@datainteg.io`

## License
MIT
