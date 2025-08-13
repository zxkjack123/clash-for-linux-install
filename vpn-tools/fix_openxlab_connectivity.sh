#!/bin/bash

# 🔧 OpenXLab/MinerU Connectivity Fix
# 
# DESCRIPTION:
#   Comprehensive solution for OpenXLab and MinerU connectivity issues
#   Provides multiple fixes and workarounds for ERR_CONNECTION_CLOSED
#
# USAGE:
#   ./fix_openxlab_connectivity.sh
#
# WHAT IT DOES:
#   • Diagnoses OpenXLab connectivity issues
#   • Tests multiple proxy configurations
#   • Provides DNS and network fixes
#   • Offers alternative access methods
#   • Creates temporary workarounds

echo "🔧 OpenXLab/MinerU Connectivity Fix"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "🔍 Diagnosing OpenXLab connectivity issues..."
echo ""

# Step 1: Test basic connectivity
echo "1️⃣ Testing basic connectivity..."
echo "================================"

# Test DNS resolution
echo -n "🌐 DNS Resolution: "
if nslookup sso.openxlab.org.cn >/dev/null 2>&1; then
    echo -e "${GREEN}✅ OK${NC}"
    dns_ok=true
else
    echo -e "${RED}❌ Failed${NC}"
    dns_ok=false
fi

# Test ping
echo -n "📡 Ping Test: "
if timeout 5 ping -c 1 sso.openxlab.org.cn >/dev/null 2>&1; then
    echo -e "${GREEN}✅ OK${NC}"
    ping_ok=true
else
    echo -e "${RED}❌ Failed${NC}"
    ping_ok=false
fi

# Test port 443 (HTTPS)
echo -n "🔒 HTTPS Port (443): "
if timeout 5 nc -z sso.openxlab.org.cn 443 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Open${NC}"
    port_ok=true
else
    echo -e "${RED}❌ Blocked${NC}"
    port_ok=false
fi

echo ""

# Step 2: Analyze results and provide fixes
echo "2️⃣ Analysis and Solutions:"
echo "=========================="

if [ "$dns_ok" = false ]; then
    echo -e "🔧 ${YELLOW}DNS ISSUE DETECTED${NC}"
    echo "Solutions:"
    echo "• Switch DNS servers:"
    echo "  - Google DNS: 8.8.8.8, 8.8.4.4"
    echo "  - Cloudflare DNS: 1.1.1.1, 1.0.0.1"
    echo "  - Quad9 DNS: 9.9.9.9, 149.112.112.112"
    echo ""
    echo "🔧 Quick DNS fix:"
    echo "sudo systemctl stop systemd-resolved"
    echo "echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf"
    echo "echo 'nameserver 1.1.1.1' | sudo tee -a /etc/resolv.conf"
    echo ""
fi

if [ "$ping_ok" = false ] || [ "$port_ok" = false ]; then
    echo -e "🔧 ${YELLOW}NETWORK BLOCKING DETECTED${NC}"
    echo "This suggests that OpenXLab might be:"
    echo "• Blocked by your ISP or network"
    echo "• Experiencing regional access restrictions"
    echo "• Having server-side issues"
    echo ""
fi

# Step 3: Test different access methods
echo "3️⃣ Testing Alternative Access Methods:"
echo "======================================"

# Test with different user agents
echo "🔍 Testing with mobile user agent:"
mobile_test=$(timeout 8 curl -s -o /dev/null -w "%{http_code}" \
    --user-agent "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15" \
    "https://openxlab.org.cn/" 2>/dev/null)

if [ "$mobile_test" = "200" ]; then
    echo -e "📱 Mobile access: ${GREEN}✅ Working${NC}"
else
    echo -e "📱 Mobile access: ${RED}❌ Failed (Status: $mobile_test)${NC}"
fi

# Test main domain vs SSO
echo ""
echo "🔍 Testing different OpenXLab endpoints:"

endpoints=(
    "https://openxlab.org.cn/"
    "https://www.openxlab.org.cn/"
    "https://api.openxlab.org.cn/"
    "https://mineru.net/"
)

for endpoint in "${endpoints[@]}"; do
    echo -n "📍 $(echo $endpoint | cut -d'/' -f3): "
    status=$(timeout 8 curl -s -o /dev/null -w "%{http_code}" "$endpoint" 2>/dev/null)
    if [ "$status" = "200" ] || [ "$status" = "301" ] || [ "$status" = "302" ]; then
        echo -e "${GREEN}✅ OK (Status: $status)${NC}"
    else
        echo -e "${RED}❌ Failed (Status: $status)${NC}"
    fi
done

echo ""

# Step 4: Proxy optimization
echo "4️⃣ Proxy Configuration Optimization:"
echo "===================================="

echo "Current proxy status:"
ai_node=$(curl -s http://127.0.0.1:9090/proxies/AI | jq -r '.now' 2>/dev/null || echo "Unknown")
streaming_node=$(curl -s http://127.0.0.1:9090/proxies/Streaming | jq -r '.now' 2>/dev/null || echo "Unknown")
echo "🤖 AI Group: $ai_node"
echo "🎬 Streaming Group: $streaming_node"
echo ""

echo "🔧 Recommended proxy settings for Chinese AI platforms:"
echo "• Use Hong Kong or Singapore nodes when available"
echo "• Current Streaming node (V1-香港01) might work better for Chinese sites"
echo "• Consider using DIRECT connection for Chinese domestic platforms"
echo ""

# Step 5: Create workaround scripts
echo "5️⃣ Creating Workaround Solutions:"
echo "================================="

# Create a desktop shortcut for OpenXLab
cat > "$HOME/Desktop/OpenXLab-Direct.desktop" 2>/dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenXLab (Direct)
Comment=Access OpenXLab with direct connection
Exec=env no_proxy="*" firefox https://openxlab.org.cn/
Icon=firefox
Terminal=false
Categories=Development;
EOF

if [ -f "$HOME/Desktop/OpenXLab-Direct.desktop" ]; then
    chmod +x "$HOME/Desktop/OpenXLab-Direct.desktop"
    echo -e "✅ Created desktop shortcut: ${CYAN}OpenXLab-Direct.desktop${NC}"
fi

# Create browser launch script
cat > "/tmp/openxlab_browser.sh" << 'EOF'
#!/bin/bash
echo "🌐 Launching OpenXLab with optimized settings..."
export no_proxy="*"
export NO_PROXY="*"
if command -v firefox >/dev/null 2>&1; then
    firefox --new-window "https://openxlab.org.cn/" &
elif command -v google-chrome >/dev/null 2>&1; then
    google-chrome --new-window "https://openxlab.org.cn/" &
elif command -v chromium-browser >/dev/null 2>&1; then
    chromium-browser --new-window "https://openxlab.org.cn/" &
else
    echo "Please manually open: https://openxlab.org.cn/"
fi
EOF

chmod +x "/tmp/openxlab_browser.sh"
echo -e "✅ Created browser launcher: ${CYAN}/tmp/openxlab_browser.sh${NC}"

echo ""

# Step 6: Provide manual solutions
echo "6️⃣ Manual Solutions and Alternatives:"
echo "===================================="

echo -e "${BLUE}Option 1: Browser Settings${NC}"
echo "• Open browser in private/incognito mode"
echo "• Disable proxy for openxlab.org.cn in browser settings"
echo "• Clear browser cache and cookies"
echo ""

echo -e "${BLUE}Option 2: System Network Settings${NC}"
echo "• Add openxlab.org.cn to proxy bypass list"
echo "• Temporarily disable proxy for Chinese sites"
echo "• Use different DNS servers"
echo ""

echo -e "${BLUE}Option 3: Alternative URLs${NC}"
echo "Try these alternative URLs:"
echo "• Main site: https://openxlab.org.cn/"
echo "• GitHub: https://github.com/OpenXLab"
echo "• Documentation: https://openxlab.org.cn/docs/"
echo ""

echo -e "${BLUE}Option 4: VPN/Proxy Alternatives${NC}"
echo "• Use a VPN with servers in Hong Kong/Singapore"
echo "• Try different proxy servers optimized for China"
echo "• Consider using a China-specific VPN service"
echo ""

# Step 7: Quick fix commands
echo "7️⃣ Quick Fix Commands:"
echo "======================"

echo -e "${CYAN}# Test direct connection${NC}"
echo "curl --noproxy '*' https://openxlab.org.cn/"
echo ""

echo -e "${CYAN}# Launch browser without proxy${NC}"
echo "/tmp/openxlab_browser.sh"
echo ""

echo -e "${CYAN}# Check if sites work without proxy${NC}"
echo "env no_proxy='*' curl https://openxlab.org.cn/"
echo ""

echo -e "${CYAN}# Test with different DNS${NC}"
echo "nslookup sso.openxlab.org.cn 8.8.8.8"
echo ""

# Final recommendations
echo ""
echo "🎯 FINAL RECOMMENDATIONS:"
echo "========================"

if [ "$dns_ok" = false ]; then
    echo "🔴 HIGH PRIORITY: Fix DNS resolution first"
elif [ "$ping_ok" = false ] || [ "$port_ok" = false ]; then
    echo "🟡 MEDIUM PRIORITY: Network connectivity issues detected"
    echo "   → Try direct connection bypass"
    echo "   → Use alternative DNS servers"
    echo "   → Consider different VPN/proxy"
else
    echo "🟢 BASIC CONNECTIVITY OK: Issue likely proxy-related"
    echo "   → Try direct connection for OpenXLab"
    echo "   → Use Hong Kong/Singapore proxy nodes"
    echo "   → Clear browser cache"
fi

echo ""
echo "💡 IMMEDIATE ACTIONS:"
echo "1. Run: /tmp/openxlab_browser.sh"
echo "2. Or manually visit: https://openxlab.org.cn/ (bypass proxy)"
echo "3. If still not working, try: https://github.com/OpenXLab"
echo ""
echo "🔗 MinerU Direct Links:"
echo "• GitHub: https://github.com/opendatalab/MinerU"
echo "• Documentation: https://github.com/opendatalab/MinerU/blob/master/README.md"
echo ""
echo "✅ Fix completed! Try the solutions above."
