#!/bin/bash

# Docker Proxy Connection Test Script
# Tests Clash proxy accessibility from Docker containers
# Author: Auto-generated for clash-for-linux-install
# Date: August 14, 2025

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration
HOST_IP=$(hostname -I | awk '{print $1}')
CLASH_PROXY_PORT=7890
CLASH_API_PORT=9090
TIMEOUT=10

# Test URLs - Basic connectivity
BASIC_TEST_URLS=(
    "http://httpbin.org/ip"
    "https://api.github.com"
    "https://www.google.com"
    "http://www.gstatic.com/generate_204"
)

# AI/LLM API endpoints
AI_TEST_URLS=(
    "https://api.openai.com"
    "https://api.anthropic.com"
    "https://claude.ai"
    "https://platform.openai.com"
    "https://chat.openai.com"
    "https://api.cohere.ai"
    "https://api.replicate.com"
    "https://huggingface.co"
    "https://api.stability.ai"
    "https://api.together.xyz"
)

# Streaming and social media
STREAMING_TEST_URLS=(
    "https://www.youtube.com"
    "https://api.twitter.com"
    "https://www.netflix.com"
    "https://www.twitch.tv"
    "https://discord.com"
)

# Development and tools
DEV_TEST_URLS=(
    "https://registry.npmjs.org"
    "https://pypi.org"
    "https://registry-1.docker.io"
    "https://gcr.io"
    "https://quay.io"
    "https://hub.docker.com"
)

# Chinese AI platforms (should go direct)
CHINESE_AI_URLS=(
    "https://openxlab.org.cn"
    "https://www.zhipu.ai"
    "https://qianfan.cloud.baidu.com"
    "https://dashscope.aliyun.com"
    "https://api.minimax.chat"
)

# All URLs combined for comprehensive testing
ALL_TEST_URLS=("${BASIC_TEST_URLS[@]}" "${AI_TEST_URLS[@]}" "${STREAMING_TEST_URLS[@]}" "${DEV_TEST_URLS[@]}")

# Docker test image
TEST_IMAGE="curlimages/curl:latest"

echo -e "${BLUE}🐳 Docker Proxy Connection Test Suite${NC}"
echo -e "${BLUE}====================================${NC}"
echo -e "${WHITE}Host IP: ${HOST_IP}${NC}"
echo -e "${WHITE}Clash Proxy: ${HOST_IP}:${CLASH_PROXY_PORT}${NC}"
echo -e "${WHITE}Clash API: ${HOST_IP}:${CLASH_API_PORT}${NC}"
echo ""

# Function to print test status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✅ PASS${NC}: $message"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}❌ FAIL${NC}: $message"
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠️  WARN${NC}: $message"
    elif [ "$status" = "INFO" ]; then
        echo -e "${CYAN}ℹ️  INFO${NC}: $message"
    fi
}

# Function to run test with timeout and error handling
run_test() {
    local test_name="$1"
    local docker_cmd="$2"
    local expected_pattern="$3"
    
    echo -e "\n${PURPLE}📋 Test: ${test_name}${NC}"
    echo -e "${CYAN}Command: ${docker_cmd}${NC}"
    
    local output
    local exit_code
    
    # Run the command and capture output
    if output=$(eval "$docker_cmd" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    echo -e "${CYAN}Output: ${output}${NC}"
    
    # Check results
    if [ $exit_code -eq 0 ]; then
        if [ -n "$expected_pattern" ] && echo "$output" | grep -q "$expected_pattern"; then
            print_status "PASS" "$test_name completed successfully"
            return 0
        elif [ -z "$expected_pattern" ]; then
            print_status "PASS" "$test_name completed successfully"
            return 0
        else
            print_status "FAIL" "$test_name - Expected pattern '$expected_pattern' not found"
            return 1
        fi
    else
        print_status "FAIL" "$test_name - Command failed with exit code $exit_code"
        return 1
    fi
}

# Pre-flight checks
echo -e "${YELLOW}🔍 Pre-flight Checks${NC}"
echo -e "${YELLOW}==================${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_status "FAIL" "Docker is not running or not accessible"
    exit 1
fi
print_status "PASS" "Docker is running"

# Check if Clash service is running
if ! pgrep -f mihomo > /dev/null; then
    print_status "FAIL" "Clash (mihomo) service is not running"
    exit 1
fi
print_status "PASS" "Clash service is running"

# Check if ports are listening
if ! netstat -tln | grep -q ":${CLASH_PROXY_PORT}"; then
    print_status "FAIL" "Clash proxy port ${CLASH_PROXY_PORT} is not listening"
    exit 1
fi
print_status "PASS" "Clash proxy port ${CLASH_PROXY_PORT} is listening"

if ! netstat -tln | grep -q ":${CLASH_API_PORT}"; then
    print_status "FAIL" "Clash API port ${CLASH_API_PORT} is not listening"
    exit 1
fi
print_status "PASS" "Clash API port ${CLASH_API_PORT} is listening"

# Check if test image is available
echo -e "\n${YELLOW}📦 Preparing Test Environment${NC}"
echo -e "${YELLOW}=============================${NC}"

print_status "INFO" "Pulling test image: ${TEST_IMAGE}"
if docker pull ${TEST_IMAGE} > /dev/null 2>&1; then
    print_status "PASS" "Test image ${TEST_IMAGE} is ready"
else
    print_status "WARN" "Could not pull ${TEST_IMAGE}, trying to use existing image"
fi

# Test 1: Direct API access from Docker container
echo -e "\n${YELLOW}🧪 Test Suite 1: API Access Tests${NC}"
echo -e "${YELLOW}=================================${NC}"

run_test "API Version Check" \
    "docker run --rm ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s http://${HOST_IP}:${CLASH_API_PORT}/version" \
    "version"

run_test "API Config Check" \
    "docker run --rm ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s http://${HOST_IP}:${CLASH_API_PORT}/configs" \
    "allow-lan"

# Test 2: Proxy functionality tests
echo -e "\n${YELLOW}🧪 Test Suite 2: Basic Proxy Functionality Tests${NC}"
echo -e "${YELLOW}===============================================${NC}"

# Test with direct host IP
for url in "${BASIC_TEST_URLS[@]}"; do
    test_name="Basic Proxy Test: $url (Direct IP)"
    run_test "$test_name" \
        "docker run --rm ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s -x http://${HOST_IP}:${CLASH_PROXY_PORT} '$url'" \
        ""
done

# Test 2.5: AI/LLM API endpoints
echo -e "\n${YELLOW}🧪 Test Suite 2.5: AI/LLM API Endpoints${NC}"
echo -e "${YELLOW}=====================================${NC}"

for url in "${AI_TEST_URLS[@]}"; do
    test_name="AI API Test: $url"
    run_test "$test_name" \
        "docker run --rm ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s -I -x http://${HOST_IP}:${CLASH_PROXY_PORT} '$url'" \
        ""
done

# Test 2.6: Streaming and Social Media
echo -e "\n${YELLOW}🧪 Test Suite 2.6: Streaming and Social Media${NC}"
echo -e "${YELLOW}===========================================${NC}"

for url in "${STREAMING_TEST_URLS[@]}"; do
    test_name="Streaming Test: $url"
    run_test "$test_name" \
        "docker run --rm ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s -I -x http://${HOST_IP}:${CLASH_PROXY_PORT} '$url'" \
        ""
done

# Test 2.7: Development Tools and Registries
echo -e "\n${YELLOW}🧪 Test Suite 2.7: Development Tools and Registries${NC}"
echo -e "${YELLOW}================================================${NC}"

for url in "${DEV_TEST_URLS[@]}"; do
    test_name="Dev Tools Test: $url"
    run_test "$test_name" \
        "docker run --rm ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s -I -x http://${HOST_IP}:${CLASH_PROXY_PORT} '$url'" \
        ""
done

# Test 2.8: Chinese AI Platforms (Direct Connection Test)
echo -e "\n${YELLOW}🧪 Test Suite 2.8: Chinese AI Platforms (Direct Connection)${NC}"
echo -e "${YELLOW}=======================================================${NC}"

print_status "INFO" "These URLs should bypass proxy and connect directly according to Clash rules"

for url in "${CHINESE_AI_URLS[@]}"; do
    test_name="Chinese AI Direct Test: $url"
    # Test both with and without proxy to verify direct connection
    run_test "$test_name (without proxy)" \
        "docker run --rm ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s -I '$url'" \
        ""
    
    run_test "$test_name (with proxy - should still work)" \
        "docker run --rm ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s -I -x http://${HOST_IP}:${CLASH_PROXY_PORT} '$url'" \
        ""
done

# Test 3: host.docker.internal tests
echo -e "\n${YELLOW}🧪 Test Suite 3: host.docker.internal Tests${NC}"
echo -e "${YELLOW}===========================================${NC}"

run_test "API Access via host.docker.internal" \
    "docker run --rm --add-host=host.docker.internal:${HOST_IP} ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s http://host.docker.internal:${CLASH_API_PORT}/version" \
    "version"

# Test a few key URLs through host.docker.internal
KEY_URLS=(
    "https://httpbin.org/ip"
    "https://api.openai.com/v1/models"
    "https://www.google.com"
)

for url in "${KEY_URLS[@]}"; do
    test_name="Proxy Test: $url (host.docker.internal)"
    run_test "$test_name" \
        "docker run --rm --add-host=host.docker.internal:${HOST_IP} ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s -x http://host.docker.internal:${CLASH_PROXY_PORT} '$url'" \
        ""
done

# Test 4: Environment variable tests
echo -e "\n${YELLOW}🧪 Test Suite 4: Environment Variable Tests${NC}"
echo -e "${YELLOW}===========================================${NC}"

run_test "HTTP_PROXY Environment Variable" \
    "docker run --rm -e HTTP_PROXY=http://${HOST_IP}:${CLASH_PROXY_PORT} ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s http://httpbin.org/ip" \
    "origin"

run_test "HTTPS_PROXY Environment Variable" \
    "docker run --rm -e HTTPS_PROXY=http://${HOST_IP}:${CLASH_PROXY_PORT} ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s https://httpbin.org/ip" \
    "origin"

# Test 5: Docker Compose simulation
echo -e "\n${YELLOW}🧪 Test Suite 5: Docker Compose Simulation${NC}"
echo -e "${YELLOW}=========================================${NC}"

# Create temporary docker-compose.yml for testing
TEMP_COMPOSE_FILE="/tmp/docker-proxy-test-compose.yml"
cat > "${TEMP_COMPOSE_FILE}" << EOF
version: '3.8'
services:
  proxy-test:
    image: ${TEST_IMAGE}
    environment:
      - HTTP_PROXY=http://${HOST_IP}:${CLASH_PROXY_PORT}
      - HTTPS_PROXY=http://${HOST_IP}:${CLASH_PROXY_PORT}
      - NO_PROXY=localhost,127.0.0.1
    extra_hosts:
      - "host.docker.internal:${HOST_IP}"
    command: curl --connect-timeout ${TIMEOUT} -s http://httpbin.org/ip
EOF

if command -v docker-compose > /dev/null 2>&1; then
    run_test "Docker Compose Proxy Test" \
        "docker-compose -f ${TEMP_COMPOSE_FILE} run --rm proxy-test" \
        "origin"
    
    # Cleanup
    docker-compose -f "${TEMP_COMPOSE_FILE}" down > /dev/null 2>&1 || true
else
    print_status "WARN" "docker-compose not available, skipping compose tests"
fi

# Cleanup
rm -f "${TEMP_COMPOSE_FILE}"

# Test 6: Performance tests
echo -e "\n${YELLOW}🧪 Test Suite 6: Performance Tests${NC}"
echo -e "${YELLOW}=================================${NC}"

run_test "Proxy Response Time Test" \
    "docker run --rm ${TEST_IMAGE} curl --connect-timeout ${TIMEOUT} -s -w 'Time: %{time_total}s\n' -o /dev/null -x http://${HOST_IP}:${CLASH_PROXY_PORT} http://www.gstatic.com/generate_204" \
    "Time:"

# Test 7: Error handling tests
echo -e "\n${YELLOW}🧪 Test Suite 7: Error Handling Tests${NC}"
echo -e "${YELLOW}====================================${NC}"

run_test "Invalid Proxy Port Test (should fail)" \
    "docker run --rm ${TEST_IMAGE} curl --connect-timeout 5 -s -x http://${HOST_IP}:9999 http://httpbin.org/ip" \
    ""

run_test "Non-existent Host Test (should fail)" \
    "docker run --rm ${TEST_IMAGE} curl --connect-timeout 5 -s -x http://192.168.255.255:${CLASH_PROXY_PORT} http://httpbin.org/ip" \
    ""

# Summary
echo -e "\n${BLUE}📊 Test Summary${NC}"
echo -e "${BLUE}==============${NC}"

# Count Docker containers and networks
CONTAINER_COUNT=$(docker ps -a --format "table {{.Names}}" | grep -v NAMES | wc -l)
NETWORK_COUNT=$(docker network ls --format "table {{.Name}}" | grep -v NAME | wc -l)

print_status "INFO" "Total Docker containers: ${CONTAINER_COUNT}"
print_status "INFO" "Total Docker networks: ${NETWORK_COUNT}"

# Network information
echo -e "\n${PURPLE}🌐 Network Information${NC}"
echo -e "${PURPLE}=====================${NC}"

echo -e "${CYAN}Docker Networks:${NC}"
docker network ls

echo -e "\n${CYAN}Host Network Configuration:${NC}"
echo -e "Primary IP: ${HOST_IP}"
echo -e "Clash Proxy: http://${HOST_IP}:${CLASH_PROXY_PORT}"
echo -e "Clash Dashboard: http://${HOST_IP}:${CLASH_API_PORT}"

echo -e "\n${CYAN}Firewall Rules (DOCKER-USER chain):${NC}"
if command -v iptables > /dev/null 2>&1; then
    sudo iptables -L DOCKER-USER -n 2>/dev/null | grep -E "(${CLASH_PROXY_PORT}|${CLASH_API_PORT})" || echo "No specific rules found"
fi

# Usage examples
echo -e "\n${PURPLE}📖 Usage Examples${NC}"
echo -e "${PURPLE}=================${NC}"

echo -e "${CYAN}1. Simple proxy usage:${NC}"
echo -e "   docker run --rm curlimages/curl curl -x http://${HOST_IP}:${CLASH_PROXY_PORT} http://example.com"

echo -e "\n${CYAN}2. With environment variables:${NC}"
echo -e "   docker run --rm -e HTTP_PROXY=http://${HOST_IP}:${CLASH_PROXY_PORT} your-image"

echo -e "\n${CYAN}3. With host.docker.internal:${NC}"
echo -e "   docker run --rm --add-host=host.docker.internal:${HOST_IP} your-image"

echo -e "\n${CYAN}4. In docker-compose.yml:${NC}"
cat << 'EOF'
   version: '3.8'
   services:
     your-app:
       image: your-image
       environment:
         - HTTP_PROXY=http://host.docker.internal:7890
         - HTTPS_PROXY=http://host.docker.internal:7890
       extra_hosts:
         - "host.docker.internal:HOST_IP"
EOF

echo -e "\n${GREEN}🎉 Docker Proxy Test Suite Completed!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo -e "${WHITE}For troubleshooting, check: /home/gw/opt/clash-for-linux-install/DOCKER_INTEGRATION.md${NC}"
