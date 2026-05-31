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
npm install
cp .env.example .env
```

Set at least:
- `AUTH_USERNAME`, `AUTH_PASSWORD`
- `JWT_SECRET`, `REFRESH_TOKEN_SECRET`
- `CORS_ORIGINS` for your frontend

## Run
```bash
cd api
npm start
```

Default: `http://0.0.0.0:8787`

## Auto-start On VM Boot
For daily stop/start servers, install API as a systemd service:

```bash
cd api
sudo bash install-service.sh
```

This enables restart-on-failure and boot-time auto-start with a 256MB Node heap cap.

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
- `GET /healthz`
- `GET /api/v1/meta`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `GET /api/v1/monitor/overview`
- `GET /api/v1/monitor/vm`
- `GET /api/v1/monitor/fleet`
- `GET /api/v1/monitor/cluster`
- `GET /api/v1/monitor/stream` (SSE live monitoring)
- `GET /api/v1/status/live` (alias of monitor stream)
- `GET /api/v1/sellers`
- `GET /api/v1/sellers/:seller`
- `POST /api/v1/sellers`
- `POST /api/v1/sellers/:seller/actions/:action`
- `POST /api/v1/sellers/:seller/resume`
- `POST /api/v1/sellers/resume-all`
- `DELETE /api/v1/sellers/:seller`

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
