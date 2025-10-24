#!/usr/bin/env bash
# Probe a target URL across nodes in a Clash/Mihomo selector group and pick the best working one.
# Usage:
#   probe_domain_across_nodes.sh <url> [group-name]
# Example:
#   probe_domain_across_nodes.sh https://repo.protonvpn.com/ "西瓜加速"

set -euo pipefail

URL="${1:-}"
GROUP_LABEL="${2:-西瓜加速}"
[ -z "$URL" ] && { echo "Usage: $0 <url> [group-name]" >&2; exit 2; }

API_HOST="127.0.0.1"
API_PORT="9090"
API_BASE="http://${API_HOST}:${API_PORT}"

# Read secret and proxy port from runtime if available
SECRET=""
PROXY_PORT="7890"
RUNTIME_YAML="$HOME/.local/share/clash/runtime.yaml"
if command -v yq >/dev/null 2>&1 && [ -f "$RUNTIME_YAML" ]; then
  SECRET=$(yq -r '.secret // ""' "$RUNTIME_YAML" 2>/dev/null || echo "")
  PROXY_PORT=$(yq -r '."mixed-port" // .port // 7890' "$RUNTIME_YAML" 2>/dev/null || echo 7890)
  # Prefer controller port from external-controller when available
  _ui=$(yq -r '."external-controller" // "127.0.0.1:9090"' "$RUNTIME_YAML" 2>/dev/null || echo "127.0.0.1:9090")
  _port=${_ui##*:}
  if [[ "${_port}" =~ ^[0-9]+$ ]]; then
    API_PORT="${_port}"
    API_BASE="http://${API_HOST}:${API_PORT}"
  fi
fi

AUTH_HDR=()
[ -n "$SECRET" ] && AUTH_HDR=(-H "Authorization: Bearer $SECRET")

have_jq=1
command -v jq >/dev/null 2>&1 || have_jq=0

# URL-encode the group label safely
echo "# Group: $GROUP_LABEL"

group_enc="$GROUP_LABEL"
if command -v python3 >/dev/null 2>&1; then
  group_enc=$(python3 - "$GROUP_LABEL" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
  )
fi

# Verify controller is reachable
if ! curl -s --max-time 2 "$API_BASE/version" >/dev/null; then
  echo "[ERR] Clash controller not reachable at $API_BASE" >&2
  exit 2
fi

# Fetch group info
group_json=$(curl -s --max-time 3 "$API_BASE/proxies/$group_enc" "${AUTH_HDR[@]}" || true)
if [ -z "$group_json" ] || echo "$group_json" | grep -q 'Not Found'; then
  echo "[ERR] Cannot get group $GROUP_LABEL from controller at $API_BASE" >&2
  exit 3
fi

now_name=$(echo "$group_json" | jq -r '.now // ""' 2>/dev/null || echo "")
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
  curl -s -X PUT "$API_BASE/proxies/$group_enc" -H 'Content-Type: application/json' "${AUTH_HDR[@]}" --data "$data" >/dev/null || true
  sleep 1
  local res code t
  res=$(curl -I -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 6 --max-time 10 --proxy "http://127.0.0.1:${PROXY_PORT}" "$URL" || echo "000,10.000")
  code=${res%%,*}
  t=${res##*,}
  printf '[%3s] %ss  %s\n' "$code" "$t" "$name"
  if [[ "$code" =~ ^2[0-9]{2}$ || "$code" =~ ^3[0-9]{2}$ || "$code" == 403 ]]; then
    awk "BEGIN{exit !($t < $best_time)}" >/dev/null 2>&1 && { best_time="$t"; best_name="$name"; }
  fi
}

printf '\n# Probing %s across nodes (via local proxy 127.0.0.1:%s)\n' "$URL" "$PROXY_PORT"
for n in "${test_nodes[@]}"; do
  probe "$n"
done

printf '\n# Summary\n'
if [ -n "$best_name" ]; then
  echo "Best working node: $best_name  (time=${best_time}s)"
  data=$(json_payload "$best_name")
  curl -s -X PUT "$API_BASE/proxies/$group_enc" -H 'Content-Type: application/json' "${AUTH_HDR[@]}" --data "$data" >/dev/null || true
  echo "Applied selection to group: $GROUP_LABEL"
else
  echo "No working node found for $URL via proxy in tested set ($limit)."
  echo "Tip: try direct access (bypass proxy):"
  echo "  curl --noproxy '*' -I --connect-timeout 6 --max-time 10 '$URL'"
fi

exit 0
