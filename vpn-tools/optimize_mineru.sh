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

# URL 编码
urlencode(){
  local raw="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PYEOF'
import sys,urllib.parse
print(urllib.parse.quote(sys.argv[1]))
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

detect_secret(){
  local files=("$HOME/.local/share/clash/runtime.yaml" "resources/config.yaml")
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    local line
    line=$(grep -m1 '^secret:' "$f" 2>/dev/null || true)
    if [ -n "$line" ]; then
      local val
      val=$(echo "$line" | awk -F':' '{print $2}' | awk '{print $1}')
      if [ -n "$val" ]; then SECRET="$val"; return 0; fi
    fi
  done
  return 1
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

if [ -z "$SECRET" ]; then
  detect_secret || { err "未找到控制器 secret, 请使用 --secret 或设置 CLASH_SECRET"; exit 1; }
fi

ENC_GROUP=$(urlencode "$GROUP")
API="http://$CONTROLLER"
group_json=$(curl -s -H "Authorization: Bearer $SECRET" "$API/proxies/$ENC_GROUP" || true)
if [[ "$group_json" == *"Unauthorized"* || -z "$group_json" ]]; then
  err "获取分组失败: $GROUP ($CONTROLLER)"
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

info "开始测试: group=$GROUP controller=$CONTROLLER domains=${TARGET_DOMAINS[*]} 节点数=$(echo "$candidates" | wc -l)"

declare -A NODE_SUCCESS NODE_TIME NODE_DETAIL
RESULT_LINES=""
JSON_ITEMS=""

switch_node(){
  local node="$1"
  curl -s -X PUT -H "Authorization: Bearer $SECRET" -H 'Content-Type: application/json' \
    -d '{"name":"'"$node"'"}' "$API/proxies/$ENC_GROUP" >/dev/null || return 1
  sleep "$SLEEP_AFTER_SWITCH"
  return 0
}

test_domain(){
  local domain="$1"
  local out code ttotal
  out=$(curl -x "http://127.0.0.1:7890" -s -o /dev/null -w '%{http_code},%{time_total}' -m "$TIMEOUT" "https://$domain/" 2>&1 || true)
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

for node in $candidates; do
  switch_node "$node" || { err "切换失败: $node"; continue; }
  local_success=0
  total_time=0
  details=""
  domain_json=""
  for d in "${TARGET_DOMAINS[@]}"; do
    r=$(test_domain "$d")
    code=$(echo "$r" | cut -d',' -f1)
    t=$(echo "$r" | cut -d',' -f2)
    st=$(echo "$r" | cut -d',' -f3)
    total_time=$(awk -v a="$total_time" -v b="$t" 'BEGIN{printf "%.4f", a+b}')
    [ "$st" = OK ] && local_success=$((local_success+1))
    details+="$d:$code(${t}s) "
    domain_json+="{\"domain\":\"$d\",\"code\":$code,\"time\":$t,\"ok\":$( [ "$st" = OK ] && echo true || echo false )},"
  done
  NODE_SUCCESS[$node]=$local_success
  NODE_TIME[$node]=$total_time
  NODE_DETAIL[$node]="$details"
  RESULT_LINES+="$node\t$local_success\t$total_time\t$details\n"
  JSON_ITEMS+="{\"node\":\"$node\",\"success\":$local_success,\"total_time\":$total_time,\"probes\":[${domain_json%,}]},"
  echo "[NODE] $node success=$local_success time=$total_time $details" >&2
done

# 选择最佳
best_node=""
best_success=-1
best_time=999999
while read -r line; do
  [ -z "$line" ] && continue
  n=$(echo "$line" | awk '{print $1}')
  s=$(echo "$line" | awk '{print $2}')
  t=$(echo "$line" | awk '{print $3}')
  if [ "$s" -gt "$best_success" ] || { [ "$s" -eq "$best_success" ] && awk "BEGIN{exit !($t < $best_time)}"; }; then
    best_node="$n"; best_success="$s"; best_time="$t"
  fi
done < <(printf "%s" "$RESULT_LINES")

echo "\n结果表: (节点\t成功数\t总耗时\t详情)";
echo -e "$RESULT_LINES" | sort -k2,2nr -k3,3n | column -t -s $'\t' || echo -e "$RESULT_LINES" | sort -k2,2nr -k3,3n

echo "\n最佳节点: $best_node (success=$best_success total_time=$best_time)"

if [ -n "$best_node" ] && [ "$APPLY" -eq 1 ]; then
  if switch_node "$best_node"; then
    echo "已应用最佳节点: $best_node"
  else
    err "应用最佳节点失败: $best_node"
  fi
fi

if [ "$JSON_OUTPUT" -eq 1 ]; then
  echo "{\"group\":\"$GROUP\",\"domains\":[\"${TARGET_DOMAINS[*]}\"],\"best\":{\"node\":\"$best_node\",\"success\":$best_success,\"total_time\":$best_time},\"results\":[${JSON_ITEMS%,}]}"
fi

if [ -z "$best_node" ] || [ "$best_success" -le 0 ]; then
  [ "$FORCE_CONTINUE" -eq 1 ] && exit 1 || exit 1
fi
exit 0
