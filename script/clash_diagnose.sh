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

# When JSON mode is enabled, keep stdout clean for machine parsing:
# - human-readable report -> stderr
# - JSON summary -> original stdout (fd 3)
JSON_OUT_FD=1
if [ $JSON -eq 1 ]; then
  exec 3>&1
  exec 1>&2
  JSON_OUT_FD=3
fi

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
# 检查 Tailscale 状态 (Critical for chain proxy)
if command -v tailscale >/dev/null 2>&1; then
    TS_STATUS=$(tailscale status --peers=false 2>/dev/null | head -n 1)
    if echo "$TS_STATUS" | grep -q "offline"; then
        fail "Tailscale 状态: Offline (代理链路断开)"; add_json tailscale_status "offline"; STATUS=1
        echo "  建议: sudo systemctl restart tailscaled"
    else
        ok "Tailscale 状态: Online"
        add_json tailscale_status "online"
    fi
fi

if systemctl --user is-active "$KERNEL" >/dev/null 2>&1; then
  ok "systemd 服务: $KERNEL 活跃"
  add_json service_active true
else
  fail "systemd 服务: $KERNEL 未运行 (执行 clashon)"; add_json service_active false; STATUS=1
fi

# 3. 端口解析 (port / socks-port / mixed-port / external-controller)
# 兼容两种配置：
#   - mixed-port: 同一个端口同时提供 HTTP + SOCKS
#   - port + socks-port: 分离的 HTTP 端口与 SOCKS 端口
HTTP_PORT=$([ -x "$YQ" ] && "$YQ" '."port" // 7890' "$RUNTIME" 2>/dev/null || echo 7890)
SOCKS_PORT=$([ -x "$YQ" ] && "$YQ" '."socks-port" // ""' "$RUNTIME" 2>/dev/null || echo '')
MIXED_PORT=$([ -x "$YQ" ] && "$YQ" '."mixed-port" // ""' "$RUNTIME" 2>/dev/null || echo '')
HTTP_PORT=$(printf '%s' "$HTTP_PORT" | tr -d "\"'" )
SOCKS_PORT=$(printf '%s' "$SOCKS_PORT" | tr -d "\"'" )
MIXED_PORT=$(printf '%s' "$MIXED_PORT" | tr -d "\"'" )

# 实际测试端口：优先 mixed-port，否则分别使用 port / socks-port
HTTP_TEST_PORT=${MIXED_PORT:-$HTTP_PORT}
SOCKS_TEST_PORT=${MIXED_PORT:-$SOCKS_PORT}

UI_ADDR=$([ -x "$YQ" ] && "$YQ" '."external-controller" // "127.0.0.1:9090"' "$RUNTIME" 2>/dev/null || echo '127.0.0.1:9090')
UI_ADDR=$(printf '%s' "$UI_ADDR" | tr -d "\"'")
UI_PORT=${UI_ADDR##*:}
add_json mixed_port "$HTTP_TEST_PORT"; add_json ui_port "$UI_PORT"

# 3.1 安全检查：controller 是否暴露且无鉴权
ALLOW_LAN=$([ -x "$YQ" ] && "$YQ" '."allow-lan" // false' "$RUNTIME" 2>/dev/null || echo false)
ALLOW_LAN=$(printf '%s' "$ALLOW_LAN" | tr -d "\"'" | tr '[:upper:]' '[:lower:]')
SECRET=$([ -x "$YQ" ] && "$YQ" '.secret // ""' "$RUNTIME" 2>/dev/null || echo '')
SECRET=$(printf '%s' "$SECRET" | tr -d "\"'")
add_json allow_lan "$ALLOW_LAN"
add_json controller_secret_set $([ -n "$SECRET" ] && echo true || echo false)

# 判断 controller 是否绑定到非 loopback
CTRL_HOST=${UI_ADDR%%:*}
CTRL_EXPOSED=0
case "$CTRL_HOST" in
  127.0.0.1|localhost) CTRL_EXPOSED=0 ;;
  0.0.0.0|::|\[::\]) CTRL_EXPOSED=1 ;;
  *) CTRL_EXPOSED=1 ;;
esac
add_json controller_exposed $([ $CTRL_EXPOSED -eq 1 ] && echo true || echo false)

LISTEN_HTTP=$(ss -ltn 2>/dev/null | grep -E ":$HTTP_TEST_PORT\b" || true)
if [ -n "$LISTEN_HTTP" ]; then
  if [ -n "$MIXED_PORT" ]; then
    ok "监听端口: mixed $HTTP_TEST_PORT"
  else
    ok "监听端口: http $HTTP_TEST_PORT"
  fi
  add_json mixed_listen true
else
  if [ -n "$MIXED_PORT" ]; then
    fail "未监听 mixed $HTTP_TEST_PORT"
  else
    fail "未监听 http $HTTP_TEST_PORT"
  fi
  add_json mixed_listen false
  STATUS=1
fi

# SOCKS 端口监听（仅在非 mixed-port 且配置了 socks-port 时检查）
if [ -z "$MIXED_PORT" ] && [ -n "$SOCKS_PORT" ]; then
  LISTEN_SOCKS=$(ss -ltn 2>/dev/null | grep -E ":$SOCKS_PORT\b" || true)
  if [ -n "$LISTEN_SOCKS" ]; then
    ok "监听端口: socks $SOCKS_PORT"
  else
    warn "未监听 socks $SOCKS_PORT"
    STATUS=$(( STATUS==1?1:2 ))
  fi
fi
LISTEN_UI=$(ss -ltn 2>/dev/null | grep -E ":$UI_PORT\b" || true)
if [ -n "$LISTEN_UI" ]; then ok "监听端口: ui $UI_PORT"; add_json ui_listen true; else warn "控制端口未监听: $UI_PORT"; add_json ui_listen false; STATUS=$(( STATUS==1?1:2 )); fi

# controller 暴露但无 secret：高风险
if [ $CTRL_EXPOSED -eq 1 ] && [ -z "$SECRET" ]; then
  warn "安全风险：external-controller=$UI_ADDR 且 secret 为空（同网段任意主机可控制 Clash）"
  STATUS=$(( STATUS==1?1:2 ))
elif [ -z "$SECRET" ]; then
  warn "建议：设置 controller secret（推荐：clashctl secret init；或自定义：clashctl secret <token>）"
  STATUS=$(( STATUS==1?1:2 ))
fi

# 4. 控制接口版本
API_BASE="http://127.0.0.1:$UI_PORT"
AUTH_HDR=()
[ -n "$SECRET" ] && AUTH_HDR=(-H "Authorization: Bearer $SECRET")
CTRL_VERSION=$(curl -fsS --max-time 2 "${AUTH_HDR[@]}" "$API_BASE/version" 2>/dev/null || true)
if echo "$CTRL_VERSION" | grep -q '{'; then ok "控制接口可访问"; add_json controller_ok true; else fail "控制接口不可访问"; add_json controller_ok false; STATUS=1; fi

# 5. 代理连通性 (HTTP)
TEST_URL=${TEST_URL:-http://www.gstatic.com/generate_204}
HTTP_CODE=$(curl -o /dev/null -s -w '%{http_code}' --max-time 6 --proxy "http://127.0.0.1:$HTTP_TEST_PORT" "$TEST_URL" 2>/dev/null || true)
[ -z "$HTTP_CODE" ] && HTTP_CODE=000
if [ "$HTTP_CODE" = 204 ] || [ "$HTTP_CODE" = 200 ]; then ok "HTTP 代理成功 $HTTP_CODE"; add_json http_proxy_ok true; else fail "HTTP 代理失败 code=$HTTP_CODE"; add_json http_proxy_ok false; STATUS=1; fi

# 6. SOCKS5 (使用 curl 支持)
if [ -n "$SOCKS_TEST_PORT" ]; then
  SOCKS_CODE=$(curl -o /dev/null -s -w '%{http_code}' --max-time 8 --socks5-hostname "127.0.0.1:$SOCKS_TEST_PORT" "$TEST_URL" 2>/dev/null || true)
  [ -z "$SOCKS_CODE" ] && SOCKS_CODE=000
  if [ "$SOCKS_CODE" = 204 ] || [ "$SOCKS_CODE" = 200 ]; then
    ok "SOCKS5 代理成功 $SOCKS_CODE"
    add_json socks_proxy_ok true
  else
    warn "SOCKS5 测试失败 code=$SOCKS_CODE (端口=$SOCKS_TEST_PORT)"
    add_json socks_proxy_ok false
    STATUS=$(( STATUS==1?1:2 ))
  fi
else
  warn "SOCKS5 测试跳过：未配置 socks-port 且未启用 mixed-port"
  add_json socks_proxy_ok skipped
  STATUS=$(( STATUS==1?1:2 ))
fi

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

  # 安全提示 (不强制)
  if [ -z "$SECRET" ]; then
    echo ' - 安全建议：为 external-controller 设置 secret（clashctl secret init / clashctl secret <token>），并保持 external-controller 仅监听 127.0.0.1'
  fi
  if [ "$ALLOW_LAN" = true ]; then
    echo ' - 安全建议：allow-lan=true 会让代理端口对局域网可见；若只需本机/容器使用，请评估是否需要收紧'
  fi
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
  printf '%s\n' "$json_out" >&"$JSON_OUT_FD"
fi

exit $STATUS
