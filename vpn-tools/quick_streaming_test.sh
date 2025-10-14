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
TIMEOUT=${TIMEOUT:-6}
PROXY=${PROXY:-http://127.0.0.1:7890}
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
. "$SCRIPT_DIR/lib/net_helpers.sh" 2>/dev/null || true
nh_init_symbols
test_curl() { nh_curl_t "$1" "$PROXY" "$TIMEOUT"; }

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
	if [[ $code =~ ^[23][0-9][0-9]$ ]]; then status="$NH_OK"; ((score++)); else status="$NH_FAIL"; fi
	res[$k]="$status($code,$t)"
	[[ $MODE == text ]] && printf "%-10s %s\n" "$k" "${res[$k]}"
done

percent=$(nh_percent "$score" "$max")
if [[ $MODE == text ]]; then
	echo "-----------------------"
	echo "Score $score/$max (${percent}%)"
	if (( percent>=75 )); then echo "Status: $NH_READY"; elif (( percent>=50 )); then echo "Status: $NH_PARTIAL"; else echo "Status: $NH_ISSUE"; fi
else
	# JSON 输出
	printf '{\n'
	printf '  "score": %s, "max": %s, "percent": %s,\n' "$score" "$max" "$percent"
	printf '  "results": {\n'
	first=1
	for k in youtube yt_pixel netflix dash; do
		v=${res[$k]}
		if [[ $first -eq 0 ]]; then printf ',\n'; fi
		printf '    "%s": "%s"' "$k" "$v"
		first=0
	done
	printf '\n  }\n}\n'
fi

