#!/bin/bash
# =============================================================
# proxy-setup/proxy.sh
# Manages proxy list, health checking, and auto-failover.
# Only called by install.sh when --proxy flags are provided.
#
# Proxy format: host:port:user:pass
# The container is restarted with the next working proxy
# whenever the active one goes dead.
# =============================================================
set -euo pipefail

SELLER_NAME="${SELLER_NAME:-seller1}"
APP_DIR="${APP_DIR:-/opt/${SELLER_NAME}-browser}"
PROXY_LIST="${PROXY_LIST:-}"   # newline-separated "host:port:user:pass"
PROXY_DIR="$APP_DIR/proxy"
PROXY_CONF="$PROXY_DIR/proxies.conf"
ACTIVE_FILE="$PROXY_DIR/active.conf"
PROXY_LOG="$APP_DIR/logs/proxy-health.log"

echo ""
echo "======================================"
echo " [proxy-setup] $SELLER_NAME"
echo "======================================"
echo ""

mkdir -p "$PROXY_DIR" "$APP_DIR/logs"

# ─── Save proxy list to file ─────────────────────────────────
echo "Writing proxy list → $PROXY_CONF"
: > "$PROXY_CONF"
while IFS= read -r LINE; do
  [[ -z "$LINE" ]] && continue
  echo "$LINE" >> "$PROXY_CONF"
done <<< "$PROXY_LIST"

COUNT="$(grep -c . "$PROXY_CONF" || true)"
echo "  Saved $COUNT proxy entries."

# ─── Proxy health-check helper function ──────────────────────
test_proxy() {
  local HOST="$1" PORT="$2" USER="$3" PASS="$4"
  curl -fsSL --max-time 5 \
    --proxy "http://${USER}:${PASS}@${HOST}:${PORT}" \
    https://api.ipify.org &>/dev/null
}

# ─── Find first alive proxy ──────────────────────────────────
find_active_proxy() {
  while IFS=: read -r H P U W; do
    [[ -z "$H" ]] && continue
    if test_proxy "$H" "$P" "$U" "$W"; then
      echo "${H}:${P}:${U}:${W}"
      return 0
    fi
  done < "$PROXY_CONF"
  return 1
}

echo "Testing proxies..."
ACTIVE="$(find_active_proxy || true)"
if [[ -n "$ACTIVE" ]]; then
  echo "$ACTIVE" > "$ACTIVE_FILE"
  A_HOST="$(echo "$ACTIVE" | cut -d: -f1)"
  A_PORT="$(echo "$ACTIVE" | cut -d: -f2)"
  echo "  Active proxy: $A_HOST:$A_PORT"
else
  echo "  WARNING: No alive proxies found. Will retry on next health check."
  : > "$ACTIVE_FILE"
fi

# ─── proxy-status.sh helper ──────────────────────────────────
cat > "$APP_DIR/proxy-status.sh" <<SH
#!/bin/bash
PROXY_CONF="$PROXY_CONF"
ACTIVE_FILE="$ACTIVE_FILE"

echo "╔══════════════════════════════════════╗"
echo "  ${SELLER_NAME} — Proxy Status"
echo "╚══════════════════════════════════════╝"
echo ""

if [ -s "\$ACTIVE_FILE" ]; then
  ACTIVE="\$(cat "\$ACTIVE_FILE")"
  A_HOST="\$(echo "\$ACTIVE" | cut -d: -f1)"
  A_PORT="\$(echo "\$ACTIVE" | cut -d: -f2)"
  echo "  Active proxy : \$A_HOST:\$A_PORT"
else
  echo "  Active proxy : NONE (all dead or not set)"
fi
echo ""
echo "  All configured proxies:"
IDX=1
while IFS=: read -r H P U W; do
  [ -z "\$H" ] && continue
  if curl -fsSL --max-time 4 --proxy "http://\${U}:\${W}@\${H}:\${P}" \\
      https://api.ipify.org &>/dev/null; then
    STATUS="✓ alive"
  else
    STATUS="✗ dead "
  fi
  echo "    [\$IDX] \$H:\$P — \$STATUS"
  IDX=\$((IDX+1))
done < "\$PROXY_CONF"
echo ""
SH

# ─── proxy-rotate.sh helper (manual rotation) ────────────────
cat > "$APP_DIR/proxy-rotate.sh" <<SH
#!/bin/bash
# Manually rotate to the next alive proxy and restart the container.
PROXY_CONF="$PROXY_CONF"
ACTIVE_FILE="$ACTIVE_FILE"
APP_DIR="$APP_DIR"
LOG="$PROXY_LOG"
TS="\$(date '+%Y-%m-%d %H:%M:%S')"

echo "\$TS | INFO  | Manual proxy rotation requested." >> "\$LOG"
echo "Finding next alive proxy..."

find_active() {
  while IFS=: read -r H P U W; do
    [ -z "\$H" ] && continue
    if curl -fsSL --max-time 4 --proxy "http://\${U}:\${W}@\${H}:\${P}" \\
        https://api.ipify.org &>/dev/null; then
      echo "\${H}:\${P}:\${U}:\${W}"
      return 0
    fi
  done < "\$PROXY_CONF"
  return 1
}

ACTIVE="\$(find_active || true)"
if [ -z "\$ACTIVE" ]; then
  echo "No alive proxies found."
  echo "\$TS | WARN  | No alive proxies found during rotation." >> "\$LOG"
  exit 1
fi

echo "\$ACTIVE" > "\$ACTIVE_FILE"
A_HOST="\$(echo "\$ACTIVE" | cut -d: -f1)"
A_PORT="\$(echo "\$ACTIVE" | cut -d: -f2)"
A_USER="\$(echo "\$ACTIVE" | cut -d: -f3)"
A_PASS="\$(echo "\$ACTIVE" | cut -d: -f4)"
echo "Switching to proxy: \$A_HOST:\$A_PORT"
echo "\$TS | INFO  | Rotating to \$A_HOST:\$A_PORT" >> "\$LOG"

# Patch docker-compose.yml with new proxy env
sed -i "s|HTTP_PROXY=http://.*|HTTP_PROXY=http://\${A_USER}:\${A_PASS}@\${A_HOST}:\${A_PORT}|g" \\
  "\$APP_DIR/docker-compose.yml"
sed -i "s|HTTPS_PROXY=http://.*|HTTPS_PROXY=http://\${A_USER}:\${A_PASS}@\${A_HOST}:\${A_PORT}|g" \\
  "\$APP_DIR/docker-compose.yml"
sed -i "s|http_proxy=http://.*|http_proxy=http://\${A_USER}:\${A_PASS}@\${A_HOST}:\${A_PORT}|g" \\
  "\$APP_DIR/docker-compose.yml"
sed -i "s|https_proxy=http://.*|https_proxy=http://\${A_USER}:\${A_PASS}@\${A_HOST}:\${A_PORT}|g" \\
  "\$APP_DIR/docker-compose.yml"

cd "\$APP_DIR"
docker compose up -d --force-recreate
echo "\$TS | INFO  | Container restarted with new proxy." >> "\$LOG"
echo "Done. Container restarted with \$A_HOST:\$A_PORT"
SH

chmod +x "$APP_DIR/proxy-status.sh" "$APP_DIR/proxy-rotate.sh"

# ─── Proxy health-check daemon script ────────────────────────
cat > "/usr/local/bin/${SELLER_NAME}-proxy-health.sh" <<PHEALTHSCRIPT
#!/bin/bash
# Proxy health check for ${SELLER_NAME}
# If active proxy is dead → find next alive → restart container
PROXY_CONF="$PROXY_CONF"
ACTIVE_FILE="$ACTIVE_FILE"
APP_DIR="$APP_DIR"
LOG="$PROXY_LOG"
TS="\$(date '+%Y-%m-%d %H:%M:%S')"

# If proxy list doesn't exist, nothing to do
[ ! -f "\$PROXY_CONF" ] && exit 0
[ ! -s "\$PROXY_CONF" ] && exit 0

# Read current active proxy
CURRENT="\$(cat "\$ACTIVE_FILE" 2>/dev/null || true)"
if [ -n "\$CURRENT" ]; then
  C_HOST="\$(echo "\$CURRENT" | cut -d: -f1)"
  C_PORT="\$(echo "\$CURRENT" | cut -d: -f2)"
  C_USER="\$(echo "\$CURRENT" | cut -d: -f3)"
  C_PASS="\$(echo "\$CURRENT" | cut -d: -f4)"

  if curl -fsSL --max-time 5 \\
      --proxy "http://\${C_USER}:\${C_PASS}@\${C_HOST}:\${C_PORT}" \\
      https://api.ipify.org &>/dev/null; then
    echo "\$TS | OK    | Proxy \$C_HOST:\$C_PORT alive." >> "\$LOG"
    # Trim log
    [ "\$(wc -l < "\$LOG")" -gt 500 ] && tail -300 "\$LOG" > "\$LOG.tmp" && mv "\$LOG.tmp" "\$LOG"
    exit 0
  else
    echo "\$TS | DEAD  | Proxy \$C_HOST:\$C_PORT unreachable — rotating..." >> "\$LOG"
  fi
else
  echo "\$TS | INFO  | No active proxy set — finding one..." >> "\$LOG"
fi

# Find next alive proxy
NEW=""
while IFS=: read -r H P U W; do
  [ -z "\$H" ] && continue
  # Skip the dead one
  if [ "\$H" = "\$C_HOST" ] && [ "\$P" = "\$C_PORT" ]; then continue; fi
  if curl -fsSL --max-time 5 \\
      --proxy "http://\${U}:\${W}@\${H}:\${P}" \\
      https://api.ipify.org &>/dev/null; then
    NEW="\${H}:\${P}:\${U}:\${W}"
    break
  fi
done < "\$PROXY_CONF"

if [ -z "\$NEW" ]; then
  # Dead one might be back, try all proxies including dead one
  while IFS=: read -r H P U W; do
    [ -z "\$H" ] && continue
    if curl -fsSL --max-time 5 \\
        --proxy "http://\${U}:\${W}@\${H}:\${P}" \\
        https://api.ipify.org &>/dev/null; then
      NEW="\${H}:\${P}:\${U}:\${W}"
      break
    fi
  done < "\$PROXY_CONF"
fi

if [ -z "\$NEW" ]; then
  echo "\$TS | WARN  | All proxies dead. Container left running without proxy update." >> "\$LOG"
  [ "\$(wc -l < "\$LOG")" -gt 500 ] && tail -300 "\$LOG" > "\$LOG.tmp" && mv "\$LOG.tmp" "\$LOG"
  exit 1
fi

echo "\$NEW" > "\$ACTIVE_FILE"
N_HOST="\$(echo "\$NEW" | cut -d: -f1)"
N_PORT="\$(echo "\$NEW" | cut -d: -f2)"
N_USER="\$(echo "\$NEW" | cut -d: -f3)"
N_PASS="\$(echo "\$NEW" | cut -d: -f4)"
echo "\$TS | SWAP  | Switching to \$N_HOST:\$N_PORT" >> "\$LOG"

# Update docker-compose.yml with new proxy
sed -i "s|HTTP_PROXY=http://[^[:space:]]*|HTTP_PROXY=http://\${N_USER}:\${N_PASS}@\${N_HOST}:\${N_PORT}|g" \\
  "\$APP_DIR/docker-compose.yml"
sed -i "s|HTTPS_PROXY=http://[^[:space:]]*|HTTPS_PROXY=http://\${N_USER}:\${N_PASS}@\${N_HOST}:\${N_PORT}|g" \\
  "\$APP_DIR/docker-compose.yml"
sed -i "s|http_proxy=http://[^[:space:]]*|http_proxy=http://\${N_USER}:\${N_PASS}@\${N_HOST}:\${N_PORT}|g" \\
  "\$APP_DIR/docker-compose.yml"
sed -i "s|https_proxy=http://[^[:space:]]*|https_proxy=http://\${N_USER}:\${N_PASS}@\${N_HOST}:\${N_PORT}|g" \\
  "\$APP_DIR/docker-compose.yml"

# Restart container with new proxy
cd "\$APP_DIR"
docker compose up -d --force-recreate >> "\$LOG" 2>&1
echo "\$TS | INFO  | Container restarted with \$N_HOST:\$N_PORT" >> "\$LOG"

[ "\$(wc -l < "\$LOG")" -gt 500 ] && tail -300 "\$LOG" > "\$LOG.tmp" && mv "\$LOG.tmp" "\$LOG"
PHEALTHSCRIPT

chmod +x "/usr/local/bin/${SELLER_NAME}-proxy-health.sh"

# ─── Add proxy health check to crontab ───────────────────────
echo "Adding proxy health cron job (every 10 min)..."
CRON_TMP="/tmp/${SELLER_NAME}_proxy_crontab"
crontab -l -u root 2>/dev/null \
  | grep -v "${SELLER_NAME}-proxy-health" \
  > "$CRON_TMP" || true

cat >> "$CRON_TMP" <<CRON

# ── ${SELLER_NAME}: proxy health + auto-failover every 10 min ───────────
*/10 * * * * /usr/local/bin/${SELLER_NAME}-proxy-health.sh >/dev/null 2>&1
CRON

crontab -u root "$CRON_TMP"
rm -f "$CRON_TMP"

echo ""
echo "======================================"
echo " [proxy-setup] done: ${SELLER_NAME}"
echo " Proxies saved : $PROXY_CONF"
echo " Active proxy  : $(cat "$ACTIVE_FILE" 2>/dev/null | cut -d: -f1-2 || echo 'none')"
echo " Health check  : every 10 min (auto-failover)"
echo "======================================"
