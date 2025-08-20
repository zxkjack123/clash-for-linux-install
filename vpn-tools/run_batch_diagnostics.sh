#!/bin/bash
# Batch Diagnostics Orchestrator
#
# Runs a curated set of quick (fast) and full (deeper) diagnostic scripts,
# captures their outputs (text + optional JSON/MD where supported), and
# assembles a unified Markdown summary report with timestamps and key metrics.
#
# Usage:
#   ./run_batch_diagnostics.sh [--quick] [--full] [--out report.md] [--ai-limit N]
#                               [--skip-heavy] [--keep-tmp]
#
# Defaults: run both quick + full tiers (skips very heavy multi‑minute AI unless specified).
#
set -euo pipefail

QUICK=0
FULL=0
OUT="batch_diagnostics_$(date '+%Y%m%d_%H%M%S').md"
AI_LIMIT=10
SKIP_HEAVY=0
KEEP_TMP=0
SUMMARY_ONLY=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--quick) QUICK=1; shift;;
		--full) FULL=1; shift;;
		--out) OUT="$2"; shift 2;;
		--ai-limit) AI_LIMIT="$2"; shift 2;;
		--skip-heavy) SKIP_HEAVY=1; shift;;
		--keep-tmp) KEEP_TMP=1; shift;;
		--summary-only) SUMMARY_ONLY=1; shift;;
		-h|--help)
			sed -n '1,80p' "$0"; exit 0;;
		*) echo "Unknown arg: $1" >&2; exit 2;;
	esac
done

[[ $QUICK -eq 0 && $FULL -eq 0 ]] && { QUICK=1; FULL=1; }

have() { command -v "$1" >/dev/null 2>&1; }

log(){ echo "[$(date '+%H:%M:%S')] $*" >&2; }

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

tmpdir=$(mktemp -d -t vpn-batch-XXXX)
trap '[[ $KEEP_TMP -eq 1 ]] || rm -rf "$tmpdir"' EXIT

section(){ echo; echo "## $1"; echo; }

collect_quick(){
	log "Running quick tier scripts"
	./show_vpn_status.sh > "$tmpdir/status.txt" 2>&1 || true
	./quick_vpn_check.sh > "$tmpdir/quick_vpn.txt" 2>&1 || true
	./quick_ai_test.sh > "$tmpdir/quick_ai.txt" 2>&1 || true
	./quick_streaming_test.sh > "$tmpdir/quick_stream.txt" 2>&1 || true
	./network_connectivity_test.sh quick > "$tmpdir/net_quick.txt" 2>&1 || true
}

collect_full(){
	log "Running full tier scripts"
	./network_connectivity_test.sh full > "$tmpdir/net_full.txt" 2>&1 || true
	./proxy_connectivity_report.sh > "$tmpdir/proxy_report.md" 2>&1 || true
	./test_ai_simple.sh --limit "$AI_LIMIT" > "$tmpdir/ai_simple.txt" 2>&1 || true
	./optimize_ai_enhanced.sh --limit "$AI_LIMIT" > "$tmpdir/ai_enhanced.txt" 2>&1 || true
	./optimize_youtube_streaming.sh > "$tmpdir/yt_opt.txt" 2>&1 || true
	# MinerU / OpenXLab specialized optimization (limit nodes for speed)
	if [[ -x ./optimize_mineru.sh ]]; then
		./optimize_mineru.sh --limit 5 > "$tmpdir/mineru_opt.txt" 2>&1 || true
	fi
	if [[ $SKIP_HEAVY -eq 0 ]]; then
		./test_ai_connectivity.sh --limit "$AI_LIMIT" --rounds 3 --json "$tmpdir/ai_conn.json" --md "$tmpdir/ai_conn.md" > "$tmpdir/ai_conn_console.txt" 2>&1 || true
	fi
}

dedup_stream(){ awk '!(NR>1 && $0==prev){print}{prev=$0}'; }
summarize_file(){ local label="$1" path="$2"; [[ -s $path ]] || return 0; echo "### $label"; echo; echo '```'; sed -e '1,120p' "$path" | dedup_stream; echo '```'; echo; }

build_report(){
	{
		echo "# Batch VPN Diagnostics Report"
		echo
		echo "Generated: $(date '+%F %T')"
		echo "Mode: $( [[ $QUICK -eq 1 ]] && echo quick ) $( [[ $FULL -eq 1 ]] && echo full )" | xargs
		echo "AI Node Limit: $AI_LIMIT  Heavy Suite: $( [[ $SKIP_HEAVY -eq 1 ]] && echo skipped || echo included )"
		echo
		section "Summary Highlights"
		controller_line=$(grep -E 'Controller:' "$tmpdir/status.txt" 2>/dev/null | head -n1 || true)
		exit_ip_line=$(grep -E 'Exit IP:' "$tmpdir/status.txt" 2>/dev/null | head -n1 || true)
		ai_best_enh=$(grep -E '^Best node:' "$tmpdir/ai_enhanced.txt" 2>/dev/null | head -n1 || true)
		ai_best_conn=$(grep -E '^Best node:' "$tmpdir/ai_conn_console.txt" 2>/dev/null | head -n1 || true)
		yt_best=$(grep -E '^Best node:' "$tmpdir/yt_opt.txt" 2>/dev/null | head -n1 || true)
		mineru_best=$(grep -E '^[最佳节][佳点]节点:' "$tmpdir/mineru_opt.txt" 2>/dev/null | head -n1 || true)
		quick_ai_sample=$(grep -E 'Score|success' "$tmpdir/quick_ai.txt" 2>/dev/null | head -n2 || true)
		echo '| Item | Value |'
		echo '|------|-------|'
		[[ -n $controller_line ]] && printf '| Controller | %s |\n' "$controller_line"
		[[ -n $exit_ip_line ]] && printf '| Exit IP | %s |\n' "$exit_ip_line"
		[[ -n $ai_best_enh ]] && printf '| AI Enhanced | %s |\n' "$ai_best_enh"
		[[ -n $ai_best_conn ]] && printf '| AI Stability | %s |\n' "$ai_best_conn"
		[[ -n $yt_best ]] && printf '| YouTube Opt | %s |\n' "$yt_best"
		[[ -n $mineru_best ]] && printf '| MinerU Opt | %s |\n' "$mineru_best"
		[[ -n $quick_ai_sample ]] && printf '| Quick AI | %s |\n' "${quick_ai_sample}" | head -n1
		echo
		[[ -s $tmpdir/proxy_report.md ]] && { echo "### Proxy Connectivity Table"; echo; sed -n '1,80p' "$tmpdir/proxy_report.md"; echo; }
			if [[ $SUMMARY_ONLY -eq 0 ]]; then
				section "Raw Outputs"
			fi
		[[ $SUMMARY_ONLY -eq 0 && $QUICK -eq 1 ]] && {
			summarize_file "Status" "$tmpdir/status.txt"
			summarize_file "Quick VPN" "$tmpdir/quick_vpn.txt"
			summarize_file "Quick AI" "$tmpdir/quick_ai.txt"
			summarize_file "Quick Streaming" "$tmpdir/quick_stream.txt"
			summarize_file "Network Quick" "$tmpdir/net_quick.txt"
		}
		[[ $SUMMARY_ONLY -eq 0 && $FULL -eq 1 ]] && {
			summarize_file "Network Full" "$tmpdir/net_full.txt"
			summarize_file "AI Simple" "$tmpdir/ai_simple.txt"
			summarize_file "AI Enhanced" "$tmpdir/ai_enhanced.txt"
			summarize_file "YouTube Optimization" "$tmpdir/yt_opt.txt"
			if [[ -s $tmpdir/ai_conn.md ]]; then
				echo "### AI Connectivity Stability (Markdown)"; echo; sed -n '1,100p' "$tmpdir/ai_conn.md"; echo
			fi
		}
	} > "$OUT"
	log "Report written: $OUT"
	[[ $KEEP_TMP -eq 1 ]] && log "Temp data in $tmpdir"
}

set +e  # prevent grep/curl transient errors from aborting entire batch
[[ $QUICK -eq 1 ]] && collect_quick || true
[[ $FULL -eq 1 ]] && collect_full || true
set -e
build_report

echo "$OUT"
exit 0
