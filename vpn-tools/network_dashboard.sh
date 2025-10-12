#!/usr/bin/env bash
# network_dashboard.sh
# 目的: 网络状态可视化仪表盘
# 功能:
#   1. 实时显示网络健康状态
#   2. 展示各服务类别的性能指标
#   3. 显示节点状态和告警信息
#   4. 提供交互式操作界面
#
# 使用方法:
#   ./network_dashboard.sh           # 显示仪表盘
#   ./network_dashboard.sh --watch   # 持续刷新模式

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$BASE_DIR")"
METRICS_FILE="$HOME/.local/share/clash/metrics/health_metrics.json"
ALERT_LOG="$HOME/.local/share/clash/logs/health_alerts.log"
HISTORY_LOG="$HOME/.local/share/clash/logs/health_history.log"

# 加载环境变量配置（.env文件）
if [[ -f "$BASE_DIR/load_env.sh" ]]; then
    source "$BASE_DIR/load_env.sh"
fi

API=${CLASH_API:-http://127.0.0.1:9090}
WATCH_MODE=false
REFRESH_INTERVAL=10

have() { command -v "$1" >/dev/null 2>&1; }

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# 获取终端宽度
get_terminal_width() {
    tput cols 2>/dev/null || echo 80
}

# 绘制分隔线
draw_separator() {
    local width=$(get_terminal_width)
    printf '%*s\n' "$width" '' | tr ' ' '='
}

# 绘制标题
draw_header() {
    clear
    local width=$(get_terminal_width)
    echo -e "${BOLD}${CYAN}"
    printf '%*s\n' "$width" '' | tr ' ' '='
    printf "%*s\n" $(((${#1}+width)/2)) "$1"
    printf '%*s\n' "$width" '' | tr ' ' '='
    echo -e "${RESET}"
}

# 获取服务状态图标
get_status_icon() {
    local rate="$1"
    if [ "$rate" -ge 90 ]; then
        echo -e "${GREEN}●${RESET}"
    elif [ "$rate" -ge 70 ]; then
        echo -e "${YELLOW}●${RESET}"
    else
        echo -e "${RED}●${RESET}"
    fi
}

# 获取健康等级颜色
get_grade_color() {
    local grade="$1"
    case "${grade:0:1}" in
        A) echo -e "${GREEN}" ;;
        B) echo -e "${CYAN}" ;;
        C) echo -e "${YELLOW}" ;;
        *) echo -e "${RED}" ;;
    esac
}

# 显示系统概览
show_system_overview() {
    echo -e "${BOLD}${BLUE}▸ 系统概览${RESET}"
    echo ""
    
    # Clash服务状态
    local service_status="●"
    local service_color="${RED}"
    if systemctl --user is-active mihomo &>/dev/null; then
        service_status="●"
        service_color="${GREEN}"
    fi
    echo -e "  Clash服务:    ${service_color}${service_status}${RESET} $(systemctl --user is-active mihomo 2>/dev/null || echo 'inactive')"
    
    # API状态
    local api_status="✗"
    local api_color="${RED}"
    if curl -fsS "$API/version" >/dev/null 2>&1; then
        api_status="✓"
        api_color="${GREEN}"
        local version=$(curl -fsS "$API/version" 2>/dev/null | grep -oP '"version":"[^"]+' | cut -d'"' -f4 || echo "unknown")
        echo -e "  API状态:      ${api_color}${api_status}${RESET} $version"
    else
        echo -e "  API状态:      ${api_color}${api_status}${RESET} 不可访问"
    fi
    
    # 当前节点
    if curl -fsS "$API/proxies/西瓜加速" >/dev/null 2>&1; then
        local current_node
        if have jq; then
            current_node=$(curl -fsS "$API/proxies/西瓜加速" 2>/dev/null | jq -r '.now' 2>/dev/null || echo "unknown")
        else
            current_node=$(curl -fsS "$API/proxies/西瓜加速" 2>/dev/null | grep -oP '"now":"[^"]+' | cut -d'"' -f4 || echo "unknown")
        fi
        echo -e "  当前节点:     ${CYAN}$current_node${RESET}"
    fi
    
    # 运行时间
    if systemctl --user is-active mihomo &>/dev/null; then
        local uptime=$(systemctl --user show mihomo --property=ActiveEnterTimestamp 2>/dev/null | cut -d'=' -f2)
        if [ -n "$uptime" ]; then
            local uptime_seconds=$(( $(date +%s) - $(date -d "$uptime" +%s 2>/dev/null || echo 0) ))
            local uptime_str=$(printf '%dd %dh %dm' $((uptime_seconds/86400)) $((uptime_seconds%86400/3600)) $((uptime_seconds%3600/60)))
            echo -e "  运行时间:     $uptime_str"
        fi
    fi
    
    echo ""
}

# 显示健康状态
show_health_status() {
    echo -e "${BOLD}${BLUE}▸ 健康状态${RESET}"
    echo ""
    
    if [ ! -f "$METRICS_FILE" ]; then
        echo -e "  ${YELLOW}⚠${RESET} 暂无健康数据，请运行监控脚本"
        echo ""
        return
    fi
    
    if ! have jq; then
        echo -e "  ${YELLOW}⚠${RESET} 需要安装 jq 以显示详细信息"
        echo ""
        return
    fi
    
    local score=$(jq -r '.health_score' "$METRICS_FILE" 2>/dev/null || echo "0")
    local grade=$(jq -r '.health_grade' "$METRICS_FILE" 2>/dev/null || echo "未知")
    local check_time=$(jq -r '.check_time' "$METRICS_FILE" 2>/dev/null || echo "未知")
    
    local grade_color=$(get_grade_color "$grade")
    
    # 健康分数条
    local bar_width=50
    local filled=$((score * bar_width / 100))
    local empty=$((bar_width - filled))
    
    echo -e "  健康分数:     ${grade_color}${BOLD}$score/100${RESET} ($grade)"
    echo -n "  "
    printf "${GREEN}█%.0s${RESET}" $(seq 1 $filled)
    printf "${RESET}░%.0s" $(seq 1 $empty)
    echo ""
    echo -e "  最近检查:     $check_time"
    echo ""
}

# 显示服务详情
show_services_detail() {
    echo -e "${BOLD}${BLUE}▸ 服务详情${RESET}"
    echo ""
    
    if [ ! -f "$METRICS_FILE" ] || ! have jq; then
        echo -e "  ${YELLOW}⚠${RESET} 数据不可用"
        echo ""
        return
    fi
    
    printf "  %-15s %6s   %10s   %10s\n" "类别" "状态" "成功率" "平均延迟"
    printf "  %-15s %6s   %10s   %10s\n" "────────────" "────" "──────" "────────"
    
    local services=(
        "ai:AI服务"
        "development:开发服务"
        "streaming:流媒体"
        "domestic:国内网站"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r key label <<< "$service_info"
        
        local rate=$(jq -r ".services.$key.success_rate" "$METRICS_FILE" 2>/dev/null || echo "0")
        local latency=$(jq -r ".services.$key.avg_latency_ms" "$METRICS_FILE" 2>/dev/null || echo "0")
        local success=$(jq -r ".services.$key.success" "$METRICS_FILE" 2>/dev/null || echo "0")
        local total=$(jq -r ".services.$key.total" "$METRICS_FILE" 2>/dev/null || echo "0")
        
        local icon=$(get_status_icon "$rate")
        
        printf "  %-15s %6s   %7s%%   %8sms\n" "$label" "$icon" "$rate" "$latency"
    done
    
    echo ""
}

# 显示最近告警
show_recent_alerts() {
    echo -e "${BOLD}${BLUE}▸ 最近告警${RESET}"
    echo ""
    
    if [ ! -f "$ALERT_LOG" ] || [ ! -s "$ALERT_LOG" ]; then
        echo -e "  ${GREEN}✓${RESET} 暂无告警"
        echo ""
        return
    fi
    
    local alert_count=$(tail -n 10 "$ALERT_LOG" | wc -l)
    echo -e "  显示最近 $alert_count 条告警:"
    echo ""
    
    tail -n 10 "$ALERT_LOG" | while IFS= read -r line; do
        if [[ "$line" =~ CRITICAL ]]; then
            echo -e "  ${RED}●${RESET} $line"
        elif [[ "$line" =~ WARNING ]]; then
            echo -e "  ${YELLOW}●${RESET} $line"
        else
            echo -e "  ${CYAN}●${RESET} $line"
        fi
    done
    
    echo ""
}

# 显示性能趋势
show_performance_trend() {
    echo -e "${BOLD}${BLUE}▸ 性能趋势（最近10次检查）${RESET}"
    echo ""
    
    if [ ! -f "$HISTORY_LOG" ] || ! have jq; then
        echo -e "  ${YELLOW}⚠${RESET} 历史数据不可用"
        echo ""
        return
    fi
    
    # 提取最近10次的健康分数
    local scores=($(grep "健康分数" "$HISTORY_LOG" | tail -n 10 | grep -oP '\d+/100' | cut -d'/' -f1))
    
    if [ ${#scores[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}⚠${RESET} 暂无历史数据"
        echo ""
        return
    fi
    
    # 简单的ASCII图表
    local max_score=100
    local bar_height=10
    
    for i in $(seq 9 -1 0); do
        local threshold=$((max_score - i * 10))
        printf "  %3d |" "$threshold"
        
        for score in "${scores[@]}"; do
            if [ "$score" -ge "$threshold" ]; then
                printf " █"
            else
                printf "  "
            fi
        done
        echo ""
    done
    
    printf "  %3s +" "0"
    printf '─%.0s' $(seq 1 $((${#scores[@]} * 2)))
    echo ""
    printf "      "
    for i in $(seq 1 ${#scores[@]}); do
        printf " $i"
    done
    echo ""
    echo ""
}

# 显示快速操作
show_quick_actions() {
    echo -e "${BOLD}${BLUE}▸ 快速操作${RESET}"
    echo ""
    echo -e "  ${CYAN}[1]${RESET} 运行健康检查        ${CYAN}[2]${RESET} 优化AI服务"
    echo -e "  ${CYAN}[3]${RESET} 优化流媒体          ${CYAN}[4]${RESET} 查看详细报告"
    echo -e "  ${CYAN}[5]${RESET} 重启Clash服务       ${CYAN}[6]${RESET} 运行时修复"
    echo -e "  ${GREEN}[7]${RESET} ${BOLD}一键优化全网络${RESET}      ${CYAN}[q]${RESET} 退出"
    echo ""
}

# 执行操作
execute_action() {
    local action="$1"
    
    case "$action" in
        1)
            echo "运行健康检查..."
            "$BASE_DIR/network_health_monitor.sh"
            ;;
        2)
            echo "优化AI服务..."
            "$BASE_DIR/optimize_ai.sh"
            ;;
        3)
            echo "优化流媒体..."
            "$BASE_DIR/select_youtube_node.sh"
            ;;
        4)
            echo "生成详细报告..."
            "$BASE_DIR/network_health_monitor.sh" --report
            ;;
        5)
            echo "重启Clash服务..."
            systemctl --user restart mihomo
            ;;
        6)
            echo "运行时修复..."
            bash "$PARENT_DIR/script/runtime_guard.sh" --auto-fix
            ;;
        7)
            echo "🚀 一键优化全网络..."
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            if [ -x "$BASE_DIR/optimize_all_network.sh" ]; then
                "$BASE_DIR/optimize_all_network.sh"
            else
                echo "错误: 优化脚本不存在或不可执行"
            fi
            ;;
        q|Q)
            echo "退出仪表盘"
            exit 0
            ;;
        *)
            echo "无效的选项: $action"
            ;;
    esac
    
    echo ""
    read -p "按回车键继续..." -r
}

# 显示完整仪表盘
show_dashboard() {
    draw_header "CLASH 网络监控仪表盘"
    show_system_overview
    draw_separator
    show_health_status
    draw_separator
    show_services_detail
    draw_separator
    show_recent_alerts
    draw_separator
    show_performance_trend
    draw_separator
    
    if ! $WATCH_MODE; then
        show_quick_actions
    else
        echo -e "${CYAN}自动刷新中...${RESET} (${REFRESH_INTERVAL}秒后刷新，Ctrl+C 退出)"
        echo ""
    fi
}

# Watch模式
watch_dashboard() {
    while true; do
        show_dashboard
        sleep "$REFRESH_INTERVAL"
    done
}

# 交互模式
interactive_mode() {
    while true; do
        show_dashboard
        read -p "请选择操作: " -n 1 -r action
        echo ""
        
        [ "$action" = "q" ] || [ "$action" = "Q" ] && break
        
        execute_action "$action"
    done
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        --watch|-w)
            WATCH_MODE=true
            shift
            ;;
        --interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            cat <<EOF
网络状态仪表盘

用法:
  $0 [选项]

选项:
  --watch, -w       持续刷新模式
  --interval SEC    设置刷新间隔（秒，默认10）
  -h, --help        显示帮助

说明:
  默认模式为交互式，可以执行快速操作
  Watch模式会自动刷新，适合监控

示例:
  $0                    # 交互式仪表盘
  $0 --watch            # 持续刷新
  $0 --watch --interval 5   # 5秒刷新一次

EOF
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# 主逻辑
if $WATCH_MODE; then
    watch_dashboard
else
    interactive_mode
fi
