#!/bin/bash

# DESCRIPTION:
#   Unified interactive launcher for vpn-tools scripts. Presents categorized menu,
#   performs basic dependency and controller checks, and executes chosen script.
#
# USAGE:
#   ./launcher.sh            # interactive menu
#   ./launcher.sh ai         # jump directly to AI submenu
#   ./launcher.sh run quick_vpn_check.sh   # run specific script with validation
#
set -euo pipefail
ROOT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
cd "$ROOT_DIR"

API="http://127.0.0.1:9090"
PORT_TEST_URL="https://www.google.com" # generic reachability

have() { command -v "$1" >/dev/null 2>&1; }
err() { echo "[ERROR] $*" >&2; }
info() { echo "[INFO] $*" >&2; }

check_basics() {
	for b in curl; do have "$b" || { err "Missing dependency: $b"; exit 1; }; done
	if ! curl -fsS "$API/version" >/dev/null 2>&1; then
		err "Clash controller not reachable at $API (start service?)"; return 0
	fi
}

scripts_ai=(optimize_ai.sh optimize_ai_enhanced.sh test_ai_connectivity.sh test_braintrust_connectivity.sh customize_ai_group.sh quick_ai_test.sh test_ai_nodes.sh test_ai_simple.sh)
scripts_stream=(select_youtube_node.sh optimize_youtube_streaming.sh streaming_manager.sh quick_streaming_test.sh)
scripts_net=(quick_vpn_check.sh network_connectivity_test.sh proxy_connectivity_report.sh show_vpn_status.sh test_docker_proxy.sh restart_clash_service.sh)
scripts_cn=(fix_openxlab_connectivity.sh quick_openxlab_access.sh test_chinese_ai_platforms.sh test_openxlab_direct_rules.sh)

run_script() {
	local s="$1"
	if [[ ! -x $s ]]; then err "Script $s missing or not executable"; exit 2; fi
	echo "---- Running $s ----"; echo
	"./$s" "$@" || err "$s exited with code $?"; echo
	read -rp "Press Enter to return to menu..." _ || true
}

print_header() {
	clear
	cat <<EOF
==============================
	VPN Tools Interactive Menu
==============================
Directory : $ROOT_DIR
Controller: $API
Date/Time : $(date '+%F %T')
EOF
	echo
}

menu_main() {
	while true; do
		print_header
		cat <<'M'
[1] 🤖 AI Optimization
[2] 🎬 Streaming Tools
[3] 🌐 Network & Proxy Tests
[4] 🇨🇳 Chinese AI / OpenXLab
[5] 📚 Show Help (show_help.sh list)
[R] 🔁 Refresh Status
[Q] ❌ Quit
M
		read -rp "Select option: " ans
		case ${ans,,} in
			1) menu_ai;;
			2) menu_stream;;
			3) menu_net;;
			4) menu_cn;;
			5) ./show_help.sh list | less -R; ;;
			r) check_basics;;
			q) exit 0;;
			*) echo "Invalid"; sleep 1;;
		esac
	done
}

submenu() {
	local title="$1"; shift
	local arr=("$@")
	while true; do
		clear
		echo "=== $title ==="; echo
		local i=1
		for s in "${arr[@]}"; do printf "%2d) %s\n" $i "$s"; ((i++)); done
		echo " Q) Back"
		read -rp "Select script: " sel
		case ${sel,,} in
			q) return;;
			*) if [[ $sel =~ ^[0-9]+$ ]] && (( sel>=1 && sel<=${#arr[@]} )); then run_script "${arr[sel-1]}"; else echo "Invalid"; sleep 1; fi;;
		esac
	done
}

menu_ai()    { submenu "AI Optimization" "${scripts_ai[@]}"; }
menu_stream(){ submenu "Streaming Tools" "${scripts_stream[@]}"; }
menu_net()   { submenu "Network & Proxy Tests" "${scripts_net[@]}"; }
menu_cn()    { submenu "Chinese / OpenXLab" "${scripts_cn[@]}"; }

if [[ ${1:-} == run ]]; then shift; run_script "$@"; exit 0; fi

case ${1:-} in
	ai) menu_ai;;
	streaming) menu_stream;;
	net|network) menu_net;;
	cn|china) menu_cn;;
	*) check_basics; menu_main;;
esac

