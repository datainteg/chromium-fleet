#!/bin/bash
# =============================================================
# chromium-fleet — One-Command Installer
# https://github.com/datainteg/chromium-fleet
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/datainteg/chromium-fleet/main/install.sh \
#     | bash -s -- \
#         --seller    seller1 \
#         --port      3000 \
#         --user      admin \
#         --pass      "StrongPass!" \
#         --subdomain seller1.yourdomain.com \
#         [--proxy    "host:port:user:pass"]   (optional, repeatable)
# =============================================================
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/datainteg/chromium-fleet/main"

# ─── Defaults ────────────────────────────────────────────────
SELLER_NAME="seller1"
CHROME_PORT="3000"
CHROME_USER="admin"
CHROME_PASS=""
SUBDOMAIN=""
TZ_NAME="Asia/Kolkata"
MEM_LIMIT="3g"
CPU_LIMIT="1.5"
SHM_SIZE="2gb"
SWAP_SIZE="4G"
PROXIES=()

# ─── Colours ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log()  { echo -e "${GREEN}[✓]${RESET} $*"; }
info() { echo -e "${CYAN}[i]${RESET} $*"; }
err()  { echo -e "${RED}[✗]${RESET} $*" >&2; }

# ─── Usage ───────────────────────────────────────────────────
usage() {
  echo ""
  echo -e "${BOLD}chromium-fleet installer${RESET}"
  echo ""
  echo "  --seller      NAME        Instance name            (default: seller1)"
  echo "  --port        PORT        Host port for Chromium   (default: 3000)"
  echo "  --user        USER        Basic-auth username      (default: admin)"
  echo "  --pass        PASS        Basic-auth password      [REQUIRED]"
  echo "  --subdomain   DOMAIN      e.g. s1.example.com      [REQUIRED]"
  echo "  --tz          TIMEZONE    Container timezone        (default: Asia/Kolkata)"
  echo "  --mem         LIMIT       Docker mem limit          (default: 3g)"
  echo "  --cpu         LIMIT       Docker CPU limit          (default: 1.5)"
  echo "  --shm         SIZE        /dev/shm size             (default: 2gb)"
  echo "  --swap        SIZE        Swap size                 (default: 4G)"
  echo "  --proxy       PROXY       host:port:user:pass       (optional, repeatable)"
  echo "  --help                    Show this message"
  echo ""
  echo "Examples:"
  echo ""
  echo "  # No proxy"
  echo "  ... | bash -s -- --seller s1 --port 3000 --pass secret --subdomain s1.ex.com"
  echo ""
  echo "  # With multiple proxies (auto-failover)"
  echo "  ... | bash -s -- --seller s1 --port 3000 --pass secret --subdomain s1.ex.com \\"
  echo "        --proxy 1.2.3.4:8080:user1:pass1 \\"
  echo "        --proxy 5.6.7.8:8080:user2:pass2"
  echo ""
}

# ─── Argument parser ─────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seller)    SELLER_NAME="$2"; shift 2 ;;
    --port)      CHROME_PORT="$2"; shift 2 ;;
    --user)      CHROME_USER="$2"; shift 2 ;;
    --pass)      CHROME_PASS="$2"; shift 2 ;;
    --subdomain) SUBDOMAIN="$2";   shift 2 ;;
    --tz)        TZ_NAME="$2";     shift 2 ;;
    --mem)       MEM_LIMIT="$2";   shift 2 ;;
    --cpu)       CPU_LIMIT="$2";   shift 2 ;;
    --shm)       SHM_SIZE="$2";    shift 2 ;;
    --swap)      SWAP_SIZE="$2";   shift 2 ;;
    --proxy)     PROXIES+=("$2");  shift 2 ;;
    --help|-h)   usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ─── Validation ──────────────────────────────────────────────
ERRORS=()
[[ -z "$CHROME_PASS" ]] && ERRORS+=("--pass is required")
[[ -z "$SUBDOMAIN"   ]] && ERRORS+=("--subdomain is required")
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  err "Missing required parameters:"
  for e in "${ERRORS[@]}"; do echo "    • $e"; done
  usage; exit 1
fi

[[ "$EUID" -ne 0 ]] && { err "Run as root (sudo or root user)."; exit 1; }

# ─── Banner ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║       chromium-fleet  installer          ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}"
echo ""
info "Seller     : $SELLER_NAME"
info "Port       : $CHROME_PORT"
info "Subdomain  : $SUBDOMAIN"
info "Auth User  : $CHROME_USER"
info "Timezone   : $TZ_NAME"
info "Mem Limit  : $MEM_LIMIT"
info "CPU Limit  : $CPU_LIMIT"
info "SHM Size   : $SHM_SIZE"
info "Swap Size  : $SWAP_SIZE"
if [[ ${#PROXIES[@]} -gt 0 ]]; then
  info "Proxies    : ${#PROXIES[@]} configured"
  for i in "${!PROXIES[@]}"; do
    PH="$(echo "${PROXIES[$i]}" | cut -d: -f1)"
    PP="$(echo "${PROXIES[$i]}" | cut -d: -f2)"
    info "  Proxy $((i+1))  : $PH:$PP"
  done
else
  info "Proxies    : none (direct connection)"
fi
echo ""

# ─── Download sub-scripts ────────────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

info "Downloading setup scripts..."
curl -fsSL "$REPO_RAW/chrome-setup/setup.sh" -o "$TMP_DIR/setup.sh"
curl -fsSL "$REPO_RAW/nginx-setup/nginx.sh"  -o "$TMP_DIR/nginx.sh"
curl -fsSL "$REPO_RAW/proxy-setup/proxy.sh"  -o "$TMP_DIR/proxy.sh"
chmod +x "$TMP_DIR/setup.sh" "$TMP_DIR/nginx.sh" "$TMP_DIR/proxy.sh"

# Build PROXY_LIST env var (newline-separated)
PROXY_LIST=""
for p in "${PROXIES[@]}"; do PROXY_LIST+="${p}"$'\n'; done

# ─── Run sub-scripts ─────────────────────────────────────────
log "Running Chrome VM setup..."
SELLER_NAME="$SELLER_NAME" CHROME_PORT="$CHROME_PORT" \
CHROME_USER="$CHROME_USER" CHROME_PASS="$CHROME_PASS" \
TZ_NAME="$TZ_NAME" MEM_LIMIT="$MEM_LIMIT" CPU_LIMIT="$CPU_LIMIT" \
SHM_SIZE="$SHM_SIZE" SWAP_SIZE="$SWAP_SIZE" PROXY_LIST="$PROXY_LIST" \
  bash "$TMP_DIR/setup.sh"

if [[ ${#PROXIES[@]} -gt 0 ]]; then
  log "Running proxy setup..."
  SELLER_NAME="$SELLER_NAME" APP_DIR="/opt/${SELLER_NAME}-browser" \
  PROXY_LIST="$PROXY_LIST" bash "$TMP_DIR/proxy.sh"
fi

log "Running Nginx setup..."
SELLER_NAME="$SELLER_NAME" CHROME_PORT="$CHROME_PORT" \
CHROME_USER="$CHROME_USER" CHROME_PASS="$CHROME_PASS" \
SUBDOMAIN="$SUBDOMAIN" bash "$TMP_DIR/nginx.sh"

# ─── Done ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║           ALL DONE!                      ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Chromium URL  :${RESET} http://$SUBDOMAIN"
echo -e "  ${BOLD}Direct access :${RESET} http://$(hostname -I | awk '{print $1}'):$CHROME_PORT"
echo -e "  ${BOLD}Login         :${RESET} $CHROME_USER / $CHROME_PASS"
echo -e "  ${BOLD}App dir       :${RESET} /opt/${SELLER_NAME}-browser"
echo -e "  ${BOLD}Session state :${RESET} /opt/${SELLER_NAME}-browser/profile  (always preserved)"
if [[ ${#PROXIES[@]} -gt 0 ]]; then
  echo -e "  ${BOLD}Proxy config  :${RESET} /opt/${SELLER_NAME}-browser/proxy/proxies.conf"
fi
echo ""
echo -e "  ${BOLD}Next step:${RESET}"
echo -e "    1. Open http://$SUBDOMAIN"
echo -e "    2. Log into indiamart.com as the seller"
echo -e "    3. Install any Chrome extensions needed"
echo -e "    4. Done — GCP VM stop/start keeps you logged in"
echo ""
echo -e "  ${BOLD}Helper scripts:${RESET}"
echo -e "    /opt/${SELLER_NAME}-browser/start.sh     ← resume session"
echo -e "    /opt/${SELLER_NAME}-browser/stop.sh      ← graceful stop"
echo -e "    /opt/${SELLER_NAME}-browser/restart.sh   ← stop + start"
echo -e "    /opt/${SELLER_NAME}-browser/recreate.sh  ← full recreate (session safe)"
echo -e "    /opt/${SELLER_NAME}-browser/update.sh    ← pull new image"
echo -e "    /opt/${SELLER_NAME}-browser/status.sh"
echo -e "    /opt/${SELLER_NAME}-browser/logs.sh"
if [[ ${#PROXIES[@]} -gt 0 ]]; then
  echo -e "    /opt/${SELLER_NAME}-browser/proxy-status.sh"
  echo -e "    /opt/${SELLER_NAME}-browser/proxy-rotate.sh"
fi
echo ""
