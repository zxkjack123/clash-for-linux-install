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
TIMEOUT=6
test() { curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+2))" --proxy "$PROXY" "$1" 2>/dev/null || echo "000,$TIMEOUT"; }
declare -A targets=(
	[chatgpt]="https://chat.openai.com/"
	[braintrust]="https://www.braintrust.dev/"
	[github_web]="https://github.com/"
	[github_api]="https://api.github.com/"
	[copilot_edge]="https://api.githubcopilot.com/"
)

# Allowed HTTP status patterns per target (regex). Default: 2xx/3xx
declare -A allow_codes=(
	[default]='^[23][0-9][0-9]$'
	[copilot_edge]='^([23][0-9][0-9]|401|403|404)$'
)
declare -A res
score=0; max=5
for k in chatgpt braintrust github_web github_api copilot_edge; do
	out=$(test "${targets[$k]}") || true
	code=${out%%,*}; t=${out##*,}; status=FAIL
	pattern=${allow_codes[$k]:-${allow_codes[default]}}
	if [[ $code =~ $pattern ]]; then status=OK; ((score++)); fi
	res[$k]="$status($code,$t)"
	[[ $MODE == text ]] && printf "%-12s %s\n" "$k" "${res[$k]}"
done
percent=$((score*100/max))
if [[ $MODE == text ]]; then
	echo "------------------------"
	echo "Score $score/$max (${percent}%)"
	if (( percent>=75 )); then echo "Status: ✅ READY"; status_exit=0; elif (( percent>=50 )); then echo "Status: ⚠️ PARTIAL"; status_exit=1; else echo "Status: ❌ ISSUE"; status_exit=2; fi
else
	printf '{\n'
	printf '  "score": %s, "max": %s, "percent": %s,\n' "$score" "$max" "$percent"
	printf '  "results": {\n'
	first=1
	for k in chatgpt braintrust github_web github_api copilot_edge; do
		v=${res[$k]}
		if [[ $first -eq 0 ]]; then printf ',\n'; fi
		printf '    "%s": "%s"' "$k" "$v"
		first=0
	done
	printf '\n  }\n}\n'
fi
exit ${status_exit:-0}

