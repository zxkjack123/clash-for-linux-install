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

# Fallback to system yq if the bundled path is not available.
if [ ! -x "$YQ_BIN" ] && command -v yq >/dev/null 2>&1; then
  YQ_BIN="$(command -v yq)"
fi

read -r -d '' SCNET_PRIORITY_RULES <<'EOF' || true
DOMAIN,c-1966322474660876290.qdai.scnet.cn,DIRECT
DOMAIN,c-1996024701209694210.szai.scnet.cn,DIRECT
DOMAIN,c-2002916625925693441.szai.scnet.cn,DIRECT
DOMAIN-SUFFIX,qdai.scnet.cn,DIRECT
DOMAIN,api.scnet.cn,DIRECT
DOMAIN-SUFFIX,scnet.cn,DIRECT
DOMAIN-SUFFIX,szai.scnet.cn,DIRECT
EOF

# GitHub Copilot: optional priority routing.
#
# Why this exists:
# - Subscription rules often include broad `DOMAIN-KEYWORD,github,...` or GitHub dev rule-sets.
# - If Copilot-specific domains are not placed early, they may be swallowed by those broad rules.
#
# Strategy:
# - If a proxy-group named "COPILOT" exists, route Copilot domains to it.
# - Otherwise, fall back to DIRECT (safe default).
# - Always place these rules at the top of the rules list.
#
# You can override target group explicitly (must exist), e.g.:
#   CLASH_COPILOT_TARGET="COPILOT" bash script/sanitize_runtime.sh --restart
read -r -d '' COPILOT_PRIORITY_RULES_TEMPLATE <<'EOF' || true
DOMAIN,api.githubcopilot.com,${TARGET}
DOMAIN,api.individual.githubcopilot.com,${TARGET}
DOMAIN-SUFFIX,githubcopilot.com,${TARGET}
DOMAIN,copilot-proxy.githubusercontent.com,${TARGET}
EOF

DRY=false
RESTART=false
VERBOSE=false

# Google Scholar often rate-limits/blocks shared DC egress IPs with
# "We're sorry... automated queries".
# Strategy (safe-by-default):
#   - Only add Scholar rules when we can confirm the target proxy-group exists.
#   - Place them at the top of rules so they override broad DOMAIN-SUFFIX,google.com rules.
# Override target group with: CLASH_GOOGLE_SCHOLAR_TARGET="<group-name>"
CLASH_GOOGLE_SCHOLAR_TARGET="${CLASH_GOOGLE_SCHOLAR_TARGET:-}"

# Override Copilot target group (optional; must exist).
CLASH_COPILOT_TARGET="${CLASH_COPILOT_TARGET:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry) DRY=true; shift ;;
    --restart) RESTART=true; shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
    --file|-f)
      [[ $# -ge 2 ]] || { echo "[ERR] --file/-f 需要一个路径" >&2; exit 1; }
      TARGET_FILE="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,30p' "$0"; exit 0 ;;
    *) echo "[ERR] 未知参数: $1" >&2; exit 1 ;;
  esac
done

log(){ echo "[sanitize] $*"; }
vv(){ $VERBOSE && echo "[debug] $*" >&2 || true; }

[[ -n "$TARGET_FILE" ]] && RUNTIME="$TARGET_FILE"
[[ -f "$RUNTIME" ]] || { echo "[ERR] runtime 不存在: $RUNTIME" >&2; exit 1; }

# Detect a safe Scholar target group (only if yq is available)
GOOGLE_SCHOLAR_TARGET=""
GOOGLE_SCHOLAR_PRIORITY_RULES=""

# Detect a safe Copilot target group (only if yq is available)
COPILOT_TARGET=""
COPILOT_PRIORITY_RULES=""
if [ -x "$YQ_BIN" ]; then
  if [ -n "$CLASH_GOOGLE_SCHOLAR_TARGET" ]; then
    # honor explicit override only if it exists in proxy-groups
    if CLASH_GOOGLE_SCHOLAR_TARGET="$CLASH_GOOGLE_SCHOLAR_TARGET" "$YQ_BIN" -e '((.["proxy-groups"] // []) | map(.name) | contains([strenv(CLASH_GOOGLE_SCHOLAR_TARGET)]))' "$RUNTIME" >/dev/null 2>&1; then
      GOOGLE_SCHOLAR_TARGET="$CLASH_GOOGLE_SCHOLAR_TARGET"
    else
      vv "CLASH_GOOGLE_SCHOLAR_TARGET 指定的分组不存在: $CLASH_GOOGLE_SCHOLAR_TARGET (将忽略)"
    fi
  fi
  if [ -z "$GOOGLE_SCHOLAR_TARGET" ]; then
    # Best-effort auto pick (never guess a non-existent group)
    GOOGLE_SCHOLAR_TARGET=$("$YQ_BIN" -r '
      ((.["proxy-groups"] // []) | map(.name)) as $names |
      if ($names | index("AUTO-SMART")) != null then "AUTO-SMART"
      elif ($names | index("速云梯")) != null then "速云梯"
      elif ($names | index("PROXY")) != null then "PROXY"
      else ""
      end
    ' "$RUNTIME" 2>/dev/null || echo "")
  fi
  if [ -n "$GOOGLE_SCHOLAR_TARGET" ]; then
    # Keep rules minimal/specific to avoid affecting other Google services.
    GOOGLE_SCHOLAR_PRIORITY_RULES=$'DOMAIN,scholar.google.com,'"$GOOGLE_SCHOLAR_TARGET"$'\nDOMAIN-SUFFIX,scholar.googleusercontent.com,'"$GOOGLE_SCHOLAR_TARGET"
  fi

  # Copilot routing:
  # - honor explicit CLASH_COPILOT_TARGET only if the group exists
  # - otherwise prefer a dedicated group named "COPILOT" if present
  # - otherwise default to DIRECT
  if [ -n "$CLASH_COPILOT_TARGET" ]; then
    if CLASH_COPILOT_TARGET="$CLASH_COPILOT_TARGET" "$YQ_BIN" -e '((.["proxy-groups"] // []) | map(.name) | contains([strenv(CLASH_COPILOT_TARGET)]))' "$RUNTIME" >/dev/null 2>&1; then
      COPILOT_TARGET="$CLASH_COPILOT_TARGET"
    else
      vv "CLASH_COPILOT_TARGET 指定的分组不存在: $CLASH_COPILOT_TARGET (将忽略)"
    fi
  fi
  if [ -z "$COPILOT_TARGET" ]; then
    # mikefarah/yq v4 supports map()/contains(), but not jq-style if/index.
    # Keep the decision in bash and only ask yq for an existence boolean.
    if "$YQ_BIN" -e '((.["proxy-groups"] // []) | map(.name) | contains(["COPILOT"]))' "$RUNTIME" >/dev/null 2>&1; then
      COPILOT_TARGET="COPILOT"
    else
      COPILOT_TARGET="DIRECT"
    fi
  fi
  # Materialize template into concrete rule lines.
  if [ -n "$COPILOT_TARGET" ]; then
    # Replace literal "${TARGET}" safely (no regex pitfalls).
    COPILOT_PRIORITY_RULES="${COPILOT_PRIORITY_RULES_TEMPLATE//'${TARGET}'/$COPILOT_TARGET}"
  fi
fi

# Fallback (no yq): try to detect a safe existing group by plain text.
# IMPORTANT: Do not inject a rule referencing a non-existent group (mihomo will fail to start).
if [ -z "$GOOGLE_SCHOLAR_TARGET" ]; then
  if [ -n "$CLASH_GOOGLE_SCHOLAR_TARGET" ] && grep -qF "name: $CLASH_GOOGLE_SCHOLAR_TARGET" "$RUNTIME" 2>/dev/null; then
    GOOGLE_SCHOLAR_TARGET="$CLASH_GOOGLE_SCHOLAR_TARGET"
  else
    for cand in AUTO-SMART 速云梯 PROXY; do
      if grep -qF "name: $cand" "$RUNTIME" 2>/dev/null; then
        GOOGLE_SCHOLAR_TARGET="$cand"
        break
      fi
    done
  fi
fi

# Fallback (no yq): try to detect COPILOT group by plain text.
if [ -z "$COPILOT_TARGET" ]; then
  if [ -n "$CLASH_COPILOT_TARGET" ] && grep -qF "name: $CLASH_COPILOT_TARGET" "$RUNTIME" 2>/dev/null; then
    COPILOT_TARGET="$CLASH_COPILOT_TARGET"
  elif grep -qF 'name: COPILOT' "$RUNTIME" 2>/dev/null; then
    COPILOT_TARGET="COPILOT"
  else
    COPILOT_TARGET="DIRECT"
  fi
fi
if [ -z "$COPILOT_PRIORITY_RULES" ] && [ -n "$COPILOT_TARGET" ]; then
  COPILOT_PRIORITY_RULES="${COPILOT_PRIORITY_RULES_TEMPLATE//'${TARGET}'/$COPILOT_TARGET}"
fi

if [ -z "$GOOGLE_SCHOLAR_PRIORITY_RULES" ] && [ -n "$GOOGLE_SCHOLAR_TARGET" ]; then
  GOOGLE_SCHOLAR_PRIORITY_RULES=$'DOMAIN,scholar.google.com,'"$GOOGLE_SCHOLAR_TARGET"$'\nDOMAIN-SUFFIX,scholar.googleusercontent.com,'"$GOOGLE_SCHOLAR_TARGET"
fi

# 预扫描统计
HIJACK_1=$(grep -E "IP-CIDR,1.1.1.1/32,.*(西瓜加速|PROXY|Proxy|proxy).*no-resolve" -n "$RUNTIME" || true)
HIJACK_8=$(grep -E "IP-CIDR,8.8.8.8/32,.*(西瓜加速|PROXY|Proxy|proxy).*no-resolve" -n "$RUNTIME" || true)
HAS_DIRECT_1=$(grep -E "IP-CIDR,1.1.1.1/32,DIRECT,no-resolve" -n "$RUNTIME" || true)
HAS_DIRECT_8=$(grep -E "IP-CIDR,8.8.8.8/32,DIRECT,no-resolve" -n "$RUNTIME" || true)
FALLBACK_HAS_IP=$(grep -E "^ *fallback:.*(1.1.1.1|8.8.8.8)" -n "$RUNTIME" || true)
HAS_SCHOLAR_RULE=$(grep -E "^ *- +DOMAIN,scholar\\.google\\.com," -n "$RUNTIME" || true)
HAS_COPILOT_RULE=$(grep -E "^ *- +(DOMAIN|DOMAIN-SUFFIX),.*githubcopilot\\.com," -n "$RUNTIME" || true)

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
  if [ -n "$GOOGLE_SCHOLAR_PRIORITY_RULES" ]; then
    [[ -z "$HAS_SCHOLAR_RULE" ]] && echo "将补充(高优先级): DOMAIN,scholar.google.com,${GOOGLE_SCHOLAR_TARGET}"
  else
    echo "提示: 未能确定 Google Scholar 的安全分组 (yq 不可用或缺少可用分组)，将不注入 Scholar 规则"
  fi
  if [ -n "$COPILOT_PRIORITY_RULES" ]; then
    [[ -z "$HAS_COPILOT_RULE" ]] && echo "将补充(高优先级): Copilot 规则 -> ${COPILOT_TARGET}"
  else
    echo "提示: 未生成 Copilot 优先规则（将保持现状）"
  fi
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
      )
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

# GitHub Copilot: ensure Copilot rules are placed before broad GitHub rules.
# Only inject when we can produce a safe rule set (target must be DIRECT or an existing group).
if [ -x "$YQ_BIN" ] && [ -n "$COPILOT_PRIORITY_RULES" ]; then
  # Always operate on an array (some merged configs may omit rules temporarily).
  # IMPORTANT: Do not sort rules here; ordering is how Clash/Mihomo resolves matches.
  PRIORITY_RULES="$COPILOT_PRIORITY_RULES" "$YQ_BIN" -i '
    .rules = (
      ((.rules // []) | map(tostring)) as $rules |
      (
        (strenv(PRIORITY_RULES) | split("\n") | map(select(length > 0)))
          | map(sub("\\r$"; ""))
          | map(select(length > 0))
      ) as $prio |
      (
        ($rules
          | map(
              select((test("^DOMAIN,api\\.githubcopilot\\.com,")) | not)
              | select((test("^DOMAIN,api\\.individual\\.githubcopilot\\.com,")) | not)
              | select((test("^DOMAIN-SUFFIX,githubcopilot\\.com,")) | not)
              | select((test("^DOMAIN,copilot-proxy\\.githubusercontent\\.com,")) | not)
            )
        )
      ) as $rest |
      ($prio + $rest)
    )
  ' "$RUNTIME" 2>/dev/null && MODIFIED=true || true
fi

# Text-only fallback: inject Copilot rules at the top of rules: (if yq isn't available).
if [ ! -x "$YQ_BIN" ] && [ -n "$COPILOT_PRIORITY_RULES" ]; then
  # Remove any existing Copilot rules (regardless of target) to avoid duplicates/conflicts.
  sed -i -E \
    -e '/^\s*-\s*DOMAIN,api\.githubcopilot\.com,/d' \
    -e '/^\s*-\s*DOMAIN,api\.individual\.githubcopilot\.com,/d' \
    -e '/^\s*-\s*DOMAIN-SUFFIX,githubcopilot\.com,/d' \
    -e '/^\s*-\s*DOMAIN,copilot-proxy\.githubusercontent\.com,/d' \
    "$RUNTIME" 2>/dev/null || true

  # Insert right after rules: so it overrides broad GitHub rules.
  if ! grep -qE '^\s*-\s*DOMAIN,api\.githubcopilot\.com,' "$RUNTIME" 2>/dev/null; then
    # sed inserts in reverse order (last inserted appears first); insert bottom-up.
    sed -i "/^rules:/a \\  - DOMAIN,copilot-proxy.githubusercontent.com,${COPILOT_TARGET}" "$RUNTIME" 2>/dev/null || true
    sed -i "/^rules:/a \\  - DOMAIN-SUFFIX,githubcopilot.com,${COPILOT_TARGET}" "$RUNTIME" 2>/dev/null || true
    sed -i "/^rules:/a \\  - DOMAIN,api.individual.githubcopilot.com,${COPILOT_TARGET}" "$RUNTIME" 2>/dev/null || true
    sed -i "/^rules:/a \\  - DOMAIN,api.githubcopilot.com,${COPILOT_TARGET}" "$RUNTIME" 2>/dev/null || true
    MODIFIED=true
  fi
fi

# 修复历史遗留: 某些脚本/手工合并可能把多条规则拼在同一个 list item 里
# 典型症状: "...,DIRECT, DOMAIN,..." 或 "...,DIRECT DOMAIN,..." 导致 mihomo 解析报错
if [ -x "$YQ_BIN" ]; then
  if "$YQ_BIN" -e '.rules? | length > 0' "$RUNTIME" >/dev/null 2>&1; then
    # 1) 修复最常见的边界缺失逗号: ",DIRECT DOMAIN,..." -> ",DIRECT, DOMAIN,..."
    # 2) 若某条规则包含 ", (DOMAIN|IP-CIDR|GEOIP|MATCH)," 作为“第二条规则”的起点，则按 ", " 拆分
    #    (不会误伤正常规则，因为正常规则内部基本不会出现逗号+空格)
    "$YQ_BIN" -i '
      .rules = (
        (.rules // [])
        | map(
            (tostring
              | sub(",DIRECT DOMAIN,"; ",DIRECT, DOMAIN,")
              | sub(",DIRECT DOMAIN-SUFFIX,"; ",DIRECT, DOMAIN-SUFFIX,")
              | sub(",DIRECT DOMAIN-KEYWORD,"; ",DIRECT, DOMAIN-KEYWORD,")
              | sub(",DIRECT DOMAIN-REGEX,"; ",DIRECT, DOMAIN-REGEX,")
              | sub(",DIRECT IP-CIDR,"; ",DIRECT, IP-CIDR,")
              | sub(",DIRECT IP-CIDR6,"; ",DIRECT, IP-CIDR6,")
              | sub(",DIRECT SRC-IP-CIDR,"; ",DIRECT, SRC-IP-CIDR,")
              | sub(",DIRECT DST-PORT,"; ",DIRECT, DST-PORT,")
              | sub(",DIRECT SRC-PORT,"; ",DIRECT, SRC-PORT,")
              | sub(",DIRECT GEOIP,"; ",DIRECT, GEOIP,")
              | sub(",DIRECT PROCESS-NAME,"; ",DIRECT, PROCESS-NAME,")
              | sub(",DIRECT PROCESS-PATH,"; ",DIRECT, PROCESS-PATH,")
              | sub(",DIRECT RULE-SET,"; ",DIRECT, RULE-SET,")
              | sub(",DIRECT MATCH,"; ",DIRECT, MATCH,")
              | split(", ")
            )
          )
        | flatten
        | map(sub("^\\s+"; "") | sub("\\s+$"; ""))
        | map(select(length > 0))
      )
    ' "$RUNTIME" 2>/dev/null && MODIFIED=true || true
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
        (
          (strenv(PRIORITY_RULES) | split("\n") | map(select(length > 0)))
            | map(sub("\\r$"; ""))
            | map(select(length > 0))
        ) as $prio |
        ($prio + ((.rules // []) | reduce .[] as $item (
          [];
          . + (if ($prio | index($item)) then [] else [$item] end)
        )))
      )
    ' "$RUNTIME" 2>/dev/null && MODIFIED=true || true
  fi
fi

# Google Scholar: ensure rules are placed before broad Google suffix rules.
# Only inject when the target proxy-group exists (see auto-detection above).
if [ -x "$YQ_BIN" ] && [ -n "$GOOGLE_SCHOLAR_PRIORITY_RULES" ]; then
  if "$YQ_BIN" -e '.rules? | length > 0' "$RUNTIME" >/dev/null 2>&1; then
    PRIORITY_RULES="$GOOGLE_SCHOLAR_PRIORITY_RULES" "$YQ_BIN" -i '
      .rules = (
        (
          (strenv(PRIORITY_RULES) | split("\n") | map(select(length > 0)))
            | map(sub("\\r$"; ""))
            | map(select(length > 0))
        ) as $prio |
        (
          (.rules // [])
          | map(
              select((test("^DOMAIN,scholar\\.google\\.com,")) | not)
              | select((test("^DOMAIN-SUFFIX,scholar\\.googleusercontent\\.com,")) | not)
            )
        ) as $rest |
        ($prio + $rest)
      )
    ' "$RUNTIME" 2>/dev/null && MODIFIED=true || true
  fi
fi

# Text-only fallback: inject Scholar rules at the top of rules: (if yq isn't available).
if [ ! -x "$YQ_BIN" ] && [ -n "$GOOGLE_SCHOLAR_PRIORITY_RULES" ]; then
  # Remove any existing Scholar rules (regardless of target) to avoid duplicates/conflicts.
  sed -i -E \
    -e '/^\s*-\s*DOMAIN,scholar\.google\.com,/d' \
    -e '/^\s*-\s*DOMAIN-SUFFIX,scholar\.googleusercontent\.com,/d' \
    "$RUNTIME" 2>/dev/null || true

  if ! grep -qE '^\s*-\s*DOMAIN,scholar\.google\.com,' "$RUNTIME" 2>/dev/null; then
    # Insert right after rules: so it overrides broad DOMAIN-SUFFIX,google.com rules.
    sed -i "/^rules:/a \  - DOMAIN-SUFFIX,scholar.googleusercontent.com,${GOOGLE_SCHOLAR_TARGET}" "$RUNTIME" 2>/dev/null || true
    sed -i "/^rules:/a \  - DOMAIN,scholar.google.com,${GOOGLE_SCHOLAR_TARGET}" "$RUNTIME" 2>/dev/null || true
    MODIFIED=true
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

# Re-pin DIRECT IP-CIDR rules to absolute top.
# Rationale: later "priority rules" injections (Copilot/SCNET/Scholar) may prepend other DOMAIN rules,
# which can accidentally push the 1.1.1.1 / 8.8.8.8 safeguards down. Keep them at index 0/1.
if [ -x "$YQ_BIN" ]; then
  if "$YQ_BIN" -e '.rules? | length > 0' "$RUNTIME" >/dev/null 2>&1; then
    # Keep the DIRECT safeguards at index 0/1, but also ensure Copilot rules are immediately
    # after them (still before any subscription rules).
    if [ -n "$COPILOT_PRIORITY_RULES" ]; then
      PRIORITY_RULES="$COPILOT_PRIORITY_RULES" "$YQ_BIN" -i '
        .rules = (
          ((.rules // []) | map(tostring)) as $rules |
          (
            (strenv(PRIORITY_RULES) | split("\n") | map(select(length > 0)))
              | map(sub("\\r$"; ""))
              | map(select(length > 0))
          ) as $prio |
          ["IP-CIDR,1.1.1.1/32,DIRECT,no-resolve","IP-CIDR,8.8.8.8/32,DIRECT,no-resolve"] as $direct |
          (
            ($rules
              | map(
                  # Drop duplicates of the safeguards
                  select(. != "IP-CIDR,1.1.1.1/32,DIRECT,no-resolve")
                  | select(. != "IP-CIDR,8.8.8.8/32,DIRECT,no-resolve")
                  # Drop any existing Copilot rules (regardless of target)
                  | select((test("^DOMAIN,api\\.githubcopilot\\.com,")) | not)
                  | select((test("^DOMAIN,api\\.individual\\.githubcopilot\\.com,")) | not)
                  | select((test("^DOMAIN-SUFFIX,githubcopilot\\.com,")) | not)
                  | select((test("^DOMAIN,copilot-proxy\\.githubusercontent\\.com,")) | not)
                )
            )
          ) as $rest |
          ($direct + $prio + $rest)
        )
      ' "$RUNTIME" 2>/dev/null && MODIFIED=true || true
    else
      "$YQ_BIN" -i '
        .rules = (
          ["IP-CIDR,1.1.1.1/32,DIRECT,no-resolve","IP-CIDR,8.8.8.8/32,DIRECT,no-resolve"] +
          ((.rules // [])
            | map(select(. != "IP-CIDR,1.1.1.1/32,DIRECT,no-resolve" and . != "IP-CIDR,8.8.8.8/32,DIRECT,no-resolve"))
          )
        )
      ' "$RUNTIME" 2>/dev/null && MODIFIED=true || true
    fi
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
