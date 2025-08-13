#!/bin/bash

echo "🎥 Quick YouTube Streaming Test"
echo "=============================="

# Test current streaming node
echo "Current Streaming Node:"
curl -s "http://127.0.0.1:9090/proxies/Streaming" | jq -r '.now'

echo ""
echo "Testing YouTube connectivity..."

# Get current IP
echo -n "📍 Current IP: "
curl -s --proxy http://127.0.0.1:7890 --max-time 5 http://ip-api.com/json | jq -r '.query + " (" + .country + ")"'

echo ""
echo "🎯 Streaming Service Tests:"

# Test YouTube main site
echo -n "🎥 YouTube Main: "
if timeout 8 curl -s --proxy http://127.0.0.1:7890 "https://www.youtube.com" | grep -q -i "youtube" 2>/dev/null; then
    echo "✅ Working"
else
    echo "❌ Failed"
fi

# Test YouTube video
echo -n "📺 YouTube Video: "
if timeout 8 curl -s --proxy http://127.0.0.1:7890 "https://www.youtube.com/watch?v=dQw4w9WgXcQ" | grep -q -i "youtube\|video" 2>/dev/null; then
    echo "✅ Working"
else
    echo "❌ Failed"
fi

# Test Netflix
echo -n "🎬 Netflix: "
netflix_code=$(curl -s -o /dev/null -w "%{http_code}" --proxy http://127.0.0.1:7890 --max-time 8 "https://www.netflix.com" 2>/dev/null)
if [[ "$netflix_code" =~ ^(200|301|302)$ ]]; then
    echo "✅ Working ($netflix_code)"
else
    echo "❌ Blocked ($netflix_code)"
fi

# Test Twitch
echo -n "🎮 Twitch: "
twitch_code=$(curl -s -o /dev/null -w "%{http_code}" --proxy http://127.0.0.1:7890 --max-time 8 "https://www.twitch.tv" 2>/dev/null)
if [[ "$twitch_code" =~ ^(200|301|302)$ ]]; then
    echo "✅ Working ($twitch_code)"
else
    echo "❌ Blocked ($twitch_code)"
fi

echo ""
echo "🔄 Quick node switching commands:"
echo "US node: curl -X PUT http://127.0.0.1:9090/proxies/Streaming -H 'Content-Type: application/json' -d '{\"name\":\"V1-美国01|流媒体|GPT\"}'"
echo "SG node: curl -X PUT http://127.0.0.1:9090/proxies/Streaming -H 'Content-Type: application/json' -d '{\"name\":\"V1-新加坡01|流媒体|GPT\"}'"
echo "JP node: curl -X PUT http://127.0.0.1:9090/proxies/Streaming -H 'Content-Type: application/json' -d '{\"name\":\"V1-日本01|流媒体|GPT\"}'"
echo "HK node: curl -X PUT http://127.0.0.1:9090/proxies/Streaming -H 'Content-Type: application/json' -d '{\"name\":\"V1-香港01\"}'"

echo ""
echo "✅ Quick test complete!"
