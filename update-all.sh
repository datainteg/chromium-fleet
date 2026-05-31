#!/bin/bash
# =============================================================
# scripts/update-all.sh
# Pulls latest Chromium image and recreates all seller containers.
# =============================================================
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: Run as root."
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "  chromium-fleet — Update All Sellers"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

UPDATED=0
FAILED=0

for DIR in /opt/*-browser; do
  [ -d "$DIR" ] || continue
  [ -f "$DIR/docker-compose.yml" ] || continue
  NAME="$(basename "$DIR" | sed 's/-browser$//')"
  echo "── Updating: $NAME ──────────────────────────"
  cd "$DIR"
  if docker compose pull -q && docker compose up -d --force-recreate; then
    echo "  ✓ $NAME updated"
    UPDATED=$((UPDATED + 1))
  else
    echo "  ✗ $NAME failed"
    FAILED=$((FAILED + 1))
  fi
  echo ""
done

echo "══════════════════════════════════════════"
echo "  Updated : $UPDATED"
echo "  Failed  : $FAILED"
echo "══════════════════════════════════════════"
