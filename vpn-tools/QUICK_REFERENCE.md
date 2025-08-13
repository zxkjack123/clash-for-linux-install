# 🚀 QUICK REFERENCE CARD

**📁 Important**: All commands must be run from the `vpn-tools/` folder.

## 🎯 Daily Usage Commands

```bash
# Navigate to tools folder first
cd vpn-tools

# Morning routine - verify everything works
./quick_vpn_check.sh

# Before AI work (ChatGPT, Claude, etc.)
./optimize_ai.sh

# Before streaming (YouTube, Netflix, etc.)
./select_youtube_node.sh

# Weekly comprehensive check
./network_connectivity_test.sh full
```

## ⚡ Emergency Fixes

```bash
# Navigate to tools folder first
cd vpn-tools

# AI services not working
./optimize_ai.sh

# YouTube/streaming issues  
./select_youtube_node.sh

# General connectivity problems
./network_connectivity_test.sh quick

# Switch streaming regions
./streaming_manager.sh us    # US content
./streaming_manager.sh hk    # Asia content
./streaming_manager.sh jp    # Japan content
```

## 📊 Testing & Troubleshooting

```bash
# Quick health check (30 seconds)
./quick_vpn_check.sh

# Network connectivity test (1-8 minutes)
./network_connectivity_test.sh [full|quick|chinese|international]

# Comprehensive AI testing (15-20 minutes)
./test_ai_connectivity.sh

# Full streaming optimization (10-15 minutes)
./optimize_youtube_streaming.sh
```

## 🛠️ Management Commands

```bash
# Interactive streaming management
./streaming_manager.sh [status|test|auto|list|us|sg|jp|hk|tw]

# AI group customization
./customize_ai_group.sh

# Show help for any script
./show_help.sh [script_name|ai|streaming|network]

# List all available tools
./show_help.sh list
```

## 🎯 Performance Expectations

| Status | Chinese Sites | International | AI Services | Streaming |
|--------|---------------|---------------|-------------|-----------|
| 🏆 Excellent | 100%, <200ms | >90% via proxy | >90%, <5s | YouTube <3s |
| 🥈 Good | 100%, <500ms | >80% via proxy | >70%, <10s | YouTube <6s |
| 🔧 Needs Fix | <100%, >500ms | <80% via proxy | <70%, >10s | YouTube >6s |

## 📞 Quick Help

```bash
./show_help.sh              # Show all available scripts
./show_help.sh ai            # AI tools help
./show_help.sh streaming     # Streaming tools help  
./show_help.sh network       # Network tools help
cat TESTING_TOOLS_GUIDE.md  # Full documentation
```

---
**🎉 Happy proxy optimization!** 
*For detailed guides, see TESTING_TOOLS_GUIDE.md*
