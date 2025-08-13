#!/bin/bash

echo "=== Testing AI Group Nodes for AI Service Connectivity ==="
echo ""

# Current AI group nodes
AI_NODES=(
    "V1-美国01|流媒体|GPT"
    "V1-美国02|流媒体|GPT" 
    "V1-美国03|流媒体|GPT"
    "V1-美国04|流媒体|GPT"
    "V1-美国05|流媒体|GPT"
    "V1-美国06|流媒体|GPT"
    "V1-美国07|流媒体|GPT"
    "V1-美国08|流媒体|GPT"
    "V1-美国09|流媒体|GPT"
    "V1-美国10|流媒体|GPT"
)

# Additional nodes to test
ADDITIONAL_NODES=(
    "V1-新加坡01|流媒体|GPT"
    "V1-新加坡02|流媒体|GPT"
    "V1-日本01|流媒体|GPT"
    "V1-日本02|流媒体|GPT"
    "V1-台湾省01|流媒体|GPT"
    "V1-越南01|GPT"
)

# Test function
test_node() {
    local node="$1"
    echo "Testing: $node"
    
    # Switch to node
    curl -s -X PUT "http://127.0.0.1:9090/proxies/AI" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$node\"}" >/dev/null
    
    sleep 2
    
    # Test AI services
    local score=0
    
    # Test OpenAI API
    echo -n "  OpenAI API: "
    if timeout 8 curl -s --proxy http://127.0.0.1:7890 https://api.openai.com/v1/models | grep -q "gpt" 2>/dev/null; then
        echo "✅ OK"
        ((score++))
    else
        echo "❌ FAILED"
    fi
    
    # Test ChatGPT
    echo -n "  ChatGPT: "
    if timeout 8 curl -s --proxy http://127.0.0.1:7890 https://chat.openai.com | grep -q "OpenAI" 2>/dev/null; then
        echo "✅ OK"
        ((score++))
    else
        echo "❌ FAILED"
    fi
    
    # Test Claude
    echo -n "  Claude: "
    if timeout 8 curl -s --proxy http://127.0.0.1:7890 https://claude.ai | grep -q -i "claude\|anthropic" 2>/dev/null; then
        echo "✅ OK"
        ((score++))
    else
        echo "❌ FAILED"
    fi
    
    # Test speed with a simple request
    echo -n "  Speed test: "
    local start_time=$(date +%s.%N)
    if timeout 5 curl -s --proxy http://127.0.0.1:7890 https://www.google.com >/dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "N/A")
        echo "${duration}s"
    else
        echo "TIMEOUT"
        duration="999"
    fi
    
    echo "  Score: $score/3"
    echo ""
    
    # Return score and duration for sorting
    echo "$node:$score:$duration"
}

# Test all nodes
echo "Testing current AI group nodes..."
results=()

for node in "${AI_NODES[@]}"; do
    result=$(test_node "$node")
    results+=("$result")
done

echo "Testing additional promising nodes..."
for node in "${ADDITIONAL_NODES[@]}"; do
    result=$(test_node "$node") 
    results+=("$result")
done

# Sort results by score (descending) then by duration (ascending)
echo "=== RESULTS ==="
echo ""
IFS=$'\n' sorted=($(printf '%s\n' "${results[@]}" | sort -t: -k2,2nr -k3,3n))

echo "🏆 BEST NODES FOR AI SERVICES:"
best_nodes=()
rank=1

for result in "${sorted[@]}"; do
    IFS=':' read -r node score duration <<< "$result"
    
    if [[ $score -eq 3 ]]; then
        echo "✅ $rank. $node (Perfect: $score/3, ${duration}s)"
        best_nodes+=("$node")
    elif [[ $score -eq 2 ]]; then
        echo "🟡 $rank. $node (Good: $score/3, ${duration}s)"
        [[ ${#best_nodes[@]} -lt 5 ]] && best_nodes+=("$node")
    else
        echo "🔴 $rank. $node (Poor: $score/3, ${duration}s)"
    fi
    ((rank++))
done

# Set best node
if [[ ${#best_nodes[@]} -gt 0 ]]; then
    best_node="${best_nodes[0]}"
    echo ""
    echo "🎯 Setting AI group to best node: $best_node"
    curl -s -X PUT "http://127.0.0.1:9090/proxies/AI" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$best_node\"}" >/dev/null
    
    sleep 2
    current=$(curl -s "http://127.0.0.1:9090/proxies/AI" | jq -r '.now')
    echo "✅ AI group now using: $current"
fi

echo ""
echo "Test completed!"
