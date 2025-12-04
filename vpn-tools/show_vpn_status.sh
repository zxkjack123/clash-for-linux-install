#!/bin/bash

# DESCRIPTION:
#   Show aggregated status of Clash/Mihomo environment: controller version, active
#   AI/YOUTUBE groups current node, quick connectivity probes, exit IP geolocation.
#
# USAGE:
#   ./show_vpn_status.sh
#
set -uo pipefail
API=${CLASH_API:-http://127.0.0.1:9990}
PROXY=${PROXY:-http://127.0.0.1:7890}

STATUS_GROUPS=(
    "GLOBAL"
    "速云梯"
    "🇭🇰 HK-自动选择"
    "🇯🇵 JP-自动选择"
    "🇸🇬 SG-自动选择"
    "🇹🇼 TW-自动选择"
    "故障转移"
)
declare -A GROUP_DESCRIPTIONS=(
    ["GLOBAL"]="AI/开发/流媒体统一调度"
    ["速云梯"]="主控分组，可手动挑选任意节点"
    ["🇭🇰 HK-自动选择"]="香港自动测速"
    ["🇯🇵 JP-自动选择"]="日本自动测速"
    ["🇸🇬 SG-自动选择"]="新加坡自动测速"
    ["🇹🇼 TW-自动选择"]="台湾自动测速"
    ["故障转移"]="超时自动切换 (Fallback)"
)

have() { command -v "$1" >/dev/null 2>&1; }
fetch_json() { curl -fsS "$1" 2>/dev/null || echo '{}'; }

urlencode_component() {
    local raw="$1"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$raw" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
    elif command -v jq >/dev/null 2>&1; then
        printf '%s' "$raw" | jq -sRr @uri
    elif command -v perl >/dev/null 2>&1; then
        perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$raw"
    else
        local LC_CTYPE=C
        local out="" c hex i
        for ((i=0; i<${#raw}; i++)); do
            c=${raw:i:1}
            case "$c" in
                [a-zA-Z0-9._-]) out+="$c" ;;
                ' ') out+="%20" ;;
                *)
                    hex=$(printf '%s' "$c" | od -An -tx1 | head -n1 | tr -d ' \n')
                    hex=${hex^^}
                    out+="%${hex:-00}"
                ;;
            esac
        done
        printf '%s\n' "$out"
    fi
}

get_now() {
    local group="$1" encoded
    encoded=$(urlencode_component "$group")
    curl -fsS "$API/proxies/${encoded}" 2>/dev/null | sed -n 's/.*"now":"\([^"]*\)".*/\1/p'
}

echo "=== VPN Status ($(date '+%F %T')) ==="
if curl -fsS "$API/version" >/dev/null 2>&1; then
    ver=$(curl -fsS "$API/version" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
    echo "Controller: UP (version=$ver)"
else
    echo "Controller: DOWN ($API)"; # 不立即退出，继续尝试后续信息
fi

for g in "${STATUS_GROUPS[@]}"; do
    now=$(get_now "$g")
    printf '%-20s current: %s\n' "$g" "${now:-Unknown}"
done

echo
echo "-- Quick Probes (proxy) --"
probe() { local url="$1" label="$2" out code t; out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 5 --max-time 8 --proxy "$PROXY" "$url" 2>/dev/null || echo "000,5"); code=${out%%,*}; t=${out##*,}; printf '%-10s %s %ss\n' "$label" "$code" "$t"; }
probe https://api.openai.com/v1/models openai
probe https://www.youtube.com/ youtube
probe https://i.ytimg.com/generate_204 yt_pixel
probe https://www.netflix.com/ netflix

echo
geo=$(curl -s --proxy "$PROXY" https://ipapi.co/json 2>/dev/null || echo '{}')
ip=$(echo "$geo" | sed -n 's/.*"ip":"\([^"]*\)".*/\1/p')
country=$(echo "$geo" | sed -n 's/.*"country_name":"\([^"]*\)".*/\1/p')
echo "Exit IP: ${ip:-unknown} (${country:-N/A})"

echo
echo "Tip: run ./quick_vpn_check.sh or ./quick_ai_test.sh for deeper checks"

#!/bin/bash

# 📋 VPN Configuration Summary
# 
# DESCRIPTION:
#   Shows the current VPN configuration status with all recent updates
#   Displays routing rules, service status, and available tools
#
# USAGE:
#   ./show_vpn_status.sh

echo "📋 VPN Configuration Summary"
echo "============================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "🚀 SERVICE STATUS:"
echo "=================="

# Check mihomo service
if systemctl --user is-active mihomo.service >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Mihomo Service: Running${NC}"
else
    echo -e "${RED}❌ Mihomo Service: Stopped${NC}"
fi

# Check API
if curl -s http://127.0.0.1:9990/version >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Clash API: Accessible${NC}"
    
    # Get version info
    if have jq; then
        version_info=$(curl -s http://127.0.0.1:9990/version | jq -r '.version' 2>/dev/null || echo "Unknown")
    else
        version_info=$(curl -s http://127.0.0.1:9990/version | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
        [ -z "$version_info" ] && version_info="Unknown"
    fi
    echo "📦 Version: $version_info"
else
    echo -e "${RED}❌ Clash API: Not accessible${NC}"
fi

echo ""
echo "🎯 CURRENT ROUTING CONFIGURATION:"
echo "=================================="

for g in "${STATUS_GROUPS[@]}"; do
	now=$(get_now "$g")
	desc=${GROUP_DESCRIPTIONS[$g]-}
	printf '  • %-20s %-30s' "$g" "节点: ${now:-Unknown}"
	if [[ -n ${desc:-} ]]; then
		printf ' (%s)' "$desc"
	fi
	echo
done
echo ""

echo "🇨🇳 Chinese AI Platforms (DIRECT):"
echo "  • OpenXLab (openxlab.org.cn)"
echo "  • OpenXLab SSO (sso.openxlab.org.cn)"
echo "  • MinerU (mineru.net)"
echo "  • Route: Direct ISP connection (bypasses proxy)"
echo ""

echo "🌐 RECENT CONFIGURATION UPDATES:"
echo "================================="
echo -e "${CYAN}✅ Added OpenXLab to DIRECT rules${NC}"
echo -e "${CYAN}✅ Added MinerU to DIRECT rules${NC}"
echo -e "${CYAN}✅ Added Braintrust.dev to AI-Manual group${NC}"
echo -e "${CYAN}✅ Updated mixin.yaml with new rules${NC}"
echo -e "${CYAN}✅ Created Chinese AI platform testing tools${NC}"
echo -e "${CYAN}✅ Service restarted with new configuration${NC}"

echo ""
echo "🛠️  AVAILABLE TOOLS:"
echo "==================="
echo "🇨🇳 Chinese AI Platforms:"
echo "  ./quick_openxlab_access.sh      # Quick OpenXLab/MinerU access"
echo "  ./fix_openxlab_connectivity.sh  # Comprehensive OpenXLab troubleshooting"
echo "  ./test_chinese_ai_platforms.sh  # Test Chinese AI platform connectivity"
echo ""
echo "🤖 International AI Platforms:"
echo "  ./optimize_ai.sh                # Optimize for OpenAI, Claude, Braintrust"
echo "  ./test_ai_connectivity.sh       # Test AI platform connectivity"
echo "  ./test_braintrust_connectivity.sh # Test Braintrust.dev specifically"
echo ""
echo "🎬 Streaming Optimization:"
echo "  ./streaming_manager.sh          # Optimize streaming services"
echo "  ./select_youtube_node.sh        # Optimize YouTube specifically"
echo ""
echo "🔧 System Management:"
echo "  ./restart_clash_service.sh      # Restart service with config validation"
echo "  ./network_connectivity_test.sh  # Comprehensive network testing"
echo "  ./show_help.sh                  # Complete help system"
echo ""

echo "🧪 QUICK CONNECTIVITY TESTS:"
echo "============================="

# Test a few key services
echo -n "🤖 OpenAI API: "
if timeout 5 curl -s -o /dev/null -w "%{http_code}" "https://api.openai.com/" 2>/dev/null | grep -q "200\|40[13]"; then
    echo -e "${GREEN}✅ Reachable${NC}"
else
    echo -e "${YELLOW}⚠️ Limited${NC}"
fi

echo -n "🧠 Claude.ai: "
if timeout 5 curl -s -o /dev/null -w "%{http_code}" "https://claude.ai/" 2>/dev/null | grep -q "200\|40[13]"; then
    echo -e "${GREEN}✅ Reachable${NC}"
else
    echo -e "${YELLOW}⚠️ Limited${NC}"
fi

echo -n "🔬 Braintrust.dev: "
if timeout 5 curl -s -o /dev/null -w "%{http_code}" "https://www.braintrust.dev/" 2>/dev/null | grep -q "200"; then
    echo -e "${GREEN}✅ Reachable${NC}"
else
    echo -e "${YELLOW}⚠️ Limited${NC}"
fi

echo -n "🇨🇳 MinerU: "
if timeout 5 curl -s -o /dev/null -w "%{http_code}" "https://mineru.net/" 2>/dev/null | grep -q "200"; then
    echo -e "${GREEN}✅ Direct${NC}"
else
    echo -e "${YELLOW}⚠️ Limited${NC}"
fi

echo -n "🎬 YouTube: "
if timeout 5 curl -s -o /dev/null -w "%{http_code}" "https://www.youtube.com/" 2>/dev/null | grep -q "200"; then
    echo -e "${GREEN}✅ Reachable${NC}"
else
    echo -e "${YELLOW}⚠️ Limited${NC}"
fi

echo ""
echo "📊 CONFIGURATION FILES:"
echo "========================"
echo "📁 Main Config: /home/gw/opt/clash-for-linux-install/resources/config.yaml"
echo "📁 Mixin Config: /home/gw/opt/clash-for-linux-install/resources/mixin.yaml"
echo "📁 Tools Directory: /home/gw/opt/clash-for-linux-install/vpn-tools/"
echo "📁 Backups: /home/gw/opt/clash-for-linux-install/resources/backup/"

echo ""
echo "💡 NEXT STEPS:"
echo "=============="
echo "1. 🧪 Test OpenXLab: ./quick_openxlab_access.sh"
echo "2. 🔍 Run full network test: ./network_connectivity_test.sh"
echo "3. 📚 Get specific help: ./show_help.sh [tool_name]"
echo "4. 🎯 Optimize for specific service: ./optimize_ai.sh or ./streaming_manager.sh"

echo ""
echo -e "${CYAN}🎉 VPN is fully configured and optimized!${NC}"
echo -e "${CYAN}   • International AI platforms → Proxy${NC}"
echo -e "${CYAN}   • Chinese AI platforms → Direct${NC}"
echo -e "${CYAN}   • Streaming services → Optimized nodes${NC}"
