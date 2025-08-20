#!/bin/bash

# DESCRIPTION:
#   Interactive tool to view and customize the AI proxy group, list candidate nodes,
#   test latency/connectivity quickly, and apply the selected node through Clash/Mihomo
#   external controller (assumed at 127.0.0.1:9090). Works safely (read-only except the
#   single PUT to change group). Provides fuzzy filtering.
#
# USAGE:
#   ./customize_ai_group.sh                # interactive menu
#   FILTER=美国 ./customize_ai_group.sh     # pre-filter nodes containing pattern
#   non-interactive example:
#     ./customize_ai_group.sh --set "V1-美国01|流媒体|GPT"
#
# REQUIREMENTS:
#   curl, jq (optional – pretty output), bash 4+
#
# EXIT CODES:
#   0 success / applied (or no change)
#   1 controller unreachable
#   2 invalid node name
#
set -euo pipefail

API="http://127.0.0.1:9090"
GROUP="AI"

have_jq() { command -v jq >/dev/null 2>&1; }
err() { echo "[ERROR] $*" >&2; }
info() { echo "[INFO] $*" >&2; }

check_controller() {
	if ! curl -fsS "$API/version" >/dev/null 2>&1; then
		err "Cannot reach Clash controller at $API (set CLASH_API?)"; exit 1; fi
}

get_group_json() { curl -fsS "$API/proxies/$GROUP"; }

list_nodes() {
	local filter="${FILTER:-}" json
	json=$(get_group_json)
	if have_jq; then
		if [[ -n $filter ]]; then
			echo "$json" | jq -r '.all[]' | grep -i -- "$filter" || true
		else
			echo "$json" | jq -r '.all[]'
		fi
	else
		# fallback parse
		echo "$json" | sed -n 's/.*"all":\[\(.*\)\].*/\1/p' | tr '"', ' ' ' ' | tr ',' '\n'
	fi
}

current_node() { get_group_json | ( have_jq && jq -r '.now' || sed -n 's/.*"now":"\([^"]*\)".*/\1/p'); }

apply_node() {
	local node="$1"
	if [[ -z $node ]]; then err "Empty node"; exit 2; fi
	curl -fsS -X PUT "$API/proxies/$GROUP" -H 'Content-Type: application/json' -d '{"name":"'
