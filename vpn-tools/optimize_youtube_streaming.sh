#!/bin/bash

echo "🎬 YouTube Streaming Optimization Tool"
echo "====================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

PROXY_API="http://127.0.0.1:9090"

# Streaming services to test
declare -A STREAMING_TESTS=(
    ["YouTube"]="https://www.youtube.com"
    ["YouTube_API"]="https://www.googleapis.com/youtube/v3/videos?part=snippet&chart=mostPopular&maxResults=1&key=dummy"
    ["Netflix"]="https://www.netflix.com"
    ["Twitch"]="https://www.twitch.tv"
    ["Vimeo"]="https://vimeo.com"
)

echo "📋 Current Streaming Group Configuration:"
curl -s "$PROXY_API/proxies/Streaming" | jq '{current: .now, type: .type, total_members: (.all | length)}'

echo ""
echo "🌍 Discovering All Streaming-Capable Nodes..."

# Get all streaming nodes by region
US_NODES=($(curl -s "$PROXY_API/proxies" | jq -r '.proxies | keys[]' | grep "美国.*流媒体"))
HK_NODES=($(curl -s "$PROXY_API/proxies" | jq -r '.proxies | keys[]' | grep "香港"))
SG_NODES=($(curl -s "$PROXY_API/proxies" | jq -r '.proxies | keys[]' | grep "新加坡.*流媒体"))
JP_NODES=($(curl -s "$PROXY_API/proxies" | jq -r '.proxies | keys[]' | grep "日本.*流媒体"))
TW_NODES=($(curl -s "$PROXY_API/proxies" | jq -r '.proxies | keys[]' | grep "台湾.*流媒体"))

ALL_STREAMING_NODES=("${US_NODES[@]}" "${HK_NODES[@]}" "${SG_NODES[@]}" "${JP_NODES[@]}" "${TW_NODES[@]}")

echo "Found ${#ALL_STREAMING_NODES[@]} streaming-capable nodes:"
echo "  🇺🇸 US: ${#US_NODES[@]} nodes"
echo "  🇭🇰 HK: ${#HK_NODES[@]} nodes" 
echo "  🇸🇬 SG: ${#SG_NODES[@]} nodes"
echo "  🇯🇵 JP: ${#JP_NODES[@]} nodes"
echo "  🇹🇼 TW: ${#TW_NODES[@]} nodes"

# Test streaming performance for a node
test_streaming_node() {
    local node="$1"
    local region="$2"
    echo ""
    echo -e "${BLUE}Testing: $node${NC}"
    
    # Switch to node
    curl -s -X PUT "$PROXY_API/proxies/Streaming" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$node\"}" >/dev/null
    
    sleep 3
    
    # Get current IP and location
    local ip_info=$(curl -s --proxy http://127.0.0.1:7890 --max-time 5 "http://ip-api.com/json" 2>/dev/null)
    local current_ip=$(echo "$ip_info" | jq -r '.query // "unknown"')
    local current_country=$(echo "$ip_info" | jq -r '.country // "unknown"')
    
    echo "  📍 IP: $current_ip ($current_country)"
    
    local score=0
    local total_time=0
    local test_count=0
    
    # Test YouTube (most important)
    echo -n "  🎥 YouTube: "
    local start_time=$(date +%s.%N)
    local youtube_status=$(curl -s -o /dev/null -w "%{http_code}" \
        --proxy "http://127.0.0.1:7890" \
        --connect-timeout 8 \
        --max-time 12 \
        "https://www.youtube.com" 2>/dev/null)
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    if [[ "$youtube_status" =~ ^(200|301|302)$ ]]; then
        echo -e "${GREEN}✅ OK${NC} (${duration}s)"
        ((score += 3))  # YouTube gets triple weight
        total_time=$(echo "$total_time + $duration" | bc -l 2>/dev/null || echo "$total_time")
    else
        echo -e "${RED}❌ FAILED${NC} ($youtube_status)"
    fi
    ((test_count++))
    
    # Test YouTube video loading speed
    echo -n "  📺 YouTube Video: "
    local start_time=$(date +%s.%N)
    local video_test=$(curl -s --proxy http://127.0.0.1:7890 \
        --connect-timeout 8 --max-time 10 \
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ" 2>/dev/null | head -c 1000)
    local end_time=$(date +%s.%N)
    local video_duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    if echo "$video_test" | grep -q -i "youtube\|video" 2>/dev/null; then
        echo -e "${GREEN}✅ OK${NC} (${video_duration}s)"
        ((score += 2))  # Video loading gets double weight
        total_time=$(echo "$total_time + $video_duration" | bc -l 2>/dev/null || echo "$total_time")
    else
        echo -e "${RED}❌ FAILED${NC}"
    fi
    ((test_count++))
    
    # Test Netflix
    echo -n "  🎬 Netflix: "
    local netflix_status=$(curl -s -o /dev/null -w "%{http_code}" \
        --proxy "http://127.0.0.1:7890" \
        --connect-timeout 6 \
        --max-time 10 \
        "https://www.netflix.com" 2>/dev/null)
    
    if [[ "$netflix_status" =~ ^(200|301|302)$ ]]; then
        echo -e "${GREEN}✅ OK${NC}"
        ((score++))
    else
        echo -e "${YELLOW}? BLOCKED${NC} ($netflix_status)"
    fi
    ((test_count++))
    
    # Test Twitch
    echo -n "  🎮 Twitch: "
    local twitch_status=$(curl -s -o /dev/null -w "%{http_code}" \
        --proxy "http://127.0.0.1:7890" \
        --connect-timeout 6 \
        --max-time 10 \
        "https://www.twitch.tv" 2>/dev/null)
    
    if [[ "$twitch_status" =~ ^(200|301|302)$ ]]; then
        echo -e "${GREEN}✅ OK${NC}"
        ((score++))
    else
        echo -e "${YELLOW}? BLOCKED${NC} ($twitch_status)"
    fi
    ((test_count++))
    
    # Calculate speed score (lower is better)
    local avg_time="999"
    if [[ $score -gt 0 ]]; then
        avg_time=$(echo "scale=2; $total_time / 2" | bc -l 2>/dev/null || echo "999")  # Only YouTube tests count for speed
    fi
    
    echo -e "  ${PURPLE}📊 Score: $score/7, Speed: ${avg_time}s${NC}"
    
    # Return data for ranking: node|score|speed|region|ip|country
    echo "$node|$score|$avg_time|$region|$current_ip|$current_country"
}

echo ""
echo -e "${YELLOW}🚀 Testing Streaming Performance...${NC}"
echo "(Testing YouTube, Netflix, Twitch for optimal streaming experience)"

# Test representative nodes from each region for initial screening
test_results=()

echo ""
echo -e "${BLUE}Phase 1: Regional Representative Testing${NC}"

# Test 2 best nodes from each region
for region_nodes in "US:${US_NODES[*]:0:2}" "HK:${HK_NODES[*]:0:2}" "SG:${SG_NODES[*]:0:2}" "JP:${JP_NODES[*]:0:2}" "TW:${TW_NODES[*]:0:1}"; do
    IFS=':' read -r region nodes <<< "$region_nodes"
    
    for node in $nodes; do
        if [[ -n "$node" ]]; then
            result=$(test_streaming_node "$node" "$region")
            test_results+=("$result")
        fi
    done
done

echo ""
echo -e "${BLUE}Phase 2: Top Performers Extended Testing${NC}"

# Sort initial results and test more nodes from top regions
IFS=$'\n' sorted_initial=($(printf '%s\n' "${test_results[@]}" | sort -t'|' -k2,2nr -k3,3n))

# Get top 3 regions
top_regions=()
for result in "${sorted_initial[@]:0:3}"; do
    IFS='|' read -r node score speed region ip country <<< "$result"
    if [[ ! " ${top_regions[@]} " =~ " ${region} " ]]; then
        top_regions+=("$region")
    fi
done

# Test more nodes from top regions
for region in "${top_regions[@]}"; do
    case $region in
        "US") additional_nodes=("${US_NODES[@]:2:3}") ;;
        "HK") additional_nodes=("${HK_NODES[@]:2:2}") ;;
        "SG") additional_nodes=("${SG_NODES[@]:2:2}") ;;
        "JP") additional_nodes=("${JP_NODES[@]:2:2}") ;;
        "TW") additional_nodes=() ;;
    esac
    
    for node in "${additional_nodes[@]}"; do
        if [[ -n "$node" ]]; then
            result=$(test_streaming_node "$node" "$region")
            test_results+=("$result")
        fi
    done
done

echo ""
echo -e "${GREEN}🏆 YOUTUBE STREAMING OPTIMIZATION RESULTS${NC}"
echo "================================================"

# Sort all results by score (desc) then by speed (asc)
IFS=$'\n' final_sorted=($(printf '%s\n' "${test_results[@]}" | sort -t'|' -k2,2nr -k3,3n))

echo ""
echo -e "${GREEN}🥇 TOP STREAMING NODES FOR YOUTUBE:${NC}"

best_nodes=()
excellent_nodes=()
good_nodes=()
rank=1

for result in "${final_sorted[@]}"; do
    IFS='|' read -r node score speed region ip country <<< "$result"
    
    if [[ $score -ge 6 ]]; then
        echo -e "${GREEN}$rank. $node${NC}"
        echo -e "   ${PURPLE}🏆 EXCELLENT${NC} - Score: $score/7, Speed: ${speed}s"
        echo -e "   📍 $country ($ip) - Region: $region"
        excellent_nodes+=("$node")
        best_nodes+=("$node")
    elif [[ $score -ge 4 ]]; then
        echo -e "${YELLOW}$rank. $node${NC}"
        echo -e "   ${YELLOW}🥈 GOOD${NC} - Score: $score/7, Speed: ${speed}s"
        echo -e "   📍 $country ($ip) - Region: $region"
        good_nodes+=("$node")
        [[ ${#best_nodes[@]} -lt 8 ]] && best_nodes+=("$node")
    else
        echo -e "$rank. $node"
        echo -e "   ${RED}🥉 POOR${NC} - Score: $score/7, Speed: ${speed}s"
        echo -e "   📍 $country ($ip) - Region: $region"
    fi
    echo ""
    ((rank++))
done

echo -e "${BLUE}📊 STREAMING GROUP OPTIMIZATION${NC}"
echo "==============================="

if [[ ${#excellent_nodes[@]} -gt 0 ]]; then
    top_node="${excellent_nodes[0]}"
    echo -e "🎯 Setting Streaming group to best YouTube node: ${GREEN}$top_node${NC}"
    
    curl -s -X PUT "$PROXY_API/proxies/Streaming" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$top_node\"}" >/dev/null
    
    sleep 3
    
    # Verify the change
    current=$(curl -s "$PROXY_API/proxies/Streaming" | jq -r '.now')
    echo -e "✅ Streaming group now using: ${GREEN}$current${NC}"
    
    echo ""
    echo -e "${BLUE}🔍 FINAL YOUTUBE VERIFICATION${NC}"
    echo "=========================="
    echo -n "📍 Current IP: "
    curl -s --proxy http://127.0.0.1:7890 --max-time 5 http://ip-api.com/json | jq -r '.query + " (" + .country + ")"'
    
    echo -n "🎥 YouTube Access: "
    if timeout 8 curl -s --proxy http://127.0.0.1:7890 "https://www.youtube.com" | grep -q -i "youtube" 2>/dev/null; then
        echo -e "${GREEN}✅ Working Perfectly${NC}"
    else
        echo -e "${RED}❌ Issues Detected${NC}"
    fi
    
    echo -n "📺 Video Loading: "
    if timeout 8 curl -s --proxy http://127.0.0.1:7890 "https://www.youtube.com/watch?v=dQw4w9WgXcQ" | grep -q -i "youtube\|video" 2>/dev/null; then
        echo -e "${GREEN}✅ Fast Loading${NC}"
    else
        echo -e "${RED}❌ Slow/Blocked${NC}"
    fi
    
else
    echo -e "${RED}❌ No excellent nodes found. Using best available...${NC}"
    if [[ ${#good_nodes[@]} -gt 0 ]]; then
        backup_node="${good_nodes[0]}"
        curl -s -X PUT "$PROXY_API/proxies/Streaming" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"$backup_node\"}" >/dev/null
        echo -e "🔄 Set to backup node: ${YELLOW}$backup_node${NC}"
    fi
fi

echo ""
echo -e "${GREEN}💡 OPTIMIZATION RECOMMENDATIONS:${NC}"
echo "================================"
echo "🏆 Best overall nodes: ${#excellent_nodes[@]} excellent, ${#good_nodes[@]} good"
echo "🎯 Current streaming node: $(curl -s "$PROXY_API/proxies/Streaming" | jq -r '.now')"
echo "🔄 Manual switching: curl -X PUT http://127.0.0.1:9090/proxies/Streaming -H 'Content-Type: application/json' -d '{\"name\":\"NODE_NAME\"}'"
echo "📺 Optimized for: YouTube (primary), Netflix, Twitch"
echo ""
echo -e "${GREEN}✅ YouTube streaming optimization complete!${NC}"
