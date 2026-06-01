# Release and Deployment Checklist

Use this checklist when deploying a new VM, upgrading an existing installation, or testing a release.

---

## A. Pre-Push Checks (run before every GitHub push)

```bash
# No vendor/copyright-sensitive terms
grep -R "indiamart" . --include="*.sh" --include="*.js" --include="*.md" --include="*.yml" || echo "CLEAN"

# No secrets, credentials, or runtime files tracked
git ls-files | grep -E "\.env$|proxy\.env|\.log$|profile/|backups/" || echo "NONE"

# Shell script syntax
bash -n install.sh setup.sh nginx.sh proxy.sh uninstall.sh health-all.sh update-all.sh list-sellers.sh api/install-service.sh

# Node.js syntax
node -c api/src/server.js
node -c api/src/config.js
node -c api/src/exec.js
node -c api/src/fleetService.js
node -c api/src/monitoringService.js
node -c api/src/validators.js
node -c api/src/sessions.js
node -c api/src/events.js
node -c api/src/webhook.js
```

All commands must exit 0 with no output (shell) or `OK` (node) before pushing.

---

## B. Pre-Install Checks

- [ ] VM is running Debian 12 or Ubuntu 22.04/24.04 (64-bit).
- [ ] Root or sudo access confirmed.
- [ ] Ports 80 and 443 open in firewall.
- [ ] DNS A record for target subdomain points to VM public IP.
- [ ] Port 8787 blocked from public internet (firewall rule in place).
- [ ] `api/.env` created from `api/.env.example` with all secrets filled in.
- [ ] `JWT_SECRET` and `REFRESH_TOKEN_SECRET` are unique, random (64+ chars).
- [ ] `AUTH_USERNAME` and `AUTH_PASSWORD` set to strong values.
- [ ] `CORS_ORIGINS` set to frontend domain(s), not localhost.

---

## C. Fresh VM Install Tests

### C1. No-Proxy Install Test

```bash
curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/install.sh \
  | bash -s -- \
      --seller test-no-proxy \
      --port 3000 \
      --user admin \
      --pass "TestPass123!" \
      --subdomain chrome1.yourdomain.com
```

Verify:
- [ ] No errors during install.
- [ ] `docker ps | grep test-no-proxy-chrome` shows container running.
- [ ] `cat /opt/test-no-proxy-browser/docker-compose.yml | grep HTTP_PROXY` returns nothing (no proxy creds in YAML).
- [ ] `cat /opt/test-no-proxy-browser/proxy.env` is empty or absent.
- [ ] Open `http://chrome1.yourdomain.com` → Nginx basic auth prompt appears.
- [ ] Login with admin/TestPass123! → Chromium loads.

---

### C2. One-Proxy Install Test

```bash
curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/install.sh \
  | bash -s -- \
      --seller test-one-proxy \
      --port 3001 \
      --user admin \
      --pass "TestPass123!" \
      --subdomain chrome2.yourdomain.com \
      --proxy "1.2.3.4:8080:proxyuser:proxypass"
```

Verify:
- [ ] No errors during install.
- [ ] `cat /opt/test-one-proxy-browser/proxy.env` contains `HTTP_PROXY=http://proxyuser:...` (credentials present).
- [ ] `stat -c "%a %U:%G" /opt/test-one-proxy-browser/proxy.env` shows `600 root:root`.
- [ ] `cat /opt/test-one-proxy-browser/docker-compose.yml | grep proxypass` returns nothing (creds NOT in YAML).
- [ ] `cat /opt/test-one-proxy-browser/docker-compose.yml | grep env_file` shows `env_file` directive present.
- [ ] Container is running and browser accessible.

---

### C3. Multi-Proxy Failover Test

```bash
curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/install.sh \
  | bash -s -- \
      --seller test-multi-proxy \
      --port 3002 \
      --user admin \
      --pass "TestPass123!" \
      --subdomain chrome3.yourdomain.com \
      --proxy "1.2.3.4:8080:user1:pass1" \
      --proxy "5.6.7.8:8080:user2:pass2"
```

Verify:
- [ ] `cat /opt/test-multi-proxy-browser/proxy/proxies.conf` contains both proxy entries.
- [ ] `cat /opt/test-multi-proxy-browser/proxy/active.conf` contains one active proxy (host:port only visible).
- [ ] `cat /opt/test-multi-proxy-browser/proxy.env` contains one proxy (the active one).
- [ ] Kill the active proxy (disable it) and wait for next health check (10 min), or trigger manually:
  ```bash
  /opt/test-multi-proxy-browser/proxy-rotate.sh
  ```
- [ ] `cat /opt/test-multi-proxy-browser/proxy/active.conf` shows different proxy after rotation.
- [ ] Browser still accessible after rotation.
- [ ] No proxy passwords visible in any log file:
  ```bash
  grep -r "pass1\|pass2" /opt/test-multi-proxy-browser/logs/
  ```

---

## D. API Docker Tests

```bash
# On the VM, from the repo root:
cp api/.env.example api/.env
# Edit api/.env — fill in secrets, CORS_ORIGINS, etc.
sudo bash api/install-service.sh --docker
```

Verify:
- [ ] `docker ps | grep fleet-api` shows API container running.
- [ ] `docker compose -f docker-compose.fleet.yml logs api | tail -5` shows listening message.
- [ ] `curl -s http://127.0.0.1:8787/healthz` returns `{"ok":true,...}`.
- [ ] `curl -s -X POST http://127.0.0.1:8787/api/v1/auth/login -H "Content-Type: application/json" -d '{"username":"admin","password":"wrong"}' | jq .error` returns `"Invalid username or password"`.
- [ ] Login with correct credentials returns `accessToken` and `refreshToken`.
- [ ] `GET /api/v1/sellers` with Bearer token returns seller list.
- [ ] `POST /api/v1/sellers` returns `501` (Docker mode, install disabled). _(Only when `FLEET_ROOT` is set.)_
- [ ] `GET /api/v1/monitor/overview` returns VM and fleet stats.

---

## E. Nginx Tests

Verify:
- [ ] DNS A record for subdomain points to VM IP.
- [ ] `nginx -t` passes (Nginx config is valid).
- [ ] HTTP → HTTPS redirect works: `curl -I http://chrome1.yourdomain.com` returns `301`.
- [ ] HTTPS accessible: `curl -I https://chrome1.yourdomain.com` returns `401` (basic auth required — correct).
- [ ] SSL cert valid: `curl -v https://chrome1.yourdomain.com 2>&1 | grep "subject\|expire"`.
- [ ] Certbot renewal dry run passes: `certbot renew --dry-run`.
- [ ] Nginx reload after cert renewal works: `systemctl reload nginx && systemctl is-active nginx`.

---

## F. VM Reboot Tests

Assumption: VM is scheduled to stop at 18:30 UTC and start at 00:30 UTC daily.

Verify:
- [ ] Configure cloud scheduler to stop VM at 18:30 UTC, start at 00:30 UTC.
- [ ] Stop VM (or wait for schedule).
- [ ] Start VM (or wait for schedule).
- [ ] After VM starts, wait 90–120 seconds.
- [ ] `docker ps | grep -chrome` shows all Chrome containers are running.
- [ ] `tail /opt/<seller>-browser/logs/health.log` shows `@reboot` health check fired.
- [ ] No cron jobs are scheduled to run between 18:30 UTC and 00:30 UTC (verify with `crontab -l -u root`).

---

### F1. Browser Session Persistence Test

After VM stop/start:
- [ ] Open browser subdomain in a browser tab.
- [ ] You are still logged into the target website — no re-login required.
- [ ] Browser tabs from previous session are restored.
- [ ] Installed Chrome extensions are still present.
- [ ] `ls -la /opt/<seller>-browser/profile/chromium/` shows session files with recent timestamps.

---

## G. Production Checks

### G1. Proxy Tests

Via API (requires JWT token):
```bash
TOKEN="<your-access-token>"
curl -s -X POST https://chrome1.yourdomain.com/api/v1/sellers/test-multi-proxy/actions/proxy-rotate \
  -H "Authorization: Bearer $TOKEN" | jq .
```

Verify:
- [ ] Response shows `action: "proxy-rotate"` with stdout output.
- [ ] `cat /opt/test-multi-proxy-browser/proxy/active.conf` changed to new proxy.
- [ ] `cat /opt/test-multi-proxy-browser/proxy.env` updated to new proxy credentials.
- [ ] Chrome container restarted with new proxy: `docker ps | grep test-multi-proxy-chrome` shows `Up X seconds`.
- [ ] Browser still accessible after restart.

Proxy live test via API:
```bash
curl -s https://chrome1.yourdomain.com/api/v1/sellers/test-multi-proxy/proxies/test \
  -H "Authorization: Bearer $TOKEN" | jq .
```
- [ ] Response includes `alive: true/false` and `latencyMs` per proxy.

---

### G2. Frontend Endpoint Smoke Test

Using the API with a valid JWT token, verify these endpoints return non-error responses:

```bash
BASE="https://chrome1.yourdomain.com"
TOKEN="<your-access-token>"

curl -s "$BASE/healthz" | jq .ok
curl -s "$BASE/api/v1/meta" -H "Authorization: Bearer $TOKEN" | jq .service
curl -s "$BASE/api/v1/monitor/overview" -H "Authorization: Bearer $TOKEN" | jq .health.overall
curl -s "$BASE/api/v1/monitor/vm" -H "Authorization: Bearer $TOKEN" | jq .vm.cpuCores
curl -s "$BASE/api/v1/sellers" -H "Authorization: Bearer $TOKEN" | jq .count
curl -s "$BASE/api/v1/sellers/test-no-proxy" -H "Authorization: Bearer $TOKEN" | jq .running
curl -s "$BASE/api/v1/sellers/test-no-proxy/events" -H "Authorization: Bearer $TOKEN" | jq .count
curl -s "$BASE/api/v1/sellers/test-multi-proxy/proxies" -H "Authorization: Bearer $TOKEN" | jq .count
```

Verify:
- [ ] All return HTTP 200 with valid JSON.
- [ ] No response contains `stderr`, `stdout`, `args`, or internal filesystem paths.
- [ ] SSE stream connects: `curl -N "$BASE/api/v1/monitor/stream" -H "Authorization: Bearer $TOKEN"` → receives `event: ready` then `event: overview`.
- [ ] Rate limit test: send 21 auth requests in 15 minutes → 21st returns `429`.

---

### G3. Security Verification

- [ ] `grep -r "indiamart" . --include="*.sh" --include="*.md" --include="*.js"` → no results.
- [ ] `grep HTTP_PROXY /opt/<seller>-browser/docker-compose.yml` → no results (credentials not in YAML).
- [ ] `stat -c "%a" /opt/<seller>-browser/proxy.env` → `600`.
- [ ] `stat -c "%a" /etc/nginx/htpasswd/<seller>` → `640`.
- [ ] `stat -c "%a" /etc/nginx/htpasswd/` → `750`.
- [ ] Port 8787 not accessible from internet (test from external host).
- [ ] `api/.env` not committed: `git status api/.env` → shows it as ignored.
- [ ] `curl -s http://YOURVM_IP:8787/healthz` → connection refused or timeout from public internet.
- [ ] `ALLOW_INSTALL=false` and `ALLOW_UNINSTALL=false` confirmed in `api/.env`.
- [ ] `ALLOW_DESTRUCTIVE_ACTIONS=false` confirmed in `api/.env`.
- [ ] SSH restricted to trusted IPs (not `0.0.0.0/0`) in firewall/cloud VPC rules.
- [ ] Strong `JWT_SECRET` and `REFRESH_TOKEN_SECRET` set (not `.env.example` defaults).
- [ ] `CORS_ORIGINS` set to actual production frontend domain (not localhost).
