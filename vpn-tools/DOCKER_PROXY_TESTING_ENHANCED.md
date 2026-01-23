# Enhanced Docker Proxy Testing for AI/LLM Services

## Overview
The Docker proxy test suite has been significantly enhanced to provide comprehensive testing of proxy connectivity for AI/LLM services and other critical endpoints.

## Enhanced Test Categories

### 🤖 AI/LLM API Endpoints
Tests connectivity to major AI and machine learning platforms:
- **OpenAI**: `https://api.openai.com`
- **Anthropic**: `https://api.anthropic.com/v1/complete`
- **Claude**: `https://claude.ai`
- **Cohere**: `https://api.cohere.ai`
- **Replicate**: `https://api.replicate.com`
- **Hugging Face**: `https://huggingface.co/api/models`
- **Google AI**: `https://ai.google.dev`
- **Perplexity**: `https://api.perplexity.ai`

### 🎬 Streaming and Social Media
Tests access to popular streaming and social platforms:
- **YouTube**: `https://www.youtube.com`
- **Netflix**: `https://www.netflix.com`
- **Twitch**: `https://www.twitch.tv`
- **Discord**: `https://discord.com`
- **Reddit**: `https://www.reddit.com`
- **Twitter/X**: `https://x.com`

### 🛠️ Development Tools and Registries
Tests connectivity to development resources:
- **npm Registry**: `https://registry.npmjs.org`
- **PyPI**: `https://pypi.org`
- **Docker Hub**: `https://registry-1.docker.io`
- **GitHub Container Registry**: `https://ghcr.io`
- **Maven Central**: `https://repo1.maven.org`
- **Homebrew**: `https://formulae.brew.sh`

### 🇨🇳 Chinese AI Platforms (Direct Connection Testing)
Tests both proxy and direct connections for Chinese services:
- **OpenXLab**: `https://openxlab.org.cn`
- **Zhipu AI**: `https://open.bigmodel.cn`
- **Baidu AI**: `https://aip.baidubce.com`
- **Alibaba Cloud**: `https://ecs.console.aliyun.com`

## Usage

### Run Full Test Suite
```bash
cd /path/to/clash-for-linux-install/vpn-tools

# Recommended on Linux (works with secure localhost-only controller)
DOCKER_NET_MODE=host ./test_docker_proxy.sh

# Alternative: bridged networking (requires controller/proxy to listen on non-loopback)
DOCKER_NET_MODE=bridge ./test_docker_proxy.sh
```

### Focus on Specific Test Categories
```bash
# Just AI/LLM endpoints
./test_docker_proxy.sh 2>&1 | grep -A 20 "AI/LLM API Endpoints"

# Just streaming services
./test_docker_proxy.sh 2>&1 | grep -A 20 "Streaming and Social Media"

# Just development tools
./test_docker_proxy.sh 2>&1 | grep -A 20 "Development Tools"
```

## Test Results Summary

### ✅ Successfully Working
- **OpenAI API**: Proxy connection established successfully
- **YouTube**: Streaming proxy access confirmed
- **npm Registry**: Development tool access verified
- **GitHub API**: Development platform connectivity confirmed
- **Basic HTTP/HTTPS**: All fundamental proxy functions working

### 🔍 Test Features
- **Categorized Testing**: Organized by service type for better diagnostics
- **Dual Testing for Chinese Sites**: Both proxy and direct connection validation
- **Comprehensive Coverage**: Over 25 different service endpoints
- **Docker Integration**: All tests run within Docker containers
- **Multiple Connection Methods**: Direct IP, host.docker.internal, environment variables

## Configuration Requirements

### Clash Configuration
The following settings must be enabled in your Clash configuration:
```yaml
mixed-port: 7890
# Security default: keep the controller on localhost.
external-controller: "127.0.0.1:9090"
```

On Linux, the easiest secure way to let Docker reach the host proxy/controller is to run the test container with host networking (no need to expose `0.0.0.0`):

- Prefer: Docker `--network host`
- Only if you *must* access from bridged networks: expose to `0.0.0.0` **and** set a controller `secret` + firewall rules.

### Automatic Port Detection & Overrides

The test script reads `~/.local/share/clash/runtime.yaml` (falling back to `config.yaml`/`mixin.yaml`) to auto-detect the actual `mixed-port` and `external-controller` values. This means you no longer need to hardcode 7890/9090—as long as the Clash service is running with LAN access, the script will discover the correct ports.

If you need to override the detected ports (for example, when running against a remote host), export the environment variables before executing the test suite:

```bash
CLASH_PROXY_PORT=7891 CLASH_API_PORT=9900 ./test_docker_proxy.sh
```

### Firewall Rules
Ensure Docker containers can access Clash:
```bash
# Allow Docker networks to access Clash ports
sudo iptables -I DOCKER-USER -s 172.16.0.0/12 -d <HOST_IP> -p tcp --dport 7890 -j ACCEPT
sudo iptables -I DOCKER-USER -s 172.16.0.0/12 -d <HOST_IP> -p tcp --dport 9090 -j ACCEPT
```

## Troubleshooting

### Common Issues
1. **Connection Refused (bridge mode)**: If your controller/proxy is bound to `127.0.0.1`, containers in bridged mode cannot reach it. Prefer `DOCKER_NET_MODE=host`.
2. **Timeout Errors**: Verify firewall rules allow Docker-to-host communication
3. **API Errors (401 Unauthorized)**: If `runtime.yaml` has `secret`, API calls must include `Authorization: Bearer <secret>` (the test script handles this automatically).

### Debug Commands
```bash
# Check port bindings
ss -tln | grep -E ":(7890|9090)"

# Test API access from container (Linux host networking)
docker run --rm --network host curlimages/curl:latest \
	curl -s http://127.0.0.1:9090/version

# If controller secret is enabled, add:
#   -H "Authorization: Bearer <CLASH_SECRET>"

# Test proxy connectivity (Linux host networking)
docker run --rm --network host curlimages/curl:latest \
	curl -s -x http://127.0.0.1:7890 http://httpbin.org/ip

# Bridged mode examples (replace <HOST_IP> with your host LAN IP)
docker run --rm curlimages/curl:latest \
	curl -s http://<HOST_IP>:9090/version
docker run --rm curlimages/curl:latest \
	curl -s -x http://<HOST_IP>:7890 http://httpbin.org/ip
```

## Performance Notes
- **AI API Tests**: Use HEAD requests to minimize data transfer
- **Streaming Tests**: Connection verification only, no content download
- **Chinese Services**: Dual testing may take longer due to network conditions
- **Total Runtime**: Approximately 3-5 minutes for full test suite

## Security Considerations
- Tests use public endpoints only
- No authentication credentials required
- All tests are read-only operations
- Container isolation maintained throughout testing

## Next Steps
1. Monitor test results for any service-specific issues
2. Add authentication testing for AI APIs (if needed)
3. Consider automated scheduled testing
4. Expand coverage for additional AI/ML platforms as they emerge
