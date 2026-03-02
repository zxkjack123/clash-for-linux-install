#!/usr/bin/env bash
# Probe a target URL across nodes in a Clash/Mihomo selector group and pick the best working one.
# Usage:
#   probe_domain_across_nodes.sh <url> [group-name]
# Example:
#   probe_domain_across_nodes.sh https://repo.protonvpn.com/ "西瓜加速"

set -euo pipefail

URL="${1:-}"
GROUP_LABEL="${2:-}"
[ -z "$URL" ] && { echo "Usage: $0 <url> [group-name]" >&2; exit 2; }

# Optional env bootstrap (controller URL + secret)
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
if [[ -f "$SCRIPT_DIR/load_env.sh" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/load_env.sh" 2>/dev/null || true
fi

if declare -F clash_require_cmd >/dev/null 2>&1; then
  clash_require_cmd curl "required for controller/proxy probing"
  clash_optional_cmd jq "optional (better JSON parsing)" || true
  clash_optional_cmd python3 "optional (better URL encoding)" || true
fi

API_BASE="${CLASH_API:-http://127.0.0.1:9090}"

if [[ -z "${GROUP_LABEL:-}" ]] && declare -F clash_pick_selector_group >/dev/null 2>&1; then
  GROUP_LABEL="$(clash_pick_selector_group "西瓜加速" "速云梯" "GLOBAL" "自动选择" "PROXY" 2>/dev/null || true)"
fi
GROUP_LABEL=${GROUP_LABEL:-GLOBAL}

# Read proxy port from runtime if available (for local proxy probing)
PROXY_PORT="7890"
RUNTIME_YAML="$(clash_runtime_file 2>/dev/null || echo "$HOME/.local/share/clash/runtime.yaml")"
yq_bin="$(clash_yq_bin 2>/dev/null || true)"
if [[ -n "$yq_bin" && -f "$RUNTIME_YAML" ]]; then
  PROXY_PORT=$($yq_bin -r '."mixed-port" // .port // 7890' "$RUNTIME_YAML" 2>/dev/null || echo 7890)
fi

AUTH_HDR=()
_hdr="$(clash_auth_header 2>/dev/null || true)"
[[ -n "${_hdr:-}" ]] && AUTH_HDR=(-H "${_hdr}")

have_jq=1
command -v jq >/dev/null 2>&1 || have_jq=0

# URL-encode the group label safely
echo "# Group: $GROUP_LABEL"

group_enc="$GROUP_LABEL"
if declare -F clash_urlencode >/dev/null 2>&1; then
  group_enc=$(clash_urlencode "$GROUP_LABEL")
elif command -v python3 >/dev/null 2>&1; then
  group_enc=$(python3 - "$GROUP_LABEL" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
  )
fi

# Verify controller is reachable
if declare -F clash_api_get >/dev/null 2>&1; then
  clash_api_get "$API_BASE/version" >/dev/null 2>&1 || { echo "[ERR] Clash controller not reachable at $API_BASE" >&2; exit 2; }
else
  curl -fsS --noproxy '*' --connect-timeout 2 --max-time 3 ${AUTH_HDR[@]+"${AUTH_HDR[@]}"} "$API_BASE/version" >/dev/null || { echo "[ERR] Clash controller not reachable at $API_BASE" >&2; exit 2; }
fi

# Fetch group info
if declare -F clash_api_get >/dev/null 2>&1; then
  group_json=$(clash_api_get "$API_BASE/proxies/$group_enc" 2>/dev/null || true)
else
  group_json=$(curl -s --noproxy '*' --connect-timeout 2 --max-time 3 "$API_BASE/proxies/$group_enc" ${AUTH_HDR[@]+"${AUTH_HDR[@]}"} || true)
fi
if [ -z "$group_json" ] || echo "$group_json" | grep -q 'Not Found'; then
  echo "[ERR] Cannot get group $GROUP_LABEL from controller at $API_BASE" >&2
  exit 3
fi

now_name=""
if command -v jq >/dev/null 2>&1; then
  now_name=$(echo "$group_json" | jq -r '.now // ""' 2>/dev/null || echo "")
else
  now_name=$(echo "$group_json" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p' | head -n1)
fi
[ -n "$now_name" ] && echo "# Current: $now_name" || echo "# Current: unknown"

# Collect all nodes
if [ $have_jq -eq 1 ]; then
  mapfile -t ALL_NODES < <(echo "$group_json" | jq -r '.all[]' 2>/dev/null || true)
else
  mapfile -t ALL_NODES < <(echo "$group_json" | sed -n 's/.*"all":\[\(.*\)\].*/\1/p' | tr ',' '\n' | sed 's/[\[\]"]//g;s/^ *//;s/ *$//' || true)
fi

if [ ${#ALL_NODES[@]} -eq 0 ]; then
  echo "[ERR] No nodes found in group" >&2
  exit 4
fi

# Filter out non-node selectors and system labels
filtered=()
for n in "${ALL_NODES[@]}"; do
  case "$n" in
    *自动选择*|*故障转移*|*剩余流量*|*套餐到期*|★*|🈴*) continue;;
  esac
  filtered+=("$n")
done

limit=25
test_nodes=("${filtered[@]:0:$limit}")
echo "# Candidates: ${#test_nodes[@]} (showing first $limit)"
printf '  - %s\n' "${test_nodes[@]}" | sed -n '1,20p'

best_name=""
best_time="9999.000"

json_payload() {
  local name="$1"
  if [ $have_jq -eq 1 ]; then
    jq -n --arg n "$name" '{name:$n}'
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$name" <<'PY'
import sys, json
print(json.dumps({"name": sys.argv[1]}))
PY
  else
    printf '{"name":"%s"}' "$name"
  fi
}

probe() {
  local name="$1"; shift || true
  local data
  data=$(json_payload "$name")
  if declare -F clash_api_put_json >/dev/null 2>&1; then
    clash_api_put_json "$API_BASE/proxies/$group_enc" "$data" >/dev/null 2>&1 || true
  else
    curl -s --noproxy '*' --connect-timeout 2 --max-time 4 -X PUT "$API_BASE/proxies/$group_enc" -H 'Content-Type: application/json' ${AUTH_HDR[@]+"${AUTH_HDR[@]}"} --data "$data" >/dev/null || true
  fi
  sleep 1
  local res code t
  res=$(curl -I -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 6 --max-time 10 --proxy "http://127.0.0.1:${PROXY_PORT}" "$URL" || echo "000,10.000")
  code=${res%%,*}
  t=${res##*,}
  printf '%s,%s,%s\n' "$code" "$t" "$name"
}

printf '\n# Probing %s across nodes (via local proxy 127.0.0.1:%s)\n' "$URL" "$PROXY_PORT"
for n in "${test_nodes[@]}"; do
  out=$(probe "$n")
  code=${out%%,*}
  rest=${out#*,}
  t=${rest%%,*}
  name=${rest#*,}
  printf '[%3s] %ss  %s\n' "$code" "$t" "$name"
  if [[ "$code" =~ ^2[0-9]{2}$ || "$code" =~ ^3[0-9]{2}$ || "$code" == 403 ]]; then
    if awk "BEGIN{exit !($t < $best_time)}" >/dev/null 2>&1; then
      best_time="$t"
      best_name="$name"
    fi
  fi
done

printf '\n# Summary\n'
if [ -n "$best_name" ]; then
  echo "Best working node: $best_name  (time=${best_time}s)"
  data=$(json_payload "$best_name")
  if declare -F clash_api_put_json >/dev/null 2>&1; then
    clash_api_put_json "$API_BASE/proxies/$group_enc" "$data" >/dev/null 2>&1 || true
  else
    curl -s --noproxy '*' --connect-timeout 2 --max-time 4 -X PUT "$API_BASE/proxies/$group_enc" -H 'Content-Type: application/json' ${AUTH_HDR[@]+"${AUTH_HDR[@]}"} --data "$data" >/dev/null || true
  fi
  echo "Applied selection to group: $GROUP_LABEL"
else
  echo "No working node found for $URL via proxy in tested set ($limit)."
  echo "Tip: try direct access (bypass proxy):"
  echo "  curl --noproxy '*' -I --connect-timeout 6 --max-time 10 '$URL'"
fi

exit 0
