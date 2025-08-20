#!/bin/bash

# DESCRIPTION:
#   Lightweight AI optimization: evaluates a shortlist of candidate nodes for the AI
#   group using latency + success to OpenAI/Claude endpoints, selects best node.
#   Faster (≈2-3 min) than full enhanced script.
#
# USAGE:
#   ./optimize_ai.sh
#   NODES="nodeA,nodeB" ./optimize_ai.sh   # custom candidate list
#
set -euo pipefail
API=${CLASH_API:-http://127.0.0.1:9090}
GROUP=AI
have() { command -v "$1" >/dev/null 2>&1; }

default_nodes=(
	"V1-美国01|流媒体|GPT"
	"V1-美国05|流媒体|GPT"
	"V1-美国10|流媒体|GPT"
	"V1-新加坡01|流媒体|GPT"
	"V1-日本01|流媒体|GPT"
)

IFS=',' read -r -a candidates <<< "${NODES:-${default_nodes[*]}}"

echo "=== Quick AI Optimization ($(date '+%F %T')) ==="
if ! curl -fsS "$API/version" >/dev/null 2>&1; then
	echo "Controller unreachable at $API" >&2; exit 1; fi

switch_node() { curl -s -X PUT "$API/proxies/$GROUP" -H 'Content-Type: application/json' -d '{"name":"'"$1"'"}' >/dev/null; }

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

for node in "${candidates[@]}"; do
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
	now=$(curl -s "$API/proxies/$GROUP" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p')
	echo "✅ Applied AI group node: $now"
else
	echo "No suitable node found." >&2
fi

