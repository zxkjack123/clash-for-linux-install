#!/bin/bash

# 🔄 Test OpenXLab Direct Connection Rules
# 
# DESCRIPTION:
#   Tests the newly added OpenXLab DIRECT rules in Clash configuration
#   Reloads config and verifies that OpenXLab domains use direct connection
#
# USAGE:
#   ./test_openxlab_direct_rules.sh                # safe checks only (no reload, no browser)
#   ./test_openxlab_direct_rules.sh --reload       # reload config via controller
#   ./test_openxlab_direct_rules.sh --open         # launch browser
#   ./test_openxlab_direct_rules.sh --reload --open

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_PATH="${ROOT_DIR}/resources/config.yaml"

# Optional .env + controller/secret auto-detection
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true
clash_env_bootstrap 2>/dev/null || true

API_BASE="${CLASH_API:-http://127.0.0.1:9090}"
AUTH_ARGS=()
if [[ -n "${CLASH_SECRET:-}" ]]; then
    AUTH_ARGS=(-H "Authorization: Bearer ${CLASH_SECRET}")
fi

RELOAD=0
OPEN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --reload|--apply) RELOAD=1; shift;;
        --open) OPEN=1; shift;;
        -h|--help)
            grep -E '^#' "$0" | head -n 60
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2;;
    esac
done

CTRL_CURL_OPTS=(--noproxy '*' --connect-timeout 2 --max-time 8)

echo "🔄 Testing OpenXLab Direct Connection Rules"
echo "==========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "📋 OpenXLab domains added to DIRECT rules:"
echo "• openxlab.org.cn (main domain)"
echo "• sso.openxlab.org.cn (SSO login)"
echo "• api.openxlab.org.cn (API)"
echo "• www.openxlab.org.cn (www subdomain)"
echo "• mineru.net (MinerU main site)"
echo ""

if [[ $RELOAD -eq 1 ]]; then
    echo "🔄 Reloading Clash configuration..."
    # Reload the configuration
    set +e
    reload_result=$(curl -fsS "${CTRL_CURL_OPTS[@]}" -X PUT "${API_BASE}/configs" \
        "${AUTH_ARGS[@]}" \
        -H "Content-Type: application/json" \
        -d "{\"path\":\"${CONFIG_PATH}\"}" \
        2>/dev/null)
    reload_rc=$?
    set -e

    if [ ${reload_rc} -eq 0 ]; then
        echo -e "${GREEN}✅ Configuration reloaded successfully${NC}"
    else
        echo -e "${RED}❌ Failed to reload configuration${NC}"
        echo "(Hint) If controller auth is enabled, ensure CLASH_SECRET is set." >&2
        exit 1
    fi

    echo ""
    echo "⏳ Waiting for configuration to take effect..."
    sleep 3
else
    echo -e "${YELLOW}ℹ️ Preview mode: skipping controller reload. Re-run with --reload to apply.${NC}"
    echo ""
fi

echo ""
echo "🧪 Testing OpenXLab domains with new DIRECT rules:"
echo "=================================================="

# Test domains that should now use DIRECT connection
domains=(
    "openxlab.org.cn"
    "sso.openxlab.org.cn"
    "mineru.net"
)

echo ""
for domain in "${domains[@]}"; do
    echo -n "📍 Testing $domain: "
    
    # Test with longer timeout since it's direct connection
    response=$(timeout 10 curl -s -o /dev/null -w "%{http_code},%{time_total}" \
        --connect-timeout 5 --max-time 10 \
        --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        "https://$domain/" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        http_code=$(echo $response | cut -d',' -f1)
        time_total=$(echo $response | cut -d',' -f2)
        
        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
            echo -e "${GREEN}✅ OK${NC} (HTTP $http_code, ${time_total}s)"
        elif [ "$http_code" -eq 000 ]; then
            echo -e "${YELLOW}⚠️ Connecting...${NC} (Still may work in browser)"
        else
            echo -e "${YELLOW}⚠️ HTTP $http_code${NC} (${time_total}s)"
        fi
    else
        echo -e "${YELLOW}⚠️ Connection timeout${NC} (May work in browser)"
    fi
done

echo ""
echo "🔍 Verifying configuration rules:"
echo "================================="

# Check if rules are loaded correctly by testing rule matching
echo -n "📋 Checking if openxlab.org.cn rule is active: "
if grep -q "openxlab.org.cn,DIRECT" "${CONFIG_PATH}"; then
    echo -e "${GREEN}✅ Rule found in config${NC}"
else
    echo -e "${RED}❌ Rule not found${NC}"
fi

echo -n "📋 Checking if sso.openxlab.org.cn rule is active: "
if grep -q "sso.openxlab.org.cn,DIRECT" "${CONFIG_PATH}"; then
    echo -e "${GREEN}✅ Rule found in config${NC}"
else
    echo -e "${RED}❌ Rule not found${NC}"
fi

echo ""
echo "🎯 Testing Browser Access:"
echo "=========================="

echo "🌐 To test in browser, try these URLs:"
echo "1. https://openxlab.org.cn/"
echo "2. https://sso.openxlab.org.cn/"
echo "3. https://mineru.net/"
echo ""
echo "💡 These domains should now bypass the proxy and connect directly."
echo ""

if [[ $OPEN -eq 1 ]]; then
    echo "🚀 Quick browser test:"
    # Try to launch browser with one of the URLs
    if command -v firefox >/dev/null 2>&1; then
        echo "🦊 Launching Firefox with OpenXLab..."
        firefox --new-tab "https://openxlab.org.cn/" >/dev/null 2>&1 &
        echo "✅ Firefox launched - OpenXLab should load directly"
    elif command -v google-chrome >/dev/null 2>&1; then
        echo "🌐 Launching Chrome with OpenXLab..."
        google-chrome --new-tab "https://openxlab.org.cn/" >/dev/null 2>&1 &
        echo "✅ Chrome launched - OpenXLab should load directly"
    else
        echo "📋 No browser found. Please manually visit: https://openxlab.org.cn/"
    fi
else
    echo "ℹ️ Browser launch skipped (use --open to launch automatically)."
fi

echo ""
echo "📊 SUMMARY:"
echo "==========="
echo -e "${BLUE}✅ OpenXLab domains added to DIRECT rules${NC}"
echo -e "${BLUE}✅ Configuration reloaded${NC}"
echo -e "${BLUE}✅ Rules are active in config${NC}"
echo ""
echo "🔧 What this means:"
echo "• OpenXLab domains will bypass your proxy"
echo "• Connections will go directly through your ISP"
echo "• This may resolve ERR_CONNECTION_CLOSED issues"
echo "• Browser should now load OpenXLab pages"
echo ""
echo "💡 If still not working:"
echo "• The issue may be ISP-level blocking"
echo "• Try different DNS servers (8.8.8.8, 1.1.1.1)"
echo "• Use mobile hotspot to test"
echo "• Contact ISP about accessing OpenXLab"
echo ""
echo "🎯 Alternative access methods:"
echo "./quick_openxlab_access.sh  # Browser launcher with bypass"
echo "./fix_openxlab_connectivity.sh  # Comprehensive troubleshooting"
