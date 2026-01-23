#!/usr/bin/env bash

# 🧠 Enhanced AI Optimization with Braintrust.dev Support
# 
# DESCRIPTION:
#   Enhanced AI optimization that includes Braintrust.dev and related AI development platforms
#   Tests and optimizes for comprehensive AI development workflow
#
# USAGE:
#   ./optimize_ai_enhanced.sh          # preview (will restore original node)
#   ./optimize_ai_enhanced.sh --apply  # keep the best node
#
# WHAT IT DOES:
#   • Tests key AI nodes for Braintrust.dev, OpenAI, Claude, and development platforms
#   • Measures performance for AI development workflows
#   • Automatically selects best performing node for AI development
#   • Includes Braintrust.dev-specific optimization
#
# WHEN TO USE:
#   • Before AI development work involving Braintrust.dev
#   • When AI development tools are slow or not responding
#   • For comprehensive AI development optimization

echo "🧠 Enhanced AI Service Optimization (with Braintrust.dev)"
echo "========================================================"

set -euo pipefail

APPLY=false
GROUP="AI"
PROXY="${PROXY:-http://127.0.0.1:7890}"

usage() {
    cat <<'EOF'
Enhanced AI optimization (Braintrust/OpenAI/Claude)

Options:
    --apply         Keep the best node (default: preview; restore original)
    --group NAME    Proxy group to switch (default: AI)
    --proxy URL     Local HTTP proxy to use for probes (default: http://127.0.0.1:7890)
    -h, --help      Show help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=true; shift;;
        --group)
            [[ $# -ge 2 ]] || { echo "ERROR: --group requires a value" >&2; exit 2; }
            GROUP="$2"; shift 2;;
        --proxy)
            [[ $# -ge 2 ]] || { echo "ERROR: --proxy requires a URL" >&2; exit 2; }
            PROXY="$2"; shift 2;;
        -h|--help) usage; exit 0;;
        *) echo "Unknown arg: $1" >&2; usage; exit 2;;
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

CTRL_CURL_OPTS=(--noproxy '*' --connect-timeout 2 --max-time 6)
NET_CURL_OPTS=(--connect-timeout 8 --max-time 12 --proxy "$PROXY")

urlencode() {
    local s="$1"
    if command -v python3 >/dev/null 2>&1; then
        python3 - <<'PY' "$s"
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
    else
        # Best-effort fallback (handles spaces only)
        echo "${s// /%20}"
    fi
}

get_now_node() {
    local group="$1" enc
    enc="$(urlencode "$group")"
    if command -v jq >/dev/null 2>&1; then
        curl -fsS "${CTRL_CURL_OPTS[@]}" "${AUTH_HDR[@]}" "$API/proxies/$enc" 2>/dev/null | jq -r '.now // empty' 2>/dev/null || true
    else
        curl -fsS "${CTRL_CURL_OPTS[@]}" "${AUTH_HDR[@]}" "$API/proxies/$enc" 2>/dev/null | sed -n 's/.*"now":"\([^"]*\)".*/\1/p' | head -n1 || true
    fi
}

set_group_node() {
    local group="$1" node="$2" enc
    enc="$(urlencode "$group")"
    curl -fsS "${CTRL_CURL_OPTS[@]}" "${AUTH_HDR[@]}" -X PUT "$API/proxies/$enc" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$node\"}" >/dev/null 2>&1
}

score_for_time() {
    local t="$1"
    awk -v t="$t" 'BEGIN{ if (t<=2) print 20; else if (t<=4) print 15; else if (t<=6) print 10; else print 5 }'
}

if ! curl -fsS "${CTRL_CURL_OPTS[@]}" "${AUTH_HDR[@]}" "$API/version" >/dev/null 2>&1; then
    echo "❌ Clash controller not reachable at $API" >&2
    exit 1
fi

ORIG_NODE="$(get_now_node "$GROUP")"
if [[ -z "${ORIG_NODE:-}" ]]; then
    echo "WARN: cannot determine current node for group '$GROUP' (will still run tests)" >&2
fi

restore_on_exit() {
    $APPLY && return 0
    [[ -n "${ORIG_NODE:-}" ]] || return 0
    echo ""
    echo "↩ Restoring $GROUP to original node: $ORIG_NODE"
    set_group_node "$GROUP" "$ORIG_NODE" || true
}
trap restore_on_exit EXIT

# Test key nodes optimized for AI development platforms
NODES_TO_TEST=(
    "V1-美国01|流媒体|GPT"
    "V1-美国05|流媒体|GPT"
    "V1-美国10|流媒体|GPT"
    "V1-新加坡01|流媒体|GPT"
    "V1-新加坡02|流媒体|GPT"
    "V1-日本01|流媒体|GPT"
)

# AI Development platforms to test
declare -A TEST_PLATFORMS=(
    ["Braintrust"]="https://www.braintrust.dev/"
    ["OpenAI API"]="https://api.openai.com/"
    ["ChatGPT"]="https://chat.openai.com/"
    ["Claude"]="https://claude.ai/"
    ["Hugging Face"]="https://huggingface.co/"
    ["Replicate"]="https://replicate.com/"
)

best_node=""
best_score=0

echo "🔍 Testing AI development platforms on different nodes..."
echo ""

for node in "${NODES_TO_TEST[@]}"; do
    echo "🧪 Testing node: $node"
    
    # Switch to test node
    if ! set_group_node "$GROUP" "$node"; then
        echo "  ⚠️  Switch failed (node not available in group '$GROUP'?)"
        echo ""
        continue
    fi
    
    sleep 2  # Allow time for switch
    
    score=0
    successful_tests=0
    total_time=0
    
    for platform in "${!TEST_PLATFORMS[@]}"; do
        url="${TEST_PLATFORMS[$platform]}"
        echo -n "  📍 $platform: "
        
        # Test with timeout
        response=$(curl -s -o /dev/null -w "%{http_code},%{time_total}" "${NET_CURL_OPTS[@]}" "$url" 2>/dev/null || echo "000,12")
        http_code=$(echo "$response" | cut -d',' -f1)
        time_total=$(echo "$response" | cut -d',' -f2)
            
            if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
                echo "✅ OK (${time_total}s)"
                successful_tests=$((successful_tests + 1))
                
                # Calculate score based on response time
                score=$((score + $(score_for_time "$time_total")))
                total_time=$(awk -v a="$total_time" -v b="$time_total" 'BEGIN{ printf "%.3f", a+b }')
            else
                echo "⚠️ HTTP $http_code"
                score=$((score + 1))  # Minimal points for connection
            fi
    done
    
    # Bonus points for Braintrust.dev specifically (since it's the focus)
    echo -n "  🎯 Braintrust API test: "
    response=$(curl -s -o /dev/null -w "%{http_code},%{time_total}" "${NET_CURL_OPTS[@]}" "https://api.braintrust.dev/" 2>/dev/null || echo "000,12")
    http_code=$(echo "$response" | cut -d',' -f1)
    time_total=$(echo "$response" | cut -d',' -f2)
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
        echo "✅ OK (${time_total}s)"
        score=$((score + 10))  # Bonus for Braintrust API
    else
        echo "⚠️ HTTP $http_code"
    fi

    avg_time=$(awk -v total="$total_time" -v n="$successful_tests" 'BEGIN{ if (n>0) printf "%.3f", total/n; else print "0" }')
    success_rate=$(awk -v ok="$successful_tests" -v n="${#TEST_PLATFORMS[@]}" 'BEGIN{ if (n>0) printf "%.1f", ok*100/n; else print "0" }')
    
    echo "  📊 Score: $score/140, Success: ${success_rate}%, Avg Time: ${avg_time}s"
    echo ""
    
    # Track best performing node
    if [ $score -gt $best_score ]; then
        best_score=$score
        best_node=$node
    fi
done

echo "🏆 OPTIMIZATION RESULTS:"
echo "======================="
echo "🥇 Best Node: $best_node"
echo "🎯 Best Score: $best_score/140"
echo ""

if [ -n "$best_node" ]; then
    echo "🎯 Setting AI group to best performing node: $best_node"
    if $APPLY; then
        set_group_node "$GROUP" "$best_node" || true
    else
        echo "NOTE: preview mode (not applied). Use --apply to keep the best node."
    fi
    
    sleep 2
    
    echo ""
    echo "✅ Optimization complete! Verifying new setup..."
    echo ""
    
    # Verify the change and test key platforms
    current_node=$(get_now_node "$GROUP")
    [[ -z "${current_node:-}" ]] && current_node="Unknown"
    echo "🤖 Current AI Group: $current_node"
    echo ""
    
    echo "🧪 Quick verification test:"
    echo "  Braintrust.dev: $(curl -s -o /dev/null -w 'Status %{http_code}, %{time_total}s' "${NET_CURL_OPTS[@]}" "https://www.braintrust.dev/" 2>/dev/null || echo 'Status 000, 12s')"
    echo "  OpenAI API: $(curl -s -o /dev/null -w 'Status %{http_code}, %{time_total}s' "${NET_CURL_OPTS[@]}" "https://api.openai.com/" 2>/dev/null || echo 'Status 000, 12s')"
    echo "  Claude: $(curl -s -o /dev/null -w 'Status %{http_code}, %{time_total}s' "${NET_CURL_OPTS[@]}" "https://claude.ai/" 2>/dev/null || echo 'Status 000, 12s')"
    
    echo ""
    echo "🎉 AI development environment optimized for Braintrust.dev!"
    echo ""
    echo "💡 Tips for optimal AI development:"
    echo "  • Braintrust.dev should now load faster"
    echo "  • AI API calls should have better performance"
    echo "  • Run './test_braintrust_connectivity.sh' for detailed analysis"
    echo "  • Use './quick_vpn_check.sh' for daily status checks"
    
else
    echo "❌ No suitable node found. Please check your proxy configuration."
fi
