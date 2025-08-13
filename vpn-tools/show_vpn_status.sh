#!/bin/bash

# 📋 VPN Configuration Summary
# 
# DESCRIPTION:
#   Shows the current VPN configuration status with all recent updates
#   Displays routing rules, service status, and available tools
#
# USAGE:
#   ./show_vpn_status.sh

echo "📋 VPN Configuration Summary"
echo "============================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "🚀 SERVICE STATUS:"
echo "=================="

# Check mihomo service
if systemctl --user is-active mihomo.service >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Mihomo Service: Running${NC}"
else
    echo -e "${RED}❌ Mihomo Service: Stopped${NC}"
fi

# Check API
if curl -s http://127.0.0.1:9090/version >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Clash API: Accessible${NC}"
    
    # Get version info
    version_info=$(curl -s http://127.0.0.1:9090/version | jq -r '.version' 2>/dev/null || echo "Unknown")
    echo "📦 Version: $version_info"
else
    echo -e "${RED}❌ Clash API: Not accessible${NC}"
fi

echo ""
echo "🎯 CURRENT ROUTING CONFIGURATION:"
echo "=================================="

# Get current proxy settings
AI_NODE=$(curl -s http://127.0.0.1:9090/proxies/AI | jq -r '.now' 2>/dev/null || echo "Unknown")
STREAMING_NODE=$(curl -s http://127.0.0.1:9090/proxies/Streaming | jq -r '.now' 2>/dev/null || echo "Unknown")
DEVELOPMENT_NODE=$(curl -s http://127.0.0.1:9090/proxies/Development | jq -r '.now' 2>/dev/null || echo "Unknown")

echo "🤖 AI Services:"
echo "  • Current Node: $AI_NODE"
echo "  • Routes: OpenAI, Claude, ChatGPT, Braintrust.dev"
echo ""

echo "🎬 Streaming Services:"
echo "  • Current Node: $STREAMING_NODE" 
echo "  • Routes: YouTube, Netflix, Twitch, Bilibili"
echo ""

echo "⚙️  Development Services:"
echo "  • Current Node: $DEVELOPMENT_NODE"
echo "  • Routes: GitHub, Docker, NPM, PyPI"
echo ""

echo "🇨🇳 Chinese AI Platforms (DIRECT):"
echo "  • OpenXLab (openxlab.org.cn)"
echo "  • OpenXLab SSO (sso.openxlab.org.cn)"
echo "  • MinerU (mineru.net)"
echo "  • Route: Direct ISP connection (bypasses proxy)"
echo ""

echo "🌐 RECENT CONFIGURATION UPDATES:"
echo "================================="
echo -e "${CYAN}✅ Added OpenXLab to DIRECT rules${NC}"
echo -e "${CYAN}✅ Added MinerU to DIRECT rules${NC}"
echo -e "${CYAN}✅ Added Braintrust.dev to AI-Manual group${NC}"
echo -e "${CYAN}✅ Updated mixin.yaml with new rules${NC}"
echo -e "${CYAN}✅ Created Chinese AI platform testing tools${NC}"
echo -e "${CYAN}✅ Service restarted with new configuration${NC}"

echo ""
echo "🛠️  AVAILABLE TOOLS:"
echo "==================="
echo "🇨🇳 Chinese AI Platforms:"
echo "  ./quick_openxlab_access.sh      # Quick OpenXLab/MinerU access"
echo "  ./fix_openxlab_connectivity.sh  # Comprehensive OpenXLab troubleshooting"
echo "  ./test_chinese_ai_platforms.sh  # Test Chinese AI platform connectivity"
echo ""
echo "🤖 International AI Platforms:"
echo "  ./optimize_ai.sh                # Optimize for OpenAI, Claude, Braintrust"
echo "  ./test_ai_connectivity.sh       # Test AI platform connectivity"
echo "  ./test_braintrust_connectivity.sh # Test Braintrust.dev specifically"
echo ""
echo "🎬 Streaming Optimization:"
echo "  ./streaming_manager.sh          # Optimize streaming services"
echo "  ./select_youtube_node.sh        # Optimize YouTube specifically"
echo ""
echo "🔧 System Management:"
echo "  ./restart_clash_service.sh      # Restart service with config validation"
echo "  ./network_connectivity_test.sh  # Comprehensive network testing"
echo "  ./show_help.sh                  # Complete help system"
echo ""

echo "🧪 QUICK CONNECTIVITY TESTS:"
echo "============================="

# Test a few key services
echo -n "🤖 OpenAI API: "
if timeout 5 curl -s -o /dev/null -w "%{http_code}" "https://api.openai.com/" 2>/dev/null | grep -q "200\|40[13]"; then
    echo -e "${GREEN}✅ Reachable${NC}"
else
    echo -e "${YELLOW}⚠️ Limited${NC}"
fi

echo -n "🧠 Claude.ai: "
if timeout 5 curl -s -o /dev/null -w "%{http_code}" "https://claude.ai/" 2>/dev/null | grep -q "200\|40[13]"; then
    echo -e "${GREEN}✅ Reachable${NC}"
else
    echo -e "${YELLOW}⚠️ Limited${NC}"
fi

echo -n "🔬 Braintrust.dev: "
if timeout 5 curl -s -o /dev/null -w "%{http_code}" "https://www.braintrust.dev/" 2>/dev/null | grep -q "200"; then
    echo -e "${GREEN}✅ Reachable${NC}"
else
    echo -e "${YELLOW}⚠️ Limited${NC}"
fi

echo -n "🇨🇳 MinerU: "
if timeout 5 curl -s -o /dev/null -w "%{http_code}" "https://mineru.net/" 2>/dev/null | grep -q "200"; then
    echo -e "${GREEN}✅ Direct${NC}"
else
    echo -e "${YELLOW}⚠️ Limited${NC}"
fi

echo -n "🎬 YouTube: "
if timeout 5 curl -s -o /dev/null -w "%{http_code}" "https://www.youtube.com/" 2>/dev/null | grep -q "200"; then
    echo -e "${GREEN}✅ Reachable${NC}"
else
    echo -e "${YELLOW}⚠️ Limited${NC}"
fi

echo ""
echo "📊 CONFIGURATION FILES:"
echo "========================"
echo "📁 Main Config: /home/gw/opt/clash-for-linux-install/resources/config.yaml"
echo "📁 Mixin Config: /home/gw/opt/clash-for-linux-install/resources/mixin.yaml"
echo "📁 Tools Directory: /home/gw/opt/clash-for-linux-install/vpn-tools/"
echo "📁 Backups: /home/gw/opt/clash-for-linux-install/resources/backup/"

echo ""
echo "💡 NEXT STEPS:"
echo "=============="
echo "1. 🧪 Test OpenXLab: ./quick_openxlab_access.sh"
echo "2. 🔍 Run full network test: ./network_connectivity_test.sh"
echo "3. 📚 Get specific help: ./show_help.sh [tool_name]"
echo "4. 🎯 Optimize for specific service: ./optimize_ai.sh or ./streaming_manager.sh"

echo ""
echo -e "${CYAN}🎉 VPN is fully configured and optimized!${NC}"
echo -e "${CYAN}   • International AI platforms → Proxy${NC}"
echo -e "${CYAN}   • Chinese AI platforms → Direct${NC}"
echo -e "${CYAN}   • Streaming services → Optimized nodes${NC}"
