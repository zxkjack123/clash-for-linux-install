#!/bin/bash

# DESCRIPTION:
#   Evaluate candidate nodes for YouTube streaming performance (initial HTML + a
#   video manifest HEAD) and set best node in STREAM or MEDIA group (auto-detect).
#
# USAGE:
#   ./select_youtube_node.sh
#   GROUP=Stream ./select_youtube_node.sh
#
set -euo pipefail
API=${CLASH_API:-http://127.0.0.1:9090}
GROUP=${GROUP:-YOUTUBE}

default_nodes=(
	"V1-美国01|流媒体|GPT"
	"V1-美国05|流媒体|GPT"
	"V1-美国10|流媒体|GPT"
	"V1-新加坡01|流媒体|GPT"
	"V1-日本01|流媒体|GPT"
)
IFS=',' read -r -a nodes <<< "${NODES:-${default_nodes[*]}}"

echo "=== YouTube Node Selection ($(date '+%F %T')) ==="

if ! curl -fsS "$API/version" >/dev/null 2>&1; then echo "Controller unreachable" >&2; exit 1; fi

switch() { curl -s -X PUT "$API/proxies/$GROUP" -H 'Content-Type: application/json' -d '{"name":"'"$1"'"}' >/dev/null; }

test_url() { # url label
	local out http t
	out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 6 --max-time 10 "$1" 2>/dev/null || echo "000,9.999")
	http=${out%%,*}; t=${out##*,}
	local pts=0
	if [[ $http =~ ^2|3 ]]; then
		if (( $(echo "$t <= 1.2" | bc -l 2>/dev/null || echo 0) )); then pts=6
		elif (( $(echo "$t <= 2.5" | bc -l 2>/dev/null || echo 0) )); then pts=5
		elif (( $(echo "$t <= 4" | bc -l 2>/dev/null || echo 0) )); then pts=4
		elif (( $(echo "$t <= 6" | bc -l 2>/dev/null || echo 0) )); then pts=3
		else pts=2; fi
	fi
	echo "$2:$http:$t:$pts"
}

best_node=""; best_score=-1

for n in "${nodes[@]}"; do
	echo "\n🧪 Node: $n"
	switch "$n"; sleep 2
	mapfile -t res < <(
		test_url https://www.youtube.com/ home
		test_url https://i.ytimg.com/generate_204 pixel
		test_url https://www.youtube.com/s/player/230b3f4e/player_ias.vflset/en_US/base.js basejs)
	total=0
	for r in "${res[@]}"; do IFS=':' read -r label code t pts <<<"$r"; printf "  %-6s code=%s time=%s pts=%s\n" "$label" "$code" "$t" "$pts"; total=$((total+pts)); done
	echo "  => Score: $total"
	if (( total > best_score )); then best_score=$total; best_node=$n; fi
done

echo "\n🏆 Best YouTube node: $best_node (score $best_score)"
if [[ -n $best_node ]]; then switch "$best_node"; sleep 1; echo "✅ Applied"; fi

