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

order=(youtube yt_pixel netflix dash)

declare -A res
score=0; max=${#order[@]}
for k in "${order[@]}"; do
	out=$(test_curl "${sites[$k]}"); code=${out%%,*}; t=${out##*,}; status=FAIL
	if [[ $code =~ ^[23][0-9][0-9]$ ]]; then status="$NH_OK"; ((++score)); else status="$NH_FAIL"; fi
	res[$k]="$status($code,$t)"
	[[ $MODE == text ]] && printf "%-10s %s\n" "$k" "${res[$k]}"
done

percent=$(nh_percent "$score" "$max")
if [[ $MODE == text ]]; then
	echo "-----------------------"
	echo "Score $score/$max (${percent}%)"
	if (( percent>=75 )); then echo "Status: $NH_READY"; status_exit=0; elif (( percent>=50 )); then echo "Status: $NH_PARTIAL"; status_exit=1; else echo "Status: $NH_ISSUE"; status_exit=2; fi
else
	# JSON 输出
	printf '{\n'
	printf '  "score": %s, "max": %s, "percent": %s,\n' "$score" "$max" "$percent"
	printf '  "results": {\n'
	first=1
	for k in "${order[@]}"; do
		v=${res[$k]}
		if [[ $first -eq 0 ]]; then printf ',\n'; fi
		if declare -F nh_json_escape_str >/dev/null 2>&1; then
			printf '    "%s": "%s"' "$k" "$(nh_json_escape_str "$v")"
		else
			printf '    "%s": "%s"' "$k" "$v"
		fi
		first=0
	done
	printf '\n  }\n}\n'
	if (( percent>=75 )); then status_exit=0; elif (( percent>=50 )); then status_exit=1; else status_exit=2; fi
fi

exit ${status_exit:-0}

