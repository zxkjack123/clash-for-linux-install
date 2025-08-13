#!/bin/bash

# Docker Proxy Demo Script
# Demonstrates different ways to use Clash proxy with Docker containers
# Author: Auto-generated for clash-for-linux-install
# Date: August 14, 2025

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

HOST_IP=$(hostname -I | awk '{print $1}')

echo -e "${BLUE}🐳 Docker Proxy Usage Demo${NC}"
echo -e "${BLUE}=========================${NC}"
echo -e "Host IP: ${HOST_IP}"
echo -e "Clash Proxy: http://${HOST_IP}:7890"
echo ""

echo -e "${YELLOW}📋 Demo 1: Simple HTTP request with proxy${NC}"
echo -e "${CYAN}Command:${NC} docker run --rm curlimages/curl curl -x http://${HOST_IP}:7890 -s http://httpbin.org/ip"
docker run --rm curlimages/curl curl -x http://${HOST_IP}:7890 -s http://httpbin.org/ip
echo ""

echo -e "${YELLOW}📋 Demo 2: Using environment variables${NC}"
echo -e "${CYAN}Command:${NC} docker run --rm -e HTTP_PROXY=http://${HOST_IP}:7890 curlimages/curl curl -s http://httpbin.org/ip"
docker run --rm -e HTTP_PROXY=http://${HOST_IP}:7890 curlimages/curl curl -s http://httpbin.org/ip
echo ""

echo -e "${YELLOW}📋 Demo 3: Using host.docker.internal${NC}"
echo -e "${CYAN}Command:${NC} docker run --rm --add-host=host.docker.internal:${HOST_IP} -e HTTP_PROXY=http://host.docker.internal:7890 curlimages/curl curl -s http://httpbin.org/ip"
docker run --rm --add-host=host.docker.internal:${HOST_IP} -e HTTP_PROXY=http://host.docker.internal:7890 curlimages/curl curl -s http://httpbin.org/ip
echo ""

echo -e "${YELLOW}📋 Demo 4: Testing HTTPS proxy${NC}"
echo -e "${CYAN}Command:${NC} docker run --rm -e HTTPS_PROXY=http://${HOST_IP}:7890 curlimages/curl curl -s https://httpbin.org/ip"
docker run --rm -e HTTPS_PROXY=http://${HOST_IP}:7890 curlimages/curl curl -s https://httpbin.org/ip
echo ""

echo -e "${YELLOW}📋 Demo 5: Accessing Clash API from container${NC}"
echo -e "${CYAN}Command:${NC} docker run --rm curlimages/curl curl -s http://${HOST_IP}:9090/version"
docker run --rm curlimages/curl curl -s http://${HOST_IP}:9090/version
echo ""

echo -e "${GREEN}✅ All demos completed successfully!${NC}"
echo ""
echo -e "${BLUE}📖 Usage Examples for Your Applications:${NC}"
echo ""
echo -e "${CYAN}1. Single container with proxy:${NC}"
echo "   docker run --rm -e HTTP_PROXY=http://${HOST_IP}:7890 -e HTTPS_PROXY=http://${HOST_IP}:7890 your-image"
echo ""
echo -e "${CYAN}2. Docker Compose example:${NC}"
cat << EOF
   version: '3.8'
   services:
     your-app:
       image: your-image
       environment:
         - HTTP_PROXY=http://host.docker.internal:7890
         - HTTPS_PROXY=http://host.docker.internal:7890
         - NO_PROXY=localhost,127.0.0.1
       extra_hosts:
         - "host.docker.internal:${HOST_IP}"
EOF
echo ""
echo -e "${CYAN}3. With curl directly:${NC}"
echo "   docker run --rm curlimages/curl curl -x http://${HOST_IP}:7890 https://www.google.com"
echo ""
echo -e "${GREEN}🎉 Your Docker containers can now use Clash proxy!${NC}"
