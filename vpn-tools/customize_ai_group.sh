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

# Optional env bootstrap (controller URL + secret)
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
if [[ -f "$SCRIPT_DIR/load_env.sh" ]]; then
	# shellcheck source=/dev/null
	source "$SCRIPT_DIR/load_env.sh" 2>/dev/null || true
fi

API="${CLASH_API:-http://127.0.0.1:9090}"
GROUP="AI"

AUTH_HDR=()
_hdr="$(clash_auth_header 2>/dev/null || true)"
[[ -n "${_hdr:-}" ]] && AUTH_HDR=(-H "${_hdr}")

urlencode() {
	local s="$1"
	if command -v python3 >/dev/null 2>&1; then
		python3 - "$s" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
	else
		printf '%s' "$s"
	fi
}

have_jq() { command -v jq >/dev/null 2>&1; }
err() { echo "[ERROR] $*" >&2; }
info() { echo "[INFO] $*" >&2; }

check_controller() {
	if ! curl -fsS --noproxy '*' --connect-timeout 2 --max-time 3 "${AUTH_HDR[@]}" "$API/version" >/dev/null 2>&1; then
		err "Cannot reach Clash controller at $API (set CLASH_API?)"; exit 1; fi
}

get_group_json() { curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "${AUTH_HDR[@]}" "$API/proxies/$GROUP"; }

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
	# Verify node is in list
	if ! list_nodes | grep -Fx -- "$node" >/dev/null 2>&1; then
		err "Node '$node' not in group list"; exit 2; fi
	if [[ $node == "$(current_node)" ]]; then
		info "Node '$node' already active (no change)"; return 0; fi
	if curl -fsS --noproxy '*' --connect-timeout 2 --max-time 6 -X PUT "${AUTH_HDR[@]}" "$API/proxies/$GROUP" -H 'Content-Type: application/json' -d '{"name":"'"$node"'"}' >/dev/null; then
		info "Applied node: $node"; return 0
	else
		err "Failed to apply node $node"; return 2
	fi

}


# Test latency via controller delay API (if supported)
test_latency() {
	local node="$1" timeout_ms="${LATENCY_TIMEOUT_MS:-3000}" url="${TEST_URL:-https://www.gstatic.com/generate_204}" r
	# Try delay endpoint; some forks require url & timeout params
	local node_enc
	node_enc="$(urlencode "$node")"
	r=$(curl -fsS --noproxy '*' --connect-timeout 2 --max-time $(( (timeout_ms/1000)+2 )) "${AUTH_HDR[@]}" "$API/proxies/$node_enc/delay?timeout=$timeout_ms&url=$url" 2>/dev/null || true)
	if [[ $r =~ ([0-9]{1,5})ms ]]; then
		printf '%s' "${BASH_REMATCH[1]}"
	else
		printf 'N/A'
	fi
}

print_menu() {
	local current="$(current_node)" filter="${FILTER:-}"; local i=0
	mapfile -t nodes < <(list_nodes)
	if [[ -n $filter ]]; then info "Filter: $filter (matched ${#nodes[@]})"; fi
	printf '\nCurrent: %s\n' "$current"
	printf 'Idx  %-50s  %6s\n' "Node" "RTT"
	printf '---- %-50s  %6s\n' "--------------------------------------------------" "------"
	for n in "${nodes[@]}"; do
		[[ -z $n ]] && continue
		lat=$(test_latency "$n")
		mark=" "; [[ $n == "$current" ]] && mark="*"
		printf '%3d%s %-50s %6s\n' "$i" "$mark" "$n" "$lat"
		((++i))
	done
	printf '\nActions: [number]=switch  r=refresh  f=filter  q=quit\n'
}

interactive_loop() {
	print_menu
	while true; do
		read -rp '> ' ans || break
		case $ans in
			q|quit) exit 0;;
			r) print_menu;;
			f) read -rp 'New filter: ' FILTER; print_menu;;
			'' ) continue;;
			*[!0-9]*) echo 'Enter index, r, f or q';;
			*)
				mapfile -t nodes < <(list_nodes)
				idx=$ans
				if (( idx<0 || idx>=${#nodes[@]} )); then echo 'Index out of range'; continue; fi
				sel=${nodes[$idx]}
				apply_node "$sel" && print_menu || true
			;;
		esac
	done
}

usage() {
	grep -E '^# ' "$0" | sed 's/^# \?//' | sed -n '1,60p'
}

main() {
	SET_NODE=""; SHOW_ONLY=0
	while [[ $# -gt 0 ]]; do
		case $1 in
			--set) SET_NODE="$2"; shift 2;;
			-h|--help) usage; exit 0;;
			*) echo "Unknown arg: $1" >&2; exit 1;;
		esac
	done
	check_controller
	if [[ -n $SET_NODE ]]; then
		# pattern support: pick first matching node (case-insensitive substring)
		cand=$(list_nodes | grep -i -- "$SET_NODE" | head -n1 || true)
		if [[ -z $cand ]]; then err "No node matches pattern: $SET_NODE"; exit 2; fi
		apply_node "$cand"
		return
	fi
	# interactive default
	interactive_loop
}

main "$@"
