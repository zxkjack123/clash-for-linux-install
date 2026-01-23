#!/usr/bin/env bash
# optimize_all_network.sh
# 一键优化所有类型的网络连接
# 功能：自动运行AI、开发、流媒体、国内网站等各类服务的优化脚本

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$BASE_DIR")"
LOG_FILE="$HOME/.local/share/clash/logs/optimize_all_$(date +%Y%m%d_%H%M%S).log"

# Load env (optional) and bootstrap controller/secret (env override -> legacy compat -> runtime.yaml -> default)
# shellcheck source=/dev/null
if [[ -f "$BASE_DIR/load_env.sh" ]]; then
    source "$BASE_DIR/load_env.sh" || true
fi

clash_env_bootstrap 2>/dev/null || true

API="${CLASH_API:-http://127.0.0.1:9090}"
export CLASH_API="$API"

SERVICE="${BIN_KERNEL_NAME:-mihomo}"

# Safety policy: no disruptive actions by default.
AUTO_START_SERVICE=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --start-service|--auto-start)
                AUTO_START_SERVICE=true
                shift
                ;;
            -h|--help)
                cat <<EOF
Usage: $0 [--start-service]

  --start-service   If Clash/Mihomo is not active, attempt to start it (systemctl --user start ...)

By default, this script will NOT start or restart services automatically.
EOF
                exit 0
                ;;
            *)
                echo "Unknown arg: $1" >&2
                echo "Run with --help for usage." >&2
                exit 2
                ;;
        esac
    done
}

AUTH_HDR=()
_hdr="$(clash_auth_header 2>/dev/null || true)"
[[ -n "${_hdr:-}" ]] && AUTH_HDR=(-H "${_hdr}")

CURL_CTRL_OPTS=(--noproxy '*' --connect-timeout 2 --max-time 4)
PROXY="${PROXY:-http://127.0.0.1:7890}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 工具函数
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo -e "$msg" | tee -a "$LOG_FILE"
}

log_success() { log "${GREEN}✓${NC} $*"; }
log_error() { log "${RED}✗${NC} $*"; }
log_warn() { log "${YELLOW}⚠${NC} $*"; }
log_info() { log "${BLUE}ℹ${NC} $*"; }

# 显示标题
show_banner() {
    clear
    echo -e "${BLUE}"
    cat <<'EOF'
╔════════════════════════════════════════════════════════╗
║                                                        ║
║        🚀 一键优化全网络连接 🚀                        ║
║                                                        ║
║   自动优化：AI服务 | 开发工具 | 流媒体 | 国内网站       ║
║                                                        ║
╚════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    log_info "优化日志: $LOG_FILE"
    echo ""
}

# 检查Clash服务状态
check_clash_status() {
    log_info "检查Clash服务状态..."
    
    if ! systemctl --user is-active "$SERVICE" &>/dev/null; then
        if $AUTO_START_SERVICE; then
            log_warn "Clash服务未运行，--start-service 已启用，尝试启动..."
            if systemctl --user start "$SERVICE"; then
                log_success "Clash服务启动成功"
                sleep 3
            else
                log_error "无法启动Clash服务，请手动检查"
                return 1
            fi
        else
            log_error "Clash服务未运行 (为避免默认副作用，本脚本不会自动启动服务)"
            log_info "你可以手动启动: systemctl --user start $SERVICE"
            log_info "或使用本脚本的 --start-service 允许自动启动"
            return 1
        fi
    else
        log_success "Clash服务运行正常"
    fi
    
    if curl -fsS "${CURL_CTRL_OPTS[@]}" "${AUTH_HDR[@]}" "$API/version" >/dev/null 2>&1; then
        local version=$(curl -s "${CURL_CTRL_OPTS[@]}" "${AUTH_HDR[@]}" "$API/version" | grep -oP '"version":"\K[^"]+' || echo "未知")
        log_success "Clash API可访问 (版本: $version)"
    else
        log_error "Clash API不可访问"
        return 1
    fi
    
    echo ""
    return 0
}

# 运行单个优化脚本
run_optimization() {
    local script="$1"
    local name="$2"
    local timeout="${3:-300}"  # 默认超时5分钟
    
    log_info "开始: $name"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ ! -x "$script" ]; then
        log_warn "脚本不存在或不可执行: $script"
        return 1
    fi
    
    local start_time=$(date +%s)
    
    if timeout "$timeout" bash "$script" &>>"$LOG_FILE"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "$name 完成 (耗时: ${duration}秒)"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "$name 超时 (>${timeout}秒)"
        else
            log_error "$name 失败 (退出码: $exit_code)"
        fi
        return 1
    fi
}

# 执行运行时修复
run_runtime_guard() {
    log_info "步骤 1/5: 运行时环境修复"
    echo ""
    
    local script="$PARENT_DIR/script/runtime_guard.sh"
    if [ -f "$script" ]; then
        run_optimization "$script" "运行时修复" 180
    else
        log_warn "运行时修复脚本不存在: $script"
    fi
    
    echo ""
}

# 优化AI服务连接
optimize_ai() {
    log_info "步骤 2/5: 优化AI服务连接"
    echo ""
    
    local scripts=(
        "$BASE_DIR/optimize_ai_enhanced.sh|增强AI优化"
        "$BASE_DIR/optimize_ai.sh|标准AI优化"
    )
    
    for entry in "${scripts[@]}"; do
        IFS='|' read -r script name <<< "$entry"
        if [ -x "$script" ]; then
            run_optimization "$script" "$name" 240
            break  # 只运行第一个可用的
        fi
    done
    
    echo ""
}

# 优化开发服务连接
optimize_dev() {
    log_info "步骤 3/5: 优化开发服务连接"
    echo ""
    
    # 检查GitHub连接
    log_info "测试GitHub连接..."
    if timeout 10 curl -fsS --proxy "$PROXY" https://api.github.com >/dev/null 2>&1; then
        log_success "GitHub连接正常"
    else
        log_warn "GitHub连接异常，建议切换节点"
    fi
    
    # 检查NPM连接
    log_info "测试NPM连接..."
    if timeout 10 curl -fsS --proxy "$PROXY" https://registry.npmjs.org >/dev/null 2>&1; then
        log_success "NPM连接正常"
    else
        log_warn "NPM连接异常"
    fi
    
    # 检查PyPI连接
    log_info "测试PyPI连接..."
    if timeout 10 curl -fsS --proxy "$PROXY" https://pypi.org >/dev/null 2>&1; then
        log_success "PyPI连接正常"
    else
        log_warn "PyPI连接异常"
    fi
    
    echo ""
}

# 优化流媒体连接
optimize_streaming() {
    log_info "步骤 4/5: 优化流媒体连接"
    echo ""
    
    local scripts=(
        "$BASE_DIR/optimize_youtube_streaming.sh|YouTube流媒体优化"
        "$BASE_DIR/select_youtube_node.sh|YouTube节点选择"
    )
    
    for entry in "${scripts[@]}"; do
        IFS='|' read -r script name <<< "$entry"
        if [ -x "$script" ]; then
            run_optimization "$script" "$name" 180
            break
        fi
    done
    
    echo ""
}

# 检查国内网站连接
check_domestic() {
    log_info "步骤 5/5: 检查国内网站连接"
    echo ""
    
    local sites=(
        "https://www.baidu.com|百度"
        "https://www.taobao.com|淘宝"
        "https://www.bilibili.com|哔哩哔哩"
        "https://www.zhihu.com|知乎"
    )
    
    local total=0 success=0
    
    for site in "${sites[@]}"; do
        IFS='|' read -r url name <<< "$site"
        ((total++))
        
        log_info "测试 $name..."
        if timeout 10 curl -fsS --noproxy '*' "$url" >/dev/null 2>&1; then
            log_success "$name 连接正常"
            ((success++))
        else
            log_warn "$name 连接异常"
        fi
    done
    
    echo ""
    log_info "国内网站连接: $success/$total 正常"
    echo ""
}

# 运行健康检查
run_health_check() {
    log_info "运行最终健康检查..."
    echo ""
    
    local health_script="$BASE_DIR/network_health_monitor.sh"
    if [ -x "$health_script" ]; then
        if "$health_script" &>>"$LOG_FILE"; then
            log_success "健康检查完成"
            
            # 显示健康分数
            local metrics_file="$HOME/.local/share/clash/metrics/health_metrics.json"
            if [ -f "$metrics_file" ] && command -v jq >/dev/null 2>&1; then
                local score=$(jq -r '.health_score // "未知"' "$metrics_file")
                local grade=$(jq -r '.health_grade // "未知"' "$metrics_file")
                
                echo ""
                log_info "════════════════════════════════════════"
                log_info "  网络健康分数: ${GREEN}$score/100${NC}"
                log_info "  健康等级: ${GREEN}$grade${NC}"
                log_info "════════════════════════════════════════"
            fi
        else
            log_warn "健康检查执行失败"
        fi
    fi
    
    echo ""
}

# 显示优化总结
show_summary() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                   优化完成总结                          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log_success "所有网络优化任务已完成"
    log_info "详细日志: $LOG_FILE"
    
    echo ""
    echo -e "${YELLOW}建议后续操作：${NC}"
    echo "  1. 运行 ./network_dashboard.sh 查看实时状态"
    echo "  2. 运行 ./quick_ai_test.sh 测试AI服务"
    echo "  3. 运行 ./quick_streaming_test.sh 测试流媒体"
    echo "  4. 如果问题依然存在，请查看日志文件"
    echo ""
}

# 主流程
main() {
    parse_args "$@"
    show_banner
    
    # 检查服务状态
    if ! check_clash_status; then
        log_error "Clash服务异常，无法继续优化"
        exit 1
    fi
    
    sleep 2
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行各项优化（即使某项失败也继续）
    run_runtime_guard || true
    sleep 2
    
    optimize_ai || true
    sleep 2
    
    optimize_dev || true
    sleep 2
    
    optimize_streaming || true
    sleep 2
    
    check_domestic || true
    sleep 2
    
    # 运行健康检查
    run_health_check || true
    
    # 计算总耗时
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    local minutes=$((total_duration / 60))
    local seconds=$((total_duration % 60))
    
    # 显示总结
    show_summary
    
    log_info "总耗时: ${minutes}分${seconds}秒"
    echo ""
}

# 脚本入口
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
