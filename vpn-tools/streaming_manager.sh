#!/bin/bash

# DESCRIPTION:
#   Interactive manager for streaming related groups (e.g. YOUTUBE / STREAM / MEDIA).
#   Allows listing candidate nodes, quick latency probing (YouTube pixel), applying
#   selection, and performing a short verification test.
#
# USAGE:
#   ./streaming_manager.sh
#   GROUP=YOUTUBE ./streaming_manager.sh
#
set -euo pipefail
API=${CLASH_API:-http://127.0.0.1:9090}
GROUP=${GROUP:-YOUTUBE}
PIXEL=https://i.ytimg.com/generate_204

have() { command -v "$1" >/dev/null 2>&1; }
err(){ echo "[ERROR] $*" >&2; }

if ! curl -fsS "$API/version" >/dev/null 2>&1; then err "Controller unreachable at $API"; exit 1; fi

group_json=$(curl -fsS "$API/proxies/$GROUP" || true)
if [[ -z $group_json ]]; then err "Group $GROUP not found"; exit 2; fi

nodes=()
if have jq; then mapfile -t nodes < <(echo "$group_json" | jq -r '.all[]'); else nodes=($(echo "$group_json" | sed -n 's/.*"all":\[\(.*\)\].*/\1/p' | tr '"' '\n' | sed '/^$/d')); fi

current=$(echo "$group_json" | (have jq && jq -r '.now' || sed -n 's/.*"now":"\([^"]*\)".*/\1/p'))

switch() { curl -s -X PUT "$API/proxies/$GROUP" -H 'Content-Type: application/json' -d '{"name":"'"$1"'"}' >/dev/null; }
probe() { # node
	switch "$1"; sleep 1
	local out http t
	out=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout 5 --max-time 7 "$PIXEL" 2>/dev/null || echo "000,9.999")
	http=${out%%,*}; t=${out##*,}
	printf "%s,%s,%s\n" "$1" "$http" "$t"
}

verify() {
	echo "Verification:"
	curl -s -o /dev/null -w '  YouTube home % {http_code} in %{time_total}s\n' --connect-timeout 6 --max-time 10 https://www.youtube.com/ || true
}

while true; do
	clear
	echo "=== Streaming Manager ($GROUP) ==="
	echo "Current: $current"
	echo "Nodes: ${#nodes[@]}"; echo
	echo "1) List nodes"
	echo "2) Quick probe top 8"
	echo "3) Choose node"
	echo "4) Verify current"
	echo "Q) Quit"
	read -rp "Select: " ans
	case ${ans,,} in
		1)
			i=1; for n in "${nodes[@]}"; do printf "%2d) %s\n" $i "$n"; ((i++)); done; read -rp "Enter to continue" _;;
		2)
			echo "Node,HTTP,Time"; for n in "${nodes[@]:0:8}"; do probe "$n"; done | sort -t, -k2,2 -k3,3n; read -rp "Enter to continue" _;;
		3)
			read -rp "Enter node (exact match or number): " pick
			if [[ $pick =~ ^[0-9]+$ ]] && (( pick>=1 && pick<=${#nodes[@]} )); then sel=${nodes[pick-1]}; else sel="$pick"; fi
			if printf '%s\n' "${nodes[@]}" | grep -Fxq "$sel"; then switch "$sel"; current="$sel"; echo "Applied: $sel"; verify; else echo "Not found"; fi; read -rp "Enter" _;;
		4) verify; read -rp "Enter" _;;
		q) break;;
		*) ;;
	esac
done

