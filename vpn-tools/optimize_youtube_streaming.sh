#!/bin/bash

# DESCRIPTION:
#   Full streaming optimization focused on YouTube: tests candidate nodes with a
#   wider suite (home page, pixel, base.js, manifest) plus stability (repeat pixel
#   probe). Chooses best composite scoring node and applies to YOUTUBE group.
#
# USAGE:
#   ./optimize_youtube_streaming.sh
#   NODES="n1,n2" ./optimize_youtube_streaming.sh
#
set -euo pipefail
API=${CLASH_API:-http://127.0.0.1:9090}
GROUP=${GROUP:-YOUTUBE}
TIMEOUT=6
default_nodes=("V1-美国01|流媒体|GPT" "V1-美国05|流媒体|GPT" "V1-美国10|流媒体|GPT" "V1-新加坡01|流媒体|GPT" "V1-日本01|流媒体|GPT")
IFS=',' read -r -a nodes <<< "${NODES:-${default_nodes[*]}}"

if ! curl -fsS "$API/version" >/dev/null 2>&1; then echo "Controller unreachable" >&2; exit 1; fi

switch() { curl -s -X PUT "$API/proxies/$GROUP" -H 'Content-Type: application/json' -d '{"name":"'"$1"'"}' >/dev/null; }
metric() { # url weight label
	local url="$1" weight="$2" label="$3" out http t s=0
	out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+4))" "$url" 2>/dev/null || echo "000,9.999")
	http=${out%%,*}; t=${out##*,}
	if [[ $http =~ ^2|3 ]]; then
		if (( $(echo "$t <= 1.5" | bc -l 2>/dev/null || echo 0) )); then s=$((5*weight))
		elif (( $(echo "$t <= 3" | bc -l 2>/dev/null || echo 0) )); then s=$((4*weight))
		elif (( $(echo "$t <= 5" | bc -l 2>/dev/null || echo 0) )); then s=$((3*weight))
		elif (( $(echo "$t <= 7" | bc -l 2>/dev/null || echo 0) )); then s=$((2*weight))
		else s=$((1*weight)); fi
	fi
	printf '%s:%s:%s:%s\n' "$label" "$http" "$t" "$s"
}

best_node=""; best_score=-1
echo "=== YouTube Streaming Optimization ($(date '+%F %T')) ==="

for n in "${nodes[@]}"; do
	echo "\n🧪 Node: $n"; switch "$n"; sleep 2
	mapfile -t res < <(
		metric https://www.youtube.com/ 3 home
		metric https://i.ytimg.com/generate_204 2 pixel
		metric https://www.youtube.com/s/player/230b3f4e/player_ias.vflset/en_US/base.js 2 basejs
		metric https://dash.akamaized.net/envivio/EnvivioDash3/manifest.mpd 1 manifest)
	total=0
	for r in "${res[@]}"; do IFS=':' read -r label code t s <<<"$r"; printf "  %-8s code=%s time=%s score=%s\n" "$label" "$code" "$t" "$s"; total=$((total+s)); done
	echo "  Stability pixel (3 repeats):"
	stab=0
	for i in {1..3}; do out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 4 --max-time 6 https://i.ytimg.com/generate_204 2>/dev/null || echo "000,9.999"); c=${out%%,*}; tt=${out##*,}; [[ $c =~ ^2|3 ]] && stab=$((stab+1)); printf "    #%d %s %ss\n" $i "$c" "$tt"; done
	echo "  => Node composite score: $total (+stab $stab)"
	total=$((total + stab))
	if (( total > best_score )); then best_score=$total; best_node=$n; fi
done

echo "\n🏆 Best node: $best_node (score $best_score)"
if [[ -n $best_node ]]; then switch "$best_node"; echo "✅ Applied to $GROUP"; fi

