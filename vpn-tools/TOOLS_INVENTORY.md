# VPN Tools Inventory

## 🐳 Docker Integration Tools

### test_docker_proxy.sh
**Purpose**: Comprehensive test suite for Docker container proxy connectivity  
**Usage**: `./test_docker_proxy.sh`  
**Features**:
- Pre-flight checks (Docker, Clash service, ports)
- API access verification from containers
- Proxy functionality testing with multiple URLs
- host.docker.internal compatibility testing
- Environment variable proxy testing
- Docker Compose simulation
- Performance and error handling tests
- Detailed network information and usage examples

**Test Coverage**:
- ✅ Docker service status
- ✅ Clash service status and port availability
- ✅ API endpoint accessibility
- ✅ Proxy functionality with real websites
- ✅ Multiple connection methods (direct IP, host.docker.internal)
- ✅ Environment variable configuration
- ✅ Docker Compose compatibility
- ✅ Performance metrics
- ✅ Error scenarios

## 🔧 Service Management Tools

### restart_clash_service.sh
**Purpose**: Restart Clash/Mihomo service with configuration validation  
**Usage**: `./restart_clash_service.sh`  
**Features**:
- Configuration backup before restart
- Service status verification
- OpenXLab and AI connectivity testing
- Configuration validation

## 🌐 Network Testing Tools

### network_connectivity_test.sh
**Purpose**: Test network connectivity and proxy routing
**Usage**: `./network_connectivity_test.sh`

### quick_vpn_check.sh
**Purpose**: Quick VPN status and connectivity check
**Usage**: `./quick_vpn_check.sh`

## 🤖 AI Platform Tools

### optimize_ai.sh
**Purpose**: Optimize proxy settings for AI platforms
**Usage**: `./optimize_ai.sh`

### test_ai_connectivity.sh
**Purpose**: Test connectivity to various AI platforms
**Usage**: `./test_ai_connectivity.sh`

### quick_ai_test.sh
**Purpose**: Quick test of AI platform accessibility
**Usage**: `./quick_ai_test.sh`

### test_chinese_ai_platforms.sh
**Purpose**: Test Chinese AI platforms (OpenXLab, etc.)
**Usage**: `./test_chinese_ai_platforms.sh`

### quick_openxlab_access.sh
**Purpose**: Quick OpenXLab connectivity test
**Usage**: `./quick_openxlab_access.sh`

## 🎬 Streaming Tools

### streaming_manager.sh
**Purpose**: Manage streaming service proxy settings
**Usage**: `./streaming_manager.sh`

### optimize_youtube_streaming.sh
**Purpose**: Optimize proxy for YouTube streaming
**Usage**: `./optimize_youtube_streaming.sh`

### quick_streaming_test.sh
**Purpose**: Quick streaming service connectivity test
**Usage**: `./quick_streaming_test.sh`

### select_youtube_node.sh
**Purpose**: Select optimal node for YouTube
**Usage**: `./select_youtube_node.sh`

## 📊 Monitoring Tools

### show_vpn_status.sh
**Purpose**: Display comprehensive VPN status
**Usage**: `./show_vpn_status.sh`

### proxy_connectivity_report.sh
**Purpose**: Generate detailed connectivity report
**Usage**: `./proxy_connectivity_report.sh`

## 🔧 Utility Tools

### launcher.sh
**Purpose**: Main launcher for VPN tools
**Usage**: `./launcher.sh`

### show_help.sh
**Purpose**: Display help information
**Usage**: `./show_help.sh`

### customize_ai_group.sh
**Purpose**: Customize AI proxy groups
**Usage**: `./customize_ai_group.sh`

### fix_openxlab_connectivity.sh
**Purpose**: Fix OpenXLab connectivity issues
**Usage**: `./fix_openxlab_connectivity.sh`

---

## 📋 Quick Reference

### Docker Proxy Testing
```bash
# Full test suite
./test_docker_proxy.sh

# Quick verification
docker run --rm curlimages/curl curl -x http://$(hostname -I | awk '{print $1}'):7890 http://httpbin.org/ip
```

### Service Management
```bash
# Restart Clash with validation
./restart_clash_service.sh

# Check VPN status
./show_vpn_status.sh
```

### AI Platform Testing
```bash
# Test all AI platforms
./test_ai_connectivity.sh

# Quick OpenXLab test
./quick_openxlab_access.sh
```

### Streaming Testing
```bash
# Test streaming services
./quick_streaming_test.sh

# Optimize for YouTube
./optimize_youtube_streaming.sh
```

---

**Last Updated**: August 14, 2025  
**Docker Integration**: ✅ Fully Supported  
**Total Tools**: 20+ scripts for comprehensive VPN management