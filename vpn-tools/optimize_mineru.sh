#!/usr/bin/env bash
# optimize_mineru.sh
# 专用于 MinerU / OpenXLab 相关域名 (sso.openxlab.org.cn, mineru.net) 的节点可用性测试与优化脚本。
# 目的：在一个 Selector 分组(默认: 西瓜加速) 内，找出能成功完成 TLS+HTTP 访问目标域的最优节点，并可选自动切换。
#
# 特性:
#  * 枚举分组候选节点 (排除 DIRECT)
#  * 顺序切换测试，每个节点对两个目标域做一次 HTTPS 访问
#  * 记录 HTTP 状态码、总耗时、是否成功 (2xx/3xx 视为成功)
#  * 评分: 先按成功域数量(满分=2)排序，再按总耗时升序
#  * 支持 include / exclude 过滤与数量限制
#  * 可 JSON 输出 (--json) 与自动应用最佳节点 (--apply)
#  * 不因单个节点失败中断
#
# 注意: 如果当前 Clash/Mihomo 规则里已将这些域名标记 DIRECT, 节点切换不会影响结果。
#       若要评估代理链路质量，请临时注释或上移规则优先级，或在单独 profile 中测试。
#
# 依赖: curl, awk, (可选 jq, python3 用于 URL 编码). 未安装 jq 将使用简单解析。
#
# 退出码:
#  0 成功找到节点 (并在请求时可能已切换)
#  1 未找到可用节点 / 控制器访问失败 / 未获取 secret
#  2 参数错误

set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load env (optional) and bootstrap controller/secret (env override -> legacy compat -> runtime.yaml -> default)
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true

clash_env_bootstrap 2>/dev/null || true

GROUP_DEFAULT="西瓜加速"
TARGET_DOMAINS=("sso.openxlab.org.cn" "mineru.net")
CONTROLLER="127.0.0.1:9090"
GROUP="$GROUP_DEFAULT"
LIMIT=""
FILTER_INCLUDE=""
FILTER_EXCLUDE=""
APPLY=0
JSON_OUTPUT=0
TIMEOUT=8
SLEEP_AFTER_SWITCH=0.25
SECRET="${CLASH_SECRET:-}"
FORCE_CONTINUE=0

usage() {
  cat <<EOF
用法: $0 [选项]
  --group NAME            指定代理分组 (默认: $GROUP_DEFAULT)
  --controller HOST:PORT  控制器地址 (默认: $CONTROLLER)
  --limit N               只测试前 N 个节点 (过滤后)
  --include REGEX         仅包含匹配 REGEX 的节点
  --exclude REGEX         排除匹配 REGEX 的节点
  --timeout SEC           每次请求超时 (默认 $TIMEOUT)
  --apply                 测试完自动应用最佳节点
  --json                  附加 JSON 输出
  --domains d1,d2         自定义要测试的域 (逗号分隔)
  --sleep SEC             节点切换后等待 (默认 $SLEEP_AFTER_SWITCH)
  --secret VALUE          指定控制器 secret (覆盖自动探测)
  --force-continue        即使全部失败也输出 JSON/Table (退出码仍 1)
  -h, --help              显示帮助

评分: 按成功域数量降序，其次按总耗时升序。
EOF
}

err(){ echo "[ERR] $*" >&2; }
info(){ echo "[INFO] $*" >&2; }

json_escape_str() {
  # Escape a string for JSON value context (without surrounding quotes).
  local s="${1-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

is_json_number() {
  # Strict JSON number matcher (subset for our use): int/float without exponent.
  # - No leading zeros unless the number is exactly 0 or starts with 0.
  [[ ${1-} =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?$ ]]
}

# URL 编码
urlencode(){
  local raw="$1"
  if declare -F clash_urlencode >/dev/null 2>&1; then
    clash_urlencode "$raw"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$raw" <<'PYEOF'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PYEOF
  else
    local i c out=""
    for ((i=0;i<${#raw};i++)); do
      c=${raw:i:1}
      case $c in [a-zA-Z0-9._~-]) out+="$c" ;; *) printf -v hex '%%%02X' "'${c}"; out+="$hex" ;; esac
    done
    echo "$out"
  fi
}

is_success_code(){ [[ $1 =~ ^[23][0-9][0-9]$ ]]; }

parse_args(){
  while [ $# -gt 0 ]; do
    case "$1" in
      --group) GROUP="$2"; shift 2;;
      --controller) CONTROLLER="$2"; shift 2;;
      --limit) LIMIT="$2"; shift 2;;
      --include) FILTER_INCLUDE="$2"; shift 2;;
      --exclude) FILTER_EXCLUDE="$2"; shift 2;;
      --timeout) TIMEOUT="$2"; shift 2;;
      --apply) APPLY=1; shift;;
      --json) JSON_OUTPUT=1; shift;;
      --domains) IFS=',' read -r -a TARGET_DOMAINS <<< "$2"; shift 2;;
      --sleep) SLEEP_AFTER_SWITCH="$2"; shift 2;;
      --secret) SECRET="$2"; shift 2;;
      --force-continue) FORCE_CONTINUE=1; shift;;
      -h|--help) usage; exit 0;;
      *) err "未知参数: $1"; usage; exit 2;;
    esac
  done
}

parse_args "$@"

# Honor --secret override for this run.
if [ -n "${SECRET:-}" ]; then
  export CLASH_SECRET="$SECRET"
fi

# If secret still unset, try best-effort auto-detect (auth may be disabled).
if [ -z "$SECRET" ] && declare -F clash_detect_secret >/dev/null 2>&1; then
  SECRET="$(clash_detect_secret 2>/dev/null || true)"
fi

ENC_GROUP=$(urlencode "$GROUP")
API="${CLASH_API:-http://$CONTROLLER}"

ctrl_get() {
  if declare -F clash_api_get >/dev/null 2>&1; then
    clash_api_get "$1" 2>/dev/null || true
  else
    curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "$1" 2>/dev/null || true
  fi
}

ctrl_put_json() {
  local url="$1" payload="$2"
  if declare -F clash_api_put_json >/dev/null 2>&1; then
    clash_api_put_json "$url" "$payload" >/dev/null 2>&1 || true
  else
    curl -s --noproxy '*' --connect-timeout 2 --max-time 4 -X PUT -H 'Content-Type: application/json' --data "$payload" "$url" >/dev/null || true
  fi
}

group_json=$(ctrl_get "$API/proxies/$ENC_GROUP")

# If default legacy group missing, try to auto-pick a Selector group.
if { [[ -z "$group_json" ]] || printf '%s' "$group_json" | grep -qiE 'unauthorized|not found'; } && [[ "$GROUP" == "$GROUP_DEFAULT" ]]; then
  if declare -F clash_pick_selector_group >/dev/null 2>&1; then
    picked="$(clash_pick_selector_group "西瓜加速" "速云梯" "GLOBAL" "自动选择" "PROXY" 2>/dev/null || true)"
    if [[ -n "$picked" ]]; then
      GROUP="$picked"
      ENC_GROUP=$(urlencode "$GROUP")
      group_json=$(ctrl_get "$API/proxies/$ENC_GROUP")
    fi
  fi
fi

if [[ -z "$group_json" ]] || printf '%s' "$group_json" | grep -qi 'unauthorized'; then
  err "获取分组失败: $GROUP ($CONTROLLER) (secret may be required)"
  exit 1
fi

extract_nodes(){
  if command -v jq >/dev/null 2>&1; then
    echo "$group_json" | jq -r '.all[]'
  else
    echo "$group_json" | tr '\n' ' ' | sed -n 's/.*"all"\s*:\s*\[\([^]]*\)\].*/\1/p' | tr ',' '\n' | sed 's/"//g'
  fi
}

candidates=$(extract_nodes | grep -v '^DIRECT$' | grep -v '^$' || true)
if [ -n "$FILTER_INCLUDE" ]; then
  candidates=$(echo "$candidates" | grep -E "$FILTER_INCLUDE" || true)
fi
if [ -n "$FILTER_EXCLUDE" ]; then
  candidates=$(echo "$candidates" | grep -Ev "$FILTER_EXCLUDE" || true)
fi
if [ -z "$candidates" ]; then
  err "过滤后无候选节点"
  exit 1
fi
if [ -n "$LIMIT" ]; then
  candidates=$(echo "$candidates" | head -n "$LIMIT")
fi

mapfile -t CANDIDATES < <(printf '%s\n' "$candidates")

info "开始测试: group=$GROUP controller=$CONTROLLER domains=${TARGET_DOMAINS[*]} 节点数=$(echo "$candidates" | wc -l)"

declare -A NODE_SUCCESS NODE_TIME NODE_DETAIL
RESULT_LINES=""
JSON_ITEMS=""

best_node=""
best_success=-1
best_time=""

float_lt(){
  # args: a b  (return 0 when a < b)
  awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 < b+0)}'
}

switch_node(){
  local node="$1"
  ctrl_put_json "$API/proxies/$ENC_GROUP" "{\"name\":\"$(json_escape_str "$node")\"}" || return 1
  sleep "$SLEEP_AFTER_SWITCH"
  return 0
}

test_domain(){
  local domain="$1"
  local out code ttotal
  out=$(curl -x "http://127.0.0.1:7890" -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 4 --max-time "$TIMEOUT" "https://$domain/" 2>/dev/null || echo "000,$TIMEOUT")
  code=${out%%,*}
  ttotal=${out##*,}
  [[ $code =~ ^[0-9]{3}$ ]] || code=000
  [[ -n $ttotal ]] || ttotal=$TIMEOUT
  if is_success_code "$code"; then
    echo "$code,$ttotal,OK"
  else
    echo "$code,$ttotal,FAIL"
  fi
}

for node in "${CANDIDATES[@]}"; do
  switch_node "$node" || { err "切换失败: $node"; continue; }
  local_success=0
  total_time=0
  details=""
  domain_json_items=""
  for d in "${TARGET_DOMAINS[@]}"; do
    r=$(test_domain "$d")
    code=$(echo "$r" | cut -d',' -f1)
    t=$(echo "$r" | cut -d',' -f2)
    st=$(echo "$r" | cut -d',' -f3)
    total_time=$(awk -v a="$total_time" -v b="$t" 'BEGIN{printf "%.4f", a+b}')
    [ "$st" = OK ] && local_success=$((local_success+1))
    details+="$d:$code(${t}s) "
    domain_json_items+="{\"domain\":\"$(json_escape_str "$d")\",\"code\":\"$(json_escape_str "$code")\",\"time\":$t,\"ok\":$( [ "$st" = OK ] && echo true || echo false )},"
  done
  NODE_SUCCESS["$node"]=$local_success
  NODE_TIME["$node"]=$total_time
  NODE_DETAIL["$node"]="$details"
  RESULT_LINES+="$node"$'\t'"$local_success"$'\t'"$total_time"$'\t'"$details"$'\n'
  JSON_ITEMS+="{\"node\":\"$(json_escape_str "$node")\",\"success\":$local_success,\"total_time\":$total_time,\"probes\":[${domain_json_items%,}]},"
  echo "[NODE] $node success=$local_success time=$total_time $details" >&2

  if [ "$local_success" -gt "$best_success" ]; then
    best_node="$node"; best_success="$local_success"; best_time="$total_time"
  elif [ "$local_success" -eq "$best_success" ] && [ -n "$best_time" ] && float_lt "$total_time" "$best_time"; then
    best_node="$node"; best_success="$local_success"; best_time="$total_time"
  elif [ "$local_success" -eq "$best_success" ] && [ -z "$best_time" ]; then
    best_node="$node"; best_success="$local_success"; best_time="$total_time"
  fi
done

echo "\n结果表: (节点\t成功数\t总耗时\t详情)";
printf '%s' "$RESULT_LINES" | sort -t $'\t' -k2,2nr -k3,3n | column -t -s $'\t' || printf '%s' "$RESULT_LINES" | sort -t $'\t' -k2,2nr -k3,3n

echo "\n最佳节点: $best_node (success=$best_success total_time=$best_time)"

if [ -n "$best_node" ] && [ "$APPLY" -eq 1 ]; then
  if switch_node "$best_node"; then
    echo "已应用最佳节点: $best_node"
  else
    err "应用最佳节点失败: $best_node"
  fi
fi

if [ "$JSON_OUTPUT" -eq 1 ]; then
  # Emit strict JSON to stdout.
  printf '{'
  printf '"group":"%s",' "$(json_escape_str "$GROUP")"
  printf '"domains":['
  d_first=1
  for d in "${TARGET_DOMAINS[@]}"; do
    [ $d_first -eq 1 ] || printf ','
    d_first=0
    printf '"%s"' "$(json_escape_str "$d")"
  done
  printf '],'

  # best.total_time: numeric when parseable, otherwise string
  best_time_json="0"
  if [ -n "${best_time:-}" ] && is_json_number "$best_time"; then
    best_time_json="$best_time"
  else
    best_time_json="\"$(json_escape_str "${best_time:-0}")\""
  fi

  printf '"best":{'
  printf '"node":"%s","success":%s,"total_time":%s' \
    "$(json_escape_str "${best_node:-}")" "${best_success:-0}" "$best_time_json"
  printf '},'
  printf '"results":[%s]' "${JSON_ITEMS%,}"
  printf '}'
  printf '\n'
fi

if [ -z "$best_node" ] || [ "$best_success" -le 0 ]; then
  [ "$FORCE_CONTINUE" -eq 1 ] && exit 1 || exit 1
fi
exit 0
