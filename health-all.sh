#!/bin/bash
# =============================================================
# scripts/health-all.sh
# Quick health overview of all chromium-fleet sellers on this VM.
# =============================================================

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "  chromium-fleet — Health Overview"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

for DIR in /opt/*-browser; do
  [ -d "$DIR" ] || continue
  [ -f "$DIR/docker-compose.yml" ] || continue
  NAME="$(basename "$DIR" | sed 's/-browser$//')"
  CONTAINER="${NAME}-chrome"
  STATUS="$(docker ps --filter "name=${CONTAINER}" --format '{{.Status}}' 2>/dev/null)"

  if [ -n "$STATUS" ]; then
    echo "  ✓ $NAME  →  $STATUS"
  else
    echo "  ✗ $NAME  →  NOT RUNNING"
  fi

  # Show proxy status if applicable
  PROXY_CONF="$DIR/proxy/proxies.conf"
  ACTIVE_FILE="$DIR/proxy/active.conf"
  if [ -f "$PROXY_CONF" ] && [ -s "$PROXY_CONF" ]; then
    TOTAL="$(grep -c . "$PROXY_CONF" || true)"
    ACTIVE="$(cat "$ACTIVE_FILE" 2>/dev/null | cut -d: -f1-2 || echo 'none')"
    echo "    Proxy: $ACTIVE (1 active of $TOTAL configured)"
  fi
done

echo ""
echo "  System resources:"
echo "    CPU  : $(top -bn1 | grep 'Cpu(s)' | awk '{print $2}')% used"
echo "    RAM  : $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
echo "    Disk : $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')"
echo "    Swap : $(free -h | awk '/^Swap:/ {print $3 "/" $2}')"
echo ""
