# chromium-fleet

Generic, multi-instance Chromium browser VMs — managed via Docker, fronted by Nginx with Basic Auth and auto SSL. Supports optional multi-proxy with automatic failover.

---

## Repository Structure

```
chromium-fleet/
├── install.sh                  ← one-command entry point (curl this)
├── uninstall.sh                ← per-seller clean removal
├── chrome-setup/
│   └── setup.sh                ← Docker + swap + container + cron
├── nginx-setup/
│   └── nginx.sh                ← Nginx + Basic Auth + SSL
├── proxy-setup/
│   └── proxy.sh                ← proxy management + auto-failover
└── scripts/
    ├── list-sellers.sh         ← list all instances on this VM
    ├── update-all.sh           ← pull latest image for all instances
    └── health-all.sh           ← system + container health overview
```

---

## Quick Start

### No proxy

```bash
curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/install.sh \
  | bash -s -- \
      --seller    seller1 \
      --port      3000 \
      --user      admin \
      --pass      "StrongPass!" \
      --subdomain seller1.yourdomain.com
```

### With one proxy

```bash
curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/install.sh \
  | bash -s -- \
      --seller    seller1 \
      --port      3000 \
      --user      admin \
      --pass      "StrongPass!" \
      --subdomain seller1.yourdomain.com \
      --proxy     "1.2.3.4:8080:proxyuser:proxypass"
```

### With multiple proxies (auto-failover)

```bash
curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/install.sh \
  | bash -s -- \
      --seller    seller1 \
      --port      3000 \
      --user      admin \
      --pass      "StrongPass!" \
      --subdomain seller1.yourdomain.com \
      --proxy     "1.2.3.4:8080:user1:pass1" \
      --proxy     "5.6.7.8:8080:user2:pass2" \
      --proxy     "9.10.11.12:3128:user3:pass3"
```

---

## All Parameters

| Flag | Default | Required | Description |
|---|---|---|---|
| `--seller` | `seller1` | No | Unique instance name |
| `--port` | `3000` | No | Host port for Chromium |
| `--user` | `admin` | No | Nginx Basic Auth username |
| `--pass` | — | **YES** | Nginx Basic Auth password |
| `--subdomain` | — | **YES** | Full domain, e.g. `s1.example.com` |
| `--tz` | `Asia/Kolkata` | No | Container timezone |
| `--mem` | `3g` | No | Docker memory limit |
| `--cpu` | `1.5` | No | Docker CPU limit |
| `--shm` | `2gb` | No | `/dev/shm` size |
| `--swap` | `4G` | No | Swap file size |
| `--proxy` | — | No | `host:port:user:pass` — repeatable |

---

## Running Multiple Sellers on One VM

Each seller gets a completely isolated stack:

| Resource | Pattern |
|---|---|
| Docker container | `{seller}-chrome` |
| App directory | `/opt/{seller}-browser/` |
| Nginx vhost | `/etc/nginx/sites-available/{seller}-chrome` |
| htpasswd file | `/etc/nginx/htpasswd/{seller}` |
| Proxy config | `/opt/{seller}-browser/proxy/proxies.conf` |
| Cron jobs | tagged with seller name |

```bash
# Seller 1 — port 3000
... | bash -s -- --seller seller1 --port 3000 --pass pass1 --subdomain s1.ex.com

# Seller 2 — port 3001
... | bash -s -- --seller seller2 --port 3001 --pass pass2 --subdomain s2.ex.com

# Seller 3 — port 3002, with proxy
... | bash -s -- --seller seller3 --port 3002 --pass pass3 --subdomain s3.ex.com \
      --proxy "1.2.3.4:8080:u:p"
```

---

## Proxy System

Proxy support is **opt-in** — only active when `--proxy` is passed.

**Proxy format:** `host:port:username:password`

### How auto-failover works

1. At install time, each proxy is tested. The first alive one becomes active.
2. A cron job runs **every 10 minutes** and tests the active proxy.
3. If the active proxy is dead, it scans the list and switches to the next alive proxy.
4. The Docker container is restarted with the new proxy automatically.
5. Logs written to `/opt/{seller}-browser/logs/proxy-health.log`.

### Proxy helper commands

```bash
# Check proxy status
/opt/seller1-browser/proxy-status.sh

# Manually rotate to next alive proxy
/opt/seller1-browser/proxy-rotate.sh
```

---

## What Gets Installed

### Chrome VM (`chrome-setup/setup.sh`)
- Docker + Docker Compose
- Swap file
- `lscr.io/linuxserver/chromium` container
- Helper scripts in `/opt/{seller}-browser/`
- Cron: health check (5 min), log cleanup (daily 06:15 IST), reboot cleanup, weekly update

### Nginx (`nginx-setup/nginx.sh`)
- Reverse proxy → `localhost:{PORT}`
- WebSocket pass-through (required for KasmVNC/noVNC)
- Per-seller Basic Auth via htpasswd
- `/healthz` endpoint (no auth) for uptime monitoring
- Auto SSL via Certbot if DNS already points here

### Proxy (`proxy-setup/proxy.sh`) *(optional)*
- Saves all proxies to `proxies.conf`
- Tests each proxy and sets the first alive one as active
- Generates `proxy-status.sh` and `proxy-rotate.sh`
- Cron: proxy health + auto-failover every 10 min

---

## Cron Jobs (per seller)

| Schedule | Job |
|---|---|
| Every 5 min | Container health check — restart if down |
| Every 10 min | Proxy health check + auto-failover (only if proxy enabled) |
| Daily 06:15 AM IST | Clear Docker logs, journal, Nginx logs, APT cache |
| On reboot (+2 min) | Log cleanup |
| Sunday 02:00 AM IST | Pull latest image + recreate container |

---

## Helper Scripts (per seller)

Located in `/opt/{seller}-browser/`:

| Script | Action |
|---|---|
| `start.sh` | Start container |
| `stop.sh` | Stop container |
| `restart.sh` | Restart container |
| `logs.sh` | Follow container logs |
| `status.sh` | Container + resource usage |
| `update.sh` | Pull latest image + recreate |
| `proxy-status.sh` | All proxy alive/dead status *(proxy only)* |
| `proxy-rotate.sh` | Manually rotate to next alive proxy *(proxy only)* |

## Fleet-wide Scripts

Located in `scripts/` (or install globally):

```bash
bash scripts/list-sellers.sh    # all sellers + status
bash scripts/health-all.sh      # health + resource overview
bash scripts/update-all.sh      # update all seller containers
```

---

## SSL / HTTPS

SSL is attempted automatically if DNS already points here.

If you point DNS **after** installation:
```bash
certbot --nginx -d seller1.yourdomain.com --redirect
```

---

## Uninstall

Remove one seller cleanly (does not touch others):

```bash
curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/uninstall.sh \
  | bash -s -- --seller seller1
```

What gets removed: container, app directory, cron jobs, Nginx config, htpasswd, logs.

---

## Requirements

- Debian 12 or Ubuntu 22.04 / 24.04 (64-bit)
- Root access
- Open firewall ports: **80**, **443**, and your Chromium port(s)
- Domain DNS A-record pointing to server IP (for SSL)

---

## License

MIT
