#!/bin/bash
# =============================================================
# api/install-service.sh
#
# Install the chromium-fleet API as a service.
#
# Mode A — Docker (recommended):
#   Runs the API as a Docker container managed by docker-compose.fleet.yml.
#   Use this on any VM that already has Docker installed.
#
#     sudo bash api/install-service.sh --docker
#
# Mode B — systemd (legacy, host Node.js):
#   Runs the API directly on the host as a systemd service.
#
#     sudo bash api/install-service.sh
# =============================================================
set -euo pipefail

DOCKER_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker) DOCKER_MODE=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: run as root (sudo)."
  exit 1
fi

FLEET_DIR="$(cd "$(dirname "$0")/.." && pwd)"
API_DIR="$FLEET_DIR/api"

if [[ ! -f "$API_DIR/.env" ]]; then
  cp "$API_DIR/.env.example" "$API_DIR/.env"
  echo "Created $API_DIR/.env from .env.example. Update secrets before production."
fi

# ─── Docker mode ─────────────────────────────────────────────
if [[ "$DOCKER_MODE" == "true" ]]; then
  if ! command -v docker &>/dev/null; then
    echo "ERROR: docker is required. Install it first (setup.sh installs docker)."
    exit 1
  fi

  if [[ ! -f "$FLEET_DIR/docker-compose.fleet.yml" ]]; then
    echo "ERROR: $FLEET_DIR/docker-compose.fleet.yml not found."
    exit 1
  fi

  echo "Building and starting chromium-fleet-api in Docker..."
  cd "$FLEET_DIR"
  docker compose -f docker-compose.fleet.yml build api
  docker compose -f docker-compose.fleet.yml up -d api

  echo ""
  echo "API is running in Docker."
  echo "  Logs  : docker compose -f $FLEET_DIR/docker-compose.fleet.yml logs -f api"
  echo "  Stop  : docker compose -f $FLEET_DIR/docker-compose.fleet.yml stop api"
  echo "  Restart: docker compose -f $FLEET_DIR/docker-compose.fleet.yml restart api"
  exit 0
fi

# ─── Systemd mode ────────────────────────────────────────────
if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node is required (Node 18+)."
  exit 1
fi

if [[ ! -d "$API_DIR/node_modules" ]]; then
  echo "Installing npm dependencies..."
  cd "$API_DIR"
  npm install --omit=dev
fi

SERVICE_NAME="chromium-fleet-api"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

cat > "$SERVICE_FILE" <<SERVICE
[Unit]
Description=Chromium Fleet API
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
Type=simple
WorkingDirectory=${API_DIR}
Environment=NODE_ENV=production
Environment=NODE_OPTIONS=--max-old-space-size=256
ExecStart=/usr/bin/env node src/server.js
Restart=always
RestartSec=5
User=root
Group=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"

echo ""
echo "Installed and started ${SERVICE_NAME} (systemd)."
echo "  Status: systemctl status ${SERVICE_NAME}"
echo "  Logs  : journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "Tip: use --docker flag to run as a Docker container instead."
