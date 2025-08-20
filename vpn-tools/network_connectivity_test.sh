#!/bin/bash

# DESCRIPTION:
#   Comprehensive (full) or quick network + proxy connectivity assessment covering
#   DNS resolution, direct vs proxy reachability, latency distribution, and AI /
#   streaming endpoints. Outputs structured sections. Quick mode ~1m, full ~5-8m.
#
# USAGE:
#   ./network_connectivity_test.sh quick
#   ./network_connectivity_test.sh full
#   ./network_connectivity_test.sh           # default quick
#
set -euo pipefail
MODE=${1:-quick}
PROXY=${PROXY:-http://127.0.0.1:7890}
API=${CLASH_API:-http://127.0.0.1:9090}
TIMEOUT=6

have() { command -v "$1" >/dev/null 2>&1; }
curl_t() { curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+4))" "$@" 2>/dev/null || echo "000,$TIMEOUT"; }

section() { echo; printf '===== %s =====\n' "$1"; }

section "ENVIRONMENT"
echo "Timestamp : $(date '+%F %T')"
echo "Proxy     : $PROXY"
echo "Controller: $API (reachable=$([[ $(curl -fsS "$API/version" 2>/dev/null || echo fail) != fail ]] && echo yes || echo no))"

section "DNS BASELINE"
for host in api.openai.com claude.ai youtube.com netflix.com braintrust.dev; do
	ip=$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1; exit}')
	printf '%-18s %s\n' "$host" "${ip:-RESOLVE_FAIL}"
done

section "DIRECT VS PROXY REACHABILITY"
test_pair() { local url="$1" label="$2"; d=$(curl_t "$url"); p=$(curl_t --proxy "$PROXY" "$url"); printf '%-10s direct=%s proxy=%s\n' "$label" "$d" "$p"; }
for row in \
	"https://api.openai.com/v1/models openai" \
	"https://www.youtube.com/ youtube" \
	"https://www.netflix.com/ netflix" \
	"https://claude.ai/ claude" \
	"https://ipapi.co/json ipapi"; do
	test_pair ${row% *} ${row##* }
done

section "LATENCY SAMPLE (PROXY)"
targets=(https://www.google.com https://www.cloudflare.com https://www.bing.com)
for t in "${targets[@]}"; do
	out=$(curl_t --proxy "$PROXY" "$t"); code=${out%%,*}; tt=${out##*,}; printf '%-30s %s %ss\n' "$t" "$code" "$tt"; done

if [[ $MODE == full ]]; then
	section "EXTENDED AI / STREAMING"
	extended=(https://chat.openai.com/ https://i.ytimg.com/generate_204 https://dash.akamaized.net/envivio/EnvivioDash3/manifest.mpd https://www.braintrust.dev/ https://huggingface.co/)
	for u in "${extended[@]}"; do out=$(curl_t --proxy "$PROXY" "$u"); printf '%-55s %s %ss\n' "$u" "${out%%,*}" "${out##*,}"; done

	section "REPEATABILITY (OpenAI 5x via proxy)"
	for i in {1..5}; do out=$(curl_t --proxy "$PROXY" https://api.openai.com/v1/models); echo "Attempt $i: $out"; sleep 1; done
fi

section "SUMMARY"
echo "Mode     : $MODE"
echo "All done : $(date '+%T')"

