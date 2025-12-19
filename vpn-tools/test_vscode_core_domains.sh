#!/usr/bin/env bash
# VS Code 核心域名连通性成功率对比（DIRECT vs 代理）
#
# 目的：在“落实 DIRECT 规则”之前，快速比较直连与代理的可用性与延迟。
# 注意：这里把 401/403/404 也视为“可达”，因为它们通常表示目标可访问但需要鉴权/路径不存在。

set -uo pipefail

PROXY="${PROXY:-http://127.0.0.1:7890}"
N="${N:-10}"
DIRECT_CONNECT_TIMEOUT="${DIRECT_CONNECT_TIMEOUT:-3}"
DIRECT_MAX_TIME="${DIRECT_MAX_TIME:-5}"
PROXY_CONNECT_TIMEOUT="${PROXY_CONNECT_TIMEOUT:-3}"
PROXY_MAX_TIME="${PROXY_MAX_TIME:-7}"

_usage() {
  cat <<'EOF'
Usage:
  PROXY=http://127.0.0.1:7890 N=10 bash vpn-tools/test_vscode_core_domains.sh

Env:
  PROXY                  HTTP proxy URL (default: http://127.0.0.1:7890)
  N                      Attempts per target per mode (default: 10)
  DIRECT_CONNECT_TIMEOUT Seconds (default: 3)
  DIRECT_MAX_TIME        Seconds (default: 5)
  PROXY_CONNECT_TIMEOUT  Seconds (default: 3)
  PROXY_MAX_TIME         Seconds (default: 7)

Exit codes:
  0  All targets direct/proxy completed
  1  Some target had 0 successful attempts in either mode
EOF
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  _usage
  exit 0
fi

case "$N" in
  ''|*[!0-9]*) echo "N must be an integer, got: $N" >&2; exit 2;;
  0) echo "N must be >= 1" >&2; exit 2;;
esac

ok_code() {
  local code="$1"
  case "$code" in
    2??|3??|401|403|404) return 0;;
    *) return 1;;
  esac
}

probe() {
  local mode="$1" url="$2"
  local code time

  if [ "$mode" = proxy ]; then
    read -r code time < <(
      curl -sS -o /dev/null -w "%{http_code} %{time_total}" \
        --proxy "$PROXY" \
        --connect-timeout "$PROXY_CONNECT_TIMEOUT" \
        --max-time "$PROXY_MAX_TIME" \
        "$url" 2>/dev/null \
        || echo "000 ${PROXY_MAX_TIME}.000"
    )
  else
    read -r code time < <(
      curl -sS -o /dev/null -w "%{http_code} %{time_total}" \
        --connect-timeout "$DIRECT_CONNECT_TIMEOUT" \
        --max-time "$DIRECT_MAX_TIME" \
        "$url" 2>/dev/null \
        || echo "000 ${DIRECT_MAX_TIME}.000"
    )
  fi

  echo "$code $time"
}

percentile_line() {
  # p: 1..99, file already sorted numeric, n is total lines.
  local p="$1" file="$2" n="$3"
  local idx=$(( (p*n + 99) / 100 ))
  [ "$idx" -lt 1 ] && idx=1
  [ "$idx" -gt "$n" ] && idx="$n"
  sed -n "${idx}p" "$file" 2>/dev/null || echo "na"
}

summary_one() {
  local name="$1" url="$2"

  echo
  echo "== $name =="
  echo "URL: $url"

  for mode in direct proxy; do
    local ok=0 fail=0
    local times codes p50 p95 topcodes

    times=$(mktemp) || { echo "mktemp failed" >&2; return 1; }
    codes=$(mktemp) || { rm -f "$times"; echo "mktemp failed" >&2; return 1; }

    for i in $(seq 1 "$N" 2>/dev/null || true); do
      read -r c t < <(probe "$mode" "$url")
      echo "$t" >> "$times"
      echo "$c" >> "$codes"
      if ok_code "$c"; then ok=$((ok+1)); else fail=$((fail+1)); fi
    done

    sort -n "$times" -o "$times" 2>/dev/null || true
    p50=$(percentile_line 50 "$times" "$N")
    p95=$(percentile_line 95 "$times" "$N")
    topcodes=$(sort "$codes" 2>/dev/null | uniq -c | sort -nr | head -n 3 | tr "\n" ";" | sed 's/;$/\n/' 2>/dev/null || echo "")

    printf "%-6s ok=%d/%d fail=%d p50=%ss p95=%ss codes=%s" \
      "$mode" "$ok" "$N" "$fail" "${p50:-na}" "${p95:-na}" "$topcodes"

    rm -f "$times" "$codes"
  done
}

# 选择尽量“稳定且轻量”的探测 URL：
# - update API: 返回 200 并且体积小
# - marketplace 首页: 返回 200
# - gallery publisher endpoint: 可能返回 404，但可用于验证连通性（可达即可）
TARGETS=(
  "update.code.visualstudio.com|https://update.code.visualstudio.com/api/update/linux-x64/stable/latest"
  "marketplace.visualstudio.com|https://marketplace.visualstudio.com/"
  "*.gallery.vsassets.io|https://ms-python.gallery.vsassets.io/_apis/public/gallery/publishers/ms-python"
)

rc=0
for item in "${TARGETS[@]}"; do
  name=${item%%|*}
  url=${item#*|}
  summary_one "$name" "$url" || rc=1
  echo

done

echo "Hint: If DIRECT consistently beats PROXY here, adding targeted DIRECT rules for these domains is usually safe."
exit "$rc"
