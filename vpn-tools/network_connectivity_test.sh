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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load env (optional) and bootstrap controller/secret (env override -> legacy compat -> runtime.yaml -> default)
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/load_env.sh" 2>/dev/null || true

API="${CLASH_API:-http://127.0.0.1:9090}"
SECRET="${CLASH_SECRET:-}"
AUTH_HDR=()
[[ -n "$SECRET" ]] && AUTH_HDR=(-H "Authorization: Bearer $SECRET")
TIMEOUT=6

have() { command -v "$1" >/dev/null 2>&1; }
curl_t() { curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+4))" "$@" 2>/dev/null || echo "000,$TIMEOUT"; }
curl_t_direct() { curl_t --noproxy '*' "$@"; }
curl_t_proxy() { curl_t --proxy "$PROXY" "$@"; }

section() { echo; printf '===== %s =====\n' "$1"; }

section "ENVIRONMENT"
echo "Timestamp : $(date '+%F %T')"
echo "Proxy     : $PROXY"
echo "Controller: $API (reachable=$([[ $(curl -fsS --noproxy '*' --connect-timeout 2 --max-time 4 "${AUTH_HDR[@]}" "$API/version" 2>/dev/null || echo fail) != fail ]] && echo yes || echo no))"

section "DNS BASELINE"
for host in api.openai.com claude.ai youtube.com netflix.com braintrust.dev upwork.com; do
	ip=$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1; exit}')
	printf '%-18s %s\n' "$host" "${ip:-RESOLVE_FAIL}"
done

section "DIRECT VS PROXY REACHABILITY"
test_pair() { local url="$1" label="$2"; d=$(curl_t_direct "$url"); p=$(curl_t_proxy "$url"); printf '%-10s direct=%s proxy=%s\n' "$label" "$d" "$p"; }
for row in \
	"https://api.openai.com/v1/models openai" \
	"https://www.youtube.com/ youtube" \
	"https://www.netflix.com/ netflix" \
	"https://claude.ai/ claude" \
	"https://ipapi.co/json ipapi" \
	"https://api.scnet.cn/api/llm/v1/chat/completions scnet-llm" \
	"http://c-1996151687735582721.qdai.scnet.cn:58043 scnet-mineru-api" \
	"http://c-1996024701209694210.szai.scnet.cn:58043 scnet-mineru-api-sz" \
	"http://c-2002916625925693441.szai.scnet.cn:58043 scnet-mineru-api-sz2" \
	"https://sg.uiuiapi.com/ uiui" \
	"https://siliconflow.cn/ siliconflow" \
	"https://openrouter.ai/api/v1 openrouter" \
	"https://www.upwork.com/ upwork"; do
	test_pair ${row% *} ${row##* }
done

section "LATENCY SAMPLE (PROXY)"
targets=(https://www.google.com https://www.cloudflare.com https://www.bing.com)
for t in "${targets[@]}"; do
	out=$(curl_t_proxy "$t"); code=${out%%,*}; tt=${out##*,}; printf '%-30s %s %ss\n' "$t" "$code" "$tt"; done

if [[ $MODE == full ]]; then
	section "EXTENDED AI / STREAMING"
	extended=(https://chat.openai.com/ https://api.scnet.cn/api/llm/v1/chat/completions http://c-1996151687735582721.qdai.scnet.cn:58043 http://c-1996024701209694210.szai.scnet.cn:58043 http://c-2002916625925693441.szai.scnet.cn:58043 https://sg.uiuiapi.com/ https://siliconflow.cn/ https://openrouter.ai/api/v1 https://i.ytimg.com/generate_204 https://dash.akamaized.net/envivio/EnvivioDash3/manifest.mpd https://www.braintrust.dev/ https://huggingface.co/ https://www.upwork.com/)
	for u in "${extended[@]}"; do out=$(curl_t_proxy "$u"); printf '%-55s %s %ss\n' "$u" "${out%%,*}" "${out##*,}"; done

	section "REPEATABILITY (OpenAI 5x via proxy)"
	for i in {1..5}; do out=$(curl_t_proxy https://api.openai.com/v1/models); echo "Attempt $i: $out"; sleep 1; done
fi

section "SUMMARY"
echo "Mode     : $MODE"
echo "All done : $(date '+%T')"

