#!/usr/bin/env bash
# alert_notification.sh
# 目的: 网络监控告警通知系统
# 功能:
#   1. 支持多种通知渠道（桌面通知、邮件、Webhook、日志）
#   2. 告警级别分类（INFO, WARNING, CRITICAL）
#   3. 告警去重和频率限制
#   4. 告警历史记录
#
# 使用方法:
#   ./alert_notification.sh INFO "测试消息"
#   ./alert_notification.sh WARNING "网络延迟过高"
#   ./alert_notification.sh CRITICAL "服务不可用"

set -euo pipefail

ALERT_LEVEL="${1:-INFO}"
ALERT_MESSAGE="${2:-No message provided}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# 配置
ALERT_LOG="$HOME/.local/share/clash/logs/alerts.log"
ALERT_HISTORY="$HOME/.local/share/clash/logs/alert_history.log"
ALERT_CONFIG="$HOME/.local/share/clash/alert_config.conf"
RATE_LIMIT_FILE="$HOME/.local/share/clash/alert_rate_limit.dat"

# 默认配置
ENABLE_DESKTOP_NOTIFICATION=true
ENABLE_LOG=true
ENABLE_WEBHOOK=false
ENABLE_EMAIL=false
WEBHOOK_URL=""
EMAIL_TO=""
RATE_LIMIT_SECONDS=300  # 5分钟内相同告警只发送一次

mkdir -p "$(dirname "$ALERT_LOG")"
touch "$ALERT_LOG" "$ALERT_HISTORY" "$RATE_LIMIT_FILE"

# 加载配置
if [ -f "$ALERT_CONFIG" ]; then
    source "$ALERT_CONFIG" || true
fi

have() { command -v "$1" >/dev/null 2>&1; }

# 告警去重检查
is_rate_limited() {
    local current_time
    current_time=$(date +%s)

    # NOTE:
    # - RATE_LIMIT_FILE uses a simple pipe-delimited format:
    #     level|message|unix_ts
    # - ALERT_MESSAGE may contain regex/meta chars; avoid grep patterns.
    # - ALERT_MESSAGE may contain '|'/newlines; sanitize for the key file.
    local msg_key="$ALERT_MESSAGE"
    msg_key=${msg_key//$'\n'/ }
    msg_key=${msg_key//|/ }

    # Find the latest timestamp for this level+message.
    local last_time=""
    if [[ -s "$RATE_LIMIT_FILE" ]]; then
        last_time=$(awk -F'|' -v lvl="$ALERT_LEVEL" -v msg="$msg_key" '$1==lvl && $2==msg {t=$3} END{print t}' "$RATE_LIMIT_FILE" 2>/dev/null || true)
    fi
    if [[ -n "${last_time:-}" && "$last_time" =~ ^[0-9]+$ ]]; then
        local time_diff=$((current_time - last_time))
        if [ "$time_diff" -lt "$RATE_LIMIT_SECONDS" ]; then
            return 0  # 在频率限制内
        fi
    fi

    # 更新发送时间
    printf '%s|%s|%s\n' "$ALERT_LEVEL" "$msg_key" "$current_time" >> "$RATE_LIMIT_FILE"

    # 清理旧记录（保留最近1小时）
    local cutoff_time=$((current_time - 3600))
    local tmp_file="${RATE_LIMIT_FILE}.tmp"
    awk -F'|' -v cutoff="$cutoff_time" 'NF>=3 && $3 ~ /^[0-9]+$/ && $3 >= cutoff {print}' "$RATE_LIMIT_FILE" > "$tmp_file" 2>/dev/null || true
    if [ -f "$tmp_file" ]; then
        mv -f "$tmp_file" "$RATE_LIMIT_FILE" 2>/dev/null || rm -f "$tmp_file"
    fi

    return 1  # 不在频率限制内
}

# 写入日志
log_alert() {
    if $ENABLE_LOG; then
        echo "[$TIMESTAMP] [$ALERT_LEVEL] $ALERT_MESSAGE" >> "$ALERT_LOG"
        echo "$TIMESTAMP|$ALERT_LEVEL|$ALERT_MESSAGE" >> "$ALERT_HISTORY"
    fi
}

# 桌面通知
send_desktop_notification() {
    if ! $ENABLE_DESKTOP_NOTIFICATION; then
        return 0
    fi
    
    local urgency="normal"
    local icon="dialog-information"
    
    case "$ALERT_LEVEL" in
        CRITICAL)
            urgency="critical"
            icon="dialog-error"
            ;;
        WARNING)
            urgency="normal"
            icon="dialog-warning"
            ;;
        INFO)
            urgency="low"
            icon="dialog-information"
            ;;
    esac
    
    # 尝试多种桌面通知方式
    if have notify-send; then
        notify-send -u "$urgency" -i "$icon" "Clash 网络监控" "$ALERT_MESSAGE" 2>/dev/null || true
    elif have zenity; then
        zenity --notification --text="[$ALERT_LEVEL] $ALERT_MESSAGE" 2>/dev/null || true
    elif have kdialog; then
        kdialog --passivepopup "$ALERT_MESSAGE" 10 2>/dev/null || true
    fi
}

# Webhook通知
send_webhook() {
    if ! $ENABLE_WEBHOOK || [ -z "$WEBHOOK_URL" ]; then
        return 0
    fi
    
    if ! have curl; then
        return 0
    fi
    
    # 构造JSON payload
    local payload=$(cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "level": "$ALERT_LEVEL",
  "message": "$ALERT_MESSAGE",
  "source": "clash-monitor",
  "hostname": "$(hostname)"
}
EOF
)
    
    curl -s -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --connect-timeout 3 \
        --max-time 5 >/dev/null 2>&1 || true
}

# 邮件通知
send_email() {
    if ! $ENABLE_EMAIL || [ -z "$EMAIL_TO" ]; then
        return 0
    fi
    
    if ! have mail && ! have sendmail; then
        return 0
    fi
    
    local subject="[Clash Monitor] $ALERT_LEVEL Alert"
    local body="Time: $TIMESTAMP\nLevel: $ALERT_LEVEL\nMessage: $ALERT_MESSAGE\nHost: $(hostname)"
    
    if have mail; then
        echo -e "$body" | mail -s "$subject" "$EMAIL_TO" 2>/dev/null || true
    elif have sendmail; then
        echo -e "Subject: $subject\n\n$body" | sendmail "$EMAIL_TO" 2>/dev/null || true
    fi
}

# 终端输出（总是启用）
print_alert() {
    local color_reset="\033[0m"
    local color=""
    
    case "$ALERT_LEVEL" in
        CRITICAL)
            color="\033[1;31m"  # 红色加粗
            ;;
        WARNING)
            color="\033[1;33m"  # 黄色加粗
            ;;
        INFO)
            color="\033[1;32m"  # 绿色加粗
            ;;
    esac
    
    echo -e "${color}[ALERT ${ALERT_LEVEL}]${color_reset} $ALERT_MESSAGE"
}

# 主逻辑
main() {
    # 验证告警级别
    case "$ALERT_LEVEL" in
        INFO|WARNING|CRITICAL)
            ;;
        *)
            echo "错误: 无效的告警级别: $ALERT_LEVEL (应为: INFO, WARNING, CRITICAL)"
            exit 1
            ;;
    esac
    
    # 检查频率限制
    if is_rate_limited; then
        # 被限流，只记录到历史，不发送通知
        echo "$TIMESTAMP|$ALERT_LEVEL|$ALERT_MESSAGE|RATE_LIMITED" >> "$ALERT_HISTORY"
        return 0
    fi
    
    # 发送告警
    print_alert
    log_alert
    send_desktop_notification
    send_webhook
    send_email
}

# 配置命令
if [ "${1:-}" = "--config" ]; then
    cat > "$ALERT_CONFIG" <<EOF
# Clash 监控告警配置
# 编辑此文件以自定义告警行为

# 启用桌面通知（需要 notify-send 或 zenity）
ENABLE_DESKTOP_NOTIFICATION=true

# 启用日志记录
ENABLE_LOG=true

# 启用 Webhook 通知
ENABLE_WEBHOOK=false
WEBHOOK_URL=""  # 例如: https://your-webhook-url.com/alert

# 启用邮件通知
ENABLE_EMAIL=false
EMAIL_TO=""  # 例如: admin@example.com

# 告警频率限制（秒）
# 相同告警在此时间内只发送一次
RATE_LIMIT_SECONDS=300
EOF
    echo "配置文件已创建: $ALERT_CONFIG"
    echo "请编辑此文件以自定义告警设置"
    exit 0
fi

# 测试命令
if [ "${1:-}" = "--test" ]; then
    echo "测试告警系统..."
    "$0" INFO "这是一条测试信息"
    sleep 1
    "$0" WARNING "这是一条测试警告"
    sleep 1
    "$0" CRITICAL "这是一条测试严重告警"
    echo "测试完成！请检查桌面通知和日志文件"
    exit 0
fi

# 查看告警历史
if [ "${1:-}" = "--history" ]; then
    if [ -f "$ALERT_HISTORY" ]; then
        echo "最近20条告警历史:"
        tail -n 20 "$ALERT_HISTORY" | column -t -s'|' || tail -n 20 "$ALERT_HISTORY"
    else
        echo "暂无告警历史"
    fi
    exit 0
fi

# 帮助信息
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    cat <<EOF
告警通知系统

用法:
  $0 LEVEL MESSAGE              发送告警
  $0 --config                   创建配置文件
  $0 --test                     测试告警系统
  $0 --history                  查看告警历史
  $0 --help                     显示帮助

告警级别:
  INFO      - 一般信息
  WARNING   - 警告
  CRITICAL  - 严重问题

示例:
  $0 INFO "系统正常运行"
  $0 WARNING "网络延迟过高: 500ms"
  $0 CRITICAL "Clash服务停止"

配置:
  配置文件位于: $ALERT_CONFIG
  运行 --config 创建默认配置
  
支持的通知方式:
  - 终端输出（总是启用）
  - 桌面通知（notify-send/zenity/kdialog）
  - Webhook（POST JSON）
  - 邮件（mail/sendmail）
  - 日志文件

告警去重:
  相同告警在 RATE_LIMIT_SECONDS 内只发送一次
  默认: 300秒（5分钟）
  
日志文件:
  告警日志: $ALERT_LOG
  历史记录: $ALERT_HISTORY
EOF
    exit 0
fi

# 执行主逻辑
main
