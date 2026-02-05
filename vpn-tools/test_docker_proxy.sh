#!/bin/bash

# Docker Proxy Connection Test Script
# Tests Clash proxy accessibility from Docker containers
# Author: Auto-generated for clash-for-linux-install
# Date: August 14, 2025

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load optional .env and controller/secret auto-detection helpers
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true

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
TIMEOUT=10

# Docker network mode:
# - host: recommended on Linux; allows accessing controller bound to 127.0.0.1 safely
# - bridge: requires the controller/proxy to listen on a non-loopback address (e.g., allow-lan + bind 0.0.0.0)
: "${DOCKER_NET_MODE:=host}"

DEFAULT_PROXY_PORT=7890
DEFAULT_API_PORT=9090
CLASH_DATA_DIR="${HOME}/.local/share/clash"
RUNTIME_FILE="${CLASH_DATA_DIR}/runtime.yaml"
BASE_CONFIG_FILE="${CLASH_DATA_DIR}/config.yaml"
MIXIN_FILE="${CLASH_DATA_DIR}/mixin.yaml"
CONFIG_CANDIDATES=("${RUNTIME_FILE}" "${BASE_CONFIG_FILE}" "${MIXIN_FILE}")

read_yaml_value() {
    local key="$1"
    local file="$2"

    [ -f "$file" ] || return 1

    local line
    if ! line=$(grep -m1 -E "^[[:space:]]*${key}:" "$file" 2>/dev/null); then
        return 1
    fi

    line=${line#*:}
    line=${line//\"/}
    line=${line//$'\''/}
    echo "$line" | xargs
}

detect_port_from_config() {
    local key="$1"
    local fallback="$2"
    local value

    for file in "${CONFIG_CANDIDATES[@]}"; do
        value=$(read_yaml_value "$key" "$file") || continue
        if [[ "$value" =~ ([0-9]{2,5})$ ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    done

    echo "$fallback"
}

: "${CLASH_PROXY_PORT:=$(detect_port_from_config "mixed-port" "$(detect_port_from_config "port" "$DEFAULT_PROXY_PORT")")}"
: "${CLASH_API_PORT:=$(detect_port_from_config "external-controller" "$DEFAULT_API_PORT")}"

# If load_env.sh populated CLASH_API (e.g., http://127.0.0.1:9090), prefer its port.
if [[ -n "${CLASH_API:-}" ]]; then
    api_hostport="${CLASH_API#http://}"
    api_hostport="${api_hostport#https://}"
    api_hostport="${api_hostport%%/*}"
    if [[ "$api_hostport" == *:* ]]; then
        api_port="${api_hostport##*:}"
        if [[ "$api_port" =~ ^[0-9]{2,5}$ ]]; then
            CLASH_API_PORT="$api_port"
        fi
    fi
fi

DOCKER_RUN_NET_ARGS=()
DOCKER_ADD_HOST_ARGS=()
DOCKER_ENV_SECRET_ARGS=()
TARGET_HOST="${HOST_IP}"

case "${DOCKER_NET_MODE}" in
    host)
        DOCKER_RUN_NET_ARGS=(--network host)
        TARGET_HOST="127.0.0.1"
        ;;
    bridge)
        DOCKER_ADD_HOST_ARGS=(--add-host="host.docker.internal:${HOST_IP}")
        TARGET_HOST="${HOST_IP}"
        ;;
    *)
        echo -e "${RED}Invalid DOCKER_NET_MODE: ${DOCKER_NET_MODE} (expected: host|bridge)${NC}" >&2
        exit 2
        ;;
esac

if [[ "${DOCKER_NET_MODE}" == "bridge" && -n "${CLASH_API:-}" ]]; then
    if [[ "${CLASH_API}" == http://127.0.0.1:* || "${CLASH_API}" == https://127.0.0.1:* || "${CLASH_API}" == http://localhost:* || "${CLASH_API}" == https://localhost:* ]]; then
        echo -e "${YELLOW}⚠️  WARN${NC}: CLASH_API points to localhost (${CLASH_API}); bridge mode containers may NOT reach it. Consider DOCKER_NET_MODE=host." >&2
    fi
fi

# If CLASH_SECRET is set, pass it into the container without echoing its value.
if [[ -n "${CLASH_SECRET:-}" ]]; then
    DOCKER_ENV_SECRET_ARGS=(-e CLASH_SECRET)
fi

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
echo -e "${WHITE}Docker net mode: ${DOCKER_NET_MODE}${NC}"
echo -e "${WHITE}Proxy target: ${TARGET_HOST}:${CLASH_PROXY_PORT}${NC}"
echo -e "${WHITE}API target: ${TARGET_HOST}:${CLASH_API_PORT}${NC}"
if [[ -n "${CLASH_SECRET:-}" ]]; then
    echo -e "${WHITE}Controller auth: enabled (secret loaded)${NC}"
else
    echo -e "${WHITE}Controller auth: none (secret not set)${NC}"
fi
echo ""

redact_sensitive() {
    # Best-effort redaction for logs (commands + outputs).
    # Do not ever print secrets verbatim.
    local s="$1"
    if [[ -n "${CLASH_SECRET:-}" ]]; then
        s=${s//${CLASH_SECRET}/***REDACTED***}
    fi
    s=$(echo "$s" | sed -E \
        -e 's/(Authorization:[[:space:]]*Bearer[[:space:]]+)[^"[:space:]]+/\1***REDACTED***/g' \
        -e 's/([?&](token|apikey|api_key|key|secret)=)[^& ]+/\1***REDACTED***/gI')
    echo "$s"
}

format_cmd() {
    # Format argv as a printable shell-ish command (best-effort).
    local out="" a
    for a in "$@"; do
        out+="$(printf '%q ' "$a")"
    done
    out=${out% }
    printf '%s' "$out"
}

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
    local expected_pattern="$2"
    local expect_rc="${3:-0}"
    shift 3
    local -a cmd=("$@")
    
    echo -e "\n${PURPLE}📋 Test: ${test_name}${NC}"
    echo -e "${CYAN}Command: $(redact_sensitive "$(format_cmd "${cmd[@]}")")${NC}"
    
    local output
    local exit_code
    
    # Run the command and capture output
    set +e
    output=$("${cmd[@]}" 2>&1)
    exit_code=$?
    set -e
    
    echo -e "${CYAN}Output: $(redact_sensitive "${output}")${NC}"
    
    # Check results
    if [ $exit_code -eq $expect_rc ]; then
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
        if [ $expect_rc -ne 0 ]; then
            print_status "FAIL" "$test_name - Command returned $exit_code (expected $expect_rc)"
        else
            print_status "FAIL" "$test_name - Command failed with exit code $exit_code"
        fi
        return 1
    fi
}

run_test_expect_fail() {
    # Expect a non-zero exit (any non-zero counts as pass).
    local test_name="$1"; shift
    echo -e "\n${PURPLE}📋 Test: ${test_name}${NC}"
    echo -e "${CYAN}Command: $(redact_sensitive "$(format_cmd "$@")")${NC}"

    local output exit_code
    set +e
    output=$("$@" 2>&1)
    exit_code=$?
    set -e

    echo -e "${CYAN}Output: $(redact_sensitive "${output}")${NC}"
    if [ $exit_code -ne 0 ]; then
        print_status "PASS" "$test_name failed as expected (exit=$exit_code)"
        return 0
    fi
    print_status "FAIL" "$test_name unexpectedly succeeded"
    return 1
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
is_port_listening() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
        return $?
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -tln 2>/dev/null | grep -q ":${port}"
        return $?
    fi
    return 1
}

if ! is_port_listening "${CLASH_PROXY_PORT}"; then
    print_status "FAIL" "Clash proxy port ${CLASH_PROXY_PORT} is not listening"
    exit 1
fi
print_status "PASS" "Clash proxy port ${CLASH_PROXY_PORT} is listening"

if ! is_port_listening "${CLASH_API_PORT}"; then
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
    "version" 0 \
    docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" "${DOCKER_ENV_SECRET_ARGS[@]}" "${TEST_IMAGE}" sh -c "if [ -n \"\${CLASH_SECRET:-}\" ]; then curl --connect-timeout ${TIMEOUT} -s -H \"Authorization: Bearer \$CLASH_SECRET\" http://${TARGET_HOST}:${CLASH_API_PORT}/version; else curl --connect-timeout ${TIMEOUT} -s http://${TARGET_HOST}:${CLASH_API_PORT}/version; fi"

run_test "API Config Check" \
    "allow-lan" 0 \
    docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" "${DOCKER_ENV_SECRET_ARGS[@]}" "${TEST_IMAGE}" sh -c "if [ -n \"\${CLASH_SECRET:-}\" ]; then curl --connect-timeout ${TIMEOUT} -s -H \"Authorization: Bearer \$CLASH_SECRET\" http://${TARGET_HOST}:${CLASH_API_PORT}/configs; else curl --connect-timeout ${TIMEOUT} -s http://${TARGET_HOST}:${CLASH_API_PORT}/configs; fi"

# Test 2: Proxy functionality tests
echo -e "\n${YELLOW}🧪 Test Suite 2: Basic Proxy Functionality Tests${NC}"
echo -e "${YELLOW}===============================================${NC}"

# Test with direct host IP
for url in "${BASIC_TEST_URLS[@]}"; do
    test_name="Basic Proxy Test: $url (Direct IP)"
    run_test "$test_name" \
    "" 0 \
    docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" "${TEST_IMAGE}" curl --connect-timeout "${TIMEOUT}" -s -x "http://${TARGET_HOST}:${CLASH_PROXY_PORT}" "$url"
done

# Test 2.5: AI/LLM API endpoints
echo -e "\n${YELLOW}🧪 Test Suite 2.5: AI/LLM API Endpoints${NC}"
echo -e "${YELLOW}=====================================${NC}"

for url in "${AI_TEST_URLS[@]}"; do
    test_name="AI API Test: $url"
    run_test "$test_name" \
    "" 0 \
    docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" "${TEST_IMAGE}" curl --connect-timeout "${TIMEOUT}" -s -I -x "http://${TARGET_HOST}:${CLASH_PROXY_PORT}" "$url"
done

# Test 2.6: Streaming and Social Media
echo -e "\n${YELLOW}🧪 Test Suite 2.6: Streaming and Social Media${NC}"
echo -e "${YELLOW}===========================================${NC}"

for url in "${STREAMING_TEST_URLS[@]}"; do
    test_name="Streaming Test: $url"
    run_test "$test_name" \
    "" 0 \
    docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" "${TEST_IMAGE}" curl --connect-timeout "${TIMEOUT}" -s -I -x "http://${TARGET_HOST}:${CLASH_PROXY_PORT}" "$url"
done

# Test 2.7: Development Tools and Registries
echo -e "\n${YELLOW}🧪 Test Suite 2.7: Development Tools and Registries${NC}"
echo -e "${YELLOW}================================================${NC}"

for url in "${DEV_TEST_URLS[@]}"; do
    test_name="Dev Tools Test: $url"
    run_test "$test_name" \
    "" 0 \
    docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" "${TEST_IMAGE}" curl --connect-timeout "${TIMEOUT}" -s -I -x "http://${TARGET_HOST}:${CLASH_PROXY_PORT}" "$url"
done

# Test 2.8: Chinese AI Platforms (Direct Connection Test)
echo -e "\n${YELLOW}🧪 Test Suite 2.8: Chinese AI Platforms (Direct Connection)${NC}"
echo -e "${YELLOW}=======================================================${NC}"

print_status "INFO" "These URLs should bypass proxy and connect directly according to Clash rules"

for url in "${CHINESE_AI_URLS[@]}"; do
    test_name="Chinese AI Direct Test: $url"
    # Test both with and without proxy to verify direct connection
    run_test "$test_name (without proxy)" \
        "" 0 \
        docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" "${TEST_IMAGE}" curl --connect-timeout "${TIMEOUT}" -s -I "$url"
    
    run_test "$test_name (with proxy - should still work)" \
        "" 0 \
        docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" "${TEST_IMAGE}" curl --connect-timeout "${TIMEOUT}" -s -I -x "http://${TARGET_HOST}:${CLASH_PROXY_PORT}" "$url"
done

# Test 3: host.docker.internal tests (bridge mode only)
echo -e "\n${YELLOW}🧪 Test Suite 3: host.docker.internal Tests${NC}"
echo -e "${YELLOW}===========================================${NC}"

if [[ "${DOCKER_NET_MODE}" == "bridge" ]]; then
    run_test "API Access via host.docker.internal" \
        "version" 0 \
        docker run --rm "${DOCKER_ADD_HOST_ARGS[@]}" "${DOCKER_ENV_SECRET_ARGS[@]}" "${TEST_IMAGE}" sh -c "if [ -n \"\${CLASH_SECRET:-}\" ]; then curl --connect-timeout ${TIMEOUT} -s -H \"Authorization: Bearer \$CLASH_SECRET\" http://host.docker.internal:${CLASH_API_PORT}/version; else curl --connect-timeout ${TIMEOUT} -s http://host.docker.internal:${CLASH_API_PORT}/version; fi"

    # Test a few key URLs through host.docker.internal
    KEY_URLS=(
        "https://httpbin.org/ip"
        "https://api.openai.com/v1/models"
        "https://www.google.com"
    )

    for url in "${KEY_URLS[@]}"; do
        test_name="Proxy Test: $url (host.docker.internal)"
        run_test "$test_name" \
            "" 0 \
            docker run --rm "${DOCKER_ADD_HOST_ARGS[@]}" "${TEST_IMAGE}" curl --connect-timeout "${TIMEOUT}" -s -x "http://host.docker.internal:${CLASH_PROXY_PORT}" "$url"
    done
else
    print_status "INFO" "Skipping host.docker.internal tests (DOCKER_NET_MODE=host)"
fi

# Test 4: Environment variable tests
echo -e "\n${YELLOW}🧪 Test Suite 4: Environment Variable Tests${NC}"
echo -e "${YELLOW}===========================================${NC}"

run_test "HTTP_PROXY Environment Variable" \
    "origin" 0 \
    docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" -e "HTTP_PROXY=http://${TARGET_HOST}:${CLASH_PROXY_PORT}" "${TEST_IMAGE}" curl --connect-timeout "${TIMEOUT}" -s http://httpbin.org/ip

run_test "HTTPS_PROXY Environment Variable" \
    "origin" 0 \
    docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" -e "HTTPS_PROXY=http://${TARGET_HOST}:${CLASH_PROXY_PORT}" "${TEST_IMAGE}" curl --connect-timeout "${TIMEOUT}" -s https://httpbin.org/ip

# Test 5: Docker Compose simulation
echo -e "\n${YELLOW}🧪 Test Suite 5: Docker Compose Simulation${NC}"
echo -e "${YELLOW}=========================================${NC}"

# Create temporary docker-compose.yml for testing
TEMP_COMPOSE_FILE="/tmp/docker-proxy-test-compose.yml"
if [[ "${DOCKER_NET_MODE}" == "host" ]]; then
        cat > "${TEMP_COMPOSE_FILE}" << EOF
version: '3.8'
services:
    proxy-test:
        image: ${TEST_IMAGE}
        network_mode: host
        environment:
            - HTTP_PROXY=http://${TARGET_HOST}:${CLASH_PROXY_PORT}
            - HTTPS_PROXY=http://${TARGET_HOST}:${CLASH_PROXY_PORT}
            - NO_PROXY=localhost,127.0.0.1
        command: curl --connect-timeout ${TIMEOUT} -s http://httpbin.org/ip
EOF
else
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
fi

if command -v docker-compose > /dev/null 2>&1; then
    run_test "Docker Compose Proxy Test" \
        "origin" 0 \
        docker-compose -f "${TEMP_COMPOSE_FILE}" run --rm proxy-test
    
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
    "Time:" 0 \
    docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" "${TEST_IMAGE}" curl --connect-timeout "${TIMEOUT}" -s -w "Time: %{time_total}s\\n" -o /dev/null -x "http://${TARGET_HOST}:${CLASH_PROXY_PORT}" http://www.gstatic.com/generate_204

# Test 7: Error handling tests
echo -e "\n${YELLOW}🧪 Test Suite 7: Error Handling Tests${NC}"
echo -e "${YELLOW}====================================${NC}"

run_test_expect_fail "Invalid Proxy Port Test (should fail)" \
    docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" "${TEST_IMAGE}" curl --connect-timeout 5 -s -x "http://${TARGET_HOST}:9999" http://httpbin.org/ip

run_test_expect_fail "Non-existent Host Test (should fail)" \
    docker run --rm "${DOCKER_RUN_NET_ARGS[@]}" "${TEST_IMAGE}" curl --connect-timeout 5 -s -x "http://192.168.255.255:${CLASH_PROXY_PORT}" http://httpbin.org/ip

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
if [[ ${#DOCKER_RUN_NET_ARGS[@]} -gt 0 ]]; then
    echo -e "   docker run --rm $(format_cmd "${DOCKER_RUN_NET_ARGS[@]}") curlimages/curl curl -x http://${TARGET_HOST}:${CLASH_PROXY_PORT} http://example.com"
else
    echo -e "   docker run --rm curlimages/curl curl -x http://${TARGET_HOST}:${CLASH_PROXY_PORT} http://example.com"
fi

echo -e "\n${CYAN}2. With environment variables:${NC}"
if [[ ${#DOCKER_RUN_NET_ARGS[@]} -gt 0 ]]; then
    echo -e "   docker run --rm $(format_cmd "${DOCKER_RUN_NET_ARGS[@]}") -e HTTP_PROXY=http://${TARGET_HOST}:${CLASH_PROXY_PORT} your-image"
else
    echo -e "   docker run --rm -e HTTP_PROXY=http://${TARGET_HOST}:${CLASH_PROXY_PORT} your-image"
fi

echo -e "\n${CYAN}3. With host.docker.internal:${NC}"
if [[ "${DOCKER_NET_MODE}" == "bridge" ]]; then
    echo -e "   docker run --rm --add-host=host.docker.internal:${HOST_IP} your-image"
else
    echo -e "   (not needed in host network mode)"
fi

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
echo -e "${WHITE}For troubleshooting, check: docs/DOCKER_PROXY_GUIDE.md${NC}"
