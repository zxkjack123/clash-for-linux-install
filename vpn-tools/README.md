# 🚀 VPN Testing & Optimization Tools

Welcome to the comprehensive VPN testing and optimization toolkit for Clash/Mihomo proxy services. This collection of tools helps you achieve optimal performance for AI services, streaming platforms, and general connectivity.

## 📁 Folder Contents

This folder contains a curated set of testing scripts and documentation designed to optimize and monitor your VPN/proxy performance.

## 🎯 Quick Start

### Method 1: Interactive Launcher (Recommended)
```bash
cd vpn-tools
./launcher.sh
```

### Method 2: Direct Commands
```bash
cd vpn-tools
./optimize_all_network_fast.sh  # 3–5 min one-click stabilization (guard+AI+verify)
./quick_vpn_check.sh             # 30-second status check
./optimize_ai.sh                 # AI optimization (ChatGPT, Claude)
./optimize_dev_nodes.sh          # GitHub / NPM / PyPI optimization
./select_youtube_node.sh         # YouTube optimization
```

### Method 3: Help System
```bash
cd vpn-tools
./show_help.sh list              # List all available tools
./show_help.sh ai                # AI tools help
./show_help.sh streaming         # Streaming tools help
```

## 📋 Tool Categories

### 🤖 AI Optimization
- **`optimize_ai.sh`** - Quick AI optimization (2-3 min)
- **`test_ai_connectivity.sh`** - Comprehensive AI testing (15-20 min)
- **`customize_ai_group.sh`** - Interactive AI management
- **`quick_ai_test.sh`** - Instant AI verification (30s)

### 🧑‍💻 Dev / Research Optimization
- **`optimize_dev_nodes.sh`** - Auto-select GitHub/NPM/PyPI friendly nodes (2-3 min)
- **`quick_dev_research_test.sh`** - Deep diagnostics for GitHub/NPM/PyPI (2-3 min)

### 🎬 Streaming Optimization
- **`select_youtube_node.sh`** - Quick YouTube optimization (3-5 min)
- **`optimize_youtube_streaming.sh`** - Full streaming optimization (10-15 min)
- **`streaming_manager.sh`** - Interactive streaming management
- **`quick_streaming_test.sh`** - Instant streaming verification (30s)
- **`fix_zoom_connectivity.sh`** - One-click Zoom diagnose/repair (auto DNS check, node switch)

### 🌐 Network Testing
- **`network_connectivity_test.sh`** - Comprehensive network test (5-8 min)
- **`quick_vpn_check.sh`** - Instant VPN status (15-30s)
- **`jp_tailscale_single_node_test.sh`** - JP-Tailscale single-node benchmark (DERP/latency/throughput/concurrency)
- **`test_vscode_core_domains.sh`** - Compare DIRECT vs proxy success-rate for VS Code core domains
- **`trace_mihomo_connections.sh`** - Live controller `/connections` tracer (prove VS Code/Copilot traffic is going through mihomo and which rule/chain it hits)

### 🛠️ Management & Utilities
- **`launcher.sh`** - Interactive tool launcher
- **`show_help.sh`** - Help and documentation system
- **`harden_controller_security.sh`** - Harden controller exposure (set secret, optionally bind controller to localhost)

## 📚 Documentation

### Primary Guides
- **[TESTING_TOOLS_GUIDE.md](TESTING_TOOLS_GUIDE.md)** - Complete usage guide (200+ lines)
- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - Essential commands reference
- **[TOOLS_INVENTORY.md](TOOLS_INVENTORY.md)** - Complete inventory of all tools

### Generated Reports (on-demand)
- Reports are generated on-demand by scripts and no longer versioned in the repo.

## 🎯 Usage Scenarios

### 📅 Daily Routine
```bash
cd vpn-tools
./quick_vpn_check.sh             # Morning status check
./optimize_ai.sh                 # Before AI work
./optimize_dev_nodes.sh          # Before GitHub/NPM work
./select_youtube_node.sh         # Before streaming
```

### 🔧 Troubleshooting Workflow
```bash
cd vpn-tools
./quick_vpn_check.sh                    # 1. Quick diagnosis
./network_connectivity_test.sh quick    # 2. Detailed check
./optimize_ai.sh                        # 3. Fix AI issues
./optimize_dev_nodes.sh                 # 4. Fix GitHub/NPM/PyPI latency
./select_youtube_node.sh                # 5. Fix YouTube streaming
./fix_zoom_connectivity.sh              # 6. Fix Zoom connectivity
./network_connectivity_test.sh full     # 7. Final verification
```

### 🚀 Initial Setup
```bash
cd vpn-tools
./launcher.sh                           # Interactive setup
./test_ai_connectivity.sh               # Comprehensive AI analysis
./optimize_youtube_streaming.sh         # Full streaming optimization
```

### 🌍 Regional Switching
```bash
cd vpn-tools
./streaming_manager.sh us      # US content (Netflix US)
./streaming_manager.sh hk      # Asian content (faster for China)
./streaming_manager.sh jp      # Japanese content (anime)
./fix_zoom_connectivity.sh https://us05web.zoom.us/j/xxxxxxxx   # direct meeting check
```

## 📊 Performance Expectations

| Category          | Excellent      | Good           | Needs Fix      |
| ----------------- | -------------- | -------------- | -------------- |
| **Chinese Sites** | 100%, <200ms   | 100%, <500ms   | <100%, >500ms  |
| **International** | >90% via proxy | >80% via proxy | <80% via proxy |
| **AI Services**   | >90%, <5s      | >70%, <10s     | <70%, >10s     |
| **Streaming**     | YouTube <3s    | YouTube <6s    | YouTube >6s    |

## 🛡️ Important Notes

### File Locations
- **Working Directory**: Always run commands from the `vpn-tools/` folder
- **Scripts**: All executable scripts (`.sh` files) are in this folder
- **Documentation**: All guides and reports are in this folder

### Prerequisites
- Clash/Mihomo proxy service must be running
- Scripts require network connectivity
- Some tools may take several minutes to complete

### Safety
- All scripts are read-only testing tools
- No permanent changes are made to your system
- Safe to run multiple times

## 🧩 VS Code / Copilot: “Fetching …” 卡顿排查

当你在 VS Code / Copilot 里看到类似 `Fetching https://github.com/...` 长时间卡住时，通常是 **请求没有稳定走代理**（直连超时/重试），或者进了 mihomo 但命中 DIRECT 规则导致直连不通。

推荐流程（2 分钟内能定位到“走没走代理/命中了哪条规则”）：

1. 确保 VS Code 显式走本地代理（推荐 override）：
	- `http.proxy`: `http://127.0.0.1:7890`
	- `http.proxySupport`: `override`
2. 运行一次：`./optimize_vscode_copilot.sh`（验证 Copilot/GitHub/OpenAI 端点经 7890 可达）
3. 复现卡顿的同时运行：`./trace_mihomo_connections.sh --seconds 60`
	- 输出会显示 `rule=...` / `chains=...`，可直接证明 VS Code/Copilot 流量是否进入 mihomo、最终走 DIRECT 还是 AUTO-SMART/具体链路。

## 🆘 Getting Help

### Interactive Help
```bash
cd vpn-tools
./show_help.sh                  # General help
./show_help.sh list             # List all tools
./show_help.sh optimize_ai.sh   # Specific script help
```

### Documentation
```bash
cd vpn-tools
cat TESTING_TOOLS_GUIDE.md     # Complete guide
cat QUICK_REFERENCE.md          # Quick commands
cat TOOLS_INVENTORY.md          # Full inventory
```

### Common Issues
1. **"Permission denied"** - Run: `chmod +x *.sh`
2. **"Script not found"** - Make sure you're in the `vpn-tools/` folder
3. **"Connection failed"** - Check that Clash/Mihomo service is running

## 🎉 Quick Start Examples

### First Time User
```bash
cd vpn-tools
./launcher.sh                  # Start with interactive menu
```

### Experienced User
```bash
cd vpn-tools
./quick_vpn_check.sh           # Quick status
./optimize_ai.sh               # AI optimization
./optimize_dev_nodes.sh        # GitHub/NPM/PyPI optimization
./select_youtube_node.sh       # YouTube optimization
./network_connectivity_test.sh full  # Comprehensive test
```

### Troubleshooting
```bash
cd vpn-tools
./show_help.sh list            # See what's available
./network_connectivity_test.sh quick  # Diagnose issues
```

---

**🎊 Happy VPN optimization!** 

*For detailed instructions, see [TESTING_TOOLS_GUIDE.md](TESTING_TOOLS_GUIDE.md)*
