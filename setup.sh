#!/bin/bash
# =============================================================
# chrome-setup/setup.sh
# Called by install.sh — all config via env vars.
#
# ── How session persistence works ────────────────────────────
#
#  The GCP VM is stopped/started on a schedule you control.
#  When the VM starts again, Docker auto-starts the container
#  (restart: unless-stopped). Chrome opens with the seller
#  still logged into indiamart.com — no popup, no re-login.
#
#  This works because:
#
#  1. ./profile is a bind-mount → /config inside the container.
#     LinuxServer Chromium stores EVERYTHING here:
#       • Login cookies (indiamart, any other site)
#       • localStorage / sessionStorage
#       • Extension data & state
#       • Open tabs (Last Session / Last Tabs files)
#       • Saved passwords, autofill
#     The bind-mount lives on the VM disk, not inside Docker.
#     It survives VM stop/start, container stop/start, even
#     container deletion (docker rm).
#
#  2. restart: unless-stopped → Docker daemon brings the
#     container back automatically when the VM boots.
#     No cron, no systemd unit, no manual start needed.
#
#  3. CHROME_CLI flags:
#     --restore-last-session       → reopen all tabs on boot
#     --disable-session-crashed-bubble → no "Chrome didn't
#       shut down correctly" popup (clean VM stop looks like
#       a crash to Chrome; this suppresses the nag)
#     --no-first-run               → skip setup wizard
#
#  4. stop_grace_period: 30s → Docker sends SIGTERM and waits
#     30 seconds before SIGKILL. Chrome uses this time to
#     flush cookies and session files to disk. Without this,
#     a forced VM shutdown might not save the last session.
#
#  5. Health check uses `docker compose start` (NOT up -d)
#     when the container exists but is stopped — this resumes
#     the exact container without recreating it, so the
#     writable layer is also preserved.
#
#  ── What to do once, manually ────────────────────────────────
#  After first install:
#    1. Open http://your-subdomain in browser
#    2. Log into indiamart.com as the seller
#    3. Install any Chrome extensions you need
#    4. Done — from this point, VM stop/start preserves everything.
# =============================================================
set -euo pipefail

# ─── Config ──────────────────────────────────────────────────
SELLER_NAME="${SELLER_NAME:-seller1}"
APP_DIR="/opt/${SELLER_NAME}-browser"
CHROME_PORT="${CHROME_PORT:-3000}"
CHROME_USER="${CHROME_USER:-admin}"
CHROME_PASS="${CHROME_PASS:?CHROME_PASS env var is required}"
TZ_NAME="${TZ_NAME:-Asia/Kolkata}"
MEM_LIMIT="${MEM_LIMIT:-3g}"
CPU_LIMIT="${CPU_LIMIT:-1.5}"
SHM_SIZE="${SHM_SIZE:-2gb}"
SWAP_SIZE="${SWAP_SIZE:-4G}"
PROXY_LIST="${PROXY_LIST:-}"

echo ""
echo "======================================"
echo " [chrome-setup] $SELLER_NAME"
echo " App dir : $APP_DIR"
echo " Port    : $CHROME_PORT"
echo "======================================"
echo ""

# ─── [1] System update ───────────────────────────────────────
echo "[1/9] Updating system packages..."
apt-get update -y -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

# ─── [2] Install dependencies ────────────────────────────────
echo "[2/9] Installing packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  docker.io \
  docker-compose-plugin \
  nginx \
  apache2-utils \
  curl \
  wget \
  nano \
  htop \
  unzip \
  cron \
  ca-certificates \
  gnupg \
  lsb-release \
  certbot \
  python3-certbot-nginx \
  redsocks \
  iptables \
  net-tools

# ─── [3] Enable services ─────────────────────────────────────
echo "[3/9] Enabling services..."
systemctl enable --now docker
systemctl enable --now nginx
systemctl enable --now cron

# ─── [4] Swap ────────────────────────────────────────────────
echo "[4/9] Configuring swap..."
if [ ! -f /swapfile ]; then
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "  Swap created: $SWAP_SIZE"
else
  echo "  Swap already exists — skipping."
fi

# ─── [5] Directories ─────────────────────────────────────────
echo "[5/9] Creating directories..."
mkdir -p "$APP_DIR"/{profile,extensions,logs,proxy}

# profile/chromium must be owned by PUID=1000 so Chrome can
# write cookies and session files during a clean shutdown.
# Without this, the "last session" file may not be saved when
# the VM is stopped, causing a re-login on next boot.
mkdir -p "$APP_DIR/profile/chromium"
chown -R 1000:1000 "$APP_DIR/profile"

# ─── [6] Resolve active proxy ────────────────────────────────
PROXY_ENV_BLOCK=""

if [[ -n "$PROXY_LIST" ]]; then
  echo "[6/9] Detecting active proxy..."
  while IFS= read -r LINE; do
    [[ -z "$LINE" ]] && continue
    P_HOST="$(echo "$LINE" | cut -d: -f1)"
    P_PORT="$(echo "$LINE" | cut -d: -f2)"
    P_USER="$(echo "$LINE" | cut -d: -f3)"
    P_PASS="$(echo "$LINE" | cut -d: -f4)"
    if curl -fsSL --max-time 4 \
        --proxy "http://${P_USER}:${P_PASS}@${P_HOST}:${P_PORT}" \
        https://api.ipify.org &>/dev/null; then
      echo "  Active proxy: $P_HOST:$P_PORT"
      PROXY_ENV_BLOCK="
      - HTTP_PROXY=http://${P_USER}:${P_PASS}@${P_HOST}:${P_PORT}
      - HTTPS_PROXY=http://${P_USER}:${P_PASS}@${P_HOST}:${P_PORT}
      - http_proxy=http://${P_USER}:${P_PASS}@${P_HOST}:${P_PORT}
      - https_proxy=http://${P_USER}:${P_PASS}@${P_HOST}:${P_PORT}
      - NO_PROXY=localhost,127.0.0.1"
      break
    else
      echo "  Dead proxy: $P_HOST:$P_PORT — skipping"
    fi
  done <<< "$PROXY_LIST"
  [[ -z "$PROXY_ENV_BLOCK" ]] && echo "  WARNING: All proxies unreachable — starting without proxy."
else
  echo "[6/9] No proxy configured — skipping."
fi

# ─── [7] docker-compose.yml ──────────────────────────────────
echo "[7/9] Writing docker-compose.yml..."
cat > "$APP_DIR/docker-compose.yml" <<COMPOSE
# chromium-fleet — ${SELLER_NAME}
# Do not edit manually. Re-run install.sh to regenerate.
#
# SESSION PERSISTENCE GUARANTEE:
#   ./profile bind-mount holds all Chrome state on the VM disk.
#   It survives: VM stop/start · container stop/start · docker rm.
#   restart: unless-stopped auto-starts on VM boot (no cron needed).

services:
  chrome:
    image: lscr.io/linuxserver/chromium:latest
    container_name: ${SELLER_NAME}-chrome

    ports:
      - "${CHROME_PORT}:3000"

    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TZ_NAME}
      - CHROME_CLI=--restore-last-session --disable-session-crashed-bubble --no-first-run --disable-translate${PROXY_ENV_BLOCK}

    volumes:
      # ALL Chrome state lives here on the VM disk:
      # cookies, logins, extensions, tabs, localStorage, passwords.
      - ./profile:/config
      # Drop .crx / unpacked extension folders here.
      # Install them once in Chrome; they persist in ./profile after that.
      - ./extensions:/extensions:ro

    shm_size: "${SHM_SIZE}"
    mem_limit: "${MEM_LIMIT}"
    cpus: "${CPU_LIMIT}"

    # Auto-start on VM boot. Docker daemon starts this container
    # the moment the Docker service comes up after a VM start.
    restart: unless-stopped

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

    # Give Chrome 30 seconds to flush cookies + session to disk
    # before the container is killed on VM shutdown.
    # This is what keeps you logged in after a VM stop/start.
    stop_grace_period: 30s
COMPOSE

# ─── [8] Helper scripts ──────────────────────────────────────
echo "[8/9] Writing helper scripts..."

# start.sh — safe resume, never wipes session
cat > "$APP_DIR/start.sh" <<'SH'
#!/bin/bash
# Resume the Chromium container, preserving all session state.
# Uses `docker compose start` when container exists (state kept).
# Falls back to `docker compose up -d` only if container is gone.
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"
LOG="$APP_DIR/logs/lifecycle.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
CONTAINER="$(grep 'container_name:' docker-compose.yml | awk '{print $2}')"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "$TS | START  | Resuming existing container (session preserved)..." >> "$LOG"
  docker compose start
else
  echo "$TS | CREATE | Container not found — creating fresh..." >> "$LOG"
  docker compose up -d
fi
echo "$TS | OK     | Chrome is running." >> "$LOG"
echo "Chrome started. Session preserved."
SH

# stop.sh — graceful stop, never removes container
cat > "$APP_DIR/stop.sh" <<'SH'
#!/bin/bash
# Gracefully stop Chrome. Session state stays in ./profile.
# Container is NOT removed — start.sh resumes exactly where you left off.
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"
LOG="$APP_DIR/logs/lifecycle.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
echo "$TS | STOP   | Graceful stop (30s flush)..." >> "$LOG"
docker compose stop     # honours stop_grace_period: 30s
echo "$TS | OK     | Stopped. Login session preserved in ./profile" >> "$LOG"
echo "Chrome stopped. Run start.sh to resume — you will still be logged in."
SH

# restart.sh — stop then start (no recreate)
cat > "$APP_DIR/restart.sh" <<'SH'
#!/bin/bash
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"
LOG="$APP_DIR/logs/lifecycle.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
echo "$TS | RESTART| Stopping..." >> "$LOG"
docker compose stop
echo "$TS | RESTART| Starting..." >> "$LOG"
docker compose start
echo "$TS | OK     | Restarted. Session preserved." >> "$LOG"
echo "Chrome restarted. Session preserved."
SH

# recreate.sh — full container recreation (e.g. after proxy/config change)
# Session still preserved because ./profile is a bind-mount on the VM disk.
cat > "$APP_DIR/recreate.sh" <<'SH'
#!/bin/bash
# Recreate the container (e.g. after changing proxy or pulling a new image).
# Your login session and extensions are safe — they live in ./profile,
# not inside the container.
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"
LOG="$APP_DIR/logs/lifecycle.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
echo "$TS | RECREATE| Full container recreate. Session in ./profile is safe..." >> "$LOG"
docker compose up -d --force-recreate
echo "$TS | OK      | Recreated. Session preserved." >> "$LOG"
echo "Container recreated. You are still logged in."
SH

# update.sh — pull latest image + recreate (session safe)
cat > "$APP_DIR/update.sh" <<'SH'
#!/bin/bash
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"
LOG="$APP_DIR/logs/lifecycle.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
echo "$TS | UPDATE | Pulling latest Chromium image..." >> "$LOG"
docker compose pull -q
docker compose up -d --force-recreate
echo "$TS | OK     | Updated. Session preserved." >> "$LOG"
echo "Updated. You are still logged in."
SH

# logs.sh
cat > "$APP_DIR/logs.sh" <<'SH'
#!/bin/bash
cd "$(dirname "$0")"
docker compose logs -f
SH

# status.sh
cat > "$APP_DIR/status.sh" <<SH
#!/bin/bash
echo "╔══════════════════════════════════════════╗"
echo "  ${SELLER_NAME} — Chrome Status"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "── Container ────────────────────────────────"
docker ps -a --filter "name=${SELLER_NAME}-chrome" \\
  --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "── Resource Usage ───────────────────────────"
docker stats --no-stream \\
  --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" \\
  ${SELLER_NAME}-chrome 2>/dev/null || echo "  (container not running)"
echo ""
echo "── Session State ────────────────────────────"
PROFILE_SIZE="\$(du -sh "$APP_DIR/profile" 2>/dev/null | cut -f1)"
echo "  Profile size : \$PROFILE_SIZE   ($APP_DIR/profile)"
echo "  Extensions   : \$(find "$APP_DIR/extensions" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l) items in ./extensions"
echo ""
echo "── Last 8 lifecycle events ──────────────────"
tail -8 "$APP_DIR/logs/lifecycle.log" 2>/dev/null || echo "  (no log yet)"
echo ""
echo "── Disk ─────────────────────────────────────"
du -sh "$APP_DIR"/profile "$APP_DIR"/logs 2>/dev/null
SH

chmod +x "$APP_DIR"/*.sh

# ─── [9] Maintenance scripts + cron ──────────────────────────
echo "[9/9] Writing maintenance scripts and crontab..."

# Health check — smart: uses `start` not `up -d` when container exists
cat > "/usr/local/bin/${SELLER_NAME}-health.sh" <<HEALTH
#!/bin/bash
# Health check for ${SELLER_NAME}-chrome.
# If the container is stopped (e.g. GCP VM just booted and Docker
# hasn't brought it up yet), this starts it while preserving session.
CONTAINER="${SELLER_NAME}-chrome"
APP_DIR="$APP_DIR"
LOG="\$APP_DIR/logs/health.log"
TS="\$(date '+%Y-%m-%d %H:%M:%S')"

# Is the container running?
if docker ps --format '{{.Names}}' | grep -q "^\${CONTAINER}\$"; then
  echo "\$TS | OK    | Running." >> "\$LOG"
else
  # Container exists but stopped → start (session preserved)
  if docker ps -a --format '{{.Names}}' | grep -q "^\${CONTAINER}\$"; then
    echo "\$TS | WARN  | Container stopped — starting (session preserved)..." >> "\$LOG"
    cd "\$APP_DIR" && docker compose start >> "\$LOG" 2>&1
  else
    # Container gone entirely → recreate (session still safe in ./profile)
    echo "\$TS | WARN  | Container missing — recreating (session in ./profile is safe)..." >> "\$LOG"
    cd "\$APP_DIR" && docker compose up -d >> "\$LOG" 2>&1
  fi
  echo "\$TS | INFO  | Start issued." >> "\$LOG"
fi

# Trim log to 500 lines
[ "\$(wc -l < "\$LOG" 2>/dev/null || echo 0)" -gt 500 ] && \
  tail -300 "\$LOG" > "\$LOG.tmp" && mv "\$LOG.tmp" "\$LOG"
HEALTH

# Log cleanup
cat > "/usr/local/bin/${SELLER_NAME}-clear-logs.sh" <<CLEANUP
#!/bin/bash
LOG="$APP_DIR/logs/cleanup.log"
TS="\$(date '+%Y-%m-%d %H:%M:%S')"
echo "\$TS | START | Log cleanup..." >> "\$LOG"

# Truncate Docker JSON log files
find /var/lib/docker/containers/ -type f -name "*.log" \
  -exec truncate -s 0 {} \; 2>/dev/null || true

# Remove dangling Docker resources (never touches running containers or images)
docker container prune -f >/dev/null 2>&1 || true
docker image     prune -f >/dev/null 2>&1 || true
docker builder   prune -f >/dev/null 2>&1 || true
docker volume    prune -f >/dev/null 2>&1 || true

# Trim systemd journal
journalctl --vacuum-time=2d >/dev/null 2>&1 || true

# Trim per-seller Nginx logs if >50MB
for F in /var/log/nginx/${SELLER_NAME}-chrome-access.log \
         /var/log/nginx/${SELLER_NAME}-chrome-error.log; do
  if [ -f "\$F" ] && [ "\$(du -sm "\$F" | cut -f1)" -gt 50 ]; then
    truncate -s 0 "\$F"
    echo "\$TS | INFO  | Truncated \$F" >> "\$LOG"
  fi
done

apt-get clean >/dev/null 2>&1 || true
echo "\$TS | DONE  | Complete." >> "\$LOG"

[ "\$(wc -l < "\$LOG" 2>/dev/null || echo 0)" -gt 200 ] && \
  tail -100 "\$LOG" > "\$LOG.tmp" && mv "\$LOG.tmp" "\$LOG"
CLEANUP

chmod +x \
  "/usr/local/bin/${SELLER_NAME}-health.sh" \
  "/usr/local/bin/${SELLER_NAME}-clear-logs.sh"

# ── Crontab ───────────────────────────────────────────────────
CRON_TMP="/tmp/${SELLER_NAME}_crontab"
crontab -l -u root 2>/dev/null \
  | grep -v "# ── ${SELLER_NAME}" \
  | grep -v "${SELLER_NAME}-health" \
  | grep -v "${SELLER_NAME}-clear-logs" \
  | grep -v "${SELLER_NAME}-proxy-health" \
  > "$CRON_TMP" || true

cat >> "$CRON_TMP" <<CRON

# ── ${SELLER_NAME}: container health every 5 min ────────────────────────
*/5 * * * * /usr/local/bin/${SELLER_NAME}-health.sh >/dev/null 2>&1

# ── ${SELLER_NAME}: clear logs daily at 00:15 UTC (05:45 IST) ───────────
15 0 * * * /usr/local/bin/${SELLER_NAME}-clear-logs.sh >/dev/null 2>&1

# ── ${SELLER_NAME}: clear logs 3 min after VM boot ──────────────────────
@reboot sleep 180 && /usr/local/bin/${SELLER_NAME}-clear-logs.sh >/dev/null 2>&1

# ── ${SELLER_NAME}: weekly image update Sun 21:00 UTC (02:30 IST Mon) ───
0 21 * * 6 cd ${APP_DIR} && docker compose pull -q && docker compose up -d --force-recreate >/dev/null 2>&1
CRON

crontab -u root "$CRON_TMP"
rm -f "$CRON_TMP"

# ─── Pull and start container ────────────────────────────────
echo ""
echo "Pulling and starting Chromium container..."
cd "$APP_DIR"
docker compose pull -q
docker compose up -d

echo ""
echo "======================================"
echo " [chrome-setup] done: ${SELLER_NAME}"
echo " Local : http://localhost:${CHROME_PORT}"
echo ""
echo " NEXT STEP:"
echo "  1. Open http://your-subdomain in your browser"
echo "  2. Log into indiamart.com as the seller"
echo "  3. Install any Chrome extensions you need"
echo "  4. Done — VM stop/start will keep you logged in"
echo "======================================"
