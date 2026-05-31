#!/bin/bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: run as root (sudo)."
  exit 1
fi

API_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_NAME="chromium-fleet-api"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node is required (Node 18+)."
  exit 1
fi

if [[ ! -f "$API_DIR/.env" ]]; then
  cp "$API_DIR/.env.example" "$API_DIR/.env"
  echo "Created $API_DIR/.env from .env.example. Update secrets before production."
fi

if [[ ! -d "$API_DIR/node_modules" ]]; then
  echo "Installing npm dependencies..."
  cd "$API_DIR"
  npm install --omit=dev
fi

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

echo "Installed and started ${SERVICE_NAME}."
echo "Check status with: systemctl status ${SERVICE_NAME}"
echo "View logs with: journalctl -u ${SERVICE_NAME} -f"
