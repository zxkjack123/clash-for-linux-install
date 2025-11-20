#!/usr/bin/env bash
# test_scnet_api.sh
# 使用 SCNET API 进行端到端健康检测，同时验证代理与直连路径。

set -euo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# 自动加载 .env 配置
if [[ -f "$SCRIPT_DIR/load_env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/load_env.sh"
fi

SCNET_BASE_URL=${SCNET_BASE_URL:-https://api.scnet.cn/api/llm/v1/chat/completions}
SCNET_API_KEY=${SCNET_API_KEY:-}
SCNET_MODEL=${SCNET_MODEL:-DeepSeek-R1-671B}
PROXY=${PROXY:-http://127.0.0.1:7890}
RUN_DIRECT=1
RUN_PROXY=1
PAYLOAD_TEMPLATE='{"model":"%s","messages":[{"role":"user","content":"health check"}],"max_tokens":16,"temperature":0.1}'
TIMEOUT=20
QUIET=0

usage(){
  cat <<EOF
SCNET API 连接性测试

用法:
  ./test_scnet_api.sh [选项]

选项:
  --direct-only        仅测试直连
  --proxy-only         仅通过当前代理测试
  --proxy URL          指定代理地址 (默认: ${PROXY})
  --timeout SEC        设置超时时长 (默认: ${TIMEOUT})
  -q, --quiet          精简输出 (仅结果)
  -h, --help           查看帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --direct-only) RUN_PROXY=0; shift;;
    --proxy-only) RUN_DIRECT=0; shift;;
    --proxy) PROXY=$2; shift 2;;
    --timeout) TIMEOUT=$2; shift 2;;
    -q|--quiet) QUIET=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "未知参数: $1" >&2; usage; exit 1;;
  esac
done

[[ -n $SCNET_API_KEY ]] || { echo "[ERROR] 请在 .env 中设置 SCNET_API_KEY" >&2; exit 1; }
[[ -n $SCNET_MODEL ]] || { echo "[ERROR] 请在 .env 中设置 SCNET_MODEL" >&2; exit 1; }

PAYLOAD_JSON=$(printf "$PAYLOAD_TEMPLATE" "$SCNET_MODEL")

call_scnet(){
  local mode=$1 label=$2 proxy_flag=()
  local tmp_resp code time_taken result
  tmp_resp=$(mktemp)

  if [[ $mode == proxy ]]; then
    proxy_flag=(--proxy "$PROXY")
  fi

  if result=$(curl -sS -o"$tmp_resp" -w '%{http_code},%{time_total}' \
      --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+5))" \
      -H "Authorization: Bearer $SCNET_API_KEY" \
      -H 'Content-Type: application/json' \
      --data "$PAYLOAD_JSON" \
      "${proxy_flag[@]}" "$SCNET_BASE_URL" 2>/dev/null); then
    :
  else
    result=${result:-000,$TIMEOUT}
  fi

  IFS=, read -r code time_taken <<< "$result"

  local verdict="FAIL"
  [[ $code =~ ^(20[0-9]|201|2[0-9][0-9]|401|403|405)$ ]] && verdict="OK"

  if [[ $QUIET -eq 0 ]]; then
    echo "[$label] code=$code time=${time_taken:-NA}s verdict=$verdict"
    if [[ -s $tmp_resp ]]; then
      head -n 5 "$tmp_resp" | sed 's/^/    /'
    fi
  else
    echo "$label,$code,$time_taken,$verdict"
  fi

  rm -f "$tmp_resp"

  [[ $verdict == OK ]]
}

RESULT=0

if [[ $RUN_DIRECT -eq 1 ]]; then
  call_scnet direct "Direct" || RESULT=1
fi

if [[ $RUN_PROXY -eq 1 ]]; then
  call_scnet proxy "Proxy($PROXY)" || RESULT=1
fi

if [[ $RESULT -eq 0 ]]; then
  [[ $QUIET -eq 0 ]] && echo "SCNET API 可用 ✅"
else
  echo "SCNET API 检测存在问题 ❌" >&2
fi

exit $RESULT
