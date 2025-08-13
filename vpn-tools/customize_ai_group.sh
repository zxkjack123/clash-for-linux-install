#!/bin/bash

echo "🎯 AI Group Customization Tool"
echo "=============================="

# Get current runtime config location
CLASH_DIR="$HOME/.local/share/clash"
CONFIG_FILE="$CLASH_DIR/runtime.yaml"

echo "📋 Current AI Group Configuration:"
curl -s "http://127.0.0.1:9090/proxies/AI" | jq '{current: .now, members: .all}'

echo ""
echo "🌍 Available AI-Capable Nodes by Region:"

# US nodes
echo "🇺🇸 US Nodes:"
curl -s "http://127.0.0.1:9090/proxies" | jq -r '.proxies | keys[]' | grep "美国.*GPT" | sed 's/^/  - /'

# Singapore nodes  
echo "🇸🇬 Singapore Nodes:"
curl -s "http://127.0.0.1:9090/proxies" | jq -r '.proxies | keys[]' | grep "新加坡.*GPT" | sed 's/^/  - /'

# Japan nodes
echo "🇯🇵 Japan Nodes:"
curl -s "http://127.0.0.1:9090/proxies" | jq -r '.proxies | keys[]' | grep "日本.*GPT" | sed 's/^/  - /'

# Taiwan nodes
echo "🇹🇼 Taiwan Nodes:"
curl -s "http://127.0.0.1:9090/proxies" | jq -r '.proxies | keys[]' | grep "台湾.*GPT" | sed 's/^/  - /'

# Vietnam nodes
echo "🇻🇳 Vietnam Nodes:"
curl -s "http://127.0.0.1:9090/proxies" | jq -r '.proxies | keys[]' | grep "越南.*GPT" | sed 's/^/  - /'

echo ""
echo "🚀 Performance Testing Top Candidates..."

# Test a representative node from each region
TEST_NODES=(
    "V1-美国05|流媒体|GPT"
    "V1-新加坡01|流媒体|GPT" 
    "V1-日本02|流媒体|GPT"
    "V1-台湾省01|流媒体|GPT"
    "V1-越南01|GPT"
)

results=()

for node in "${TEST_NODES[@]}"; do
    echo -n "Testing $node... "
    
    # Switch to node
    curl -s -X PUT "http://127.0.0.1:9090/proxies/AI" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$node\"}" >/dev/null
    
    sleep 2
    
    # Quick test
    local score=0
    if timeout 5 curl -s --proxy http://127.0.0.1:7890 "https://api.openai.com/v1/models" | grep -q "gpt" 2>/dev/null; then
        ((score++))
    fi
    if timeout 5 curl -s --proxy http://127.0.0.1:7890 "https://chat.openai.com" | grep -q -i "openai" 2>/dev/null; then
        ((score++))
    fi
    
    if [[ $score -eq 2 ]]; then
        echo "✅ Excellent"
        results+=("$node:excellent")
    elif [[ $score -eq 1 ]]; then
        echo "🟡 Good"
        results+=("$node:good")
    else
        echo "❌ Poor"
        results+=("$node:poor")
    fi
done

echo ""
echo "🎯 RECOMMENDED AI GROUP CONFIGURATION"
echo "===================================="

# Collect excellent and good nodes
excellent_nodes=()
good_nodes=()

for result in "${results[@]}"; do
    IFS=':' read -r node quality <<< "$result"
    if [[ $quality == "excellent" ]]; then
        excellent_nodes+=("$node")
    elif [[ $quality == "good" ]]; then
        good_nodes+=("$node")
    fi
done

echo "🏆 Excellent nodes (recommended for AI group):"
for node in "${excellent_nodes[@]}"; do
    echo "  ✅ $node"
done

echo ""
echo "🥈 Good nodes (backup options):"
for node in "${good_nodes[@]}"; do
    echo "  🟡 $node"
done

# Create optimal AI group config
optimal_nodes=("${excellent_nodes[@]}")
if [[ ${#optimal_nodes[@]} -lt 3 ]]; then
    optimal_nodes+=("${good_nodes[@]}")
fi

# Trim to top 8 nodes
optimal_nodes=("${optimal_nodes[@]:0:8}")

echo ""
echo "🔧 UPDATING AI GROUP CONFIGURATION"
echo "================================="

# For demonstration, let's switch to the best node
if [[ ${#excellent_nodes[@]} -gt 0 ]]; then
    best_node="${excellent_nodes[0]}"
    echo "Setting AI group to best node: $best_node"
    
    curl -s -X PUT "http://127.0.0.1:9090/proxies/AI" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$best_node\"}" >/dev/null
    
    sleep 2
    
    # Verify
    current=$(curl -s "http://127.0.0.1:9090/proxies/AI" | jq -r '.now')
    echo "✅ AI group now using: $current"
    
    # Get IP and test
    echo ""
    echo "🔍 FINAL VERIFICATION"
    echo "===================="
    echo -n "Current IP: "
    curl -s --proxy http://127.0.0.1:7890 --max-time 5 https://api.ipify.org && echo ""
    
    echo -n "OpenAI API: "
    if timeout 5 curl -s --proxy http://127.0.0.1:7890 "https://api.openai.com/v1/models" | grep -q "gpt" 2>/dev/null; then
        echo "✅ Working"
    else
        echo "❌ Failed"
    fi
    
    echo -n "ChatGPT: "
    if timeout 5 curl -s --proxy http://127.0.0.1:7890 "https://chat.openai.com" | grep -q -i "openai" 2>/dev/null; then
        echo "✅ Working"
    else
        echo "❌ Failed"
    fi
    
    echo -n "Claude: "
    if timeout 5 curl -s --proxy http://127.0.0.1:7890 "https://claude.ai" | grep -q -i "claude" 2>/dev/null; then
        echo "✅ Working"
    else
        echo "❌ Failed"
    fi
fi

echo ""
echo "💡 RECOMMENDATIONS:"
echo "- Current optimal node: $(curl -s "http://127.0.0.1:9090/proxies/AI" | jq -r '.now')"
echo "- For manual selection, use: curl -X PUT http://127.0.0.1:9090/proxies/AI -H 'Content-Type: application/json' -d '{\"name\":\"NODE_NAME\"}'"
echo "- Monitor performance and switch nodes as needed"
echo ""
echo "✅ AI group optimization complete!"
