#!/usr/bin/env bash
# test_siliconflow_api.sh
# 测试硅基流动所有可能的API地址，找出正确的端点

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROXY="http://127.0.0.1:7890"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     测试硅基流动 API 地址                           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# 测试地址列表
urls=(
    "https://siliconflow.cn/"
    "https://www.siliconflow.cn/"
    "https://api.siliconflow.cn/"
    "https://api.siliconflow.cn/v1"
    "https://api.siliconflow.cn/v1/models"
    "https://api.siliconflow.cn/health"
    "https://api.siliconflow.cn/ping"
    "https://api.siliconflow.cn/status"
)

success_urls=()
partial_urls=()

for url in "${urls[@]}"; do
    echo -ne "${BLUE}测试:${NC} $url ... "
    
    # 测试HTTP状态码和响应时间
    start_ms=$(date +%s%3N)
    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
        --connect-timeout 5 --max-time 10 \
        --proxy "$PROXY" \
        "$url" 2>/dev/null || echo "000")
    end_ms=$(date +%s%3N)
    duration=$((end_ms - start_ms))
    
    # 判断结果
    if [[ "$http_code" =~ ^2 ]]; then
        echo -e "${GREEN}✅ $http_code${NC} (${duration}ms) ${GREEN}成功${NC}"
        success_urls+=("$url")
    elif [[ "$http_code" =~ ^3 ]]; then
        echo -e "${GREEN}✅ $http_code${NC} (${duration}ms) ${YELLOW}重定向${NC}"
        success_urls+=("$url")
    elif [[ "$http_code" == "401" ]] || [[ "$http_code" == "403" ]]; then
        echo -e "${YELLOW}⚠️  $http_code${NC} (${duration}ms) ${YELLOW}需要认证${NC}"
        partial_urls+=("$url")
    elif [[ "$http_code" == "404" ]]; then
        echo -e "${RED}❌ $http_code${NC} (${duration}ms) ${RED}不存在${NC}"
    elif [[ "$http_code" == "000" ]]; then
        echo -e "${RED}❌ 连接失败${NC}"
    else
        echo -e "${YELLOW}⚠️  $http_code${NC} (${duration}ms)"
        partial_urls+=("$url")
    fi
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 显示结果摘要
if [ ${#success_urls[@]} -gt 0 ]; then
    echo -e "${GREEN}✅ 可用的地址 (推荐使用):${NC}"
    for url in "${success_urls[@]}"; do
        echo -e "  ${GREEN}→${NC} $url"
    done
    echo ""

    # Prefer env override (safe, no file mutation)
    recommended_url="${success_urls[0]}"
    echo -e "${BLUE}📝 建议配置方式 (无需修改脚本文件):${NC}"
    echo ""
    echo -e "${YELLOW}export SILICONFLOW_URL=\"$recommended_url\"${NC}"
    echo -e "${YELLOW}# 或写入项目根目录 .env:${NC}"
    echo -e "${YELLOW}SILICONFLOW_URL=\"$recommended_url\"${NC}"
    echo ""
fi

if [ ${#partial_urls[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  需要认证的地址 (可能需要API Key):${NC}"
    for url in "${partial_urls[@]}"; do
        echo -e "  ${YELLOW}→${NC} $url"
    done
    echo ""
fi

if [ ${#success_urls[@]} -eq 0 ] && [ ${#partial_urls[@]} -eq 0 ]; then
    echo -e "${RED}❌ 未找到可用的地址${NC}"
    echo ""
    echo -e "${BLUE}建议:${NC}"
    echo "  1. 检查网络连接和代理设置"
    echo "  2. 访问硅基流动官网查看API文档"
    echo "  3. 或考虑使用其他AI服务替代"
    echo ""
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}说明:${NC}"
echo "- 本工具仅用于探测可达 URL，不会自动修改任何文件。"
echo "- network_health_monitor.sh 支持通过 SILICONFLOW_URL 环境变量覆盖探测地址。"
