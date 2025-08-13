#!/bin/bash

# Quick AI Service Connectivity Test
# Tests key AI services with faster timeouts for better performance

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROXY_API="http://127.0.0.1:9090"

echo -e "${BLUE}=== Quick AI Service Test ===${NC}"

# Key AI services for testing (most important ones)
declare -A AI_TESTS=(
    ["OpenAI_API"]="https://api.openai.com/v1/models"
    ["ChatGPT"]="https://chat.openai.com"
    ["Claude"]="https://claude.ai"  
    ["Anthropic_API"]="https://api.anthropic.com/v1/messages"
)

# Test a specific node
test_node_quick() {
    local node="$1"
    echo -e "\n${BLUE}Testing: $node${NC}"
    
    # Switch to node
    curl -s -X PUT "$PROXY_API/proxies/AI" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$node\"}" > /dev/null
    
    sleep 1
    
    local score=0
    local total_time=0
    local test_count=0
    
    for service in "${!AI_TESTS[@]}"; do
        local url="${AI_TESTS[$service]}"
        printf "  %-12s: " "$service"
        
        local start_time=$(date +%s.%N)
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --proxy "http://127.0.0.1:7890" \
            --connect-timeout 5 \
            --max-time 8 \
            "$url" 2>/dev/null)
        local end_time=$(date +%s.%N)
        
        local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
        
        if [[ "$response_code" =~ ^(200|401|403|429)$ ]]; then
            echo -e "${GREEN}✓ OK${NC} (${duration}s)"
            ((score++))
            total_time=$(echo "$total_time + $duration" | bc -l 2>/dev/null || echo "$total_time")
        elif [[ "$response_code" == "000" ]]; then
            echo -e "${RED}✗ TIMEOUT${NC}"
        else
            echo -e "${YELLOW}? $response_code${NC}"
        fi
        ((test_count++))
    done
    
    local avg_time=$(echo "scale=2; $total_time / $test_count" | bc -l 2>/dev/null || echo "0")
    echo -e "  ${BLUE}Score: $score/4, Avg: ${avg_time}s${NC}"
    
    echo "$node:$score:$avg_time"
}

# Get current AI group configuration
echo "Current AI group members:"
current_ai_nodes=($(curl -s "$PROXY_API/proxies/AI" | jq -r '.all[]'))
for node in "${current_ai_nodes[@]}"; do
    echo "  - $node"
done

# Test current AI nodes
echo -e "\n${YELLOW}Testing current AI group nodes...${NC}"
results=()
for node in "${current_ai_nodes[@]}"; do
    result=$(test_node_quick "$node")
    results+=("$result")
done

# Test additional promising nodes (high-speed Asian and US nodes)
echo -e "\n${YELLOW}Testing additional high-performance nodes...${NC}"
additional_nodes=(
    "V1-新加坡01|流媒体|GPT"
    "V1-新加坡02|流媒体|GPT"
    "V1-日本01|流媒体|GPT"
    "V1-日本02|流媒体|GPT"
    "V1-台湾省01|流媒体|GPT"
    "V2-新加坡05|流媒体|GPT"
    "V2-新加坡06|流媒体|GPT"
)

for node in "${additional_nodes[@]}"; do
    result=$(test_node_quick "$node")
    results+=("$result")
done

# Sort and display results
echo -e "\n${BLUE}=== RESULTS RANKING ===${NC}"
IFS=$'\n' sorted=($(printf '%s\n' "${results[@]}" | sort -t: -k2,2nr -k3,3n))

echo -e "${GREEN}🏆 BEST NODES FOR AI SERVICES:${NC}"
best_nodes=()
rank=1

for result in "${sorted[@]}"; do
    IFS=':' read -r node score time <<< "$result"
    if [[ $score -ge 3 ]]; then
        echo -e "${GREEN}$rank. $node${NC} (Score: $score/4, Time: ${time}s)"
        best_nodes+=("$node")
    else
        echo -e "$rank. $node (Score: $score/4, Time: ${time}s)"
    fi
    ((rank++))
    [[ $rank -gt 10 ]] && break
done

# Update AI group with best node
if [[ ${#best_nodes[@]} -gt 0 ]]; then
    best_node="${best_nodes[0]}"
    echo -e "\n${YELLOW}Switching AI group to best performing node: $best_node${NC}"
    
    curl -s -X PUT "$PROXY_API/proxies/AI" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$best_node\"}"
    
    echo -e "${GREEN}✅ AI group updated to: $best_node${NC}"
    
    # Test the switch worked
    sleep 2
    current=$(curl -s "$PROXY_API/proxies/AI" | jq -r '.now')
    echo -e "Current AI group node: ${BLUE}$current${NC}"
fi

echo -e "\n${BLUE}Test completed!${NC}"
