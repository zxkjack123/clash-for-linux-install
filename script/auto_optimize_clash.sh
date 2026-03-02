#!/usr/bin/env bash
# 自动优化 Clash 节点 (增强版)
# 流程: 收集节点 -> 过滤公告/提示 -> TCP 握手 -> TLS 快速握手 (trojan/vmess等) -> 计算延迟 -> 选 TopN -> 写入 mixin 的 AUTO-SMART
# 说明:
#   * 默认写入但不执行重启 (避免打断当前会话). 需手动 clashon / clashrestart
#   * --dry / --no-write 仅测试输出不修改文件
#   * 若 mixin 缺失分组会自动创建模板
#   * TLS 失败记为 500000, TCP 失败记为 999999 以便区分
#   * 过滤名称前缀: 剩余流量, 套餐到期, ★, 🈴
# 依赖: yq, bash /dev/tcp, timeout, (可选) openssl
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIXIN="$BASE_DIR/resources/mixin.yaml"
RUNTIME="$HOME/.local/share/clash/runtime.yaml"
YQ_BIN="$HOME/.local/share/clash/bin/yq"

TOP_N=6
CONNECT_TIMEOUT=1
TLS_TIMEOUT=1
RETRY=1
MAX_TEST=60
THRESH_TCP_FAIL=999999
THRESH_TLS_FAIL=500000
FILTER_REGEX='^(剩余流量|套餐到期|★|🈴)'
TMP_RESULT="$(mktemp -t clash_latency.XXXXXX 2>/dev/null || true)"
[ -n "$TMP_RESULT" ] || TMP_RESULT="${XDG_RUNTIME_DIR:-/tmp}/.clash_latency.$$.$RANDOM"
: > "$TMP_RESULT"
trap 'rm -f "$TMP_RESULT" "${TMP_RESULT}.top" 2>/dev/null || true' EXIT INT TERM

APPLY=true
DRY=false
CUSTOM_TOPN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry) DRY=true; APPLY=false; shift ;;
    --no-write) APPLY=false; shift ;;
    --apply) APPLY=true; shift ;;
    -n|--top|--top-n) CUSTOM_TOPN="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
用法: $(basename "$0") [options]
  -n, --top N        Top N (默认 6)
  --dry              仅测试输出, 不写文件
  --no-write         同上
  --apply            强制写入 (默认)
  --help             本帮助
示例: ./$(basename "$0") -n 8 --dry
EOF
      exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$CUSTOM_TOPN" ]] && TOP_N="$CUSTOM_TOPN"

err(){ echo "[ERR] $*" >&2; }
info(){ echo "[INFO] $*"; }

[ -x "$YQ_BIN" ] || { err "缺少 yq: $YQ_BIN"; exit 1; }
[ -f "$RUNTIME" ] || { err "缺少 runtime.yaml: $RUNTIME (先运行 clashon 以生成, 或订阅更新后再试)"; exit 1; }

DELIM='###CLASH###'
mapfile -t ROWS < <(
  "$YQ_BIN" ".proxies[] | select(.type==\"trojan\" or .type==\"vmess\" or .type==\"ss\" or .type==\"hysteria\" or .type==\"tuic\") | (.name|tostring)+\"${DELIM}\"+(.server|tostring)+\"${DELIM}\"+(.port|tostring)" "$RUNTIME" 2>/dev/null \
   | sed 's/^"//;s/"$//' \
   | grep -Ev "$FILTER_REGEX" || true
)
[ ${#ROWS[@]} -gt 0 ] || { err "未找到可测试节点(过滤后为空)"; exit 1; }

> "$TMP_RESULT"
idx=0
for row in "${ROWS[@]}"; do
  name=${row%%${DELIM}*}; rest=${row#*${DELIM}}; server=${rest%%${DELIM}*}; port=${rest##*${DELIM}}
  idx=$((idx+1))
  echo "- 测试 [$idx/${#ROWS[@]}] $name ($server:$port)" >&2
  # TCP
  start_ms=$(date +%s%3N)
  tcp_ok=false
  for r in $(seq 0 $RETRY); do
    if timeout $CONNECT_TIMEOUT bash -c "</dev/tcp/$server/$port" 2>/dev/null; then tcp_ok=true; break; fi
  done
  end_ms=$(date +%s%3N)
  if ! $tcp_ok; then
    printf '%d %s\n' "$THRESH_TCP_FAIL" "$name" >> "$TMP_RESULT"
    echo "  TCP失败 -> 标记 $THRESH_TCP_FAIL" >&2
  else
    base_latency=$((end_ms-start_ms))
    tls_latency=$base_latency
    if command -v openssl >/dev/null 2>&1; then
      tls_start=$(date +%s%3N)
      if timeout $TLS_TIMEOUT openssl s_client -servername "$server" -connect "$server:$port" </dev/null >/dev/null 2>&1; then
        tls_end=$(date +%s%3N); extra=$((tls_end-tls_start)); tls_latency=$(( base_latency + extra ))
      else
        tls_latency=$THRESH_TLS_FAIL
        echo "  TLS握手失败 -> 标记 $THRESH_TLS_FAIL" >&2
      fi
    fi
    printf '%d %s\n' "$tls_latency" "$name" >> "$TMP_RESULT"
  fi
  [ $idx -ge $MAX_TEST ] && break
done

sort -n "$TMP_RESULT" | awk '{ if($1<'"$THRESH_TLS_FAIL"')print; }' | head -n "$TOP_N" > "${TMP_RESULT}.top"
if [ ! -s "${TMP_RESULT}.top" ]; then
  # 回退: 无 TLS 成功 -> 允许 TLS 半失败
  sort -n "$TMP_RESULT" | awk '{ if($1<'"$THRESH_TCP_FAIL"')print; }' | head -n "$TOP_N" > "${TMP_RESULT}.top"
fi
info "Top $TOP_N 节点 (latency | name):"; cat "${TMP_RESULT}.top"

mapfile -t TOPN < <(awk '{ $1=""; sub(/^ /,""); print }' "${TMP_RESULT}.top")

if [ ${#TOPN[@]} -eq 0 ]; then
  err "无可用节点(全部失败) -> 不写入"
  APPLY=false
fi

if $APPLY; then
  ts=$(date +%Y%m%d_%H%M%S)
  cp -f "$MIXIN" "${MIXIN}.bak-${ts}" 2>/dev/null || true
  # 自动创建缺失分组
  "$YQ_BIN" '."proxy-groups"[]?.name' "$MIXIN" 2>/dev/null | grep -q '^AUTO-SMART$' || \
    "$YQ_BIN" -i '."proxy-groups" += [{"name":"AUTO-SMART","type":"select","proxies":[]}]' "$MIXIN"
  "$YQ_BIN" '."proxy-groups"[]?.name' "$MIXIN" 2>/dev/null | grep -q '^西瓜加速$' || \
    "$YQ_BIN" -i '."proxy-groups" += [{"name":"西瓜加速","type":"select","proxies":["AUTO-SMART","DIRECT"]}]' "$MIXIN"

  TOPN_LIST=$(printf '%s\n' "${TOPN[@]}")
  TOPN_LIST="$TOPN_LIST" "$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="AUTO-SMART")).proxies = (strenv(TOPN_LIST) | split("\n") | map(select(length > 0)))' "$MIXIN"
  # 西瓜加速: 去重 + AUTO-SMART 置顶
  "$YQ_BIN" -i '(."proxy-groups"[] | select(.name=="西瓜加速")).proxies |= (["AUTO-SMART"] + ( .[] | select(. != "AUTO-SMART") )) | (."proxy-groups"[] | select(.name=="西瓜加速")).proxies |= (unique)' "$MIXIN" || true
  info "已写入 mixin (未自动重启)。后续手动: clashon 或 clashrestart"
else
  info "未写入 (dry/no-write 模式)。"
fi

info "完成。查看: grep -n AUTO-SMART $MIXIN"
