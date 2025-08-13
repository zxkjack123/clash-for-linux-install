#!/bin/bash

# 📊 Comprehensive Proxy Connectivity Report
# 
# DESCRIPTION:
#   Complete analysis of proxy connectivity, service status, and performance
#   Provides detailed diagnostics and recommendations
#
# USAGE:
#   ./proxy_connectivity_report.sh

echo "📊 Comprehensive Proxy Connectivity Report"
echo "=========================================="
echo "⏰ Generated: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 1. Service Status Check
echo "🔧 1. SERVICE STATUS"
echo "==================="

# Check mihomo service
if systemctl --user is-active mihomo.service >/dev/null 2>&1; then
    echo -e "✅ Mihomo Service: ${GREEN}Active${NC}"
    service_ok=true
else
    echo -e "❌ Mihomo Service: ${RED}Inactive${NC}"
    service_ok=false
fi

# Check API accessibility
if curl -s -o /dev/null -w "" http://127.0.0.1:9090/proxies 2>/dev/null; then
    echo -e "✅ Clash API: ${GREEN}Accessible${NC}"
    api_ok=true
else
    echo -e "❌ Clash API: ${RED}Not responding${NC}"
    api_ok=false
fi

# Check proxy port
if netstat -tln 2>/dev/null | grep -q ":7890"; then
    echo -e "✅ Proxy Port (7890): ${GREEN}Open${NC}"
else
    echo -e "❌ Proxy Port (7890): ${RED}Not listening${NC}"
fi

echo ""

# 2. Current Configuration
echo "📋 2. CURRENT CONFIGURATION"
echo "==========================="

if [ "$api_ok" = true ]; then
    ai_node=$(curl -s http://127.0.0.1:9090/proxies/AI | jq -r '.now' 2>/dev/null || echo "Unknown")
    streaming_node=$(curl -s http://127.0.0.1:9090/proxies/Streaming | jq -r '.now' 2>/dev/null || echo "Unknown")
    
    echo "🤖 AI Group: $ai_node"
    echo "🎬 Streaming Group: $streaming_node"
    
    # Get IP information
    echo ""
    echo "📡 Network Information:"
    echo "======================="
    
    # Direct connection IP
    direct_ip=$(timeout 5 curl -s https://httpbin.org/ip 2>/dev/null | jq -r '.origin' 2>/dev/null || echo "Unknown")
    echo "🏠 Direct IP: $direct_ip"
    
    # Proxy IP
    proxy_ip=$(timeout 5 curl -s --proxy http://127.0.0.1:7890 https://httpbin.org/ip 2>/dev/null | jq -r '.origin' 2>/dev/null || echo "Unknown")
    echo "🔒 Proxy IP: $proxy_ip"
    
else
    echo "❌ Cannot retrieve configuration - API not accessible"
fi

echo ""

# 3. Connectivity Tests
echo "🧪 3. CONNECTIVITY TESTS"
echo "========================"

# Test categories
declare -A test_sites=(
    ["International Proxy"]="https://www.google.com/"
    ["Streaming Proxy"]="https://www.youtube.com/"
    ["AI Services Proxy"]="https://openai.com/"
    ["Claude AI Proxy"]="https://claude.ai/"
    ["Chinese Direct"]="https://www.baidu.com/"
    ["OpenXLab Direct"]="https://openxlab.org.cn/"
    ["MinerU Direct"]="https://mineru.net/"
)

total_tests=0
passed_tests=0

for category in "${!test_sites[@]}"; do
    url="${test_sites[$category]}"
    echo -n "📍 $category: "
    
    # Determine if this should use proxy or direct
    if [[ "$category" == *"Direct"* ]]; then
        # Test direct connection
        response=$(timeout 8 curl -s -o /dev/null -w "%{http_code},%{time_total}" \
            --noproxy "*" "$url" 2>/dev/null)
    else
        # Test through proxy
        response=$(timeout 8 curl -s -o /dev/null -w "%{http_code},%{time_total}" \
            --proxy http://127.0.0.1:7890 "$url" 2>/dev/null)
    fi
    
    if [ $? -eq 0 ]; then
        http_code=$(echo $response | cut -d',' -f1)
        time_total=$(echo $response | cut -d',' -f2)
        
        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
            echo -e "${GREEN}✅ OK${NC} (${http_code}, ${time_total}s)"
            passed_tests=$((passed_tests + 1))
        else
            echo -e "${YELLOW}⚠️ HTTP ${http_code}${NC} (${time_total}s)"
        fi
    else
        echo -e "${RED}❌ Failed${NC}"
    fi
    
    total_tests=$((total_tests + 1))
done

echo ""

# 4. Performance Analysis
echo "📈 4. PERFORMANCE ANALYSIS"
echo "=========================="

success_rate=$(echo "scale=1; $passed_tests * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
echo "📊 Overall Success Rate: $passed_tests/$total_tests (${success_rate}%)"

if [ "$passed_tests" -eq "$total_tests" ]; then
    echo -e "🏆 Status: ${GREEN}EXCELLENT${NC} - All services working"
elif [ "$passed_tests" -ge $((total_tests * 3 / 4)) ]; then
    echo -e "✅ Status: ${GREEN}GOOD${NC} - Most services working"
elif [ "$passed_tests" -ge $((total_tests / 2)) ]; then
    echo -e "⚠️ Status: ${YELLOW}FAIR${NC} - Some services need attention"
else
    echo -e "🚨 Status: ${RED}POOR${NC} - Multiple services failing"
fi

echo ""

# 5. Specific Tests for Key Services
echo "🎯 5. KEY SERVICES VERIFICATION"
echo "==============================="

# Test OpenXLab specifically (should be direct)
echo "🇨🇳 OpenXLab Direct Connection Test:"
openxlab_domains=("openxlab.org.cn" "sso.openxlab.org.cn" "mineru.net")

for domain in "${openxlab_domains[@]}"; do
    echo -n "  📍 $domain: "
    if timeout 5 curl -s -o /dev/null --noproxy "*" "https://$domain/" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${RED}❌ Failed${NC}"
    fi
done

echo ""

# Test AI Services (should be through proxy)
echo "🤖 AI Services Proxy Test:"
ai_services=("openai.com" "claude.ai" "chat.openai.com")

for service in "${ai_services[@]}"; do
    echo -n "  📍 $service: "
    if timeout 8 curl -s -o /dev/null --proxy http://127.0.0.1:7890 "https://$service/" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
    else
        echo -e "${RED}❌ Failed${NC}"
    fi
done

echo ""

# 6. Recommendations
echo "💡 6. RECOMMENDATIONS"
echo "===================="

if [ "$service_ok" = false ]; then
    echo -e "${RED}🔧 CRITICAL: Restart mihomo service${NC}"
    echo "   sudo systemctl --user restart mihomo.service"
    echo ""
fi

if [ "$api_ok" = false ]; then
    echo -e "${RED}🔧 CRITICAL: Check Clash configuration${NC}"
    echo "   Check /home/gw/opt/clash-for-linux-install/resources/config.yaml"
    echo ""
fi

if [ "$passed_tests" -lt $((total_tests * 3 / 4)) ]; then
    echo -e "${YELLOW}🔧 OPTIMIZATION NEEDED:${NC}"
    echo "• Run: ./optimize_ai.sh for AI services"
    echo "• Run: ./streaming_manager.sh for streaming"
    echo "• Check node performance with different servers"
    echo ""
fi

echo "✅ Working tools for optimization:"
echo "• ./quick_vpn_check.sh - Quick status check"
echo "• ./network_connectivity_test.sh - Full network test"
echo "• ./optimize_ai.sh - AI services optimization"
echo "• ./streaming_manager.sh - Streaming optimization"
echo "• ./test_openxlab_direct_rules.sh - OpenXLab verification"

echo ""

# 7. Quick Actions
echo "⚡ 7. QUICK ACTIONS"
echo "=================="

echo "🔄 Restart services:"
echo "   ./restart_mihomo_service.sh"
echo ""
echo "🧪 Run tests:"
echo "   ./quick_vpn_check.sh"
echo "   ./network_connectivity_test.sh quick"
echo ""
echo "🔧 Optimization:"
echo "   ./optimize_ai.sh"
echo "   ./streaming_manager.sh"
echo ""
echo "📊 Monitoring:"
echo "   http://127.0.0.1:9090/ui (Clash Dashboard)"

echo ""
echo "📋 Report completed at $(date)"
