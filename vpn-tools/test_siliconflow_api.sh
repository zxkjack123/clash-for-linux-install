#!/usr/bin/env bash
# test_siliconflow_api.sh
# 测试硅基流动所有可能的API地址，找出正确的端点

set -euo pipefail

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
    
    # 生成修复命令
    recommended_url="${success_urls[0]}"
    echo -e "${BLUE}📝 推荐修复命令:${NC}"
    echo ""
    echo -e "${YELLOW}cd /home/gw/opt/clash-for-linux-install/vpn-tools${NC}"
    echo -e "${YELLOW}sed -i 's|https://api.siliconflow.cn/|$recommended_url|g' network_health_monitor.sh${NC}"
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

# 如果找到可用地址，询问是否立即修复
if [ ${#success_urls[@]} -gt 0 ]; then
    read -p "是否立即应用修复？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        recommended_url="${success_urls[0]}"
        cd /home/gw/opt/clash-for-linux-install/vpn-tools
        
        # 备份原文件
        cp network_health_monitor.sh network_health_monitor.sh.bak-siliconflow
        
        # 应用修复
        sed -i "s|https://api.siliconflow.cn/|$recommended_url|g" network_health_monitor.sh
        
        echo ""
        echo -e "${GREEN}✅ 修复已应用！${NC}"
        echo -e "${BLUE}备份文件:${NC} network_health_monitor.sh.bak-siliconflow"
        echo ""
        echo -e "${BLUE}验证修复:${NC}"
        echo -e "${YELLOW}./network_health_monitor.sh${NC}"
        echo ""
    else
        echo ""
        echo -e "${BLUE}未应用修复${NC}"
        echo "您可以稍后手动执行上述命令"
        echo ""
    fi
fi
