#!/bin/bash
# =============================================================
# scripts/list-sellers.sh
# Lists all chromium-fleet seller instances on this VM.
# =============================================================

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "  chromium-fleet — Installed Sellers"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Find all seller app directories
SELLERS=()
for DIR in /opt/*-browser; do
  [ -d "$DIR" ] || continue
  [ -f "$DIR/docker-compose.yml" ] || continue
  NAME="$(basename "$DIR" | sed 's/-browser$//')"
  SELLERS+=("$NAME")
done

if [ ${#SELLERS[@]} -eq 0 ]; then
  echo "  No sellers installed."
  echo ""
  exit 0
fi

printf "  %-15s %-12s %-20s %-10s\n" "SELLER" "CONTAINER" "STATUS" "PORT"
printf "  %-15s %-12s %-20s %-10s\n" "──────────────" "──────────" "──────────────────" "────────"

for NAME in "${SELLERS[@]}"; do
  CONTAINER="${NAME}-chrome"
  APP_DIR="/opt/${NAME}-browser"
  PORT="$(grep -oP '(?<=- ")[\d]+(?=:3000")' "$APP_DIR/docker-compose.yml" 2>/dev/null || echo '?')"
  STATUS="$(docker ps --filter "name=${CONTAINER}" --format '{{.Status}}' 2>/dev/null || echo 'unknown')"
  [ -z "$STATUS" ] && STATUS="stopped"
  printf "  %-15s %-12s %-20s %-10s\n" "$NAME" "$CONTAINER" "$STATUS" "$PORT"
done

echo ""
echo "  Run status for individual seller:"
echo "    /opt/SELLER-browser/status.sh"
echo ""
echo "  Run proxy status:"
echo "    /opt/SELLER-browser/proxy-status.sh"
echo ""
