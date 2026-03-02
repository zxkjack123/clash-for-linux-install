#!/usr/bin/env bash
# runtime_guard.sh (轻量守护 + 自愈 + 指标)
# 功能:
#   1. 关键结构与规则健康检查 (必须存在 DIRECT 1.1.1.1 与 8.8.8.8; 不应被 PROXY/劫持)
#   2. 异常时可选自动修复: 生成临时副本 -> sanitize -> 验证 -> 原子替换 -> 可选重启
#   3. 输出简单 one-line/JSON 状态 (cron / 监控采集)
#   4. 可选详细报告 (--report) 与外部告警 hook（安全模式：--alert / --alert-script）
#   5. 采集锁等待时间 (lock wait) 供主 metrics 汇总; FIXED 视为“最近修复”事件
# 用法:
#   bash runtime_guard.sh --check                 # 仅检查, 退出码: 0=OK 1=ISSUE
#   bash runtime_guard.sh --auto-fix              # 发现问题自动修复
#   bash runtime_guard.sh --cron                  # 安静模式 (仅一行摘要)
#   bash runtime_guard.sh --check --json          # JSON 输出
#
# 告警:
#   # 白名单模式（推荐）：none|log|notify|webhook|script
#   bash runtime_guard.sh --auto-fix --alert notify
#
#   # 外部脚本告警（推荐）：
#   bash runtime_guard.sh --auto-fix --alert-script /path/to/hook.sh --alert-arg foo --alert-arg bar
#
#   # 不安全兼容模式（默认禁用）：
#   bash runtime_guard.sh --auto-fix --alert-cmd 'echo hi' --allow-unsafe-alert-cmd
# 设计原则:
#   - 幂等: 无差异不写文件不重启
#   - 最小失败面: 修复失败不破坏原 runtime
#   - 锁协调: 与合并/更新使用同一锁文件 (shared vs exclusive)

set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SH="$BASE_DIR/common.sh"
CLASH_LIB_MODE=1
[ -f "$COMMON_SH" ] && . "$COMMON_SH" 2>/dev/null || true

RUNTIME="${CLASH_CONFIG_RUNTIME:-$HOME/.local/share/clash/runtime.yaml}"
YQ="${BIN_YQ:-$HOME/.local/share/clash/bin/yq}"
SERVICE="${BIN_KERNEL_NAME:-mihomo}"
SANITIZER="$BASE_DIR/sanitize_runtime.sh"
MODE="check"
REPORT=false
AUTO_FIX=false
CRON_MODE=false
ALERT_CMD=""
ALERT_MODE="${ALERT_MODE:-none}"   # none|log|notify|webhook|script
ALERT_SCRIPT="${ALERT_SCRIPT:-}"
# ALERT_ARGS: newline-separated args (each line is one arg)
ALERT_ARGS_TEXT="${ALERT_ARGS:-}"
ALERT_ALLOW_UNSAFE_CMD=false
QUIET=false
WHITELIST_FILE="${CLASH_BASE_DIR:-$HOME/.local/share/clash}/guard_rules_whitelist.txt"
BLACKLIST_FILE="${CLASH_BASE_DIR:-$HOME/.local/share/clash}/guard_rules_blacklist.txt"
BASELINE_REPORT=false
JSON_OUT=false

[ -z "${CLASH_METRICS_FILE:-}" ] && CLASH_METRICS_FILE="$HOME/.local/share/clash/metrics.prom"
CLASH_GUARD_METRICS_FILE="${CLASH_GUARD_METRICS_FILE:-$HOME/.local/share/clash/metrics_guard.prom}"
GUARD_STATE_DIR="${CLASH_STATE_DIR:-${XDG_RUNTIME_DIR:-${CLASH_BASE_DIR:-$HOME/.local/share/clash}}}"
mkdir -p "$GUARD_STATE_DIR" 2>/dev/null || true

_guard_metrics_write() {
  # $1 key, $2 value
  local key="$1" val="$2"
  [ -z "$key" ] && return 0
  mkdir -p "$(dirname "$CLASH_GUARD_METRICS_FILE")" 2>/dev/null || true
  if [ -f "$CLASH_GUARD_METRICS_FILE" ]; then
    grep -Ev "^${key} " "$CLASH_GUARD_METRICS_FILE" >"${CLASH_GUARD_METRICS_FILE}.tmp" 2>/dev/null || cp -f "$CLASH_GUARD_METRICS_FILE" "${CLASH_GUARD_METRICS_FILE}.tmp" 2>/dev/null || true
    mv "${CLASH_GUARD_METRICS_FILE}.tmp" "$CLASH_GUARD_METRICS_FILE" 2>/dev/null || true
  else
    : > "$CLASH_GUARD_METRICS_FILE" 2>/dev/null || true
  fi
  echo "${key} ${val}" >> "$CLASH_GUARD_METRICS_FILE" 2>/dev/null || true
}

LOCK_FILE="${CLASH_LOCK_FILE:-${GUARD_STATE_DIR}/.clash_update.lock}"
LOCK_FD=0

# Output helpers.
# In JSON mode, keep stdout machine-readable; send human logs to stderr.
say(){
  $QUIET && return 0
  if $JSON_OUT; then
    echo "$*" >&2
  else
    echo "$*"
  fi
}
health_line(){ echo "$*"; }

json_escape() {
  # Minimal JSON string escape (no surrounding quotes).
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

json_array() {
  # Print a JSON array from args, escaping each string.
  local first=1 item
  printf '['
  for item in "$@"; do
    if [ $first -eq 0 ]; then printf ','; else first=0; fi
    printf '"%s"' "$(json_escape "$item")"
  done
  printf ']'
}

fail(){
  if $JSON_OUT; then
    echo "[guard][FAIL] $*" >&2
  else
    say "[guard][FAIL] $*"
  fi
  exit 1
}
warn(){
  if $JSON_OUT; then
    echo "[guard][WARN] $*" >&2
  else
    say "[guard][WARN] $*"
  fi
}
ok(){
  if $JSON_OUT; then
    echo "[guard][OK] $*" >&2
  else
    say "[guard][OK] $*"
  fi
}

_acquire_lock() {
  local mode="shared"
  $AUTO_FIX && mode="exclusive"
  LOCK_MODE="$mode"
  START_LOCK_ATTEMPT_MS=$(date +%s%3N 2>/dev/null || echo $(($(date +%s)*1000)))
  # Avoid eval here: CLASH_LOCK_FILE is user-controlled and eval would allow injection.
  exec {LOCK_FD}>"$LOCK_FILE"
  if [ "$mode" = "exclusive" ]; then
    if ! flock -w 10 -x "$LOCK_FD"; then
      if $JSON_OUT; then
        printf '{"timestamp":"%s","status":"ERROR","message":"lock-timeout","lockMode":"exclusive","lockFile":"%s"}\n' "$(date +%Y%m%d_%H%M%S)" "$LOCK_FILE"
      fi
      fail "获取独占锁超时: $LOCK_FILE"
    fi
  else
    if ! flock -w 10 -s "$LOCK_FD"; then
      if $JSON_OUT; then
        printf '{"timestamp":"%s","status":"ERROR","message":"lock-timeout","lockMode":"shared","lockFile":"%s"}\n' "$(date +%Y%m%d_%H%M%S)" "$LOCK_FILE"
      fi
      fail "获取共享锁超时: $LOCK_FILE"
    fi
  fi
  END_LOCK_ACQUIRE_MS=$(date +%s%3N 2>/dev/null || echo $(($(date +%s)*1000)))
  local delta=$((END_LOCK_ACQUIRE_MS-START_LOCK_ATTEMPT_MS))
  LOCK_WAIT_SECONDS=$(awk -v d=$delta 'BEGIN{ printf "%.3f", d/1000 }')
}

_upgrade_to_exclusive() {
  $AUTO_FIX || return 0
  [ "${LOCK_MODE:-}" = "exclusive" ] && return 0
  flock -u "$LOCK_FD" 2>/dev/null || true
  if ! flock -w 10 -x "$LOCK_FD"; then
    if $JSON_OUT; then
      printf '{"timestamp":"%s","status":"ERROR","message":"lock-upgrade-failed","lockFile":"%s"}\n' "$(date +%Y%m%d_%H%M%S)" "$LOCK_FILE"
    fi
    fail "升级独占锁失败: $LOCK_FILE"
  fi
  LOCK_MODE="exclusive"
}

_release_lock() { [ "$LOCK_FD" -gt 0 ] && flock -u "$LOCK_FD" 2>/dev/null || true; }
trap _release_lock EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --auto-fix) MODE="auto"; AUTO_FIX=true; shift ;;
    --cron) CRON_MODE=true; QUIET=true; shift ;;
    --report) REPORT=true; shift ;;
    --alert-cmd)
      if [[ $# -lt 2 ]]; then
        echo "[guard] ERROR: --alert-cmd requires a command" >&2
        exit 1
      fi
      # Backward-compat / UNSAFE: only allowed when explicitly enabled.
      ALERT_CMD="$2"; shift 2 ;;
    --allow-unsafe-alert-cmd)
      ALERT_ALLOW_UNSAFE_CMD=true; shift ;;
    --alert)
      if [[ $# -lt 2 ]]; then
        echo "[guard] ERROR: --alert requires one of: none|log|notify|webhook|script" >&2
        exit 1
      fi
      ALERT_MODE="$2"; shift 2 ;;
    --alert-script)
      if [[ $# -lt 2 ]]; then
        echo "[guard] ERROR: --alert-script requires a path" >&2
        exit 1
      fi
      ALERT_MODE="script"
      ALERT_SCRIPT="$2"; shift 2 ;;
    --alert-arg)
      if [[ $# -lt 2 ]]; then
        echo "[guard] ERROR: --alert-arg requires a value" >&2
        exit 1
      fi
      # Preserve exact arg value; do not word-split.
      ALERT_ARGS_TEXT+="${ALERT_ARGS_TEXT:+$'\n'}$2"
      shift 2 ;;
    --quiet) QUIET=true; shift ;;
    --baseline) BASELINE_REPORT=true; shift ;;
    --json) JSON_OUT=true; shift ;;
    -h|--help) sed -n '1,80p' "$0"; exit 0 ;;
    *) echo "[guard] 未知参数: $1" >&2; exit 1 ;;
  esac
done

# If a script is provided via env, assume script mode unless explicitly disabled.
if [[ -n "${ALERT_SCRIPT:-}" && ( -z "${ALERT_MODE:-}" || "${ALERT_MODE}" == "none" ) ]]; then
  ALERT_MODE="script"
fi

_acquire_lock

_build_alert_message() {
  # Keep message short and safe (no secrets).
  local msg
  msg="runtime_guard FIXED: issues=${ISSUES[*]:-unknown} runtime=$RUNTIME service=$SERVICE"
  printf '%s' "$msg"
}

_run_alert_hook() {
  local mode="${ALERT_MODE:-none}"
  local msg
  msg=$(_build_alert_message)

  case "$mode" in
    ''|none)
      return 0
      ;;
    log)
      echo "[guard][ALERT] $msg" >&2
      return 0
      ;;
    notify|webhook)
      # Use the repo's alert tool if present; it can be configured to send desktop/webhook/email.
      local alert_tool
      alert_tool="$BASE_DIR/../vpn-tools/alert_notification.sh"
      if [ -x "$alert_tool" ]; then
        "$alert_tool" WARNING "$msg" >/dev/null 2>&1 || true
        return 0
      fi
      echo "[guard][WARN] alert_notification.sh not found/executable: $alert_tool" >&2
      return 0
      ;;
    script)
      if [[ -z "${ALERT_SCRIPT:-}" ]]; then
        echo "[guard][WARN] ALERT_MODE=script but ALERT_SCRIPT is empty" >&2
        return 0
      fi
      if [[ ! -f "$ALERT_SCRIPT" ]]; then
        echo "[guard][WARN] ALERT_SCRIPT not found: $ALERT_SCRIPT" >&2
        return 0
      fi
      if [[ ! -x "$ALERT_SCRIPT" ]]; then
        echo "[guard][WARN] ALERT_SCRIPT not executable: $ALERT_SCRIPT" >&2
        return 0
      fi

      # Parse newline-separated args safely.
      local -a args=()
      if [[ -n "${ALERT_ARGS_TEXT:-}" ]]; then
        # shellcheck disable=SC2206
        mapfile -t args < <(printf '%s' "$ALERT_ARGS_TEXT")
      fi

      # Provide context via env vars (avoid printing secrets).
      GUARD_TIMESTAMP="$TS" \
      GUARD_STATUS="FIXED" \
      GUARD_RUNTIME="$RUNTIME" \
      GUARD_SERVICE="$SERVICE" \
      GUARD_ISSUES="${ISSUES[*]:-}" \
        "$ALERT_SCRIPT" "${args[@]}" >/dev/null 2>&1 || true
      return 0
      ;;
    *)
      echo "[guard][WARN] Unknown ALERT_MODE: $mode" >&2
      return 0
      ;;
  esac
}


[ -f "$RUNTIME" ] || { if $JSON_OUT; then printf '{"timestamp":"%s","status":"ERROR","message":"runtime missing"}' "$(date +%Y%m%d_%H%M%S)"; echo; fi; fail "runtime 不存在: $RUNTIME"; }

TS=$(date +%Y%m%d_%H%M%S)
STATUS=0
ISSUES=()

HAS_DIRECT_1=$(grep -E '^ *- IP-CIDR,1.1.1.1/32,DIRECT' "$RUNTIME" || true)
HAS_DIRECT_8=$(grep -E '^ *- IP-CIDR,8.8.8.8/32,DIRECT' "$RUNTIME" || true)
HIJACK=$(grep -E '^ *- IP-CIDR,(1.1.1.1|8.8.8.8)/32,.*(西瓜加速|PROXY|Proxy|proxy).*(no-resolve)?' "$RUNTIME" || true)
FALLBACK_IP=$(grep -E '^ *fallback:.*(1.1.1.1|8.8.8.8)' "$RUNTIME" || true)
if [ -x "$YQ" ]; then
  "$YQ" '.' "$RUNTIME" >/dev/null 2>&1 || ISSUES+=("YAML 语法错误")
fi
[ -z "$HAS_DIRECT_1" ] && ISSUES+=("缺失 DIRECT 1.1.1.1")
[ -z "$HAS_DIRECT_8" ] && ISSUES+=("缺失 DIRECT 8.8.8.8")
[ -n "$HIJACK" ] && ISSUES+=("检测到劫持规则")

if [ -f "$BLACKLIST_FILE" ]; then
  while IFS= read -r rx; do
    [[ -z "$rx" || "$rx" =~ ^# ]] && continue
    if grep -Eq "$rx" "$RUNTIME"; then ISSUES+=("命中黑名单:$rx"); fi
  done < "$BLACKLIST_FILE"
fi
if [ -f "$WHITELIST_FILE" ]; then
  while IFS= read -r rx; do
    [[ -z "$rx" || "$rx" =~ ^# ]] && continue
    if ! grep -Eq "$rx" "$RUNTIME"; then ISSUES+=("缺失白名单:$rx"); fi
  done < "$WHITELIST_FILE"
fi

[ ${#ISSUES[@]} -gt 0 ] && STATUS=1

REPORT_FILE=""
if $REPORT; then
  REPORT_FILE="${GUARD_STATE_DIR}/runtime_guard_report_${TS}.log"
  {
    echo "# runtime guard report @ $TS"
    echo "file: $RUNTIME"
    echo "issues: ${ISSUES[*]:-none}"
    echo "--- sample lines ---"
    [ -n "$HIJACK" ] && echo "$HIJACK"
    echo "--- tail rules (last 20) ---"; grep -E '^ *- ' "$RUNTIME" | tail -n 20 || true
    echo "--- dns.fallback ---"; grep -E '^ *fallback:' "$RUNTIME" || true
  } > "$REPORT_FILE" 2>/dev/null || true
fi

if [ $STATUS -eq 0 ]; then
  fails=0
  grade="A"
  if $BASELINE_REPORT; then
    fails=$(journalctl --user -u "$SERVICE" --since "5 min ago" --no-pager 2>/dev/null | grep -c 'connect error' 2>/dev/null || true)
    fails=$(echo "${fails:-0}" | tail -n 1)
    grade=A; [ "$fails" -gt 5 ] && grade=B; [ "$fails" -gt 15 ] && grade=C; [ "$fails" -gt 30 ] && grade=D
  fi

  $CRON_MODE && health_line "GUARD OK $TS" || { $JSON_OUT || ok "健康 (无异常)"; }
  if $JSON_OUT; then
    printf '{"timestamp":"%s","status":"OK","issues":%s,"fails_5m":%s,"grade":"%s","lockMode":"%s","lockWaitSeconds":%s}' \
      "$TS" "$(json_array)" "$fails" "$grade" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"; echo
  fi
  _guard_metrics_write clash_guard_lock_wait_seconds "${LOCK_WAIT_SECONDS:-0}"
  if $BASELINE_REPORT; then
    ok "节点失败(5m):$fails 等级:$grade"
  fi
  exit 0
fi

$CRON_MODE && health_line "GUARD ISSUE $TS ${ISSUES[*]}" || { $JSON_OUT || warn "发现问题: ${ISSUES[*]}"; }
if ! $AUTO_FIX; then
  if $JSON_OUT; then
    printf '{"timestamp":"%s","status":"ISSUE","issues":%s,"autoFix":false,"lockMode":"%s","lockWaitSeconds":%s}' \
      "$TS" "$(json_array "${ISSUES[@]}")" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"; echo
  fi
  _guard_metrics_write clash_guard_lock_wait_seconds "${LOCK_WAIT_SECONDS:-0}"
  exit 1
fi

TMP_FIX="${RUNTIME}.guard.fix.$$"
cp -f "$RUNTIME" "$TMP_FIX" || fail "备份失败"
_upgrade_to_exclusive

if [ -f "$SANITIZER" ]; then
  bash "$SANITIZER" --file "$TMP_FIX" --verbose || warn "sanitizer 返回非零, 继续"
else
  warn "缺失 sanitizer 脚本: $SANITIZER"
fi

if ! grep -q 'IP-CIDR,1.1.1.1/32,DIRECT' "$TMP_FIX"; then
  if [ -x "$YQ" ]; then
    "$YQ" -i '.rules = ((.rules // []) + ["IP-CIDR,1.1.1.1/32,DIRECT,no-resolve"])' "$TMP_FIX" 2>/dev/null || true
  else
    sed -i "/^rules:/a \  - IP-CIDR,1.1.1.1/32,DIRECT,no-resolve" "$TMP_FIX" 2>/dev/null || true
  fi
fi
if ! grep -q 'IP-CIDR,8.8.8.8/32,DIRECT' "$TMP_FIX"; then
  if [ -x "$YQ" ]; then
    "$YQ" -i '.rules = ((.rules // []) + ["IP-CIDR,8.8.8.8/32,DIRECT,no-resolve"])' "$TMP_FIX" 2>/dev/null || true
  else
    sed -i "/^rules:/a \  - IP-CIDR,8.8.8.8/32,DIRECT,no-resolve" "$TMP_FIX" 2>/dev/null || true
  fi
fi

if [ -x "$YQ" ]; then
  "$YQ" '.' "$TMP_FIX" >/dev/null 2>&1 || fail "修复后 YAML 校验失败"
fi

if diff -q "$RUNTIME" "$TMP_FIX" >/dev/null 2>&1; then
  warn "修复生成文件与原文件无差异 (可能竞争条件)"
  rm -f "$TMP_FIX"
  _guard_metrics_write clash_guard_lock_wait_seconds "${LOCK_WAIT_SECONDS:-0}"
  if $JSON_OUT; then
    printf '{"timestamp":"%s","status":"ISSUE","issues":%s,"autoFix":true,"note":"no-change","lockMode":"%s","lockWaitSeconds":%s}' \
      "$TS" "$(json_array "${ISSUES[@]}")" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"; echo
  fi
  exit 1
fi

mv "$TMP_FIX" "$RUNTIME" || fail "替换 runtime 失败"
systemctl --user restart "$SERVICE" >/dev/null 2>&1 && { $JSON_OUT || ok "已自愈并重启"; } || { $JSON_OUT || warn "重启失败, 请手动检查"; }

# Alerts (safe-by-default): prefer --alert/--alert-script or env ALERT_MODE/ALERT_SCRIPT.
_run_alert_hook || true

# Backward-compat UNSAFE hook: only run if explicitly allowed.
if [[ -n "${ALERT_CMD:-}" ]]; then
  if $ALERT_ALLOW_UNSAFE_CMD || [[ "${ALLOW_UNSAFE_ALERT_CMD:-}" == "1" ]]; then
    # Intentionally unsafe; user-supplied string.
    eval "$ALERT_CMD" >/dev/null 2>&1 || true
  else
    warn "检测到 --alert-cmd/ALERT_CMD，但默认已禁用（为安全起见）。如确需使用，请加 --allow-unsafe-alert-cmd 或设置 ALLOW_UNSAFE_ALERT_CMD=1"
  fi
fi

_guard_metrics_write clash_guard_last_fix_timestamp "$(date +%s)"
_guard_metrics_write clash_guard_lock_wait_seconds "${LOCK_WAIT_SECONDS:-0}"

$CRON_MODE && health_line "GUARD FIXED $TS" || { $JSON_OUT || ok "完成自愈"; }
[ -n "$REPORT_FILE" ] && ok "报告: $REPORT_FILE"
if $JSON_OUT; then
  printf '{"timestamp":"%s","status":"FIXED","issues":%s,"autoFix":true,"lockMode":"%s","lockWaitSeconds":%s}' \
    "$TS" "$(json_array "${ISSUES[@]}")" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"; echo
fi
exit 0
