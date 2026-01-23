#!/bin/bash

# 🧠 Braintrust.dev AI Services Connectivity Test
# 
# DESCRIPTION:
#   Comprehensive testing for Braintrust.dev and related AI development platforms
#   Tests connectivity and performance across different proxy nodes
#
# USAGE:
#   ./test_braintrust_connectivity.sh
#
# WHAT IT DOES:
#   • Tests Braintrust.dev main site and API endpoints
#   • Tests related AI development platforms
#   • Measures response times and reliability
#   • Finds optimal nodes for AI development tools
#   • Provides recommendations for best performance
#
# WHEN TO USE:
#   • Before using Braintrust AI development tools
#   • When Braintrust.dev is slow or not accessible
#   • For AI development workflow optimization
#   • Setting up optimal nodes for AI development

echo "🧠 Braintrust.dev AI Services Connectivity Test"
echo "==============================================="

set -uo pipefail

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
NC='\033[0m' # No Color

# Test sites for Braintrust and related AI development platforms
declare -A TEST_SITES=(
    ["Braintrust Main"]="https://www.braintrust.dev/"
    ["Braintrust App"]="https://app.braintrust.dev/"
    ["Braintrust API"]="https://api.braintrust.dev/"
    ["Braintrust Docs"]="https://docs.braintrust.dev/"
    ["OpenAI API"]="https://api.openai.com/"
    ["OpenAI Platform"]="https://platform.openai.com/"
    ["Anthropic API"]="https://api.anthropic.com/"
    ["Claude AI"]="https://claude.ai/"
    ["Hugging Face"]="https://huggingface.co/"
    ["Replicate"]="https://replicate.com/"
    ["LangChain"]="https://langchain.com/"
    ["Weights & Biases"]="https://wandb.ai/"
)

# Get current AI group
echo "📊 Current Configuration:"
if command -v jq >/dev/null 2>&1; then
    CURRENT_AI_NODE=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "${AUTH_HDR[@]}" "$API/proxies/AI" 2>/dev/null | jq -r '.now' 2>/dev/null || echo "Unknown")
else
    CURRENT_AI_NODE=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "${AUTH_HDR[@]}" "$API/proxies/AI" 2>/dev/null | sed -n 's/.*"now":"\([^"]*\)".*/\1/p' || echo "Unknown")
fi
echo "🤖 AI Group: $CURRENT_AI_NODE"
echo ""

# Test current node performance
echo "🔍 Testing Current Node Performance:"
echo "===================================="

total_tests=0
successful_tests=0
total_time=0

for site_name in "${!TEST_SITES[@]}"; do
    url="${TEST_SITES[$site_name]}"
    echo -n "📍 Testing $site_name... "
    
    # Test connectivity with timeout
    response=$(curl -s -o /dev/null -w "%{http_code},%{time_total}" --connect-timeout 10 --max-time 15 "$url" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        http_code=$(echo $response | cut -d',' -f1)
        time_total=$(echo $response | cut -d',' -f2)
        
        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
            echo -e "${GREEN}✅ OK${NC} (${time_total}s)"
            successful_tests=$((successful_tests + 1))
            total_time=$(echo "$total_time + $time_total" | bc -l 2>/dev/null || echo $total_time)
        else
            echo -e "${YELLOW}⚠️ HTTP $http_code${NC} (${time_total}s)"
        fi
    else
        echo -e "${RED}❌ Failed${NC}"
    fi
    
    total_tests=$((total_tests + 1))
done

echo ""
echo "📊 Current Node Performance Summary:"
echo "==================================="
success_rate=$(echo "scale=1; $successful_tests * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
avg_time=$(echo "scale=3; $total_time / $successful_tests" | bc -l 2>/dev/null || echo "0")

echo "✅ Success Rate: $successful_tests/$total_tests (${success_rate}%)"
echo "⏱️  Average Response Time: ${avg_time}s"

# Performance assessment
if (( $(echo "$success_rate >= 90" | bc -l 2>/dev/null || echo 0) )); then
    if (( $(echo "$avg_time <= 3" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "🏆 ${GREEN}EXCELLENT${NC} - Current node is optimal for Braintrust.dev!"
    else
        echo -e "🥈 ${YELLOW}GOOD${NC} - High success rate but slower response times"
    fi
elif (( $(echo "$success_rate >= 70" | bc -l 2>/dev/null || echo 0) )); then
    echo -e "🔧 ${YELLOW}NEEDS OPTIMIZATION${NC} - Consider trying different nodes"
else
    echo -e "🚨 ${RED}POOR${NC} - Current node needs optimization for AI development tools"
fi

echo ""

# Get available AI nodes for testing
echo "🔍 Available AI Nodes for Optimization:"
echo "======================================="

if command -v jq >/dev/null 2>&1; then
    AI_NODES=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 "${AUTH_HDR[@]}" "$API/proxies/AI" 2>/dev/null | jq -r '.all[]' 2>/dev/null | grep -E "(美国|新加坡|日本|台湾|越南).*GPT" || true)
else
    AI_NODES=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 5 "${AUTH_HDR[@]}" "$API/proxies/AI" 2>/dev/null | tr ',' '\n' | sed 's/[\[\]"]//g' | grep -E "(美国|新加坡|日本|台湾|越南).*GPT" || true)
fi

if [ -z "$AI_NODES" ]; then
    echo "❌ No AI nodes found. Please check your proxy configuration."
    exit 1
fi

echo "$AI_NODES" | nl

echo ""
echo "🎯 Optimization Recommendations:"
echo "================================"

if (( $(echo "$success_rate < 90" | bc -l 2>/dev/null || echo 1) )) || (( $(echo "$avg_time > 3" | bc -l 2>/dev/null || echo 1) )); then
    echo "🔧 Current performance can be improved. Recommendations:"
    echo ""
    echo "1. 🇺🇸 Try US nodes - Often best for Braintrust.dev (US-based service)"
    echo "   • V1-美国01|流媒体|GPT"
    echo "   • V1-美国05|流媒体|GPT"
    echo "   • V1-美国10|流媒体|GPT"
    echo ""
    echo "2. 🇸🇬 Try Singapore nodes - Good Asia-Pacific performance"
    echo "   • V1-新加坡01|流媒体|GPT"
    echo "   • V1-新加坡02|流媒体|GPT"
    echo ""
    echo "3. 🔄 Run comprehensive optimization:"
    echo "   ./optimize_ai.sh"
    echo ""
    echo "4. 🧪 Test specific nodes:"
    echo "   ./test_ai_connectivity.sh"
else
    echo "✅ Current node performance is excellent for Braintrust.dev!"
    echo "💡 No optimization needed at this time."
fi

echo ""
echo "⚡ Quick Actions:"
echo "================"
echo "🚀 Optimize AI nodes now:"
echo "   ./optimize_ai.sh"
echo ""
echo "🔍 Test all AI nodes:"
echo "   ./test_ai_connectivity.sh"
echo ""
echo "🎮 Interactive management:"
echo "   ./launcher.sh"
echo ""
echo "📚 Get help:"
echo "   ./show_help.sh ai"

echo ""
echo "💡 If you'd like to optimize now, run: ./optimize_ai.sh"
