#!/bin/bash

# DESCRIPTION:
#   30-second AI accessibility smoke test for current AI group route. Verifies
#   connectivity to ChatGPT web, Braintrust.dev, GitHub (web+API) and GitHub Copilot service root
#   (OpenAI / Claude removed per request). Certain endpoints (Copilot) may return 401/403/404
#   without auth; these are still considered reachable.
#
# USAGE:
#   ./quick_ai_test.sh
#   ./quick_ai_test.sh json
#
set -uo pipefail  # no -e so partial failures don't abort early
MODE=${1:-text}
PROXY=${PROXY:-http://127.0.0.1:7890}
TIMEOUT=${TIMEOUT:-6}
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
. "$SCRIPT_DIR/lib/net_helpers.sh" 2>/dev/null || true
nh_init_symbols
test() {
	local url="$1" mode="${2:-proxy}"
	if [[ "$mode" == direct ]]; then
		nh_curl_t "$url" "" "$TIMEOUT"
	else
		nh_curl_t "$url" "$PROXY" "$TIMEOUT"
	fi
}
declare -A targets=(
	[chatgpt]="https://chat.openai.com/"
	[braintrust]="https://www.braintrust.dev/"
	[github_web]="https://github.com/"
	[github_api]="https://api.github.com/"
	[copilot_edge]="https://api.githubcopilot.com/"
	[scnet]="https://api.scnet.cn/api/llm/v1/chat/completions"
	[uiui_api]="https://api.uiuihao.com/"
	[siliconflow]="https://siliconflow.cn/"
	[openrouter]="https://openrouter.ai/api/v1"
)

order=(chatgpt braintrust github_web github_api copilot_edge scnet uiui_api siliconflow openrouter)

declare -A target_proxy=(
	[siliconflow]=direct
)

# Allowed HTTP status patterns per target (regex). Default: 2xx/3xx
declare -A allow_codes=(
	[default]='^[23][0-9][0-9]$'
	[copilot_edge]='^([23][0-9][0-9]|401|403|404)$'
	[scnet]='^([23][0-9][0-9]|401|403|405)$'
	[uiui_api]='^([23][0-9][0-9]|301|302|403)$'
	[siliconflow]='^([23][0-9][0-9]|401|403)$'
	[openrouter]='^([23][0-9][0-9]|401|403)$'
)
declare -A res
score=0; max=${#order[@]}
for k in "${order[@]}"; do
	mode=${target_proxy[$k]:-proxy}
	out=$(test "${targets[$k]}" "$mode") || true
	code=${out%%,*}; t=${out##*,}; status=FAIL
	pattern=${allow_codes[$k]:-${allow_codes[default]}}
	if [[ $code =~ $pattern ]]; then status="$NH_OK"; ((score++)); else status="$NH_FAIL"; fi
	res[$k]="$status($code,$t)"
	[[ $MODE == text ]] && printf "%-12s %s\n" "$k" "${res[$k]}"
done
percent=$(nh_percent "$score" "$max")
if [[ $MODE == text ]]; then
	echo "------------------------"
	echo "Score $score/$max (${percent}%)"
	if (( percent>=75 )); then echo "Status: $NH_READY"; status_exit=0; elif (( percent>=50 )); then echo "Status: $NH_PARTIAL"; status_exit=1; else echo "Status: $NH_ISSUE"; status_exit=2; fi
else
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
fi
exit ${status_exit:-0}

