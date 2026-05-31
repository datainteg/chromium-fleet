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

Default: `http://0.0.0.0:8787`

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

## Notes
- Run API with permission to execute Docker and fleet scripts (typically root on VM).
- Command output is returned in API responses as `result.stdout` / `result.stderr`.
- For low-RAM VMs, tune `.env` monitor values: `MONITOR_CACHE_TTL_MS`, `MONITOR_STREAM_*`.

## Support
- Author: `Datainteg`
- Support Email: `support@datainteg.io`
