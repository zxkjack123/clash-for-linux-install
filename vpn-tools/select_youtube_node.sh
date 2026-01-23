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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load env (optional) and bootstrap controller/secret (env override -> legacy compat -> runtime.yaml -> default)
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true

clash_env_bootstrap 2>/dev/null || true

API=${CLASH_API:-http://127.0.0.1:9090}
PROXY=${PROXY:-http://127.0.0.1:7890}
GROUP=${GROUP:-}
LIMIT=${LIMIT:-8}
APPLY=0

CURL_PROXY_OPTS=()
[[ -n "${PROXY:-}" ]] && CURL_PROXY_OPTS=(--proxy "$PROXY")

usage(){
	cat <<EOF
Evaluate candidate nodes for YouTube reachability and latency (preview by default).

Usage:
  $0 [--group NAME] [--limit N] [--apply]

Notes:
  - By default, candidates are taken from the specified selector group (.all[]), limited by --limit.
  - This script temporarily switches nodes to probe; when --apply is NOT set, it restores the original node.

Env:
  CLASH_API, CLASH_SECRET, PROXY, GROUP, LIMIT, NODES
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

if [[ -z "${GROUP:-}" ]] && declare -F clash_pick_selector_group >/dev/null 2>&1; then
	GROUP="$(clash_pick_selector_group "YOUTUBE" "YouTube" "Streaming" "STREAMING" "MEDIA" "流媒体" 2>/dev/null || true)"
fi
GROUP=${GROUP:-YOUTUBE}

echo "=== YouTube Node Selection ($(date '+%F %T')) ==="

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

test_url() { # url label
	local out http t
	out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 6 --max-time 10 "${CURL_PROXY_OPTS[@]}" "$1" 2>/dev/null || echo "000,9.999")
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

if [[ -z "$best_node" ]]; then
	echo "No suitable node found." >&2
	exit 1
fi

if (( APPLY == 1 )); then
	switch "$best_node" || true
	sleep 1
	echo "✅ Applied"
else
	# Restore original selection
	if [[ -n "${original:-}" ]]; then
		switch "$original" >/dev/null 2>&1 || true
	fi
	echo "(preview) Would apply: $best_node"
fi

