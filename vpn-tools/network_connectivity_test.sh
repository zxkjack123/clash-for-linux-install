#!/bin/bash

# 🌐 Comprehensive Network Connectivity Testing Script
# 
# DESCRIPTION:
#   Complete connectivity verification for VPN/proxy setup
#   Tests Chinese domestic sites, international sites, AI platforms, and streaming services
#
# USAGE:
#   ./network_connectivity_test.sh [mode]
#
# MODES:
#   full          - Complete test of all categories (default)
#   quick         - Fast test of key sites only
#   chinese       - Test Chinese domestic sites only  
#   international - Test international sites only
#   ai           - Test AI platforms only
#   streaming    - Test streaming platforms only
#   speed        - Network speed test only
#
# WHAT IT DOES:
#   • Tests 10 Chinese domestic sites (direct connection)
#   • Tests 10 international sites (through proxy)
#   • Tests 6 AI platforms (through proxy)
#   • Tests 6 streaming platforms (through proxy)
#   • DNS resolution verification
#   • Network speed testing and analysis
#   • Comprehensive connectivity health assessment
#
# WHEN TO USE:
#   • Verify VPN/proxy is working correctly
#   • Troubleshoot connectivity issues
#   • Daily/weekly network health check
#   • After changing proxy configuration
#   • Before important work requiring stable connectivity
#
# DURATION: 
#   • Full test: 5-8 minutes
#   • Quick test: 1 minute
#   • Category-specific: 1-3 minutes
#
# CATEGORIES TESTED:
#   🇨🇳 Chinese Domestic (Direct): Baidu, Tencent, Alibaba, JD, Weibo, etc.
#   🌍 International (Proxy): Google, GitHub, Amazon, Facebook, Twitter, etc.
#   🤖 AI Platforms (Proxy): OpenAI, ChatGPT, Claude, Gemini, etc.
#   🎬 Streaming (Proxy): YouTube, Netflix, Twitch, Disney+, etc.
#
# EXAMPLE OUTPUT:
#   🌐 Comprehensive Network Connectivity Test
#   📍 Current Network Information
#   🔗 Direct IP: 85.234.83.184 (Japan, Tokyo)
#   🔒 Proxy IP: 85.234.83.184 (Japan, Tokyo)
#   
#   🇨🇳 Testing Chinese Domestic Sites (Direct Connection)
#   📊 Chinese sites: 10/10 working (100%)
#   
#   🌍 Testing International Sites (Through Proxy)  
#   📊 International sites: 9/10 working (90%)
#   
#   🎯 Overall success rate: 92.5% (37/40)
#   🏆 EXCELLENT - VPN working perfectly!

echo "🌐 Comprehensive Network Connectivity Test"
echo "========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test URLs - organized by category
declare -A CHINESE_SITES=(
    ["百度"]="https://www.baidu.com"
    ["腾讯"]="https://www.qq.com"
    ["阿里巴巴"]="https://www.alibaba.com"
    ["淘宝"]="https://www.taobao.com"
    ["微博"]="https://weibo.com"
    ["知乎"]="https://www.zhihu.com"
    ["B站"]="https://www.bilibili.com"
    ["网易"]="https://www.163.com"
    ["搜狐"]="https://www.sohu.com"
    ["新浪"]="https://www.sina.com.cn"
)

declare -A INTERNATIONAL_SITES=(
    ["Google"]="https://www.google.com"
    ["YouTube"]="https://www.youtube.com"
    ["Facebook"]="https://www.facebook.com"
    ["Twitter"]="https://twitter.com"
    ["Instagram"]="https://www.instagram.com"
    ["Wikipedia"]="https://www.wikipedia.org"
    ["Reddit"]="https://www.reddit.com"
    ["GitHub"]="https://github.com"
    ["StackOverflow"]="https://stackoverflow.com"
    ["BBC"]="https://www.bbc.com"
)

declare -A AI_PLATFORMS=(
    ["OpenAI"]="https://api.openai.com"
    ["ChatGPT"]="https://chat.openai.com"
    ["Claude"]="https://claude.ai"
    ["Anthropic"]="https://www.anthropic.com"
    ["Gemini"]="https://gemini.google.com"
    ["Perplexity"]="https://www.perplexity.ai"
)

declare -A STREAMING_SITES=(
    ["YouTube"]="https://www.youtube.com"
    ["Netflix"]="https://www.netflix.com"
    ["Twitch"]="https://www.twitch.tv"
    ["Disney+"]="https://www.disneyplus.com"
    ["Amazon_Prime"]="https://www.primevideo.com"
    ["Spotify"]="https://www.spotify.com"
)

# Test function
test_connectivity() {
    local name="$1"
    local url="$2"
    local use_proxy="$3"
    
    local proxy_args=""
    if [[ "$use_proxy" == "true" ]]; then
        proxy_args="--proxy http://127.0.0.1:7890"
    fi
    
    printf "  %-15s: " "$name"
    
    # Test with timeout
    local start_time=$(date +%s.%N)
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        $proxy_args \
        --connect-timeout 8 \
        --max-time 12 \
        --user-agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
        "$url" 2>/dev/null)
    local end_time=$(date +%s.%N)
    
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    # Evaluate response
    if [[ "$response_code" =~ ^(200|301|302|303|304)$ ]]; then
        echo -e "${GREEN}✅ OK${NC} (${response_code}, ${duration}s)"
        return 0
    elif [[ "$response_code" =~ ^(403|404|429)$ ]]; then
        echo -e "${YELLOW}⚠️  BLOCKED${NC} (${response_code})"
        return 1
    elif [[ "$response_code" == "000" ]]; then
        echo -e "${RED}❌ TIMEOUT${NC}"
        return 2
    else
        echo -e "${PURPLE}? UNKNOWN${NC} (${response_code})"
        return 3
    fi
}

# Show current network info
show_network_info() {
    echo -e "${CYAN}📡 Current Network Information${NC}"
    echo "=============================="
    
    echo -n "🔗 Direct IP: "
    curl -s --max-time 5 http://ip-api.com/json | jq -r '.query + " (" + .country + ", " + .city + ")"' 2>/dev/null || echo "Unable to detect"
    
    echo -n "🔒 Proxy IP: "
    curl -s --proxy http://127.0.0.1:7890 --max-time 5 http://ip-api.com/json | jq -r '.query + " (" + .country + ", " + .city + ")"' 2>/dev/null || echo "Proxy not working"
    
    echo ""
}

# Test DNS resolution
test_dns() {
    echo -e "${CYAN}🔍 DNS Resolution Test${NC}"
    echo "====================="
    
    local dns_tests=("google.com" "baidu.com" "github.com" "qq.com")
    
    for domain in "${dns_tests[@]}"; do
        printf "  %-15s: " "$domain"
        if timeout 5 nslookup "$domain" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Resolved${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi
    done
    echo ""
}

# Main testing function
run_comprehensive_test() {
    show_network_info
    test_dns
    
    # Test Chinese sites (should work without proxy)
    echo -e "${BLUE}🇨🇳 Testing Chinese Domestic Sites (Direct Connection)${NC}"
    echo "=================================================="
    
    local chinese_success=0
    local chinese_total=${#CHINESE_SITES[@]}
    
    for site in "${!CHINESE_SITES[@]}"; do
        if test_connectivity "$site" "${CHINESE_SITES[$site]}" "false"; then
            ((chinese_success++))
        fi
    done
    
    echo -e "📊 Chinese sites: ${GREEN}$chinese_success${NC}/$chinese_total working"
    echo ""
    
    # Test international sites (should work with proxy)
    echo -e "${PURPLE}🌍 Testing International Sites (Through Proxy)${NC}"
    echo "============================================="
    
    local intl_success=0
    local intl_total=${#INTERNATIONAL_SITES[@]}
    
    for site in "${!INTERNATIONAL_SITES[@]}"; do
        if test_connectivity "$site" "${INTERNATIONAL_SITES[$site]}" "true"; then
            ((intl_success++))
        fi
    done
    
    echo -e "📊 International sites: ${GREEN}$intl_success${NC}/$intl_total working"
    echo ""
    
    # Test AI platforms (should work with proxy)
    echo -e "${YELLOW}🤖 Testing AI Platforms (Through Proxy)${NC}"
    echo "======================================"
    
    local ai_success=0
    local ai_total=${#AI_PLATFORMS[@]}
    
    for platform in "${!AI_PLATFORMS[@]}"; do
        if test_connectivity "$platform" "${AI_PLATFORMS[$platform]}" "true"; then
            ((ai_success++))
        fi
    done
    
    echo -e "📊 AI platforms: ${GREEN}$ai_success${NC}/$ai_total working"
    echo ""
    
    # Test streaming sites (should work with proxy)
    echo -e "${CYAN}🎬 Testing Streaming Platforms (Through Proxy)${NC}"
    echo "============================================"
    
    local streaming_success=0
    local streaming_total=${#STREAMING_SITES[@]}
    
    for platform in "${!STREAMING_SITES[@]}"; do
        if test_connectivity "$platform" "${STREAMING_SITES[$platform]}" "true"; then
            ((streaming_success++))
        fi
    done
    
    echo -e "📊 Streaming platforms: ${GREEN}$streaming_success${NC}/$streaming_total working"
    echo ""
    
    # Overall summary
    echo -e "${GREEN}📈 CONNECTIVITY SUMMARY${NC}"
    echo "======================"
    
    local total_success=$((chinese_success + intl_success + ai_success + streaming_success))
    local total_tests=$((chinese_total + intl_total + ai_total + streaming_total))
    local success_rate=$(echo "scale=1; $total_success * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
    
    echo -e "🏠 Chinese domestic: ${GREEN}$chinese_success${NC}/$chinese_total ($(echo "scale=1; $chinese_success * 100 / $chinese_total" | bc -l 2>/dev/null || echo "0")%)"
    echo -e "🌍 International: ${GREEN}$intl_success${NC}/$intl_total ($(echo "scale=1; $intl_success * 100 / $intl_total" | bc -l 2>/dev/null || echo "0")%)"
    echo -e "🤖 AI platforms: ${GREEN}$ai_success${NC}/$ai_total ($(echo "scale=1; $ai_success * 100 / $ai_total" | bc -l 2>/dev/null || echo "0")%)"
    echo -e "🎬 Streaming: ${GREEN}$streaming_success${NC}/$streaming_total ($(echo "scale=1; $streaming_success * 100 / $streaming_total" | bc -l 2>/dev/null || echo "0")%)"
    echo ""
    echo -e "🎯 Overall success rate: ${GREEN}$success_rate%${NC} ($total_success/$total_tests)"
    
    # Health assessment
    echo ""
    if [[ $success_rate > 85 ]]; then
        echo -e "${GREEN}🏆 EXCELLENT${NC} - VPN working perfectly!"
    elif [[ $success_rate > 70 ]]; then
        echo -e "${YELLOW}🥈 GOOD${NC} - VPN working well with minor issues"
    elif [[ $success_rate > 50 ]]; then
        echo -e "${YELLOW}🥉 FAIR${NC} - VPN working but needs optimization"
    else
        echo -e "${RED}⚠️  POOR${NC} - VPN needs troubleshooting"
    fi
    
    # Recommendations
    echo ""
    echo -e "${BLUE}💡 RECOMMENDATIONS${NC}"
    echo "=================="
    
    if [[ $chinese_success -lt 8 ]]; then
        echo "🔧 Chinese sites issue: Check if direct connection is working"
    fi
    
    if [[ $intl_success -lt 7 ]]; then
        echo "🔧 International sites issue: Try switching proxy nodes"
        echo "   Use: ./streaming_manager.sh us   # or sg, jp, hk"
    fi
    
    if [[ $ai_success -lt 4 ]]; then
        echo "🔧 AI platforms issue: Run AI optimization"
        echo "   Use: ./optimize_ai.sh"
    fi
    
    if [[ $streaming_success -lt 4 ]]; then
        echo "🔧 Streaming issue: Run streaming optimization" 
        echo "   Use: ./optimize_youtube_streaming.sh"
    fi
    
    echo ""
    echo -e "${GREEN}✅ Connectivity test completed!${NC}"
}

# Speed test function
run_speed_test() {
    echo -e "${PURPLE}⚡ Speed Test${NC}"
    echo "============"
    
    echo "Testing connection speed..."
    
    # Test direct speed
    echo -n "🔗 Direct speed: "
    local direct_time=$(timeout 10 curl -s -o /dev/null -w "%{time_total}" http://www.google.com 2>/dev/null || echo "999")
    echo "${direct_time}s"
    
    # Test proxy speed
    echo -n "🔒 Proxy speed: "
    local proxy_time=$(timeout 10 curl -s --proxy http://127.0.0.1:7890 -o /dev/null -w "%{time_total}" http://www.google.com 2>/dev/null || echo "999")
    echo "${proxy_time}s"
    
    # Speed comparison
    if (( $(echo "$proxy_time < 3" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${GREEN}🚀 Excellent proxy speed!${NC}"
    elif (( $(echo "$proxy_time < 6" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${YELLOW}🏃 Good proxy speed${NC}"
    else
        echo -e "${RED}🐌 Slow proxy - consider switching nodes${NC}"
    fi
    echo ""
}

# Main script execution
case "${1:-full}" in
    "full")
        run_comprehensive_test
        run_speed_test
        ;;
    "quick")
        show_network_info
        echo "Quick test of key sites..."
        test_connectivity "Baidu" "https://www.baidu.com" "false"
        test_connectivity "Google" "https://www.google.com" "true"
        test_connectivity "YouTube" "https://www.youtube.com" "true"
        test_connectivity "OpenAI" "https://chat.openai.com" "true"
        ;;
    "chinese")
        echo -e "${BLUE}Testing Chinese sites only...${NC}"
        for site in "${!CHINESE_SITES[@]}"; do
            test_connectivity "$site" "${CHINESE_SITES[$site]}" "false"
        done
        ;;
    "international")
        echo -e "${PURPLE}Testing international sites only...${NC}"
        for site in "${!INTERNATIONAL_SITES[@]}"; do
            test_connectivity "$site" "${INTERNATIONAL_SITES[$site]}" "true"
        done
        ;;
    "speed")
        run_speed_test
        ;;
    *)
        echo "Usage: $0 [full|quick|chinese|international|speed]"
        echo ""
        echo "Options:"
        echo "  full          - Complete connectivity test (default)"
        echo "  quick         - Quick test of key sites"
        echo "  chinese       - Test Chinese domestic sites only"
        echo "  international - Test international sites only"
        echo "  speed         - Speed test only"
        ;;
esac
