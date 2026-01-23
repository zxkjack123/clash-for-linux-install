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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load env (optional) and bootstrap controller/secret (env override -> legacy compat -> runtime.yaml -> default)
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true

clash_env_bootstrap 2>/dev/null || true

API=${CLASH_API:-http://127.0.0.1:9090}
PROXY=${PROXY:-http://127.0.0.1:7890}
GROUP=${GROUP:-}
TIMEOUT=${TIMEOUT:-6}
LIMIT=${LIMIT:-8}
APPLY=0

CURL_PROXY_OPTS=()
[[ -n "${PROXY:-}" ]] && CURL_PROXY_OPTS=(--proxy "$PROXY")

usage() {
	cat <<EOF
Full YouTube streaming optimization (preview by default).

Usage:
  $0 [--group NAME] [--limit N] [--timeout SEC] [--apply]

Notes:
  - By default, candidates are taken from the specified selector group (.all[]), limited by --limit.
  - This script temporarily switches nodes to probe; when --apply is NOT set, it restores the original node.
  - Controller auth/secret is auto-detected via vpn-tools/load_env.sh.

Env:
  CLASH_API, CLASH_SECRET, PROXY, GROUP, TIMEOUT, LIMIT, NODES
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--group) GROUP="$2"; shift 2;;
		--limit) LIMIT="$2"; shift 2;;
		--timeout) TIMEOUT="$2"; shift 2;;
		--apply) APPLY=1; shift;;
		-h|--help) usage; exit 0;;
		*) echo "Unknown arg: $1" >&2; exit 1;;
	esac
done

if [[ -z "${GROUP:-}" ]] && declare -F clash_pick_selector_group >/dev/null 2>&1; then
	GROUP="$(clash_pick_selector_group "YOUTUBE" "YouTube" "Streaming" "STREAMING" "MEDIA" "流媒体" 2>/dev/null || true)"
fi
GROUP=${GROUP:-YOUTUBE}

if declare -F clash_api_get >/dev/null 2>&1; then
	clash_api_get /version >/dev/null 2>&1 || { echo "Controller unreachable at $API" >&2; exit 1; }
else
	curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "$API/version" >/dev/null 2>&1 || { echo "Controller unreachable at $API" >&2; exit 1; }
fi

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
if [[ -z "$group_json" ]]; then
	echo "Group not found: $GROUP" >&2
	exit 2
fi

nodes=()
if [[ -n "${NODES:-}" ]]; then
	IFS=',' read -r -a nodes <<< "$NODES"
else
	if command -v jq >/dev/null 2>&1; then
		mapfile -t nodes < <(printf '%s' "$group_json" | jq -r '.all[]' 2>/dev/null | head -n "$LIMIT")
	else
		mapfile -t nodes < <(printf '%s' "$group_json" | sed -n 's/.*"all":\[\(.*\)\].*/\1/p' | tr '"' '\n' | sed '/^$/d' | head -n "$LIMIT")
	fi
fi
if (( ${#nodes[@]} == 0 )); then
	echo "No candidate nodes found in group $GROUP" >&2
	exit 3
fi

original=""
if declare -F clash_group_now >/dev/null 2>&1; then
	original="$(clash_group_now "$GROUP" 2>/dev/null || true)"
fi
if [[ -z "${original:-}" ]]; then
	original=$(printf '%s' "$group_json" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p')
fi

switch() {
	local payload
	payload=$(printf '{"name":"%s"}' "$1")
	if declare -F clash_api_put_json >/dev/null 2>&1; then
		clash_api_put_json "/proxies/$group_enc" "$payload" >/dev/null 2>&1 || return 1
	else
		curl -s --noproxy '*' --connect-timeout 2 --max-time 4 -X PUT "$API/proxies/$group_enc" -H 'Content-Type: application/json' -d "$payload" >/dev/null || return 1
	fi
}
metric() { # url weight label
	local url="$1" weight="$2" label="$3" out http t s=0
	out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+4))" "${CURL_PROXY_OPTS[@]}" "$url" 2>/dev/null || echo "000,9.999")
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
		metric https://www.youtube.com/favicon.ico 2 favicon
		metric https://dash.akamaized.net/envivio/EnvivioDash3/manifest.mpd 1 manifest)
	total=0
	for r in "${res[@]}"; do IFS=':' read -r label code t s <<<"$r"; printf "  %-8s code=%s time=%s score=%s\n" "$label" "$code" "$t" "$s"; total=$((total+s)); done
	echo "  Stability pixel (3 repeats):"
	stab=0
	for i in {1..3}; do out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 4 --max-time 6 "${CURL_PROXY_OPTS[@]}" https://i.ytimg.com/generate_204 2>/dev/null || echo "000,9.999"); c=${out%%,*}; tt=${out##*,}; [[ $c =~ ^2|3 ]] && stab=$((stab+1)); printf "    #%d %s %ss\n" $i "$c" "$tt"; done
	echo "  => Node composite score: $total (+stab $stab)"
	total=$((total + stab))
	if (( total > best_score )); then best_score=$total; best_node=$n; fi
done

echo "\n🏆 Best node: $best_node (score $best_score)"

if [[ -z "$best_node" ]]; then
	echo "No suitable node found." >&2
	exit 1
fi

if (( APPLY == 1 )); then
	switch "$best_node" || true
	echo "✅ Applied to $GROUP"
else
	# Restore original selection
	if [[ -n "${original:-}" ]]; then
		switch "$original" >/dev/null 2>&1 || true
	fi
	echo "(preview) Would apply to $GROUP: $best_node"
fi

