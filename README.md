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
3. Log in to your websites and install required extensions.
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
| `--mem` | `3g` | No | Docker memory limit |
| `--cpu` | `1.5` | No | Docker CPU limit |
| `--shm` | `2gb` | No | `/dev/shm` size |
| `--swap` | `4G` | No | Swap file size |
| `--api-port` | `8787` | No | Local API upstream port for Nginx `/api` proxy |
| `--proxy` | - | No | `host:port:user:pass` (repeatable) |

## API For Frontend Integration
API docs: [`api/README.md`](./api/README.md)

Key endpoints:
- `POST /api/v1/auth/login` (username/password -> token pair)
- `POST /api/v1/auth/refresh` (rotate refresh token -> new pair)
- `POST /api/v1/auth/logout` (revoke refresh token)
- `GET /api/v1/monitor/overview`
- `GET /api/v1/monitor/vm`
- `GET /api/v1/monitor/fleet`
- `GET /api/v1/sellers`
- `POST /api/v1/sellers`
- `POST /api/v1/sellers/:seller/actions/:action`
- `DELETE /api/v1/sellers/:seller`

If Nginx setup uses default config, call API from:
- `https://<your-subdomain>/api/...`

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
