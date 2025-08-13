#!/bin/bash

# 🚀 VPN Tools Access Script
# 
# This script provides easy access to the VPN testing and optimization tools
# All tools are located in the vpn-tools/ folder

echo "🚀 Clash/Mihomo VPN Tools Access"
echo "==============================="
echo ""

# Check if vpn-tools folder exists
if [ ! -d "vpn-tools" ]; then
    echo "❌ Error: vpn-tools folder not found!"
    echo "Please make sure you're in the correct directory."
    exit 1
fi

# Show available options
echo "📋 Available Options:"
echo ""
echo "  1. 🎮 Launch Interactive Menu"
echo "  2. ⚡ Quick VPN Status Check"
echo "  3. 🤖 AI Service Optimization"
echo "  4. 🎬 YouTube Optimization"
echo "  5. 🌐 Network Connectivity Test"
echo "  6. 📚 Show Help System"
echo "  7. 📁 Enter VPN Tools Folder"
echo "  8. 📖 View Documentation"
echo ""
echo "  0. Exit"
echo ""

read -p "Select option (0-8): " choice

case $choice in
    1)
        echo "🎮 Launching Interactive Menu..."
        cd vpn-tools && ./launcher.sh
        ;;
    2)
        echo "⚡ Running Quick VPN Status Check..."
        cd vpn-tools && ./quick_vpn_check.sh
        ;;
    3)
        echo "🤖 Running AI Service Optimization..."
        cd vpn-tools && ./optimize_ai.sh
        ;;
    4)
        echo "🎬 Running YouTube Optimization..."
        cd vpn-tools && ./select_youtube_node.sh
        ;;
    5)
        echo "🌐 Running Network Connectivity Test..."
        cd vpn-tools && ./network_connectivity_test.sh
        ;;
    6)
        echo "📚 Showing Help System..."
        cd vpn-tools && ./show_help.sh list
        ;;
    7)
        echo "📁 Entering VPN Tools Folder..."
        echo "Use 'cd vpn-tools' to access the tools directory"
        echo "Available tools:"
        cd vpn-tools && ls -1 *.sh | head -10
        echo "... and more. Run './show_help.sh list' for complete list."
        ;;
    8)
        echo "📖 Available Documentation:"
        echo ""
        if [ -f "vpn-tools/README.md" ]; then
            echo "  📄 vpn-tools/README.md - VPN Tools Overview"
        fi
        if [ -f "vpn-tools/TESTING_TOOLS_GUIDE.md" ]; then
            echo "  📄 vpn-tools/TESTING_TOOLS_GUIDE.md - Complete Usage Guide"
        fi
        if [ -f "vpn-tools/QUICK_REFERENCE.md" ]; then
            echo "  📄 vpn-tools/QUICK_REFERENCE.md - Quick Reference Card"
        fi
        echo ""
        echo "To view: cat vpn-tools/[filename]"
        ;;
    0)
        echo "👋 Goodbye!"
        exit 0
        ;;
    *)
        echo "❌ Invalid option. Please try again."
        ;;
esac

echo ""
echo "💡 Tip: All VPN tools are located in the 'vpn-tools/' folder"
echo "💡 For direct access: cd vpn-tools && ./launcher.sh"
