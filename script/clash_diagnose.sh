#!/usr/bin/env bash
# clash_diagnose.sh  自动化网络 / 代理故障诊断工具
# 目的:
#   1. 一键采集 Clash/Mihomo 服务运行状态、端口监听、控制接口可用性
#   2. 测试 HTTP 代理 / SOCKS5 代理 / 直连 对比
#   3. 检查关键 DIRECT 规则 (1.1.1.1 / 8.8.8.8) 与潜在劫持
#   4. 快速统计最近失败连接、输出修复建议
#   5. 可选 JSON 输出 方便上层工具 / 监控采集
# 用法:
#   bash script/clash_diagnose.sh              # 全量诊断
#   bash script/clash_diagnose.sh --fast       # 精简快速模式 (跳过 dig / traceroute)
#   bash script/clash_diagnose.sh --json       # 结果 JSON
#   clash diag                                 # 通过 clashctl 集成别名
# 退出码:
#   0 = 通过(无关键失败)  1 = 服务/端口/代理重大失败  2 = 部分警告

set -u -o pipefail  # 不用 set -e 以便容忍单项失败继续输出整体报告

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SH="$SCRIPT_DIR/common.sh"
[ -f "$COMMON_SH" ] && { CLASH_LIB_MODE=1 . "$COMMON_SH" 2>/dev/null || true; }

FAST=0
JSON=0
VERBOSE=0
for a in "$@"; do
  case "$a" in
    --fast|-q) FAST=1 ;;
    --json) JSON=1 ;;
    -v|--verbose) VERBOSE=1 ;;
    -h|--help)
      grep -E '^# ' "$0" | sed 's/^# \?//' ; exit 0 ;;
  esac
done

log(){ printf '[diag] %s\n' "$*" >&2; }
dbg(){ [ $VERBOSE -eq 1 ] && log "DEBUG: $*" || true; }

ok(){ printf '\033[32m✔ %s\033[0m\n' "$*"; }
warn(){ printf '\033[33m⚠ %s\033[0m\n' "$*"; }
fail(){ printf '\033[31m✘ %s\033[0m\n' "$*"; }

# 结果累积
STATUS=0   # 最终退出码候选
JSON_KV=() # 键=值 原始

add_json(){ JSON_KV+=("$1=$2"); }

have(){ command -v "$1" >/dev/null 2>&1; }

# 1. 基础文件 / 环境
RUNTIME="${CLASH_CONFIG_RUNTIME:-$HOME/.local/share/clash/runtime.yaml}"
MIXIN="${CLASH_CONFIG_MIXIN:-$HOME/.local/share/clash/mixin.yaml}"
YQ="${BIN_YQ:-$HOME/.local/share/clash/bin/yq}"
KERNEL="${BIN_KERNEL_NAME:-mihomo}"

[ -f "$RUNTIME" ] || { fail "runtime.yaml 缺失: $RUNTIME"; add_json runtime_present false; STATUS=1; }
[ -f "$RUNTIME" ] && { ok "runtime.yaml 存在"; add_json runtime_present true; }

# 2. 服务状态
if systemctl --user is-active "$KERNEL" >/dev/null 2>&1; then
  ok "systemd 服务: $KERNEL 活跃"
  add_json service_active true
else
  fail "systemd 服务: $KERNEL 未运行 (执行 clashon)"; add_json service_active false; STATUS=1
fi

# 3. 端口解析 (mixed-port / external-controller)
MIXED_PORT=$([ -x "$YQ" ] && "$YQ" '.mixed-port // ."port" // 7890' "$RUNTIME" 2>/dev/null || echo 7890)
UI_ADDR=$([ -x "$YQ" ] && "$YQ" '."external-controller" // "127.0.0.1:9090"' "$RUNTIME" 2>/dev/null || echo '127.0.0.1:9090')
UI_PORT=${UI_ADDR##*:}
add_json mixed_port "$MIXED_PORT"; add_json ui_port "$UI_PORT"

LISTEN_HTTP=$(ss -ltn 2>/dev/null | grep -E ":$MIXED_PORT\b" || true)
if [ -n "$LISTEN_HTTP" ]; then ok "监听端口: mixed $MIXED_PORT"; add_json mixed_listen true; else fail "未监听 mixed $MIXED_PORT"; add_json mixed_listen false; STATUS=1; fi
LISTEN_UI=$(ss -ltn 2>/dev/null | grep -E ":$UI_PORT\b" || true)
if [ -n "$LISTEN_UI" ]; then ok "监听端口: ui $UI_PORT"; add_json ui_listen true; else warn "控制端口未监听: $UI_PORT"; add_json ui_listen false; STATUS=$(( STATUS==1?1:2 )); fi

# 4. 控制接口版本
API_BASE="http://127.0.0.1:$UI_PORT"
CTRL_VERSION=$(curl -fsS --max-time 2 "$API_BASE/version" 2>/dev/null || true)
if echo "$CTRL_VERSION" | grep -q '{'; then ok "控制接口可访问"; add_json controller_ok true; else fail "控制接口不可访问"; add_json controller_ok false; STATUS=1; fi

# 5. 代理连通性 (HTTP)
TEST_URL=${TEST_URL:-http://www.gstatic.com/generate_204}
HTTP_CODE=$(curl -o /dev/null -s -w '%{http_code}' --max-time 6 --proxy "http://127.0.0.1:$MIXED_PORT" "$TEST_URL" || echo 000)
if [ "$HTTP_CODE" = 204 ] || [ "$HTTP_CODE" = 200 ]; then ok "HTTP 代理成功 $HTTP_CODE"; add_json http_proxy_ok true; else fail "HTTP 代理失败 code=$HTTP_CODE"; add_json http_proxy_ok false; STATUS=1; fi

# 6. SOCKS5 (使用 curl 支持)
SOCKS_CODE=$(curl -o /dev/null -s -w '%{http_code}' --max-time 8 --socks5-hostname "127.0.0.1:$MIXED_PORT" "$TEST_URL" 2>/dev/null || echo 000)
if [ "$SOCKS_CODE" = 204 ] || [ "$SOCKS_CODE" = 200 ]; then ok "SOCKS5 代理成功 $SOCKS_CODE"; add_json socks_proxy_ok true; else warn "SOCKS5 测试失败 code=$SOCKS_CODE"; add_json socks_proxy_ok false; STATUS=$(( STATUS==1?1:2 )); fi

# 7. 直连对比 (无代理, 不走 127.0.0.1 代理) – 仅测一次
DIRECT_CODE=$(curl -o /dev/null -s -w '%{http_code}' --max-time 6 --noproxy '*' "$TEST_URL" || echo 000)
add_json direct_code "$DIRECT_CODE"
dbg "direct=$DIRECT_CODE proxy=$HTTP_CODE"

# 8. DNS / dig (可选)
if [ $FAST -eq 0 ] && have dig; then
  DIG_OUT=$(dig +timeout=3 +short www.google.com @127.0.0.1 2>/dev/null | head -n1 || true)
  if echo "$DIG_OUT" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+'; then ok "Clash DNS 解析成功 www.google.com -> $DIG_OUT"; add_json dns_ok true; else warn "Clash DNS 解析失败(或未启用)"; add_json dns_ok false; fi
else
  add_json dns_ok skipped
fi

# 9. 关键 DIRECT 规则 / 劫持
RULE_DIR1=$(grep -q 'IP-CIDR,1.1.1.1/32,DIRECT' "$RUNTIME" && echo 1 || echo 0)
RULE_DIR8=$(grep -q 'IP-CIDR,8.8.8.8/32,DIRECT' "$RUNTIME" && echo 1 || echo 0)
HIJACK=$(grep -E 'IP-CIDR,(1.1.1.1|8.8.8.8)/32,.*(PROXY|西瓜加速)' "$RUNTIME" >/dev/null && echo 1 || echo 0)
add_json direct_1_1_1_1 "$RULE_DIR1"; add_json direct_8_8_8_8 "$RULE_DIR8"; add_json hijack "$HIJACK"
[ "$RULE_DIR1" = 1 ] && ok "DIRECT 规则存在 1.1.1.1" || warn "缺失 DIRECT 1.1.1.1"
[ "$RULE_DIR8" = 1 ] && ok "DIRECT 规则存在 8.8.8.8" || warn "缺失 DIRECT 8.8.8.8"
[ "$HIJACK" = 0 ] && ok "无关键劫持规则" || { warn "检测到 1.1.1.1/8.8.8.8 劫持 (建议执行 sanitize_runtime.sh)"; STATUS=$(( STATUS==1?1:2 )); }

# 10. 日志失败统计
FAILS_5M_RAW=$(journalctl --user -u "$KERNEL" --since "5 min ago" --no-pager 2>/dev/null | grep -c 'connect error' || true)
# 保障是整数：去除非数字字符，空则置 0
FAILS_5M=$(printf '%s' "${FAILS_5M_RAW:-0}" | tr -cd '0-9')
[ -z "$FAILS_5M" ] && FAILS_5M=0
add_json fails_5m "$FAILS_5M"
if [ "$FAILS_5M" -gt 20 ]; then fail "5分钟连接失败数=$FAILS_5M"; [ $STATUS -eq 0 ] && STATUS=2; elif [ "$FAILS_5M" -gt 5 ]; then warn "5分钟失败数=$FAILS_5M"; [ $STATUS -eq 0 ] && STATUS=2; else ok "5分钟失败数=$FAILS_5M"; fi

# 11. 建议
echo
echo '=== 建议 / Actions ==='
if [ $STATUS -eq 0 ]; then
  ok '整体正常，无需动作'
else
  [ $STATUS -eq 1 ] && echo '关键故障建议:' || echo '次要警告建议:'
  [ "$HTTP_CODE" = 000 ] && echo ' - 检查本机防火墙是否阻断本地 7890 端口 (或端口被修改)' || true
  [ "$CTRL_VERSION" = '' ] && echo ' - external-controller 未监听 (检查 external-controller 设置, 或被占用)' || true
  [ "$RULE_DIR1" = 0 ] && echo ' - 添加 DIRECT 规则: IP-CIDR,1.1.1.1/32,DIRECT,no-resolve' || true
  [ "$RULE_DIR8" = 0 ] && echo ' - 添加 DIRECT 规则: IP-CIDR,8.8.8.8/32,DIRECT,no-resolve' || true
  [ "$HIJACK" = 1 ] && echo ' - 运行: bash script/sanitize_runtime.sh' || true
  [ "$FAILS_5M" -gt 10 ] && echo ' - 执行: clash downgrade  或  重新选择稳定节点' || true
fi

# 12. JSON 输出
if [ $JSON -eq 1 ]; then
  # 组装 JSON 手工 (避免 jq 依赖)
  json_out='{'
  first=1
  for kv in "${JSON_KV[@]}"; do
    k=${kv%%=*}; v=${kv#*=}
    if [ $first -eq 0 ]; then json_out+=","; else first=0; fi
    json_out+="\"$k\":"
    case "$v" in
      true|false|[0-9]*) json_out+="$v" ;;
      *) json_out+="\"$v\"" ;;
    esac
  done
  # append exit_status
  if [ $first -eq 0 ]; then json_out+=","; fi
  json_out+="\"exit_status\":$STATUS}"
  printf '%s\n' "$json_out"
fi

exit $STATUS
