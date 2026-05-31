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

`/healthz` is public. `/api/*` requires auth unless `DISABLE_AUTH=true`.

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
- `GET /api/v1/sellers`
- `GET /api/v1/sellers/:seller`
- `POST /api/v1/sellers`
- `POST /api/v1/sellers/:seller/actions/:action`
- `DELETE /api/v1/sellers/:seller`

## Example Seller Create Payload
```json
{
  "seller": "qa-team-1",
  "pass": "StrongPass!",
  "subdomain": "chrome1.example.com",
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

## Notes
- Run API with permission to execute Docker and fleet scripts (typically root on VM).
- Command output is returned in API responses as `result.stdout` / `result.stderr`.

## Support
- Author: `Datainteg`
- Support Email: `support@datainteg.io`
