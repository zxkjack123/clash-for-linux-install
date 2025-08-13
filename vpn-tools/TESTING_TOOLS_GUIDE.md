# 🚀 Clash/Mihomo VPN Testing & Optimization Tools

A comprehensive suite of tools for testing, optimizing, and managing your Clash/Mihomo proxy configuration. These scripts help you get the best performance for AI services, streaming platforms, and general connectivity.

**📁 Location**: All tools are located in the `vpn-tools/` folder for better organization.

## 📚 Table of Contents

- [Quick Start](#quick-start)
- [Test Scripts Overview](#test-scripts-overview)
- [AI Optimization Tools](#ai-optimization-tools)
- [Streaming Optimization Tools](#streaming-optimization-tools)
- [Network Testing Tools](#network-testing-tools)
- [Management Tools](#management-tools)
- [Troubleshooting](#troubleshooting)

## 🚀 Quick Start

### Basic Health Check
```bash
# Navigate to tools folder
cd vpn-tools

# Quick status check
./quick_vpn_check.sh

# Full network connectivity test
./network_connectivity_test.sh full
```

### Optimize for AI Services
```bash
cd vpn-tools

# Quick AI optimization
./optimize_ai.sh

# Comprehensive AI testing
./test_ai_connectivity.sh
```

### Optimize for Streaming
```bash
cd vpn-tools

# Quick YouTube optimization
./select_youtube_node.sh

# Full streaming optimization
./optimize_youtube_streaming.sh
```

## 📋 Test Scripts Overview

### 🎯 Purpose Categories

| Category | Scripts | Purpose |
|----------|---------|---------|
| **AI Services** | `optimize_ai.sh`, `test_ai_connectivity.sh` | Optimize for OpenAI, ChatGPT, Claude |
| **Streaming** | `optimize_youtube_streaming.sh`, `streaming_manager.sh` | Optimize for YouTube, Netflix, Twitch |
| **Network Testing** | `network_connectivity_test.sh`, `quick_vpn_check.sh` | Test overall connectivity |
| **Management** | `customize_ai_group.sh`, `streaming_manager.sh` | Interactive proxy management |

---

## 🤖 AI Optimization Tools

### 1. `optimize_ai.sh` - Quick AI Optimization
**Purpose**: Fast optimization for AI services (OpenAI, ChatGPT, Claude)

**Usage**:
```bash
./optimize_ai.sh
```

**What it does**:
- Tests 6 key AI-capable nodes
- Measures OpenAI API, ChatGPT, and Claude connectivity
- Automatically selects and switches to the best performing node
- Provides performance verification

**When to use**:
- Before using AI services
- When AI services are slow or not working
- Daily optimization routine

**Expected output**:
```
🤖 AI Service Optimization Test
Testing: V1-美国01|流媒体|GPT
  OpenAI API: ✅ OK (2.3s)
  ChatGPT Web: ✅ OK
  Claude: ✅ OK
🎯 Setting AI group to best performing node
✅ AI group updated to: V1-美国05|流媒体|GPT
```

---

### 2. `test_ai_connectivity.sh` - Comprehensive AI Testing
**Purpose**: Detailed testing of all 33 AI-capable nodes across 5 regions

**Usage**:
```bash
./test_ai_connectivity.sh
```

**What it does**:
- Tests all 33 AI nodes (US, Singapore, Japan, Taiwan, Vietnam)
- Comprehensive testing of 6 AI services
- Performance ranking with latency analysis
- Detailed reporting and recommendations

**When to use**:
- Initial setup and configuration
- Troubleshooting AI connectivity issues
- Finding the absolute best AI nodes
- Weekly optimization review

**Duration**: 15-20 minutes (comprehensive testing)

---

### 3. `customize_ai_group.sh` - AI Group Management
**Purpose**: Interactive management and regional analysis of AI nodes

**Usage**:
```bash
./customize_ai_group.sh
```

**What it does**:
- Shows available AI nodes by region
- Tests representative nodes from each region
- Provides recommendations for optimal AI group configuration
- Regional performance comparison

**When to use**:
- Exploring different regional options
- Understanding AI node distribution
- Manual AI group customization

---

## 🎬 Streaming Optimization Tools

### 1. `optimize_youtube_streaming.sh` - Full Streaming Optimization
**Purpose**: Comprehensive optimization for YouTube and streaming platforms

**Usage**:
```bash
./optimize_youtube_streaming.sh
```

**What it does**:
- Tests all 26 streaming nodes across 5 regions
- Multi-phase testing (regional screening + detailed analysis)
- Tests YouTube, Netflix, Twitch, and video platforms
- Automatic best node selection with performance scoring

**When to use**:
- Setting up streaming for the first time
- YouTube videos are slow or not loading
- Comprehensive streaming optimization needed

**Duration**: 10-15 minutes (full testing)

**Expected output**:
```
🎬 YouTube Streaming Optimization Tool
Found 26 streaming-capable nodes:
🇺🇸 US: 10 nodes
🇭🇰 HK: 5 nodes
🏆 BEST NODES FOR YOUTUBE:
✅ 1. V1-香港01 (Perfect: 6/7, 1.2s)
🎯 Setting Streaming group to best node
✅ YouTube streaming optimization complete!
```

---

### 2. `select_youtube_node.sh` - Quick YouTube Optimization
**Purpose**: Fast testing of 8 key streaming candidates for YouTube

**Usage**:
```bash
./select_youtube_node.sh
```

**What it does**:
- Tests 8 pre-selected high-performance streaming nodes
- Focuses specifically on YouTube performance
- Quick selection and switching (3-5 minutes)
- YouTube-specific verification

**When to use**:
- Quick YouTube optimization needed
- Current streaming node is slow
- Daily streaming setup

**Duration**: 3-5 minutes

---

### 3. `streaming_manager.sh` - Interactive Streaming Management
**Purpose**: Easy streaming group management with regional switching

**Usage**:
```bash
# Show current status
./streaming_manager.sh status

# Switch to specific regions
./streaming_manager.sh us    # US nodes
./streaming_manager.sh sg    # Singapore nodes  
./streaming_manager.sh jp    # Japan nodes
./streaming_manager.sh hk    # Hong Kong nodes
./streaming_manager.sh tw    # Taiwan nodes

# Quick tests
./streaming_manager.sh test     # Test current node
./streaming_manager.sh auto     # Auto-select best
./streaming_manager.sh list     # List all nodes
```

**What it does**:
- Interactive streaming group management
- One-command regional switching
- Performance testing and verification
- Status monitoring

**When to use**:
- Need to switch streaming regions quickly
- Want to test different regional nodes
- Regular streaming management

---

### 4. `quick_streaming_test.sh` - Instant Streaming Verification
**Purpose**: Quick verification of current streaming performance

**Usage**:
```bash
./quick_streaming_test.sh
```

**What it does**:
- Tests current streaming node performance
- YouTube, Netflix, Twitch connectivity check
- Shows current IP and location
- Provides quick switching commands

**When to use**:
- Verify streaming is working
- Quick performance check
- Troubleshoot streaming issues

**Duration**: 30 seconds

---

## 🌐 Network Testing Tools

### 1. `network_connectivity_test.sh` - Comprehensive Network Test
**Purpose**: Complete connectivity verification for VPN/proxy setup

**Usage**:
```bash
# Full comprehensive test
./network_connectivity_test.sh full

# Quick test of key sites
./network_connectivity_test.sh quick

# Test Chinese sites only
./network_connectivity_test.sh chinese

# Test international sites only  
./network_connectivity_test.sh international

# Speed test only
./network_connectivity_test.sh speed
```

**What it does**:
- Tests 10 Chinese domestic sites (direct connection)
- Tests 10 international sites (through proxy)
- Tests 6 AI platforms (through proxy)
- Tests 6 streaming platforms (through proxy)
- DNS resolution verification
- Speed testing and network analysis
- Comprehensive health assessment

**When to use**:
- Verify VPN/proxy is working correctly
- Troubleshoot connectivity issues
- Daily/weekly network health check
- After changing proxy configuration

**Duration**: 
- Full test: 5-8 minutes
- Quick test: 1 minute

**Expected output**:
```
🌐 Comprehensive Network Connectivity Test
📍 Current Network Information
🔗 Direct IP: 85.234.83.184 (Japan, Tokyo)
🔒 Proxy IP: 85.234.83.184 (Japan, Tokyo)

🇨🇳 Testing Chinese Domestic Sites (Direct Connection)
📊 Chinese sites: 10/10 working

🌍 Testing International Sites (Through Proxy)  
📊 International sites: 9/10 working

🎯 Overall success rate: 92.5% (37/40)
🏆 EXCELLENT - VPN working perfectly!
```

---

### 2. `quick_vpn_check.sh` - Instant VPN Status
**Purpose**: Fast VPN/proxy status verification

**Usage**:
```bash
./quick_vpn_check.sh
```

**What it does**:
- Shows current AI and Streaming group nodes
- Displays direct vs proxy IP addresses
- Quick test of key sites (Baidu, Google, YouTube, OpenAI)
- Instant health assessment

**When to use**:
- Quick daily VPN check
- Verify proxy is working
- Before starting work requiring VPN
- Troubleshoot basic connectivity

**Duration**: 15-30 seconds

---

## 🛠️ Management Tools

### AI Group Management
```bash
# Check current AI group
curl -s http://127.0.0.1:9090/proxies/AI | jq '.now'

# Switch AI group manually
curl -X PUT http://127.0.0.1:9090/proxies/AI \
  -H "Content-Type: application/json" \
  -d '{"name":"V1-美国05|流媒体|GPT"}'
```

### Streaming Group Management
```bash
# Check current streaming group
curl -s http://127.0.0.1:9090/proxies/Streaming | jq '.now'

# Use streaming manager for easy switching
./streaming_manager.sh us    # Switch to US
./streaming_manager.sh jp    # Switch to Japan
```

---

## 🔧 Troubleshooting

### Common Issues and Solutions

#### 1. AI Services Not Working
```bash
# Quick fix
./optimize_ai.sh

# If still not working
./test_ai_connectivity.sh
# Look for nodes with high scores and switch manually
```

#### 2. YouTube/Streaming Issues
```bash
# Quick fix
./select_youtube_node.sh

# For comprehensive optimization
./optimize_youtube_streaming.sh

# Try different regions
./streaming_manager.sh hk    # Hong Kong
./streaming_manager.sh sg    # Singapore
```

#### 3. General Connectivity Issues
```bash
# Full diagnosis
./network_connectivity_test.sh full

# Check if basic proxy is working
./quick_vpn_check.sh

# Test specific categories
./network_connectivity_test.sh chinese        # Domestic sites
./network_connectivity_test.sh international  # Foreign sites
```

#### 4. Slow Performance
```bash
# Speed test
./network_connectivity_test.sh speed

# Try switching regions
./streaming_manager.sh sg    # Singapore (Asia-Pacific)
./streaming_manager.sh jp    # Japan (Asia)
./streaming_manager.sh us    # US (Americas)
```

---

## ⚡ Quick Reference

### Daily Usage Commands
```bash
# Morning routine - verify everything works
./quick_vpn_check.sh

# Before AI work
./optimize_ai.sh

# Before streaming
./select_youtube_node.sh

# Weekly comprehensive check
./network_connectivity_test.sh full
```

### Performance Optimization
```bash
# Best overall performance
./optimize_ai.sh && ./select_youtube_node.sh

# Regional switching for specific content
./streaming_manager.sh us    # US content (Netflix US)
./streaming_manager.sh hk    # Asia content (faster for Asia)
./streaming_manager.sh jp    # Japan content (anime, etc.)
```

### Troubleshooting Workflow
```bash
1. ./quick_vpn_check.sh                    # Quick diagnosis
2. ./network_connectivity_test.sh quick    # Detailed check
3. ./optimize_ai.sh                        # Fix AI issues
4. ./select_youtube_node.sh                # Fix streaming issues
5. ./network_connectivity_test.sh full     # Final verification
```

---

## 📊 Performance Expectations

### Excellent Performance (🏆)
- **Chinese sites**: 100% accessible, <200ms response
- **International sites**: >90% accessible via proxy
- **AI platforms**: >90% working, <5s response times
- **Streaming**: YouTube loading <3s, smooth playback

### Good Performance (🥈)
- **Chinese sites**: 100% accessible, <500ms response
- **International sites**: >80% accessible via proxy
- **AI platforms**: >70% working, <10s response times
- **Streaming**: YouTube loading <6s, occasional buffering

### Needs Optimization (🔧)
- **Chinese sites**: <100% accessible or >500ms response
- **International sites**: <80% accessible via proxy
- **AI platforms**: <70% working or >10s response times
- **Streaming**: YouTube loading >6s, frequent buffering

---

## 🎯 Best Practices

1. **Run daily quick checks**: `./quick_vpn_check.sh`
2. **Optimize weekly**: Run full optimization scripts
3. **Monitor performance**: Use network connectivity tests
4. **Switch regions as needed**: Use streaming manager for different content
5. **Keep documentation updated**: Refer to this guide for optimal usage

**Happy proxy optimization! 🚀**
