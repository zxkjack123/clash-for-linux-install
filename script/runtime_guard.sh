#!/usr/bin/env bash
# runtime_guard.sh (轻量守护 + 自愈 + 指标)
# 功能:
#   1. 关键结构与规则健康检查 (必须存在 DIRECT 1.1.1.1 与 8.8.8.8; 不应被 PROXY/劫持)
#   2. 异常时可选自动修复: 生成临时副本 -> sanitize -> 验证 -> 原子替换 -> 可选重启
#   3. 输出简单 one-line/JSON 状态 (cron / 监控采集)
#   4. 可选详细报告 (--report) 与外部告警 hook (--alert-cmd)
#   5. 采集锁等待时间 (lock wait) 供主 metrics 汇总; FIXED 视为“最近修复”事件
# 用法:
#   bash runtime_guard.sh --check            # 仅检查, 退出码: 0=OK 1=ISSUE
#   bash runtime_guard.sh --auto-fix         # 发现问题自动修复
#   bash runtime_guard.sh --cron             # 安静模式 (仅一行摘要)
#   bash runtime_guard.sh --check --json     # JSON 输出
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
QUIET=false
WHITELIST_FILE="${CLASH_BASE_DIR:-$HOME/.local/share/clash}/guard_rules_whitelist.txt"
BLACKLIST_FILE="${CLASH_BASE_DIR:-$HOME/.local/share/clash}/guard_rules_blacklist.txt"
BASELINE_REPORT=false
JSON_OUT=false

[ -z "${CLASH_METRICS_FILE:-}" ] && CLASH_METRICS_FILE="$HOME/.local/share/clash/metrics.prom"
CLASH_GUARD_METRICS_FILE="${CLASH_GUARD_METRICS_FILE:-$HOME/.local/share/clash/metrics_guard.prom}"

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

LOCK_FILE="${CLASH_LOCK_FILE:-/tmp/.clash_update.lock}"
LOCK_FD=0

_acquire_lock() {
  local mode="shared"
  $AUTO_FIX && mode="exclusive"
  LOCK_MODE="$mode"
  START_LOCK_ATTEMPT_MS=$(date +%s%3N 2>/dev/null || echo $(($(date +%s)*1000)))
  eval "exec {LOCK_FD}>\"$LOCK_FILE\""
  if [ "$mode" = "exclusive" ]; then
    flock -w 10 -x "$LOCK_FD" || fail "获取独占锁超时: $LOCK_FILE"
  else
    flock -w 10 -s "$LOCK_FD" || fail "获取共享锁超时: $LOCK_FILE"
  fi
  END_LOCK_ACQUIRE_MS=$(date +%s%3N 2>/dev/null || echo $(($(date +%s)*1000)))
  local delta=$((END_LOCK_ACQUIRE_MS-START_LOCK_ATTEMPT_MS))
  LOCK_WAIT_SECONDS=$(awk -v d=$delta 'BEGIN{ printf "%.3f", d/1000 }')
}

_upgrade_to_exclusive() {
  $AUTO_FIX || return 0
  flock -u "$LOCK_FD" 2>/dev/null || true
  flock -w 10 -x "$LOCK_FD" || fail "升级独占锁失败: $LOCK_FILE"
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
    --alert-cmd) ALERT_CMD="$2"; shift 2 ;;
    --quiet) QUIET=true; shift ;;
    --baseline) BASELINE_REPORT=true; shift ;;
    --json) JSON_OUT=true; shift ;;
    -h|--help) sed -n '1,80p' "$0"; exit 0 ;;
    *) echo "[guard] 未知参数: $1" >&2; exit 1 ;;
  esac
done

_acquire_lock

say(){ $QUIET || echo "$*"; }
health_line(){ echo "$*"; }
fail(){ say "[guard][FAIL] $*"; exit 1; }
warn(){ say "[guard][WARN] $*"; }
ok(){ say "[guard][OK] $*"; }


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
  REPORT_FILE="/tmp/runtime_guard_report_${TS}.log"
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
  $CRON_MODE && health_line "GUARD OK $TS" || { $JSON_OUT || ok "健康 (无异常)"; }
  if $JSON_OUT; then
    printf '{"timestamp":"%s","status":"OK","issues":[],"fails_5m":0,"lockMode":"%s","lockWaitSeconds":%s}' "$TS" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"; echo
  fi
  _guard_metrics_write clash_guard_lock_wait_seconds "${LOCK_WAIT_SECONDS:-0}"
  if $BASELINE_REPORT; then
    fails=$(journalctl --user -u "$SERVICE" --since "5 min ago" --no-pager 2>/dev/null | grep -c 'connect error' || echo 0)
    grade=A; [ $fails -gt 5 ] && grade=B; [ $fails -gt 15 ] && grade=C; [ $fails -gt 30 ] && grade=D
    ok "节点失败(5m):$fails 等级:$grade"
    if $JSON_OUT; then
      printf '{"timestamp":"%s","status":"OK","fails_5m":%s,"grade":"%s","lockMode":"%s","lockWaitSeconds":%s}' "$TS" "$fails" "$grade" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"; echo
    fi
  fi
  exit 0
fi

$CRON_MODE && health_line "GUARD ISSUE $TS ${ISSUES[*]}" || { $JSON_OUT || warn "发现问题: ${ISSUES[*]}"; }
if ! $AUTO_FIX; then
  if $JSON_OUT; then
    printf '{"timestamp":"%s","status":"ISSUE","issues":["%s"],"autoFix":false,"lockMode":"%s","lockWaitSeconds":%s}' "$TS" "${ISSUES[*]}" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"; echo
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

grep -q 'IP-CIDR,1.1.1.1/32,DIRECT' "$TMP_FIX" || echo "  - IP-CIDR,1.1.1.1/32,DIRECT,no-resolve" >> "$TMP_FIX"
grep -q 'IP-CIDR,8.8.8.8/32,DIRECT' "$TMP_FIX" || echo "  - IP-CIDR,8.8.8.8/32,DIRECT,no-resolve" >> "$TMP_FIX"

if [ -x "$YQ" ]; then
  "$YQ" '.' "$TMP_FIX" >/dev/null 2>&1 || fail "修复后 YAML 校验失败"
fi

if diff -q "$RUNTIME" "$TMP_FIX" >/dev/null 2>&1; then
  warn "修复生成文件与原文件无差异 (可能竞争条件)"
  rm -f "$TMP_FIX"
  _guard_metrics_write clash_guard_lock_wait_seconds "${LOCK_WAIT_SECONDS:-0}"
  if $JSON_OUT; then
    printf '{"timestamp":"%s","status":"ISSUE","issues":["%s"],"autoFix":true,"note":"no-change" ,"lockMode":"%s","lockWaitSeconds":%s}' "$TS" "${ISSUES[*]}" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"; echo
  fi
  exit 1
fi

mv "$TMP_FIX" "$RUNTIME" || fail "替换 runtime 失败"
systemctl --user restart "$SERVICE" >/dev/null 2>&1 && { $JSON_OUT || ok "已自愈并重启"; } || { $JSON_OUT || warn "重启失败, 请手动检查"; }
[ -n "$ALERT_CMD" ] && eval "$ALERT_CMD" >/dev/null 2>&1 || true

_guard_metrics_write clash_guard_last_fix_timestamp "$(date +%s)"
_guard_metrics_write clash_guard_lock_wait_seconds "${LOCK_WAIT_SECONDS:-0}"

$CRON_MODE && health_line "GUARD FIXED $TS" || { $JSON_OUT || ok "完成自愈"; }
[ -n "$REPORT_FILE" ] && ok "报告: $REPORT_FILE"
if $JSON_OUT; then
  printf '{"timestamp":"%s","status":"FIXED","issues":["%s"],"autoFix":true,"lockMode":"%s","lockWaitSeconds":%s}' "$TS" "${ISSUES[*]}" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"; echo
fi
exit 0
  rm -f "$TMP_FIX"
