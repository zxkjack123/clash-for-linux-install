#!/bin/bash

# AI Connectivity Test Script
# Tests connectivity to major AI services through different proxy nodes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# AI service URLs to test
AI_SERVICES=(
    "https://api.openai.com/v1/models"
    "https://api.anthropic.com/v1/messages"
    "https://chat.openai.com"
    "https://claude.ai"
    "https://gemini.google.com"
    "https://www.perplexity.ai"
)

AI_SERVICE_NAMES=(
    "OpenAI_API"
    "Anthropic_API"
    "ChatGPT_Web"
    "Claude_Web"
    "Gemini"
    "Perplexity"
)

# Proxy API base URL
PROXY_API="http://127.0.0.1:9090"

echo -e "${BLUE}=== AI Service Connectivity Test ===${NC}"
echo -e "${YELLOW}Testing connectivity to AI services through all available proxy nodes...${NC}\n"

# Get all GPT-enabled and AI-suitable nodes
echo "Getting list of AI-capable proxy nodes..."
AI_NODES=($(curl -s "$PROXY_API/proxies" | jq -r '.proxies | keys[]' | grep -E "(GPT|日本|美国|新加坡|台湾|越南)" | grep -v "西瓜加速"))

echo -e "Found ${#AI_NODES[@]} AI-capable nodes:\n"
for node in "${AI_NODES[@]}"; do
    echo "  - $node"
done
echo ""

# Function to test single node against all AI services
test_node_ai_connectivity() {
    local node="$1"
    local results=()
    local total_score=0
    
    echo -e "${BLUE}Testing node: ${node}${NC}"
    
    # Switch to this node in AI group
    curl -s -X PUT "$PROXY_API/proxies/AI" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$node\"}" > /dev/null
    
    sleep 2  # Wait for switch to take effect
    
    # Test each AI service
    for i in "${!AI_SERVICES[@]}"; do
        local service_url="${AI_SERVICES[$i]}"
        local service_name="${AI_SERVICE_NAMES[$i]}"
        
        printf "  %-15s: " "$service_name"
        
        # Test connectivity with timeout
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --proxy "http://127.0.0.1:7890" \
            --connect-timeout 10 \
            --max-time 15 \
            "$service_url" 2>/dev/null)
        
        local latency=$(curl -s -o /dev/null -w "%{time_total}" \
            --proxy "http://127.0.0.1:7890" \
            --connect-timeout 10 \
            --max-time 15 \
            "$service_url" 2>/dev/null)
        
        if [[ "$response_code" =~ ^(200|401|403|429)$ ]]; then
            # These codes indicate the service is reachable
            echo -e "${GREEN}✓ OK${NC} (${response_code}, ${latency}s)"
            results+=("$service_name:OK:$latency")
            ((total_score += 1))
        elif [[ "$response_code" == "000" ]]; then
            echo -e "${RED}✗ TIMEOUT${NC}"
            results+=("$service_name:TIMEOUT:999")
        else
            echo -e "${YELLOW}? UNKNOWN${NC} ($response_code)"
            results+=("$service_name:UNKNOWN:$latency")
        fi
    done
    
    local avg_latency=$(echo "${results[@]}" | grep -o '[0-9.]*' | awk '{sum+=$1; count++} END {if(count>0) print sum/count; else print 999}')
    
    echo -e "  ${BLUE}Score: $total_score/${#AI_SERVICES[@]} services, Avg latency: ${avg_latency}s${NC}\n"
    
    # Return score and latency for ranking
    echo "$node:$total_score:$avg_latency"
}

# Test all nodes and collect results
echo -e "${YELLOW}Starting comprehensive AI connectivity tests...${NC}\n"
test_results=()

for node in "${AI_NODES[@]}"; do
    result=$(test_node_ai_connectivity "$node")
    test_results+=("$result")
done

# Sort results by score (descending) then by latency (ascending)
echo -e "${BLUE}=== AI Connectivity Test Results ===${NC}\n"
echo "Ranking nodes by AI service accessibility and performance:"
echo ""

IFS=$'\n' sorted_results=($(printf '%s\n' "${test_results[@]}" | sort -t: -k2,2nr -k3,3n))

echo -e "${GREEN}🏆 TOP AI NODES (Recommended for AI group):${NC}"
best_nodes=()
rank=1

for result in "${sorted_results[@]}"; do
    IFS=':' read -r node_name score latency <<< "$result"
    
    if [[ $score -ge 3 && $(echo "$latency < 5" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
        if [[ $rank -le 5 ]]; then
            echo -e "${GREEN}$rank. $node_name${NC} - Score: $score/6, Latency: ${latency}s"
            best_nodes+=("$node_name")
        else
            echo -e "$rank. $node_name - Score: $score/6, Latency: ${latency}s"
        fi
    else
        echo -e "${YELLOW}$rank. $node_name${NC} - Score: $score/6, Latency: ${latency}s"
    fi
    ((rank++))
done

echo ""
echo -e "${BLUE}=== AI GROUP CONFIGURATION RECOMMENDATION ===${NC}"
echo ""
echo "Based on connectivity tests, recommended AI group nodes:"
for node in "${best_nodes[@]:0:8}"; do
    echo "  ✓ $node"
done

# Generate configuration update command
echo ""
echo -e "${YELLOW}To update the AI group with best performing nodes:${NC}"
echo ""
echo "curl -s -X PUT '$PROXY_API/proxies/AI' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"name\":\"${best_nodes[0]}\"}'"

echo ""
echo -e "${GREEN}Test completed! Best node for AI services: ${best_nodes[0]}${NC}"
