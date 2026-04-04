#!/usr/bin/env bash
# network_health_monitor.sh
# 目的: 网络健康综合监控守护进程
# 功能:
#   1. 定期检测网络连接质量（延迟、丢包、带宽）
#   2. 监控关键服务可用性（AI、开发、流媒体）
#   3. 自动检测问题并触发修复
#   4. 记录历史数据用于分析趋势
#   5. 异常时发送告警通知
#
# 使用方法:
#   ./network_health_monitor.sh              # 前台运行一次检查
#   ./network_health_monitor.sh --daemon     # 后台守护模式（每10分钟检查）
#   ./network_health_monitor.sh --check-only # 仅检查不修复
#   ./network_health_monitor.sh --report     # 生成详细报告

set -euo pipefail

# 配置
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$BASE_DIR")"
LOG_DIR="$HOME/.local/share/clash/logs"
METRICS_DIR="$HOME/.local/share/clash/metrics"
ALERT_LOG="$LOG_DIR/health_alerts.log"
HISTORY_LOG="$LOG_DIR/health_history.log"
HEALTH_METRICS="$METRICS_DIR/health_metrics.json"

# 加载环境变量配置（.env文件）
# 备注：监控脚本应尽量“保守”，不要因可选环境文件缺失/异常而直接退出。
if [[ -f "$BASE_DIR/load_env.sh" ]]; then
    # shellcheck source=/dev/null
    source "$BASE_DIR/load_env.sh" || true
fi

# Controller address/secret are bootstrapped by load_env.sh (env override -> legacy compat -> runtime.yaml -> default).
API="${CLASH_API:-http://127.0.0.1:9090}"
AUTH_HDR=()
_hdr="$(clash_auth_header 2>/dev/null || true)"
[[ -n "${_hdr:-}" ]] && AUTH_HDR=(-H "${_hdr}")
CURL_CTRL_OPTS=(--connect-timeout 2 --max-time 4)

PROXY=${PROXY:-http://127.0.0.1:7890}
# systemd --user unit name (override via .env if your kernel/service name differs)
SERVICE=${BIN_KERNEL_NAME:-mihomo}
CHECK_INTERVAL=600  # 10分钟
ALERT_SCRIPT="$BASE_DIR/alert_notification.sh"

# Optional overrides (avoid editing scripts; prefer .env)
SILICONFLOW_URL=${SILICONFLOW_URL:-https://siliconflow.cn/}

# 阈值配置
LATENCY_WARN=500      # 延迟警告阈值(ms)
LATENCY_CRITICAL=1000 # 延迟严重阈值(ms)
FAIL_RATE_WARN=20     # 失败率警告阈值(%)
FAIL_RATE_CRITICAL=40 # 失败率严重阈值(%)
MIN_HEALTH_SCORE=60   # 最低健康分数

# 运行模式
MODE="once"
CHECK_ONLY=false
REPORT_ONLY=false
# Safety-first default: do NOT change routing/service unless explicitly requested.
AUTO_FIX=false

# 初始化
mkdir -p "$LOG_DIR" "$METRICS_DIR"
touch "$ALERT_LOG" "$HISTORY_LOG"

# 工具函数
have() { command -v "$1" >/dev/null 2>&1; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$HISTORY_LOG"; }
alert() { 
    local level="$1" msg="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg" | tee -a "$ALERT_LOG"
    if [ -x "$ALERT_SCRIPT" ]; then
        "$ALERT_SCRIPT" "$level" "$msg" || true
    fi
}

# 检查服务可用性
check_clash_service() {
    local status="OK"
    local msg=""
    
    if ! systemctl --user is-active "$SERVICE" &>/dev/null; then
        status="CRITICAL"
        msg="Clash服务未运行"
        echo "$status|$msg"
        return 1
    fi
    
    if declare -F clash_api_get >/dev/null 2>&1; then
        if ! clash_api_get /version >/dev/null 2>&1; then
            status="CRITICAL"
            msg="Clash API不可访问"
            echo "$status|$msg"
            return 1
        fi
    else
        if ! curl -fsS --noproxy '*' "${CURL_CTRL_OPTS[@]}" ${AUTH_HDR[@]+"${AUTH_HDR[@]}"} "$API/version" >/dev/null 2>&1; then
            status="CRITICAL"
            msg="Clash API不可访问"
            echo "$status|$msg"
            return 1
        fi
    fi
    
    echo "$status|$msg"
    return 0
}

# 测试单个URL
test_url() {
    local url="$1" label="$2" use_proxy="${3:-yes}" pattern="${4:-^[23]}"
    local start_ms end_ms duration_ms http_code
    
    start_ms=$(date +%s%3N)
    local mode=$(echo "$use_proxy" | tr '[:upper:]' '[:lower:]')
    if [[ "$mode" == "yes" || "$mode" == "proxy" ]]; then
        http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \
            --proxy "$PROXY" "$url" 2>/dev/null || echo "000")
    else
        http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \
            --noproxy '*' "$url" 2>/dev/null || echo "000")
    fi
    end_ms=$(date +%s%3N)
    duration_ms=$((end_ms - start_ms))
    
    local success=0
    if [[ "$http_code" =~ $pattern ]]; then
        success=1
    fi
    
    echo "$label|$http_code|$duration_ms|$success"
}

# 检查AI服务
check_ai_services() {
    log "检查AI服务..." >&2
    local total=0 success=0 total_latency=0
    
    local services=(
        $'https://chat.openai.com/\tChatGPT\t^[23]\tyes'
        $'https://api.scnet.cn/api/llm/v1/chat/completions\tSCNET\t^(20[0-9]|401|403|405)$\tyes'
        $'https://sg.uiuiapi.com/\tUIUI-API\t^(20[0-9]|30[12378])$\tyes'
        "${SILICONFLOW_URL}"$'\t硅基流动\t^(20[0-9]|30[0-9])$\tdirect'
        $'https://openrouter.ai/api/v1\tOpenRouter\t^(20[0-9]|401|403)$\tyes'
        $'https://kimi.moonshot.cn/\tKimi\t^[23]\tyes'
    )
    
    for service in "${services[@]}"; do
        local url label pattern proxy_pref
        IFS=$'\t' read -r url label pattern proxy_pref <<< "$service"
        local regex="${pattern:-^[23]}"
        local proxy_mode="${proxy_pref:-yes}"
        case "${proxy_mode,,}" in
            direct|no|off)
                proxy_mode="no"
                ;;
            *)
                proxy_mode="yes"
                ;;
         esac
        result=$(test_url "$url" "$label" "$proxy_mode" "$regex")
        IFS='|' read -r lbl code latency succ <<< "$result"

        total=$((total + 1))
        success=$((success + succ))
        total_latency=$((total_latency + latency))
        
        log "  $lbl: ${code} (${latency}ms) [$([ $succ -eq 1 ] && echo 'OK' || echo 'FAIL')]" >&2
    done
    
    local avg_latency=$((total_latency / total))
    local success_rate=$((success * 100 / total))
    
    echo "$success_rate|$avg_latency|$success|$total"
}

# 检查开发服务
check_dev_services() {
    log "检查开发服务..." >&2
    local total=0 success=0 total_latency=0
    
    local services=(
        $'https://api.github.com\tGitHub\t^[23]'
        $'https://registry.npmjs.org\tNPM\t^[23]'
        $'https://pypi.org\tPyPI\t^[23]'
        $'https://crates.io\tCrates\t^(20[0-9]|30[0-9]|403)$'
    )
    
    for service in "${services[@]}"; do
        local url label pattern
        IFS=$'\t' read -r url label pattern <<< "$service"
        result=$(test_url "$url" "$label" "yes" "${pattern:-^[23]}")
        IFS='|' read -r lbl code latency succ <<< "$result"

        total=$((total + 1))
        success=$((success + succ))
        total_latency=$((total_latency + latency))
        
        log "  $lbl: ${code} (${latency}ms) [$([ $succ -eq 1 ] && echo 'OK' || echo 'FAIL')]" >&2
    done
    
    local avg_latency=$((total_latency / total))
    local success_rate=$((success * 100 / total))
    
    echo "$success_rate|$avg_latency|$success|$total"
}

# 检查流媒体服务
check_streaming_services() {
    log "检查流媒体服务..." >&2
    local total=0 success=0 total_latency=0
    
    local services=(
        "https://www.youtube.com|YouTube"
        "https://zoom.us|Zoom"
        "https://meet.google.com|Google-Meet"
    )
    
    for service in "${services[@]}"; do
        IFS='|' read -r url label <<< "$service"
        result=$(test_url "$url" "$label" "yes")
        IFS='|' read -r lbl code latency succ <<< "$result"

        total=$((total + 1))
        success=$((success + succ))
        total_latency=$((total_latency + latency))
        
        log "  $lbl: ${code} (${latency}ms) [$([ $succ -eq 1 ] && echo 'OK' || echo 'FAIL')]" >&2
    done
    
    local avg_latency=$((total_latency / total))
    local success_rate=$((success * 100 / total))
    
    echo "$success_rate|$avg_latency|$success|$total"
}

# 检查国内网站
check_domestic_sites() {
    log "检查国内网站..." >&2
    local total=0 success=0 total_latency=0
    
    local sites=(
        "https://www.baidu.com|百度"
        "https://www.taobao.com|淘宝"
        "https://www.bilibili.com|哔哩哔哩"
        "https://www.zhihu.com|知乎"
    )
    
    for site in "${sites[@]}"; do
        IFS='|' read -r url label <<< "$site"
        result=$(test_url "$url" "$label" "no")
        IFS='|' read -r lbl code latency succ <<< "$result"

        total=$((total + 1))
        success=$((success + succ))
        total_latency=$((total_latency + latency))
        
        log "  $lbl: ${code} (${latency}ms) [$([ $succ -eq 1 ] && echo 'OK' || echo 'FAIL')]" >&2
    done
    
    local avg_latency=$((total_latency / total))
    local success_rate=$((success * 100 / total))
    
    echo "$success_rate|$avg_latency|$success|$total"
}

# 计算健康分数
calculate_health_score() {
    local ai_rate="$1" ai_latency="$2"
    local dev_rate="$3" dev_latency="$4"
    local stream_rate="$5" stream_latency="$6"
    local domestic_rate="$7" domestic_latency="$8"
    
    # 权重：AI(30%), Dev(25%), Streaming(20%), Domestic(25%)
    local score=0
    
    # 成功率贡献 (70%)
    score=$((score + ai_rate * 30 * 70 / 10000))
    score=$((score + dev_rate * 25 * 70 / 10000))
    score=$((score + stream_rate * 20 * 70 / 10000))
    score=$((score + domestic_rate * 25 * 70 / 10000))
    
    # 延迟贡献 (30%)
    local latency_score=0
    [ "$ai_latency" -lt 500 ] && latency_score=$((latency_score + 30))
    [ "$dev_latency" -lt 500 ] && latency_score=$((latency_score + 25))
    [ "$stream_latency" -lt 500 ] && latency_score=$((latency_score + 20))
    [ "$domestic_latency" -lt 300 ] && latency_score=$((latency_score + 25))
    
    score=$((score + latency_score * 30 / 100))
    
    echo "$score"
}

# 获取健康等级
get_health_grade() {
    local score="$1"
    if [ "$score" -ge 90 ]; then echo "A - 优秀"
    elif [ "$score" -ge 80 ]; then echo "B - 良好"
    elif [ "$score" -ge 70 ]; then echo "C - 一般"
    elif [ "$score" -ge 60 ]; then echo "D - 较差"
    else echo "F - 故障"
    fi
}

# 触发自动修复
trigger_auto_fix() {
    local issue="$1"
    
    $CHECK_ONLY && return 0
    $AUTO_FIX || return 0
    
    log "触发自动修复: $issue"
    
    case "$issue" in
        "ai_fail")
            if [ -x "$BASE_DIR/optimize_ai.sh" ]; then
                log "执行AI优化..."
                "$BASE_DIR/optimize_ai.sh" --apply &>>"$LOG_DIR/auto_fix.log" || true
            fi
            ;;
        "streaming_fail")
            if [ -x "$BASE_DIR/select_youtube_node.sh" ]; then
                log "执行流媒体优化..."
                "$BASE_DIR/select_youtube_node.sh" --apply &>>"$LOG_DIR/auto_fix.log" || true
            fi
            ;;
        "runtime_issues")
            if [ -x "$PARENT_DIR/script/runtime_guard.sh" ]; then
                log "执行运行时修复..."
                bash "$PARENT_DIR/script/runtime_guard.sh" --auto-fix &>>"$LOG_DIR/auto_fix.log" || true
            fi
            ;;
        "service_down")
            log "尝试重启服务..."
            systemctl --user restart "$SERVICE" || true
            sleep 5
            ;;
    esac
}

# 主检查流程
perform_health_check() {
    local timestamp=$(date +%s)
    local check_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "========================================="
    log "开始网络健康检查: $check_time"
    log "========================================="
    
    # 1. 检查Clash服务
    local service_status="OK"
    if ! check_result=$(check_clash_service); then
        service_status="FAIL"
        alert "CRITICAL" "Clash服务异常"
        trigger_auto_fix "service_down"
        return 1
    fi
    
    # 2. 检查各类服务
    IFS='|' read -r ai_rate ai_latency ai_succ ai_total <<< "$(check_ai_services)"
    IFS='|' read -r dev_rate dev_latency dev_succ dev_total <<< "$(check_dev_services)"
    IFS='|' read -r stream_rate stream_latency stream_succ stream_total <<< "$(check_streaming_services)"
    IFS='|' read -r domestic_rate domestic_latency domestic_succ domestic_total <<< "$(check_domestic_sites)"
    
    # 3. 计算健康分数
    local health_score=$(calculate_health_score \
        "$ai_rate" "$ai_latency" \
        "$dev_rate" "$dev_latency" \
        "$stream_rate" "$stream_latency" \
        "$domestic_rate" "$domestic_latency")
    
    local health_grade=$(get_health_grade "$health_score")
    
    # 4. 输出结果
    log ""
    log "========== 健康检查结果 =========="
    log "总体健康分数: $health_score/100"
    log "健康等级: $health_grade"
    log ""
    log "AI服务:     成功率 ${ai_rate}% | 平均延迟 ${ai_latency}ms"
    log "开发服务:   成功率 ${dev_rate}% | 平均延迟 ${dev_latency}ms"
    log "流媒体服务: 成功率 ${stream_rate}% | 平均延迟 ${stream_latency}ms"
    log "国内网站:   成功率 ${domestic_rate}% | 平均延迟 ${domestic_latency}ms"
    log "================================="
    
    # 5. 保存指标
    cat > "$HEALTH_METRICS" <<EOF
{
  "timestamp": $timestamp,
  "check_time": "$check_time",
  "health_score": $health_score,
  "health_grade": "$health_grade",
  "services": {
    "ai": {
      "success_rate": $ai_rate,
      "avg_latency_ms": $ai_latency,
      "success": $ai_succ,
      "total": $ai_total
    },
    "development": {
      "success_rate": $dev_rate,
      "avg_latency_ms": $dev_latency,
      "success": $dev_succ,
      "total": $dev_total
    },
    "streaming": {
      "success_rate": $stream_rate,
      "avg_latency_ms": $stream_latency,
      "success": $stream_succ,
      "total": $stream_total
    },
    "domestic": {
      "success_rate": $domestic_rate,
      "avg_latency_ms": $domestic_latency,
      "success": $domestic_succ,
      "total": $domestic_total
    }
  }
}
EOF
    
    # 6. 检测问题并告警
    if [ "$health_score" -lt "$MIN_HEALTH_SCORE" ]; then
        alert "CRITICAL" "网络健康分数过低: $health_score/100 ($health_grade)"
        trigger_auto_fix "runtime_issues"
    fi
    
    if [ "$ai_rate" -lt 50 ]; then
        alert "WARNING" "AI服务成功率过低: ${ai_rate}%"
        trigger_auto_fix "ai_fail"
    fi
    
    if [ "$stream_rate" -lt 50 ]; then
        alert "WARNING" "流媒体服务成功率过低: ${stream_rate}%"
        trigger_auto_fix "streaming_fail"
    fi
    
    if [ "$ai_latency" -gt "$LATENCY_CRITICAL" ]; then
        alert "WARNING" "AI服务延迟过高: ${ai_latency}ms"
    fi
    
    if [ "$domestic_rate" -lt 80 ]; then
        alert "WARNING" "国内网站访问异常: 成功率 ${domestic_rate}%"
    fi
    
    log "健康检查完成"
    echo "$health_score"
}

# 生成详细报告
generate_report() {
    log "生成详细健康报告..." >&2
    
    local report_file="$LOG_DIR/health_report_$(date +%Y%m%d_%H%M%S).md"
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$report_file" <<EOFTEMPLATE
# 网络健康监控报告

**生成时间**: $current_time

## 概览

EOFTEMPLATE
    
    if [ -f "$HEALTH_METRICS" ]; then
        if have jq; then
            local health_score=$(jq -r '.health_score // "未知"' "$HEALTH_METRICS")
            local health_grade=$(jq -r '.health_grade // "未知"' "$HEALTH_METRICS")
            
            echo "**健康分数**: $health_score/100" >> "$report_file"
            echo "**健康等级**: $health_grade" >> "$report_file"
            echo "" >> "$report_file"
            echo "## 服务详情" >> "$report_file"
            echo "" >> "$report_file"
            
            for service in ai development streaming domestic; do
                local service_upper=$(echo $service | tr '[:lower:]' '[:upper:]')
                local success_rate=$(jq -r ".services.$service.success_rate // 0" "$HEALTH_METRICS")
                local avg_latency=$(jq -r ".services.$service.avg_latency_ms // 0" "$HEALTH_METRICS")
                local success=$(jq -r ".services.$service.success // 0" "$HEALTH_METRICS")
                local total=$(jq -r ".services.$service.total // 0" "$HEALTH_METRICS")
                
                echo "### $service_upper" >> "$report_file"
                echo "- 成功率: ${success_rate}%" >> "$report_file"
                echo "- 平均延迟: ${avg_latency}ms" >> "$report_file"
                echo "- 成功/总数: ${success}/${total}" >> "$report_file"
                echo "" >> "$report_file"
            done
        else
            echo "**注意**: 需要安装jq工具以显示详细数据" >> "$report_file"
        fi
    else
        echo "**注意**: 尚未进行健康检查，请先运行健康检查" >> "$report_file"
    fi
    
    echo "## 最近告警" >> "$report_file"
    echo "" >> "$report_file"
    echo '```' >> "$report_file"
    tail -n 20 "$ALERT_LOG" >> "$report_file" 2>/dev/null || echo "无告警记录" >> "$report_file"
    echo '```' >> "$report_file"
    
    echo "" >> "$report_file"
    echo "## 历史趋势" >> "$report_file"
    echo "" >> "$report_file"
    echo '```' >> "$report_file"
    tail -n 50 "$HISTORY_LOG" | grep "健康分数" >> "$report_file" 2>/dev/null || echo "无历史数据" >> "$report_file"
    echo '```' >> "$report_file"
    
    log "报告已生成: $report_file"
    cat "$report_file"
}

# 守护进程模式
daemon_mode() {
    log "启动守护进程模式 (检查间隔: ${CHECK_INTERVAL}秒)"
    
    while true; do
        perform_health_check || true
        log "等待 ${CHECK_INTERVAL} 秒后下次检查..."
        sleep "$CHECK_INTERVAL"
    done
}

# 参数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        --daemon|-d)
            MODE="daemon"
            shift
            ;;
        --auto-fix)
            AUTO_FIX=true
            CHECK_ONLY=false
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            AUTO_FIX=false
            shift
            ;;
        --report|-r)
            REPORT_ONLY=true
            shift
            ;;
        --no-fix)
            AUTO_FIX=false
            shift
            ;;
        --interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            cat <<EOF
网络健康监控工具

用法:
  $0 [选项]

选项:
  --daemon, -d        后台守护模式
    --auto-fix           显式启用自动修复/切换/重启（默认关闭，避免影响 Copilot 连接）
  --check-only        仅检查不修复
  --report, -r        生成详细报告
  --no-fix            禁用自动修复
  --interval SECONDS  设置检查间隔（守护模式）
  -h, --help          显示帮助

示例:
  $0                  # 运行一次检查
    $0 --auto-fix        # 运行一次检查并允许自动修复
  $0 --daemon         # 后台守护模式
  $0 --report         # 生成报告
  $0 --check-only     # 仅检查不修复
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
if $REPORT_ONLY; then
    generate_report
elif [ "$MODE" = "daemon" ]; then
    daemon_mode
else
    perform_health_check
fi
