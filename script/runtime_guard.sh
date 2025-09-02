#!/usr/bin/env bash
# runtime_guard.sh
# P1/P2: 守护 + 自愈 + 报警 (轻量)
# 功能:
#   1. 结构与关键规则健康检查 (必含 DIRECT 1.1.1.1 与 8.8.8.8, 不含被劫持 proxy 规则)
#   2. 若发现异常 -> 运行 sanitize_runtime.sh --file 临时副本 -> 验证 -> 原子替换 -> 可选重启
#   3. 产生健康状态行, 可供 cron/systemd timer 收集
#   4. 可选 --report 生成详尽报告文件
#   5. 可选 --alert-cmd "<cmd>" 当发生修复动作时执行通知 (hook)
# 用法:
#   bash runtime_guard.sh --check          # 仅检查 (退出码 0=ok 1=warn/need-fix)
#   bash runtime_guard.sh --auto-fix       # 检查并自动修复
#   bash runtime_guard.sh --cron           # 静默输出 one-line 状态 (为 cron 设计)
#   bash runtime_guard.sh --auto-fix --alert-cmd 'notify-send "Clash runtime 修复"'
# 设计原则:
#   - 幂等, 避免无差别写入导致频繁重启
#   - 失败回滚: 临时文件替换失败不破坏现有 runtime

set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SH="$BASE_DIR/common.sh"
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

# 全局锁: 与更新/合并进程共享, 避免 runtime.yaml 并发写入
# 约定: 检查模式获得共享锁(-s); 自动修复需要独占锁(-x)
LOCK_FILE="${CLASH_LOCK_FILE:-/tmp/.clash_update.lock}"
LOCK_FD=0

_acquire_lock() {
  # 打开锁文件 (创建如不存在)
  # AUTO_FIX 使用独占锁; 否则使用共享锁
  local mode="shared"
  $AUTO_FIX && mode="exclusive"
  LOCK_MODE="$mode"
  # 记录开始等待时间 (毫秒)
  START_LOCK_ATTEMPT_MS=$(date +%s%3N 2>/dev/null || date +%s000)
  # shellcheck disable=SC3028
  eval "exec {LOCK_FD}>\"$LOCK_FILE\""
  if [ "$mode" = "exclusive" ]; then
    flock -w 10 -x "$LOCK_FD" || fail "获取独占锁超时: $LOCK_FILE"
  else
    flock -w 10 -s "$LOCK_FD" || fail "获取共享锁超时: $LOCK_FILE"
  fi
  END_LOCK_ACQUIRE_MS=$(date +%s%3N 2>/dev/null || date +%s000)
  local delta=$((END_LOCK_ACQUIRE_MS-START_LOCK_ATTEMPT_MS))
  # 计算秒 (保留 3 位)
  LOCK_WAIT_SECONDS=$(awk -v d=$delta 'BEGIN{ printf "%.3f", d/1000 }')
}

_upgrade_to_exclusive() {
  # 若初始为共享锁但后续需要修复 (理论上 AUTO_FIX 只会在启动就决定), 处理升级
  $AUTO_FIX || return 0
  # 已经是独占锁就无需动作; 简化: 直接尝试转换 (部分 flock 不支持, 采取重新加锁策略)
  # 释放并重新获取独占锁 (窗口很小)
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
    -h|--help)
      sed -n '1,60p' "$0"; exit 0 ;;
    *) echo "[guard] 未知参数: $1" >&2; exit 1 ;;
  esac
done

# 参数解析后获取锁 (根据 AUTO_FIX 决定模式)
_acquire_lock

say(){ $QUIET || echo "$*"; }
health_line(){ echo "$*"; }
fail(){ say "[guard][FAIL] $*"; exit 1; }
warn(){ say "[guard][WARN] $*"; }
ok(){ say "[guard][OK] $*"; }

[ -f "$RUNTIME" ] || fail "runtime 不存在: $RUNTIME"

TS=$(date +%Y%m%d_%H%M%S)
STATUS=0
ISSUES=()

# 读取关键信息
HAS_DIRECT_1=$(grep -E '^ *- IP-CIDR,1.1.1.1/32,DIRECT' "$RUNTIME" || true)
HAS_DIRECT_8=$(grep -E '^ *- IP-CIDR,8.8.8.8/32,DIRECT' "$RUNTIME" || true)
HIJACK=$(grep -E '^ *- IP-CIDR,(1.1.1.1|8.8.8.8)/32,.*(西瓜加速|PROXY|Proxy|proxy).*(no-resolve)?' "$RUNTIME" || true)
# 判断 fallback 是否重新出现裸 IP (信息级)
FALLBACK_IP=$(grep -E '^ *fallback:.*(1.1.1.1|8.8.8.8)' "$RUNTIME" || true)
# 校验 YAML 基本合法性
if [ -x "$YQ" ]; then
  "$YQ" '.' "$RUNTIME" >/dev/null 2>&1 || ISSUES+=("YAML 语法错误")
fi
[ -z "$HAS_DIRECT_1" ] && ISSUES+=("缺失 DIRECT 1.1.1.1")
[ -z "$HAS_DIRECT_8" ] && ISSUES+=("缺失 DIRECT 8.8.8.8")
[ -n "$HIJACK" ] && ISSUES+=("检测到劫持规则")

# 规则白名单/黑名单 (仅文本匹配/正则)
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

if [ ${#ISSUES[@]} -gt 0 ]; then
  STATUS=1
fi

REPORT_FILE=""
if $REPORT; then
  REPORT_FILE="/tmp/runtime_guard_report_${TS}.log"
  {
    echo "# runtime guard report @ $TS"
    echo "file: $RUNTIME"
    echo "issues: ${ISSUES[*]:-none}" 
    echo "--- sample lines ---"
    [ -n "$HIJACK" ] && echo "$HIJACK"
    echo "--- tail rules (last 20) ---"
    grep -E '^ *- ' "$RUNTIME" | tail -n 20 || true
    echo "--- dns.fallback ---"
    grep -E '^ *fallback:' "$RUNTIME" || true
  } > "$REPORT_FILE" 2>/dev/null || true
fi

if [ $STATUS -eq 0 ]; then
  $CRON_MODE && health_line "GUARD OK $TS" || ok "健康 (无异常)"
  if $JSON_OUT; then
    printf '{"timestamp":"%s","status":"OK","issues":[],"fails_5m":0,"lockMode":"%s","lockWaitSeconds":%s}' "$TS" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"
    echo
  fi
  if $BASELINE_REPORT; then
    # 节点可用性基线 (过去 5 分钟失败次数简化)
    fails=$(journalctl --user -u "$SERVICE" --since "5 min ago" --no-pager 2>/dev/null | grep -c 'connect error' || echo 0)
    grade=A
    [ $fails -gt 5 ] && grade=B
    [ $fails -gt 15 ] && grade=C
    [ $fails -gt 30 ] && grade=D
    ok "节点失败(5m):$fails 等级:$grade"
    if $JSON_OUT; then
      printf '{"timestamp":"%s","status":"OK","fails_5m":%s,"grade":"%s","lockMode":"%s","lockWaitSeconds":%s}' "$TS" "$fails" "$grade" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"
      echo
    fi
  fi
  exit 0
fi

# 有异常
$CRON_MODE && health_line "GUARD ISSUE $TS ${ISSUES[*]}" || warn "发现问题: ${ISSUES[*]}"

if ! $AUTO_FIX; then
  if $JSON_OUT; then
  printf '{"timestamp":"%s","status":"ISSUE","issues":["%s"],"autoFix":false,"lockMode":"%s","lockWaitSeconds":%s}' "$TS" "${ISSUES[*]}" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"
    echo
  fi
  exit 1
fi

TMP_FIX="${RUNTIME}.guard.fix.$$"
cp -f "$RUNTIME" "$TMP_FIX" || fail "备份失败"

# 升级到独占锁 (若当前仍为共享)。正常 AUTO_FIX 已经独占, 此处冗余保障
_upgrade_to_exclusive

# 复用 sanitizer (写入临时文件)
if [ -f "$SANITIZER" ]; then
  bash "$SANITIZER" --file "$TMP_FIX" --verbose || warn "sanitizer 返回非零, 继续"
else
  warn "缺失 sanitizer 脚本: $SANITIZER"
fi

# 确保关键 DIRECT 规则存在
grep -q 'IP-CIDR,1.1.1.1/32,DIRECT' "$TMP_FIX" || echo "  - IP-CIDR,1.1.1.1/32,DIRECT,no-resolve" >> "$TMP_FIX"
grep -q 'IP-CIDR,8.8.8.8/32,DIRECT' "$TMP_FIX" || echo "  - IP-CIDR,8.8.8.8/32,DIRECT,no-resolve" >> "$TMP_FIX"

# 验证
if [ -x "$YQ" ]; then
  "$YQ" '.' "$TMP_FIX" >/dev/null 2>&1 || fail "修复后 YAML 校验失败"
fi

# 判断是否实际改变
if diff -q "$RUNTIME" "$TMP_FIX" >/dev/null 2>&1; then
  warn "修复生成文件与原文件无差异 (可能竞争条件)"
  rm -f "$TMP_FIX"
  exit 1
fi

mv "$TMP_FIX" "$RUNTIME" || fail "替换 runtime 失败"
systemctl --user restart "$SERVICE" >/dev/null 2>&1 && ok "已自愈并重启" || warn "重启失败, 请手动检查"
[ -n "$ALERT_CMD" ] && eval "$ALERT_CMD" >/dev/null 2>&1 || true

# 写入 metrics: guard_last_fix_timestamp & guard_lock_wait_seconds
if [ -n "${CLASH_METRICS_FILE:-}" ]; then
  mkdir -p "$(dirname "$CLASH_METRICS_FILE")" 2>/dev/null || true
  { sed -i '/^clash_guard_last_fix_timestamp /d;/^clash_guard_lock_wait_seconds /d' "$CLASH_METRICS_FILE" 2>/dev/null || true; } && true
  echo "clash_guard_last_fix_timestamp $(date +%s)" >>"$CLASH_METRICS_FILE"
  echo "clash_guard_lock_wait_seconds ${LOCK_WAIT_SECONDS:-0}" >>"$CLASH_METRICS_FILE"
fi

$CRON_MODE && health_line "GUARD FIXED $TS" || ok "完成自愈"
[ -n "$REPORT_FILE" ] && ok "报告: $REPORT_FILE"
if $JSON_OUT; then
  printf '{"timestamp":"%s","status":"FIXED","issues":["%s"],"autoFix":true,"lockMode":"%s","lockWaitSeconds":%s}' "$TS" "${ISSUES[*]}" "$LOCK_MODE" "${LOCK_WAIT_SECONDS:-0}"
  echo
fi
exit 0
