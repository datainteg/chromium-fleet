#!/bin/bash
# =============================================================
# uninstall.sh — Remove ONE seller instance cleanly.
# Other sellers on the same VM are NOT affected.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/uninstall.sh \
#     | bash -s -- --seller seller1
# =============================================================
set -euo pipefail

SELLER_NAME=""
ASSUME_YES="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seller) SELLER_NAME="$2"; shift 2 ;;
    --yes|-y) ASSUME_YES="true"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$SELLER_NAME" ]]; then
  echo "ERROR: --seller is required"
  echo "Usage: uninstall.sh --seller NAME"
  exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: Run as root."
  exit 1
fi

if ! [[ "$SELLER_NAME" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]]; then
  echo "ERROR: --seller must match ^[a-z0-9][a-z0-9_-]{0,31}$"
  exit 1
fi

APP_DIR="/opt/${SELLER_NAME}-browser"
CONF_NAME="${SELLER_NAME}-chrome"

echo ""
echo "======================================"
echo " Uninstall: $SELLER_NAME"
echo " App dir  : $APP_DIR"
echo "======================================"
echo ""
if [[ "$ASSUME_YES" != "true" ]]; then
  read -rp "This will delete all data for '$SELLER_NAME'. Continue? [y/N]: " CONFIRM
  [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "Aborted." && exit 0
fi

echo ""
echo "[1/6] Stopping and removing Docker container..."
if [ -f "$APP_DIR/docker-compose.yml" ]; then
  cd "$APP_DIR"
  docker compose down --volumes --remove-orphans 2>/dev/null || true
fi

echo "[2/6] Removing app directory..."
rm -rf "$APP_DIR"

echo "[3/6] Removing maintenance scripts..."
rm -f "/usr/local/bin/${SELLER_NAME}-health.sh"
rm -f "/usr/local/bin/${SELLER_NAME}-clear-logs.sh"
rm -f "/usr/local/bin/${SELLER_NAME}-proxy-health.sh"
rm -f "/usr/local/bin/${SELLER_NAME}-set-proxy-env.sh"
rm -f "/usr/local/bin/${SELLER_NAME}-backup-profile.sh"

echo "[4/6] Removing crontab entries..."
CRON_TMP="/tmp/${SELLER_NAME}_uninstall_cron"
crontab -l -u root 2>/dev/null \
  | grep -v "${SELLER_NAME}-health" \
  | grep -v "${SELLER_NAME}-clear-logs" \
  | grep -v "${SELLER_NAME}-proxy-health" \
  | grep -v "${SELLER_NAME}-backup-profile" \
  | grep -v "# ── ${SELLER_NAME}" \
  > "$CRON_TMP" || true
crontab -u root "$CRON_TMP"
rm -f "$CRON_TMP"

echo "[5/6] Removing Nginx config and logs..."
rm -f "/etc/nginx/sites-enabled/$CONF_NAME"
rm -f "/etc/nginx/sites-available/$CONF_NAME"
rm -f "/etc/nginx/htpasswd/${SELLER_NAME}"
rm -f "/var/log/nginx/${SELLER_NAME}-chrome-access.log"
rm -f "/var/log/nginx/${SELLER_NAME}-chrome-error.log"

echo "[6/6] Reloading Nginx..."
nginx -t && systemctl reload nginx 2>/dev/null || true

echo ""
echo "======================================"
echo " '$SELLER_NAME' removed successfully."
echo " Other sellers on this VM are untouched."
echo "======================================"
