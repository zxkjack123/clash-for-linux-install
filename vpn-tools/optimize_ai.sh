#!/bin/bash

#!/bin/bash

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

# Controller address/secret (support hardened controller)
RUNTIME_FILE="${CLASH_CONFIG_RUNTIME:-$HOME/.local/share/clash/runtime.yaml}"
YQ_BIN="${BIN_YQ:-$HOME/.local/share/clash/bin/yq}"

API=${CLASH_API:-}
API_SECRET=""

if [[ -z "$API" ]] && [[ -x "$YQ_BIN" ]] && [[ -f "$RUNTIME_FILE" ]]; then
	ui_addr=$($YQ_BIN -r '."external-controller" // "127.0.0.1:9090"' "$RUNTIME_FILE" 2>/dev/null || echo '127.0.0.1:9090')
	ui_addr=$(printf '%s' "$ui_addr" | tr -d "\"'")
	# normalize to URL
	if echo "$ui_addr" | grep -q '://'; then
		API="$ui_addr"
	else
		API="http://${ui_addr}"
	fi
	API_SECRET=$($YQ_BIN -r '.secret // ""' "$RUNTIME_FILE" 2>/dev/null || echo '')
	API_SECRET=$(printf '%s' "$API_SECRET" | tr -d "\"'")
fi

API=${API:-http://127.0.0.1:9090}
AUTH_HDR=()
[[ -n "$API_SECRET" ]] && AUTH_HDR=(-H "Authorization: Bearer $API_SECRET")
PREF_GROUPS=("AI" "西瓜加速" "GLOBAL" "自动选择")
have() { command -v "$1" >/dev/null 2>&1; }

default_nodes=(
	"V1-美国01|流媒体|GPT"
	"V1-美国05|流媒体|GPT"
	"V1-美国10|流媒体|GPT"
	"V1-新加坡01|流媒体|GPT"
	"V1-日本01|流媒体|GPT"
)

echo "=== Quick AI Optimization ($(date '+%F %T')) ==="
if ! curl -fsS "${AUTH_HDR[@]}" "$API/version" >/dev/null 2>&1; then
	echo "Controller unreachable at $API" >&2; exit 1; fi

# Select a valid selector group
pick_group() {
	local plist json have_jq=0 g
	command -v jq >/dev/null 2>&1 && have_jq=1
	json=$(curl -fsS "${AUTH_HDR[@]}" "$API/proxies" 2>/dev/null || echo '{}')
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
group_json=$(curl -fsS "${AUTH_HDR[@]}" "$API/proxies/$GROUP" 2>/dev/null || true)
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
	filtered=(${available[@]:0:8})
fi

switch_node() { curl -s -X PUT "${AUTH_HDR[@]}" "$API/proxies/$GROUP" -H 'Content-Type: application/json' -d '{"name":"'"$1"'"}' >/dev/null; }

test_platform() {
	local url="$1" label="$2"; local out http t
	out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 6 --max-time 10 "$url" 2>/dev/null || echo "000,9.999")
	http=${out%%,*}; t=${out##*,}
	local pts=0
	if [[ $http =~ ^2|3 ]]; then
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
if [[ -n $best_node ]]; then
	switch_node "$best_node"; sleep 1
		now=$(curl -s "${AUTH_HDR[@]}" "$API/proxies/$GROUP" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p')
	echo "✅ Applied $GROUP group node: $now"
else
	echo "No suitable node found." >&2
fi

