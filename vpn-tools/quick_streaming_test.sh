#!/bin/bash

# DESCRIPTION:
#   30-second streaming capability smoke test. Checks YouTube, Netflix (homepage),
#   and a generic dash manifest request to evaluate basic reachability through the
#   current streaming group routing. Produces concise PASS/FAIL output.
#
# USAGE:
#   ./quick_streaming_test.sh
#   ./quick_streaming_test.sh json
#
set -euo pipefail
MODE=${1:-text}
TIMEOUT=6
PROXY=${PROXY:-http://127.0.0.1:7890}
test_curl() { curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+2))" --proxy "$PROXY" "$1" 2>/dev/null || echo "000,$TIMEOUT"; }

declare -A sites=(
	[youtube]="https://www.youtube.com/"
	[yt_pixel]="https://i.ytimg.com/generate_204"
	[netflix]="https://www.netflix.com/"
	[dash]="https://dash.akamaized.net/envivio/EnvivioDash3/manifest.mpd"
)

declare -A res
score=0; max=4
for k in "${!sites[@]}"; do
	out=$(test_curl "${sites[$k]}"); code=${out%%,*}; t=${out##*,}; status=FAIL
	if [[ $code =~ ^2|3 ]]; then status=OK; ((score++)); fi
	res[$k]="$status($code,$t)"
	[[ $MODE == text ]] && printf "%-10s %s\n" "$k" "${res[$k]}"
done

percent=$((score*100/max))
if [[ $MODE == text ]]; then
	echo "-----------------------"
	echo "Score $score/$max (${percent}%)"
	if (( percent>=75 )); then echo "Status: ✅ STREAMING READY"; elif (( percent>=50 )); then echo "Status: ⚠️ PARTIAL"; else echo "Status: ❌ ISSUE"; fi
else
	echo '{'
	echo '  "score":'"$score",'"max":'"$max",'"percent":'"$percent",'
	echo '  "results": {'
	first=1
	for k in youtube yt_pixel netflix dash; do
		v=${res[$k]}; [[ $first -eq 0 ]] && echo ','; printf '    "%s": "%s"' "$k" "$v"; first=0
	done
	echo '
	}
}'
fi

