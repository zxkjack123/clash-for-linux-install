#!/bin/bash

# DESCRIPTION:
#   Ultra-fast (<=30s) diagnostic to confirm Clash/Mihomo proxy + AI reachability.
#   Tests controller, local ports, outbound via proxy, a few AI/streaming endpoints,
#   and reports a concise PASS/FAIL summary with simple scoring.
#
# USAGE:
#   ./quick_vpn_check.sh
#   ./quick_vpn_check.sh json   # machine-readable JSON output
#
set -euo pipefail

API=${CLASH_API:-http://127.0.0.1:9090}
# Secret resolution order:
# 1. Explicit env CLASH_API_SECRET
# 2. resources/mixin.yaml secret: value
# 3. config.yaml secret: value
# If still empty, auth may be disabled – we'll probe both auth / no-auth.
API_SECRET="${CLASH_API_SECRET:-}"
if [[ -z $API_SECRET ]]; then
	for f in "$(dirname "$0")/../resources/mixin.yaml" "$(dirname "$0")/../resources/config.yaml" "$(dirname "$0")/../config.yaml"; do
		if [[ -z $API_SECRET && -f $f ]]; then
			s=$(grep -E '^secret:' "$f" 2>/dev/null | head -n1 | awk '{print $2}')
			[[ -n $s ]] && API_SECRET="$s"
		fi
	done
fi
PROXY_HOST=127.0.0.1
HTTP_PORT=7890
SOCKS_PORT=7891
MODE=${1:-text}
TIMEOUT=6

have() { command -v "$1" >/dev/null 2>&1; }
json_escape() { sed 's/\\/\\\\/g; s/"/\\"/g'; }
timed_curl() { curl -s -o /dev/null -w '%{http_code},%{time_total}' --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT+2))" "$@" 2>/dev/null || echo "000,$TIMEOUT"; }

declare -A RESULTS
# Scoring baseline components: controller + ports(2) + proxy_http + youtube + github_web + github_api + copilot_edge = 8
score=0; max_score=8

controller_status_details=""

test_step() {
	local key="$1" desc="$2"; shift 2
	local out http t status
	out=$(timed_curl "$@")
	http=${out%%,*}; t=${out##*,}
	status=FAIL
	# Accept 2xx/3xx codes explicitly (3 digits)
	if [[ $http =~ ^[23][0-9][0-9]$ ]]; then status=OK; ((++score)); fi
	RESULTS[$key]="$status($http,$t)"
	[[ $MODE == text ]] && printf "%-28s %s\n" "$desc" "$status ($http $t s)"
}

echo "=== Quick VPN Check ($(date '+%F %T')) ===" >&2
[[ -n $API_SECRET ]] && echo "(Detected controller secret)" >&2

# Controller (capture nuanced auth states)
ctrl_code=""; ctrl_code_nosecret=""; ctrl_latency=""; ctrl_latency_nosecret=""
if [[ -n $API_SECRET ]]; then
	ctrl_raw=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' -H "Authorization: Bearer $API_SECRET" "$API/version" 2>/dev/null || true)
	ctrl_code=${ctrl_raw%%,*}; ctrl_latency=${ctrl_raw##*,}
fi
if [[ -z $ctrl_code || $ctrl_code == 401 || $ctrl_code == 403 || -z $API_SECRET ]]; then
	# Try without secret
	ctrl_raw2=$(curl -s -o /dev/null -w '%{http_code},%{time_total}' "$API/version" 2>/dev/null || true)
	ctrl_code_nosecret=${ctrl_raw2%%,*}; ctrl_latency_nosecret=${ctrl_raw2##*,}
fi

controller_label="Controller"
if [[ $ctrl_code == 200 ]]; then
	RESULTS[controller]="OK(200,${ctrl_latency}s)"; ((++score))
elif [[ $ctrl_code_nosecret == 200 ]]; then
	# Auth not required
	RESULTS[controller]="OK(200,${ctrl_latency_nosecret}s)"; ((++score))
elif [[ $ctrl_code == 401 || $ctrl_code_nosecret == 401 || $ctrl_code == 403 || $ctrl_code_nosecret == 403 ]]; then
	# Auth required but unreachable without proper secret. Treat as reachable (no network issue) so score counts.
	RESULTS[controller]="AUTH(${ctrl_code:-${ctrl_code_nosecret}})"; ((++score))
	controller_label="Controller (auth)"
else
	# Network / other failure
	RESULTS[controller]="FAIL(${ctrl_code:-${ctrl_code_nosecret:-noresp}})"
fi
[[ $MODE == text ]] && printf "%-28s %s\n" "$controller_label" "${RESULTS[controller]}"

# Port reachability (TCP SYN)
for p in $HTTP_PORT $SOCKS_PORT; do
	# Skip SOCKS test if no dedicated socks-port configured (only mixed-port 7890 present)
	if [[ $p -eq $SOCKS_PORT ]]; then
		if ! ss -ltn | grep -q ":$SOCKS_PORT"; then
			RESULTS[port_$p]=SKIP
			# Adjust denominator since SOCKS not active
			((max_score--))
			[[ $MODE == text ]] && printf "%-28s %s\n" "Port $p" "SKIP (not configured)"
			continue
		fi
	fi
	if timeout 1 bash -c "</dev/tcp/$PROXY_HOST/$p" 2>/dev/null; then
		RESULTS[port_$p]=OK; ((++score))
	else RESULTS[port_$p]=FAIL; fi
	[[ $MODE == text ]] && printf "%-28s %s\n" "Port $p" "${RESULTS[port_$p]}"
done

test_step proxy_http "Proxy HTTP (httpbin)" --proxy http://$PROXY_HOST:$HTTP_PORT https://httpbin.org/ip

# AI endpoints (lightweight HEAD via -I still counts a GET sometimes; keep GET)
# (Removed OpenAI / Claude by request) Add GitHub & Copilot tests

# Streaming quick (YouTube base HTML)
test_step youtube "YouTube" --proxy http://$PROXY_HOST:$HTTP_PORT https://www.youtube.com/
test_step github_web "GitHub Web" --proxy http://$PROXY_HOST:$HTTP_PORT https://github.com/
test_step github_api "GitHub API" --proxy http://$PROXY_HOST:$HTTP_PORT https://api.github.com/
# Copilot root may return 401/403; accept 2xx/3xx/401/403/404 as reachable
out=$(timed_curl --proxy http://$PROXY_HOST:$HTTP_PORT https://api.githubcopilot.com/)
code=${out%%,*}; t=${out##*,}; status=FAIL
if [[ $code =~ ^([23][0-9][0-9]|401|403|404)$ ]]; then status=OK; ((++score)); fi
RESULTS[copilot_edge]="$status($code,$t)"
[[ $MODE == text ]] && printf "%-28s %s\n" "Copilot Edge" "${RESULTS[copilot_edge]}"

# Geo check (which exit IP)
geo_json=$(curl -s --proxy http://$PROXY_HOST:$HTTP_PORT https://ipapi.co/json 2>/dev/null || true)
country=$(echo "$geo_json" | sed -n 's/.*"country_name":"\([^"]*\)".*/\1/p')
ip=$(echo "$geo_json" | sed -n 's/.*"ip":"\([^"]*\)".*/\1/p')
[[ -n $ip ]] && RESULTS[geo]="$ip/$country" || RESULTS[geo]=unknown
[[ $MODE == text ]] && printf "%-28s %s\n" "Exit IP Country" "${RESULTS[geo]}"

SUMMARY=$((score*100/max_score))

if [[ $MODE == text ]]; then
	echo "---------------------------------------"
	echo "Score: $score/$max_score  (${SUMMARY}%)"
	if (( SUMMARY >= 75 )); then echo "Status: ✅ GOOD"; elif (( SUMMARY >= 50 )); then echo "Status: ⚠️ PARTIAL"; else echo "Status: ❌ PROBLEM"; fi
else
	# JSON output
	{
		echo '{'
		echo '  "timestamp": '"$(date +%s)",
		for k in controller port_$HTTP_PORT port_$SOCKS_PORT proxy_http youtube github_web github_api copilot_edge geo; do
			v=${RESULTS[$k]:-NA}; printf '  "%s": "%s",\n' "$k" "$v" | json_escape
		done
		echo '  "score": '"$score",'
		echo '  "max_score": '"$max_score",'
		echo '  "percent": '"$SUMMARY"
		echo '}'
	}
fi

