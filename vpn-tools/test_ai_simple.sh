#!/bin/bash

echo "=== AI Service Connectivity Test ==="
echo "Testing major AI services through current proxy..."

# Test OpenAI
echo -n "OpenAI API: "
if timeout 10 curl -s --proxy http://127.0.0.1:7890 https://api.openai.com/v1/models > /dev/null 2>&1; then
    echo "✅ OK"
else
    echo "❌ FAILED"
fi

# Test ChatGPT
echo -n "ChatGPT: "
if timeout 10 curl -s --proxy http://127.0.0.1:7890 https://chat.openai.com > /dev/null 2>&1; then
    echo "✅ OK"
else
    echo "❌ FAILED"
fi

# Test Claude
echo -n "Claude: "
if timeout 10 curl -s --proxy http://127.0.0.1:7890 https://claude.ai > /dev/null 2>&1; then
    echo "✅ OK"
else
    echo "❌ FAILED"
fi

# Test Anthropic API
echo -n "Anthropic API: "
if timeout 10 curl -s --proxy http://127.0.0.1:7890 https://api.anthropic.com > /dev/null 2>&1; then
    echo "✅ OK"
else
    echo "❌ FAILED"
fi

echo ""
echo "Current proxy status:"
export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"
curl -s --max-time 5 http://ip-api.com/json | jq '{country: .country, city: .city, ip: .query}'
unset http_proxy https_proxy
