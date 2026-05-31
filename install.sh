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
#         [--api-port 8787]                    (optional, default: 8787)
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
MEM_LIMIT="2g"
CPU_LIMIT="1.0"
SHM_SIZE="1gb"
SWAP_SIZE="2G"
API_PORT="8787"
PROXIES=()

# ─── Colours ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log()  { echo -e "${GREEN}[✓]${RESET} $*"; }
info() { echo -e "${CYAN}[i]${RESET} $*"; }
err()  { echo -e "${RED}[✗]${RESET} $*" >&2; }

is_valid_seller_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]]
}

is_valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

is_valid_subdomain() {
  local domain="$1" label tld idx
  [[ -n "$domain" && ${#domain} -le 253 ]] || return 1
  [[ "$domain" != .* && "$domain" != *. ]] || return 1
  [[ "$domain" != *..* ]] || return 1

  IFS='.' read -r -a labels <<< "$domain"
  (( ${#labels[@]} >= 2 )) || return 1

  for label in "${labels[@]}"; do
    [[ ${#label} -ge 1 && ${#label} -le 63 ]] || return 1
    [[ "$label" =~ ^[A-Za-z0-9-]+$ ]] || return 1
    [[ "$label" != -* && "$label" != *- ]] || return 1
  done

  idx=$((${#labels[@]} - 1))
  tld="${labels[$idx]}"
  [[ ${#tld} -ge 2 ]] || return 1
}

is_valid_proxy() {
  local proxy="$1" host port user pass extra
  IFS=: read -r host port user pass extra <<< "$proxy"
  [[ -n "${host:-}" && -n "${port:-}" && -n "${user:-}" && -n "${pass:-}" && -z "${extra:-}" ]] || return 1
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

is_valid_size_value() {
  [[ "$1" =~ ^[1-9][0-9]*([kKmMgG])([bB])?$ ]]
}

is_valid_cpu_limit() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  awk -v value="$1" 'BEGIN { exit !(value > 0 && value <= 8) }'
}

download_script() {
  local out="$1"
  shift
  local rel
  for rel in "$@"; do
    if curl -fsSL "$REPO_RAW/$rel" -o "$out"; then
      return 0
    fi
  done
  return 1
}

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
  echo "  --mem         LIMIT       Docker mem limit          (default: 2g)"
  echo "  --cpu         LIMIT       Docker CPU limit          (default: 1.0)"
  echo "  --shm         SIZE        /dev/shm size             (default: 1gb)"
  echo "  --swap        SIZE        Swap size                 (default: 2G)"
  echo "  --api-port    PORT        Local API upstream port   (default: 8787)"
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
    --seller)    [[ $# -lt 2 ]] && { err "Missing value for --seller"; usage; exit 1; }; SELLER_NAME="$2"; shift 2 ;;
    --port)      [[ $# -lt 2 ]] && { err "Missing value for --port"; usage; exit 1; }; CHROME_PORT="$2"; shift 2 ;;
    --user)      [[ $# -lt 2 ]] && { err "Missing value for --user"; usage; exit 1; }; CHROME_USER="$2"; shift 2 ;;
    --pass)      [[ $# -lt 2 ]] && { err "Missing value for --pass"; usage; exit 1; }; CHROME_PASS="$2"; shift 2 ;;
    --subdomain) [[ $# -lt 2 ]] && { err "Missing value for --subdomain"; usage; exit 1; }; SUBDOMAIN="$2"; shift 2 ;;
    --tz)        [[ $# -lt 2 ]] && { err "Missing value for --tz"; usage; exit 1; }; TZ_NAME="$2"; shift 2 ;;
    --mem)       [[ $# -lt 2 ]] && { err "Missing value for --mem"; usage; exit 1; }; MEM_LIMIT="$2"; shift 2 ;;
    --cpu)       [[ $# -lt 2 ]] && { err "Missing value for --cpu"; usage; exit 1; }; CPU_LIMIT="$2"; shift 2 ;;
    --shm)       [[ $# -lt 2 ]] && { err "Missing value for --shm"; usage; exit 1; }; SHM_SIZE="$2"; shift 2 ;;
    --swap)      [[ $# -lt 2 ]] && { err "Missing value for --swap"; usage; exit 1; }; SWAP_SIZE="$2"; shift 2 ;;
    --api-port)  [[ $# -lt 2 ]] && { err "Missing value for --api-port"; usage; exit 1; }; API_PORT="$2"; shift 2 ;;
    --proxy)     [[ $# -lt 2 ]] && { err "Missing value for --proxy"; usage; exit 1; }; PROXIES+=("$2"); shift 2 ;;
    --help|-h)   usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ─── Validation ──────────────────────────────────────────────
ERRORS=()
[[ -z "$CHROME_PASS" ]] && ERRORS+=("--pass is required")
[[ -z "$SUBDOMAIN"   ]] && ERRORS+=("--subdomain is required")
is_valid_seller_name "$SELLER_NAME" || ERRORS+=("--seller must match: ^[a-z0-9][a-z0-9_-]{0,31}$")
is_valid_port "$CHROME_PORT" || ERRORS+=("--port must be a number between 1 and 65535")
is_valid_port "$API_PORT" || ERRORS+=("--api-port must be a number between 1 and 65535")
is_valid_subdomain "$SUBDOMAIN" || ERRORS+=("--subdomain must be a valid domain like chrome1.example.com")
is_valid_size_value "$MEM_LIMIT" || ERRORS+=("--mem must look like 2g, 1536m, 1gb")
is_valid_cpu_limit "$CPU_LIMIT" || ERRORS+=("--cpu must be a positive number up to 8 (example: 1.0)")
is_valid_size_value "$SHM_SIZE" || ERRORS+=("--shm must look like 1gb, 512m")
is_valid_size_value "$SWAP_SIZE" || ERRORS+=("--swap must look like 2G, 4096M")
for proxy in "${PROXIES[@]}"; do
  is_valid_proxy "$proxy" || ERRORS+=("Invalid --proxy value '$proxy' (expected host:port:user:pass with numeric port)")
done
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  err "Invalid or missing parameters:"
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
info "API Port   : $API_PORT"
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
download_script "$TMP_DIR/setup.sh" "setup.sh" "chrome-setup/setup.sh" \
  || { err "Unable to download setup.sh from repository."; exit 1; }
download_script "$TMP_DIR/nginx.sh" "nginx.sh" "nginx-setup/nginx.sh" \
  || { err "Unable to download nginx.sh from repository."; exit 1; }
download_script "$TMP_DIR/proxy.sh" "proxy.sh" "proxy-setup/proxy.sh" \
  || { err "Unable to download proxy.sh from repository."; exit 1; }
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
SUBDOMAIN="$SUBDOMAIN" API_PORT="$API_PORT" bash "$TMP_DIR/nginx.sh"

# ─── Done ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║           ALL DONE!                      ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Chromium URL  :${RESET} http://$SUBDOMAIN"
echo -e "  ${BOLD}Direct access :${RESET} http://$(hostname -I | awk '{print $1}'):$CHROME_PORT"
echo -e "  ${BOLD}Login         :${RESET} $CHROME_USER / [hidden]"
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
