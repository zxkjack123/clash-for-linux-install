#!/usr/bin/env bash
# setup_monitoring_cron.sh
# 目的: 设置定期监控任务调度
# 功能:
#   1. 自动配置 crontab 定时任务
#   2. 设置不同频率的监控任务
#   3. 配置日志轮转
#   4. 设置自动优化任务
#
# 使用方法:
#   ./setup_monitoring_cron.sh --install   # 安装监控任务(默认仅监控，不自动修复)
#   ./setup_monitoring_cron.sh --uninstall # 卸载监控任务
#   ./setup_monitoring_cron.sh --status    # 查看状态

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$BASE_DIR")"
CRON_BACKUP="$HOME/.local/share/clash/cron_backup_$(date +%Y%m%d_%H%M%S).txt"

# Safety-first defaults:
# - Do NOT auto-fix or auto-optimize unless explicitly enabled.
WITH_AUTOFIX=0
WITH_OPTIMIZER=0

have() { command -v "$1" >/dev/null 2>&1; }

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# 检查是否已安装监控任务
check_monitoring_installed() {
    have crontab || return 1
    crontab -l 2>/dev/null | grep -q "network_health_monitor" && return 0
    return 1
}

# 安装监控任务
install_monitoring() {
    log "开始安装监控任务..."

    if ! have crontab; then
        log "❌ 未找到 crontab 命令：请先安装 cron (Debian/Ubuntu: cron)" 
        return 1
    fi
    
    # 备份现有 crontab
    if crontab -l &>/dev/null; then
        crontab -l > "$CRON_BACKUP"
        log "已备份现有 crontab 到: $CRON_BACKUP"
    fi
    
    # 检查脚本是否存在并设置可执行权限
    local scripts=(
        "$BASE_DIR/network_health_monitor.sh"
        "$BASE_DIR/intelligent_rule_optimizer.sh"
        "$PARENT_DIR/script/runtime_guard.sh"
        "$BASE_DIR/alert_notification.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log "警告: 脚本不存在: $script"
        else
            chmod +x "$script"
            log "设置可执行权限: $script"
        fi
    done
    
    # 生成新的 crontab 配置
    local temp_cron=$(mktemp)
    
    # 保留现有的 crontab（排除旧的监控任务）
    if crontab -l &>/dev/null; then
        crontab -l | grep -v "network_health_monitor\|runtime_guard\|intelligent_rule\|clash_log_rotate" >> "$temp_cron" || true
    fi
    
    cat >> "$temp_cron" <<EOF

# ===== Clash 网络监控任务 =====
# 由 setup_monitoring_cron.sh 自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF

    if [[ $WITH_AUTOFIX -eq 1 ]]; then
        cat >> "$temp_cron" <<EOF

# 每10分钟进行一次网络健康检查（允许自动修复）
*/10 * * * * $BASE_DIR/network_health_monitor.sh --auto-fix >> $HOME/.local/share/clash/logs/monitor_cron.log 2>&1

# 每10分钟运行一次运行时守护检查（允许自动修复）
*/10 * * * * bash $PARENT_DIR/script/runtime_guard.sh --auto-fix --cron >> $HOME/.local/share/clash/logs/guard_cron.log 2>&1
EOF
    else
        cat >> "$temp_cron" <<EOF

# 每10分钟进行一次网络健康检查（仅监控，不修复）
*/10 * * * * $BASE_DIR/network_health_monitor.sh --check-only >> $HOME/.local/share/clash/logs/monitor_cron.log 2>&1

# 每10分钟运行一次运行时守护检查（仅检查，不修复）
*/10 * * * * bash $PARENT_DIR/script/runtime_guard.sh --check --cron >> $HOME/.local/share/clash/logs/guard_cron.log 2>&1
EOF
    fi

    if [[ $WITH_OPTIMIZER -eq 1 ]]; then
        cat >> "$temp_cron" <<EOF

# 每天凌晨3点进行智能规则学习
0 3 * * * $BASE_DIR/intelligent_rule_optimizer.sh --learn >> $HOME/.local/share/clash/logs/optimizer_cron.log 2>&1

# 每周日凌晨4点进行全面规则分析和优化
0 4 * * 0 $BASE_DIR/intelligent_rule_optimizer.sh --analyze >> $HOME/.local/share/clash/logs/optimizer_cron.log 2>&1
EOF
    fi

    cat >> "$temp_cron" <<EOF

# 每天凌晨2点清理和轮转日志（保留最近30天）
0 2 * * * find $HOME/.local/share/clash/logs/ -name "*.log" -mtime +30 -delete >> $HOME/.local/share/clash/logs/cleanup.log 2>&1

# 每小时生成一次健康报告快照（仅检查）
0 * * * * $BASE_DIR/network_health_monitor.sh --check-only >> $HOME/.local/share/clash/logs/hourly_check.log 2>&1

# ===== Clash 网络监控任务结束 =====

EOF
    
    # 安装新的 crontab
    if crontab "$temp_cron"; then
        log "✅ 监控任务安装成功！"
        rm -f "$temp_cron"
    else
        log "❌ 安装失败！"
        log "临时文件保留在: $temp_cron"
        return 1
    fi
    
    log ""
    log "已安装以下监控任务:"
    if [[ $WITH_AUTOFIX -eq 1 ]]; then
        log "  - 每10分钟: 网络健康检查（允许自动修复）"
        log "  - 每10分钟: 运行时守护检查（允许自动修复）"
    else
        log "  - 每10分钟: 网络健康检查（仅监控，不修复）"
        log "  - 每10分钟: 运行时守护检查（仅检查，不修复）"
    fi
    if [[ $WITH_OPTIMIZER -eq 1 ]]; then
        log "  - 每天03:00: 智能规则学习"
        log "  - 每周日04:00: 全面规则分析"
    fi
    log "  - 每天02:00: 日志清理（保留30天）"
    log "  - 每小时: 健康快照（仅检查）"
    log ""
    log "查看日志:"
    log "  tail -f $HOME/.local/share/clash/logs/monitor_cron.log"
    log "  tail -f $HOME/.local/share/clash/logs/guard_cron.log"
}

# 卸载监控任务
uninstall_monitoring() {
    log "开始卸载监控任务..."

    if ! have crontab; then
        log "❌ 未找到 crontab 命令：无法卸载 (系统未安装 cron?)"
        return 1
    fi
    
    if ! check_monitoring_installed; then
        log "未检测到已安装的监控任务"
        return 0
    fi
    
    # 备份现有 crontab
    crontab -l > "$CRON_BACKUP"
    log "已备份现有 crontab 到: $CRON_BACKUP"
    
    # 移除监控任务
    local temp_cron=$(mktemp)
    crontab -l | grep -v "network_health_monitor\|runtime_guard\|intelligent_rule\|clash_log_rotate\|===== Clash" > "$temp_cron" || true
    
    if crontab "$temp_cron"; then
        log "✅ 监控任务卸载成功！"
        rm -f "$temp_cron"
    else
        log "❌ 卸载失败！"
        return 1
    fi
}

# 查看状态
show_status() {
    log "监控任务状态:"
    log ""

    if ! have crontab; then
        log "❌ 未找到 crontab 命令：无法查看状态 (系统未安装 cron?)"
        return 1
    fi
    
    if check_monitoring_installed; then
        log "✅ 监控任务已安装"
        log ""
        log "当前配置的任务:"
        crontab -l | grep -A 20 "===== Clash 网络监控任务" | grep -v "^#" | grep -v "^$"
    else
        log "❌ 监控任务未安装"
    fi
    
    log ""
    log "最近的监控日志:"
    
    local log_files=(
        "$HOME/.local/share/clash/logs/monitor_cron.log"
        "$HOME/.local/share/clash/logs/guard_cron.log"
        "$HOME/.local/share/clash/logs/health_alerts.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ]; then
            log ""
            log "=== $(basename "$log_file") (最近5行) ==="
            tail -n 5 "$log_file" || true
        fi
    done
    
    log ""
    log "健康监控统计:"
    if [ -f "$HOME/.local/share/clash/metrics/health_metrics.json" ]; then
        if command -v jq &>/dev/null; then
            log "  最近检查时间: $(jq -r '.check_time' "$HOME/.local/share/clash/metrics/health_metrics.json")"
            log "  健康分数: $(jq -r '.health_score' "$HOME/.local/share/clash/metrics/health_metrics.json")/100"
            log "  健康等级: $(jq -r '.health_grade' "$HOME/.local/share/clash/metrics/health_metrics.json")"
        else
            log "  (安装 jq 以查看详细信息)"
        fi
    else
        log "  暂无健康数据"
    fi
}

# 测试监控脚本
test_monitoring() {
    log "测试监控脚本..."
    log ""
    
    # 测试网络健康监控
    if [ -x "$BASE_DIR/network_health_monitor.sh" ]; then
        log "1. 测试网络健康监控..."
        "$BASE_DIR/network_health_monitor.sh" --check-only || log "  警告: 测试失败"
    else
        log "❌ network_health_monitor.sh 不存在或不可执行"
    fi
    
    log ""
    
    # 测试告警系统
    if [ -x "$BASE_DIR/alert_notification.sh" ]; then
        log "2. 测试告警系统..."
        "$BASE_DIR/alert_notification.sh" INFO "监控系统测试" || log "  警告: 测试失败"
    else
        log "❌ alert_notification.sh 不存在或不可执行"
    fi
    
    log ""
    
    # 测试运行时守护
    if [ -x "$PARENT_DIR/script/runtime_guard.sh" ]; then
        log "3. 测试运行时守护..."
        bash "$PARENT_DIR/script/runtime_guard.sh" --check || log "  警告: 测试失败"
    else
        log "❌ runtime_guard.sh 不存在或不可执行"
    fi
    
    log ""
    log "✅ 测试完成"
}

# 创建初始目录和配置
setup_directories() {
    log "创建监控目录结构..."
    
    local dirs=(
        "$HOME/.local/share/clash/logs"
        "$HOME/.local/share/clash/metrics"
        "$HOME/.local/share/clash/backup"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log "  创建: $dir"
    done
    
    # 创建告警配置
    if [ ! -f "$HOME/.local/share/clash/alert_config.conf" ]; then
        "$BASE_DIR/alert_notification.sh" --config
    fi
    
    log "✅ 目录结构创建完成"
}

# 显示帮助
show_help() {
    cat <<EOF
Clash 监控任务调度设置工具

用法:
  $0 [选项]

选项:
  --install      安装监控任务到 crontab
    --with-autofix 与 --install 搭配：允许自动修复（高风险，会切换/重启/改配置）
    --with-optimizer 与 --install 搭配：启用智能规则学习/分析（可能修改策略/选择）
    --install-full  等价于: --install --with-autofix --with-optimizer
  --uninstall    卸载监控任务
  --status       查看监控任务状态
  --test         测试监控脚本
  --setup        设置目录结构
  -h, --help     显示帮助

监控任务说明:
  1. 网络健康检查（每10分钟）
     - 检测AI、开发、流媒体、国内网站的可用性
     - 计算健康分数并告警
      - 默认仅监控；如需自动修复请使用 --with-autofix

  2. 运行时守护（每10分钟）
     - 检查配置文件完整性
      - 默认仅检查；如需自动修复请使用 --with-autofix
     - 确保关键规则存在

  3. 智能规则优化（每天、每周）
     - 学习历史性能数据
     - 自动分析节点性能
     - 生成优化建议

  4. 日志管理（每天）
     - 清理30天前的日志
     - 避免磁盘空间占用

示例:
    $0 --install      # 安装监控任务（默认仅监控，不自动修复）
    $0 --install --with-autofix      # 安装监控任务 + 允许自动修复
    $0 --install --with-optimizer    # 安装监控任务 + 启用规则学习/分析
    $0 --install-full # 安装全套任务（自动修复 + 优化）
  $0 --status       # 查看运行状态
  $0 --test         # 测试所有监控脚本

日志位置:
  $HOME/.local/share/clash/logs/
    - monitor_cron.log    # 健康监控日志
    - guard_cron.log      # 运行时守护日志
    - optimizer_cron.log  # 规则优化日志
    - health_alerts.log   # 告警日志

EOF
}

# 参数解析
ACTION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            ACTION="install"
            shift
            ;;
        --install-full)
            ACTION="install"
            WITH_AUTOFIX=1
            WITH_OPTIMIZER=1
            shift
            ;;
        --with-autofix)
            WITH_AUTOFIX=1
            shift
            ;;
        --with-optimizer)
            WITH_OPTIMIZER=1
            shift
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --test)
            ACTION="test"
            shift
            ;;
        --setup)
            ACTION="setup"
            shift
            ;;
        -h|--help)
            ACTION="help"
            shift
            ;;
        *)
            echo "未知参数: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

case "${ACTION:-help}" in
    install)
        setup_directories
        install_monitoring
        ;;
    uninstall)
        uninstall_monitoring
        ;;
    status)
        show_status
        ;;
    test)
        test_monitoring
        ;;
    setup)
        setup_directories
        ;;
    help|*)
        show_help
        ;;
esac
