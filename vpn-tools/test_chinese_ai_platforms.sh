#!/bin/bash

# 🇨🇳 Chinese AI Platforms Connectivity Test
# 
# DESCRIPTION:
#   Specialized testing for Chinese AI platforms including OpenXLab, MinerU, and others
#   Tests different proxy configurations to find optimal routing for Chinese services
#
# USAGE:
#   ./test_chinese_ai_platforms.sh
#
# WHAT IT DOES:
#   • Tests OpenXLab SSO and main site
#   • Tests MinerU and related Chinese AI platforms
#   • Tests different proxy nodes (HK, SG, CN-friendly nodes)
#   • Provides optimization recommendations for Chinese AI services
#
# WHEN TO USE:
#   • When OpenXLab or Chinese AI platforms are not accessible
#   • Before using MinerU, OpenXLab, or other Chinese AI tools
#   • When getting ERR_CONNECTION_CLOSED from Chinese sites

echo "🇨🇳 Chinese AI Platforms Connectivity Test"
echo "==========================================="

set -uo pipefail

APPLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply|--yes) APPLY=1; shift;;
        -h|--help)
            echo "Usage: $0 [--apply]" >&2
            echo "  --apply  Allow node switching and apply best node to AI group" >&2
            exit 0;;
        *) echo "Unknown arg: $1" >&2; exit 2;;
    esac
done

# Optional env bootstrap (controller URL + secret)
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
if [[ -f "$SCRIPT_DIR/load_env.sh" ]]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/load_env.sh" 2>/dev/null || true
fi

API="${CLASH_API:-http://127.0.0.1:9090}"
AUTH_HDR=()
_hdr="$(clash_auth_header 2>/dev/null || true)"
[[ -n "${_hdr:-}" ]] && AUTH_HDR=(-H "${_hdr}")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Chinese AI platforms to test
declare -A CHINESE_AI_SITES=(
    ["OpenXLab SSO"]="https://sso.openxlab.org.cn/"
    ["OpenXLab Main"]="https://openxlab.org.cn/"
    ["MinerU"]="https://mineru.net/"
    ["Baidu AI"]="https://ai.baidu.com/"
    ["Alibaba Cloud AI"]="https://www.aliyun.com/product/ai"
    ["Tencent AI"]="https://ai.qq.com/"
    ["SenseTime"]="https://www.sensetime.com/"
    ["Megvii"]="https://www.megvii.com/"
    ["iFLYTEK"]="https://www.iflytek.com/"
    ["ByteDance AI"]="https://www.volcengine.com/"
)

# Get current configuration
echo "📊 Current Network Configuration:"
if command -v jq >/dev/null 2>&1; then
    CURRENT_AI_NODE=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "${AUTH_HDR[@]}" "$API/proxies/AI" 2>/dev/null | jq -r '.now' 2>/dev/null || echo "Unknown")
    CURRENT_STREAMING_NODE=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "${AUTH_HDR[@]}" "$API/proxies/Streaming" 2>/dev/null | jq -r '.now' 2>/dev/null || echo "Unknown")
else
    CURRENT_AI_NODE=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "${AUTH_HDR[@]}" "$API/proxies/AI" 2>/dev/null | sed -n 's/.*"now":"\([^"]*\)".*/\1/p' || echo "Unknown")
    CURRENT_STREAMING_NODE=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "${AUTH_HDR[@]}" "$API/proxies/Streaming" 2>/dev/null | sed -n 's/.*"now":"\([^"]*\)".*/\1/p' || echo "Unknown")
fi
echo "🤖 AI Group: $CURRENT_AI_NODE"
echo "🎬 Streaming Group: $CURRENT_STREAMING_NODE"
echo ""

# Test current node performance for Chinese AI sites
echo "🔍 Testing Current Node Performance:"
echo "===================================="

total_tests=0
successful_tests=0
failed_tests=0

for site_name in "${!CHINESE_AI_SITES[@]}"; do
    url="${CHINESE_AI_SITES[$site_name]}"
    echo -n "📍 Testing $site_name... "
    
    # Test with extended timeout and specific options for Chinese sites
    response=$(curl -s -o /dev/null -w "%{http_code},%{time_total},%{size_download}" \
        --connect-timeout 15 --max-time 30 \
        --retry 2 --retry-delay 1 \
        --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        "$url" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        http_code=$(echo $response | cut -d',' -f1)
        time_total=$(echo $response | cut -d',' -f2)
        size_download=$(echo $response | cut -d',' -f3)
        
        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
            echo -e "${GREEN}✅ OK${NC} (${time_total}s, ${size_download} bytes)"
            successful_tests=$((successful_tests + 1))
        elif [ "$http_code" -eq 000 ]; then
            echo -e "${RED}❌ CONNECTION_CLOSED${NC}"
            failed_tests=$((failed_tests + 1))
        else
            echo -e "${YELLOW}⚠️ HTTP $http_code${NC} (${time_total}s)"
            failed_tests=$((failed_tests + 1))
        fi
    else
        echo -e "${RED}❌ FAILED${NC}"
        failed_tests=$((failed_tests + 1))
    fi
    
    total_tests=$((total_tests + 1))
done

echo ""
echo "📊 Current Node Performance Summary:"
echo "==================================="
success_rate=$(echo "scale=1; $successful_tests * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
echo "✅ Success Rate: $successful_tests/$total_tests (${success_rate}%)"
echo "❌ Failed: $failed_tests/$total_tests"

# Performance assessment and recommendations
echo ""
if [ "$successful_tests" -eq 0 ]; then
    echo -e "🚨 ${RED}CRITICAL${NC} - No Chinese AI platforms accessible!"
    echo ""
    echo "🔧 RECOMMENDED ACTIONS:"
    echo "1. 🇭🇰 Try Hong Kong nodes (usually best for Chinese sites)"
    echo "2. 🇸🇬 Try Singapore nodes (good for China access)"
    echo "3. 🇯🇵 Try Japan nodes (sometimes work for Chinese services)"
    echo "4. 🔄 Switch to direct connection for Chinese domestic sites"
elif [ "$successful_tests" -lt 3 ]; then
    echo -e "🔧 ${YELLOW}NEEDS OPTIMIZATION${NC} - Limited Chinese AI access"
    echo ""
    echo "💡 RECOMMENDATIONS:"
    echo "• Try different regional nodes (HK/SG preferred)"
    echo "• Some Chinese AI platforms may require direct connection"
    echo "• Consider using dedicated China-friendly nodes"
else
    echo -e "🏆 ${GREEN}GOOD${NC} - Most Chinese AI platforms accessible"
fi

echo ""
echo "🎯 Node Optimization for Chinese AI Platforms:"
echo "=============================================="

if [[ $APPLY -ne 1 ]]; then
    echo "ℹ️ Preview mode: not switching nodes and not applying any changes." 
    echo "   Re-run with --apply to test China-friendly nodes and set the best one." 
    echo ""
    echo "🔗 OpenXLab login URL (query params redacted):"
    echo "https://sso.openxlab.org.cn/mineru-login?redirect=<redacted>"
    exit 0
fi

# Test different nodes specifically for Chinese AI access
CHINA_FRIENDLY_NODES=(
    "V1-香港01"
    "V1-香港02" 
    "V1-新加坡01"
    "V1-新加坡02"
    "V1-日本01"
    "V1-台湾省01"
)

echo "Testing China-friendly nodes for OpenXLab access..."
echo ""

best_node=""
best_score=0

for node in "${CHINA_FRIENDLY_NODES[@]}"; do
    # Check if node exists
    if command -v jq >/dev/null 2>&1; then
        exists=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 6 "${AUTH_HDR[@]}" "$API/proxies/AI" 2>/dev/null | jq -r '.all[]' 2>/dev/null | grep -q "$node" && echo 1 || echo 0)
    else
        exists=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 6 "${AUTH_HDR[@]}" "$API/proxies/AI" 2>/dev/null | tr ',' '\n' | sed 's/[\[\]"]//g' | grep -q "$node" && echo 1 || echo 0)
    fi

    if [[ $exists -eq 1 ]]; then
        echo "🧪 Testing node: $node"
        
        # Switch to test node
        curl -fsS --noproxy '*' --connect-timeout 2 --max-time 6 -X PUT "${AUTH_HDR[@]}" "$API/proxies/AI" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$node\"}" >/dev/null 2>&1
        
        sleep 3  # Allow time for switch
        
        score=0
        
        # Test key Chinese AI sites with this node
        echo -n "  📍 OpenXLab SSO: "
        if timeout 15 curl -s -o /dev/null --connect-timeout 10 "https://sso.openxlab.org.cn/" >/dev/null 2>&1; then
            echo "✅ OK"
            score=$((score + 20))
        else
            echo "❌ Failed"
        fi
        
        echo -n "  📍 OpenXLab Main: "
        if timeout 15 curl -s -o /dev/null --connect-timeout 10 "https://openxlab.org.cn/" >/dev/null 2>&1; then
            echo "✅ OK"
            score=$((score + 20))
        else
            echo "❌ Failed"
        fi
        
        echo -n "  📍 MinerU: "
        if timeout 15 curl -s -o /dev/null --connect-timeout 10 "https://mineru.net/" >/dev/null 2>&1; then
            echo "✅ OK"
            score=$((score + 15))
        else
            echo "❌ Failed"
        fi
        
        echo "  📊 Score: $score/55"
        echo ""
        
        # Track best performing node
        if [ $score -gt $best_score ]; then
            best_score=$score
            best_node=$node
        fi
    else
        echo "⚠️ Node $node not available"
        echo ""
    fi
done

# Apply optimization
if [ -n "$best_node" ] && [ $best_score -gt 0 ]; then
    echo "🏆 OPTIMIZATION RESULTS:"
    echo "======================"
    echo "🥇 Best Node for Chinese AI: $best_node"
    echo "🎯 Score: $best_score/55"
    echo ""
    
    echo "🎯 Setting AI group to optimal node: $best_node"
    curl -fsS --noproxy '*' --connect-timeout 2 --max-time 6 -X PUT "${AUTH_HDR[@]}" "$API/proxies/AI" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$best_node\"}" >/dev/null 2>&1
    
    sleep 3
    
    echo ""
    echo "✅ Optimization complete! Testing OpenXLab access..."
    echo ""
    
    # Verify OpenXLab access
    echo "🧪 OpenXLab SSO Verification:"
    if timeout 15 curl -s -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" "https://sso.openxlab.org.cn/"; then
        echo "✅ OpenXLab SSO is now accessible!"
    else
        echo "❌ OpenXLab SSO still not accessible"
    fi
    
    echo ""
    echo "🎉 Chinese AI platforms optimized!"
    echo ""
    echo "💡 Usage Tips:"
    echo "• OpenXLab should now work better"
    echo "• MinerU login should be accessible"
    echo "• Try the specific URL again in your browser"
    echo "• If still having issues, try direct connection for Chinese sites"
    
else
    echo "❌ No suitable nodes found for Chinese AI platforms"
    echo ""
    echo "🔧 Alternative Solutions:"
    echo "1. Try direct connection (disable proxy) for Chinese sites"
    echo "2. Use a VPN specifically optimized for China access"
    echo "3. Contact your network administrator about China connectivity"
fi

echo ""
echo "🔗 SPECIFIC URL TO TRY:"
echo "====================="
echo "https://sso.openxlab.org.cn/mineru-login?redirect=<redacted>"
echo ""
echo "⚡ Quick Commands:"
echo "================"
echo "🔍 Test again: ./test_chinese_ai_platforms.sh"
echo "🎮 Manage nodes: ./streaming_manager.sh"
echo "📚 Get help: ./show_help.sh"
