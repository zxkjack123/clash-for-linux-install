#!/bin/bash

# 🔄 Restart Clash/Mihomo Service with Updated Configuration
# 
# DESCRIPTION:
#   Restarts the mihomo service with updated configuration including OpenXLab direct rules
#   Validates configuration, applies updates, and ensures service is running properly
#
# USAGE:
#   ./restart_clash_service.sh
#
# WHAT IT DOES:
#   • Validates current configuration files
#   • Backs up current config
#   • Restarts mihomo service
#   • Verifies service status
#   • Tests configuration changes
#   • Validates OpenXLab direct connection rules

echo "🔄 Restarting Clash/Mihomo Service with Updated Configuration"
echo "==========================================================="

set -euo pipefail

APPLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply|--yes) APPLY=1; shift;;
        -h|--help)
            echo "Usage: $0 [--apply]" >&2
            echo "  --apply  Actually back up config and restart mihomo.service" >&2
            exit 0;;
        *) echo "Unknown arg: $1" >&2; exit 2;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Resolve repo paths robustly regardless of current working directory
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Optional env bootstrap (controller URL + secret)
if [[ -f "$ROOT_DIR/vpn-tools/load_env.sh" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT_DIR/vpn-tools/load_env.sh" 2>/dev/null || true
fi

API="${CLASH_API:-http://127.0.0.1:9090}"
AUTH_HDR=()
_hdr="$(clash_auth_header 2>/dev/null || true)"
[[ -n "${_hdr:-}" ]] && AUTH_HDR=(-H "${_hdr}")

# Configuration paths
CONFIG_DIR="$ROOT_DIR/resources"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
MIXIN_FILE="$CONFIG_DIR/mixin.yaml"
BACKUP_DIR="$CONFIG_DIR/backup"

echo "📁 Configuration Files:"
echo "• Main config: $CONFIG_FILE"
echo "• Mixin config: $MIXIN_FILE"
echo ""

# Step 1: Create backup (apply mode only)
echo "💾 Creating configuration backup..."
if [[ $APPLY -ne 1 ]]; then
    echo -e "${YELLOW}ℹ️ Preview mode: skipping backup creation (use --apply to proceed).${NC}"
else
    mkdir -p "$BACKUP_DIR"
    timestamp=$(date +"%Y%m%d_%H%M%S")

    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_DIR/config_${timestamp}.yaml"
        echo -e "${GREEN}✅ Main config backed up${NC}"
    else
        echo -e "${RED}❌ Main config file not found${NC}"
        exit 1
    fi

    if [ -f "$MIXIN_FILE" ]; then
        cp "$MIXIN_FILE" "$BACKUP_DIR/mixin_${timestamp}.yaml"
        echo -e "${GREEN}✅ Mixin config backed up${NC}"
    else
        echo -e "${YELLOW}⚠️ Mixin config file not found${NC}"
    fi
fi

echo ""

# Step 2: Validate configuration
echo "🔍 Validating configuration files..."

# Check that key proxy groups exist in main config
for _grp in AUTO PROXY COPILOT DEV; do
    if grep -q "name:.*\"${_grp}\"" "$CONFIG_FILE" 2>/dev/null; then
        echo -e "${GREEN}✅ Proxy group ${_grp} found in main config${NC}"
    else
        echo -e "${YELLOW}⚠️ Proxy group ${_grp} not found in main config${NC}"
    fi
done

echo ""

# Step 3: Check current service status
echo "📊 Current service status:"
echo "========================="

if systemctl --user is-active mihomo.service >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Mihomo service is running${NC}"
    CURRENT_STATUS="running"
else
    echo -e "${YELLOW}⚠️ Mihomo service is not running${NC}"
    CURRENT_STATUS="stopped"
fi

# Check if API is accessible
if curl -fsS --noproxy '*' --connect-timeout 2 --max-time 3 ${AUTH_HDR[@]+"${AUTH_HDR[@]}"} "$API/version" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Clash API is accessible${NC}"
    API_STATUS="accessible"
else
    echo -e "${YELLOW}⚠️ Clash API is not accessible${NC}"
    API_STATUS="not_accessible"
fi

echo ""

if [[ $APPLY -ne 1 ]]; then
    echo -e "${CYAN}🧪 Preview summary:${NC} service=$CURRENT_STATUS, controller=$API_STATUS"
    echo -e "${CYAN}To actually restart mihomo.service, re-run with: --apply${NC}"
    exit 0
fi

# Step 4: Restart the service
echo "🔄 Restarting mihomo service..."
echo "==============================="

echo "📤 Stopping mihomo service..."
if systemctl --user stop mihomo.service; then
    echo -e "${GREEN}✅ Service stopped${NC}"
else
    echo -e "${RED}❌ Failed to stop service${NC}"
    exit 1
fi

# Wait a moment for clean shutdown
sleep 2

echo "📥 Starting mihomo service..."
if systemctl --user start mihomo.service; then
    echo -e "${GREEN}✅ Service started${NC}"
else
    echo -e "${RED}❌ Failed to start service${NC}"
    
    # Show service status for debugging
    echo "🔍 Service status for debugging:"
    systemctl --user status mihomo.service --no-pager
    exit 1
fi

# Wait for service to fully initialize
echo "⏳ Waiting for service to initialize..."
sleep 5

echo ""

# Step 5: Verify service is running properly
echo "✅ Verifying service status:"
echo "============================"

# Check service status
if systemctl --user is-active mihomo.service >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Mihomo service is running${NC}"
else
    echo -e "${RED}❌ Mihomo service failed to start${NC}"
    echo "🔍 Service logs:"
    systemctl --user status mihomo.service --no-pager -l
    exit 1
fi

# Check API accessibility
echo "⏳ Waiting for API to be available..."
retries=0
max_retries=10

while [ $retries -lt $max_retries ]; do
    if curl -fsS --noproxy '*' --connect-timeout 2 --max-time 3 ${AUTH_HDR[@]+"${AUTH_HDR[@]}"} "$API/version" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Clash API is accessible${NC}"
        break
    else
        retries=$((retries + 1))
        echo "🔄 Retry $retries/$max_retries..."
        sleep 2
    fi
done

if [ $retries -eq $max_retries ]; then
    echo -e "${RED}❌ Clash API not accessible after restart${NC}"
    exit 1
fi

echo ""

# Step 5.1: Apply system proxy best-practices (GNOME ignore-hosts)
if command -v gsettings >/dev/null 2>&1; then
    echo "🧰 Applying GNOME proxy ignore-hosts best practices..."
    if [ -x "$ROOT_DIR/script/ensure_system_proxy_best_practices.sh" ]; then
        # Keep GNOME ports in sync with the actual running config (mixed-port or port+socks-port).
        bash "$ROOT_DIR/script/ensure_system_proxy_best_practices.sh" --set-manual-from-runtime || true
    else
        echo -e "${YELLOW}⚠️ ensure_system_proxy_best_practices.sh not found at $ROOT_DIR/script, skipping${NC}"
    fi
fi

# Step 6: Test configuration changes
echo "🧪 Testing configuration changes:"
echo "================================="

# Show current proxy group status
echo "📊 Current proxy groups:"
for _grp in AUTO PROXY COPILOT DEV VSCODE DOCKER; do
    _now=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 ${AUTH_HDR[@]+"${AUTH_HDR[@]}"} "$API/proxies/$_grp" 2>/dev/null | jq -r '.now // "N/A"' 2>/dev/null || echo "Unknown")
    printf "  %-10s → %s\n" "$_grp" "$_now"
done

echo ""

# Test OpenXLab direct connection
echo "🧪 Testing OpenXLab direct connection rules:"
echo "============================================"

domains=(
    "openxlab.org.cn"
    "sso.openxlab.org.cn"
    "mineru.net"
)

for domain in "${domains[@]}"; do
    echo -n "📍 Testing $domain: "
    
    if response=$(timeout 8 curl -s -o /dev/null -w "%{http_code},%{time_total}" \
        --connect-timeout 5 --max-time 8 \
        "https://$domain/" 2>/dev/null); then
        http_code=$(echo "$response" | cut -d',' -f1)
        time_total=$(echo "$response" | cut -d',' -f2)

        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
            echo -e "${GREEN}✅ OK${NC} (HTTP $http_code, ${time_total}s)"
        else
            echo -e "${YELLOW}⚠️ HTTP $http_code${NC} (${time_total}s)"
        fi
    else
        echo -e "${YELLOW}⚠️ Connection timeout${NC}"
    fi
done

echo ""

# Step 7: Test international services via proxy
echo "🌍 Testing international services (via proxy):"
echo "================================================"

proxy_test_domains=(
    "copilot-proxy.githubusercontent.com/_ping"
    "www.google.com"
    "github.com"
)

for url in "${proxy_test_domains[@]}"; do
    domain=$(echo "$url" | cut -d'/' -f1)
    echo -n "🔗 Testing $domain: "

    if response=$(timeout 10 curl -s -o /dev/null -w "%{http_code},%{time_total}" \
        -x http://127.0.0.1:7890 \
        --connect-timeout 5 --max-time 10 \
        "https://$url" 2>/dev/null); then
        http_code=$(echo "$response" | cut -d',' -f1)
        time_total=$(echo "$response" | cut -d',' -f2)
        http_code=${http_code:-0}
        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
            echo -e "${GREEN}✅ OK${NC} (HTTP $http_code, ${time_total}s)"
        else
            echo -e "${YELLOW}⚠️ HTTP $http_code${NC} (${time_total}s)"
        fi
    else
        echo -e "${YELLOW}⚠️ Connection timeout${NC}"
    fi
done

echo ""

# Step 8: Final summary
echo "📊 RESTART SUMMARY:"
echo "==================="
echo -e "${GREEN}✅ Mihomo service restarted successfully${NC}"
echo -e "${GREEN}✅ Configuration loaded${NC}"
echo -e "${GREEN}✅ API accessible${NC}"

echo ""
echo "🎯 CURRENT ROUTING:"
echo "=================="
_auto_now=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 3 ${AUTH_HDR[@]+"${AUTH_HDR[@]}"} "$API/proxies/AUTO" 2>/dev/null | jq -r '.now // "?"' 2>/dev/null || echo "?")
echo "  AUTO (url-test):  → $_auto_now"
echo "  COPILOT (fallback): → AUTO → $_auto_now"
echo "  DEV (fallback):     → AUTO → $_auto_now"
echo "  VSCODE (fallback):  → AUTO → $_auto_now"
echo "  DOCKER (fallback):  → AUTO → $_auto_now"
echo "  ACADEMIC (select):  → manual"
echo ""

echo "🔗 QUICK TESTS:"
echo "==============="
echo "🤖 Test AI services: ./optimize_ai.sh"
echo "📊 Full network test: ./network_connectivity_test.sh"
echo "📊 Show VPN status: ./show_vpn_status.sh"
echo ""

echo -e "${CYAN}🎉 Service restart completed successfully!${NC}"
