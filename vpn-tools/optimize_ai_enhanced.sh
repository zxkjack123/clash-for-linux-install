#!/bin/bash

# 🧠 Enhanced AI Optimization with Braintrust.dev Support
# 
# DESCRIPTION:
#   Enhanced AI optimization that includes Braintrust.dev and related AI development platforms
#   Tests and optimizes for comprehensive AI development workflow
#
# USAGE:
#   ./optimize_ai_enhanced.sh
#
# WHAT IT DOES:
#   • Tests key AI nodes for Braintrust.dev, OpenAI, Claude, and development platforms
#   • Measures performance for AI development workflows
#   • Automatically selects best performing node for AI development
#   • Includes Braintrust.dev-specific optimization
#
# WHEN TO USE:
#   • Before AI development work involving Braintrust.dev
#   • When AI development tools are slow or not responding
#   • For comprehensive AI development optimization

echo "🧠 Enhanced AI Service Optimization (with Braintrust.dev)"
echo "========================================================"

# Test key nodes optimized for AI development platforms
NODES_TO_TEST=(
    "V1-美国01|流媒体|GPT"
    "V1-美国05|流媒体|GPT"
    "V1-美国10|流媒体|GPT"
    "V1-新加坡01|流媒体|GPT"
    "V1-新加坡02|流媒体|GPT"
    "V1-日本01|流媒体|GPT"
)

# AI Development platforms to test
declare -A TEST_PLATFORMS=(
    ["Braintrust"]="https://www.braintrust.dev/"
    ["OpenAI API"]="https://api.openai.com/"
    ["ChatGPT"]="https://chat.openai.com/"
    ["Claude"]="https://claude.ai/"
    ["Hugging Face"]="https://huggingface.co/"
    ["Replicate"]="https://replicate.com/"
)

best_node=""
best_score=0

echo "🔍 Testing AI development platforms on different nodes..."
echo ""

for node in "${NODES_TO_TEST[@]}"; do
    echo "🧪 Testing node: $node"
    
    # Switch to test node
    curl -X PUT http://127.0.0.1:9090/proxies/AI \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$node\"}" >/dev/null 2>&1
    
    sleep 2  # Allow time for switch
    
    score=0
    successful_tests=0
    total_time=0
    
    for platform in "${!TEST_PLATFORMS[@]}"; do
        url="${TEST_PLATFORMS[$platform]}"
        echo -n "  📍 $platform: "
        
        # Test with timeout
        response=$(curl -s -o /dev/null -w "%{http_code},%{time_total}" --connect-timeout 8 --max-time 12 "$url" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            http_code=$(echo $response | cut -d',' -f1)
            time_total=$(echo $response | cut -d',' -f2)
            
            if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
                echo "✅ OK (${time_total}s)"
                successful_tests=$((successful_tests + 1))
                
                # Calculate score based on response time
                if (( $(echo "$time_total <= 2" | bc -l 2>/dev/null || echo 0) )); then
                    score=$((score + 20))  # Excellent
                elif (( $(echo "$time_total <= 4" | bc -l 2>/dev/null || echo 0) )); then
                    score=$((score + 15))  # Good
                elif (( $(echo "$time_total <= 6" | bc -l 2>/dev/null || echo 0) )); then
                    score=$((score + 10))  # Average
                else
                    score=$((score + 5))   # Slow but working
                fi
                
                total_time=$(echo "$total_time + $time_total" | bc -l 2>/dev/null || echo $total_time)
            else
                echo "⚠️ HTTP $http_code"
                score=$((score + 1))  # Minimal points for connection
            fi
        else
            echo "❌ Failed"
        fi
    done
    
    # Bonus points for Braintrust.dev specifically (since it's the focus)
    echo -n "  🎯 Braintrust API test: "
    response=$(curl -s -o /dev/null -w "%{http_code},%{time_total}" --connect-timeout 8 --max-time 12 "https://api.braintrust.dev/" 2>/dev/null)
    if [ $? -eq 0 ]; then
        http_code=$(echo $response | cut -d',' -f1)
        time_total=$(echo $response | cut -d',' -f2)
        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
            echo "✅ OK (${time_total}s)"
            score=$((score + 10))  # Bonus for Braintrust API
        else
            echo "⚠️ HTTP $http_code"
        fi
    else
        echo "❌ Failed"
    fi
    
    avg_time=$(echo "scale=3; $total_time / $successful_tests" | bc -l 2>/dev/null || echo "0")
    success_rate=$(echo "scale=1; $successful_tests * 100 / ${#TEST_PLATFORMS[@]}" | bc -l 2>/dev/null || echo "0")
    
    echo "  📊 Score: $score/140, Success: ${success_rate}%, Avg Time: ${avg_time}s"
    echo ""
    
    # Track best performing node
    if [ $score -gt $best_score ]; then
        best_score=$score
        best_node=$node
    fi
done

echo "🏆 OPTIMIZATION RESULTS:"
echo "======================="
echo "🥇 Best Node: $best_node"
echo "🎯 Best Score: $best_score/140"
echo ""

if [ -n "$best_node" ]; then
    echo "🎯 Setting AI group to best performing node: $best_node"
    curl -X PUT http://127.0.0.1:9090/proxies/AI \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$best_node\"}" >/dev/null 2>&1
    
    sleep 2
    
    echo ""
    echo "✅ Optimization complete! Verifying new setup..."
    echo ""
    
    # Verify the change and test key platforms
    current_node=$(curl -s http://127.0.0.1:9090/proxies/AI | jq -r '.now')
    echo "🤖 Current AI Group: $current_node"
    echo ""
    
    echo "🧪 Quick verification test:"
    echo "  Braintrust.dev: $(curl -s -o /dev/null -w "Status %{http_code}, %{time_total}s" --connect-timeout 8 "https://www.braintrust.dev/")"
    echo "  OpenAI API: $(curl -s -o /dev/null -w "Status %{http_code}, %{time_total}s" --connect-timeout 8 "https://api.openai.com/")"
    echo "  Claude: $(curl -s -o /dev/null -w "Status %{http_code}, %{time_total}s" --connect-timeout 8 "https://claude.ai/")"
    
    echo ""
    echo "🎉 AI development environment optimized for Braintrust.dev!"
    echo ""
    echo "💡 Tips for optimal AI development:"
    echo "  • Braintrust.dev should now load faster"
    echo "  • AI API calls should have better performance"
    echo "  • Run './test_braintrust_connectivity.sh' for detailed analysis"
    echo "  • Use './quick_vpn_check.sh' for daily status checks"
    
else
    echo "❌ No suitable node found. Please check your proxy configuration."
fi
