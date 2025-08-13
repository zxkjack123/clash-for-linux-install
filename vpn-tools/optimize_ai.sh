#!/bin/bash

# 🤖 AI Service Optimization Script
# 
# DESCRIPTION:
#   Fast optimization tool for AI services (OpenAI, ChatGPT, Claude, etc.)
#   Tests 6 key AI-capable nodes and automatically selects the best performer
#
# USAGE:
#   ./optimize_ai.sh
#
# WHAT IT DOES:
#   • Tests pre-selected high-performance AI nodes (US region)
#   • Measures OpenAI API, ChatGPT web, Claude, and Braintrust.dev connectivity
#   • Automatically switches to best performing node
#   • Provides verification and performance metrics
#
# WHEN TO USE:
#   • Before using AI services (ChatGPT, Claude, etc.)
#   • When AI services are slow or not responding
#   • Daily optimization routine
#   • Quick AI connectivity fix
#
# DURATION: 2-3 minutes
# PERFORMANCE IMPACT: Low (tests only 6 nodes)
#
# EXAMPLE OUTPUT:
#   🤖 AI Service Optimization Test
#   Testing: V1-美国01|流媒体|GPT
#     OpenAI API: ✅ OK (2.3s)
#     ChatGPT Web: ✅ OK
#     Claude: ✅ OK
#   🎯 Setting AI group to best performing node
#   ✅ AI group updated to: V1-美国05|流媒体|GPT

echo "🤖 AI Service Optimization Test"
echo "================================"

# Test key nodes for AI service performance
NODES_TO_TEST=(
    "V1-美国01|流媒体|GPT"
    "V1-美国05|流媒体|GPT"
    "V1-美国10|流媒体|GPT"
    "V1-新加坡01|流媒体|GPT"
    "V1-日本01|流媒体|GPT"
    "V1-台湾省01|流媒体|GPT"
)

test_node_performance() {
    local node="$1"
    echo ""
    echo "Testing: $node"
    
    # Switch proxy
    curl -s -X PUT "http://127.0.0.1:9090/proxies/AI" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$node\"}" >/dev/null
    
    sleep 3
    
    # Get current IP for verification
    local current_ip=$(timeout 5 curl -s --proxy http://127.0.0.1:7890 https://api.ipify.org 2>/dev/null || echo "unknown")
    echo "  IP: $current_ip"
    
    local score=0
    local total_time=0
    
    # Test 1: OpenAI API
    echo -n "  OpenAI API: "
    local start=$(date +%s.%N)
    if timeout 10 curl -s --proxy http://127.0.0.1:7890 "https://api.openai.com/v1/models" | grep -q "object.*list" 2>/dev/null; then
        local end=$(date +%s.%N)
        local time=$(echo "$end - $start" | bc -l)
        echo "✅ ${time}s"
        ((score++))
        total_time=$(echo "$total_time + $time" | bc -l)
    else
        echo "❌ FAILED"
    fi
    
    # Test 2: ChatGPT
    echo -n "  ChatGPT Web: "
    local start=$(date +%s.%N)
    if timeout 8 curl -s --proxy http://127.0.0.1:7890 "https://chat.openai.com" | grep -q -i "openai\|chatgpt" 2>/dev/null; then
        local end=$(date +%s.%N)
        local time=$(echo "$end - $start" | bc -l)
        echo "✅ ${time}s"
        ((score++))
        total_time=$(echo "$total_time + $time" | bc -l)
    else
        echo "❌ FAILED"
    fi
    
    # Test 3: Claude
    echo -n "  Claude: "
    local start=$(date +%s.%N)
    if timeout 8 curl -s --proxy http://127.0.0.1:7890 "https://claude.ai" | grep -q -i "claude\|anthropic" 2>/dev/null; then
        local end=$(date +%s.%N)
        local time=$(echo "$end - $start" | bc -l)
        echo "✅ ${time}s"
        ((score++))
        total_time=$(echo "$total_time + $time" | bc -l)
    else
        echo "❌ FAILED"
    fi
    
    # Test 4: Braintrust.dev
    echo -n "  Braintrust.dev: "
    local start=$(date +%s.%N)
    if timeout 8 curl -s --proxy http://127.0.0.1:7890 "https://www.braintrust.dev" | grep -q -i "braintrust\|ai" 2>/dev/null; then
        local end=$(date +%s.%N)
        local time=$(echo "$end - $start" | bc -l)
        echo "✅ ${time}s"
        ((score++))
        total_time=$(echo "$total_time + $time" | bc -l)
    else
        echo "❌ FAILED"
    fi
    
    local avg_time="0"
    if [[ $score -gt 0 ]]; then
        avg_time=$(echo "scale=2; $total_time / $score" | bc -l)
    fi
    
    echo "  📊 Score: $score/4, Avg time: ${avg_time}s"
    
    # Return score and time for ranking
    echo "$node|$score|$avg_time|$current_ip"
}

# Test all nodes
echo "Testing selected AI nodes..."
results=()

for node in "${NODES_TO_TEST[@]}"; do
    result=$(test_node_performance "$node")
    results+=("$result")
done

echo ""
echo "🏆 RESULTS RANKING"
echo "=================="

# Sort by score (desc) then by time (asc)
IFS=$'\n' sorted=($(printf '%s\n' "${results[@]}" | sort -t'|' -k2,2nr -k3,3n))

echo ""
best_node=""
rank=1

for result in "${sorted[@]}"; do
    IFS='|' read -r node score time ip <<< "$result"
    
    if [[ $score -eq 4 ]]; then
        echo "🥇 $rank. $(echo "$node" | cut -d'|' -f1) - PERFECT (${score}/4, ${time}s, IP: $ip)"
        [[ -z "$best_node" ]] && best_node="$node"
    elif [[ $score -eq 3 ]]; then
        echo "🥈 $rank. $(echo "$node" | cut -d'|' -f1) - EXCELLENT (${score}/4, ${time}s, IP: $ip)"
        [[ -z "$best_node" ]] && best_node="$node"
    elif [[ $score -eq 2 ]]; then
        echo "� $rank. $(echo "$node" | cut -d'|' -f1) - GOOD (${score}/4, ${time}s, IP: $ip)"
        [[ -z "$best_node" ]] && best_node="$node"
    else
        echo "🔧 $rank. $(echo "$node" | cut -d'|' -f1) - NEEDS WORK (${score}/4, ${time}s, IP: $ip)"
    fi
    ((rank++))
done

# Apply best configuration
if [[ -n "$best_node" ]]; then
    echo ""
    echo "🎯 OPTIMIZING AI GROUP"
    echo "====================="
    echo "Setting AI group to best performing node: $best_node"
    
    curl -s -X PUT "http://127.0.0.1:9090/proxies/AI" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$best_node\"}" >/dev/null
    
    sleep 2
    
    # Verify the change
    current=$(curl -s "http://127.0.0.1:9090/proxies/AI" | jq -r '.now')
    echo "✅ AI group now using: $current"
    
    # Final verification test
    echo ""
    echo "🔍 VERIFICATION TEST"
    echo "==================="
    echo -n "Final IP check: "
    curl -s --proxy http://127.0.0.1:7890 --max-time 5 https://api.ipify.org && echo ""
    
    echo -n "OpenAI API test: "
    if timeout 5 curl -s --proxy http://127.0.0.1:7890 "https://api.openai.com/v1/models" | grep -q "object.*list" 2>/dev/null; then
        echo "✅ Working"
    else
        echo "❌ Failed"
    fi
    
    echo -n "Braintrust.dev test: "
    if timeout 5 curl -s --proxy http://127.0.0.1:7890 "https://www.braintrust.dev" | grep -q -i "braintrust" 2>/dev/null; then
        echo "✅ Working"
    else
        echo "❌ Failed"
    fi
else
    echo "❌ No suitable nodes found for AI services"
fi

echo ""
echo "🏁 Optimization complete!"
