# chromium-fleet API

REST API control plane for `chromium-fleet`, designed for frontend integration.

## 1) Install

```bash
cd api
npm install
cp .env.example .env
```

Edit `.env` and set at least:

- `AUTH_USERNAME`, `AUTH_PASSWORD`, `JWT_SECRET`
- `CORS_ORIGINS` to your frontend URL(s)

## 2) Run

```bash
cd api
npm start
```

Default server: `http://0.0.0.0:8787`

## 3) Auth

Default mode is username/password login + JWT bearer token.

1. `POST /api/v1/auth/login` with:

```json
{
  "username": "admin",
  "password": "your-password"
}
```

2. Use returned access token:

```http
Authorization: Bearer <accessToken>
```

Optional legacy mode:

- Set `ALLOW_API_KEY_AUTH=true`
- Send `x-api-key: <API_KEY>`

`/healthz` is public. `/api/*` requires auth unless `DISABLE_AUTH=true`.

## 4) Endpoints

### `GET /healthz`

Health check.

### `GET /api/v1/meta`

Server capabilities and supported actions.

### `POST /api/v1/auth/login`

Login with username/password and receive JWT access token.

### `GET /api/v1/monitor/overview`

Combined VM usage + fleet/cluster health snapshot.

### `GET /api/v1/monitor/vm`

VM/system usage metrics (CPU, memory, swap, disk root, load average, uptime).

### `GET /api/v1/monitor/fleet`

Fleet status and usage summary across all sellers.

### `GET /api/v1/monitor/cluster`

Alias of fleet monitoring for cluster-style dashboards.

### `GET /api/v1/sellers`

List installed sellers and current state.

### `GET /api/v1/sellers/:seller`

Get a single seller summary.

### `POST /api/v1/sellers`

Create a seller (calls `install.sh`).

Payload:

```json
{
  "seller": "seller1",
  "pass": "StrongPass!",
  "subdomain": "seller1.example.com",
  "port": 3000,
  "user": "admin",
  "tz": "Asia/Kolkata",
  "mem": "3g",
  "cpu": "1.5",
  "shm": "2gb",
  "swap": "4G",
  "proxies": [
    "1.2.3.4:8080:user1:pass1",
    "5.6.7.8:8080:user2:pass2"
  ]
}
```

### `DELETE /api/v1/sellers/:seller`

Remove a seller (calls `uninstall.sh --yes`).

### `POST /api/v1/sellers/:seller/actions/:action`

Run one seller lifecycle action.

Supported action values:

- `start`
- `stop`
- `restart`
- `recreate`
- `update`
- `status`
- `proxy-status`
- `proxy-rotate`

## 5) Notes

- API process should run as a user with permission to run Docker and manage seller scripts (typically root on VM).
- Command output is returned in API responses as `result.stdout` / `result.stderr`.
