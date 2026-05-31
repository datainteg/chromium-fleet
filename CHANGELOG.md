# Changelog

All notable changes to `chromium-fleet` are documented here.

Format: [Semantic Versioning](https://semver.org). Types: `Added`, `Changed`, `Fixed`, `Security`, `Removed`.

---

## [0.1.0] — 2026-06-01

### Added

**Core infrastructure**
- Per-seller Chromium Docker containers using `lscr.io/linuxserver/chromium`.
- Browser profile bind-mounted at `/opt/<seller>-browser/profile` — persists login sessions, cookies, extensions, and tabs across VM stop/start and container restarts.
- `install.sh` one-command installer with `--seller`, `--port`, `--subdomain`, `--pass`, `--proxy` flags.
- `setup.sh` — Docker container setup, swap, sysctl tuning, cron jobs, helper scripts.
- `nginx.sh` — Nginx reverse proxy with WebSocket headers, basic auth (htpasswd), per-seller subdomains, optional Let's Encrypt SSL via certbot.
- `proxy.sh` — Proxy pool setup with health check, auto-failover cron (every 10 min), `proxy-rotate.sh`, `proxy-status.sh`.
- `uninstall.sh` — Clean removal of one seller without affecting others.
- `list-sellers.sh`, `health-all.sh`, `update-all.sh` — fleet-level ops scripts.
- Per-seller helper scripts: `start.sh`, `stop.sh`, `restart.sh`, `recreate.sh`, `update.sh`, `status.sh`, `logs.sh`.
- Daily profile backup at 02:00 UTC — tar.gz of `./profile`, last 3 days kept.
- Docker `HEALTHCHECK` on all Chrome containers.
- VM stop/start aware cron schedule (designed for 12 AM–6 AM IST downtime window).
- `@reboot` auto-resume of Chrome containers after VM start.

**Node.js REST API (`api/`)**
- JWT auth: `POST /api/v1/auth/login`, `/auth/refresh` (token rotation), `/auth/logout`.
- Persistent refresh token store (`sessions.js`) backed by JSON file — survives API restarts.
- Rate limiting: auth (20 req/15min), API-wide (200 req/min), SSE per-IP (3 concurrent).
- Global error sanitization — no stderr/paths/args leaked to clients.
- `GET /api/v1/monitor/overview` — cached VM + fleet health snapshot.
- `GET /api/v1/monitor/vm` — CPU, RAM, disk, swap.
- `GET /api/v1/monitor/fleet` — all sellers with Docker container stats.
- `GET /api/v1/monitor/stream` — live SSE stream for frontend dashboard.
- `GET /api/v1/sellers` — list all sellers with Docker state (parallel fetch).
- `GET /api/v1/sellers/:seller` — single seller detail.
- `POST /api/v1/sellers` — create seller (host-mode only, 501 in Docker API mode).
- `DELETE /api/v1/sellers/:seller` — remove seller (host-mode only).
- `POST /api/v1/sellers/:seller/actions/:action` — lifecycle actions.
- `POST /api/v1/sellers/actions/:action` — fleet-wide bulk action (concurrency 3).
- `POST /api/v1/sellers/:seller/resume`, `POST /api/v1/sellers/resume-all`.
- `GET/POST/DELETE /api/v1/sellers/:seller/proxies` — proxy pool CRUD (passwords always masked).
- `GET /api/v1/sellers/:seller/proxies/test` — parallel live proxy health test.
- `GET /api/v1/sellers/:seller/logs` — Docker container logs.
- `GET /api/v1/sellers/:seller/events` — crash/recovery event log (ring buffer, last 50).
- `GET /api/v1/sellers/:seller/config` — seller config export (subdomain, port, proxy pool).
- `GET/DELETE /api/v1/sellers/:seller/extensions` — extension management.
- `GET /api/v1/sellers/:seller/backups` — list profile backups.
- `POST /api/v1/sellers/:seller/restore/:filename` — restore profile from backup.
- `POST /api/v1/webhook/test` — fire test payload to configured WEBHOOK_URL.
- `GET /healthz` — health check including Docker connectivity status.
- Background state watcher — detects container crashes, fires webhook, records events.
- Webhook crash/recovery alerts (Discord, Slack, any HTTP endpoint).

**Security**
- Proxy credentials stored in `proxy.env` (chmod 600) — never in `docker-compose.yml`.
- Backward-compatible migration: `set-proxy-env.sh` removes legacy YAML credentials on next proxy rotation.
- htpasswd created atomically via temp file + umask 077, no world-readable window.
- SSE payload cap (2MB per event), hourly quota (100MB per connection).
- `ALLOW_INSTALL=false` / `ALLOW_UNINSTALL=false` flags for lockdown after provisioning.
- Docker API mode: `POST /api/v1/sellers` and `DELETE /api/v1/sellers/:seller` return `501`.
- `trust proxy 1` for accurate IP-based rate limiting behind Nginx.

**Docker**
- `api/Dockerfile` — Node 20 Alpine + bash + curl + docker-cli.
- `docker-compose.fleet.yml` — API as Docker service, mounts docker.sock + /opt + /fleet.
- `api/install-service.sh` — `--docker` flag for Docker mode, no flag for systemd.

**Documentation**
- `README.md` — quick start, architecture diagram, parameters table, API overview.
- `api/README.md` — deployment, auth flow, production .env recommendations, endpoint map.
- `api/API_REFERENCE.md` — full reference with request/response examples and curl commands.
- `SECURITY.md` — vulnerability reporting, docker.sock risk, firewall rules, secret requirements.
- `RELEASE_CHECKLIST.md` — 10-section deployment verification checklist.

### Security

- Proxy credentials isolated to `proxy.env` (chmod 600). Previously written into `docker-compose.yml` (exposed via `docker inspect` and file reads).
- API error responses sanitized — no internal details exposed to clients.
- Auth endpoint rate limiting (20 req / 15 min per IP).
- Global API rate limiting (200 req / 1 min per IP).
- SSE per-IP connection limit, payload cap, hourly quota.
- htpasswd created atomically with no world-readable window.
