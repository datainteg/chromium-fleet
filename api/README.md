<p align="center">
  <img src="../docs/assets/datainteg-chromium-fleet-logo.svg" alt="Datainteg Chromium Fleet" width="220" />
</p>

# Chromium Fleet API

REST control plane for `chromium-fleet`, built for frontend integration and operations dashboards.

<p>
  <img alt="Runtime" src="https://img.shields.io/badge/runtime-Node%2018%2B-16a34a?style=flat-square" />
  <img alt="Auth" src="https://img.shields.io/badge/auth-JWT%20%2B%20Refresh-0284c7?style=flat-square" />
  <img alt="API" src="https://img.shields.io/badge/type-REST-f97316?style=flat-square" />
</p>

## Install
```bash
cd api
cp .env.example .env   # fill in secrets
```

Set at least:
- `AUTH_USERNAME`, `AUTH_PASSWORD`
- `JWT_SECRET`, `REFRESH_TOKEN_SECRET`
- `CORS_ORIGINS` for your frontend

## Run — Docker (recommended)

```bash
# From repo root:
sudo bash api/install-service.sh --docker
```

This builds a Docker image, starts the API container, and auto-restarts on boot/crash.

Manage:
```bash
docker compose -f docker-compose.fleet.yml logs -f api
docker compose -f docker-compose.fleet.yml restart api
docker compose -f docker-compose.fleet.yml down
```

The API container mounts `/var/run/docker.sock` (Docker control), `/opt` (seller dirs), and the repo root as `/fleet` (scripts).

## Run — systemd (legacy)

```bash
cd api
npm install
sudo bash install-service.sh
```

## Run — development

```bash
cd api
npm install
npm run dev
```

Default: `http://127.0.0.1:8787` (bind address from HOST env, default 127.0.0.1)

## Production .env Recommendations

Copy `.env.example` to `.env` and set at minimum:

| Variable | Required | Recommendation |
|---|---|---|
| `AUTH_USERNAME` | Yes | Any non-default username |
| `AUTH_PASSWORD` | Yes | 16+ chars, mixed case/numbers/symbols |
| `JWT_SECRET` | Yes | `openssl rand -base64 48` (unique per deploy) |
| `REFRESH_TOKEN_SECRET` | Yes | `openssl rand -base64 48` (different from JWT_SECRET) |
| `CORS_ORIGINS` | Yes | Your frontend domain(s), not localhost |
| `HOST` | Yes | Keep `127.0.0.1` — never `0.0.0.0` in production |
| `ALLOW_INSTALL` | Yes | Set `false` once sellers are provisioned |
| `ALLOW_UNINSTALL` | Yes | Set `false` once sellers are provisioned |
| `SESSIONS_FILE` | No | Default `/opt/chromium-fleet-sessions.json` |
| `WEBHOOK_URL` | No | Discord/Slack webhook for crash alerts |

Rate limiting (all configurable via `.env`):

| Variable | Default | Purpose |
|---|---|---|
| `RATE_LIMIT_AUTH_WINDOW_MS` | `900000` (15 min) | Auth endpoint window |
| `RATE_LIMIT_AUTH_MAX` | `20` | Max auth requests per window per IP |
| `RATE_LIMIT_API_WINDOW_MS` | `60000` (1 min) | Global API window |
| `RATE_LIMIT_API_MAX` | `200` | Max API requests per window per IP |

SSE stream protection:

| Variable | Default | Purpose |
|---|---|---|
| `SSE_MAX_CONNECTIONS_PER_IP` | `3` | Max concurrent SSE streams per IP |
| `SSE_MAX_EVENT_BYTES` | `2097152` (2MB) | Max single event payload |
| `SSE_MAX_BYTES_PER_HOUR` | `104857600` (100MB) | Per-connection hourly quota |

## Auth Flow (Recommended)
1. Login with username/password:
```http
POST /api/v1/auth/login
Content-Type: application/json
```

```json
{
  "username": "admin",
  "password": "your-password"
}
```

2. Use access token:
```http
Authorization: Bearer <accessToken>
```

3. Refresh when access token expires:
```http
POST /api/v1/auth/refresh
Content-Type: application/json
```

```json
{
  "refreshToken": "<refreshToken>"
}
```

4. Logout/revoke:
```http
POST /api/v1/auth/logout
Content-Type: application/json
```

```json
{
  "refreshToken": "<refreshToken>"
}
```

## Optional Legacy Auth
- Enable `ALLOW_API_KEY_AUTH=true`
- Pass `x-api-key: <API_KEY>`

`/healthz` is public. `/api/*` requires API auth unless `DISABLE_AUTH=true`.
If you call API through Nginx, default setup also enforces Nginx basic auth.

## Core Endpoints

### Health / Meta
- `GET /healthz` — public health check
- `GET /api/v1/meta` — server capabilities, auth mode, available actions

### Auth
- `POST /api/v1/auth/login` — username/password → token pair
- `POST /api/v1/auth/refresh` — rotate refresh token → new pair
- `POST /api/v1/auth/logout` — revoke refresh token

### Monitoring
- `GET /api/v1/monitor/overview` — VM + fleet health (cached)
- `GET /api/v1/monitor/vm` — CPU, RAM, disk, swap
- `GET /api/v1/monitor/fleet` — all sellers + Docker container stats
- `GET /api/v1/monitor/cluster` — alias of fleet
- `GET /api/v1/monitor/stream?intervalMs=15000` — SSE live stream
- `GET /api/v1/status/live` — alias of monitor stream

### Seller Management
- `GET /api/v1/sellers` — list all sellers with Docker state
- `GET /api/v1/sellers/:seller` — single seller detail
- `POST /api/v1/sellers` — create seller (runs install.sh)
- `POST /api/v1/sellers/:seller/actions/:action` — lifecycle actions
- `POST /api/v1/sellers/:seller/resume` — start if stopped
- `POST /api/v1/sellers/resume-all` — resume all stopped sellers
- `DELETE /api/v1/sellers/:seller` — remove seller

#### Seller Actions (`:action`)
`start` · `stop` · `restart` · `recreate` · `update` · `status` · `proxy-status` · `proxy-rotate`

### Proxy Pool Management
Proxy is optional. Sellers without proxies work normally — these endpoints return empty lists.

- `GET /api/v1/sellers/:seller/proxies` — list proxies (passwords masked)
- `POST /api/v1/sellers/:seller/proxies` — add proxy to pool
  ```json
  { "proxy": "1.2.3.4:8080:user:pass" }
  ```
- `DELETE /api/v1/sellers/:seller/proxies/:index` — remove proxy by index (0-based)
- `POST /api/v1/sellers/:seller/actions/proxy-rotate` — rotate to next alive proxy
- `POST /api/v1/sellers/:seller/actions/proxy-status` — live proxy health check

### Seller Health Events
Automatic crash/recovery detection — events recorded when container state changes. State watcher polls every 30 seconds.

- `GET /api/v1/sellers/:seller/events` — last 50 health events (crash, recovery, etc.)

### Fleet Bulk Actions
Run one action across all sellers simultaneously (concurrency-limited to 3 at a time).

- `POST /api/v1/sellers/actions/:action` — same actions as per-seller: `start` · `stop` · `restart` · `recreate` · `update`

### Extension Management
The `./extensions/` directory is mounted read-only into Chrome. Drop `.crx` files or unpacked extension folders there and install them once in the browser — they persist in `./profile` after that.

- `GET /api/v1/sellers/:seller/extensions` — list extensions in `./extensions/` dir
- `DELETE /api/v1/sellers/:seller/extensions/:name` — remove a `.crx` file or unpacked folder

### Profile Backup & Restore
Daily backups are created automatically (cron at 02:00 UTC). Restore replaces the current profile — container stops, profile is swapped, container restarts.

- `GET /api/v1/sellers/:seller/backups` — list available backups with file sizes
- `POST /api/v1/sellers/:seller/restore/:filename` — restore from `profile-YYYYMMDD.tar.gz`
  - Container stops gracefully (30s flush), current profile saved as `profile-pre-restore-<ts>`, backup extracted, container restarts.
  - **Destructive** — current session is replaced. Current profile is preserved as `profile-pre-restore-*` in the app dir.

### Seller Logs
- `GET /api/v1/sellers/:seller/logs?lines=100` — last N Docker container logs (max 1000)

## Frontend Dashboard Endpoint Map

Use these endpoints to build a frontend dashboard:

| Dashboard feature | Method | Endpoint |
|---|---|---|
| Login | `POST` | `/api/v1/auth/login` |
| Refresh session | `POST` | `/api/v1/auth/refresh` |
| Logout | `POST` | `/api/v1/auth/logout` |
| Server capabilities | `GET` | `/api/v1/meta` |
| **Monitoring** | | |
| VM health card (CPU/RAM/disk/swap) | `GET` | `/api/v1/monitor/vm` |
| Fleet + VM overview (cached) | `GET` | `/api/v1/monitor/overview` |
| Live dashboard stream (SSE) | `GET` | `/api/v1/monitor/stream?intervalMs=15000` |
| **Browser Instances** | | |
| List all browsers + Docker state | `GET` | `/api/v1/sellers` |
| Single browser detail | `GET` | `/api/v1/sellers/:seller` |
| Start browser | `POST` | `/api/v1/sellers/:seller/actions/start` |
| Stop browser | `POST` | `/api/v1/sellers/:seller/actions/stop` |
| Restart browser | `POST` | `/api/v1/sellers/:seller/actions/restart` |
| Full recreate (safe) | `POST` | `/api/v1/sellers/:seller/actions/recreate` |
| Update image + recreate | `POST` | `/api/v1/sellers/:seller/actions/update` |
| Container status | `POST` | `/api/v1/sellers/:seller/actions/status` |
| Resume if stopped | `POST` | `/api/v1/sellers/:seller/resume` |
| Resume all stopped | `POST` | `/api/v1/sellers/resume-all` |
| Fleet bulk action | `POST` | `/api/v1/sellers/actions/:action` |
| Container logs | `GET` | `/api/v1/sellers/:seller/logs?lines=100` |
| Health event log | `GET` | `/api/v1/sellers/:seller/events` |
| **Proxy Management** | | |
| List proxy pool (passwords masked) | `GET` | `/api/v1/sellers/:seller/proxies` |
| Live proxy health test | `GET` | `/api/v1/sellers/:seller/proxies/test` |
| Add proxy to pool | `POST` | `/api/v1/sellers/:seller/proxies` |
| Remove proxy by index | `DELETE` | `/api/v1/sellers/:seller/proxies/:index` |
| Rotate to next alive proxy | `POST` | `/api/v1/sellers/:seller/actions/proxy-rotate` |
| Proxy pool status (via script) | `POST` | `/api/v1/sellers/:seller/actions/proxy-status` |
| **Extensions and Backups** | | |
| List installed extensions | `GET` | `/api/v1/sellers/:seller/extensions` |
| Remove extension | `DELETE` | `/api/v1/sellers/:seller/extensions/:name` |
| List profile backups | `GET` | `/api/v1/sellers/:seller/backups` |
| Restore from backup | `POST` | `/api/v1/sellers/:seller/restore/:filename` |

## Live Status Stream (SSE)
Use this for continuous frontend dashboard updates:

```http
GET /api/v1/monitor/stream?intervalMs=15000
Authorization: Bearer <accessToken>
```

Notes:
- `intervalMs` is optional and clamped to server-safe bounds.
- Stream sends `ready`, periodic `overview`, and `error` events.
- Idle keepalive comments are emitted to keep reverse-proxy connections alive.

## Example Seller Create Payload
```json
{
  "seller": "qa-team-1",
  "pass": "StrongPass!",
  "subdomain": "chrome1.example.com",
  "port": 3000,
  "user": "admin",
  "tz": "Asia/Kolkata",
  "mem": "2g",
  "cpu": "1.0",
  "shm": "1gb",
  "swap": "2G",
  "proxies": [
    "1.2.3.4:8080:user1:pass1",
    "5.6.7.8:8080:user2:pass2"
  ]
}
```

## Webhook Crash Alerts

Set `WEBHOOK_URL` in `.env` to receive a POST when a seller crashes or recovers.

Compatible with Discord, Slack, and any HTTP endpoint:

```env
# Discord
WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN

# Slack
WEBHOOK_URL=https://hooks.slack.com/services/T.../B.../...
```

Payload sent on crash/recovery:
```json
{
  "service": "chromium-fleet",
  "event": "seller_crashed",
  "seller": "qa-team-1",
  "containerState": "exited",
  "previousState": "running",
  "timestamp": "2025-01-01T03:00:00.000Z"
}
```

Events: `seller_crashed` | `seller_recovered`

## CORS — Production Setup

`CORS_ORIGINS` controls which browser origins can call the API directly.

```env
# api/.env
CORS_ORIGINS=https://dashboard.yourdomain.com,https://admin.yourdomain.com
```

If the frontend is served from the same subdomain as Nginx (e.g. `https://chrome1.yourdomain.com`), add it to `CORS_ORIGINS`.

When calling the API **through Nginx** (`/api/...`), requests also require Nginx basic auth. Frontend must include `Authorization: Basic ...` header alongside `Authorization: Bearer <token>`. Use two separate headers or proxy the API on a different subdomain without basic auth if needed.

For local development:
```env
CORS_ORIGINS=http://localhost:3000,http://localhost:5173
```

## Security Warning — Docker Socket

Mounting `/var/run/docker.sock` grants the API container host-level Docker daemon access.

**Production hardening checklist:**
- Never expose port `8787` publicly — serve API only through Nginx (`/api` proxy).
- API is protected by both Nginx basic auth AND JWT (`Authorization: Bearer`).
- Set `ALLOW_INSTALL=false` + `ALLOW_UNINSTALL=false` once all sellers are provisioned.
- Rate limiting is on by default — tune `RATE_LIMIT_API_MAX` and `RATE_LIMIT_AUTH_MAX`.
- SSE streams are quota-limited per connection — tune `SSE_MAX_BYTES_PER_HOUR`.
- In Docker mode (`FLEET_ROOT` is set), `POST /api/v1/sellers` and `DELETE /api/v1/sellers/:seller` return `501` — run `install.sh` / `uninstall.sh` on the host VM instead.

## Docker API Mode Restrictions

When the API runs in Docker (`FLEET_ROOT=/fleet` is set via `docker-compose.fleet.yml`):

| Endpoint | Behavior |
|---|---|
| `POST /api/v1/sellers` | Returns `501` — run `install.sh` on host directly |
| `DELETE /api/v1/sellers/:seller` | Returns `501` — run `uninstall.sh` on host directly |
| All lifecycle actions | ✓ Work normally (docker.sock) |
| All monitoring endpoints | ✓ Work normally |
| All proxy endpoints | ✓ Work normally |
| All SSE streams | ✓ Work normally |

Additionally, if `ALLOW_INSTALL=false` or `ALLOW_UNINSTALL=false` is set in `.env`, the corresponding endpoint returns `403 Forbidden` regardless of Docker mode.

## Notes

- Run API with permission to execute Docker and fleet scripts (root on VM, or Docker with `/var/run/docker.sock` mount).
- Command output is in `result.stdout` / `result.stderr` in API responses.
- For low-RAM VMs tune `.env`: `MONITOR_CACHE_TTL_MS`, `MONITOR_STREAM_*`.
- `createSeller` (install) does not work in Docker API mode — run `install.sh` on host directly.

## Support
- Author: `Datainteg`
- Support Email: `support@datainteg.io`
