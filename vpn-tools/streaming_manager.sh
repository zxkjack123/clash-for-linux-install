#!/bin/bash

# 🎮 Interactive Streaming Manager Script
# 
# DESCRIPTION:
#   Easy streaming group management with regional switching and performance testing
#   One-command solution for streaming optimization across different regions
#
# USAGE:
#   ./streaming_manager.sh [command]
#
# COMMANDS:
#   status    - Show current streaming configuration and node
#   test      - Test current streaming node performance
#   auto      - Auto-select best streaming node
#   list      - List all available streaming nodes by region
#   us        - Switch to US streaming nodes
#   sg        - Switch to Singapore streaming nodes  
#   jp        - Switch to Japan streaming nodes
#   hk        - Switch to Hong Kong streaming nodes
#   tw        - Switch to Taiwan streaming nodes
#   vn        - Switch to Vietnam streaming nodes
#
# WHAT IT DOES:
#   • Interactive streaming group management
#   • One-command regional switching
#   • Performance testing and verification
#   • Status monitoring and reporting
#   • Regional node recommendations
#
# WHEN TO USE:
#   • Need to switch streaming regions quickly
#   • Want to test different regional nodes for content
#   • Regular streaming performance management
#   • Accessing region-specific content (Netflix regions, etc.)
#   • Troubleshooting streaming performance
#
# DURATION: 
#   • Status/List: Instant
#   • Test: 30 seconds
#   • Regional switch: 5-10 seconds
#   • Auto-select: 2-3 minutes
#
# REGIONAL SPECIALTIES:
#   🇺🇸 US: Best for Netflix US, Hulu, US content
#   🇭🇰 HK: Best for Asian content, fastest for China users
#   🇸🇬 SG: Best Asia-Pacific performance, good for SEA content
#   🇯🇵 JP: Best for Japanese content, anime streaming
#   🇹🇼 TW: Good for Chinese content, Taiwan-specific services
#   🇻🇳 VN: Budget option, good for Southeast Asian content
#
# EXAMPLE OUTPUT:
#   🎮 Streaming Manager
#   
#   📊 Current Status:
#   🎬 Streaming Group: V1-香港01
#   📍 Current Region: Hong Kong
#   🔍 Performance: Excellent (1.2s YouTube load)
#   
#   💡 Quick Commands:
#   ./streaming_manager.sh us    # Switch to US
#   ./streaming_manager.sh test  # Test current node
#   ./streaming_manager.sh auto  # Auto-optimize

echo "🎬 Streaming Group Manager"
echo "========================="

show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  status    - Show current streaming configuration"
    echo "  test      - Quick test current streaming node"
    echo "  us        - Switch to US streaming node"
    echo "  sg        - Switch to Singapore node"
    echo "  jp        - Switch to Japan node"
    echo "  hk        - Switch to Hong Kong node"
    echo "  tw        - Switch to Taiwan node"
    echo "  list      - List all available streaming nodes"
    echo "  auto      - Auto-select best node for YouTube"
    echo ""
}

show_status() {
    echo "📊 Current Streaming Group Status:"
    echo "================================="
    local config=$(curl -s "http://127.0.0.1:9090/proxies/Streaming")
    echo "Current Node: $(echo "$config" | jq -r '.now')"
    echo "Group Type: $(echo "$config" | jq -r '.type')"
    echo "Total Members: $(echo "$config" | jq '.all | length')"
    
    echo ""
    echo "📍 Current Location:"
    curl -s --proxy http://127.0.0.1:7890 --max-time 5 http://ip-api.com/json | jq -r '"IP: " + .query + " (" + .country + ", " + .city + ")"'
}

test_current() {
    echo "🧪 Testing Current Streaming Node:"
    echo "================================="
    
    local current=$(curl -s "http://127.0.0.1:9090/proxies/Streaming" | jq -r '.now')
    echo "Testing: $current"
    echo ""
    
    # YouTube test
    echo -n "🎥 YouTube: "
    if timeout 8 curl -s --proxy http://127.0.0.1:7890 "https://www.youtube.com" | grep -q -i "youtube" 2>/dev/null; then
        echo "✅ Working"
    else
        echo "❌ Failed"
    fi
    
    # Netflix test
    echo -n "🎬 Netflix: "
    local netflix_code=$(curl -s -o /dev/null -w "%{http_code}" --proxy http://127.0.0.1:7890 --max-time 8 "https://www.netflix.com" 2>/dev/null)
    if [[ "$netflix_code" =~ ^(200|301|302)$ ]]; then
        echo "✅ Working ($netflix_code)"
    else
        echo "❌ Blocked ($netflix_code)"
    fi
    
    # Speed test
    echo -n "⚡ Speed Test: "
    local start=$(date +%s.%N)
    if timeout 5 curl -s --proxy http://127.0.0.1:7890 "https://www.google.com" >/dev/null 2>&1; then
        local end=$(date +%s.%N)
        local duration=$(echo "$end - $start" | bc -l 2>/dev/null || echo "unknown")
        echo "${duration}s"
    else
        echo "TIMEOUT"
    fi
}

switch_region() {
    local region="$1"
    local node=""
    
    case "$region" in
        "us") node="V1-美国01|流媒体|GPT" ;;
        "sg") node="V1-新加坡01|流媒体|GPT" ;;
        "jp") node="V1-日本01|流媒体|GPT" ;;
        "hk") node="V1-香港01" ;;
        "tw") node="V1-台湾省01|流媒体|GPT" ;;
        *) echo "❌ Unknown region: $region"; return 1 ;;
    esac
    
    echo "🔄 Switching to $region node: $node"
    
    curl -s -X PUT "http://127.0.0.1:9090/proxies/Streaming" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$node\"}" >/dev/null
    
    sleep 2
    
    local current=$(curl -s "http://127.0.0.1:9090/proxies/Streaming" | jq -r '.now')
    echo "✅ Switched to: $current"
    
    # Quick verification
    echo -n "📍 New IP: "
    curl -s --proxy http://127.0.0.1:7890 --max-time 5 http://ip-api.com/json | jq -r '.query + " (" + .country + ")"'
}

list_nodes() {
    echo "📋 Available Streaming Nodes:"
    echo "============================="
    
    local config=$(curl -s "http://127.0.0.1:9090/proxies/Streaming")
    local current=$(echo "$config" | jq -r '.now')
    
    echo "$config" | jq -r '.all[]' | while read -r node; do
        if [[ "$node" == "$current" ]]; then
            echo "🔸 $node (CURRENT)"
        else
            echo "  $node"
        fi
    done
}

auto_select() {
    echo "🤖 Auto-selecting best YouTube node..."
    echo "====================================="
    
    # Test a few key nodes quickly
    local candidates=("V1-美国01|流媒体|GPT" "V1-新加坡01|流媒体|GPT" "V1-日本01|流媒体|GPT")
    local best_node=""
    local best_score=0
    
    for node in "${candidates[@]}"; do
        echo "Testing: $node"
        
        curl -s -X PUT "http://127.0.0.1:9090/proxies/Streaming" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$node\"}" >/dev/null
        
        sleep 2
        
        local score=0
        if timeout 5 curl -s --proxy http://127.0.0.1:7890 "https://www.youtube.com" | grep -q -i "youtube" 2>/dev/null; then
            ((score += 2))
        fi
        if timeout 3 curl -s --proxy http://127.0.0.1:7890 "https://www.google.com" >/dev/null 2>&1; then
            ((score++))
        fi
        
        echo "  Score: $score/3"
        
        if [[ $score -gt $best_score ]]; then
            best_score=$score
            best_node="$node"
        fi
    done
    
    if [[ -n "$best_node" ]]; then
        echo ""
        echo "🎯 Best node found: $best_node (Score: $best_score/3)"
        
        curl -s -X PUT "http://127.0.0.1:9090/proxies/Streaming" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$best_node\"}" >/dev/null
        
        echo "✅ Auto-selection complete!"
    else
        echo "❌ No suitable nodes found"
    fi
}

# Main command handling
case "${1:-status}" in
    "status") show_status ;;
    "test") test_current ;;
    "us"|"sg"|"jp"|"hk"|"tw") switch_region "$1" ;;
    "list") list_nodes ;;
    "auto") auto_select ;;
    "help"|"-h"|"--help") show_usage ;;
    *) echo "❌ Unknown command: $1"; show_usage; exit 1 ;;
esac
