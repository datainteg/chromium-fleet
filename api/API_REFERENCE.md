# API Reference

Complete reference for the `chromium-fleet` REST API.

**Base URL:** `https://<your-subdomain>/api` (through Nginx) or `http://127.0.0.1:8787` (direct, localhost only)

**Auth required:** All `/api/*` endpoints require `Authorization: Bearer <accessToken>` unless noted.

**Get a token:** `POST /api/v1/auth/login`

---

## Table of Contents

- [Authentication](#authentication)
- [Health and Meta](#health-and-meta)
- [Monitoring](#monitoring)
- [Seller Management](#seller-management)
- [Seller Actions](#seller-actions)
- [Proxy Pool](#proxy-pool)
- [Logs and Events](#logs-and-events)
- [Extensions](#extensions)
- [Profile Backups](#profile-backups)
- [Error Responses](#error-responses)

---

## Authentication

### POST /api/v1/auth/login

Exchange username and password for an access token and refresh token.

No auth header required.

**Request**
```http
POST /api/v1/auth/login
Content-Type: application/json
```
```json
{
  "username": "admin",
  "password": "YourStrongPassword"
}
```

**Success `200`**
```json
{
  "tokenType": "Bearer",
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "accessExpiresInSeconds": 900,
  "refreshExpiresInSeconds": 604800
}
```

**Errors**
```json
{ "error": "Invalid username or password" }         // 401
{ "error": "JWT auth is not configured on this server" } // 500
{ "error": "Too many auth attempts. Try again later." }  // 429
```

**curl**
```bash
curl -s -X POST https://chrome1.yourdomain.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"YourStrongPassword"}' | jq .
```

**Frontend usage:** Store `accessToken` in memory (not localStorage). Store `refreshToken` in an httpOnly cookie or secure storage. Call refresh before the access token expires.

---

### POST /api/v1/auth/refresh

Exchange a refresh token for a new token pair. Old refresh token is revoked (rotation).

No auth header required.

**Request**
```http
POST /api/v1/auth/refresh
Content-Type: application/json
```
```json
{
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Success `200`** — same shape as login response
```json
{
  "tokenType": "Bearer",
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "accessExpiresInSeconds": 900,
  "refreshExpiresInSeconds": 604800
}
```

**Errors**
```json
{ "error": "refreshToken is required" }              // 400
{ "error": "Invalid or expired refresh token" }      // 401
{ "error": "Refresh token is revoked" }              // 401
```

**curl**
```bash
curl -s -X POST https://chrome1.yourdomain.com/api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refreshToken":"<your-refresh-token>"}' | jq .
```

---

### POST /api/v1/auth/logout

Revoke a refresh token. Access tokens expire naturally.

No auth header required.

**Request**
```http
POST /api/v1/auth/logout
Content-Type: application/json
```
```json
{
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Success `200`**
```json
{ "loggedOut": true }
```

**curl**
```bash
curl -s -X POST https://chrome1.yourdomain.com/api/v1/auth/logout \
  -H "Content-Type: application/json" \
  -d '{"refreshToken":"<your-refresh-token>"}' | jq .
```

---

## Health and Meta

### GET /healthz

Public health check. No auth required.

**Success `200`**
```json
{
  "ok": true,
  "service": "chromium-fleet-api",
  "version": "0.1.0",
  "uptimeSeconds": 3742,
  "authEnabled": true
}
```

**curl**
```bash
curl -s https://chrome1.yourdomain.com/healthz | jq .
```

---

### GET /api/v1/meta

Server capabilities and feature flags.

**Success `200`**
```json
{
  "service": "chromium-fleet-api",
  "version": "0.1.0",
  "authEnabled": true,
  "authMode": {
    "jwtEnabled": true,
    "apiKeyEnabled": false,
    "refreshTokenRotation": true
  },
  "allowInstall": true,
  "allowUninstall": true,
  "allowActions": true,
  "runningInDocker": true,
  "supportedActions": ["start","stop","restart","recreate","update","status","proxy-status","proxy-rotate"],
  "monitoringEndpoints": [
    "/api/v1/monitor/overview",
    "/api/v1/monitor/vm",
    "/api/v1/monitor/fleet",
    "/api/v1/monitor/cluster",
    "/api/v1/monitor/stream",
    "/api/v1/status/live"
  ],
  "proxyEndpoints": [
    "GET /api/v1/sellers/:seller/proxies",
    "POST /api/v1/sellers/:seller/proxies",
    "DELETE /api/v1/sellers/:seller/proxies/:index"
  ]
}
```

**curl**
```bash
curl -s https://chrome1.yourdomain.com/api/v1/meta \
  -H "Authorization: Bearer $TOKEN" | jq .
```

**Frontend usage:** Call this on app load to check `allowInstall`, `allowUninstall`, `supportedActions`. Disable install/remove buttons if flags are false.

---

## Monitoring

### GET /api/v1/monitor/overview

Full VM + fleet health snapshot. Cached (default 4s TTL).

**Success `200`**
```json
{
  "timestamp": "2025-01-01T07:00:00.000Z",
  "health": {
    "overall": "healthy",
    "vm": {
      "healthy": true,
      "issues": []
    },
    "fleet": {
      "healthy": true,
      "status": "healthy",
      "degradedSellers": []
    }
  },
  "vm": {
    "host": "chrome-vm-1",
    "platform": "linux",
    "release": "5.15.0-1034-gcp",
    "arch": "x64",
    "cpuCores": 2,
    "uptimeSeconds": 21600,
    "loadAverage": {
      "oneMinute": 0.45,
      "fiveMinutes": 0.38,
      "fifteenMinutes": 0.31
    },
    "cpu": { "usagePercent": 12.5 },
    "memory": {
      "totalBytes": 4294967296,
      "usedBytes": 2684354560,
      "freeBytes": 1610612736,
      "usedPercent": 62.5
    },
    "swap": {
      "available": true,
      "totalBytes": 2147483648,
      "usedBytes": 214748364,
      "freeBytes": 1932735283,
      "usedPercent": 10.0
    },
    "diskRoot": {
      "filesystem": "/dev/sda1",
      "mountPoint": "/",
      "totalBytes": 53687091200,
      "usedBytes": 21474836480,
      "freeBytes": 32212254720,
      "usedPercent": 40
    }
  },
  "fleet": {
    "summary": {
      "health": "healthy",
      "totalSellers": 2,
      "runningSellers": 2,
      "stoppedSellers": 0,
      "proxyEnabledSellers": 1,
      "degradedSellers": []
    },
    "sellers": [ ... ],
    "containerUsage": [ ... ]
  }
}
```

**Health values:**
- `overall`: `"healthy"` | `"degraded"`
- `fleet.status`: `"healthy"` | `"degraded"` | `"critical"` | `"empty"`

**curl**
```bash
curl -s https://chrome1.yourdomain.com/api/v1/monitor/overview \
  -H "Authorization: Bearer $TOKEN" | jq .health
```

---

### GET /api/v1/monitor/vm

VM-only metrics (CPU, RAM, disk, swap). Not cached.

**Success `200`**
```json
{
  "timestamp": "2025-01-01T07:00:00.000Z",
  "vm": {
    "host": "chrome-vm-1",
    "cpuCores": 2,
    "uptimeSeconds": 21600,
    "cpu": { "usagePercent": 12.5 },
    "memory": {
      "totalBytes": 4294967296,
      "usedBytes": 2684354560,
      "freeBytes": 1610612736,
      "usedPercent": 62.5
    },
    "swap": {
      "available": true,
      "totalBytes": 2147483648,
      "usedBytes": 214748364,
      "usedPercent": 10.0
    },
    "diskRoot": {
      "totalBytes": 53687091200,
      "usedBytes": 21474836480,
      "usedPercent": 40
    }
  }
}
```

**curl**
```bash
curl -s https://chrome1.yourdomain.com/api/v1/monitor/vm \
  -H "Authorization: Bearer $TOKEN" | jq .vm.memory
```

---

### GET /api/v1/monitor/fleet

All sellers with Docker container stats.

**Success `200`**
```json
{
  "timestamp": "2025-01-01T07:00:00.000Z",
  "fleet": {
    "summary": {
      "health": "healthy",
      "totalSellers": 2,
      "runningSellers": 2,
      "stoppedSellers": 0,
      "proxyEnabledSellers": 1,
      "degradedSellers": []
    },
    "sellers": [
      {
        "seller": "qa-team-1",
        "appDir": "/opt/qa-team-1-browser",
        "containerName": "qa-team-1-chrome",
        "port": 3000,
        "containerState": "running",
        "running": true,
        "hasProxy": false,
        "proxyCount": 0,
        "activeProxy": null
      }
    ],
    "containerUsage": [
      {
        "containerName": "qa-team-1-chrome",
        "cpuPercent": "2.34%",
        "memUsage": "312MiB / 2GiB",
        "netIO": "1.2MB / 456kB",
        "blockIO": "89MB / 12MB"
      }
    ]
  }
}
```

**curl**
```bash
curl -s https://chrome1.yourdomain.com/api/v1/monitor/fleet \
  -H "Authorization: Bearer $TOKEN" | jq .fleet.summary
```

---

### GET /api/v1/monitor/stream

**Live SSE stream** for real-time frontend dashboard. Sends events indefinitely until client disconnects.

**Query params:**
- `intervalMs` (optional) — polling interval in ms, clamped to `5000–60000`. Default: `15000`.

**Request**
```http
GET /api/v1/monitor/stream?intervalMs=10000
Authorization: Bearer <accessToken>
```

**SSE event types:**

`ready` — sent once on connect
```
event: ready
data: {"timestamp":"2025-01-01T07:00:00.000Z","intervalMs":10000,"heartbeatMs":10000,"cacheTtlMs":4000}
```

`overview` — sent every `intervalMs`
```
event: overview
data: { ...same shape as GET /api/v1/monitor/overview... }
```

`error` — sent if monitoring fails or quota exceeded
```
event: error
data: {"timestamp":"2025-01-01T07:00:01.000Z","error":"monitor stream failed"}
```

`: keepalive <timestamp>` — comment line sent every `heartbeatMs` to keep reverse-proxy connections alive

**Limits:**
- Max 3 concurrent streams per IP (returns `429` if exceeded)
- Max 2MB per individual event
- Max 100MB per connection per hour (stream closes with error event)

**curl**
```bash
curl -N "https://chrome1.yourdomain.com/api/v1/monitor/stream?intervalMs=15000" \
  -H "Authorization: Bearer $TOKEN"
```

**JavaScript (browser)**
```javascript
const es = new EventSource(
  'https://chrome1.yourdomain.com/api/v1/monitor/stream?intervalMs=15000',
  { headers: { Authorization: `Bearer ${accessToken}` } }
  // Note: browser EventSource does not support custom headers natively.
  // Use a polyfill such as 'eventsource' npm package, or pass token as query param
  // if your API supports it, or proxy through your frontend server.
);

es.addEventListener('ready', (e) => {
  console.log('Stream connected:', JSON.parse(e.data));
});

es.addEventListener('overview', (e) => {
  const data = JSON.parse(e.data);
  updateDashboard(data);
});

es.addEventListener('error', (e) => {
  console.error('Stream error:', e.data);
});
```

**Note on browser SSE auth:** Standard `EventSource` does not support `Authorization` headers. Options:
1. Use an SSE polyfill that supports headers (`@microsoft/fetch-event-source`)
2. Route the SSE endpoint through your backend-for-frontend

---

### GET /api/v1/status/live

Alias for `GET /api/v1/monitor/stream`. Same behavior.

---

## Seller Management

### GET /api/v1/sellers

List all installed sellers (browser instances) with Docker state.

**Success `200`**
```json
{
  "count": 2,
  "sellers": [
    {
      "seller": "qa-team-1",
      "appDir": "/opt/qa-team-1-browser",
      "containerName": "qa-team-1-chrome",
      "port": 3000,
      "containerState": "running",
      "running": true,
      "hasProxy": false,
      "proxyCount": 0,
      "activeProxy": null
    },
    {
      "seller": "qa-team-2",
      "appDir": "/opt/qa-team-2-browser",
      "containerName": "qa-team-2-chrome",
      "port": 3001,
      "containerState": "running",
      "running": true,
      "hasProxy": true,
      "proxyCount": 2,
      "activeProxy": "1.2.3.4:8080"
    }
  ]
}
```

**Container states:** `running` | `exited` | `paused` | `restarting` | `not-found` | `docker-unavailable`

**curl**
```bash
curl -s https://chrome1.yourdomain.com/api/v1/sellers \
  -H "Authorization: Bearer $TOKEN" | jq '.sellers[] | {seller, running, activeProxy}'
```

---

### GET /api/v1/sellers/:seller

Single seller detail.

**Success `200`**
```json
{
  "seller": "qa-team-1",
  "appDir": "/opt/qa-team-1-browser",
  "containerName": "qa-team-1-chrome",
  "port": 3000,
  "containerState": "running",
  "running": true,
  "hasProxy": false,
  "proxyCount": 0,
  "activeProxy": null
}
```

**Errors**
```json
{ "error": "Seller not found", "requestId": "..." }  // 404
{ "error": "Invalid seller name", "requestId": "..." } // 400
```

**curl**
```bash
curl -s https://chrome1.yourdomain.com/api/v1/sellers/qa-team-1 \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

### POST /api/v1/sellers

Create a new browser instance (runs `install.sh` on the host VM).

**Disabled in Docker API mode** — returns `501`. Run `install.sh` directly on the VM.

**Request**
```http
POST /api/v1/sellers
Content-Type: application/json
Authorization: Bearer <accessToken>
```
```json
{
  "seller": "qa-team-3",
  "pass": "StrongPass123!",
  "subdomain": "chrome3.yourdomain.com",
  "port": 3002,
  "user": "admin",
  "tz": "Asia/Kolkata",
  "mem": "2g",
  "cpu": "1.0",
  "shm": "1gb",
  "swap": "2G",
  "proxies": [
    "1.2.3.4:8080:proxyuser:proxypass",
    "5.6.7.8:8080:proxyuser2:proxypass2"
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `seller` | Yes | `^[a-z0-9][a-z0-9_-]{0,31}$` |
| `pass` | Yes | Nginx basic auth password |
| `subdomain` | Yes | Valid domain, e.g. `chrome3.example.com` |
| `port` | No | Default `3000`. Must not be in use. |
| `user` | No | Basic auth username. Default `admin`. |
| `tz` | No | Container timezone. Default `Asia/Kolkata`. |
| `mem` | No | Docker mem limit, e.g. `2g`, `1536m`. Default `2g`. |
| `cpu` | No | Docker CPU limit `0.1–8.0`. Default `1.0`. |
| `shm` | No | `/dev/shm` size. Default `1gb`. |
| `swap` | No | Swap size. Default `2G`. |
| `proxies` | No | Array of `"host:port:user:pass"` strings. |

**Success `201`**
```json
{
  "seller": "qa-team-3",
  "result": {
    "code": 0,
    "stdout": "[✓] Chrome started. Session preserved.",
    "stderr": "",
    "durationMs": 42300
  }
}
```

**Errors**
```json
{ "error": "seller is required and must match ^[a-z0-9]...", "requestId": "..." }  // 400
{ "error": "Port 3002 is already in use on this host", "requestId": "..." }        // 409
{ "error": "Seller creation is disabled by server configuration", "requestId":"..."} // 403
{ "error": "Seller creation requires running install.sh directly...", "requestId":"..."} // 501 (Docker mode)
```

---

### DELETE /api/v1/sellers/:seller

Remove a browser instance (runs `uninstall.sh` on the host VM). **Destructive — deletes all session data.**

**Disabled in Docker API mode** — returns `501`.

**Success `200`**
```json
{
  "seller": "qa-team-3",
  "result": {
    "code": 0,
    "stdout": "'qa-team-3' removed successfully.",
    "durationMs": 3800
  }
}
```

**curl**
```bash
curl -s -X DELETE https://chrome1.yourdomain.com/api/v1/sellers/qa-team-3 \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

## Seller Actions

### POST /api/v1/sellers/:seller/actions/:action

Run a lifecycle action on a single seller.

**Available actions:**

| Action | Effect |
|---|---|
| `start` | Start container (preserves session). Uses `docker compose start`. |
| `stop` | Stop container gracefully (30s flush). Does NOT remove container. |
| `restart` | Stop then start. Session preserved. |
| `recreate` | Full container recreate (`docker compose up -d --force-recreate`). Session safe (bind-mount). |
| `update` | Pull latest image then recreate. Session safe. |
| `status` | Print container status and resource usage. |
| `proxy-status` | Print live health status for each proxy in pool. |
| `proxy-rotate` | Find next alive proxy, update `proxy.env`, restart container. |

**Success `200`**
```json
{
  "seller": "qa-team-1",
  "action": "restart",
  "result": {
    "code": 0,
    "stdout": "Chrome restarted. Session preserved.",
    "stderr": "",
    "durationMs": 4200
  }
}
```

**Errors**
```json
{ "error": "Unsupported action 'nuke'", "requestId": "..." }          // 400
{ "error": "Action script not found: /opt/...", "requestId": "..." }  // 404
{ "error": "Seller actions are disabled by server configuration" }    // 403
```

**curl examples**
```bash
# Start
curl -s -X POST https://chrome1.yourdomain.com/api/v1/sellers/qa-team-1/actions/start \
  -H "Authorization: Bearer $TOKEN" | jq .result.stdout

# Rotate proxy
curl -s -X POST https://chrome1.yourdomain.com/api/v1/sellers/qa-team-2/actions/proxy-rotate \
  -H "Authorization: Bearer $TOKEN" | jq .result

# Live proxy status
curl -s -X POST https://chrome1.yourdomain.com/api/v1/sellers/qa-team-2/actions/proxy-status \
  -H "Authorization: Bearer $TOKEN" | jq .result.stdout
```

---

### POST /api/v1/sellers/:seller/resume

Start seller if stopped. No-op if already running.

**Success `200` — already running**
```json
{
  "seller": "qa-team-1",
  "resumed": false,
  "reason": "already-running",
  "before": { "running": true, "containerState": "running", ... },
  "after": { "running": true, "containerState": "running", ... }
}
```

**Success `200` — was stopped, now started**
```json
{
  "seller": "qa-team-1",
  "resumed": true,
  "reason": "started",
  "before": { "running": false, "containerState": "exited", ... },
  "after": { "running": true, "containerState": "running", ... },
  "result": { "code": 0, "stdout": "Chrome started.", "durationMs": 2100 }
}
```

**curl**
```bash
curl -s -X POST https://chrome1.yourdomain.com/api/v1/sellers/qa-team-1/resume \
  -H "Authorization: Bearer $TOKEN" | jq '{resumed, reason}'
```

---

### POST /api/v1/sellers/resume-all

Resume all stopped sellers (concurrency 3 at a time).

**Success `200`**
```json
{
  "total": 3,
  "resumedCount": 1,
  "failedCount": 0,
  "results": [
    { "seller": "qa-team-1", "resumed": false, "reason": "already-running" },
    { "seller": "qa-team-2", "resumed": true,  "reason": "started" },
    { "seller": "qa-team-3", "resumed": false, "reason": "already-running" }
  ]
}
```

**curl**
```bash
curl -s -X POST https://chrome1.yourdomain.com/api/v1/sellers/resume-all \
  -H "Authorization: Bearer $TOKEN" | jq '{total, resumedCount, failedCount}'
```

---

### POST /api/v1/sellers/actions/:action

**Fleet-wide bulk action** — run one action on ALL sellers (concurrency 3 at a time).

Same actions as per-seller: `start` | `stop` | `restart` | `recreate` | `update`

**Success `200`**
```json
{
  "action": "restart",
  "total": 3,
  "successCount": 3,
  "failedCount": 0,
  "results": [
    { "seller": "qa-team-1", "success": true, "result": { "code": 0, "stdout": "..." } },
    { "seller": "qa-team-2", "success": true, "result": { "code": 0, "stdout": "..." } },
    { "seller": "qa-team-3", "success": true, "result": { "code": 0, "stdout": "..." } }
  ]
}
```

**curl**
```bash
# Restart all sellers at once
curl -s -X POST https://chrome1.yourdomain.com/api/v1/sellers/actions/restart \
  -H "Authorization: Bearer $TOKEN" | jq '{action, total, successCount}'
```

---

## Proxy Pool

> Proxy is optional. Sellers without proxies return `count: 0, proxies: []` — no errors.
> Passwords are always masked in list/test responses.

### GET /api/v1/sellers/:seller/proxies

List proxy pool. Passwords masked.

**Success `200`**
```json
{
  "seller": "qa-team-2",
  "count": 2,
  "proxies": [
    { "index": 0, "host": "1.2.3.4", "port": "8080", "user": "proxyuser1", "active": true },
    { "index": 1, "host": "5.6.7.8", "port": "8080", "user": "proxyuser2", "active": false }
  ]
}
```

**No proxy configured**
```json
{ "seller": "qa-team-1", "count": 0, "proxies": [] }
```

**curl**
```bash
curl -s https://chrome1.yourdomain.com/api/v1/sellers/qa-team-2/proxies \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

### POST /api/v1/sellers/:seller/proxies

Add a proxy to the pool.

**Request**
```http
POST /api/v1/sellers/qa-team-2/proxies
Content-Type: application/json
Authorization: Bearer <accessToken>
```
```json
{
  "proxy": "9.10.11.12:3128:myuser:mypassword"
}
```

Format: `host:port:username:password` (port must be numeric)

**Success `201`**
```json
{
  "seller": "qa-team-2",
  "added": "9.10.11.12:3128",
  "count": 3
}
```

**Errors**
```json
{ "error": "proxy is required (host:port:user:pass)" }                       // 400
{ "error": "Invalid proxy format. Expected: host:port:user:pass..." }        // 400
{ "error": "Proxy already exists in pool" }                                   // 409
```

**curl**
```bash
curl -s -X POST https://chrome1.yourdomain.com/api/v1/sellers/qa-team-2/proxies \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"proxy":"9.10.11.12:3128:myuser:mypassword"}' | jq .
```

---

### DELETE /api/v1/sellers/:seller/proxies/:index

Remove a proxy by index (0-based, from list response).

If the removed proxy was the active one, `active.conf` is cleared and the next health check will pick a new active proxy.

**Success `200`**
```json
{
  "seller": "qa-team-2",
  "removed": "9.10.11.12:3128",
  "count": 2
}
```

**Errors**
```json
{ "error": "Proxy index 5 out of range (0–2)" }  // 400
```

**curl**
```bash
# Remove proxy at index 1
curl -s -X DELETE https://chrome1.yourdomain.com/api/v1/sellers/qa-team-2/proxies/1 \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

### GET /api/v1/sellers/:seller/proxies/test

**Live test** every proxy in the pool — makes actual HTTP requests through each proxy to verify connectivity. Returns latency and external IP per proxy.

**Success `200`**
```json
{
  "seller": "qa-team-2",
  "count": 2,
  "proxies": [
    {
      "index": 0,
      "host": "1.2.3.4",
      "port": "8080",
      "user": "proxyuser1",
      "alive": true,
      "latencyMs": 312,
      "externalIp": "1.2.3.4",
      "active": true
    },
    {
      "index": 1,
      "host": "5.6.7.8",
      "port": "8080",
      "user": "proxyuser2",
      "alive": false,
      "latencyMs": null,
      "externalIp": null,
      "active": false
    }
  ]
}
```

**No proxies configured**
```json
{ "seller": "qa-team-1", "count": 0, "proxies": [] }
```

**curl**
```bash
curl -s https://chrome1.yourdomain.com/api/v1/sellers/qa-team-2/proxies/test \
  -H "Authorization: Bearer $TOKEN" | jq '.proxies[] | {host, alive, latencyMs}'
```

**Note:** This endpoint makes real outbound HTTP requests. Response time depends on proxy response time (up to ~8s per proxy, tested in parallel).

---

## Logs and Events

### GET /api/v1/sellers/:seller/logs

Docker container logs (stdout + stderr combined).

**Query params:**
- `lines` (optional) — number of lines, `1–1000`. Default `100`.

**Success `200`**
```json
{
  "seller": "qa-team-1",
  "containerName": "qa-team-1-chrome",
  "lines": 50,
  "logs": "2025-01-01T07:00:00.000Z [cont-init.d] executing container initialization scripts...\n2025-01-01T07:00:01.000Z [cont-init.d] done.\n..."
}
```

**curl**
```bash
curl -s "https://chrome1.yourdomain.com/api/v1/sellers/qa-team-1/logs?lines=50" \
  -H "Authorization: Bearer $TOKEN" | jq .logs
```

---

### GET /api/v1/sellers/:seller/events

In-memory health event log. Records the last 50 state change events (crash/recovery) detected by the background state watcher (polls every 30s).

**Success `200`**
```json
{
  "seller": "qa-team-1",
  "count": 2,
  "events": [
    {
      "type": "seller_recovered",
      "containerState": "running",
      "previousState": "exited",
      "timestamp": "2025-01-01T07:02:30.000Z"
    },
    {
      "type": "seller_crashed",
      "containerState": "exited",
      "previousState": "running",
      "timestamp": "2025-01-01T03:00:01.000Z"
    }
  ]
}
```

**Event types:** `seller_crashed` | `seller_recovered`

**No events yet**
```json
{ "seller": "qa-team-1", "count": 0, "events": [] }
```

**curl**
```bash
curl -s https://chrome1.yourdomain.com/api/v1/sellers/qa-team-1/events \
  -H "Authorization: Bearer $TOKEN" | jq '.events[:5]'
```

**Note:** Events are in-memory only. They reset on API restart.

---

## Extensions

### GET /api/v1/sellers/:seller/extensions

List files and folders in the seller's `./extensions/` directory.

**Success `200`**
```json
{
  "seller": "qa-team-1",
  "count": 2,
  "extensions": [
    { "name": "ublock-origin.crx", "type": "crx" },
    { "name": "my-custom-extension", "type": "unpacked" }
  ]
}
```

**No extensions installed**
```json
{ "seller": "qa-team-1", "count": 0, "extensions": [] }
```

**curl**
```bash
curl -s https://chrome1.yourdomain.com/api/v1/sellers/qa-team-1/extensions \
  -H "Authorization: Bearer $TOKEN" | jq .
```

**Note:** To install a new extension, drop the `.crx` file or unpacked folder into `/opt/<seller>-browser/extensions/` on the VM, then open Chrome and install it once. After installation, Chrome stores extension state in `./profile` and the extension persists after restarts.

---

### DELETE /api/v1/sellers/:seller/extensions/:name

Remove an extension file or folder from `./extensions/`.

**Success `200`**
```json
{
  "seller": "qa-team-1",
  "deleted": "ublock-origin.crx"
}
```

**Errors**
```json
{ "error": "Extension not found: ublock-origin.crx" }  // 404
{ "error": "Invalid extension name" }                   // 400
```

**curl**
```bash
curl -s -X DELETE \
  "https://chrome1.yourdomain.com/api/v1/sellers/qa-team-1/extensions/ublock-origin.crx" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

## Profile Backups

Daily profile backups are created automatically by cron at 02:00 UTC. Each backup is a `.tar.gz` of the full `./profile` directory (Chrome session, cookies, extensions). The last 3 daily backups are kept.

### GET /api/v1/sellers/:seller/backups

List available profile backups with file sizes.

**Success `200`**
```json
{
  "seller": "qa-team-1",
  "count": 3,
  "backups": [
    { "filename": "profile-20250103.tar.gz", "sizeBytes": 52428800 },
    { "filename": "profile-20250102.tar.gz", "sizeBytes": 51380224 },
    { "filename": "profile-20250101.tar.gz", "sizeBytes": 50331648 }
  ]
}
```

**No backups yet**
```json
{ "seller": "qa-team-1", "count": 0, "backups": [] }
```

**curl**
```bash
curl -s https://chrome1.yourdomain.com/api/v1/sellers/qa-team-1/backups \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

### POST /api/v1/sellers/:seller/restore/:filename

**Destructive.** Restore a profile backup. Steps:
1. Stop container (30s graceful flush)
2. Move current `./profile` to `./profile-pre-restore-<timestamp>` (safety copy)
3. Extract backup into `./profile/`
4. Fix ownership (`1000:1000`)
5. Start container

**Request**
```http
POST /api/v1/sellers/qa-team-1/restore/profile-20250101.tar.gz
Authorization: Bearer <accessToken>
```

No request body.

**Success `200`**
```json
{
  "seller": "qa-team-1",
  "restored": "profile-20250101.tar.gz",
  "previousProfileSaved": "profile-pre-restore-1735718400000"
}
```

**Errors**
```json
{ "error": "Backup not found: profile-20250101.tar.gz" }              // 404
{ "error": "Invalid backup filename. Expected: profile-YYYYMMDD.tar.gz" } // 400
```

**curl**
```bash
curl -s -X POST \
  "https://chrome1.yourdomain.com/api/v1/sellers/qa-team-1/restore/profile-20250101.tar.gz" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

**Warning:** Current Chrome session is replaced. Previous profile is saved as `profile-pre-restore-*` in the app directory — not deleted automatically.

---

## Error Responses

All error responses follow this shape:

```json
{
  "error": "Human-readable message",
  "requestId": "uuid-v4"
}
```

| Code | Meaning |
|---|---|
| `400` | Bad request — missing or invalid input |
| `401` | Unauthorized — missing, expired, or invalid token |
| `403` | Forbidden — action disabled by server config |
| `404` | Not found — seller or resource does not exist |
| `409` | Conflict — port in use, proxy already exists |
| `429` | Rate limited — too many requests |
| `500` | Internal server error — check API logs (`docker compose logs api`) |
| `501` | Not implemented — only from Docker mode for install/remove |

**Note:** 500 errors intentionally return a generic message to avoid leaking internal details. Use `requestId` to correlate with server-side logs.

---

## Quick Auth Flow (JavaScript)

```javascript
const API = 'https://chrome1.yourdomain.com';

async function login(username, password) {
  const res = await fetch(`${API}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password })
  });
  if (!res.ok) throw new Error((await res.json()).error);
  return res.json(); // { accessToken, refreshToken, accessExpiresInSeconds, ... }
}

async function apiFetch(path, options = {}, accessToken) {
  const res = await fetch(`${API}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${accessToken}`,
      ...(options.headers || {})
    }
  });
  if (!res.ok) {
    const err = await res.json();
    throw Object.assign(new Error(err.error), { status: res.status, requestId: err.requestId });
  }
  return res.json();
}

// Usage
const { accessToken, refreshToken } = await login('admin', 'YourPassword');
const sellers = await apiFetch('/api/v1/sellers', {}, accessToken);
const overview = await apiFetch('/api/v1/monitor/overview', {}, accessToken);
await apiFetch('/api/v1/sellers/qa-team-1/actions/restart', { method: 'POST' }, accessToken);
```
