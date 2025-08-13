#!/bin/bash

echo "🎯 YouTube Node Selector"
echo "======================="

# Key streaming nodes to test (best candidates from each region)
CANDIDATES=(
    "V1-美国01|流媒体|GPT"
    "V1-美国05|流媒体|GPT"
    "V1-新加坡01|流媒体|GPT"
    "V1-新加坡02|流媒体|GPT"
    "V1-日本01|流媒体|GPT"
    "V1-日本02|流媒体|GPT"
    "V1-香港01"
    "V1-台湾省01|流媒体|GPT"
)

test_youtube_node() {
    local node="$1"
    echo ""
    echo "Testing: $node"
    
    # Switch to node
    curl -s -X PUT "http://127.0.0.1:9090/proxies/Streaming" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$node\"}" >/dev/null
    
    sleep 2
    
    local score=0
    local region=""
    
    # Get IP info
    local ip_info=$(curl -s --proxy http://127.0.0.1:7890 --max-time 5 http://ip-api.com/json 2>/dev/null)
    local ip=$(echo "$ip_info" | jq -r '.query // "unknown"')
    local country=$(echo "$ip_info" | jq -r '.country // "unknown"')
    
    echo "  📍 $ip ($country)"
    
    # Test YouTube main site
    echo -n "  🎥 YouTube: "
    local yt_start=$(date +%s.%N)
    if timeout 8 curl -s --proxy http://127.0.0.1:7890 "https://www.youtube.com" | grep -q -i "youtube" 2>/dev/null; then
        local yt_end=$(date +%s.%N)
        local yt_time=$(echo "$yt_end - $yt_start" | bc -l 2>/dev/null || echo "0")
        echo "✅ OK (${yt_time}s)"
        ((score += 3))
    else
        echo "❌ FAILED"
    fi
    
    # Test YouTube video page
    echo -n "  📺 Video: "
    if timeout 6 curl -s --proxy http://127.0.0.1:7890 "https://www.youtube.com/watch?v=dQw4w9WgXcQ" | grep -q -i "youtube\|video" 2>/dev/null; then
        echo "✅ OK"
        ((score += 2))
    else
        echo "❌ FAILED"
    fi
    
    # Test speed with a simple request
    echo -n "  ⚡ Speed: "
    local speed_start=$(date +%s.%N)
    if timeout 4 curl -s --proxy http://127.0.0.1:7890 "https://www.google.com" >/dev/null 2>&1; then
        local speed_end=$(date +%s.%N)
        local speed_time=$(echo "$speed_end - $speed_start" | bc -l 2>/dev/null || echo "999")
        echo "${speed_time}s"
        if (( $(echo "$speed_time < 2" | bc -l 2>/dev/null || echo 0) )); then
            ((score++))
        fi
    else
        echo "TIMEOUT"
        speed_time="999"
    fi
    
    echo "  📊 Score: $score/6"
    
    echo "$node:$score:$speed_time:$country:$ip"
}

echo "Testing key streaming candidates for YouTube..."
results=()

for node in "${CANDIDATES[@]}"; do
    result=$(test_youtube_node "$node")
    results+=("$result")
done

echo ""
echo "🏆 YOUTUBE STREAMING RESULTS"
echo "============================"

# Sort by score (desc) then by speed (asc)
IFS=$'\n' sorted=($(printf '%s\n' "${results[@]}" | sort -t: -k2,2nr -k3,3n))

echo ""
best_node=""
rank=1

for result in "${sorted[@]}"; do
    IFS=':' read -r node score speed country ip <<< "$result"
    
    if [[ $score -ge 5 ]]; then
        echo "🥇 $rank. $node - EXCELLENT"
        echo "   Score: $score/6, Speed: ${speed}s, Location: $country ($ip)"
        [[ -z "$best_node" ]] && best_node="$node"
    elif [[ $score -ge 3 ]]; then
        echo "🥈 $rank. $node - GOOD"
        echo "   Score: $score/6, Speed: ${speed}s, Location: $country ($ip)"
        [[ -z "$best_node" ]] && best_node="$node"
    else
        echo "🥉 $rank. $node - POOR"
        echo "   Score: $score/6, Speed: ${speed}s, Location: $country ($ip)"
    fi
    ((rank++))
done

# Set best node
if [[ -n "$best_node" ]]; then
    echo ""
    echo "🎯 Setting streaming group to: $best_node"
    
    curl -s -X PUT "http://127.0.0.1:9090/proxies/Streaming" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$best_node\"}" >/dev/null
    
    sleep 2
    
    current=$(curl -s "http://127.0.0.1:9090/proxies/Streaming" | jq -r '.now')
    echo "✅ Streaming group now using: $current"
    
    echo ""
    echo "🔍 Final YouTube verification:"
    echo -n "📍 IP: "
    curl -s --proxy http://127.0.0.1:7890 --max-time 5 http://ip-api.com/json | jq -r '.query + " (" + .country + ")"'
    
    echo -n "🎥 YouTube: "
    if timeout 5 curl -s --proxy http://127.0.0.1:7890 "https://www.youtube.com" | grep -q -i "youtube" 2>/dev/null; then
        echo "✅ Working"
    else
        echo "❌ Failed"
    fi
fi

echo ""
echo "✅ YouTube optimization complete!"
