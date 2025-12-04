#!/usr/bin/env bash
# 最小运行时清洗脚本 (独立版)
# 目标:
#   1. 移除订阅/合并后遗留的 1.1.1.1 / 8.8.8.8 经由“西瓜加速”或其它非 DIRECT 的 IP-CIDR 劫持规则
#   2. 确保存在高优先级 DIRECT 规则: IP-CIDR,1.1.1.1/32,DIRECT,no-resolve & IP-CIDR,8.8.8.8/32,DIRECT,no-resolve
#   3. 从 dns.fallback 中移除裸 IP 1.1.1.1 / 8.8.8.8 (避免不稳定时造成递归/EOF 震荡)
#   4. 可选 --restart 重启服务 (只在成功修改后)
# 说明:
#   - 优先使用 yq 精准修改; 若缺失则回退到纯文本方式 (不改变除目标外的内容)
#   - 幂等: 重复执行不会产生重复 DIRECT 规则
#   - 仅修改 runtime.yaml，不触及 mixin.yaml (低侵入)
# 用法:
#   bash script/sanitize_runtime.sh          # 执行实际清洗
#   bash script/sanitize_runtime.sh --dry    # 仅查看将要改动
#   bash script/sanitize_runtime.sh --restart  # 清洗后重启 mihomo/clash
#   bash script/sanitize_runtime.sh --verbose  # 输出更多细节
set -eo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SH="$BASE_DIR/common.sh"
if [ -f "$COMMON_SH" ]; then
  # 容忍 common.sh 内使用未定义变量
  . "$COMMON_SH" 2>/dev/null || true
fi

RUNTIME="${CLASH_CONFIG_RUNTIME:-$HOME/.local/share/clash/runtime.yaml}"
TARGET_FILE=""
YQ_BIN="${BIN_YQ:-$HOME/.local/share/clash/bin/yq}"
SERVICE="${BIN_KERNEL_NAME:-mihomo}"

read -r -d '' SCNET_PRIORITY_RULES <<'EOF' || true
DOMAIN,c-1966322474660876290.qdai.scnet.cn,DIRECT
DOMAIN,c-1996024701209694210.szai.scnet.cn,DIRECT
DOMAIN-SUFFIX,qdai.scnet.cn,DIRECT
DOMAIN,api.scnet.cn,DIRECT
DOMAIN-SUFFIX,scnet.cn,DIRECT
DOMAIN-SUFFIX,szai.scnet.cn,DIRECT
EOF

DRY=false
RESTART=false
VERBOSE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry) DRY=true; shift ;;
    --restart) RESTART=true; shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
  --file|-f) TARGET_FILE="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,30p' "$0"; exit 0 ;;
    *) echo "[ERR] 未知参数: $1" >&2; exit 1 ;;
  esac
done

log(){ echo "[sanitize] $*"; }
vv(){ $VERBOSE && echo "[debug] $*" >&2 || true; }

[[ -n "$TARGET_FILE" ]] && RUNTIME="$TARGET_FILE"
[[ -f "$RUNTIME" ]] || { echo "[ERR] runtime 不存在: $RUNTIME" >&2; exit 1; }

# 预扫描统计
HIJACK_1=$(grep -E "IP-CIDR,1.1.1.1/32,.*(西瓜加速|PROXY|Proxy|proxy).*no-resolve" -n "$RUNTIME" || true)
HIJACK_8=$(grep -E "IP-CIDR,8.8.8.8/32,.*(西瓜加速|PROXY|Proxy|proxy).*no-resolve" -n "$RUNTIME" || true)
HAS_DIRECT_1=$(grep -E "IP-CIDR,1.1.1.1/32,DIRECT,no-resolve" -n "$RUNTIME" || true)
HAS_DIRECT_8=$(grep -E "IP-CIDR,8.8.8.8/32,DIRECT,no-resolve" -n "$RUNTIME" || true)
FALLBACK_HAS_IP=$(grep -E "^ *fallback:.*(1.1.1.1|8.8.8.8)" -n "$RUNTIME" || true)

vv "Hijack1: ${HIJACK_1:-<none>}"
vv "Hijack8: ${HIJACK_8:-<none>}"
vv "Direct1: ${HAS_DIRECT_1:-<none>}"
vv "Direct8: ${HAS_DIRECT_8:-<none>}"
vv "FallbackIPs: ${FALLBACK_HAS_IP:-<none>}"

if $DRY; then
  echo "===== DRY-RUN 预览 ====="
  [[ -n "$HIJACK_1$HIJACK_8" ]] && echo "将移除 劫持规则 行:" && echo "$HIJACK_1" "$HIJACK_8"
  [[ -z "$HAS_DIRECT_1" ]] && echo "将补充: IP-CIDR,1.1.1.1/32,DIRECT,no-resolve (置顶)"
  [[ -z "$HAS_DIRECT_8" ]] && echo "将补充: IP-CIDR,8.8.8.8/32,DIRECT,no-resolve (置顶)"
  [[ -n "$FALLBACK_HAS_IP" ]] && echo "将从 dns.fallback 移除裸 IP: 1.1.1.1 / 8.8.8.8"
  [[ -z "$HIJACK_1$HIJACK_8$FALLBACK_HAS_IP" && -n "$HAS_DIRECT_1$HAS_DIRECT_8" ]] && echo "无修改 (已清洁)"
  exit 0
fi

if ! $DRY; then
  BACKUP="${RUNTIME}.bak.$(date +%Y%m%d_%H%M%S)"
  cp -f "$RUNTIME" "$BACKUP"
  log "已备份: $BACKUP"
fi

MODIFIED=false

if [ -x "$YQ_BIN" ]; then
  vv "使用 yq 模式修改"
  set +e
  "$YQ_BIN" -i '
    .rules = (
      ( ["IP-CIDR,1.1.1.1/32,DIRECT,no-resolve","IP-CIDR,8.8.8.8/32,DIRECT,no-resolve"] +
        ((.rules // []) | map(select(. != "IP-CIDR,1.1.1.1/32,西瓜加速,no-resolve" and . != "IP-CIDR,8.8.8.8/32,西瓜加速,no-resolve")))
      ) | unique
    ) |
    .dns.fallback = ((.dns.fallback // []) | map(select(. != "1.1.1.1" and . != "8.8.8.8")))
  ' "$RUNTIME" 2>/dev/null
  RC=$?
  set -e
  if [ $RC -eq 0 ]; then
    MODIFIED=true
  else
    vv "yq 修改失败, 进入文本回退"
  fi
fi

if ! $MODIFIED; then
  vv "文本模式处理"
  TMP="${RUNTIME}.tmp.$$"
  # 删除劫持行 (兼容引号/无引号)
  grep -Ev "IP-CIDR,1.1.1.1/32,西瓜加速,no-resolve|IP-CIDR,8.8.8.8/32,西瓜加速,no-resolve" "$RUNTIME" > "$TMP" || true
  mv "$TMP" "$RUNTIME"
  # fallback 去除裸IP (简易: 不深入解析, 直接替换当前行)
  sed -i -E 's/(fallback:.*)1.1.1.1 */\1/g; s/(fallback:.*)8.8.8.8 */\1/g' "$RUNTIME" || true
  # 若不存在 DIRECT 规则, 插入到 rules: 下第一组列表位置
  if ! grep -q "IP-CIDR,1.1.1.1/32,DIRECT,no-resolve" "$RUNTIME"; then
    sed -i "/^rules:/a \  - IP-CIDR,1.1.1.1/32,DIRECT,no-resolve" "$RUNTIME"
    MODIFIED=true
  fi
  if ! grep -q "IP-CIDR,8.8.8.8/32,DIRECT,no-resolve" "$RUNTIME"; then
    sed -i "/^rules:/a \  - IP-CIDR,8.8.8.8/32,DIRECT,no-resolve" "$RUNTIME"
    MODIFIED=true
  fi
fi

# 优先保持 QDAI/SCNET 相关规则在列表上方, 避免被 DOMAIN-SUFFIX,cn 提前截断
if [ -x "$YQ_BIN" ] && [ -n "$SCNET_PRIORITY_RULES" ]; then
  if "$YQ_BIN" -e '.rules? | length > 0' "$RUNTIME" >/dev/null 2>&1; then
    PRIORITY_RULES="$SCNET_PRIORITY_RULES" "$YQ_BIN" -i '
      .rules = (
        (env(PRIORITY_RULES) | split("\n") | map(select(length > 0))) as $prio |
        ($prio + ((.rules // []) | reduce .[] as $item (
          [];
          . + (if ($prio | index($item)) then [] else [$item] end)
        )))
      )
    ' "$RUNTIME" 2>/dev/null && MODIFIED=true || true
  fi
fi

# 确保 GEOIP / MATCH 规则始终位于自定义规则之后, 避免 mixin 追加的规则被提前 MATCH 截断
if [ -x "$YQ_BIN" ]; then
  if "$YQ_BIN" -e '.rules? | length > 0' "$RUNTIME" >/dev/null 2>&1; then
    "$YQ_BIN" -i '
      .rules = (
        (.rules // []) as $rules |
        ($rules | map(select(test("^GEOIP,")))) as $geos |
        ($rules | map(select(test("^MATCH,")))) as $matches |
        ($rules | map(select((((test("^GEOIP,")) or (test("^MATCH,")))) | not ))) + $geos + $matches
      )
    ' "$RUNTIME" 2>/dev/null && MODIFIED=true || true
  fi
fi

# 变更摘要
NEW_HIJACK=$(grep -E "IP-CIDR,(1.1.1.1|8.8.8.8)/32,西瓜加速,no-resolve" "$RUNTIME" || true)
if [ -n "$NEW_HIJACK" ]; then
  log "警告: 仍检测到残留劫持行 (请手动检查):"; echo "$NEW_HIJACK"
else
  log "已移除劫持规则"
fi

for ip in 1.1.1.1 8.8.8.8; do
  if grep -q "IP-CIDR,${ip}/32,DIRECT,no-resolve" "$RUNTIME"; then
    log "DIRECT 规则存在: ${ip}"
  else
    log "警告: 缺失 DIRECT 规则: ${ip}"
  fi
  if grep -E "^ *fallback:.*${ip}" "$RUNTIME" >/dev/null; then
    log "提示: fallback 仍含 ${ip} (如需彻底移除请编辑 dns.fallback)"
  fi
done

if $RESTART && [ "$RUNTIME" = "${CLASH_CONFIG_RUNTIME:-$HOME/.local/share/clash/runtime.yaml}" ]; then
  log "重启服务: $SERVICE"; systemctl --user restart "$SERVICE" && log "重启完成" || log "重启失败";
fi

log "完成"
