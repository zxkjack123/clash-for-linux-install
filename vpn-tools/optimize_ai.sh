#!/usr/bin/env bash

# DESCRIPTION:
#   Lightweight AI optimization: evaluates a shortlist of candidate nodes for an AI-like
#   selector group using latency + success to OpenAI/Claude endpoints, selects best node.
#   Auto-detects a valid selector group when 'AI' is missing (prefers: 西瓜加速, GLOBAL, 自动选择).
#   Faster (≈2-3 min) than full enhanced script.
#
# USAGE:
#   ./optimize_ai.sh
#   NODES="nodeA,nodeB" ./optimize_ai.sh   # custom candidate list

set -euo pipefail

# Load env (optional) and bootstrap controller/secret
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true

API="${CLASH_API:-http://127.0.0.1:9090}"
PROXY="${PROXY:-http://127.0.0.1:7890}"
APPLY=${APPLY:-0}
LIMIT=${LIMIT:-8}
PREF_GROUPS=("AI" "西瓜加速" "GLOBAL" "自动选择")
have() { command -v "$1" >/dev/null 2>&1; }

CURL_PROXY_OPTS=()
[[ -n "${PROXY:-}" ]] && CURL_PROXY_OPTS=(--proxy "$PROXY")

usage(){
	cat <<EOF
Quick AI Optimization (preview by default).

Usage:
  $0 [--group NAME] [--limit N] [--apply]

Notes:
  - Temporarily switches nodes during testing; when --apply is NOT set, restores the original node.
  - Controller auth/secret is auto-detected via vpn-tools/load_env.sh.

Env:
  CLASH_API, CLASH_SECRET, PROXY, GROUP, LIMIT, NODES, APPLY
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--group) GROUP="$2"; shift 2;;
		--limit) LIMIT="$2"; shift 2;;
		--apply) APPLY=1; shift;;
		-h|--help) usage; exit 0;;
		*) echo "Unknown arg: $1" >&2; exit 1;;
	esac
done

default_nodes=(
	"V1-美国01|流媒体|GPT"
	"V1-美国05|流媒体|GPT"
	"V1-美国10|流媒体|GPT"
	"V1-新加坡01|流媒体|GPT"
	"V1-日本01|流媒体|GPT"
)

echo "=== Quick AI Optimization ($(date '+%F %T')) ==="
if declare -F clash_api_get >/dev/null 2>&1; then
	clash_api_get /version >/dev/null 2>&1 || { echo "Controller unreachable at $API" >&2; exit 1; }
else
	curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "$API/version" >/dev/null 2>&1 || { echo "Controller unreachable at $API" >&2; exit 1; }
fi

# Select a valid selector group
pick_group() {
	local plist json have_jq=0 g
	command -v jq >/dev/null 2>&1 && have_jq=1
	if declare -F clash_api_get >/dev/null 2>&1; then
		json=$(clash_api_get /proxies 2>/dev/null || echo '{}')
	else
		json=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "$API/proxies" 2>/dev/null || echo '{}')
	fi
	if (( have_jq )); then
		for g in "${PREF_GROUPS[@]}"; do
			if echo "$json" | jq -e --arg k "$g" '.proxies[$k].type == "Selector"' >/dev/null 2>&1; then
				echo "$g"; return 0; fi
		done
		# fallback: first selector key
		echo "$json" | jq -r '.proxies | to_entries[] | select(.value.type=="Selector") | .key' | head -n1
	else
		# poor-man detection
		for g in "${PREF_GROUPS[@]}"; do
			echo "$json" | grep -q '"'"$g"'":{[^}]*"type":"Selector"' && { echo "$g"; return 0; }
		done
		echo "$json" | tr '\n' ' ' | sed 's/},/}\n/g' | grep '"type":"Selector"' | sed -n 's/.*"\([^"]\+\)":{.*"type":"Selector".*/\1/p' | head -n1
	fi
}

GROUP=${GROUP:-}
if [[ -z ${GROUP} ]]; then
	GROUP=$(pick_group)
fi
if [[ -z ${GROUP} ]]; then echo "No selector group found via API; abort." >&2; exit 1; fi
echo "Using group: $GROUP"

# Build candidates list
declare -a candidates
if [[ -n ${NODES:-} ]]; then
	IFS=',' read -r -a candidates <<< "$NODES"
else
	candidates=("${default_nodes[@]}")
fi

# Intersect candidates with group's available nodes
group_enc="$GROUP"
if declare -F clash_urlencode >/dev/null 2>&1; then
	group_enc="$(clash_urlencode "$GROUP")"
fi

group_json=""
if declare -F clash_api_get >/dev/null 2>&1; then
	group_json=$(clash_api_get "/proxies/$group_enc" 2>/dev/null || true)
else
	group_json=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "$API/proxies/$group_enc" 2>/dev/null || true)
fi
if [[ -z $group_json ]]; then echo "Cannot fetch group $GROUP" >&2; exit 1; fi
available=()
if have jq; then
	mapfile -t available < <(echo "$group_json" | jq -r '.all[]' 2>/dev/null)
else
	available=($(echo "$group_json" | sed -n 's/.*"all":\[\(.*\)\].*/\1/p' | tr '"' '\n' | sed '/^$/d'))
fi

# Filter candidates to those present in available; if none match, fall back to first 8 available
filtered=()
for n in "${candidates[@]}"; do
	printf '%s\n' "${available[@]}" | grep -Fxq "$n" && filtered+=("$n") || true
done
if (( ${#filtered[@]} == 0 )); then
	filtered=("${available[@]:0:$LIMIT}")
fi

original=""
if declare -F clash_group_now >/dev/null 2>&1; then
	original="$(clash_group_now "$GROUP" 2>/dev/null || true)"
fi
if [[ -z "${original:-}" ]]; then
	original=$(printf '%s' "$group_json" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p')
fi

switch_node() {
	local payload
	payload=$(printf '{"name":"%s"}' "$1")
	if declare -F clash_api_put_json >/dev/null 2>&1; then
		clash_api_put_json "/proxies/$group_enc" "$payload" >/dev/null 2>&1 || return 1
	else
		curl -s --noproxy '*' --connect-timeout 2 --max-time 4 -X PUT "$API/proxies/$group_enc" -H 'Content-Type: application/json' -d "$payload" >/dev/null || return 1
	fi
}

test_platform() {
	local url="$1" label="$2"; local out http t
	out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 6 --max-time 10 "${CURL_PROXY_OPTS[@]}" "$url" 2>/dev/null || echo "000,9.999")
	http=${out%%,*}; t=${out##*,}
	local pts=0
	if [[ $http =~ ^[23] ]] || [[ $http == "401" ]] || [[ $http == "403" ]]; then
		if (( $(echo "$t <= 2" | bc -l 2>/dev/null || echo 0) )); then pts=5
		elif (( $(echo "$t <= 4" | bc -l 2>/dev/null || echo 0) )); then pts=4
		elif (( $(echo "$t <= 6" | bc -l 2>/dev/null || echo 0) )); then pts=3
		else pts=2; fi
	else pts=0; fi
	printf "%s:%s:%s:%s\n" "$label" "$http" "$t" "$pts"
}

best_node=""; best_score=-1

for node in "${filtered[@]}"; do
	[[ -z "$node" ]] && continue
	echo "\n🧪 Testing node: $node"
	switch_node "$node"; sleep 2
	mapfile -t results < <(
		test_platform https://api.openai.com/v1/models openai 
		test_platform https://claude.ai/ claude 
		test_platform https://chat.openai.com/ chatgpt)
	total=0
	for r in "${results[@]}"; do IFS=':' read -r label code t pts <<<"$r"; printf "  %-7s code=%s time=%s pts=%s\n" "$label" "$code" "$t" "$pts"; total=$((total+pts)); done
	echo "  => Node score: $total"
	if (( total > best_score )); then best_score=$total; best_node=$node; fi
done

echo "\n🏆 Best node: $best_node (score $best_score)"
if [[ -z "$best_node" ]]; then
	echo "No suitable node found." >&2
	exit 1
fi

if (( APPLY == 1 )); then
	switch_node "$best_node"; sleep 1
	now=""
	if declare -F clash_group_now >/dev/null 2>&1; then
		now="$(clash_group_now "$GROUP" 2>/dev/null || true)"
	fi
	[[ -z "${now:-}" ]] && now="$best_node"
	echo "✅ Applied $GROUP group node: $now"
else
	# Restore original selection
	if [[ -n "${original:-}" ]]; then
		switch_node "$original" >/dev/null 2>&1 || true
	fi
	echo "(preview) Would apply $GROUP -> $best_node"
fi

