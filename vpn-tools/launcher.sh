#!/bin/bash

# 🚀 Proxy Tools Launcher
# 
# DESCRIPTION:
#   Interactive launcher for all proxy testing and optimization tools
#   Simple menu-driven interface for easy tool selection

echo "🚀 Clash/Mihomo VPN Testing Tools Launcher"
echo "=========================================="
echo "📍 Location: vpn-tools/ folder"
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

show_main_menu() {
    echo -e "${BLUE}📋 Main Menu:${NC}"
    echo ""
    echo "  1. ⚡ Quick VPN Check (30s)"
    echo "  2. 🤖 AI Optimization (3 min)"
    echo "  3. 🎬 YouTube Optimization (5 min)"
    echo "  4. 🌐 Network Test (8 min)"
    echo ""
    echo "  5. 🔧 Advanced AI Tools"
    echo "  6. 🎮 Advanced Streaming Tools"
    echo "  7. 📊 Advanced Network Tools"
    echo ""
    echo "  8. 📚 Help & Documentation"
    echo "  9. 📄 Quick Reference Card"
    echo ""
    echo "  0. Exit"
    echo ""
}

show_ai_menu() {
    echo -e "${BLUE}🤖 AI Tools Menu:${NC}"
    echo ""
    echo "  1. Quick AI Optimization (3 min)"
    echo "  2. Comprehensive AI Testing (20 min)"
    echo "  3. Customize AI Group"
    echo "  4. Back to Main Menu"
    echo ""
}

show_streaming_menu() {
    echo -e "${BLUE}🎬 Streaming Tools Menu:${NC}"
    echo ""
    echo "  1. Quick YouTube Optimization (5 min)"
    echo "  2. Full Streaming Optimization (15 min)"
    echo "  3. Streaming Manager (interactive)"
    echo "  4. Quick Streaming Test (30s)"
    echo "  5. Back to Main Menu"
    echo ""
}

show_network_menu() {
    echo -e "${BLUE}🌐 Network Tools Menu:${NC}"
    echo ""
    echo "  1. Quick Network Test (1 min)"
    echo "  2. Full Network Test (8 min)"
    echo "  3. Chinese Sites Only"
    echo "  4. International Sites Only"
    echo "  5. AI Platforms Only"
    echo "  6. Streaming Platforms Only"
    echo "  7. Speed Test Only"
    echo "  8. Back to Main Menu"
    echo ""
}

run_tool() {
    local tool=$1
    local description=$2
    echo ""
    echo -e "${YELLOW}🚀 Running: $description${NC}"
    echo "============================================"
    if [[ -f "$tool" && -x "$tool" ]]; then
        "./$tool"
    else
        echo -e "${RED}❌ Error: $tool not found or not executable${NC}"
        echo "Please make sure the script exists and has execute permissions."
    fi
    echo ""
    echo -e "${GREEN}✅ Tool execution completed.${NC}"
    echo ""
    read -p "Press Enter to continue..."
    echo ""
}

# Main execution loop
while true; do
    clear
    echo "🚀 Clash/Mihomo VPN Testing Tools Launcher"
    echo "=========================================="
    echo "📍 Location: vpn-tools/ folder"
    echo ""
    
    show_main_menu
    read -p "Select option (0-9): " choice
    
    case $choice in
        1)
            run_tool "quick_vpn_check.sh" "Quick VPN Status Check"
            ;;
        2)
            run_tool "optimize_ai.sh" "AI Service Optimization"
            ;;
        3)
            run_tool "select_youtube_node.sh" "YouTube Optimization"
            ;;
        4)
            run_tool "network_connectivity_test.sh" "Comprehensive Network Test"
            ;;
        5)
            # AI Tools submenu
            while true; do
                clear
                echo "🚀 Clash/Mihomo Proxy Tools Launcher"
                echo "===================================="
                echo ""
                show_ai_menu
                read -p "Select AI tool (1-4): " ai_choice
                
                case $ai_choice in
                    1)
                        run_tool "optimize_ai.sh" "Quick AI Optimization"
                        ;;
                    2)
                        run_tool "test_ai_connectivity.sh" "Comprehensive AI Testing"
                        ;;
                    3)
                        run_tool "customize_ai_group.sh" "AI Group Customization"
                        ;;
                    4)
                        break
                        ;;
                    *)
                        echo "Invalid option. Please try again."
                        sleep 1
                        ;;
                esac
            done
            ;;
        6)
            # Streaming Tools submenu
            while true; do
                clear
                echo "🚀 Clash/Mihomo Proxy Tools Launcher"
                echo "===================================="
                echo ""
                show_streaming_menu
                read -p "Select streaming tool (1-5): " stream_choice
                
                case $stream_choice in
                    1)
                        run_tool "select_youtube_node.sh" "Quick YouTube Optimization"
                        ;;
                    2)
                        run_tool "optimize_youtube_streaming.sh" "Full Streaming Optimization"
                        ;;
                    3)
                        echo ""
                        echo -e "${YELLOW}🎮 Streaming Manager Usage:${NC}"
                        echo "  ./streaming_manager.sh status    # Show current status"
                        echo "  ./streaming_manager.sh us        # Switch to US"
                        echo "  ./streaming_manager.sh hk        # Switch to Hong Kong"
                        echo "  ./streaming_manager.sh jp        # Switch to Japan"
                        echo "  ./streaming_manager.sh test      # Test current node"
                        echo "  ./streaming_manager.sh auto      # Auto-select best"
                        echo ""
                        read -p "Press Enter to continue..."
                        ;;
                    4)
                        run_tool "quick_streaming_test.sh" "Quick Streaming Test"
                        ;;
                    5)
                        break
                        ;;
                    *)
                        echo "Invalid option. Please try again."
                        sleep 1
                        ;;
                esac
            done
            ;;
        7)
            # Network Tools submenu
            while true; do
                clear
                echo "🚀 Clash/Mihomo Proxy Tools Launcher"
                echo "===================================="
                echo ""
                show_network_menu
                read -p "Select network tool (1-8): " net_choice
                
                case $net_choice in
                    1)
                        run_tool "network_connectivity_test.sh quick" "Quick Network Test"
                        ;;
                    2)
                        run_tool "network_connectivity_test.sh full" "Full Network Test"
                        ;;
                    3)
                        run_tool "network_connectivity_test.sh chinese" "Chinese Sites Test"
                        ;;
                    4)
                        run_tool "network_connectivity_test.sh international" "International Sites Test"
                        ;;
                    5)
                        run_tool "network_connectivity_test.sh ai" "AI Platforms Test"
                        ;;
                    6)
                        run_tool "network_connectivity_test.sh streaming" "Streaming Platforms Test"
                        ;;
                    7)
                        run_tool "network_connectivity_test.sh speed" "Speed Test"
                        ;;
                    8)
                        break
                        ;;
                    *)
                        echo "Invalid option. Please try again."
                        sleep 1
                        ;;
                esac
            done
            ;;
        8)
            echo ""
            echo -e "${BLUE}📚 Help & Documentation:${NC}"
            echo ""
            echo "Available help commands:"
            echo "  ./show_help.sh list                 # List all scripts"
            echo "  ./show_help.sh ai                   # AI tools help"
            echo "  ./show_help.sh streaming             # Streaming tools help"
            echo "  ./show_help.sh network               # Network tools help"
            echo "  ./show_help.sh [script_name]         # Specific script help"
            echo ""
            echo "Documentation files:"
            echo "  cat TESTING_TOOLS_GUIDE.md          # Complete guide"
            echo "  cat QUICK_REFERENCE.md               # Quick reference"
            echo ""
            read -p "Press Enter to continue..."
            ;;
        9)
            echo ""
            echo -e "${BLUE}📄 Quick Reference Card:${NC}"
            echo ""
            cat QUICK_REFERENCE.md 2>/dev/null || echo "QUICK_REFERENCE.md not found"
            echo ""
            read -p "Press Enter to continue..."
            ;;
        0)
            echo ""
            echo -e "${GREEN}👋 Thanks for using Clash/Mihomo Proxy Tools!${NC}"
            echo ""
            exit 0
            ;;
        *)
            echo ""
            echo -e "${RED}❌ Invalid option. Please try again.${NC}"
            sleep 1
            ;;
    esac
done
