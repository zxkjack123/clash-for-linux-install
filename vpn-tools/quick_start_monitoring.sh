#!/usr/bin/env bash
# quick_start_monitoring.sh
# 快速启动网络监控系统
# 用法: ./quick_start_monitoring.sh

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BOLD}${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     🚀 Clash 网络监控系统 - 快速启动向导                  ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"

log() { echo -e "${GREEN}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
error() { echo -e "${RED}✗${RESET} $*"; }
info() { echo -e "${BLUE}ℹ${RESET} $*"; }

# 检查依赖
check_dependencies() {
    info "检查系统依赖..."
    
    local missing=()
    
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v systemctl >/dev/null 2>&1 || missing+=("systemd")
    command -v crontab >/dev/null 2>&1 || missing+=("cron")
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "缺少依赖: ${missing[*]}"
        echo "请先安装: sudo apt install ${missing[*]}"
        return 1
    fi
    
    log "依赖检查通过"
    
    # 可选依赖
    if ! command -v jq >/dev/null 2>&1; then
        warn "建议安装 jq 以获得更好的体验: sudo apt install jq"
    fi
    
    if ! command -v notify-send >/dev/null 2>&1; then
        warn "建议安装 notify-send 以启用桌面通知: sudo apt install libnotify-bin"
    fi
}

# 检查Clash服务
check_clash_service() {
    info "检查 Clash 服务..."
    
    if ! systemctl --user is-active mihomo &>/dev/null; then
        error "Clash 服务未运行"
        echo "请先启动 Clash: systemctl --user start mihomo"
        return 1
    fi
    
    if ! curl -fsS http://127.0.0.1:9090/version >/dev/null 2>&1; then
        error "Clash API 不可访问"
        return 1
    fi
    
    log "Clash 服务正常"
}

# 初始化监控系统
initialize_system() {
    info "初始化监控系统..."
    
    # 创建目录结构
    "$BASE_DIR/setup_monitoring_cron.sh" --setup
    
    # 创建告警配置
    if [ ! -f "$HOME/.local/share/clash/alert_config.conf" ]; then
        "$BASE_DIR/alert_notification.sh" --config
        log "已创建告警配置文件"
    fi
    
    log "初始化完成"
}

# 运行初始健康检查
run_initial_check() {
    info "运行初始健康检查..."
    
    if "$BASE_DIR/network_health_monitor.sh" --check-only; then
        log "初始健康检查完成"
    else
        warn "健康检查发现问题，建议运行修复"
    fi
}

# 安装定时任务
install_cron_jobs() {
    info "安装定时监控任务..."
    
    if "$BASE_DIR/setup_monitoring_cron.sh" --install; then
        log "定时任务安装成功"
    else
        error "定时任务安装失败"
        return 1
    fi
}

# 显示下一步
show_next_steps() {
    echo ""
    echo -e "${BOLD}${GREEN}✅ 监控系统启动成功！${RESET}"
    echo ""
    echo -e "${BOLD}下一步操作：${RESET}"
    echo ""
    echo -e "  ${BLUE}1.${RESET} 查看网络状态仪表盘："
    echo -e "     ${YELLOW}./network_dashboard.sh${RESET}"
    echo ""
    echo -e "  ${BLUE}2.${RESET} 持续监控模式（推荐）："
    echo -e "     ${YELLOW}./network_dashboard.sh --watch${RESET}"
    echo ""
    echo -e "  ${BLUE}3.${RESET} 配置告警通知："
    echo -e "     ${YELLOW}nano ~/.local/share/clash/alert_config.conf${RESET}"
    echo ""
    echo -e "  ${BLUE}4.${RESET} 运行智能规则优化："
    echo -e "     ${YELLOW}./intelligent_rule_optimizer.sh --analyze${RESET}"
    echo ""
    echo -e "  ${BLUE}5.${RESET} 查看监控状态："
    echo -e "     ${YELLOW}./setup_monitoring_cron.sh --status${RESET}"
    echo ""
    echo -e "${BOLD}已安装的自动任务：${RESET}"
    echo ""
    echo -e "  ⏰ 每10分钟：网络健康检查 + 自动修复"
    echo -e "  ⏰ 每小时：  健康快照记录"
    echo -e "  ⏰ 每天03:00：规则学习优化"
    echo -e "  ⏰ 每周日04:00：全面性能分析"
    echo -e "  ⏰ 每天02:00：日志清理（保留30天）"
    echo ""
    echo -e "${BOLD}查看日志：${RESET}"
    echo -e "  tail -f ~/.local/share/clash/logs/monitor_cron.log"
    echo ""
    echo -e "${BOLD}完整文档：${RESET}"
    echo -e "  ${YELLOW}cat $(dirname "$BASE_DIR")/NETWORK_OPTIMIZATION_GUIDE.md${RESET}"
    echo ""
    echo -e "🎉 ${BOLD}祝您使用愉快！${RESET}"
    echo ""
}

# 主流程
main() {
    echo ""
    
    # 1. 检查依赖
    check_dependencies || exit 1
    echo ""
    
    # 2. 检查Clash服务
    check_clash_service || exit 1
    echo ""
    
    # 3. 初始化系统
    initialize_system
    echo ""
    
    # 4. 运行初始检查
    run_initial_check
    echo ""
    
    # 5. 询问是否安装定时任务
    read -p "是否安装定时监控任务？(y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_cron_jobs
    else
        info "跳过定时任务安装，您可以稍后运行："
        echo "  ./setup_monitoring_cron.sh --install"
    fi
    echo ""
    
    # 6. 显示下一步
    show_next_steps
    
    # 7. 询问是否打开仪表盘
    read -p "是否现在打开网络监控仪表盘？(y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        exec "$BASE_DIR/network_dashboard.sh"
    fi
}

# 运行主流程
main
