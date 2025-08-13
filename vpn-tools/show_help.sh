#!/bin/bash

# 📚 Help Documentation Script
# 
# DESCRIPTION:
#   Quick access to documentation and usage guides for all testing tools
#
# USAGE:
#   ./show_help.sh [script_name]
#   ./show_help.sh list           # List all available scripts
#   ./show_help.sh ai             # Show AI-related scripts
#   ./show_help.sh streaming      # Show streaming-related scripts  
#   ./show_help.sh network        # Show network testing scripts

echo "📚 Clash/Mihomo VPN Testing Tools Help"
echo "======================================"
echo "📍 Location: vpn-tools/ folder"

show_script_help() {
    local script=$1
    if [[ -f "$script" ]]; then
        echo ""
        echo "📄 $script:"
        echo "$(head -30 "$script" | grep -A 25 "^# DESCRIPTION:" | sed 's/^# //' | sed 's/^#$//')"
        echo ""
    else
        echo "❌ Script $script not found"
    fi
}

case "${1:-list}" in
    "list")
        echo ""
        echo "🔍 Available Scripts:"
        echo "===================="
        echo ""
        echo "🤖 AI OPTIMIZATION TOOLS:"
        echo "  optimize_ai.sh              - Quick AI optimization with Braintrust.dev (2-3 min)"
        echo "  optimize_ai_enhanced.sh     - Enhanced AI optimization for development (5-7 min)"
        echo "  test_ai_connectivity.sh     - Comprehensive AI testing (15-20 min)"
        echo "  test_braintrust_connectivity.sh - Braintrust.dev specific testing (3-5 min)"
        echo "  customize_ai_group.sh       - Interactive AI group management"
        echo ""
        echo "🎬 STREAMING OPTIMIZATION TOOLS:"
        echo "  select_youtube_node.sh      - Quick YouTube optimization (3-5 min)"
        echo "  optimize_youtube_streaming.sh - Full streaming optimization (10-15 min)"
        echo "  streaming_manager.sh        - Interactive streaming management"
        echo "  quick_streaming_test.sh     - Instant streaming verification (30s)"
        echo ""
        echo "🌐 NETWORK TESTING TOOLS:"
        echo "  network_connectivity_test.sh - Comprehensive network test (5-8 min)"
        echo "  quick_vpn_check.sh          - Instant VPN status check (15-30s)"
        echo ""
        echo "📋 USAGE EXAMPLES:"
        echo "  ./show_help.sh optimize_ai.sh           # Get help for specific script"
        echo "  ./show_help.sh ai                       # Show all AI tools"
        echo "  ./show_help.sh streaming                 # Show all streaming tools"
        echo "  ./show_help.sh network                   # Show all network tools"
        echo ""
        echo "📖 For detailed documentation: cat TESTING_TOOLS_GUIDE.md"
        echo "📍 All tools are located in the vpn-tools/ folder"
        ;;
    
    "ai")
        echo ""
        echo "🤖 AI OPTIMIZATION TOOLS:"
        echo "========================="
        show_script_help "optimize_ai.sh"
        show_script_help "test_ai_connectivity.sh"
        show_script_help "customize_ai_group.sh"
        ;;
        
    "streaming")
        echo ""
        echo "🎬 STREAMING OPTIMIZATION TOOLS:"
        echo "==============================="
        show_script_help "select_youtube_node.sh"
        show_script_help "optimize_youtube_streaming.sh"
        show_script_help "streaming_manager.sh"
        echo "  quick_streaming_test.sh - Instant streaming verification"
        ;;
        
    "network")
        echo ""
        echo "🌐 NETWORK TESTING TOOLS:"
        echo "========================"
        show_script_help "network_connectivity_test.sh"
        show_script_help "quick_vpn_check.sh"
        ;;
        
    *.sh)
        show_script_help "$1"
        ;;
        
    *)
        echo ""
        echo "❓ Unknown option: $1"
        echo ""
        echo "Available options:"
        echo "  list, ai, streaming, network, or any script name (e.g., optimize_ai.sh)"
        echo ""
        echo "Example: ./show_help.sh optimize_ai.sh"
        ;;
esac

echo ""
echo "💡 QUICK START COMMANDS:"
echo "  ./quick_vpn_check.sh                    # Check if VPN is working"
echo "  ./optimize_ai.sh                        # Optimize for AI services"  
echo "  ./select_youtube_node.sh                # Optimize for YouTube"
echo "  ./network_connectivity_test.sh quick    # Quick network test"
echo ""
